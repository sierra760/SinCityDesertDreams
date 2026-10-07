# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Incidents must remain distinct from ordinary traffic in the actual 3D path.
extends "res://tests/exploration/async_test_case.gd"

func test_riots_are_published_and_disaster_planes_keep_their_owner() -> void:
	var city := flat_city()
	city.building.put(40, 40, Buildings.ROAD_FIRST)
	var sim := make_simulation(city)
	var disasters := sim.get_system(&"disasters") as DisasterSystem
	disasters.load({"active": {"kind": "riot", "x": 40, "y": 40, "remaining": 8}, "riots": {"40,40": 1}})
	var source := CityEntityRecords.new()
	source.simulation = sim
	var records := source.gather()
	var riots := records.filter(func(r: Dictionary) -> bool: return r.kind == &"riot")
	check_eq(riots.size(), 1, "live riot reaches the 3D renderer")
	if not riots.is_empty(): check_eq(riots[0].pos, Vector2(40, 40))
	disasters.load({"active": {"kind": "plane_crash", "x": 40, "y": 40, "remaining": 8},
		"entities": [{"kind": "plane", "x": 15, "y": 20, "frame": 1, "heading": 2}]})
	var planes := source.gather().filter(func(r: Dictionary) -> bool: return r.kind == &"plane")
	check_eq(planes.size(), 1)
	if not planes.is_empty(): check_eq(planes[0].get("source", &""), &"disasters", "crash plane bypasses ordinary traffic filtering")
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim.free()

func test_moving_disasters_have_owned_models_and_leave_no_generic_cars() -> void:
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(flat_city())
	var records: Array = []
	for kind: StringName in [&"tornado", &"monster", &"hurricane", &"beam", &"riot", &"plane"]:
		records.append({"kind": kind, "pos": Vector2(30 + records.size() * 4, 40), "source": &"disasters", "frame": 3})
	feedback.sync_records(records)
	var layer := feedback.get_node_or_null("Disasters") as Node3D
	check(layer != null, "dedicated incident geometry exists")
	check(feedback.traffic.multimesh == null, "hazards never turn into generic vehicle boxes")
	if layer != null:
		check_eq(layer.get_child_count(), 6, "every live incident is represented")
		for visual: Node3D in layer.get_children():
			check(not visual.find_children("*", "MeshInstance3D", true, false).is_empty(), "incident has visible original geometry")
			check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "presentation adds no physical obstacles")
		var first := layer.get_child(0)
		records[0].pos = Vector2(33, 41)
		feedback.sync_records(records)
		check_eq(layer.get_child(0), first, "moving incident reuses visual resources")
		check_eq((first as Node3D).position.x, 33.5, "visual follows live position")
		feedback.sync_records([])
		check_eq(layer.get_child_count(), 0, "ended disasters disappear immediately")
	feedback.free()
	await process_frame

func test_incident_rendering_preserves_city_and_rng() -> void:
	var city := flat_city()
	var payload := SaveFormat.encode_city(city)
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([{ "kind": &"monster", "pos": Vector2(30, 40), "source": &"disasters" },
		{ "kind": &"riot", "pos": Vector2(INF, 40), "source": &"disasters" }])
	check_eq(SaveFormat.encode_city(city), payload, "incident models are read-only")
	feedback.clear()
	var layer := feedback.get_node_or_null("Disasters")
	if layer != null: check_eq(layer.get_child_count(), 0, "city replacement clears old incidents")
	feedback.free()
	await process_frame

func test_plane_and_monster_face_their_clockwise_simulation_heading() -> void:
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(flat_city())
	for example: Array in [[2, Vector3.RIGHT], [6, Vector3.LEFT]]:
		feedback.sync_records([{"kind": &"plane", "pos": Vector2(30, 40), "source": &"disasters", "heading": example[0]},
			{"kind": &"monster", "pos": Vector2(34, 40), "source": &"disasters", "heading": example[0]}])
		for visual: Node3D in feedback.disaster_visuals.get_children():
			check((visual.basis * Vector3.FORWARD).is_equal_approx(example[1]), "directional incident faces its travel direction")
			(visual as CityDisasterVisual3D)._process(0.5)
			check((visual.basis * Vector3.FORWARD).is_equal_approx(example[1]), "art motion preserves simulation heading")
	feedback.free()
	await process_frame

func test_disaster_assets_are_imported_editable_model_exports() -> void:
	for kind: StringName in [&"tornado", &"monster", &"hurricane", &"beam", &"riot", &"plane", &"fire"]:
		var path := "res://assets/desert-dreams-disasters/%s.glb" % kind
		check(ResourceLoader.exists(path), "authored Blender export exists: " + String(kind))
		var visual := CityDisasterVisual3D.new()
		visual.build(kind)
		root.add_child(visual)
		check_eq(visual.get_meta("authored_model", ""), path, "actual visual uses the authored resource")
		var meshes := visual.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), "model has rendered mesh parts")
		for part: MeshInstance3D in meshes:
			check(part.mesh.get_aabb().size.is_finite(), "mesh bounds are finite")
			for surface in part.mesh.get_surface_count():
				var arrays := part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				check_eq(normals.size(), vertices.size(), "export has normals")
				check_eq(uv.size(), vertices.size(), "editable model retains UV mapping")
		check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "incident art adds no obstacles")
		visual.free()
	await process_frame

func test_authored_fire_retains_incident_marker_contract() -> void:
	var city := flat_city()
	city.stamp_building(30, 40, Buildings.RES_1X1_FIRST)
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([{ "kind": &"fire", "pos": Vector2(30, 40), "source": &"disasters" }])
	check_eq(feedback.marker_count(), 1, "one flame marker per burning tile")
	var flame := feedback.markers.get_child(0) as Node3D
	check_eq(flame.get_meta("authored_model", ""), "res://assets/desert-dreams-disasters/fire.glb", "fire uses its Blender model")
	check(flame.position.y >= CityGeometry3D.surface_height(city, Vector2i(30, 40)), "flame starts on a supported surface")
	feedback.sync_records([])
	check_eq(feedback.marker_count(), 0, "extinguished flame disappears")
	feedback.free()
	await process_frame

func test_fire_visual_follows_current_roof_and_demolition() -> void:
	var city := flat_city()
	city.stamp_building(30, 40, Buildings.RES_1X1_FIRST)
	var feedback := CityFeedback3D.new()
	feedback.catalog = CityModelCatalog.new()
	check_eq(feedback.catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	root.add_child(feedback)
	feedback.bind_city(city)
	var records := [{"kind": &"fire", "pos": Vector2(30, 40), "source": &"disasters"}]
	feedback.sync_records(records)
	var roof := CityGeometry3D.surface_height(city, Vector2i(30, 40)) + float(feedback.catalog.entries[Buildings.RES_1X1_FIRST].height)
	check_eq((feedback.markers.get_child(0) as Node3D).position.y, roof, "flame starts at the authored roof")
	city.clear_footprint(30, 40)
	feedback.sync_records(records)
	check_eq((feedback.markers.get_child(0) as Node3D).position.y, CityGeometry3D.surface_height(city, Vector2i(30, 40)), "remaining fire moves to the cleared ground")
	feedback.free()
	await process_frame

func test_fire_uses_the_entire_sloped_building_foundation() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	city.stamp_building(30, 40, Buildings.RES_2X2_FIRST)
	city.terrain_surface.set_vertex(32, 42, 6)
	var feedback := CityFeedback3D.new()
	feedback.catalog = CityModelCatalog.new()
	check_eq(feedback.catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([{"kind": &"fire", "pos": Vector2(31, 40), "source": &"disasters"}])
	var roof := 6 * CityGeometry3D.HEIGHT + float(feedback.catalog.entries[Buildings.RES_2X2_FIRST].height)
	check(absf((feedback.markers.get_child(0) as Node3D).position.y - roof) < 0.000001, "fire on a non-anchor tile clears the whole rendered lot")
	feedback.free()
	await process_frame

func test_fire_updates_after_corner_only_and_encoded_terrain_edits() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	city.stamp_building(30, 40, Buildings.RES_1X1_FIRST)
	var feedback := CityFeedback3D.new()
	feedback.catalog = CityModelCatalog.new()
	check_eq(feedback.catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	root.add_child(feedback)
	feedback.bind_city(city)
	var records := [{"kind": &"fire", "pos": Vector2(30, 40), "source": &"disasters"}]
	feedback.sync_records(records)
	var altitude_before := city.altitude.data.duplicate()
	city.terrain_surface.set_vertex(30, 40, 5)
	city.terrain_surface.set_vertex(30, 41, 5)
	feedback.sync_records(records)
	check_eq(city.altitude.data, altitude_before, "corner edit retains tile minimum bytes")
	var roof := 5 * CityGeometry3D.HEIGHT + float(feedback.catalog.entries[Buildings.RES_1X1_FIRST].height)
	check(absf((feedback.markers.get_child(0) as Node3D).position.y - roof) < 0.000001, "corner-only edit raises the flame with the rigid roof")
	city.terrain_surface = null
	feedback.sync_records(records)
	var before := (feedback.markers.get_child(0) as Node3D).position.y
	# Raised cap changes visible corners without modifying altitude words.
	for y in range(39, 42):
		for x in range(29, 32): city.terrain.put(x, y, Terrain.PLATEAU)
	feedback.sync_records(records)
	check((feedback.markers.get_child(0) as Node3D).position.y > before, "encoded terrain edit refreshes the flame")
	feedback.free()
	await process_frame

func test_imported_flames_retain_the_authored_emission_palette() -> void:
	var visual := CityDisasterVisual3D.new()
	visual.build(&"fire")
	var strengths: Dictionary = {}
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		check_eq((part.material_override as ShaderMaterial).shader, CityDisasterVisual3D.fire_material().shader, "shared authored fire shader with independent playback time")
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var properties: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			check(not properties.is_empty(), "export carries each vertex's emission and roughness")
			for value: Vector2 in properties:
				strengths[roundi(value.x * 1000)] = true
				check(value.y >= 0.0 and value.y <= 1.0, "authored roughness remains valid")
	for strength in [0, 150, 300, 600, 1200]:
		check(strengths.has(strength), "matte smoke and four distinct warm emission strengths survive batching")
	for name: StringName in [&"core_emission", &"amber_emission", &"orange_emission", &"coal_emission"]:
		var color: Vector3 = CityDisasterVisual3D.fire_material().get_shader_parameter(name)
		check(color.x > color.z + 0.1, "actual shader palette retains warm emission")
	visual.free()
