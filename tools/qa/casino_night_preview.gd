# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Native views of a synthetic casino strip at night (and one by day) through
## the actual CityView3D: every resort plus Despicable's along a boulevard.
## Run only in an isolated project copy with private user data:
## NIGHT_EVIDENCE=<dir> godot --path <copy> --script res://tools/qa/casino_night_preview.gd
extends SceneTree

const Case := preload("res://tests/test_case.gd")
const RESORTS := [Tools.Kind.ARCOLOGY_COMSTOCK, Tools.Kind.ARCOLOGY_JUNCTION, Tools.Kind.ARCOLOGY_BOULDER,
	Tools.Kind.ARCOLOGY_ORBIT, Tools.Kind.ARCOLOGY_FIX, Tools.Kind.ARCOLOGY_ALIBI, Tools.Kind.ARCOLOGY_VELVET,
	Tools.Kind.ARCOLOGY_AFTERGLOW, Tools.Kind.ARCOLOGY_LAST, Tools.Kind.ARCOLOGY_DUST, Tools.Kind.ARCOLOGY_BODDY,
	Tools.Kind.ARCOLOGY_WOOLIER, Tools.Kind.ARCOLOGY_STOCKGROWERS, Tools.Kind.ARCOLOGY_FREMONT]
const BOULEVARD := 40

func _initialize() -> void:
	call_deferred("_run")

func _strip() -> City:
	var city: City = Case.flat_city(50000000)
	city.founded_year = 2010
	var builder := Builder.new(city, CityStats.new())
	builder.apply(Tools.Kind.ROAD, Vector2i(BOULEVARD, 6), Vector2i(BOULEVARD, 100))
	for y: int in range(10, 100, 12):
		builder.apply(Tools.Kind.ROAD, Vector2i(BOULEVARD - 8, y), Vector2i(BOULEVARD + 8, y))
	var y := 12
	for i: int in RESORTS.size():
		var kind: int = RESORTS[i]
		var size: Vector2i = Tools.footprint(kind)
		var west := i % 2 == 0
		var x := BOULEVARD - 1 - size.x if west else BOULEVARD + 2
		var placed: Dictionary = builder.apply(kind, Vector2i(x, y), Vector2i(x, y))
		if not placed.get("ok", false):
			placed = builder.apply(kind, Vector2i(x + size.x / 2, y + size.y / 2), Vector2i(x + size.x / 2, y + size.y / 2))
		print("PLACE ", kind, " ok=", placed.get("ok", false), " ", placed.get("reason", ""))
		if not west: y += 6
	city.building.put(BOULEVARD + 1, 8, 126)
	# The fixture has no plants; mark every tile powered so no outage icons show.
	for yy: int in City.HEIGHT:
		for xx: int in City.WIDTH:
			city.flags.put(xx, yy, city.flags.at(xx, yy) | TileFlags.POWERED)
	return city

func _run() -> void:
	var output := OS.get_environment("NIGHT_EVIDENCE")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	OS.low_processor_usage_mode = false
	var city := _strip()
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	var mid := Vector3(BOULEVARD + .5, CityGeometry3D.surface_height(city, Vector2i(BOULEVARD, 40)), 40.5)
	var count := 0
	view.set_night_mode(false, true)
	view.set_camera_state(mid, 1, 30.0)
	if not await _capture(view, view.camera, output, "strip-district-day"): return
	view.set_night_mode(true, true)
	for shot: Array in [["strip-wide", 1, 64.0, 52.0], ["strip-district", 1, 30.0, 40.0], ["strip-close-north", 2, 12.0, 24.0], ["strip-close-south", 0, 12.0, 60.0]]:
		view.set_camera_state(Vector3(mid.x, mid.y, float(shot[3])), int(shot[1]), float(shot[2]))
		if not await _capture(view, view.camera, output, shot[0]): return
		count += 1
	print("CASINO_LOTS ", view.night.casinos.lots.size() if view.night.casinos != null else -1)
	var graph: CityTrafficGraph = view.traffic.graph
	var camera := Camera3D.new()
	camera.fov = 64
	camera.near = .01
	camera.far = 300
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	var g := mid.y
	var poses := {
		"street-boulevard-north": [graph.walk_point(Vector2i(BOULEVARD, 70), Vector2(.2, .5)) + Vector3(0, .11, 0), Vector3(BOULEVARD + .5, g + .4, 30)],
		"street-boulevard-south": [graph.walk_point(Vector2i(BOULEVARD, 20), Vector2(.8, .5)) + Vector3(0, .11, 0), Vector3(BOULEVARD + .5, g + .4, 60)],
		"street-raised-strip": [Vector3(BOULEVARD + 6.0, g + 2.2, 78.0), Vector3(BOULEVARD, g + .6, 50)],
		"street-skyline": [Vector3(BOULEVARD + 14.0, g + .5, 96.0), Vector3(BOULEVARD, g + 1.6, 50)],
	}
	for name: String in poses:
		camera.position = poses[name][0]
		camera.look_at(poses[name][1])
		if not await _capture(view, camera, output, name + "-night"): return
		count += 1
	print("CASINO_NIGHT_CAPTURED: %d native views on %s" % [count + 1, RenderingServer.get_current_rendering_method()])
	quit()

func _capture(view: CityView3D, camera: Camera3D, output: String, name: String) -> bool:
	for frame: int in 12:
		view.traffic.advance(1.0 / 30.0, false, [], camera)
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name + ".png")) != OK:
		quit(1)
		return false
	return true
