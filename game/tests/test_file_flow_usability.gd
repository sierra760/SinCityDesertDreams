# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
var host: GameHost
var cleanup_paths: Array[String] = []

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://file-flow-usability.cfg"
	root.add_child(host)

func after_each() -> void:
	await _wait_for_loading()
	host.free()
	for path in cleanup_paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cleanup_paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://file-flow-usability.cfg"))
	await process_frame

func _wait_for_loading() -> void:
	for frame in 40:
		if not host.loading_screen.visible: return
		RenderingServer.force_draw(false)
		await process_frame
	check(false,"loading completes")

# Guards against: Regenerate on untouched generated land asking to save it.
func test_regenerate_untouched_land_needs_no_prompt() -> void:
	var first := host.start_new_city({"name":"Fresh land","seed":4321})
	check_eq(host.stage,GameHost.Stage.EDITING)
	for frame in 3: await process_frame
	check(host.files.has_unsaved_changes(),"a never-saved map still counts as unsaved for New/Load/Quit")
	host.files.request_city_action(&"regenerate")
	check(not host.notice_dialog.is_open(),"untouched generated land regenerates without a prompt")
	await _wait_for_loading()
	check(host.sim.city != first,"new land replaced the old")
	check(not host.notice_dialog.is_open())
	# Regenerated land is again a fresh baseline.
	var second := host.sim.city
	host.files.request_city_action(&"regenerate")
	check(not host.notice_dialog.is_open(),"regenerated land is also untouched")
	await _wait_for_loading()
	check(host.sim.city != second)
	# A real edit brings the question back, with its reason.
	check(host.terrain_editor.raise(20,20).ok)
	host.files.request_city_action(&"regenerate")
	check(host.notice_dialog.is_open(),"edited land asks before regenerating")
	check(host.notice_dialog.body_label.text.contains("before generating new land"))
	host.escape()
	check(not host.notice_dialog.is_open())
	# Other actions keep their prompt for never-saved land, now naming the action.
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	check(host.notice_dialog.body_label.text.contains("before starting a new city"))
	check_eq((host.notice_dialog.choice_buttons[1] as Button).text,"Don't Save")
	host.escape()

# Guards against: accented and non-Latin save names being silently stripped.
func test_save_names_keep_international_letters() -> void:
	check_eq(SaveDialog.clean_name("Ciudad Juárez"),"Ciudad Juárez")
	check_eq(SaveDialog.clean_name("東京 2050"),"東京 2050")
	check_eq(SaveDialog.clean_name("Zürich-Ost (Neu)"),"Zürich-Ost (Neu)")
	check_eq(SaveDialog.clean_name("a/b\\c:d*e?f\"g<h>i|j"),"abcdefghij")
	check_eq(SaveDialog.clean_name("  ..Hidden town.  "),"Hidden town")
	check_eq(SaveDialog.clean_name("Tab\tName\u0007"),"TabName")
	check_eq(SaveDialog.clean_name("Round Trip: 2?"),"Round Trip 2")
	check_eq(SaveDialog.clean_name("Mesa.sc2d"),"Mesa")
	check_eq(SaveDialog.clean_name("CON"),"CON city")
	check_eq(SaveDialog.clean_name("lpt1.old"),"lpt1 city.old")
	check_eq(SaveDialog.clean_name("Console"),"Console","only exact device names are changed")
	check_eq(SaveDialog.clean_name("/:*?"),"")
	host.begin_city(flat_city(),{},11,null)
	var path := host.files.save_city_as("Café Ñandú")
	cleanup_paths.append(path)
	check_eq(path.get_file(),"Café Ñandú.sc2d")
	check(FileAccess.file_exists(path))
	check(SaveFormat.load(path).ok)

# Guards against: founding or regenerating resetting choices made while shaping.
func test_found_keeps_disaster_and_auto_budget_choices() -> void:
	host.start_new_city({"name":"Control","seed":777})
	check(host.found_city())
	var control_rng := host.sim.rng.state()
	host.start_new_city({"name":"Chosen","seed":777})
	host.sim.stats.disasters_enabled = false
	host.sim.stats.auto_budget = true
	host.regenerate(777)
	check(not host.sim.stats.disasters_enabled,"regenerate keeps Disasters off")
	check(host.sim.stats.auto_budget,"regenerate keeps Auto budget on")
	check(host.found_city())
	check(not host.sim.stats.disasters_enabled,"founding keeps Disasters off")
	check(host.sim.stats.auto_budget,"founding keeps Auto budget on")
	check_eq(host.sim.rng.state(),control_rng,"carried choices consume no random numbers")

# Guards against: the default "Mayor" credit shown as if it were a name.
func test_default_mayor_credit_is_omitted() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	dialog.open([{"name":"Plain","path":"user://saves/plain.sc2d","mayor":"Mayor","saved_at":1760000000},
		{"name":"Named","path":"user://saves/named.sc2d","mayor":"Ana","saved_at":1760000000}] as Array[Dictionary])
	check(not dialog.details_label.text.contains("Mayor:"),dialog.details_label.text)
	check(not dialog.details_label.text.contains("UTC"),"saved time is local, not UTC")
	dialog.select(1)
	check(dialog.details_label.text.contains("Mayor: Ana"))
	dialog.free()
	var plain := CityShare._success("user://x.sc2d","Plain","Mayor")
	check(not String(plain.message).contains("a city by"),plain.message)
	var named := CityShare._success("user://x.sc2d","Named","Ana")
	check(String(named.message).contains("a city by Ana"))

# Guards against: internal paths and codes in load errors.
func test_load_errors_name_the_file_in_plain_words() -> void:
	host.begin_city(flat_city(),{},5,null)
	var junk := "user://file-flow-junk.sc2d"
	var newer := "user://file-flow-newer.sc2d"
	cleanup_paths.append_array([junk,newer])
	var file := FileAccess.open(junk,FileAccess.WRITE)
	# Valid JSON (a malformed document logs an engine parse error), but not a city.
	file.store_string(JSON.stringify({"format":"spreadsheet","version":1}))
	file.close()
	file = FileAccess.open(newer,FileAccess.WRITE)
	file.store_string(JSON.stringify({"format":"sc2d","version":SaveFormat.VERSION+1,"stage":"play","city":{}}))
	file.close()
	check(not host.load_city(junk))
	check(host.notice_dialog.body_label.text.contains("file-flow-junk.sc2d"))
	check(host.notice_dialog.body_label.text.contains("isn't a Sin City - Desert Dreams city"))
	check(not host.notice_dialog.body_label.text.contains("user://"))
	host.notice_dialog.dismiss()
	check(not host.load_city(newer))
	check(host.notice_dialog.body_label.text.contains("newer version"))
	host.notice_dialog.dismiss()

# Guards against: a started New City reusing the last name/seed, and word seeds
# shown as their hash.
func test_new_city_entries_clear_after_start_only() -> void:
	var dialog := host.new_city_dialog
	host.open_new_city_dialog()
	dialog.name_edit.text = "Kept on cancel"
	dialog.seed_edit.text = "mesa"
	dialog.generate_preview()
	check(dialog.preview_label.text.contains("Seed mesa"),dialog.preview_label.text)
	dialog.close()
	host.open_new_city_dialog()
	check_eq(dialog.name_edit.text,"Kept on cancel")
	check_eq(dialog.seed_edit.text,"mesa")
	dialog.start()
	await _wait_for_loading()
	check_eq(host.sim.city.name,"Kept on cancel")
	check_eq(dialog.name_edit.text,"")
	check_eq(dialog.seed_edit.text,"")
	host.files.request_city_action(&"new")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss(&"discard")
	check(dialog.is_open())
	check(not dialog.name_edit.text.is_empty(),"a fresh name is rolled")
	check(not dialog.seed_edit.text.is_empty(),"a fresh seed is rolled")
	dialog.close()
