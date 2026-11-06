# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Native Explore views of on-tile street blades and highway gantries through
## the actual CityView3D and street signage. Run only in an isolated project
## copy with private user data:
## SIGNS_EVIDENCE=<dir> godot --path <copy> --script res://tools/qa/street_signs_preview.gd
extends SceneTree

const Case := preload("res://tests/test_case.gd")
const Topology := preload("res://scripts/core/naming/street_topology.gd")

func _initialize() -> void:
	call_deferred("_run")

func _road(city: City, a: Vector2i, b: Vector2i) -> void:
	var result := Builder.new(city, CityStats.new()).apply(Tools.Kind.ROAD, a, b)
	assert(result.ok and result.applied)

func _city() -> Dictionary:
	var city: City = Case.flat_city()
	var names: Dictionary = {}
	# Highway pair: x=20 southbound, x=21 northbound; three west-side exits.
	for y: int in range(2, 100):
		city.building.put(20, y, NetworkShapes.HIGHWAY_NS)
		city.building.put(21, y, NetworkShapes.HIGHWAY_NS)
	var exits := {20: "Flamingo Road", 40: "Tropicana Avenue", 75: "Russell Road"}
	for row: int in exits:
		city.building.put(19, row, 95)
		city.flags.put(19, row, RotationMapper.AXIS_FLAG)
		_road(city, Vector2i(19, row-1), Vector2i(19, row-3))
		names[Topology.link_key(Vector2i(19, row-1), &"open", Vector2i(19, row-2), &"open")] = exits[row]
	# Houses lining both sides of the highway.
	for y: int in range(4, 98):
		for x: int in [17, 18, 22, 23]:
			if city.building.atv(Vector2i(x, y)) == 0: city.building.put(x, y, 112 + ((x + y) % 4))
	# A four-way junction boxed in by houses on every corner.
	_road(city, Vector2i(30, 50), Vector2i(40, 50))
	_road(city, Vector2i(35, 45), Vector2i(35, 55))
	for cell: Vector2i in [Vector2i(34, 49), Vector2i(36, 49), Vector2i(34, 51), Vector2i(36, 51), Vector2i(33, 49), Vector2i(37, 51)]:
		city.building.put(cell.x, cell.y, 112 + (cell.x % 4))
	names[Topology.link_key(Vector2i(35, 49), &"open", Vector2i(35, 50), &"open")] = "Fremont Street"
	names[Topology.link_key(Vector2i(34, 50), &"open", Vector2i(35, 50), &"open")] = "Las Vegas Boulevard"
	return {"city": city, "names": names}

func _run() -> void:
	var output := OS.get_environment("SIGNS_EVIDENCE")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# An occluded macOS window stops presenting frames; keep the capture visible.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	OS.low_processor_usage_mode = false
	var fixture := _city()
	var city: City = fixture.city
	var topology := Topology.new()
	topology.rebuild(city)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	var naming := StreetNamingService.new()
	naming.bind_city(city, topology)
	view.bind_street_names(topology, naming)
	for key: String in fixture.names:
		var keys: Array[String] = [key]
		var applied: Dictionary = naming.assign(keys, fixture.names[key], topology.revision)
		if not applied.ok: printerr("naming failed ", key); quit(3); return
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .01
	camera.far = 300
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	var graph: CityTrafficGraph = topology.traffic_graph()
	var deck := func(at: Vector2) -> float:
		var cell := Vector2i(floori(at.x), floori(at.y))
		return graph.point(cell, &"highway", at - Vector2(cell)).y
	var ground := func(at: Vector2) -> float:
		var cell := Vector2i(floori(at.x), floori(at.y))
		return CityGeometry3D.point_on_ground(city, cell, at - Vector2(cell)).y
	# [eye, target, eye height, target height, surface]
	var poses := {
		"driver-exit-gantry": [Vector2(20.30, 12.0), Vector2(20.45, 18.5), .11, .42, "deck"],
		"driver-exit-close": [Vector2(20.30, 15.6), Vector2(20.40, 18.5), .11, .45, "deck"],
		"driver-distance-gantry": [Vector2(20.30, 19.2), Vector2(20.45, 22.5), .11, .42, "deck"],
		"driver-stretch-gantry": [Vector2(20.30, 54.6), Vector2(20.45, 58.5), .11, .42, "deck"],
		"oblique-exit-lined": [Vector2(25.5, 15.0), Vector2(20.5, 18.5), .9, .3, "ground"],
		"oblique-distance-lined": [Vector2(25.5, 25.5), Vector2(20.5, 22.5), .9, .3, "ground"],
		"junction-pedestrian-ne": [Vector2(36.35, 48.4), Vector2(35.15, 49.9), .12, .16, "ground"],
		"junction-pedestrian-sw": [Vector2(34.4, 51.8), Vector2(35.15, 50.15), .12, .16, "ground"],
		"junction-above": [Vector2(37.2, 52.6), Vector2(35.1, 50.1), .7, .05, "ground"],
		"junction-blade-close": [Vector2(35.62, 50.80), Vector2(35.15, 50.15), .12, .17, "ground"],
		"junction-blade-side": [Vector2(34.45, 50.62), Vector2(35.14, 50.14), .13, .16, "ground"],
		"junction-blade-macro": [Vector2(35.30, 50.36), Vector2(35.14, 50.14), .15, .15, "ground"],
		"junction-blade-macro-2": [Vector2(34.92, 50.38), Vector2(35.14, 50.14), .14, .15, "ground"],
		"distance-board-close": [Vector2(20.40, 20.3), Vector2(20.45, 22.5), .16, .47, "deck"],
		"exit-board-close": [Vector2(20.30, 16.6), Vector2(20.30, 18.5), .16, .47, "deck"],
	}
	var count := 0
	for name: String in poses:
		var pose: Array = poses[name]
		var eye: Vector2 = pose[0]
		var target: Vector2 = pose[1]
		var surface: Callable = deck if pose[4] == "deck" else ground
		camera.position = Vector3(eye.x, surface.call(eye) + pose[2], eye.y)
		var aim_y: float = (deck.call(target) if pose[4] == "deck" or name.begins_with("oblique") else ground.call(target)) + pose[3]
		camera.look_at(Vector3(target.x, aim_y, target.y))
		if not await _capture(output, name): return
		count += 1
	var diagnostics: Array = view.street_signage.diagnostics
	print("SIGN_DIAGNOSTICS ", diagnostics)
	var kinds := {}
	for node: Node in view.street_signage.find_children("*", "Node3D", true, false):
		if node.has_meta("sign_kind"): kinds[node.get_meta("sign_kind")] = int(kinds.get(node.get_meta("sign_kind"), 0)) + 1
	print("SIGN_KINDS ", kinds)
	print("SIGNS_PREVIEW_CAPTURED: %d native views on %s" % [count, RenderingServer.get_current_rendering_method()])
	quit()

func _capture(output: String, name: String) -> bool:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name + ".png")) != OK:
		quit(1)
		return false
	return true
