# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Native views of building lots planting their trees in each vegetation zone,
## through the actual CityView3D: the same row of buildings on a desert floor,
## a woodland bench and a forest bench.
## Run only in an isolated project copy with private user data:
## VEGETATION_EVIDENCE=<dir> godot --path <copy> --script res://tools/lot_vegetation_preview.gd
extends SceneTree

const MODELS := [150, 174, 238, 204, 145, 213, 236, 251]
## [first row, ground level] per zone band: palms, piñon-juniper, pines.
const BANDS := [[20, 2], [50, 12], [80, 22]]


func _initialize() -> void:
	call_deferred("_run")


func _city() -> City:
	var city := City.new()
	city.name = "Lot Vegetation Preview"
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			city.terrain.put(x, y, Terrain.FLAT)
			var level := 2
			for band: Array in BANDS:
				if y >= int(band[0]) - 6 and y < int(band[0]) + 14: level = int(band[1])
			city.set_heights(x, y, level, 0)
	for band: Array in BANDS:
		var x := 20
		for code: int in MODELS:
			city.stamp_building(x, int(band[0]), code)
			x += Buildings.size(code).x + 1
		for road_x: int in range(18, x + 2):
			city.building.put(road_x, int(band[0]) + 5, Buildings.ROAD_FIRST + 1)
	city.vegetation = VegetationZones.make([true, true, true], [8, 16])
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
	var names := ["palms", "woodland", "forest"]
	for i: int in BANDS.size():
		var row: int = BANDS[i][0]
		for part: Array in [["west", 26.0], ["east", 40.0]]:
			var target := Vector3(part[1], 0, row + 2.5)
			target.y = _ground(city, Vector2(target.x, target.z))
			view.set_camera_state(target, 0, 6.0)
			if not await _capture(output, "lots-%s-%s" % [names[i], part[0]]): return
		var close := Vector3(23.0, 0, row + 1.5)
		close.y = _ground(city, Vector2(close.x, close.z))
		view.set_camera_state(close, 3, 2.6)
		if not await _capture(output, "lots-%s-close" % names[i]): return
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .01
	camera.far = 200
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	for i: int in BANDS.size():
		var row: int = BANDS[i][0]
		var eye := Vector2(18.5, row + 5.5)
		camera.position = Vector3(eye.x, _ground(city, eye) + .16, eye.y)
		camera.look_at(Vector3(30.0, _ground(city, Vector2(30, row + 2)) + .35, row + 2.0))
		if not await _capture(output, "street-%s" % names[i]): return
	view.clear_exploration_camera()
	camera.queue_free()
	print("LOT_VEGETATION_PREVIEW_CAPTURED on %s" % RenderingServer.get_current_rendering_method())
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
