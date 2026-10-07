# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Incremental network physics must equal a full resolution byte for byte after
## every edit: highway, bridge, ramp, road, rail, power and terrain changes,
## rubble, palms, region-boundary edits, undo and several simultaneous edits on
## real bundled cities, through the native kernel and the GDScript fallback.
extends "res://tests/test_case.gd"
const Native := preload("res://scripts/view/city_network_physics_native.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")

var _modes: Dictionary = {}


func after_all() -> void:
	Native.force_fallback = false
	CityNetworks3D.incremental_physics = true


static func _regions() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, 16):
		for x: int in range(0, City.WIDTH, 16): result.append(Rect2i(x, y, 16, 16))
	return result


static func _project(root: CityNetworks3D, city: City) -> void:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	root.update_regions(city, _regions(), 16)
	CityGeometry3D.end_ground_sampling(sampling)


## The full reference: the native kernel where it exists (byte-identical to
## the GDScript resolver, see test_native_network_physics), else GDScript.
static func _full(root: CityNetworks3D) -> Dictionary:
	var forced := Native.force_fallback
	Native.force_fallback = false
	var result: Dictionary
	if Native.available():
		result = Native.resolve_packed(root._physical_cells, root._physical_groups, root._physical_roles, root._physical_depths, root._physical_triangles, root._physical_boxes, root._physical_obstacles)
	else:
		result = Resolver.resolve(root.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT)), root._physical_boxes, root._physical_obstacles)
	Native.force_fallback = forced
	return result


func _first_difference(actual: PackedVector3Array, expected: PackedVector3Array, label: String) -> void:
	if actual == expected: return
	print("    %s differs: actual=%d expected=%d points" % [label, actual.size(), expected.size()])
	for i: int in mini(actual.size(), expected.size()):
		if actual[i] != expected[i]:
			print("    first difference at %d: actual=%s expected=%s" % [i, var_to_str(actual[i]), var_to_str(expected[i])])
			return


## One edit step: project, resolve incrementally and compare with a full resolution.
func _step(root: CityNetworks3D, city: City, label: String, expect_incremental: bool) -> void:
	_project(root, city)
	if root._physics_incremental != null: root._physics_incremental.last_mode = "cached"
	var started := Time.get_ticks_usec()
	var actual := root.physical_data()
	var incremental_us := Time.get_ticks_usec() - started
	var manager: RefCounted = root._physics_incremental
	var mode: String = manager.last_mode if manager != null else "none"
	_modes[mode] = int(_modes.get(mode, 0)) + 1
	started = Time.get_ticks_usec()
	var expected := _full(root)
	var full_us := Time.get_ticks_usec() - started
	expected["road_tunnels"] = root._road_tunnels.duplicate(true)
	check(var_to_bytes(actual) == var_to_bytes(expected), label + " equals a full resolution byte for byte")
	_first_difference(actual.physical_floor_faces, expected.physical_floor_faces, label + " floors")
	_first_difference(actual.physical_obstacle_faces, expected.physical_obstacle_faces, label + " obstacles")
	if expect_incremental: check(mode in ["incremental", "retained", "cached"], label + " avoided a full resolution (" + mode + ")")
	print("    %s mode=%s changed_regions=%d recomputed_groups=%d wall_groups=%d context_groups=%d incremental_ms=%.1f full_ms=%.1f floor=%d obstacles=%d" % [label, mode,
		manager.last_changed_regions if manager != null else 0, manager.last_recomputed_groups if manager != null else 0,
		manager.last_wall_groups if manager != null else 0, manager.last_context_groups if manager != null else 0,
		incremental_us / 1000.0, full_us / 1000.0, actual.physical_floor_faces.size(), actual.physical_obstacle_faces.size()])


static func _cells_where(city: City, predicate: Callable) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if predicate.call(city.building.at(x, y)): result.append(Vector2i(x, y))
	return result


static func _pick(cells: Array[Vector2i], fraction: float) -> Vector2i:
	return cells[clampi(int(cells.size() * fraction), 0, cells.size() - 1)] if not cells.is_empty() else Vector2i(-1, -1)


static func _empty_dry(city: City, near: Vector2i) -> Vector2i:
	for radius: int in range(1, 12):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var cell := near + Vector2i(dx, dy)
				if city.in_bounds(cell.x, cell.y) and city.building.atv(cell) == Buildings.NONE and not city.is_water(cell.x, cell.y): return cell
	return Vector2i(-1, -1)


func _put(city: City, cell: Vector2i, code: int, undo: Array) -> void:
	if cell.x < 0 or not city.in_bounds(cell.x, cell.y): return
	undo.append([cell, city.building.atv(cell)])
	city.building.putv(cell, code)


## A varied edit sequence over one real city.
func _sequence(path: String, label: String, full_checks: bool) -> void:
	var loaded := Sc2Import.load(path)
	check(loaded.ok, label + " imports")
	if not loaded.ok: return
	var city: City = loaded.city
	var root := CityNetworks3D.new()
	_project(root, city)
	_step(root, city, label + " initial", false)
	var highways := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_highway(code))
	var bridges := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_road_bridge(code) or NetworkShapes.is_rail_bridge(code))
	var ramps := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_onramp(code))
	var roads := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_plain_road(code))
	var rails := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_plain_rail(code))
	var power := _cells_where(city, func(code: int) -> bool: return NetworkShapes.is_plain_power(code))
	var undo: Array = []
	# Remove a highway piece: its deck group and its neighbours' walls change.
	_put(city, _pick(highways, 0.3), Buildings.NONE, undo)
	_step(root, city, label + " highway removed", true)
	# Rubble on a second highway and a road.
	_put(city, _pick(highways, 0.7), Buildings.RUBBLE_1, undo)
	_put(city, _pick(roads, 0.5), Buildings.RUBBLE_4, undo)
	_step(root, city, label + " rubble on highway and road", true)
	# A bridge and an onramp disappear in different regions at once.
	_put(city, _pick(bridges, 0.5), Buildings.NONE, undo)
	_put(city, _pick(ramps, 0.5), Buildings.NONE, undo)
	_step(root, city, label + " bridge and ramp removed", true)
	# New road, rail and power tiles beside existing networks.
	var road_site := _empty_dry(city, _pick(roads, 0.2))
	_put(city, road_site, NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH), undo)
	_put(city, _empty_dry(city, _pick(rails, 0.4)), NetworkShapes.shape_id(NetworkShapes.Family.RAIL, NetworkShapes.EAST | NetworkShapes.WEST), undo)
	_put(city, _empty_dry(city, _pick(power, 0.6)), NetworkShapes.shape_id(NetworkShapes.Family.POWER, NetworkShapes.EAST | NetworkShapes.WEST), undo)
	_step(root, city, label + " road rail power placed", true)
	# A highway tile on empty ground next to a highway, near a region boundary.
	var boundary := Vector2i(-1, -1)
	for cell: Vector2i in highways:
		if cell.x % 16 in [0, 15] or cell.y % 16 in [0, 15]:
			boundary = cell
			break
	if boundary.x >= 0:
		_put(city, boundary, Buildings.NONE, undo)
		_step(root, city, label + " highway removed at a region boundary", true)
	# Palms only: identical physical inputs keep the resolution.
	var planted := 0
	for y: int in range(5, City.HEIGHT - 5, 7):
		for x: int in range(5, City.WIDTH - 5, 7):
			if planted < 30 and city.building.at(x, y) == Buildings.NONE and not city.is_water(x, y):
				_put(city, Vector2i(x, y), Buildings.TREES_1, undo)
				planted += 1
	_step(root, city, label + " palms planted", true)
	# Terrain under a highway rises one level.
	var raised := _pick(highways, 0.5)
	if raised.x >= 0:
		var height: int = city.altitude.at(raised.x, raised.y)
		undo.append(["altitude", raised, height])
		city.altitude.put(raised.x, raised.y, mini(height + 1, 31))
		_step(root, city, label + " terrain raised under a highway", true)
	# Undo everything: the original city resolves exactly again.
	undo.reverse()
	for entry: Array in undo:
		if entry[0] is String:
			city.altitude.put(entry[1].x, entry[1].y, entry[2])
		else:
			city.building.putv(entry[0], entry[1])
	_step(root, city, label + " all edits undone", true)
	if full_checks:
		# A fresh projection of the final city resolves to the same bytes.
		var fresh := CityNetworks3D.new()
		CityNetworks3D.incremental_physics = false
		_project(fresh, city)
		var fresh_data := fresh.physical_data()
		CityNetworks3D.incremental_physics = true
		check(var_to_bytes(root.physical_data()) == var_to_bytes(fresh_data), label + " equals a fresh projection's full resolution")
		fresh.free()
	root.free()


func test_native_incremental_real_cities() -> void:
	Native.force_fallback = false
	if not Native.available():
		print("    native geometry kernel unavailable on %s; the fallback test covers this platform" % OS.get_name())
		return
	for name: String in ["La Presa", "Foothills Ranch", "Valle del Mar"]:
		_sequence("res://assets/cities/%s.sc2" % name, name + " native", true)
	print("    modes ", _modes)


func test_fallback_incremental_real_city() -> void:
	Native.force_fallback = true
	_sequence("res://assets/cities/Aliso Niguel.sc2", "Aliso Niguel fallback", false)
	Native.force_fallback = false


## The detailed per-group output reassembles the full resolution exactly.
func test_detailed_output_reassembles_full_resolution() -> void:
	for fallback: bool in [false, true]:
		Native.force_fallback = fallback
		var loaded := Sc2Import.load("res://assets/cities/Salton Shores.sc2" if fallback else "res://assets/cities/La Presa.sc2")
		var root := CityNetworks3D.new()
		_project(root, loaded.city)
		var detail := Native.resolve_detailed(root._physical_cells, root._physical_groups, root._physical_roles, root._physical_depths, root._physical_triangles, true)
		var expected := _full(root)
		var obstacles := root._physical_obstacles.duplicate()
		obstacles.append_array(detail.bottoms)
		obstacles.append_array(detail.walls)
		check(detail.floor == expected.physical_floor_faces, "detailed floors equal the full resolution (fallback=%s)" % fallback)
		check(obstacles == expected.physical_obstacle_faces, "inputs + bottoms + walls equal the full obstacles (fallback=%s)" % fallback)
		var ends: PackedInt32Array = detail.wall_ends
		check(ends.size() == (detail.keys as PackedInt32Array).size() / 3 and (ends.is_empty() or ends[-1] == (detail.walls as PackedVector3Array).size()), "wall ends cover every wall (fallback=%s)" % fallback)
		var boundaries := Native.resolve_boundaries(detail.deck, detail.deck_depths, detail.bottom_ends)
		check(boundaries.walls == detail.walls and boundaries.wall_ends == detail.wall_ends, "boundary-only walls equal the detailed walls (fallback=%s)" % fallback)
		root.free()
	Native.force_fallback = false
