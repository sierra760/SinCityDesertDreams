# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var underground_script

func before_all() -> void:
	var path := "res://scripts/view/city_underground_3d.gd"
	if ResourceLoader.exists(path): underground_script = load(path)

func test_underground_renderer_exists() -> void:
	check(underground_script != null, "batched underground renderer must exist")

func test_all_stored_masks_and_crossings_are_decoded_without_art_conversion() -> void:
	if underground_script == null: return
	for mask in range(1, 16):
		check_eq(underground_script.decode(mask), {"pipe_mask": mask, "subway_mask": 0, "pipe_above": false, "station": false})
		check_eq(underground_script.decode(mask + 15), {"pipe_mask": 0, "subway_mask": mask, "pipe_above": false, "station": false})
	for code in range(31, 35):
		var decoded: Dictionary = underground_script.decode(code)
		check_eq(decoded.pipe_mask, 5 if code % 2 else 10)
		check_eq(decoded.subway_mask, 10 if code % 2 else 5)
		check_eq(decoded.pipe_above, code >= 33)
		check_eq(decoded.station, false)
	check_eq(underground_script.decode(35), {"pipe_mask": 0, "subway_mask": 15, "pipe_above": false, "station": true})
	for code in [-1, 0, 36, 255]: check_eq(underground_script.decode(code).pipe_mask | underground_script.decode(code).subway_mask, 0)

func test_endpoints_crossing_heights_station_marker_water_and_fingerprint() -> void:
	if underground_script == null: return
	var city := flat_city()
	var renderer = underground_script.new()
	renderer.bind_city(city)
	for mask in range(1, 16):
		city.underground.put(10, 10, mask)
		renderer.refresh()
		var faces: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var arms := 0
		for bit in [1, 2, 4, 8]: if mask & bit: arms += 1
		check_eq(faces.size(), arms * 6)
		for p in faces:
			if not mask & 1: check_ge(p.z, 10.4)
			if not mask & 2: check_lt(p.x, 10.7)
			if not mask & 4: check_lt(p.z, 10.7)
			if not mask & 8: check_ge(p.x, 10.4)
	for code in range(31, 35):
		city.underground.put(10, 10, code)
		renderer.refresh()
		var faces: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray=renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var steel_height := -INF
		var ballast_low := INF
		var ballast_high := -INF
		for i: int in faces.size():
			var color := colors[i]
			if Vector3(color.r-.72,color.g-.75,color.b-.71).length()<.006: steel_height=maxf(steel_height,faces[i].y)
			if Vector3(color.r-.44,color.g-.40,color.b-.33).length()<.006:
				ballast_low=minf(ballast_low,faces[i].y)
				ballast_high=maxf(ballast_high,faces[i].y)
		check(is_finite(steel_height),"crossing retains actual running rails")
		check_eq(faces[0].y > steel_height,code>=33,"pipe/subway crossing ordering")
		var ground := CityOverlay3D.surface_point(city,Vector2i(10,10),Vector2(.5,.5)).y
		var rail_height: float=renderer.LOWER_OFFSET if code>=33 else renderer.UPPER_OFFSET
		check_lt(absf(steel_height-ground-rail_height-.014),.00001,"rail height keeps intended utility layer")
		check_lt(absf(ballast_low-ground-rail_height+.062),.00001,"berm base is continuous at all offsets")
		check_lt(absf(ballast_high-ground-rail_height),.00001,"berm shoulder meets rail bed")
	city.underground.put(10, 10, 35)
	renderer.refresh()
	var faces: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_gt(faces.size(), 24, "station has all links and vertical marker")
	var top := -INF
	for p in faces: top = maxf(top, p.y)
	check_gt(top, faces[0].y + 0.4)
	check_eq(renderer.get_child_count(), 1)
	var before := SaveFormat.encode_city(city)
	var mesh: ArrayMesh = renderer.mesh_instance.mesh
	var builds: int = renderer.rebuild_count
	renderer.refresh()
	check_eq(renderer.mesh_instance.mesh, mesh)
	check_eq(renderer.rebuild_count, builds)
	check_eq(SaveFormat.encode_city(city), before)
	city.flags.set_bits(10, 10, TileFlags.WATERED, true)
	renderer.refresh()
	check_eq(renderer.rebuild_count, builds + 1)
	city.set_heights(10, 10, 6)
	renderer.refresh()
	check_eq(renderer.rebuild_count, builds + 2)
	renderer.clear()
	check_eq(renderer.mesh_instance.mesh, null)
	renderer.free()

func test_sloped_ribbons_follow_the_same_facets_and_pipe_service_color() -> void:
	if underground_script == null: return
	var city := flat_city()
	city.underground.put(10, 10, 15)
	city.terrain.put(10, 10, 5)
	var renderer = underground_script.new()
	renderer.bind_city(city)
	var arrays: Array = renderer.mesh_instance.mesh.surface_get_arrays(0)
	var faces: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(0, faces.size(), 3):
		var centroid := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		var ground := CityGeometry3D.point_on_ground(city, Vector2i(10, 10), Vector2(centroid.x - 10, centroid.z - 10))
		check(is_equal_approx(centroid.y, ground.y + renderer.LOWER_OFFSET), "utility triangle follows terrain facet")
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(absf(colors[0].r - renderer.PIPE_DRY.r) < 1.0 / 255.0 and absf(colors[0].g - renderer.PIPE_DRY.g) < 1.0 / 255.0)
	city.flags.set_bits(10, 10, TileFlags.WATERED, true)
	renderer.refresh()
	colors = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(absf(colors[0].r - renderer.PIPE_WET.r) < 1.0 / 255.0 and absf(colors[0].g - renderer.PIPE_WET.g) < 1.0 / 255.0)
	city.terrain.put(10, 10, Terrain.SURFACE)
	city.set_heights(10, 10, 2, 8)
	renderer.refresh()
	faces = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in faces: check(is_equal_approx(point.y, CityGeometry3D.water_surface_height(city, Vector2i(10, 10)) + renderer.LOWER_OFFSET))
	renderer.free()

func test_full_city_mesh_bound_and_simulation_state_preserved() -> void:
	if underground_script == null: return
	var city := flat_city()
	city.underground.data.fill(35)
	var sim := make_simulation(city)
	sim.speed = GameClock.Speed.PAUSED
	var city_before := SaveFormat.encode_city(city)
	var state_before := var_to_bytes(sim.snapshot())
	var renderer = underground_script.new()
	renderer.bind_city(city)
	check_eq(renderer.get_child_count(), 1)
	check_eq(renderer.mesh_instance.mesh.get_surface_count(), 1)
	var vertex_count: int=renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check_gt(vertex_count,City.WIDTH*City.HEIGHT*54,"stations include railway details")
	check_lt(vertex_count,City.WIDTH*City.HEIGHT*500,"detailed railway remains one bounded mesh")
	renderer.refresh()
	check_eq(SaveFormat.encode_city(city), city_before)
	check_eq(var_to_bytes(sim.snapshot()), state_before)
	renderer.free()
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim._system_index.clear()
	sim.free()
