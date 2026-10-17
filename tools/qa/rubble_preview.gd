# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Native views of rubble and contaminated ground through the actual CityView3D.
## Run only in an isolated project copy with private user data:
## RUBBLE_EVIDENCE=<dir> godot --path <copy> --script res://tools/rubble_preview.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _city() -> City:
	var city := City.new()
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			city.terrain.put(x, y, Terrain.FLAT)
			# Flat ground west of x=40, a hillside rising one level a tile, then a plateau.
			city.set_heights(x, y, 4 + clampi(x - 40, 0, 5), 0)
	# One of each code on flat ground, then a hillside row, then a mixed field.
	for i: int in 5:
		city.building.put(28 + i * 2, 60, Buildings.RUBBLE_1 + i)
		city.building.put(41 + i, 64, Buildings.RUBBLE_1 + i)
	for y: int in range(66, 72):
		for x: int in range(28, 36):
			city.building.put(x, y, Buildings.RUBBLE_1 + ((x * 7 + y * 3) % 4))
	city.building.put(30, 73, Buildings.CONTAMINATION)
	city.building.put(31, 73, Buildings.CONTAMINATION)
	# A street and ordinary houses give scale.
	for x: int in range(26, 48):
		city.building.put(x, 62, Buildings.ROAD_FIRST + 1)
	for x: int in [27, 29, 31, 33, 35, 37]:
		city.building.put(x, 58, 112 + (x % 4))
	return city


func _run() -> void:
	var output := OS.get_environment("RUBBLE_EVIDENCE")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	# Captures must not wait on display refresh while the window is in the background.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(_city())
	view.set_active(true)
	view.refresh(true)
	var shots := {
		"aerial-flat": [Vector3(32.5, .0, 60.5), 0, 9.0],
		"aerial-flat-rotated": [Vector3(32.5, .0, 60.5), 2, 9.0],
		"aerial-hillside": [Vector3(43.5, 1.5, 64.5), 0, 7.5],
		"aerial-field": [Vector3(32, .0, 69), 1, 13.0],
		"aerial-close-contamination": [Vector3(36.5, .0, 60.5), 0, 3.2],
		"aerial-close-rubble1": [Vector3(28.5, .0, 60.5), 3, 3.2],
		"aerial-wide": [Vector3(36, .0, 66), 0, 34.0],
		"aerial-hillside-west": [Vector3(43.5, .0, 64.5), 1, 4.2],
		"aerial-hillside-southwest": [Vector3(43.5, .0, 64.5), 2, 4.2],
	}
	for name: String in shots:
		var shot: Array = shots[name]
		var target: Vector3 = shot[0]
		target.y = _ground(view.city, Vector2(target.x, target.z))
		view.set_camera_state(target, shot[1], shot[2])
		if not await _capture(output, name): return
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .01
	camera.far = 200
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	# Eye about 1.9 m above the street, looking at the debris.
	var streets := {
		"street-rubble1": [Vector2(28.5, 61.4), Vector2(28.5, 60.45)],
		"street-rubble2": [Vector2(30.9, 61.4), Vector2(30.5, 60.45)],
		"street-rubble3": [Vector2(32.2, 61.4), Vector2(32.5, 60.45)],
		"street-rubble4": [Vector2(34.9, 61.4), Vector2(34.5, 60.45)],
		"street-contamination": [Vector2(36.4, 61.4), Vector2(36.5, 60.45)],
		"street-hillside": [Vector2(39.2, 65.6), Vector2(43.5, 64.5)],
		"street-field": [Vector2(36.6, 72.6), Vector2(33.0, 69.0)],
	}
	var city: City = view.city
	for name: String in streets:
		var pose: Array = streets[name]
		var eye: Vector2 = pose[0]
		var target: Vector2 = pose[1]
		camera.position = Vector3(eye.x, _ground(city, eye) + .16, eye.y)
		camera.look_at(Vector3(target.x, _ground(city, target) + .03, target.y))
		if not await _capture(output, name): return
	print("RUBBLE_PREVIEW_CAPTURED: %d native views on %s" % [shots.size() + streets.size(), RenderingServer.get_current_rendering_method()])
	quit()


func _ground(city: City, at: Vector2) -> float:
	var cell := Vector2i(floori(at.x), floori(at.y))
	return CityGeometry3D.point_on_ground(city, cell, at - Vector2(cell)).y


func _capture(output: String, name: String) -> bool:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name + ".png")) != OK:
		quit(1)
		return false
	return true
