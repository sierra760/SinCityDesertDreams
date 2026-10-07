# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Building/zone edits recolour retained terrain chunks exactly as a fresh build.
extends "res://tests/exploration/async_test_case.gd"
func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []
func _chunk(city: City, region: Rect2i) -> Dictionary:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	var data := CityGeometry3D.build_chunk(city, region)
	CityGeometry3D.end_ground_sampling(sampling)
	return data
func _same_chunk(a: Dictionary, b: Dictionary, label: String) -> void:
	check(_arrays(a.mesh) == _arrays(b.mesh), label + ": mesh arrays equal a fresh build")
	for key: String in b:
		if key == "mesh": continue
		check(a.has(key) and a[key] == b[key], label + ": " + key + " equals a fresh build")
func test_recoloured_chunks_match_fresh_builds() -> void:
	var recolored_count := 0
	for path: String in ["res://assets/cities/La Presa.sc2", "res://assets/cities/Valle del Mar.sc2", "res://assets/cities/Salton Shores.sc2"]:
		var loaded := Sc2Import.load(path)
		if not loaded.ok:
			check(false, "import " + path)
			continue
		var city: City = loaded.city
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var tested := 0
		var attempts := 0
		while tested < 24 and attempts < 6000:
			attempts += 1
			var x := rng.randi_range(0, City.WIDTH - 1)
			var y := rng.randi_range(0, City.HEIGHT - 1)
			var code := city.building.at(x, y)
			if not (code == Buildings.NONE or Buildings.is_zone_building(code) or code == Buildings.TREES_1): continue
			var region := Rect2i(Vector2i(x / 16 * 16, y / 16 * 16), Vector2i(16, 16))
			var before := _chunk(city, region)
			match tested % 4:
				0: city.building.put(x, y, Buildings.RES_1X1_FIRST if code == Buildings.NONE else Buildings.NONE)
				1: city.zone.put(x, y, Zones.make((Zones.kind(city.zone.at(x, y)) + 1) % 7))
				2:
					city.building.put(x, y, Buildings.NONE)
					city.zone.put(x, y, Zones.make(Zones.COM_LOW))
				3: city.building.put(x, y, Buildings.TREES_1 if code != Buildings.TREES_1 else Buildings.NONE)
			var fresh := _chunk(city, region)
			var recolored := CityGeometry3D.recolor_chunk(city, before, [Vector2i(x, y)])
			check(not recolored.is_empty(), path.get_file() + ": retained chunk carries tint records")
			if recolored.is_empty(): continue
			if recolored.mesh != before.mesh: recolored_count += 1
			_same_chunk(recolored, fresh, path.get_file() + " cell " + str(Vector2i(x, y)) + " case " + str(tested % 4))
			tested += 1
		check(tested == 24, path.get_file() + ": found 24 dry editable cells")
	check(recolored_count > 20, "recolouring produced new meshes for most edits (" + str(recolored_count) + ")")
	# Through the view: tint-only edits recolour; a tunnel mouth still rebuilds.
	var loaded := Sc2Import.load("res://assets/cities/Salton Shores.sc2")
	var city: City = loaded.city
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var target := Vector2i(-1, -1)
	for y: int in range(2, City.HEIGHT - 2):
		for x: int in range(2, City.WIDTH - 2):
			if city.building.at(x, y) == Buildings.NONE and not city.is_water(x, y) and city.zone_kind_at(x, y) == Zones.NONE:
				target = Vector2i(x, y)
				break
		if target.x >= 0: break
	check(target.x >= 0, "a dry empty cell exists")
	var chunk_body_ids: Array = []
	for child: Node in view.chunks.get_children(): chunk_body_ids.append(child.get_instance_id())
	city.zone.put(target.x, target.y, Zones.make(Zones.RES_LOW))
	view.refresh()
	check(view.refresh_statistics.terrain_recolored_chunks == 1 and view.refresh_statistics.terrain_rebuilt_chunks == 0, "zoning recolours one chunk without a rebuild")
	city.building.put(target.x, target.y, Buildings.RES_1X1_FIRST)
	view.refresh()
	check(view.refresh_statistics.terrain_recolored_chunks == 1 and view.refresh_statistics.terrain_rebuilt_chunks == 0, "a new lot recolours one chunk without a rebuild")
	var current_ids: Array = []
	for child: Node in view.chunks.get_children(): current_ids.append(child.get_instance_id())
	check(current_ids == chunk_body_ids, "recolouring keeps every terrain mesh and picking body identity")
	var incremental: Array = []
	for data: Dictionary in view._traversal_chunks: incremental.append(_arrays(data.mesh) if data.has("mesh") else [])
	view.refresh(true)
	var full: Array = []
	for data: Dictionary in view._traversal_chunks: full.append(_arrays(data.mesh) if data.has("mesh") else [])
	check(incremental == full, "recoloured terrain meshes equal a forced full rebuild")
	# Service and orientation flags never reach the terrain mesh.
	var flagged := 0
	var flag_rng := RandomNumberGenerator.new()
	flag_rng.seed = 9
	while flagged < 12:
		var fx := flag_rng.randi_range(0, City.WIDTH - 1)
		var fy := flag_rng.randi_range(0, City.HEIGHT - 1)
		if NetworkShapes.in_rail_family(city.building.at(fx, fy)): continue
		city.flags.put(fx, fy, city.flags.at(fx, fy) ^ (RotationMapper.AXIS_FLAG if flagged % 2 == 0 else TileFlags.CONDUCTS_POWER))
		flagged += 1
	view.refresh()
	check(view.refresh_statistics.terrain_rebuilt_chunks == 0 and view.refresh_statistics.terrain_recolored_chunks == 0, "flag-only changes leave every terrain chunk alone")
	incremental = []
	for data: Dictionary in view._traversal_chunks: incremental.append(_arrays(data.mesh) if data.has("mesh") else [])
	view.refresh(true)
	full = []
	for data: Dictionary in view._traversal_chunks: full.append(_arrays(data.mesh) if data.has("mesh") else [])
	check(incremental == full, "terrain after flag-only changes equals a forced full rebuild")
	city.building.put(target.x, target.y, Buildings.TUNNEL_FIRST)
	view.refresh()
	check(view.refresh_statistics.terrain_rebuilt_chunks >= 1, "a tunnel mouth still rebuilds terrain geometry")
	view.queue_free()
	await process_frame
