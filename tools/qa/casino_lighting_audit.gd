# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Night lighting audit: every casino stands alone on its own block with a road
## in front, seen from its front, both sides, the back and close to its entrance,
## so the neon, marquee and wash can be checked against the building itself.
## Run only in an isolated project copy with private user data:
## NIGHT_EVIDENCE=<dir> [NIGHT_ONLY=251,252] godot --path <copy> --script res://tools/qa/casino_lighting_audit.gd
extends SceneTree

const Case := preload("res://tests/test_case.gd")
const RESORTS := [Tools.Kind.ARCOLOGY_COMSTOCK, Tools.Kind.ARCOLOGY_JUNCTION, Tools.Kind.ARCOLOGY_BOULDER,
	Tools.Kind.ARCOLOGY_ORBIT, Tools.Kind.ARCOLOGY_FIX, Tools.Kind.ARCOLOGY_ALIBI, Tools.Kind.ARCOLOGY_VELVET,
	Tools.Kind.ARCOLOGY_AFTERGLOW, Tools.Kind.ARCOLOGY_LAST, Tools.Kind.ARCOLOGY_DUST, Tools.Kind.ARCOLOGY_BODDY,
	Tools.Kind.ARCOLOGY_WOOLIER, Tools.Kind.ARCOLOGY_STOCKGROWERS, Tools.Kind.ARCOLOGY_FREMONT]
const SPACING := 26

func _initialize() -> void:
	call_deferred("_run")

func _blocks() -> City:
	var city: City = Case.flat_city(50000000)
	city.founded_year = 2010
	var builder := Builder.new(city, CityStats.new())
	var kinds: Array = RESORTS.duplicate()
	kinds.append(-1) # Despicable's
	for i: int in kinds.size():
		var origin := Vector2i(10 + (i % 4) * SPACING, 10 + (i / 4) * SPACING)
		var size: Vector2i = Tools.footprint(kinds[i]) if kinds[i] >= 0 else Vector2i.ONE
		builder.apply(Tools.Kind.ROAD, Vector2i(origin.x - 3, origin.y + size.y), Vector2i(origin.x + size.x + 2, origin.y + size.y))
		if kinds[i] >= 0:
			var placed: Dictionary = builder.apply(kinds[i], origin, origin)
			if not placed.get("ok", false): print("PLACE_FAILED ", kinds[i], " ", placed.get("reason", ""))
		else:
			city.building.put(origin.x, origin.y, 126)
	for yy: int in City.HEIGHT:
		for xx: int in City.WIDTH:
			city.flags.put(xx, yy, city.flags.at(xx, yy) | TileFlags.POWERED)
	return city

func _run() -> void:
	var output := OS.get_environment("NIGHT_EVIDENCE")
	if output.is_empty(): quit(2); return
	var only := OS.get_environment("NIGHT_ONLY").split(",", false)
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	OS.low_processor_usage_mode = false
	var city := _blocks()
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true, true)
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .01
	camera.far = 300
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	await process_frame
	var count := 0
	for record: Dictionary in view.night.casinos.lots:
		if not only.is_empty() and not str(record.code) in only: continue
		var bounds: AABB = record.bounds
		var center := bounds.get_center()
		var base := bounds.position.y
		var front := Vector3(0, 0, 1)
		var door_point := center
		if not (record.door as Dictionary).is_empty():
			front = Vector3(record.door.front.x, 0, record.door.front.y).normalized()
			door_point = Vector3(record.door.center.x, base, record.door.center.y)
		var side := front.cross(Vector3.UP).normalized()
		var reach := maxf(bounds.size.x, bounds.size.z) * .5 + maxf(1.2, bounds.size.y * .7)
		var look := Vector3(center.x, base + minf(bounds.size.y * .45, 1.2), center.z)
		var poses := {
			"a-front": [look + front * reach + Vector3(0, .1, 0), look],
			"b-right": [look + side * reach + Vector3(0, .1, 0), look],
			"c-back": [look - front * reach + Vector3(0, .1, 0), look],
			"d-left": [look - side * reach + Vector3(0, .1, 0), look],
			"e-entrance": [door_point + front * .75 + Vector3(0, .14, 0), door_point + Vector3(0, .12, 0)],
			"g-crown": [Vector3(center.x, base + bounds.size.y * .85, center.z) + (front * .8 + side * .5).normalized() * maxf(maxf(bounds.size.x, bounds.size.z) * 1.1, bounds.size.y * .45) + Vector3(0, bounds.size.y * .3, 0), Vector3(center.x, base + bounds.size.y * .85, center.z)],
			"f-aerial": [look + (front + side * .6).normalized() * reach * 1.1 + Vector3(0, bounds.size.y * .9 + 1.0, 0), Vector3(center.x, base + bounds.size.y * .5, center.z)],
		}
		for name: String in poses:
			camera.position = poses[name][0]
			camera.look_at(poses[name][1])
			if not await _capture(view, camera, output, "%d-%s" % [record.code, name]): return
			count += 1
	print("CASINO_AUDIT_CAPTURED: %d native views on %s" % [count, RenderingServer.get_current_rendering_method()])
	quit()

func _capture(view: CityView3D, camera: Camera3D, output: String, name: String) -> bool:
	for frame: int in 8:
		view.traffic.advance(1.0 / 30.0, false, [], camera)
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name + ".png")) != OK:
		quit(1)
		return false
	return true
