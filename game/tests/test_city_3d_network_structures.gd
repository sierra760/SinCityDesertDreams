# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Network surfaces remain connected across authored structure footprints.
extends "res://tests/test_case.gd"

const PAVEMENT := Color(0.34, 0.38, 0.40)
const STEEL := Color(0.72, 0.75, 0.71)


func test_highway_corner_is_one_connected_two_cell_turn() -> void:
	var city := flat_city()
	# An odd anchor proves grouping follows the footprint flags, not map parity.
	var anchor := Vector2i(35, 89)
	var pivots := [Vector2(37, 89), Vector2(37, 91), Vector2(35, 91), Vector2(35, 89)]
	var angles := [PI, -PI / 2.0, 0.0, PI / 2.0]
	for corner: int in 4:
		for dy: int in 2:
			for dx: int in 2:
				city.building.put(anchor.x + dx, anchor.y + dy, 101 + corner)
				city.zone.put(anchor.x + dx, anchor.y + dy, Zones.corner_flags_for(dx, dy, 2, 2))
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		# Independent concentric centerlines cross each tile boundary continuously.
		for radius: float in [0.5, 1.5]:
			var gaps := 0
			for step: int in 129:
				var angle: float = angles[corner] - step * PI / 256.0
				var point: Vector2 = pivots[corner] + Vector2(cos(angle), sin(angle)) * radius
				if is_nan(surface_y(layer, point, PAVEMENT)):
					gaps += 1
			check_eq(gaps, 0, "both carriageways connect throughout 2x2 turn %d" % corner)
		layer.free()


func test_imported_highway_corner_flags_form_complete_even_and_odd_blocks() -> void:
	# Raw imported flags are NW=128, NE=16, SW=64, SE=32. Do not derive these
	# from the native Zones constants: the two retained encodings differ.
	var imported_flags := [[128, 16], [64, 32]]
	for anchor: Vector2i in [Vector2i(34, 88), Vector2i(35, 89)]:
		for corner: int in 4:
			var city := flat_city()
			for dy: int in 2:
				for dx: int in 2:
					city.building.put(anchor.x + dx, anchor.y + dy, 101 + corner)
					city.zone.put(anchor.x + dx, anchor.y + dy, imported_flags[dy][dx])
			var before := var_to_bytes([city.building.data, city.zone.data, city.flags.data])
			var layer := CityNetworks3D.new()
			layer.rebuild(city)
			var pivot: Vector2 = Vector2(anchor) + [Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2.ZERO][corner]
			var angle: float = [PI, -PI / 2.0, 0.0, PI / 2.0][corner]
			for radius: float in [0.5, 1.5]:
				var gaps := 0
				for step: int in 129:
					var point := pivot + Vector2(cos(angle - step * PI / 256.0), sin(angle - step * PI / 256.0)) * radius
					if is_nan(surface_y(layer, point, PAVEMENT)):
						gaps += 1
				check_eq(gaps, 0, "both imported carriageways connect throughout corner %d at %s" % [101 + corner, anchor])
			check_eq(var_to_bytes([city.building.data, city.zone.data, city.flags.data]), before,
				"recognizing imported footprint flags is read-only")
			layer.free()


func test_adjacent_imported_highway_turns_join_across_the_s_curve() -> void:
	var city := flat_city()
	var imported_flags := [[128, 16], [64, 32]]
	for anchor: Vector2i in [Vector2i(28, 78), Vector2i(30, 78)]:
		for dy: int in 2:
			for dx: int in 2:
				city.building.put(anchor.x + dx, anchor.y + dy, 101 if anchor.x == 28 else 103)
				city.zone.put(anchor.x + dx, anchor.y + dy, imported_flags[dy][dx])
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	for lane: float in [78.5, 79.5]:
		var left := surface_y(layer, Vector2(29.999, lane), PAVEMENT)
		var right := surface_y(layer, Vector2(30.001, lane), PAVEMENT)
		check(not is_nan(left) and not is_nan(right), "both S-curve carriageways cross the shared block edge")
		check(is_equal_approx(left, right), "the connected turn has no step at the shared block edge")
	layer.free()


func test_highway_footprint_rejects_partial_and_mismatched_imported_blocks() -> void:
	var city := flat_city()
	var anchor := Vector2i(35, 89)
	var imported_flags := [[128, 16], [64, 32]]
	for dy: int in 2:
		for dx: int in 2:
			city.building.put(anchor.x + dx, anchor.y + dy, 101)
			city.zone.put(anchor.x + dx, anchor.y + dy, imported_flags[dy][dx])
	var last := anchor + Vector2i.ONE
	city.building.putv(last, 0)
	check_eq(CityNetworks3D.highway_footprint(city, anchor, 101), Vector2i(-1, -1), "a missing quadrant is not a full structure")
	city.building.putv(last, 102)
	check_eq(CityNetworks3D.highway_footprint(city, anchor, 101), Vector2i(-1, -1), "different corner codes cannot be merged")
	city.building.putv(last, 101)
	city.zone.putv(last, 128)
	check_eq(CityNetworks3D.highway_footprint(city, anchor, 101), Vector2i(-1, -1), "the complete imported flag pattern is required")


func test_ramps_reach_their_road_and_highway_edges_for_both_axes() -> void:
	var city := flat_city()
	# Independent direction pairs from the public ramp orientation contract.
	var pairs := [[Vector2.RIGHT, Vector2.UP], [Vector2.LEFT, Vector2.UP],
		[Vector2.LEFT, Vector2.DOWN], [Vector2.RIGHT, Vector2.DOWN]]
	for axis: bool in [false, true]:
		for index: int in 4:
			city.building.put(10, 10, 93 + index)
			city.flags.put(10, 10, RotationMapper.AXIS_FLAG if axis else 0)
			var road: Vector2 = pairs[index][0]
			var high: Vector2 = pairs[index][1]
			if axis:
				road = Vector2(road.y, road.x)
				high = Vector2(high.y, high.x)
			var layer := CityNetworks3D.new()
			layer.rebuild(city)
			var low_y := surface_y(layer, Vector2(10.5, 10.5) + road * 0.5, PAVEMENT)
			var high_y := surface_y(layer, Vector2(10.5, 10.5) + high * 0.5, PAVEMENT)
			check(is_equal_approx(low_y, 4 * CityGeometry3D.HEIGHT + 0.04), "ramp %d axis %s connects to ground road" % [index, axis])
			check(is_equal_approx(high_y, 4 * CityGeometry3D.HEIGHT + 0.38), "ramp %d axis %s rises to the lowered highway" % [index, axis])
			layer.free()


func test_ramps_match_full_road_pavement_and_shoulder_width_throughout() -> void:
	var city := flat_city()
	var pairs := [[Vector2.RIGHT,Vector2.UP],[Vector2.LEFT,Vector2.UP],[Vector2.LEFT,Vector2.DOWN],[Vector2.RIGHT,Vector2.DOWN]]
	for axis: bool in [false,true]:
		for index: int in 4:
			city.flags.put(10,10,RotationMapper.AXIS_FLAG if axis else 0)
			var road: Vector2 = pairs[index][0]
			var high: Vector2 = pairs[index][1]
			if axis:
				road = Vector2(road.y,road.x)
				high = Vector2(high.y,high.x)
			var pivot := Vector2(10.5,10.5)+(road+high)*.5
			var layer := CityNetworks3D.new()
			layer._ramp(city,Vector2i(10,10),93+index)
			var missing_pavement := 0
			var excess_pavement := 0
			var missing_shoulder := 0
			for step: int in 33:
				var radial := (-high).rotated((-high).angle_to(-road)*step/32.0)
				for across: float in [-.299,.299]:
					if is_nan(surface_y(layer,pivot+radial*(.5+across),PAVEMENT)): missing_pavement += 1
				for across: float in [-.302,.302]:
					if not is_nan(surface_y(layer,pivot+radial*(.5+across),PAVEMENT)): excess_pavement += 1
				for across: float in [-.335,.335]:
					if is_nan(surface_y(layer,pivot+radial*(.5+across),Color(.74,.72,.65))): missing_shoulder += 1
			check_eq(missing_pavement,0,"full .60-tile road width at both mouths and every curve section")
			check_eq(excess_pavement,0,"pavement keeps the ordinary road's exact width")
			check_eq(missing_shoulder,0,"both shoulders match the road's .675-tile footprint")
			layer.free()


func test_ramp_pavement_keeps_inner_turn_radius_and_bounds_every_face_grade() -> void:
	var city := flat_city()
	var pivots := [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
	for axis: bool in [false, true]:
		for index: int in 4:
			city.flags.put(10, 10, RotationMapper.AXIS_FLAG if axis else 0)
			var pivot: Vector2 = pivots[index]
			if axis:
				pivot = Vector2(pivot.y, pivot.x)
			pivot += Vector2(10, 10)
			var layer := CityNetworks3D.new()
			layer._ramp(city, Vector2i(10, 10), 93 + index)
			var minimum_radius := INF
			var maximum_grade := 0.0
			for i: int in range(0, layer._faces.size(), 3):
				if not layer._colors[i].is_equal_approx(PAVEMENT):
					continue
				var a: Vector3 = layer._faces[i]
				var b: Vector3 = layer._faces[i + 1]
				var c: Vector3 = layer._faces[i + 2]
				for p: Vector3 in [a, b, c]:
					minimum_radius = minf(minimum_radius, Vector2(p.x, p.z).distance_to(pivot))
				var normal := (b - a).cross(c - a)
				var grade := rad_to_deg(atan2(Vector2(normal.x, normal.z).length(), absf(normal.y)))
				maximum_grade = maxf(maximum_grade, grade)
			check_ge(minimum_radius, 0.19, "full-width inner edge retains a positive turn radius")
			print("RAMP_GRADE index=%d axis=%s maximum_degrees=%.3f" % [index,axis,maximum_grade])
			# A full-width .60 road has a tighter inner edge than the former
			# narrow lane. Keep every pavement face below the 55-degree limit.
			check_lt(maximum_grade, 52.0, "full-width pavement remains below the driving slope limit")
			layer.free()


func test_bridge_deck_ignores_submerged_slopes_and_joins_its_banks() -> void:
	var city := flat_city()
	city.building.put(9, 10, 30)
	city.building.put(16, 10, 30)
	for x: int in range(10, 16):
		city.building.put(x, 10, 87)
		city.flags.put(x, 10, RotationMapper.AXIS_FLAG)
		city.terrain.put(x, 10, Terrain.SHORE | (Terrain.SLOPE_E if x % 2 else Terrain.SLOPE_W))
		city.set_heights(x, 10, 1 + x % 3, 3)
	var before := var_to_bytes([city.altitude.data, city.terrain.data, city.building.data, city.flags.data, city.zone.data])
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	for x: int in range(10, 16):
		for along: float in [0.0, 0.5, 1.0]:
			var height := surface_y(layer, Vector2(x + along, 10.5), PAVEMENT)
			check(is_equal_approx(height, 4 * CityGeometry3D.HEIGHT + 0.04), "bridge pavement stays at bank height over varied seabed")
	check_eq(var_to_bytes([city.altitude.data, city.terrain.data, city.building.data, city.flags.data, city.zone.data]), before)
	layer.free()


func test_imported_rail_slopes_join_both_axes_of_a_bridge() -> void:
	# Actual import codes: 46 west, 47 north, 48 east, 49 south.
	# Each dry approach rises toward the outer bank and meets a lower bridge.
	for ew: bool in [false, true]:
		var city := flat_city()
		var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
		var across := Vector2(0, 0.156) if ew else Vector2(0.156, 0)
		var start := Vector2i(10, 10)
		var near_bank := start - direction
		var far_bank := start + direction * 6
		city.building.putv(near_bank, 46 if ew else 47)
		city.building.putv(far_bank, 48 if ew else 49)
		city.terrain.putv(near_bank, Terrain.SLOPE_W if ew else Terrain.SLOPE_N)
		city.terrain.putv(far_bank, Terrain.SLOPE_E if ew else Terrain.SLOPE_S)
		city.set_heights(near_bank.x, near_bank.y, 3, 0)
		city.set_heights(far_bank.x, far_bank.y, 3, 0)
		for i: int in 6:
			var cell := start + direction * i
			city.building.putv(cell, 90 if i in [0, 5] else 91)
			city.flags.putv(cell, RotationMapper.AXIS_FLAG if ew else 0)
			city.terrain.putv(cell, Terrain.SURFACE)
			city.set_heights(cell.x, cell.y, 1, 2)
		var before := var_to_bytes([city.altitude.data, city.terrain.data, city.building.data, city.flags.data, city.zone.data])
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		for bank: Vector2i in [near_bank, far_bank]:
			for side: float in [-1.0, 1.0]:
				var missing := 0
				for step: int in 17:
					var point := Vector2(bank) + Vector2(0.5, 0.5) + Vector2(direction) * (step / 16.0 - 0.5) + across * side
					if is_nan(surface_y(layer, point, STEEL)):
						missing += 1
				check_eq(missing, 0, "imported slope %d has two straight rails throughout its approach" % city.building.atv(bank))
		for side: float in [-1.0, 1.0]:
			var near_joint := Vector2(start) + Vector2(0.5, 0.5) - Vector2(direction) * 0.5 + across * side
			var far_joint := Vector2(far_bank) + Vector2(0.5, 0.5) - Vector2(direction) * 0.5 + across * side
			for joint: Vector2 in [near_joint, far_joint]:
				var bank_height := surface_y(layer, joint - Vector2(direction) * 0.001, STEEL)
				var deck_height := surface_y(layer, joint + Vector2(direction) * 0.001, STEEL)
				check(not is_nan(bank_height) and not is_nan(deck_height), "both sides of the bridge joint retain actual steel surfaces")
				check_lt(absf(bank_height - deck_height), 0.001, "rail approach and bridge meet without a height step")
		check_eq(var_to_bytes([city.altitude.data, city.terrain.data, city.building.data, city.flags.data, city.zone.data]), before,
			"projecting approaches cannot change the imported city")
		layer.free()


func test_highway_supports_leave_the_lower_road_and_rail_clear() -> void:
	for code: int in [75, 76, 77, 78]:
		var city := flat_city()
		city.building.put(10, 10, code)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var ground := 4 * CityGeometry3D.HEIGHT
		var obstructed := false
		for child: Node in layer.get_children():
			if not child is MeshInstance3D or not child.mesh is BoxMesh:
				continue
			var box: AABB = child.mesh.get_aabb()
			box.position += child.position
			# All crossing centerlines need a clear passage above their surface.
			for t: float in [0.1, 0.3, 0.5, 0.7, 0.9]:
				var p := Vector3(10 + t, ground + 0.2, 10.5) if code in [75, 77] else Vector3(10.5, ground + 0.2, 10 + t)
				obstructed = obstructed or box.has_point(p)
		check(not obstructed, "highway %d has no support inside its lower transport path" % code)
		layer.free()


func test_tunnel_pavement_enters_hill_at_level_height() -> void:
	for index: int in 4:
		var city := flat_city()
		city.building.put(10, 10, 63 + index)
		city.terrain.put(10, 10, Terrain.SLOPE_W + index)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var inward: Vector2 = [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN][index]
		for t: float in [-0.4, 0.0, 0.25]:
			var height := surface_y(layer, Vector2(10.5, 10.5) + inward * t, PAVEMENT)
			check(is_equal_approx(height, 4 * CityGeometry3D.HEIGHT + 0.04), "tunnel floor is level instead of climbing the hill")
		check_gt(layer.get_child_count(), 1, "tunnel has an actual entrance surround")
		layer.free()


func test_subway_rails_descend_toward_the_underground_mouth() -> void:
	for index: int in 4:
		var city := flat_city()
		city.building.put(10, 10, 108 + index)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var outward: Vector2 = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][index]
		var cross := Vector2(-outward.y, outward.x)
		var outside_y := surface_y(layer, Vector2(10.5, 10.5) + outward * 0.49 + cross * 0.156, STEEL)
		var inside_y := surface_y(layer, Vector2(10.5, 10.5) - outward * 0.25 + cross * 0.156, STEEL)
		check(not is_nan(outside_y) and not is_nan(inside_y), "both ends retain steel rail surfaces")
		check_gt(outside_y - inside_y, 0.3, "subway track descends below the terrain")
		check_gt(layer.get_child_count(), 1, "subway has an actual entrance surround")
		layer.free()


func test_bridge_styles_have_their_structural_silhouettes() -> void:
	var tops := {}
	for code: int in [82, 86, 87, 88, 89, 90, 91, 106, 107]:
		var city := flat_city()
		city.building.put(10, 10, code)
		city.terrain.put(10, 10, Terrain.SURFACE)
		city.set_heights(10, 10, 1, 3)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var top := -INF
		for child: Node in layer.get_children():
			if child is MeshInstance3D:
				var aabb: AABB = child.get_aabb()
				# Beam transforms may rotate their box; transformed bounds include it.
				var world: AABB = child.transform * aabb
				top = maxf(top, world.end.y)
		tops[code] = top
		layer.free()
	check_gt(tops[82] - tops[87], 0.7, "suspension tower rises above causeway guardrails")
	check_gt(tops[86] - tops[87], 0.7, "lift towers rise above ordinary deck")
	check_gt(tops[89] - tops[88], 0.4, "raised lift span visibly differs from lowered span")
	check_gt(tops[91] - tops[87], 0.15, "rail span has visible structural trusses")
	check_gt(tops[107] - tops[87], 0.1, "reinforced span has side girders")


func test_elevated_power_pylon_reaches_its_wire_above_the_seabed() -> void:
	var city := flat_city()
	city.building.put(10, 10, 92)
	city.terrain.put(10, 10, Terrain.SURFACE)
	city.set_heights(10, 10, 1, 3)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var wire_y := surface_y(layer, Vector2(10.5, 10.5), Color(0.23, 0.22, 0.21))
	var pylon_top := -INF
	for child: Node in layer.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			pylon_top = maxf(pylon_top, child.position.y + child.mesh.size.y / 2.0)
	check(is_equal_approx(pylon_top, wire_y), "the wire is physically supported above the water")
	layer.free()


## Sample the actual emitted triangles, ignoring decorative colors and vertical faces.
func surface_y(layer: CityNetworks3D, point: Vector2, color: Color) -> float:
	for i: int in range(0, layer._faces.size(), 3):
		if not layer._colors[i].is_equal_approx(color):
			continue
		var a: Vector3 = layer._faces[i]
		var b: Vector3 = layer._faces[i + 1]
		var c: Vector3 = layer._faces[i + 2]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := point - Vector2(a.x, a.z)
		var area := ab.cross(ac)
		if absf(area) < 0.000001:
			continue
		var v := ap.cross(ac) / area
		var w := ab.cross(ap) / area
		if v >= -0.0001 and w >= -0.0001 and v + w <= 1.0001:
			return a.y + (b.y - a.y) * v + (c.y - a.y) * w
	return NAN


func test_highway_dividers_are_white_between_same_direction_lanes() -> void:
	var white := Color(0.94,0.94,0.90)
	var yellow := Color(0.86,0.72,0.36)
	for code: int in [NetworkShapes.HIGHWAY_NS,NetworkShapes.HIGHWAY_EW,NetworkShapes.HIGHWAY_CORNER_NE,NetworkShapes.HIGHWAY_CORNER_SE,NetworkShapes.HIGHWAY_CORNER_SW,NetworkShapes.HIGHWAY_CORNER_NW]:
		var city := flat_city()
		city.stamp_building(34,34,code)
		var layer := CityNetworks3D.new();layer.rebuild(city)
		check(layer._colors.has(white),"highway %d has white lane dividers"%code)
		check(not layer._colors.has(yellow),"highway %d has no opposing-traffic divider inside a carriageway"%code)
		layer.free()
	var city := flat_city();city.building.put(34,34,Buildings.ROAD_FIRST)
	var road := CityNetworks3D.new();road.rebuild(city)
	check(road._colors.has(yellow),"local two-way road retains yellow centerline")
	road.free()
