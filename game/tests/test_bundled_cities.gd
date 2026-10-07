# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const NAMES := ["Adaven", "Aliso Niguel", "Foothills Ranch", "Grant Pass - Soledad", "La Presa", "Lawndale", "Oro Canyon", "Salton Shores", "Valle del Mar"]
const CATALOG := "res://scripts/io/bundled_cities.gd"
const MAIN := preload("res://scenes/main.tscn")


func _entries() -> Array[Dictionary]:
	check(FileAccess.file_exists(CATALOG), "included-city catalog is available")
	if not FileAccess.file_exists(CATALOG): return []
	return load(CATALOG).entries()


func _supports_included(dialog: LoadDialog) -> bool:
	check(dialog.has_signal("bundled_city_requested"), "included rows have their own import routing")
	return dialog.has_signal("bundled_city_requested")


func _path(city_name: String) -> String:
	return "res://assets/cities/%s.sc2d" % city_name


func test_every_requested_city_is_a_loadable_native_save() -> void:
	var entries := _entries()
	check_eq(entries.size(), 9, "the eight supplied cities plus Adaven")
	for index in entries.size():
		check_eq(entries[index]["name"], NAMES[index])
		var path := _path(NAMES[index])
		check_eq(entries[index]["path"], path, "city opens without an external path")
		check(FileAccess.file_exists(path), "bundled file: " + NAMES[index])
		if not FileAccess.file_exists(path): continue
		var result := SaveFormat.load(path)
		check(bool(result["ok"]), "native load: " + NAMES[index])
		if not bool(result["ok"]): continue
		check_eq(String(result["stage"]), SaveFormat.STAGE_PLAY, "founded city: " + NAMES[index])
		var city: City = result["city"]
		check_eq(city.terrain.width, 128)
		check_eq(city.terrain.height, 128)
		check_eq(city.name, NAMES[index], "city carries its catalog name")
		var source := "res://assets/cities/%s.sc2" % NAMES[index]
		if not FileAccess.file_exists(source): continue
		# Converted classic cities keep the imported city's identity.
		var imported := Sc2Import.load(source)
		check(bool(imported["ok"]), "classic source still imports: " + NAMES[index])
		if not bool(imported["ok"]): continue
		var original: City = imported["city"]
		check_eq(city.funds, original.funds, "funds: " + NAMES[index])
		check_eq(city.day, original.day, "day: " + NAMES[index])
		check_eq(city.founded_year, original.founded_year, "founded: " + NAMES[index])
		check_eq(city.terrain.data, original.terrain.data, "terrain: " + NAMES[index])
		check_eq(city.altitude.data, original.altitude.data, "altitude: " + NAMES[index])


func test_provenance_records_every_shipped_save() -> void:
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/provenance.json"))
	check_eq(String(provenance.get("format", "")), "sc2d")
	var cities: Array = provenance.get("cities", [])
	check_eq(cities.size(), NAMES.size())
	for record: Dictionary in cities:
		var path := "res://assets/cities/" + String(record["file"])
		check(String(record["file"]).ends_with(".sc2d"), "native file: " + String(record["file"]))
		check_eq(FileAccess.get_sha256(path), String(record["sha256"]), "hash: " + String(record["file"]))
		check(NAMES.has(String(record["name"])), "listed city: " + String(record["name"]))


func test_same_name_personal_save_and_included_city_route_separately() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	if not _supports_included(dialog):
		dialog.free()
		return
	var entries := _entries()
	var saves: Array[Dictionary] = [{"name":"La Presa", "path":"user://saves/La Presa.sc2d", "year":2000, "population":1234, "date_text":"2026-10-05"}]
	var native_paths: Array[String] = []
	var bundled_paths: Array[String] = []
	dialog.load_requested.connect(func(path: String) -> void: native_paths.append(path))
	dialog.connect("bundled_city_requested", func(path: String) -> void: bundled_paths.append(path))
	dialog.call("open", saves, entries)
	check_eq(dialog.item_list.item_count, 10)
	dialog.select(0)
	dialog.confirm()
	check_eq(native_paths, ["user://saves/La Presa.sc2d"] as Array[String])
	check(bundled_paths.is_empty(), "personal save stays on native routing")
	for index in entries.size():
		dialog.call("open", saves, entries)
		dialog.select(index + 1)
		check(dialog.item_list.get_item_text(index + 1).contains("Included city"))
		check(dialog.details_label.text.contains("Included city"))
		check(not dialog.details_label.text.contains("Saved:"), "included source has no invented save date")
		dialog.confirm()
		check_eq(bundled_paths[-1], _path(NAMES[index]))
		check_eq(native_paths.size(), 1)
	check_eq(saves.size(), 1, "refresh does not append to the caller's personal-save list")
	dialog.free()
	await process_frame


func test_included_cities_work_without_personal_saves_and_refresh_clears_routing() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	if not _supports_included(dialog):
		dialog.free()
		return
	dialog.call("open", [] as Array[Dictionary], _entries())
	check_eq(dialog.item_list.item_count, 9)
	check(not dialog.empty_label.visible)
	check(not dialog.load_button.disabled)
	check_eq(dialog.selected_path(), _path("Adaven"))
	dialog.refresh([] as Array[Dictionary])
	check_eq(dialog.item_list.item_count, 0)
	check(dialog.empty_label.visible)
	check(dialog.load_button.disabled)
	check_eq(dialog.selected_path(), "")
	dialog.free()
	await process_frame


func test_main_picker_opens_every_included_city_as_new_paused_playable_city() -> void:
	var host: GameHost = MAIN.instantiate()
	host.preferences_path = "user://bundled-cities-test.cfg"
	root.add_child(host)
	if not _supports_included(host.load_dialog):
		host.free()
		await process_frame
		return
	for city_name: String in NAMES:
		host.files.open_load_dialog()
		var path := _path(city_name)
		var index := host.load_dialog.paths.find(path)
		check(index >= 0, "Main includes " + city_name)
		if index < 0: continue
		var imported := SaveFormat.load(path)
		check(bool(imported["ok"]), "Main source loads")
		if not bool(imported["ok"]): continue
		var expected: City = imported["city"]
		host.load_dialog.select(index)
		host.load_dialog.confirm()
		check(host.loading_screen.visible, "included selection draws loading feedback")
		for frame in 30:
			await process_frame
			if not host.loading_screen.visible: break
		check(not host.loading_screen.visible, "import finishes")
		check(host.in_game and host.stage == GameHost.Stage.PLAY)
		check_eq(host.sim.city.name, expected.name)
		check_eq(host.sim.city.funds, expected.funds)
		check_eq(host.sim.city.day, expected.day)
		check_eq(host.save_path, "", "saving uses a new native save")
		check_eq(host.sim.speed, GameClock.Speed.PAUSED)
		check_eq(host.sim.city.mayor, ViewPreferences.mayor_credit(host.preferences.get("mayor_name", "")), "credited to the player")
		check(host.files.has_unsaved_changes(), "a personal copy still needs saving")
		var saved_speed := int(imported["snapshot"].get("speed", GameClock.Speed.PAUSED))
		check_eq(host.speed_before_modal, saved_speed if saved_speed != GameClock.Speed.PAUSED else GameClock.Speed.SLOW, "resume speed")
		check_eq(host.modal_depth, 0)
		check(not host.is_input_blocked())
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bundled-cities-test.cfg"))
	await process_frame


func test_included_city_signs_are_drawn_when_labels_are_enabled() -> void:
	var host: GameHost = MAIN.instantiate()
	host.preferences_path = "user://bundled-city-signs-test.cfg"
	root.add_child(host)
	host.files.open_load_dialog()
	var index := host.load_dialog.paths.find(_path("La Presa"))
	check(index >= 0, "Main includes La Presa")
	if index >= 0:
		host.load_dialog.select(index)
		host.load_dialog.confirm()
		for frame in 30:
			await process_frame
			if not host.loading_screen.visible: break
		var signs: Dictionary = host.sim.city.signs
		check_eq(signs.size(), 9, "the classic city's player signs survive inclusion")
		check_eq(String(signs.get(Vector2i(10, 20), "")), "La Mesa Freeway")
		check(host.city_view_3d.labels_visible, "signs and labels default on")
		check_eq(host.city_view_3d._labels.get_child_count(), 9, "one aerial label per sign")
		host.city_view_3d.set_center_cell(Vector2i(10, 20))
		var label: Label = host.city_view_3d._label_nodes.get(Vector2i(10, 20))
		check(label != null and label.is_visible_in_tree(), "the centred sign's label is shown")
		if label != null:
			check_eq(label.text, "La Mesa Freeway")
			check(host.get_viewport().get_visible_rect().has_point(label.position), "the label is on screen")
		host.set_option(&"labels", false)
		check_eq(host.city_view_3d._labels.get_child_count(), 0, "turning labels off removes them")
		host.set_option(&"labels", true)
		check_eq(host.city_view_3d._labels.get_child_count(), 9, "turning labels on restores them")
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bundled-city-signs-test.cfg"))
	await process_frame


func test_included_city_can_be_saved_and_reloaded_as_native_city() -> void:
	if _entries().is_empty(): return
	var imported := SaveFormat.load(_path("La Presa"))
	check(bool(imported["ok"]))
	if not bool(imported["ok"]): return
	var city: City = imported["city"]
	var path := "user://bundled-native-roundtrip.sc2d"
	check_eq(SaveFormat.save(path, city, imported["snapshot"]), OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded["ok"]))
	if bool(loaded["ok"]):
		check_eq(SaveFormat.encode_city(loaded["city"]), SaveFormat.encode_city(city))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_every_platform_preset_includes_native_city_files_only() -> void:
	var config := ConfigFile.new()
	check_eq(config.load("res://export_presets.cfg"), OK)
	var platforms := 0
	for section: String in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"): continue
		platforms += 1
		var filters := String(config.get_value(section, "include_filter", "")).split(",")
		check(filters.has("assets/cities/provenance.json"), "%s retains included city provenance" % config.get_value(section, "name", section))
		check(filters.has("assets/cities/*.sc2d"), "%s ships native included cities" % config.get_value(section, "name", section))
		check(not filters.has("assets/cities/*.sc2"), "%s leaves classic sources out" % config.get_value(section, "name", section))
	check_eq(platforms, 6)
