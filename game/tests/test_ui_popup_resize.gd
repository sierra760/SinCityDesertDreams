# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Popup integration uses real Main wiring and real PopupMenu event delivery.
## Run with native windows to certify the nonembedded cases; backing values are
## injected so the same assertions remain deterministic on 1x and Retina hosts.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_ui_popup_resize.cfg"
var host: GameHost
var _was_embedded := true


func _run_all() -> void:
	_was_embedded = root.gui_embed_subwindows
	for method in get_method_list():
		if not String(method.name).begins_with("test_"):
			continue
		_current = method.name
		var before := _failed
		await _setup()
		await call(method.name)
		await _cleanup()
		if _failed == before:
			_passed += 1
		else:
			print("  FAIL ", method.name)
	root.gui_embed_subwindows = _was_embedded
	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _setup() -> void:
	root.gui_embed_subwindows = false
	root.size = Vector2i(2560, 1600)
	ViewPreferences.write({"ui_scale": 100}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.new_city_dialog.terrain_transport_factory = preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport
	host.display_layout.refresh_with_metrics(Vector2i(2560, 1600), 2.0)
	await _settle()


func _cleanup() -> void:
	if host.files.import_dialog != null:
		host.files.import_dialog.hide()
	for popup in host.menu_bar._menus.values():
		popup.hide()
	host.new_city_dialog.difficulty_button.get_popup().hide()
	if host.sim._ctx != null:
		host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	host = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await _settle()


func test_visible_native_menu_tracks_display_scale_and_reopens_without_growth() -> void:
	var popup: PopupMenu = host.menu_bar._menus["City"]
	popup.popup(Rect2i(40, 80, 300, 400))
	await _settle()
	check(not popup.is_embedded(), "exercise a real separate popup window")
	check(popup.visible)
	check_eq(popup.content_scale_factor, 2.0, "initial Retina scale")
	host.set_option(&"ui_scale", 125)
	await _settle()
	check_eq(popup.content_scale_factor, 2.5, "already-open menu follows UI scale")
	host.display_layout.refresh_with_metrics(Vector2i(1280, 800), 1.0)
	await _settle()
	check_eq(popup.content_scale_factor, 1.25, "already-open menu follows backing change")
	popup.hide()
	popup.popup()
	await _settle()
	var reopened := popup.size
	popup.hide()
	popup.popup()
	await _settle()
	check_eq(popup.size, reopened, "real PopupMenu reopening does not compound scale")


func test_visible_embedded_menu_refits_after_logical_resize() -> void:
	root.gui_embed_subwindows = true
	host.display_layout.refresh_with_metrics(Vector2i(1280, 800), 1.0)
	host.set_option(&"ui_scale", 100)
	var popup: PopupMenu = host.menu_bar._menus["City"]
	popup.popup(Rect2i(900, 450, 300, 300))
	await _settle()
	check(popup.is_embedded())
	host.set_option(&"ui_scale", 200)
	await _settle()
	if popup.visible:
		check(host.display_layout.logical_rect().encloses(Rect2(Vector2(popup.position), Vector2(popup.size))), "open embedded popup stays inside the shrunken logical display")


func test_native_user_resize_preserves_logical_size_on_rescale_and_reopen() -> void:
	# A plain resizable Window isolates the physical resize contract from a
	# FileDialog's theme-driven minimum size; Main's actual FileDialog is below.
	var popup := Window.new()
	popup.visible = false
	popup.size = Vector2i(300, 180)
	host.add_child(popup)
	host.display_layout.register_popup(popup)
	popup.popup()
	await _settle()
	check(not popup.is_embedded())
	check_eq(popup.size, Vector2i(600, 360))
	# Window.size is physical pixels, including a native user's resize event.
	popup.size = Vector2i(720, 480)
	await _settle()
	host.set_option(&"ui_scale", 125)
	await _settle()
	check_eq(popup.size, Vector2i(900, 600), "360x240 logical points survive the scale change")
	popup.hide()
	popup.popup()
	await _settle()
	check_eq(popup.size, Vector2i(900, 600), "reopening keeps the user-resized logical dimensions")
	popup.hide()
	popup.free()


func test_new_city_option_popup_uses_shared_scale() -> void:
	host.open_new_city_dialog()
	var popup := host.new_city_dialog.difficulty_button.get_popup()
	popup.popup(Rect2i(100, 100, 300, 160))
	await _settle()
	check(not popup.is_embedded())
	check_eq(popup.content_scale_factor, 2.0, "OptionButton popup follows root display owner")
	host.set_option(&"ui_scale", 125)
	await _settle()
	check_eq(popup.content_scale_factor, 2.5, "open OptionButton popup follows scale change")


func test_import_dialog_tracks_scale_while_open() -> void:
	host.files.open_import_dialog()
	await _settle()
	check(not host.files.import_dialog.is_embedded())
	check(host.files.import_dialog.visible)
	check_eq(host.files.import_dialog.content_scale_factor, 2.0)
	host.set_option(&"ui_scale", 125)
	await _settle()
	check_eq(host.files.import_dialog.content_scale_factor, 2.5, "visible import dialog updates before reopening")


func test_actual_menu_enter_activation_works_with_retained_toolbar_focus() -> void:
	# Route through the embedder, which invokes Window's native input hook before
	# its Viewport. Calling popup.push_input directly skips PopupMenu's handler.
	root.gui_embed_subwindows = true
	var city := flat_city()
	host.start_new_city({"name": "Popup Input", "seed": 4123}, city)
	host.found_city()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.toolbar.button_for(Tools.Kind.ROAD).grab_focus()
	var turn := host.city_view_3d.quarter_turn
	var snapshot := host.sim.snapshot().duplicate(true)
	var popup: PopupMenu = host.menu_bar._menus["View"]
	var entry: Dictionary = host.menu_bar._entries[host.menu_bar._key(&"rotate", null)]
	popup.popup(Rect2i(160, 80, 300, 400))
	await _settle()
	check(popup.is_embedded(), "exercise the engine's embedded Window input route")
	popup.set_focused_item(popup.get_item_index(int(entry["id"])))
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key)
	await _settle()
	check_eq(host.city_view_3d.quarter_turn, posmod(turn + 1, 4), "PopupMenu delivers the real Enter selection")
	check_eq(host.sim.snapshot(), snapshot, "explicit display action does not advance simulation")
