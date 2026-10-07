# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Crossing supports must leave traffic lanes clear in visuals and traversal.
extends "res://tests/test_case.gd"


func test_crossing_poles_clear_both_orientations_of_each_transport_surface() -> void:
	# Literal canonical ids and widths: road, rail, elevated highway.
	for fixture: Array in [[67, true, .60, .04], [68, false, .60, .04],
			[71, true, .59, .055], [72, false, .59, .055],
			[79, true, .92, .38], [80, false, .92, .38]]:
		var city := flat_city()
		var cell := Vector2i(15, 15)
		city.building.putv(cell, fixture[0])
		var before := var_to_bytes(SaveFormat.encode_city(city))
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		_assert_clearance(layer, cell, fixture)
		# The retained regional projection must use the same geometry.
		layer.update_regions(city, [Rect2i(0, 0, 16, 16)])
		_assert_clearance(layer, cell, fixture)
		check_eq(var_to_bytes(SaveFormat.encode_city(city)), before, "rendering leaves the city untouched")
		layer.free()


func _assert_clearance(layer: CityNetworks3D, cell: Vector2i, fixture: Array) -> void:
	var ns: bool = fixture[1]
	var width: float = fixture[2]
	var floor_y: float = 4 * CityGeometry3D.HEIGHT + float(fixture[3])
	var poles: Array[MeshInstance3D] = []
	_collect_poles(layer, poles)
	check_eq(poles.size(), 2, "crossing %d has a support at each side" % fixture[0])
	var sides: Array[bool] = []
	for pole: MeshInstance3D in poles:
		var offset: float = pole.position.x - cell.x if ns else pole.position.z - cell.y
		check(absf(offset - .5) - CityNetworks3D.POWER_POLE_WIDTH / 2 > width / 2,
			"crossing %d visible pole is outside the transport surface" % fixture[0])
		sides.append(offset < .5)
	check(sides.has(true) and sides.has(false), "supports straddle the crossing")
	var physical := layer.physical_data()
	for along: float in [.1, .3, .5, .7, .9]:
		for across: float in [.3, .5, .7]:
			var point := Vector3(cell.x + across, floor_y + .2, cell.y + along) if ns \
				else Vector3(cell.x + along, floor_y + .2, cell.y + across)
			for box: Dictionary in physical.physical_boxes:
				check(not AABB(-box.size / 2, box.size).has_point(box.transform.affine_inverse() * point),
					"crossing %d collision leaves traffic lane clear at %s" % [fixture[0], point])
	# Wire still crosses the full cell above the lane, including both endpoints,
	# clearing the tallest road/rail vehicle (about 3.4 m = 0.21 tile) with margin.
	var faces := layer._faces
	if layer._region_initialized:
		faces = layer._regions[Vector2i.ZERO]._faces
	for edge: float in [0.0, 1.0]:
		var connected := false
		for point: Vector3 in faces:
			var along: float = point.x - cell.x if ns else point.z - cell.y
			if is_equal_approx(along, edge) and point.y > floor_y + .30:
				connected = true
		check(connected, "overhead wire reaches crossing edge %s" % edge)


func _collect_poles(node: Node, poles: Array[MeshInstance3D]) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			if is_equal_approx(child.mesh.size.x, CityNetworks3D.POWER_POLE_WIDTH) and is_equal_approx(child.mesh.size.z, CityNetworks3D.POWER_POLE_WIDTH):
				poles.append(child)
		_collect_poles(child, poles)


func test_standalone_lines_keep_their_center_support() -> void:
	for code: int in [14, 15, 20, 28, 92]:
		var city := flat_city()
		city.building.put(10, 10, code)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var poles: Array[MeshInstance3D] = []
		_collect_poles(layer, poles)
		check_eq(poles.size(), 1)
		if not poles.is_empty():
			check_eq(Vector2(poles[0].position.x, poles[0].position.z), Vector2(10.5, 10.5))
			if code != 92:
				# Distribution poles stay near two storeys, not three house heights.
				var height: float = poles[0].mesh.size.y
				check(height > .35 and height < .5, "line %d pole height %s tiles is street scale" % [code, height])
		layer.free()
