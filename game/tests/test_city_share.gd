# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const ShareScriptPath := "res://scripts/io/city_share.gd"
var host: GameHost
var paths: Array[String] = []

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://test-share.cfg"
	root.add_child(host)
	var city := flat_city()
	city.name = "Share / City"
	city.mayor = "María"
	host.begin_city(city,{},7,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)

func after_each() -> void:
	for frame in 40:
		if not host.loading_screen.visible: break
		RenderingServer.force_draw(false)
		await process_frame
	host.free()
	for path: String in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-share.cfg"))
	await process_frame

func test_share_copy_keeps_manual_save_and_gameplay_identity() -> void:
	var manual := host.files.save_city_as("share-manual")
	paths.append(manual)
	var bytes := FileAccess.get_file_as_bytes(manual)
	host.sim.city.funds -= 200
	var before := host.files.save_content()
	var result: Dictionary = host.files.prepare_city_share("")
	check(result.get("ok",false))
	if not result.get("ok",false): return
	paths.append(result.path)
	check_ne(result.path,manual)
	check_eq(host.save_path,manual)
	check_eq(FileAccess.get_file_as_bytes(manual),bytes)
	check_eq(host.files.save_content(),before,"share preserves city, runtime, RNG, stage and parameters")
	check(host.files.has_unsaved_changes(),"sharing cannot masquerade as a manual save")
	var loaded := SaveFormat.load(result.path)
	check(loaded.ok)
	check_eq(SaveFormat.encode_city(loaded.city),SaveFormat.encode_city(host.sim.city))
	check_eq(loaded.snapshot,JSON.parse_string(JSON.stringify(host.sim.snapshot())),"snapshot matches the exact native wire representation")
	check_eq(loaded.city.mayor,"María")
	var second: Dictionary = host.files.prepare_city_share("")
	paths.append(second.path)
	check_ne(second.path,result.path,"another share never overwrites a file held by a share sheet")

func test_shaped_land_and_selected_save_retain_their_own_credit() -> void:
	host.session.begin_editing(host.sim.city,{"seed":7,"name":"Share / City"})
	var shaped: Dictionary = host.files.prepare_city_share("")
	check(shaped.ok)
	paths.append(shaped.path)
	var restored := SaveFormat.load(shaped.path)
	check_eq(restored.stage,SaveFormat.STAGE_EDITING)
	check_eq(restored.generator,JSON.parse_string(JSON.stringify(host.editing_params)))
	var previous := FileAccess.get_file_as_bytes(shaped.path)
	host.sim.city.mayor = "Different Mayor"
	var result: Dictionary = host.files.prepare_city_share(shaped.path)
	check(result.ok)
	paths.append(result.path)
	check_eq(FileAccess.get_file_as_bytes(result.path),previous,"selected saves share their exact saved bytes")
	check_eq(result.mayor,"María")

func test_invalid_selection_and_write_failure_do_not_share() -> void:
	check(ResourceLoader.exists(ShareScriptPath),"sharing validates files and handles preparation failure")
	if not ResourceLoader.exists(ShareScriptPath): return
	var sharing: Variant = load(ShareScriptPath)
	check(not sharing.call("copy_saved", "user://missing-share.sc2d").ok)
	var blocker := "user://share-blocker"
	paths.append(blocker)
	var file := FileAccess.open(blocker,FileAccess.WRITE)
	file.store_string("keep"); file.close()
	var before := host.files.save_content()
	check(not sharing.call("create_current",host.sim.city,host.sim.snapshot(),SaveFormat.STAGE_PLAY,{},blocker).ok)
	check_eq(host.files.save_content(),before)
	check_eq(FileAccess.get_file_as_string(blocker),"keep")

func test_share_button_selection_and_modal_return() -> void:
	var saved := host.files.save_city_as("share-selected")
	paths.append(saved)
	host.files.open_load_dialog()
	var button := host.load_dialog.find_child("ShareSave",true,false) as Button
	check(button != null and not button.disabled,"saved-city selection enables Share")
	check(host.load_dialog.has_signal("share_requested"))
	if button == null: return
	button.pressed.emit()
	for frame in 40:
		RenderingServer.force_draw(false)
		await process_frame
		if not host.loading_screen.visible: break
	var dialog := host.find_child("ShareCityDialog",true,false) as Control
	check(dialog != null and dialog.visible)
	check_eq(host.modal_depth,1)
	if dialog != null: dialog.call("close")
	check(host.load_dialog.is_open(),"Done returns to the save browser")
	check_eq(host.load_dialog.selected_path(),saved)
	host.load_dialog.refresh([], [{"name":"Classic","path":"res://assets/cities/La Presa.sc2"}])
	check(button.disabled,"included classic cities must first become native personal saves")

# Guards against: City → Share City silently doing nothing while Settings is open.
func test_share_city_works_while_settings_is_open() -> void:
	host.window_manager.open("options")
	check(host.window_manager.is_open("options"))
	host.files.request_city_share()
	for frame in 40:
		RenderingServer.force_draw(false)
		await process_frame
		if not host.loading_screen.visible: break
	var dialog := host.find_child("ShareCityDialog",true,false) as Control
	check(dialog != null and dialog.visible,"the share dialog opens")
	check(not host.window_manager.is_open("options"),"Settings steps aside")
	if dialog != null and dialog.visible:
		var prepared: Dictionary = dialog.get("copy")
		if prepared.has("path"): paths.append(String(prepared.path))
		dialog.call("close")
	check_eq(host.modal_depth,0)
