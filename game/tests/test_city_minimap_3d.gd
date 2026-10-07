# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
func test_minimap_follows_city_and_view() -> void:
	var city := City.new()
	city.building.put(71, 71, Buildings.COAL_PLANT)
	city.terrain.put(42, 42, Terrain.SURFACE)
	var before := SaveFormat.encode_city(city)
	var view := CityView3D.new()
	var overview := MiniMap.new()
	root.add_child(view)
	root.add_child(overview)
	view.bind_city(city)
	view.set_active(true)
	overview.bind(city, view)
	check(overview.get_image().get_size() == Vector2i(128, 128), "overview reads direct canonical city")
	check(absf(overview.get_image().get_pixel(71,71).r - MiniMap.COLOR_CIVIC.r) < 0.01, "building colors retained")
	for bounds: Rect2 in [Rect2(0,0,1000,640), Rect2(0,0,640,400), Rect2(0,0,1280,800)]:
		overview.apply_layout(bounds, 44, 88, 240)
		var rect := Rect2(overview._margin.position, overview._margin.size)
		var area := Rect2(240,44,bounds.size.x-240,bounds.size.y-132)
		check(area.encloses(rect), "minimap fits measured city area %s" % bounds.size)
	for rotation: int in 4:
		view.set_camera_state(view.center, rotation, 16)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = Vector2(80.5, 50.5) * overview._texture_rect.size / 128
		overview._on_click(event)
		var selected := RotationMapper.screen_to_data(80,50,rotation)
		check(Vector2(view.center.x-0.5, view.center.z-0.5) == Vector2(selected), "navigation respects camera rotation")
		overview.input_blocked = func(): return true
		var center := view.center
		event.position = Vector2.ZERO
		overview._on_click(event)
		check(view.center == center, "blocked minimap does not navigate")
		overview.input_blocked = Callable()
	check(SaveFormat.encode_city(city) == before, "overview display and navigation preserve city bytes")
	overview.free()
	view.free()
	await process_frame
	await process_frame
