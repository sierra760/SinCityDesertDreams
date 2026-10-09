# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")

class IOSHost extends GameHost:
	func can_quit_application() -> bool:
		return false

var host: GameHost
var path := "user://quit-lifecycle.sc2d"
const BAD_DESTINATION := "user://quit-lifecycle-directory"

func before_each() -> void:
	host = MAIN.instantiate()
	host.set_script(IOSHost)
	host.preferences_path = "user://quit-lifecycle.cfg"
	root.add_child(host)
	current_scene = host

func after_each() -> void:
	if is_instance_valid(current_scene): current_scene.free()
	if is_instance_valid(host): host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_DESTINATION))
	await process_frame

func _await_title() -> GameHost:
	for frame in 30:
		await process_frame
		if not is_instance_valid(host): break
	check(not is_instance_valid(host), "closing the city releases its original host")
	var title_host := current_scene as GameHost
	check(title_host != null)
	if title_host != null:
		check(title_host.title_screen.visible)
		check(not title_host.in_game)
		check_eq(title_host.sim.city, null)
	return title_host

func test_ios_discard_closes_city_without_writing_changes() -> void:
	var city := flat_city()
	city.name = "Quit lifecycle"
	host.begin_city(city, {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	check_eq(host.files.write_save(path), OK)
	host.save_path = path
	var saved := FileAccess.get_file_as_bytes(path)
	city.funds -= 100
	var state := host.sim.snapshot().duplicate(true)
	host.menu_bar.press(&"city_quit")
	check(host.notice_dialog.is_open())
	host.notice_dialog.choice_buttons[0].pressed.emit()
	check_eq(host.sim.snapshot(), state, "Cancel preserves the running city and speed")
	check_eq(host.sim.city, city)
	host.menu_bar.press(&"city_quit")
	check_eq(host.notice_dialog.choice_buttons.size(), 3)
	# Discard must return to a fresh title, not terminate the test process.
	host.notice_dialog.choice_buttons[1].pressed.emit()
	for frame in 8: await process_frame
	check(not is_instance_valid(host), "Discard releases the old city host")
	var title_host := current_scene as GameHost
	check(title_host != null, "the application remains usable after closing a city")
	if title_host != null:
		check(title_host.title_screen.visible)
		check(not title_host.in_game)
		check_eq(title_host.stage, GameHost.Stage.NONE)
		check_eq(title_host.sim.city, null)
	check_eq(FileAccess.get_file_as_bytes(path), saved, "Discard preserves the last saved bytes")
	if title_host != null:
		title_host.title_screen.new_button.pressed.emit()
		check(title_host.new_city_dialog.is_open(), "the fresh title can start another city")
		title_host.new_city_dialog.close()

func test_ios_title_hides_unsupported_quit_action() -> void:
	check(not host.title_screen.quit_button.visible)
	check(not host.menu_bar.is_enabled(&"city_quit"), "there is no city to close at the title")
	var city_menu := host.menu_bar.get_menu_popup(0)
	check_eq(city_menu.get_item_text(city_menu.get_item_count() - 1), "Close City")

func test_ios_save_succeeds_before_closing_city() -> void:
	host.begin_city(flat_city(), {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = path
	host.sim.city.funds = 19889
	host.menu_bar.press(&"city_quit")
	host.notice_dialog.choice_buttons[2].pressed.emit()
	check(is_instance_valid(host) and host.loading_screen.visible, "saving precedes the title transition")
	await _await_title()
	var loaded := SaveFormat.load(path)
	check(bool(loaded.ok))
	if loaded.ok: check_eq((loaded.city as City).funds, 19889)

func test_ios_failed_save_keeps_city_open() -> void:
	host.begin_city(flat_city(), {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	check_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAD_DESTINATION)), OK)
	host.save_path = BAD_DESTINATION
	host.menu_bar.press(&"city_quit")
	host.notice_dialog.choice_buttons[2].pressed.emit()
	for frame in 30:
		await process_frame
		if not host.loading_screen.visible: break
	check_eq(current_scene, host)
	check(host.in_game and not host.title_screen.visible)
	check(host.notice_dialog.is_open(), "a real invalid save destination reports the failure")
	check_eq(host.files._after_save_action, &"")
	check(host.files.has_unsaved_changes())
	host.notice_dialog.dismiss()

func test_ios_discard_disposes_active_explore_session() -> void:
	var city := flat_city()
	city.building.put(10, 10, 30)
	host.begin_city(city, {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(10.5, 4 * CityGeometry3D.HEIGHT, 10.5), 1, 12.0)
	await physics_frame
	check(host.enter_explore())
	if not host.exploration.is_active(): return
	var actor: WeakRef = weakref(host.exploration.pedestrian)
	host.menu_bar.press(&"city_quit")
	host.notice_dialog.choice_buttons[1].pressed.emit()
	await _await_title()
	check_eq(actor.get_ref(), null, "closed cities retain no Explore actor")
	check_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)

func test_android_back_closes_front_most_then_offers_save() -> void:
	check_eq(ProjectSettings.get_setting("application/config/quit_on_go_back",true),false,"Back reaches the game instead of quitting the app")
	host.begin_city(flat_city(), {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.sim.city.funds -= 100
	var state := host.sim.snapshot().duplicate(true)
	host.window_manager.open("options")
	check(host.window_manager.front() != null)
	host.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check_eq(host.window_manager.front(), null, "Back closes the front window first")
	check(not host.notice_dialog.is_open())
	# Repeated Back works down to nothing open, then asks before leaving.
	for press in 4:
		if host.notice_dialog.is_open(): break
		host.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(host.notice_dialog.is_open(), "an unsaved city is offered a save before leaving")
	check_eq(host.notice_dialog.choice_buttons.size(), 3)
	check(is_instance_valid(host) and host.in_game, "the city is still open")
	check_eq(host.sim.snapshot(), state, "Back never advances or alters the city")
	host.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not host.notice_dialog.is_open(), "Back on the prompt cancels it")
	check(host.in_game)

# Guards against: Android Back doing nothing while a street name is being
# typed (Escape leaves typing to the text field, so Back had no effect).
func test_android_back_cancels_a_street_name_being_typed() -> void:
	host.begin_city(flat_city(), {}, 42, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	check(host.handle_drag(Vector2i(50, 60), Vector2i(60, 60)).ok, "fixture: a road to name")
	host.select_tool(GameHost.NO_TOOL)
	var names: Node = host.get("street_names")
	check(names.enter(), "Street Names opens")
	var edit: LineEdit = names.panel.name_edit
	edit.grab_focus()
	edit.text = "Elm Stree"
	check(edit.has_focus(), "fixture: a name is being typed")
	var before := SaveFormat.encode_city(host.sim.city)
	host.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(names.is_active(), "Back keeps the editor open")
	check(not edit.has_focus(), "Back stops the typing")
	check_eq(edit.text, "", "the typed text is dropped")
	check(not host.notice_dialog.is_open(), "Back does not offer to leave the city")
	check_eq(SaveFormat.encode_city(host.sim.city), before, "no name was applied")
	host.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not names.is_active(), "the next Back closes Street Names")
	check(host.in_game)

func test_background_window_lets_the_display_sleep() -> void:
	host.begin_city(flat_city(), {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	check(host.keep_screen_on_wanted(), "a running city in the focused window keeps the display awake")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not host.keep_screen_on_wanted(), "a background or minimized window lets the display sleep")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(host.keep_screen_on_wanted(), "returning to the window keeps a running city awake again")
	host.sim.set_speed(GameClock.Speed.PAUSED)
	check(not host.keep_screen_on_wanted(), "a paused city lets the display sleep")

func test_quit_from_minimized_window_restores_it_before_prompting() -> void:
	host.begin_city(flat_city(), {}, 123, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.sim.city.funds -= 100
	host.display_layout.maximized = true
	host.display_layout.mode_override = Window.MODE_MINIMIZED
	host.files.quit_game()
	check_eq(host.display_layout.mode_override, Window.MODE_MAXIMIZED, "the window returns to its maximized state before the prompt")
	check(host.notice_dialog.is_open(), "the save question is queued in the restored window")
	host.notice_dialog.dismiss()
	host.display_layout.mode_override = -1
