# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Native views of the three altitude vegetation zones through the actual
## CityView3D, and of the Vegetation Zones window over the city.
## Run only in an isolated project copy with private user data:
## VEGETATION_EVIDENCE=<dir> godot --path <copy> --script res://tools/vegetation_preview.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


## A valley floor at level 2 rising one level per two tiles to a level-26
## ridge, wooded with every density, plus a road and houses for scale.
func _city() -> City:
	var city := City.new()
	city.name = "Vegetation Preview"
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			city.terrain.put(x, y, Terrain.FLAT)
			city.set_heights(x, y, 2 + clampi((x - 30) / 2, 0, 24), 0)
	for y: int in range(52, 76):
		for x: int in range(16, 84):
			if x == 24 or (x + y * 3) % 5 == 0: continue
			city.building.put(x, y, Buildings.TREES_1 + (x * 3 + y * 7) % 7)
	for x: int in range(10, 30):
		city.building.put(x, 62, Buildings.ROAD_FIRST + 1)
	for x: int in [11, 13, 15, 17]:
		city.building.put(x, 60, 112 + (x % 4))
	return city


func _run() -> void:
	var output := OS.get_environment("VEGETATION_EVIDENCE")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	var city := _city()
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	print("AUTOMATIC: ", VegetationZones.resolve(city))
	var shots := {
		"aerial-all-zones": [Vector3(50, 0, 64), 0, 30.0],
		"aerial-all-zones-rotated": [Vector3(50, 0, 64), 2, 30.0],
		"aerial-palms": [Vector3(40, 0, 64), 0, 8.0],
		"aerial-woodland": [Vector3(61, 0, 64), 1, 8.0],
		"aerial-forest": [Vector3(76, 0, 64), 0, 8.0],
		"aerial-close-woodland": [Vector3(61, 0, 60), 3, 3.4],
		"aerial-close-forest": [Vector3(78, 0, 60), 0, 3.4],
	}
	for name: String in shots:
		var shot: Array = shots[name]
		var target: Vector3 = shot[0]
		target.y = _ground(city, Vector2(target.x, target.z))
		view.set_camera_state(target, shot[1], shot[2])
		if not await _capture(output, name): return
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .01
	camera.far = 200
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	var streets := {
		"street-woodland": [Vector2(57.5, 57.2), Vector2(63.0, 62.0)],
		"street-forest": [Vector2(70.5, 55.2), Vector2(76.0, 60.0)],
		"street-valley-up": [Vector2(26.0, 62.5), Vector2(60.0, 63.0)],
	}
	for name: String in streets:
		var pose: Array = streets[name]
		var eye: Vector2 = pose[0]
		var target: Vector2 = pose[1]
		camera.position = Vector3(eye.x, _ground(city, eye) + .16, eye.y)
		camera.look_at(Vector3(target.x, _ground(city, target) + .3, target.y))
		if not await _capture(output, name): return
	view.clear_exploration_camera()
	camera.queue_free()
	# Custom zones: woodland pushed low, pines from mid-slope.
	city.vegetation = VegetationZones.make([true, true, true], [6, 13])
	view.refresh()
	view.set_camera_state(Vector3(50, _ground(city, Vector2(50, 64)), 64), 0, 30.0)
	if not await _capture(output, "aerial-custom-zones"): return
	# The window over the city, desktop and compact.
	var sim := Simulation.new()
	sim.city = city
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var window := VegetationWindow.new()
	layer.add_child(window)
	await process_frame
	window.bind(sim)
	window.open()
	window.histogram.hovered = 14
	window.refresh()
	if not await _capture(output, "window-desktop"): return
	root.size = Vector2i(700, 760)
	await process_frame
	if not await _capture(output, "window-compact"): return
	city.vegetation = {}
	window.refresh()
	if not await _capture(output, "window-automatic"): return
	window.set_zone_enabled(VegetationZones.Zone.PINYON_JUNIPER, false)
	if not await _capture(output, "window-woodland-off"): return
	print("VEGETATION_PREVIEW_CAPTURED on %s" % RenderingServer.get_current_rendering_method())
	sim.free()
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
