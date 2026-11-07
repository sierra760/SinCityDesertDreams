# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Native day/night views of an included city through the actual CityView3D:
## aerial Build views and street-level Explore views, each captured by day
## and under the full moon. Run only in an isolated project copy with private
## user data:
## NIGHT_EVIDENCE=<dir> [NIGHT_CITY="La Presa"] godot --path <copy> --script res://tools/qa/night_mode_preview.gd
extends SceneTree

## Codes that carry authored neon or lamps (see CityNightMode roles).
const NEON_CODES := [253, 252, 251, 254, 126, 180, 125, 127, 131, 148, 182, 256, 261, 233]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_environment("NIGHT_EVIDENCE")
	if output.is_empty(): quit(2); return
	var city_name := OS.get_environment("NIGHT_CITY")
	if city_name.is_empty(): city_name = "La Presa"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	OS.low_processor_usage_mode = false
	var loaded := SaveFormat.load("res://assets/cities/%s.sc2d" % city_name)
	if not bool(loaded.ok): printerr("load failed"); quit(3); return
	var city: City = loaded.city
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	# Find a cluster of neon-bearing buildings near roads.
	var focus := Vector2i(64, 64)
	var best := -1
	for y: int in range(4, City.HEIGHT - 4, 2):
		for x: int in range(4, City.WIDTH - 4, 2):
			var score := 0
			for dy: int in range(-4, 5):
				for dx: int in range(-4, 5):
					var code := city.building.at(x + dx, y + dy)
					if code in NEON_CODES: score += 6
					elif NetworkShapes.is_plain_road(code): score += 1
					elif code >= 112: score += 1
			if score > best:
				best = score
				focus = Vector2i(x, y)
	print("NIGHT_FOCUS ", focus, " score ", best)
	var target := Vector3(focus.x + .5, CityGeometry3D.surface_height(city, focus), focus.y + .5)
	var count := 0
	for mode: String in ["day", "night"]:
		view.set_night_mode(mode == "night", true)
		for shot: Array in [["aerial-wide", 0, 64.0], ["aerial-district", 1, 22.0], ["aerial-close", 2, 10.0]]:
			view.set_camera_state(target, int(shot[1]), float(shot[2]))
			if not await _capture(view, view.camera, output, "%s-%s" % [shot[0], mode]): return
			count += 1
	# Street level: stand on a road near the focus and look across it.
	var graph: CityTrafficGraph = view.traffic.graph
	var road := graph.nearest_cell(target, &"road", 12.0)
	if road != CityTrafficGraph.INVALID:
		var camera := Camera3D.new()
		camera.fov = 62
		camera.near = .01
		camera.far = 300
		view.world.add_child(camera)
		view.set_exploration_camera(camera)
		var eye := graph.walk_point(road, Vector2(.16, .16)) + Vector3(0, .11, 0)
		var poses := {
			"street-toward-focus": [eye, target + Vector3(0, .25, 0)],
			"street-along-road": [eye, graph.walk_point(road, Vector2(.5, .5)) + Vector3(3.0, .15, 0)],
			"street-raised": [eye + Vector3(-1.5, .9, -1.5), target + Vector3(0, .1, 0)],
		}
		for mode: String in ["day", "night"]:
			view.set_night_mode(mode == "night", true)
			for name: String in poses:
				camera.position = poses[name][0]
				camera.look_at(poses[name][1])
				if not await _capture(view, camera, output, "%s-%s" % [name, mode]): return
				count += 1
	print("NIGHT_LAMPS ", view.street_lamps.placements.size())
	print("NIGHT_PREVIEW_CAPTURED: %d native views on %s" % [count, RenderingServer.get_current_rendering_method()])
	quit()

func _capture(view: CityView3D, camera: Camera3D, output: String, name: String) -> bool:
	for frame: int in 10:
		view.traffic.advance(1.0 / 30.0, false, [], camera)
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name + ".png")) != OK:
		quit(1)
		return false
	return true
