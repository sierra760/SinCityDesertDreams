# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Zoom follows gesture magnitude: a trackpad pinch arrives as many small
## magnify events and precision touchpads/free-spinning wheels as many
## fractional wheel steps. Neither may zoom a whole step per event.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_platform_input_zoom.cfg"


func _wheel(button: MouseButton, factor: float, position: Vector2 = Vector2(90, 90)) -> InputEventMouseButton:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = button
	wheel.pressed = true
	wheel.factor = factor
	wheel.position = position
	return wheel


func test_terrain_map_pinch_accumulates_to_whole_levels() -> void:
	var map := TerrainExtentMap.new()
	root.add_child(map)
	map.size = Vector2(600, 400)
	map.view.zoom = 10
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = Vector2(300, 200)
	pinch.factor = 1.03
	for i in 20:
		map._gui_input(pinch)
	# 1.03^20 is about 1.8x: one map level (2x), not twenty.
	check_eq(int(map.view.zoom), 11, "one trackpad pinch moves about one level")
	pinch.factor = 1.0 / 1.03
	for i in 20:
		map._gui_input(pinch)
	check_eq(int(map.view.zoom), 10, "pinching back returns to the starting level")
	map.free()


func test_terrain_map_fractional_wheel_steps_add_up() -> void:
	var map := TerrainExtentMap.new()
	root.add_child(map)
	map.size = Vector2(600, 400)
	map.view.zoom = 10
	for i in 10:
		map._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.1))
	check_eq(int(map.view.zoom), 11, "ten tenth-steps are one level")
	map._gui_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, 1.0))
	check_eq(int(map.view.zoom), 10, "a whole wheel notch is still one level")
	map.view.zoom = TerrainExtentMap.MAX_ZOOM
	for i in 30:
		map._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP, 1.0))
	map._gui_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, 1.0))
	check_eq(int(map.view.zoom), TerrainExtentMap.MAX_ZOOM - 1, "steps past the closest level do not build up")
	map.free()


func test_city_wheel_zoom_follows_factor() -> void:
	ViewPreferences.write({}, PREFS)
	var host: GameHost = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	var city := flat_city()
	host.start_new_city({"name": "Zoom Test", "seed": 4127, "difficulty": City.Difficulty.EASY}, city)
	host.found_city()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	var view := host.city_view_3d
	view.set_camera_state(Vector3(64, view.center.y, 64), 0, 40.0)
	var point := view.container.position + view.container.size * 0.5
	for i in 10:
		view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.1, point))
	check(absf(view.camera_size - 40.0 * 1.25) < 0.01, "ten tenth-steps zoom one notch (1.25x), not 1.25^10")
	view.set_camera_state(Vector3(64, view.center.y, 64), 0, 40.0)
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, 1.0, point))
	check(absf(view.camera_size - 40.0 / 1.25) < 0.01, "a whole notch keeps its 1.25x step")
	var center := view.center
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_RIGHT, 1.0, point))
	check(view.center.distance_to(center) > 0.01, "sideways scroll pans the map")
	check(absf(view.camera_size - 40.0 / 1.25) < 0.01, "sideways scroll never zooms")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
