# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Runtime orientation and marine placement regressions from real city imports.
extends "res://tests/test_case.gd"

var _catalog: CityModelCatalog


func before_all() -> void:
	_catalog = CityModelCatalog.new()
	check_eq(_catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)


func _model(layer: CityBuildings3D, cell: Vector2i) -> Node3D:
	for child: Node3D in layer.get_children():
		if child.get_meta("cell", Vector2i(-1, -1)) == cell:
			return child
	return null


func _stamp(city: City, cell: Vector2i, code: int, axis: bool) -> void:
	city.stamp_building(cell.x, cell.y, code)
	city.set_flag(cell.x, cell.y, RotationMapper.AXIS_FLAG, axis)


func _water(city: City, cell: Vector2i, ground: int = 3, level: int = 5) -> void:
	city.terrain.putv(cell, Terrain.SURFACE)
	city.set_heights(cell.x, cell.y, ground, level)


func _parallel(actual: Vector3, expected: Vector3, message: String) -> void:
	check(absf(actual.normalized().dot(expected)) > 0.999, message)


func test_contiguous_runs_follow_their_cells_even_with_saved_axis_conventions() -> void:
	# Saved east-west runways can use either AXIS convention.
	# Native port development also leaves AXIS clear for either direction.
	for code: int in [Buildings.RUNWAY, Buildings.PIER]:
		for axis: bool in [false, true]:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var city := flat_city()
				for i: int in 3:
					var cell := Vector2i(10, 10) + step * i
					_stamp(city, cell, code, axis)
					if code == Buildings.PIER:
						_water(city, cell)
				var before := SaveFormat.encode_city(city)
				var layer := CityBuildings3D.new()
				layer.rebuild(city, _catalog)
				for i: int in 3:
					var model := _model(layer, Vector2i(10, 10) + step * i)
					var authored_axis := model.basis.z if code == Buildings.RUNWAY else model.basis.x
					_parallel(authored_axis, Vector3(step.x, 0, step.y), "model %d axis %s follows contiguous %s run" % [code, axis, step])
				check_eq(SaveFormat.encode_city(city), before, "presentation does not rewrite imported flags")
				layer.free()


func test_isolated_directional_models_use_axis_flag_without_rotating_other_buildings() -> void:
	for code: int in [Buildings.RUNWAY, Buildings.RUNWAY_CROSS, Buildings.PIER]:
		var city := flat_city()
		_stamp(city, Vector2i(10, 10), code, false)
		_stamp(city, Vector2i(14, 10), code, true)
		_stamp(city, Vector2i(18, 10), Buildings.RES_1X1_FIRST, true)
		var layer := CityBuildings3D.new()
		layer.rebuild(city, _catalog)
		var clear_model := _model(layer, Vector2i(10, 10))
		var set_model := _model(layer, Vector2i(14, 10))
		var authored_axis := Vector3.RIGHT if code == Buildings.PIER else Vector3.BACK
		_parallel(clear_model.basis * authored_axis, Vector3.RIGHT, "clear AXIS uses east-west fallback")
		_parallel(set_model.basis * authored_axis, Vector3.BACK, "set AXIS uses north-south fallback")
		check(_model(layer, Vector2i(18, 10)).basis.is_equal_approx(Basis.IDENTITY), "ordinary lots retain authored orientation")
		for cell: Vector2i in [Vector2i(10, 10), Vector2i(14, 10)]:
			var query := _model(layer, cell).get_node("BuildingQuery") as StaticBody3D
			check_eq(query.collision_layer, 2)
			check_eq(query.get_meta("cell"), cell)
		layer.free()


func test_marine_models_use_water_even_when_anchor_ground_is_higher_or_dry() -> void:
	for dry_anchor: bool in [false, true]:
		var city := flat_city(20000, 22)
		city.stamp_building(10, 10, Buildings.MARINA)
		for y: int in range(10, 13):
			for x: int in range(10, 13):
				_water(city, Vector2i(x, y), 21, 21)
		# A declared shore fixture: 0x33, ground 21, water 21; center ground 21.5.
		city.terrain.put(10, 10, Terrain.SURFACE | Terrain.SLOPE_E)
		if dry_anchor:
			city.terrain.put(10, 10, Terrain.FLAT)
			city.set_heights(10, 10, 22, 0)
		var before := SaveFormat.encode_city(city)
		var layer := CityBuildings3D.new()
		layer.rebuild(city, _catalog)
		var model := _model(layer, Vector2i(10, 10))
		check(is_equal_approx(model.position.y, 21 * 0.6123724357 + 0.025), "marina floats at the lot's water level, not the anchor's shore")
		check_eq(SaveFormat.encode_city(city), before)
		layer.free()


func test_marina_rear_landing_faces_the_dry_bank_on_each_side() -> void:
	for shore: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var city := flat_city(20000, 4)
		city.stamp_building(10, 10, Buildings.MARINA)
		for y: int in range(10, 13):
			for x: int in range(10, 13):
				_water(city, Vector2i(x, y), 4, 5)
		for i: int in 3:
			var cell := Vector2i(11, 11) + shore
			cell += Vector2i(shore.y, -shore.x) * (i - 1)
			city.terrain.putv(cell, Terrain.FLAT)
			city.set_heights(cell.x, cell.y, 5, 0)
		var layer := CityBuildings3D.new()
		layer.rebuild(city, _catalog)
		var model := _model(layer, Vector2i(10, 10))
		var rear := model.basis * Vector3.FORWARD
		check(rear.dot(Vector3(shore.x, 0, shore.y)) > 0.999, "marina rear landing faces %s shore" % shore)
		layer.free()


func test_connected_piers_fill_deck_gap_only_along_matching_level_run() -> void:
	for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		var city := flat_city()
		for i: int in 4:
			var cell := Vector2i(10, 10) + step * i
			_stamp(city, cell, Buildings.PIER, true)
			_water(city, cell, 3, 5 if i < 3 else 6)
		var layer := CityBuildings3D.new()
		layer.rebuild(city, _catalog)
		for i: int in 4:
			var model := _model(layer, Vector2i(10, 10) + step * i)
			var join := model.get_node_or_null("PierJoin") as MeshInstance3D
			if i < 2:
				check(join != null, "matching pier deck gap is filled")
				if join != null:
					var box := join.mesh as BoxMesh
					check_ge(box.size.x, 0.25, "join covers the four-meter authored gap")
					check(is_equal_approx(join.position.y + box.size.y * 0.5, 1.62 / 16.0), "join top is flush with authored deck")
					var query := model.get_node("BuildingQuery") as StaticBody3D
					check_ge(query.get_child_count(), 2, "gap remains queryable as its canonical pier")
			else:
				check(join == null, "unequal water levels and open endpoints are not connected")
		layer.free()


func test_neighboring_piers_on_perpendicular_axes_do_not_gain_a_side_join() -> void:
	var city := flat_city()
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10), Vector2i(12, 11), Vector2i(12, 12)]:
		_stamp(city, cell, Buildings.PIER, true)
		_water(city, cell)
	var layer := CityBuildings3D.new()
	layer.rebuild(city, _catalog)
	check(_model(layer, Vector2i(10, 10)).get_node_or_null("PierJoin") != null, "straight leading pair connects")
	check(_model(layer, Vector2i(11, 10)).get_node_or_null("PierJoin") == null, "the perpendicular deck does not receive a side join")
	check(_model(layer, Vector2i(12, 10)).get_node_or_null("PierJoin") != null, "north-south leading pair connects")
	layer.free()


func _render_points(node: Node, transform: Transform3D, boats: PackedVector3Array, bounds: Array[Vector3]) -> void:
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = transform * node.mesh.get_aabb()
		bounds.append(box.position)
		bounds.append(box.end)
		var source_names: Array = node.get_meta("source_node_names", [])
		for surface: int in node.mesh.get_surface_count():
			var source_name := String(source_names[surface]) if surface < source_names.size() else String(node.name)
			if not source_name.ends_with(" boat"): continue
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				boats.append(transform * vertex)
	for child: Node in node.get_children():
		_render_points(child, transform, boats, bounds)


func test_declared_narrow_shore_fixture_keeps_boats_clear_and_geometry_inside_lot() -> void:
	var city := flat_city(20000, 22)
	var anchor := Vector2i(10, 10)
	city.stamp_building(anchor.x, anchor.y, Buildings.MARINA)
	for y: int in range(10, 13):
		_water(city, Vector2i(10, y), 21, 21)
	check_marina_lot(city, anchor, "synthetic one-column water berth")


func test_flat_dry_bank_is_not_used_as_water_just_because_boats_clear_it() -> void:
	var city := flat_city(20000, 5)
	var anchor := Vector2i(10, 10)
	city.stamp_building(anchor.x, anchor.y, Buildings.MARINA)
	for y: int in range(10, 13):
		_water(city, Vector2i(10, y), 4, 5)
	check_marina_lot(city, anchor, "synthetic dry bank at water elevation")


func test_single_corner_water_berth_preserves_all_boats_without_leaving_lot() -> void:
	var city := flat_city(20000, 5)
	var anchor := Vector2i(10, 10)
	city.stamp_building(anchor.x, anchor.y, Buildings.MARINA)
	_water(city, Vector2i(12, 12), 4, 5)
	check_marina_lot(city, anchor, "synthetic southeast corner berth")


## Checks that a marina lot sits on its berth without changing city data.
func check_marina_lot(city: City, anchor: Vector2i, label: String) -> Dictionary:
	var before := var_to_bytes([city.terrain.data, city.altitude.data, city.building.data, city.zone.data])
	var layer := CityBuildings3D.new()
	layer.rebuild(city, _catalog)
	var model := _model(layer, anchor)
	var boats := PackedVector3Array()
	var bounds: Array[Vector3] = []
	_render_points(model, Transform3D.IDENTITY, boats, bounds)
	check(not boats.is_empty(), "actual authored boat hull vertices are checked")
	var penetration := 0.0
	var dry_points := 0
	for point: Vector3 in boats:
		var cell := Vector2i(floori(point.x), floori(point.z))
		var offset := Vector2(point.x - cell.x, point.z - cell.y)
		if not city.is_water(cell.x, cell.y):
			dry_points += 1
		var height := CityGeometry3D.visible_ground_height(city, cell, offset)
		penetration = maxf(penetration, height - point.y)
	check(penetration <= 0.005, "%s %s boat penetration %.4f" % [label, anchor, penetration])
	check_eq(dry_points, 0, "%s %s boat hull stays over the water-bearing cells" % [label, anchor])
	for point: Vector3 in bounds:
		check(point.x >= anchor.x - 0.001 and point.x <= anchor.x + 3.001 and point.z >= anchor.y - 0.001 and point.z <= anchor.y + 3.001, "%s %s stays inside its canonical lot" % [label, anchor])
	var fit := model.get_node_or_null("MarineFit") as Node3D
	if fit != null:
		check_ge(fit.scale.x, 0.45 - 0.000001, "even a one-cell berth retains a substantial marina (float32 transform tolerance)")
		check(fit.scale.is_equal_approx(Vector3.ONE * fit.scale.x), "fit preserves authored proportions")
	check_eq(var_to_bytes([city.terrain.data, city.altitude.data, city.building.data, city.zone.data]), before)
	var query := model.get_node("BuildingQuery").get_child(0) as CollisionShape3D
	check(is_equal_approx((query.shape as BoxShape3D).size.x, 2.55), "query retains full canonical footprint")
	var report := {"scale": fit.scale.x if fit != null else 1.0, "yaw_degrees": rad_to_deg(model.rotation.y),
		"local_offset": [fit.position.x, fit.position.z] if fit != null else [0.0, 0.0], "dry_boat_vertices": dry_points, "penetration": penetration}
	layer.free()
	return report
