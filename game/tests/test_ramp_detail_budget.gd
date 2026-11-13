# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## On-ramp tiles are drawn in full detail up to a budget, in row-major order;
## the rest become plain ribbons on the same surface. A map filled with ramps
## therefore stays bounded, cities within the budget are drawn exactly as
## before, and edits that move a ramp across the budget match a fresh build.
extends "res://tests/test_case.gd"

var _budget := 0


func before_all() -> void:
	_budget = CityNetworks3D.ramp_detail_budget


func after_each() -> void:
	CityNetworks3D.ramp_detail_budget = _budget


static func _regions() -> Array[Rect2i]:
	var regions: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, 16):
		for x: int in range(0, City.WIDTH, 16): regions.append(Rect2i(x, y, 16, 16))
	return regions


static func _update(root: CityNetworks3D, city: City) -> void:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	root.update_regions(city, _regions(), 16)
	CityGeometry3D.end_ground_sampling(sampling)


static func _build(city: City) -> CityNetworks3D:
	var root := CityNetworks3D.new()
	_update(root, city)
	return root


## Every region's visible and physical output, in region order.
static func _bytes(root: CityNetworks3D) -> PackedByteArray:
	var parts: Array = []
	for region: Rect2i in _regions():
		var layer: CityNetworks3D = root._regions.get(region.position)
		if layer == null: parts.append(null)
		else: parts.append([layer._faces, layer._colors, layer._cells, layer._physical_cells, layer._physical_groups, layer._physical_roles, layer._physical_depths, layer._physical_triangles])
	return var_to_bytes(parts)


static func _triangles(root: CityNetworks3D) -> Dictionary:
	var counts: Dictionary = {}
	for region: Rect2i in _regions():
		var layer: CityNetworks3D = root._regions.get(region.position)
		if layer == null: continue
		for cell: Vector2i in layer._cells: counts[cell] = int(counts.get(cell, 0)) + 1
	return counts


static func _vertices(root: CityNetworks3D, cell: Vector2i) -> PackedVector3Array:
	var layer: CityNetworks3D = root._regions[Vector2i(cell.x / 16, cell.y / 16) * 16]
	var out := PackedVector3Array()
	for t: int in layer._cells.size():
		if layer._cells[t] == cell: out.append_array(layer._faces.slice(t * 3, t * 3 + 3))
	return out


## Ten ramp tiles of every code and orientation, spread over several regions.
static func _ramp_city() -> Dictionary:
	var city := flat_city()
	var ramps: Array[Vector2i] = []
	for i: int in 10:
		var cell := Vector2i(6 + (i * 37) % 110, 5 + i * 11)
		city.building.putv(cell, Buildings.ONRAMP_FIRST + i % 4)
		if i % 3 == 0: city.flags.putv(cell, RotationMapper.AXIS_FLAG)
		ramps.append(cell)
	ramps.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {"city": city, "ramps": ramps}


func test_ramps_past_the_budget_are_plain_ribbons_on_the_same_surface() -> void:
	var fixture := _ramp_city()
	var city: City = fixture.city
	var ramps: Array[Vector2i] = fixture.ramps
	CityNetworks3D.ramp_detail_budget = 1000
	var detailed := _build(city)
	var full := _triangles(detailed)
	CityNetworks3D.ramp_detail_budget = 6
	var root := _build(city)
	var counts := _triangles(root)
	for i: int in ramps.size():
		var cell := ramps[i]
		var label := "ramp %d at %s" % [i, cell]
		if i < 6:
			check(int(counts.get(cell, 0)) > 5000 and counts.get(cell) == full.get(cell), label + " is drawn in full detail (%d triangles)" % int(counts.get(cell, 0)))
			check(_vertices(root, cell) == _vertices(detailed, cell), label + " is identical to its unbudgeted form")
			continue
		check_eq(int(counts.get(cell, 0)), CityNetworks3D.RAMP_PLAIN_STEPS * 4, label + " is a plain ribbon")
		# Every ribbon vertex lies on the detailed pavement grid.
		var surface: Dictionary = {}
		for point: Vector3 in _vertices(detailed, cell): surface[point.snappedf(0.00001)] = true
		var on_surface := true
		var low := INF
		var high := -INF
		for point: Vector3 in _vertices(root, cell):
			if not surface.has(point.snappedf(0.00001)): on_surface = false
			low = minf(low, point.y)
			high = maxf(high, point.y)
		check(on_surface, label + " follows the detailed ramp's surface")
		check(high - low > CityNetworks3D.HIGHWAY_ELEVATION * 0.8, label + " still climbs from the road to the highway (%.3f)" % (high - low))
		var floors := 0
		for patch: Dictionary in root._regions[Vector2i(cell.x / 16, cell.y / 16) * 16].physical_patches_in(Rect2i(cell, Vector2i.ONE)):
			if int(patch.role) == CityNetworks3D.PhysicalRole.FLOOR and int(patch.group) == NetworkShapes.Family.HIGHWAY: floors += 1
		check_eq(floors, CityNetworks3D.RAMP_PLAIN_STEPS * 4, label + " has a floor to drive on")
	detailed.free()
	root.free()


func test_edits_across_the_budget_match_a_fresh_build() -> void:
	var fixture := _ramp_city()
	var city: City = fixture.city
	var ramps: Array[Vector2i] = fixture.ramps
	CityNetworks3D.ramp_detail_budget = 6
	var root := _build(city)
	var edits: Array = [
		["an early ramp is removed", ramps[1], Buildings.NONE],
		["a late ramp is removed", ramps[8], Buildings.NONE],
		["the early ramp returns", ramps[1], Buildings.ONRAMP_FIRST + 2],
		["a ramp is added before all others", Vector2i(3, 1), Buildings.ONRAMP_FIRST],
		["a road is added elsewhere", Vector2i(90, 3), NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH)],
		["the first ramp is removed", Vector2i(3, 1), Buildings.NONE],
		["the last detailed ramp is removed", ramps[5], Buildings.NONE],
	]
	for edit: Array in edits:
		city.building.putv(edit[1], int(edit[2]))
		_update(root, city)
		var fresh := _build(city)
		check(_bytes(root) == _bytes(fresh), "%s: the updated layer equals a fresh build" % edit[0])
		check_eq(root._ramp_plain_from, fresh._ramp_plain_from, "%s: both agree where plain ramps begin" % edit[0])
		fresh.free()
	root.free()


func test_included_cities_stay_within_the_budget() -> void:
	var directory := DirAccess.open("res://assets/cities")
	var checked := 0
	for file: String in directory.get_files():
		var city: City = null
		if file.ends_with(".sc2d"): city = SaveFormat.load("res://assets/cities/" + file).city
		elif file.ends_with(".sc2"): city = Sc2Import.load("res://assets/cities/" + file).city
		if city == null: continue
		checked += 1
		var ramps := 0
		for code: int in city.building.data:
			if NetworkShapes.is_onramp(code): ramps += 1
		check(ramps * 2 <= CityNetworks3D.ramp_detail_budget, "%s has %d ramp tiles, well within the budget" % [file, ramps])
		check_eq(CityNetworks3D._first_plain_ramp(city), City.WIDTH * City.HEIGHT, file + " draws every ramp in full detail")
	check(checked >= 12, "every included city was checked (%d)" % checked)


func test_a_map_filled_with_ramps_stays_bounded() -> void:
	var city := flat_city()
	for y: int in range(4, 124):
		for x: int in range(4, 124): city.building.put(x, y, Buildings.ONRAMP_FIRST + (x + y) % 4)
	var ramps := 120 * 120
	var before := OS.get_static_memory_usage()
	var root := _build(city)
	var megabytes := (OS.get_static_memory_usage() - before) / 1048576.0
	var counts := _triangles(root)
	var detailed := 0
	var triangles := 0
	for cell: Vector2i in counts:
		triangles += int(counts[cell])
		if int(counts[cell]) > CityNetworks3D.RAMP_PLAIN_STEPS * 4: detailed += 1
	print("    %d ramp tiles: %d detailed, %d triangles, %.0f MB" % [ramps, detailed, triangles, megabytes])
	check_eq(detailed, CityNetworks3D.ramp_detail_budget, "only the budgeted ramps are detailed")
	check_eq(counts.size(), ramps, "every ramp tile is still drawn")
	check(triangles <= CityNetworks3D.ramp_detail_budget * 9000 + ramps * CityNetworks3D.RAMP_PLAIN_STEPS * 4, "the triangle count is bounded (%d)" % triangles)
	check(megabytes < 1200.0, "the layer stays near a gigabyte at worst (%.0f MB)" % megabytes)
	root.free()
