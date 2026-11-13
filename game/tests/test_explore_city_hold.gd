# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore holds the city: the speed keys leave its speed alone and say why,
## and the footer reads Paused until the return to Build.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-explore-city-hold.cfg"

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	var city := flat_city()
	city.building.put(10, 10, 30)
	host.begin_city(city, {}, 4242, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	host.city_view_3d.set_camera_state(Vector3(10.5, 4 * CityGeometry3D.HEIGHT, 10.5), 1, 12.0)
	await physics_frame


func after_each() -> void:
	if host.sim._ctx != null: host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	if FileAccess.file_exists(PREFERENCES): DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func _key(code: int, pressed: bool = true) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	return key


func _type(code: int) -> void:
	host._unhandled_key_input(_key(code))
	host._unhandled_key_input(_key(code, false))


func test_speed_keys_do_not_change_the_held_city() -> void:
	check(host.enter_explore(), "Explore starts")
	await physics_frame
	host.display_layout.release_city_focus()
	check_eq(host.status_bar.speed_label.text, "Paused", "the footer shows the city held")
	for code: int in [KEY_P, KEY_EQUAL, KEY_MINUS, KEY_KP_ADD, KEY_KP_SUBTRACT]:
		host.status_bar.set_message("")
		_type(code)
		check_eq(host.sim.speed, GameClock.Speed.FAST, "the kept speed is unchanged by %s" % OS.get_keycode_string(code))
		check_eq(host.status_bar.message_label.text, GameHost.EXPLORE_HELD_MESSAGE, "the key says why nothing changed")
		check_eq(host.status_bar.speed_label.text, "Paused")
	host.return_to_build()
	check_eq(host.sim.speed, GameClock.Speed.FAST, "Build resumes at the speed it had")
	check_eq(host.status_bar.speed_label.text, String(GameClock.SPEED_NAMES[GameClock.Speed.FAST]))
	_type(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "P pauses again in Build")


func test_footer_stays_paused_through_refreshes_in_explore() -> void:
	check(host.enter_explore())
	await physics_frame
	host.status_bar.refresh(host.sim)
	check_eq(host.status_bar.speed_label.text, "Paused", "a footer refresh keeps the held state")
	host._refresh_after_casino()
	check_eq(host.status_bar.speed_label.text, "Paused", "leaving a table keeps the held state")
	host.notices.show("Notice", "A notice in Explore.")
	host.notice_dialog.dismiss()
	check_eq(host.status_bar.speed_label.text, "Paused", "closing a notice keeps the held state")
	check(host.status_bar.summary().contains("Paused"))
	host.return_to_build()
	check_eq(host.status_bar.speed_label.text, String(GameClock.SPEED_NAMES[GameClock.Speed.FAST]))


func test_speed_menu_choice_in_explore_is_kept_and_explained() -> void:
	check(host.enter_explore())
	await physics_frame
	host.status_bar.set_message("")
	host.menu_bar.press(&"speed", GameClock.Speed.SLOW)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "the menu choice is kept for Build")
	check_eq(host.status_bar.speed_label.text, "Paused", "the footer still shows the city held")
	check(host.status_bar.message_label.text.contains("return to Build"), host.status_bar.message_label.text)
	var day: int = host.sim.clock.day
	for i in 30: await process_frame
	check_eq(host.sim.clock.day, day, "no day passes in Explore")
	host.return_to_build()
	check_eq(host.status_bar.speed_label.text, String(GameClock.SPEED_NAMES[GameClock.Speed.SLOW]))


func test_a_city_begun_after_explore_shows_its_own_speed() -> void:
	check(host.enter_explore())
	await physics_frame
	host.begin_city(flat_city(), {}, 5, CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	check_eq(host.status_bar.speed_label.text, String(GameClock.SPEED_NAMES[GameClock.Speed.SLOW]))
