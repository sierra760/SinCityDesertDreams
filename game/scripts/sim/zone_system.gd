# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Zone growth, decline and the RCI demand meters.
##
## Once a month every zoned lot is visited: open ground develops, buildings
## grow into larger footprints, and lots without demand, power or road access
## decline and are abandoned. The rules are written out in
## docs/simulation/zones.md; the numbers live in Params. The census and the
## growth pass walk the packed layers directly and classify buildings through
## small per-id tables built once from the roster.
class_name ZoneSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/zone_params.gd")
const W := City.WIDTH
const H := City.HEIGHT
const N := W * H
const BLOCKS := City.QUARTER * City.QUARTER
const FAMILIES := 3

## Demand accumulators per family, each in ±DEMAND_RAW_LIMIT.
var _raw_demand := Vector3i.ZERO
## Residential units at the previous pass, for the labor ratio.
var _previous_residential_units := 0
## Finished units per family at the last census.
var _units := Vector3i.ZERO
## People (residents plus jobs) per 4×4 block at the last map refresh.
var _block_people := PackedInt32Array()
## Whether a residential 2×2 finishing this pass becomes a chapel.
var _chapel_eligible := false
var _chapels := 0
## This month's counts for the news.
var _finished := PackedInt32Array([0, 0, 0])
var _declines := 0
## Tiles changed during the current pass; not revisited until the next one.
var _touched := PackedByteArray()

## Per-id tables, built once: development stage (-1 for non-lot buildings),
## whether a building is a finished zone building, footprint side.
var _stage_tbl := PackedInt32Array()
var _zone_building_tbl := PackedByteArray()
var _multi_tbl := PackedByteArray()
var _side_tbl := PackedByteArray()
## Family (-1 when not a growth zone) and top stage per zone kind.
var _family_tbl := PackedInt32Array()
## Tiles that give a lot road access, by building id.
static var _access_tbl := PackedByteArray()
## Anchor counts per building id from the last census.
var _census := PackedInt32Array()

## Layers of the city being scanned, bound for the duration of a pass.
var _bld := PackedByteArray()
var _zn := PackedByteArray()
var _flags := PackedByteArray()
var _alt := PackedInt32Array()
var _pollution := PackedByteArray()
var _land_value := PackedByteArray()
var _crime := PackedByteArray()
## Last transport pass supplies monthly city-wide residential access pressure.
## Recomputed for each growth phase, including after a mid-month load.
var _commute_success := 1.0


func _init() -> void:
	key = &"zones"
	_block_people.resize(BLOCKS)
	_raw_demand = Vector3i(Params.DEMAND_RAW_LIMIT, Params.DEMAND_RAW_LIMIT,
		Params.DEMAND_RAW_LIMIT)
	_touched.resize(N)
	_census.resize(Buildings.COUNT)
	_build_tables()


func setup(ctx: SimContext) -> void:
	var people := _take_census(ctx.city, ctx.stats)
	_previous_residential_units = _units.x
	_block_people = people
	_refresh_maps(ctx.city, people)
	_publish_demand(ctx.stats)


func monthly(ctx: SimContext, phase: int = 0) -> void:
	_commute_success = 1.0
	var transport := ctx.system(&"transport")
	if transport != null and transport.has_method("unreachable_ratio"):
		var failed := float(transport.call("unreachable_ratio"))
		if is_finite(failed):
			_commute_success -= clampf(failed, 0.0, 1.0)
	if phase == 0:
		_take_census(ctx.city, ctx.stats)
		_update_demand(ctx)
		_chapels = _census[Buildings.CHAPEL]
		_chapel_eligible = residents() > _chapels * Params.RESIDENTS_PER_CHAPEL
		_finished = PackedInt32Array([0, 0, 0])
		_declines = 0
		_scan(ctx, 0, City.HALF)
	else:
		_scan(ctx, City.HALF, City.WIDTH)
		var people := _take_census(ctx.city, ctx.stats)
		_refresh_maps(ctx.city, people)
		_report_news(ctx)


# ── Getters ──────────────────────────────────────────────────────────────

## Residents housed by one finished residential building.
func population_of(id: int) -> int:
	return Params.population_of(id)


## Jobs offered by one finished commercial or industrial building.
func jobs_of(id: int) -> int:
	return Params.jobs_of(id)


## Finished residential, commercial and industrial units at the last census.
func occupied_units() -> Vector3i:
	return _units


## Ordinary residents; arcologies are not counted here.
func residents() -> int:
	return _units.x * Params.PEOPLE_PER_UNIT


## Full-precision demand accumulators, each in ±DEMAND_RAW_LIMIT.
func raw_demand() -> Vector3i:
	return _raw_demand


## Development stage of a building id (0 open ground, -1 not a zone lot).
func stage_of(id: int) -> int:
	return Params.stage_of(id)


## Whether a lot with this footprint has road access.
static func has_access(city: City, rect: Rect2i) -> bool:
	_build_access_table()
	return _access_near(city.building.data, rect)


# ── Tables ───────────────────────────────────────────────────────────────

func _build_tables() -> void:
	_stage_tbl.resize(Buildings.COUNT)
	_zone_building_tbl.resize(Buildings.COUNT)
	_multi_tbl.resize(Buildings.COUNT)
	_side_tbl.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		_stage_tbl[id] = Params.stage_of(id)
		_zone_building_tbl[id] = 1 if Buildings.is_zone_building(id) else 0
		var s := Buildings.size(id)
		_multi_tbl[id] = 1 if s.x > 1 or s.y > 1 else 0
		_side_tbl[id] = s.x
	_family_tbl.resize(Zones.KIND_MASK + 1)
	for kind in Zones.KIND_MASK + 1:
		_family_tbl[kind] = Params.family_of(kind)
	_build_access_table()


static func _build_access_table() -> void:
	if not _access_tbl.is_empty():
		return
	_access_tbl.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		_access_tbl[id] = 1 if Params.gives_access(id) else 0


## A road (or station) lies within ACCESS_RADIUS tiles of `rect`.
static func _access_near(bld: PackedByteArray, rect: Rect2i) -> bool:
	var r := Params.ACCESS_RADIUS
	var x0 := maxi(rect.position.x - r, 0)
	var x1 := mini(rect.end.x + r, W)
	for y in range(maxi(rect.position.y - r, 0), mini(rect.end.y + r, H)):
		var i := y * W + x0
		for _x in range(x0, x1):
			if _access_tbl[bld[i]] != 0:
				return true
			i += 1
	return false


func _bind(city: City) -> void:
	_bld = city.building.data
	_zn = city.zone.data
	_flags = city.flags.data
	_alt = city.altitude.data
	_pollution = city.pollution.data
	_land_value = city.land_value.data
	_crime = city.crime.data


func _unbind() -> void:
	_bld = PackedByteArray()
	_zn = PackedByteArray()
	_flags = PackedByteArray()
	_alt = PackedInt32Array()
	_pollution = PackedByteArray()
	_land_value = PackedByteArray()
	_crime = PackedByteArray()


# ── Census ───────────────────────────────────────────────────────────────

## Count finished units per family and people per 4×4 block, count anchors
## per building id, and refresh CityStats.jobs. Returns the block people array.
func _take_census(city: City, stats: CityStats) -> PackedInt32Array:
	var people := PackedInt32Array()
	people.resize(BLOCKS)
	var units := Vector3i.ZERO
	var bld := city.building.data
	var zn := city.zone.data
	_census.fill(0)
	var i := 0
	for y in H:
		var block_row := (y >> 2) * City.QUARTER
		for x in W:
			var id := bld[i]
			if id == Buildings.NONE:
				i += 1
				continue
			var z := zn[i]
			if _multi_tbl[id] == 0 or (z & Zones.CORNER_NW) != 0:
				_census[id] += 1
			if _zone_building_tbl[id] != 0:
				var family := _family_tbl[z & Zones.KIND_MASK]
				if family >= 0 and (_multi_tbl[id] == 0 or UtilityParams.is_anchor_tile(bld, zn, i)):
					var stage := _stage_tbl[id]
					units[family] += Params.STAGE_UNITS[stage]
					people[block_row + (x >> 2)] += Params.STAGE_UNITS[stage] * Params.PEOPLE_PER_UNIT
			i += 1
	_units = units
	stats.jobs = (units.y + units.z) * Params.PEOPLE_PER_UNIT
	return people


# ── Demand ───────────────────────────────────────────────────────────────

func _update_demand(ctx: SimContext) -> void:
	var city := ctx.city
	var stats := ctx.stats
	var census := _census
	var r := _units.x
	var c := _units.y
	var i := _units.z
	var jobs := c + i
	var labor_ratio := float(_previous_residential_units) / float(jobs + 1)
	var people := (r + c + i) * Params.PEOPLE_PER_UNIT

	var recreation := 0
	for k in Params.RECREATION_KEYS:
		recreation += census[Buildings.id_of(k)]
	var stations := 0
	for k in Params.STATION_KEYS:
		stations += census[Buildings.id_of(k)]
	var rail_stations := census[Buildings.RAIL_STATION]
	var cranes := census[Buildings.CRANE]
	var neighbors := 0
	for n in stats.neighbor_populations:
		if n > 0:
			neighbors += 1
	# Port, base and neighbor-link effects (see ports.md and neighbors.md).
	var ports := ctx.system(&"ports")
	var port_bonus := Vector3i.ZERO
	var port_job_units := 0
	if ports != null and ports.has_method("demand_bonus"):
		port_bonus = ports.call("demand_bonus")
		@warning_ignore("integer_division")
		port_job_units = int(ports.call("jobs")) / Params.PEOPLE_PER_UNIT
	var trade_bonus := 0
	var neighbor_sys := ctx.system(&"neighbors")
	if neighbor_sys != null and neighbor_sys.has_method("trade_demand_bonus"):
		trade_bonus = int(neighbor_sys.call("trade_demand_bonus"))

	@warning_ignore("integer_division")
	var res_target := minf(maxf(float(Params.RES_TARGET_FLOOR), float(jobs + port_job_units + r / Params.RES_SELF_GROWTH_DIVISOR)),
		minf(float(c * Params.RES_PER_COMMERCIAL + Params.RES_BASE_TARGET),
			float((Params.RES_CAP_BASE + recreation) * Params.RES_CAP_STEP)))

	var market := float(people + Params.MARKET_BASE) / float(Params.MARKET_SCALE) \
		+ neighbors * Params.EXTERNAL_MARKET_PER_NEIGHBOR
	var industrial_workers := float(i) * labor_ratio
	@warning_ignore("integer_division")
	var com_cap := (Params.COM_CAP_BASE + stations / Params.COM_STATIONS_PER_STEP
		+ neighbors) * Params.COM_CAP_STEP
	var com_target := minf(market * industrial_workers, float(com_cap))

	var difficulty := clampi(city.difficulty, 0, Params.INDUSTRY_BY_DIFFICULTY.size() - 1)
	var phase := clampi(stats.economy_phase, 0, Params.INDUSTRY_BY_PHASE.size() - 1)
	var industry := Params.INDUSTRY_BY_DIFFICULTY[difficulty] + Params.INDUSTRY_BY_PHASE[phase]
	var economy := ctx.system(&"economy")
	if economy != null and economy.has_method("industrial_demand_modifier"):
		industry += float(economy.call("industrial_demand_modifier")) / 100.0
	var ind_cap := (Params.IND_CAP_BASE + rail_stations + cranes) * Params.IND_CAP_STEP
	var ind_target := minf(maxf(float(Params.IND_TARGET_FLOOR), industry * industrial_workers),
		float(ind_cap))

	var targets: Array[float] = [res_target, com_target, ind_target]
	# Ordinances such as sales tax or business advertising move the rate each
	# family feels; property tax still charges the player's rates.
	var felt := OrdinanceSystem.effective_rates(stats)
	var taxes: Array[int] = [felt.x, felt.y, felt.z]
	var nudges: Array[int] = [0, port_bonus.y + trade_bonus, port_bonus.z + trade_bonus]
	if stats.ordinances.get(&"pro_reading_campaign", false):
		nudges[Params.FAMILY_RESIDENTIAL] += Params.READING_NUDGE

	for family in FAMILIES:
		var ratio := targets[family] / float(_units[family] + 1) - 1.0
		var change := int(Params.DEMAND_GAIN * ratio) + Params.tax_pressure(taxes[family]) \
			+ nudges[family]
		_raw_demand[family] = clampi(_raw_demand[family] + change,
			-Params.DEMAND_RAW_LIMIT, Params.DEMAND_RAW_LIMIT)
	_previous_residential_units = r
	_publish_demand(stats)


func _publish_demand(stats: CityStats) -> void:
	var meter := Vector3i.ZERO
	for family in FAMILIES:
		@warning_ignore("integer_division")
		meter[family] = _raw_demand[family] * 999 / Params.DEMAND_RAW_LIMIT
	stats.demand = meter


# ── Growth pass ──────────────────────────────────────────────────────────

func _scan(ctx: SimContext, x_from: int, x_to: int) -> void:
	var city := ctx.city
	_bind(city)
	_touched.fill(0)
	for y in H:
		var i := y * W + x_from
		for x in range(x_from, x_to):
			if _touched[i] != 0:
				i += 1
				continue
			var kind := _zn[i] & Zones.KIND_MASK
			var family := _family_tbl[kind]
			if family < 0:
				i += 1
				continue
			var id := _bld[i]
			var stage := _stage_tbl[id]
			if stage < 0:
				i += 1
				continue
			var p := Vector2i(x, y)
			var rect := Rect2i(p, Vector2i.ONE)
			if stage > 0:
				if _multi_tbl[id] != 0 and not UtilityParams.is_anchor_tile(_bld, _zn, i):
					i += 1
					continue
				rect = Rect2i(p, Buildings.size(id))
				if not _footprint_intact(rect, id, kind):
					i += 1
					continue
			_visit_lot(ctx, rect, id, kind, family, stage)
			i += 1
	_unbind()


func _footprint_intact(rect: Rect2i, id: int, kind: int) -> bool:
	if rect.end.x > W or rect.end.y > H:
		return false
	for y in range(rect.position.y, rect.end.y):
		var i := y * W + rect.position.x
		for _x in rect.size.x:
			if _bld[i] != id or (_zn[i] & Zones.KIND_MASK) != kind:
				return false
			i += 1
	return true


func _visit_lot(ctx: SimContext, rect: Rect2i, id: int, kind: int, family: int, stage: int) -> void:
	var a := rect.position
	var ai := a.y * W + a.x
	var connected := (_flags[ai] & TileFlags.POWERED) != 0 and _access_near(_bld, rect)
	var growth := _growth_points(a, family, connected)
	var watered := (_flags[ai] & TileFlags.WATERED) != 0

	if _zone_building_tbl[id] != 0:
		if _roll(ctx) < (Params.GROWTH_POINTS_MAX - growth) / stage:
			_decline(ctx, rect, kind, stage)
			_declines += 1
			return
	elif Buildings.is_construction(id):
		if _roll(ctx) < _slowed(Params.CONSTRUCTION_FINISH / stage, watered):
			var footprint: int = Params.STAGE_FOOTPRINT[stage]
			if family == Params.FAMILY_RESIDENTIAL and footprint == 2 and _chapel_eligible:
				_stamp_chapel(ctx, a)
			else:
				_finish(ctx, rect, kind, family, stage)
				_finished[family] += 1
		return
	elif Buildings.is_abandoned(id):
		if _roll(ctx) < growth * Params.REBUILD_FACTOR / stage:
			_finish(ctx, rect, kind, family, stage)
		return

	if stage >= Params.max_stage(kind):
		return
	if family != Params.FAMILY_INDUSTRIAL \
			and _land_value_at(a.x, a.y) < Params.UPGRADE_LAND_VALUE[stage]:
		return
	if _roll(ctx) < _slowed(growth * Params.UPGRADE_FACTOR / (stage + 1), watered):
		_upgrade(ctx, rect, kind, stage)


func _roll(ctx: SimContext) -> int:
	return ctx.rng.below(Params.ROLL_SPAN)


func _slowed(threshold: int, watered: bool) -> int:
	if watered:
		return threshold
	@warning_ignore("integer_division")
	return threshold * Params.WATER_SHORTAGE_NUMERATOR / Params.WATER_SHORTAGE_DENOMINATOR


func _land_value_at(x: int, y: int) -> int:
	return _land_value[(y >> 1) * City.HALF + (x >> 1)]


## Rule 7: demand plus local conditions, 0 when the lot is not connected.
func _growth_points(anchor: Vector2i, family: int, connected: bool) -> int:
	if not connected:
		return 0
	var b := (anchor.y >> 1) * City.HALF + (anchor.x >> 1)
	var g: int = _raw_demand[family] + Params.DEMAND_RAW_LIMIT
	if family != Params.FAMILY_INDUSTRIAL:
		g += _land_value[b] * Params.LAND_VALUE_WEIGHT
	g -= maxi(0, _pollution[b] - Params.POLLUTION_TOLERANCE) * Params.POLLUTION_WEIGHT[family]
	g -= maxi(0, _crime[b] - Params.CRIME_TOLERANCE) * Params.CRIME_WEIGHT[family]
	g = clampi(g, 0, Params.GROWTH_POINTS_MAX)
	if family == Params.FAMILY_RESIDENTIAL:
		g = int(g * _commute_success)
	return g


# ── Lot changes ──────────────────────────────────────────────────────────

## Rule 9: a finished building decays into abandonment, possibly splitting.
func _decline(ctx: SimContext, rect: Rect2i, kind: int, stage: int) -> void:
	var split := ctx.rng.chance(1, 2)
	var a := rect.position
	match stage:
		1:
			_stamp_abandoned(ctx, a, kind, 1)
		2:
			if split:
				for y in range(a.y, a.y + 2):
					for x in range(a.x, a.x + 2):
						_stamp_abandoned(ctx, Vector2i(x, y), kind, 1)
			else:
				_stamp_abandoned(ctx, a, kind, 2)
		3:
			_stamp_abandoned(ctx, a, kind, 2 if split else 3)
		4:
			if split:
				for y in range(a.y, a.y + 3):
					for x in range(a.x, a.x + 3):
						if x != a.x + 1 or y != a.y + 1:
							_stamp_abandoned(ctx, Vector2i(x, y), kind, 1)
				var quadrant := ctx.rng.below(4)
				_stamp_abandoned(ctx, a + Vector2i(quadrant & 1, quadrant >> 1), kind, 3)
			else:
				_stamp_abandoned(ctx, a, kind, 4)


## Rules 10 and 11: a construction site or abandoned lot becomes a finished building.
func _finish(ctx: SimContext, rect: Rect2i, kind: int, family: int, stage: int) -> void:
	var ids := Params.finished_ids(family, stage)
	var id := 0
	if family == Params.FAMILY_RESIDENTIAL and stage == 1:
		@warning_ignore("integer_division")
		var classes: int = ids.size() / 3
		@warning_ignore("integer_division")
		var look_class := mini(_land_value_at(rect.position.x, rect.position.y)
			/ Params.RES_CLASS_LAND_VALUE_STEP, 2)
		id = ids[look_class * classes + ctx.rng.below(classes)]
	else:
		id = ids[ctx.rng.below(ids.size())]
	_stamp(ctx, rect.position, id, kind)


## Rule 12: stamp a construction site of the next stage, expanding the footprint.
func _upgrade(ctx: SimContext, rect: Rect2i, kind: int, stage: int) -> bool:
	var city := ctx.city
	var a := rect.position
	match stage:
		0:
			_stamp_construction(ctx, a, kind, 1)
			return true
		1:
			for offset in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, -1)]:
				var candidate := Rect2i(a + offset, Vector2i(2, 2))
				if _can_expand(city, candidate, kind, 1):
					_stamp_construction(ctx, candidate.position, kind, 2)
					return true
		2:
			_stamp_construction(ctx, a, kind, 3)
			return true
		3:
			for offset in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var candidate := Rect2i(a + offset, Vector2i(3, 3))
				if _can_expand(city, candidate, kind, 3) and _rim_has_road(candidate):
					_break_other_lots(ctx, candidate, rect)
					_stamp_construction(ctx, candidate.position, kind, 4)
					return true
	return false


## All tiles of `rect` share the zone kind and height, sit inside the edge
## margin, were not changed this pass, and hold nothing above `max_stage`.
func _can_expand(city: City, rect: Rect2i, kind: int, max_stage: int) -> bool:
	var m := Params.EDGE_MARGIN
	if rect.position.x < m or rect.position.y < m \
			or rect.end.x > W - m or rect.end.y > H - m:
		return false
	var height := _alt[rect.position.y * W + rect.position.x] & City.ALT_MASK
	for y in range(rect.position.y, rect.end.y):
		var i := y * W + rect.position.x
		for x in range(rect.position.x, rect.end.x):
			if _touched[i] != 0:
				return false
			if (_zn[i] & Zones.KIND_MASK) != kind or city.is_water(x, y):
				return false
			if (_alt[i] & City.ALT_MASK) != height:
				return false
			var stage := _stage_tbl[_bld[i]]
			if stage < 0 or stage > max_stage:
				return false
			i += 1
	return true


## A road (or station) touches the ring of tiles around `rect`.
func _rim_has_road(rect: Rect2i) -> bool:
	for y in range(rect.position.y - 1, rect.end.y + 1):
		if y < 0 or y >= H:
			continue
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if x < 0 or x >= W or rect.has_point(Vector2i(x, y)):
				continue
			if _access_tbl[_bld[y * W + x]] != 0:
				return true
	return false


## Other 2×2 lots overlapping a new 3×3 site are broken into abandoned 1×1
## lots so their tiles outside the site stay consistent.
func _break_other_lots(ctx: SimContext, site: Rect2i, own: Rect2i) -> void:
	var city := ctx.city
	var done: Dictionary = {}
	for y in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			if own.has_point(Vector2i(x, y)):
				continue
			var id := _bld[y * W + x]
			if Params.STAGE_FOOTPRINT[maxi(_stage_tbl[id], 0)] != 2:
				continue
			var anchor := city.anchor_of(x, y)
			if done.has(anchor):
				continue
			done[anchor] = true
			for ty in range(anchor.y, anchor.y + 2):
				for tx in range(anchor.x, anchor.x + 2):
					_stamp_abandoned(ctx, Vector2i(tx, ty), city.zone_kind_at(tx, ty), 1)


func _stamp_construction(ctx: SimContext, pos: Vector2i, kind: int, stage: int) -> void:
	var ids := Params.construction_ids(stage)
	_stamp(ctx, pos, ids[ctx.rng.below(ids.size())], kind)


func _stamp_abandoned(ctx: SimContext, pos: Vector2i, kind: int, stage: int) -> void:
	var ids := Params.abandoned_ids(stage)
	_stamp(ctx, pos, ids[ctx.rng.below(ids.size())], kind)


## Rule 10: a chapel takes the place of a residential 2×2 site.
func _stamp_chapel(ctx: SimContext, pos: Vector2i) -> void:
	_stamp(ctx, pos, Buildings.CHAPEL, Zones.NONE)
	ctx.city.add_facility(pos, {"key": &"chapel", "built_day": ctx.city.day})
	_chapels += 1
	_chapel_eligible = residents() > _chapels * Params.RESIDENTS_PER_CHAPEL
	ctx.events.report(&"chapel_built", {"at": [pos.x, pos.y]})


## Write a building into the map, mark its tiles conductive and touched.
func _stamp(ctx: SimContext, pos: Vector2i, id: int, kind: int) -> void:
	var city := ctx.city
	city.stamp_building(pos.x, pos.y, id, kind)
	var s := Buildings.size(id)
	for y in range(pos.y, pos.y + s.y):
		for x in range(pos.x, pos.x + s.x):
			city.set_flag(x, y, TileFlags.CONDUCTS_POWER | TileFlags.CONDUCTS_WATER, true)
			if x >= 0 and y >= 0 and x < W and y < H:
				_touched[y * W + x] = 1
	ctx.events.mark_dirty(Rect2i(pos, s))


# ── Maps and news ────────────────────────────────────────────────────────

## Rule 15: density and growth overlays from people per 4×4 block.
func _refresh_maps(city: City, people: PackedInt32Array) -> void:
	for b in BLOCKS:
		@warning_ignore("integer_division")
		var density := mini(people[b] / Params.DENSITY_PEOPLE_PER_STEP, 255)
		@warning_ignore("integer_division")
		var growth := clampi(128 + (people[b] - _block_people[b]) / Params.GROWTH_PEOPLE_PER_STEP, 0, 255)
		city.density.data[b] = density
		city.growth.data[b] = growth
	_block_people = people


## Rule 16.
func _report_news(ctx: SimContext) -> void:
	for family in FAMILIES:
		if ctx.stats.demand[family] > Params.BOOM_DEMAND \
				and _finished[family] >= Params.BOOM_DEVELOPMENTS:
			ctx.events.report(&"zone_boom", {
				"family": String(Params.FAMILY_NAMES[family]),
				"count": _finished[family],
			})
	if _declines >= Params.WAVE_DECLINES:
		ctx.events.report(&"abandonment_wave", {"count": _declines})


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {
		"raw_demand": [_raw_demand.x, _raw_demand.y, _raw_demand.z],
		"previous_residential_units": _previous_residential_units,
		"units": [_units.x, _units.y, _units.z],
		"block_people": Array(_block_people),
		"chapel_eligible": _chapel_eligible,
		"chapels": _chapels,
		"finished": Array(_finished),
		"declines": _declines,
	}


func load(data: Dictionary) -> void:
	var raw: Array = data.get("raw_demand", [])
	if raw.size() == 3:
		_raw_demand = Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	_previous_residential_units = int(data.get("previous_residential_units", _previous_residential_units))
	var units: Array = data.get("units", [])
	if units.size() == 3:
		_units = Vector3i(int(units[0]), int(units[1]), int(units[2]))
	var blocks: Array = data.get("block_people", [])
	if blocks.size() == BLOCKS:
		_block_people = PackedInt32Array(blocks)
	_chapel_eligible = bool(data.get("chapel_eligible", false))
	_chapels = int(data.get("chapels", 0))
	# The eastern phase finishes the western phase's monthly news totals.
	_finished = PackedInt32Array([0, 0, 0])
	var finished: Array = data.get("finished", [])
	if finished.size() == FAMILIES:
		for family in FAMILIES:
			_finished[family] = maxi(0, int(finished[family]))
	_declines = maxi(0, int(data.get("declines", 0)))
