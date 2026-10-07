# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Cities saved at another rotation carry each lot's corner flags shifted
## around its ring, so CORNER_NW is not on the top-left tile. Anchors, facility
## records and the packed anchor test must still name one tile per lot.
extends "res://tests/test_case.gd"

const RING: Array[int] = [Zones.CORNER_NW, Zones.CORNER_NE, Zones.CORNER_SE, Zones.CORNER_SW]


## Stamp a lot, then shift its corner flags `turn` steps around the ring the
## way a city saved at another rotation stores them.
static func stamp_rotated(c: City, at: Vector2i, id: int, zone_kind: int, turn: int) -> void:
	c.stamp_building(at.x, at.y, id, zone_kind)
	var s := Buildings.size(id)
	var cells: Array[Vector2i] = [at, at + Vector2i(s.x - 1, 0), at + s - Vector2i.ONE, at + Vector2i(0, s.y - 1)]
	for k in 4:
		var p := cells[k]
		c.zone.put(p.x, p.y, Zones.make(Zones.kind(c.zone.at(p.x, p.y)), RING[(k + turn) % 4]))


func _rotated_city(turn: int) -> Dictionary:
	var c := flat_city()
	var lots: Array[Vector2i] = []
	var plan := [
		[Vector2i(10, 10), Buildings.COAL_PLANT, Zones.NONE],
		[Vector2i(20, 10), Buildings.RES_2X2_FIRST, Zones.RES_HIGH],
		[Vector2i(22, 10), Buildings.RES_2X2_FIRST, Zones.RES_HIGH],
		[Vector2i(30, 10), Buildings.COM_3X3_FIRST, Zones.COM_HIGH],
		[Vector2i(40, 10), Buildings.POLICE_STATION, Zones.NONE],
		[Vector2i(125, 125), Buildings.IND_3X3_FIRST, Zones.IND_HIGH],
	]
	for entry in plan:
		stamp_rotated(c, entry[0], entry[1], entry[2], turn)
		lots.append(entry[0])
	return {"city": c, "lots": lots}


func test_rotated_lots_resolve_to_their_top_left_tile() -> void:
	for turn in 4:
		var built := _rotated_city(turn)
		var c: City = built["city"]
		var lots: Array[Vector2i] = built["lots"]
		var anchors := 0
		for y in City.HEIGHT:
			for x in City.WIDTH:
				var id := c.building_at(x, y)
				if not Buildings.is_multi_tile(id):
					continue
				var a := c.anchor_of(x, y)
				check(a in lots and Rect2i(a, Buildings.size(id)).has_point(Vector2i(x, y)), "turn %d tile %d,%d anchors at its lot" % [turn, x, y])
				var is_anchor := UtilityParams.is_anchor_tile(c.building.data, c.zone.data, y * City.WIDTH + x)
				check_eq(is_anchor, a == Vector2i(x, y), "turn %d anchor tile %d,%d agrees with anchor_of" % [turn, x, y])
				if is_anchor:
					anchors += 1
		check_eq(anchors, lots.size(), "turn %d one anchor per lot" % turn)


func test_rotated_plant_supplies_once() -> void:
	var capacities: Array[int] = []
	for turn in 4:
		var c: City = _rotated_city(turn)["city"]
		var ctx := make_context(c)
		var power := PowerSystem.new()
		power.setup(ctx)
		power.monthly(ctx)
		capacities.append(ctx.stats.power_capacity)
		var plant_records := 0
		for a in c.facilities:
			if c.facilities[a].get("key", &"") == Buildings.key(Buildings.COAL_PLANT):
				plant_records += 1
				check_eq(a, Vector2i(10, 10), "turn %d plant record at its anchor" % turn)
		check_eq(plant_records, 1, "turn %d one plant record" % turn)
	check_gt(capacities[0], 0)
	for turn in 4:
		check_eq(capacities[turn], capacities[0], "turn %d capacity matches the unrotated plant" % turn)


## The importer's facility scan over layers as a rotated save stores them.
func _import(c: City) -> City:
	c.facilities.clear()
	Sc2Import._scan_facilities(c)
	return c


func test_import_keys_rotated_facilities_by_anchor() -> void:
	for turn in 4:
		var c := _import(_rotated_city(turn)["city"])
		for at: Vector2i in [Vector2i(10, 10), Vector2i(40, 10)]:
			var id := c.building_at(at.x, at.y)
			var s := Buildings.size(id)
			var records := 0
			for a in c.facilities:
				if Rect2i(at, s).has_point(a):
					records += 1
			check_eq(records, 1, "turn %d one record for %s" % [turn, Buildings.key(id)])
			# Every tile of the lot, including the far corner, finds the record.
			var far := at + s - Vector2i.ONE
			check(not c.facility(c.anchor_of(far.x, far.y)).is_empty(), "turn %d record found from the far corner" % turn)
		var b := Builder.new(c, CityStats.new())
		var renamed := b.rename_facility(Vector2i(42, 12), "Precinct")
		check(bool(renamed["ok"]), "turn %d rename an imported rotated station" % turn)
		check_eq(String(c.facility(Vector2i(40, 10)).get("name", "")), "Precinct")


# ── anchor_of equivalence with the exhaustive search ─────────────────────

func test_square_of_identical_lots_keeps_every_anchor() -> void:
	var c := flat_city()
	var lots: Array[Vector2i] = [Vector2i(20, 20), Vector2i(22, 20), Vector2i(20, 22), Vector2i(22, 22)]
	for at in lots:
		c.stamp_building(at.x, at.y, Buildings.RES_2X2_FIRST, Zones.RES_HIGH)
	var anchors := 0
	for y in range(20, 24):
		for x in range(20, 24):
			var a := c.anchor_of(x, y)
			check(Rect2i(a, Vector2i(2, 2)).has_point(Vector2i(x, y)) and a in lots, "%d,%d anchors at its own lot" % [x, y])
			if UtilityParams.is_anchor_tile(c.building.data, c.zone.data, y * City.WIDTH + x):
				anchors += 1
	check_eq(anchors, 4, "the ring across the inner corners is not a lot")


static func _reference_anchor(c: City, x: int, y: int) -> Vector2i:
	var id := c.building.at(x, y)
	var s := Buildings.size(id)
	if s.x == 1 and s.y == 1:
		return Vector2i(x, y)
	var first := Vector2i(-1, -1)
	for ay in range(y - s.y + 1, y + 1):
		for ax in range(x - s.x + 1, x + 1):
			if _reference_footprint(c, ax, ay, id, s):
				if Zones.corners(c.zone.at(ax, ay)) == Zones.CORNER_NW:
					return Vector2i(ax, ay)
				if first.x < 0:
					first = Vector2i(ax, ay)
	if first.x >= 0:
		return first
	var ax := x
	var ay := y
	for _i in s.x:
		if Zones.corners(c.zone.at(ax, ay)) & (Zones.CORNER_NW | Zones.CORNER_SW):
			break
		if c.building.at(ax - 1, ay) != id:
			break
		ax -= 1
	for _i in s.y:
		if Zones.corners(c.zone.at(ax, ay)) & Zones.CORNER_NW:
			break
		if c.building.at(ax, ay - 1) != id:
			break
		ay -= 1
	return Vector2i(ax, ay)


static func _reference_footprint(c: City, ax: int, ay: int, id: int, s: Vector2i) -> bool:
	if not c.in_bounds(ax, ay) or not c.in_bounds(ax + s.x - 1, ay + s.y - 1):
		return false
	for dy in s.y:
		for dx in s.x:
			if c.building.at(ax + dx, ay + dy) != id:
				return false
	var ring := [Zones.corners(c.zone.at(ax, ay)), Zones.corners(c.zone.at(ax + s.x - 1, ay)),
		Zones.corners(c.zone.at(ax + s.x - 1, ay + s.y - 1)), Zones.corners(c.zone.at(ax, ay + s.y - 1))]
	for i in 4:
		var flag: int = ring[i]
		if flag == 0 or (flag & (flag - 1)) != 0:
			return false
		var next: int = ring[(i + 1) % 4]
		if next != (flag << 1 if flag != Zones.CORNER_SW else Zones.CORNER_NW):
			return false
	return true


func _check_equivalent(c: City, label: String) -> int:
	var mismatches := 0
	var anchor_mismatches := 0
	for y in range(-1, City.HEIGHT + 1):
		for x in range(-1, City.WIDTH + 1):
			var expected := _reference_anchor(c, x, y)
			if c.anchor_of(x, y) != expected:
				mismatches += 1
			if c.in_bounds(x, y) and UtilityParams.is_anchor_tile(c.building.data, c.zone.data, y * City.WIDTH + x) != (expected == Vector2i(x, y)):
				anchor_mismatches += 1
	check_eq(mismatches, 0, "%s anchor_of matches the reference" % label)
	check_eq(anchor_mismatches, 0, "%s is_anchor_tile matches the reference" % label)
	return mismatches


func test_anchor_of_matches_reference_on_bundled_and_broken_cities() -> void:
	var files := DirAccess.get_files_at("res://assets/cities")
	var imported := 0
	for f in files:
		if not f.ends_with(".sc2"):
			continue
		var r := Sc2Import.load("res://assets/cities/" + f)
		var c: City = r["city"]
		imported += 1
		_check_equivalent(c, f)
		# Plant anchors equal the plant tiles divided by the footprint area.
		var plant_tiles := 0
		var plant_anchors := 0
		var area := 0
		for y in City.HEIGHT:
			for x in City.WIDTH:
				var id := c.building_at(x, y)
				if not Buildings.is_power_plant(id) or not Buildings.is_multi_tile(id):
					continue
				area = Buildings.size(id).x * Buildings.size(id).y
				plant_tiles += 1
				if UtilityParams.is_anchor_tile(c.building.data, c.zone.data, y * City.WIDTH + x):
					plant_anchors += area
		check_eq(plant_anchors, plant_tiles, "%s plant anchors cover each plant once" % f)
	check_eq(imported, 8)
	# Broken, abutting and corner-less footprints exercise the fallback walk.
	for turn in 4:
		var c: City = _rotated_city(turn)["city"]
		c.building.put(31, 11, Buildings.RUBBLE_1)
		c.zone.put(22, 10, Zones.make(Zones.RES_HIGH, 0))
		stamp_rotated(c, Vector2i(60, 60), Buildings.RES_2X2_FIRST, Zones.RES_HIGH, turn)
		stamp_rotated(c, Vector2i(62, 60), Buildings.RES_2X2_FIRST, Zones.RES_HIGH, turn)
		stamp_rotated(c, Vector2i(60, 62), Buildings.RES_2X2_FIRST, Zones.RES_HIGH, turn)
		stamp_rotated(c, Vector2i(62, 62), Buildings.RES_2X2_FIRST, Zones.RES_HIGH, (turn + 1) % 4)
		c.stamp_building(0, 0, Buildings.COM_3X3_FIRST, Zones.COM_HIGH)
		for p: Vector2i in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 2)]:
			c.zone.put(p.x, p.y, Zones.make(Zones.COM_HIGH, 0))
		_check_equivalent(c, "turn %d broken" % turn)
