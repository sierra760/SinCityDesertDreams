# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Disasters: natural selection, menu requests, daily progression, damage,
## fires, floods, contamination, emergency crews and the advisor need line.
##
## Rules are written out in docs/simulation/disasters.md; every number comes
## from DisasterParams. Fires, riots, hot contamination and flood water are
## tile sets the system owns; the running major disaster is one record with a
## kind, a point and a day count, plus moving entities for tornado, monster,
## hurricane eye, plane and microwave beam.
class_name DisasterSystem
extends SimSystem

const ScanTables := preload("res://scripts/sim/data/public_scan_tables.gd")

const DIRS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS_8: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const CREW_KINDS: Array[StringName] = [&"fire", &"police", &"military"]
const SERVICE_BITS := TileFlags.CONDUCTS_POWER | TileFlags.POWERED | TileFlags.CONDUCTS_WATER | TileFlags.WATERED
## Days a plane may spend flying in before the crash gives up.
const PLANE_MAX_DAYS := 40
## Search radius for the nearest road when seeding a riot.
const ROAD_SEARCH_RADIUS := 24
## Search radius for the nearest burnable tile when a fire is requested on bare ground.
const FUEL_SEARCH_RADIUS := 10

var _city: City
var _ctx: SimContext
var _fires: Dictionary = {}       ## Vector2i -> days of fuel left
var _riots: Dictionary = {}       ## Vector2i -> heading 0..3
var _hot: Dictionary = {}         ## Vector2i -> days the contamination keeps spreading
var _flooded: Dictionary = {}     ## Vector2i -> depth
var _flood_remaining := 0
var _flood_total := 0
var _active: Dictionary = {}      ## the running major disaster, or empty
var _entities: Array[Dictionary] = []
var _crews: Array[Dictionary] = []
var _advice: Array[StringName] = []
## The top need last given to the newspaper, and months since then.
var _reported_need := &""
var _need_months := 0
var _outbreak_reported := false


func _init() -> void:
	key = &"disasters"


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_city = ctx.city
	_ctx = ctx
	_rebuild_overlay()


func daily(ctx: SimContext) -> void:
	_ctx = ctx
	if not _active.is_empty():
		_step_active(ctx)
	_step_fires(ctx)
	_step_riots(ctx)
	_step_hot(ctx)
	_step_flood(ctx)
	_finish_if_done(ctx)
	if not is_emergency():
		_crews.clear()
	_sync_stats(ctx)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_ctx = ctx
	_advice = _compute_advice(ctx)
	_need_months += 1
	var need: StringName = _advice[0] if not _advice.is_empty() else &""
	if need != &"" and (need != _reported_need or _need_months >= DisasterParams.ADVICE_NEWS_REPEAT_MONTHS):
		ctx.events.report(&"advisor_need", {"need": String(need)}, 0)
		_need_months = 0
	_reported_need = need
	_natural_roll(ctx)
	_sync_stats(ctx)


func yearly(ctx: SimContext) -> void:
	var city := ctx.city
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.building_at(x, y) != Buildings.CONTAMINATION:
				continue
			if _hot.has(Vector2i(x, y)):
				continue
			if ctx.rng.chance(1, DisasterParams.CONTAMINATION_CLEAR_ODDS):
				city.building.put(x, y, Buildings.NONE)
				ctx.events.mark_tile(x, y)


func networks_changed(ctx: SimContext, rect: Rect2i) -> void:
	var city := ctx.city
	for key_tile in _fires.keys():
		var t: Vector2i = key_tile
		if not rect.has_point(t):
			continue
		if city.is_water(t.x, t.y) or _spread_odds(city.building_at(t.x, t.y)) <= 0:
			_fires.erase(t)
	for key_tile in _riots.keys():
		var t: Vector2i = key_tile
		if rect.has_point(t) and not _walkable(city, t):
			_riots.erase(t)
	_sync_stats(ctx)


# ── Public interface ─────────────────────────────────────────────────────

## Start a disaster now. `at` may be (-1,-1) to let the system choose a place.
func request(ctx: SimContext, kind: StringName, at: Vector2i = Vector2i(-1, -1)) -> bool:
	_ctx = ctx
	if not DisasterParams.KINDS.has(kind):
		return false
	if not _is_fire_only(kind) and not _active.is_empty():
		return false
	var survey := _survey(ctx.city)
	if not _precondition(ctx.stats, survey, kind, false):
		return false
	return _start(ctx, kind, at, survey)


## Why `request` refused `kind` in `city`, as a short sentence for the player.
## Call it after a refused request. Reads the map only: no random draws and no
## state change.
func unavailable_reason(city: City, kind: StringName) -> String:
	if not DisasterParams.KINDS.has(kind):
		return "That disaster is not available."
	if not _is_fire_only(kind) and not _active.is_empty():
		return "Another disaster is still under way."
	if city == null:
		return ""
	var survey := _survey(city)
	match kind:
		&"fire", &"firestorm":
			if not survey["has_flammable"]: return "Needs something that can burn."
		&"flood", &"major_flood", &"hurricane":
			if not survey["has_shore"]: return "Needs shoreline."
		&"riot", &"mass_riots":
			if not survey["has_road"]: return "Needs a road."
			return "Needs a road near developed land."
		&"hazard":
			if int(survey["max_pollution"]) < DisasterParams.HAZARD_POLLUTION:
				return "Needs heavily polluted ground."
		&"meltdown":
			if not survey["has_nuclear"]:
				return "Needs a %s." % Buildings.display_name(Buildings.NUCLEAR_PLANT)
		&"microwave":
			if not survey["has_microwave"]:
				return "Needs a %s." % Buildings.display_name(Buildings.MICROWAVE_PLANT)
		&"chemical_spill":
			if not survey["has_industrial"]: return "Needs industry."
	return "There is no suitable place for it right now."


## Place an emergency crew. Only possible during an emergency.
func dispatch(kind: StringName, at: Vector2i) -> bool:
	if _ctx == null or _city == null or not is_emergency():
		return false
	if not CREW_KINDS.has(kind):
		return false
	if not _city.in_bounds(at.x, at.y) or _city.is_water(at.x, at.y):
		return false
	var limit := crews_available(kind)
	if limit <= 0:
		return false
	var same := 0
	var oldest := -1
	for i in _crews.size():
		if StringName(_crews[i]["kind"]) == kind:
			same += 1
			if oldest < 0:
				oldest = i
	if same >= limit and oldest >= 0:
		_crews.remove_at(oldest)
	_crews.append({"kind": String(kind), "x": at.x, "y": at.y, "day": _ctx.clock.day})
	_ctx.events.mark_tile(at.x, at.y)
	return true


## Crews the city can field of one kind.
func crews_available(kind: StringName) -> int:
	return int(crews_summary().get(kind, 0))


## Crews the city can field of every kind, keyed by crew kind, from one
## inexpensive look at the building grid. The toolbar asks this whenever it
## refreshes during an emergency.
func crews_summary() -> Dictionary:
	if _city == null:
		return {&"fire": 0, &"police": 0, &"military": 0}
	var fire := mini(_fast_count_anchors(_city, Buildings.FIRE_STATION), DisasterParams.MAX_CREWS)
	var police := mini(_fast_count_anchors(_city, Buildings.POLICE_STATION), DisasterParams.MAX_CREWS)
	var military := 0
	var cells := _city.building.data
	for id in _military_ids():
		if cells.has(id):
			military = DisasterParams.MILITARY_CREWS
			break
	if fire == 0 and police == 0 and military == 0:
		military = 1
	return {&"fire": fire, &"police": police, &"military": military}


## Same count as _count_anchors, searching the backing bytes natively.
func _fast_count_anchors(city: City, id: int) -> int:
	var cells := city.building.data
	if not Buildings.is_multi_tile(id):
		return cells.count(id)
	var n := 0
	var width := city.building.width
	var i := cells.find(id)
	while i >= 0:
		if Zones.corners(city.zone.at(i % width, i / width)) & Zones.CORNER_NW:
			n += 1
		i = cells.find(id, i + 1)
	return n


static var _military_cache: PackedInt32Array = PackedInt32Array()
static var _military_cached := false


static func _military_ids() -> PackedInt32Array:
	if not _military_cached:
		for id in Buildings.COUNT:
			if Buildings.category(id) == Buildings.Category.MILITARY:
				_military_cache.append(id)
		_military_cached = true
	return _military_cache


func crews() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _crews:
		out.append({"kind": StringName(c["kind"]), "x": int(c["x"]), "y": int(c["y"]),
			"pos": Vector2i(int(c["x"]), int(c["y"]))})
	return out


## Moving things for the renderer: tornado, monster, hurricane eye, plane, beam.
func entities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entities:
		out.append({"kind": StringName(e["kind"]), "x": int(e["x"]), "y": int(e["y"]),
			"pos": Vector2i(int(e["x"]), int(e["y"])), "heading": int(e.get("heading", 0)),
			"frame": int(e["frame"])})
	return out


func fires() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in _fires:
		out.append(t)
	return out


func flooded() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in _flooded:
		out.append(t)
	return out


func advice() -> Array[StringName]:
	return _advice.duplicate()


func is_emergency() -> bool:
	return not _active.is_empty() or not _fires.is_empty() or not _riots.is_empty()


## Current incident position for navigation, without changing state or RNG.
## Moving hazards take precedence; remaining tile hazards precede the epicenter.
func emergency_target() -> Vector2i:
	if _city == null or not is_emergency():
		return Vector2i(-1, -1)
	for entity: Dictionary in _entities:
		var point := Vector2i(int(entity.get("x", -1)), int(entity.get("y", -1)))
		if _city.in_bounds(point.x, point.y): return point
	for tiles: Dictionary in [_riots, _fires, _flooded, _hot]:
		for point: Vector2i in tiles:
			if _city.in_bounds(point.x, point.y): return point
	var origin := Vector2i(int(_active.get("x", -1)), int(_active.get("y", -1)))
	return origin if _city.in_bounds(origin.x, origin.y) else Vector2i(-1, -1)


## Live crowd tiles for the read-only incident renderer.
func riots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for point: Vector2i in _riots: out.append(point)
	return out


func active() -> Dictionary:
	return _active.duplicate(true)


# ── Save state ───────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {
		"fires": _tiles_to_json(_fires),
		"riots": _tiles_to_json(_riots),
		"hot": _tiles_to_json(_hot),
		"flood": _tiles_to_json(_flooded),
		"flood_remaining": _flood_remaining,
		"flood_total": _flood_total,
		"active": _active.duplicate(true),
		"entities": _entities.duplicate(true),
		"crews": _crews.duplicate(true),
		"advice": _advice_to_json(),
		"reported_need": String(_reported_need),
		"need_months": _need_months,
		"outbreak_reported": _outbreak_reported,
	}


func load(data: Dictionary) -> void:
	_fires = _tiles_from_json(data.get("fires", {}))
	_riots = _tiles_from_json(data.get("riots", {}))
	_hot = _tiles_from_json(data.get("hot", {}))
	_flooded = _tiles_from_json(data.get("flood", {}))
	_flood_remaining = int(data.get("flood_remaining", 0))
	_flood_total = int(data.get("flood_total", 0))
	var active_in: Dictionary = data.get("active", {})
	_active = {}
	for k in active_in:
		var v: Variant = active_in[k]
		_active[String(k)] = int(v) if typeof(v) == TYPE_FLOAT else v
	_entities.clear()
	var entities_in: Array = data.get("entities", [])
	for e in entities_in:
		_entities.append(_ints(e))
	_crews.clear()
	var crews_in: Array = data.get("crews", [])
	for c in crews_in:
		_crews.append(_ints(c))
	_advice.clear()
	var advice_in: Array = data.get("advice", [])
	for a in advice_in:
		_advice.append(StringName(String(a)))
	_reported_need = StringName(String(data.get("reported_need", "")))
	_need_months = int(data.get("need_months", 0))
	_outbreak_reported = bool(data.get("outbreak_reported", false))
	_rebuild_overlay()


func _tiles_to_json(tiles: Dictionary) -> Dictionary:
	var out := {}
	for t in tiles:
		out[tile_key(t)] = int(tiles[t])
	return out


func _tiles_from_json(data: Dictionary) -> Dictionary:
	var out := {}
	for k in data:
		var t := parse_tile_key(String(k))
		if t.x >= 0:
			out[t] = int(data[k])
	return out


func _advice_to_json() -> Array:
	var out: Array = []
	for a in _advice:
		out.append(String(a))
	return out


## Numbers come back from JSON as floats; keep every record integral.
func _ints(record: Dictionary) -> Dictionary:
	var out := {}
	for k in record:
		var v: Variant = record[k]
		out[String(k)] = int(v) if typeof(v) == TYPE_FLOAT else v
	return out


func _rebuild_overlay() -> void:
	if _city == null:
		return
	_city.flood_overlay.clear()
	for t in _flooded:
		_city.flood_overlay[t] = int(_flooded[t])


# ── Natural selection ────────────────────────────────────────────────────

func _natural_roll(ctx: SimContext) -> void:
	if not ctx.stats.disasters_enabled or not _active.is_empty():
		return
	var odds: int = DisasterParams.NATURAL_ODDS_BY_DIFFICULTY.get(ctx.city.difficulty, 60)
	if ctx.clock.day / GameClock.DAYS_PER_MONTH < odds:
		return
	var chance := 1 + ctx.stats.population / DisasterParams.POPULATION_PER_EXTRA_CHANCE
	if not ctx.rng.chance(chance, odds):
		return
	var survey := _survey(ctx.city)
	var pool: Array[StringName] = []
	var weights: Array[int] = []
	var total := 0
	for kind in DisasterParams.KINDS:
		if not _precondition(ctx.stats, survey, kind, true):
			continue
		var w: int = DisasterParams.NATURAL_WEIGHTS.get(kind, 0)
		if w <= 0:
			continue
		pool.append(kind)
		weights.append(w)
		total += w
	if total <= 0:
		return
	var pick := ctx.rng.below(total)
	for i in pool.size():
		pick -= weights[i]
		if pick < 0:
			_start(ctx, pool[i], Vector2i(-1, -1), survey)
			return


## What the map must offer for a kind to happen. The city-condition gates
## (crime, population, pollution, high ground) apply only to natural rolls;
## a request from the menu needs only the physical ingredients.
func _precondition(stats: CityStats, survey: Dictionary, kind: StringName, natural: bool) -> bool:
	var riot_ok: bool = not natural or stats.average_crime >= DisasterParams.RIOT_CRIME \
		or stats.approval <= DisasterParams.RIOT_APPROVAL
	match kind:
		&"fire", &"firestorm": return survey["has_flammable"]
		&"flood", &"major_flood", &"hurricane": return survey["has_shore"]
		&"riot": return riot_ok and survey["has_road"]
		&"mass_riots": return riot_ok and survey["has_road"] \
			and (not natural or stats.population >= DisasterParams.MASS_RIOT_POPULATION)
		&"hazard": return not natural or int(survey["max_pollution"]) >= DisasterParams.HAZARD_POLLUTION
		&"earthquake", &"tornado": return true
		&"monster": return not natural or stats.population >= DisasterParams.MONSTER_POPULATION
		&"meltdown": return survey["has_nuclear"]
		&"microwave": return survey["has_microwave"]
		&"volcano": return not natural or int(survey["max_ground"]) >= DisasterParams.VOLCANO_MIN_PEAK
		&"chemical_spill": return survey["has_industrial"]
		&"plane_crash": return not natural or survey["has_runway"] \
			or stats.population >= DisasterParams.PLANE_CRASH_POPULATION
	return false


## One pass over the map collecting everything the preconditions need.
func _survey(city: City) -> Dictionary:
	var s := {
		"has_flammable": false, "has_shore": false, "has_road": false, "has_nuclear": false,
		"has_microwave": false, "has_industrial": false, "has_runway": false,
		"max_ground": 0, "peak": Vector2i(64, 64), "max_pollution": 0, "polluted": Vector2i(-1, -1),
	}
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := city.building_at(x, y)
			if not s["has_flammable"] and _spread_odds(id) > 0 and not city.is_water(x, y):
				s["has_flammable"] = true
			if not s["has_road"] and Buildings.is_road_like(id):
				s["has_road"] = true
			match id:
				Buildings.NUCLEAR_PLANT: s["has_nuclear"] = true
				Buildings.MICROWAVE_PLANT: s["has_microwave"] = true
				Buildings.RUNWAY, Buildings.RUNWAY_CROSS: s["has_runway"] = true
			if Buildings.category(id) == Buildings.Category.INDUSTRIAL:
				s["has_industrial"] = true
			if not city.is_water(x, y):
				var h := city.ground_height(x, y)
				if h > int(s["max_ground"]):
					s["max_ground"] = h
					s["peak"] = Vector2i(x, y)
				if not s["has_shore"] and _touches_water(city, x, y):
					s["has_shore"] = true
	for cy in City.HALF:
		for cx in City.HALF:
			var p := city.pollution.at(cx, cy)
			if p > int(s["max_pollution"]):
				s["max_pollution"] = p
				s["polluted"] = Vector2i(cx * 2, cy * 2)
	return s


# ── Starting a disaster ──────────────────────────────────────────────────

func _start(ctx: SimContext, kind: StringName, at: Vector2i, survey: Dictionary) -> bool:
	var point := _pick_point(ctx, kind, at, survey)
	if point.x < 0:
		return false
	var major := not _is_fire_only(kind)
	if major:
		_active = {"kind": String(kind), "x": point.x, "y": point.y, "remaining": 1, "wrecked": 0, "burned": 0}
	var ok := true
	match kind:
		&"fire":
			ok = _ignite(ctx, point.x, point.y)
		&"firestorm":
			ok = _ignite_spiral(ctx, point, DisasterParams.FIRESTORM_FIRES) > 0
		&"flood":
			_begin_flood(ctx, point, DisasterParams.FLOOD_SEEDS, DisasterParams.FLOOD_DAYS)
		&"major_flood":
			_begin_flood(ctx, point, DisasterParams.MAJOR_FLOOD_SEEDS, DisasterParams.MAJOR_FLOOD_DAYS)
		&"riot":
			_riots[point] = ctx.rng.below(4)
			_active["remaining"] = DisasterParams.RIOT_DAYS
		&"mass_riots":
			ok = _begin_mass_riots(ctx, point)
			_active["remaining"] = DisasterParams.MASS_RIOT_DAYS
		&"hazard":
			_begin_hazard(ctx, point)
		&"earthquake":
			_shake(ctx, point)
			_active["remaining"] = DisasterParams.EARTHQUAKE_AFTERSHOCK_DAYS
		&"tornado":
			_entities.append({"kind": "tornado", "x": point.x, "y": point.y, "frame": 0,
				"heading": ctx.rng.below(8)})
			_active["remaining"] = DisasterParams.TORNADO_DAYS
		&"monster":
			var edge := _edge_point(ctx)
			_entities.append({"kind": "monster", "x": edge.x, "y": edge.y, "frame": 0,
				"heading": ctx.rng.below(8), "tx": point.x, "ty": point.y, "arrived": false})
			_active["remaining"] = DisasterParams.MONSTER_DAYS
		&"meltdown":
			_begin_meltdown(ctx, point)
			_active["remaining"] = DisasterParams.MELTDOWN_DAYS
		&"microwave":
			_entities.append({"kind": "beam", "x": point.x + 1, "y": point.y + 1, "frame": 0,
				"heading": ctx.rng.below(8)})
			_active["remaining"] = DisasterParams.BEAM_DAYS
		&"volcano":
			_raise_cone(ctx, point)
			_active["remaining"] = DisasterParams.VOLCANO_DAYS
		&"chemical_spill":
			_begin_spill(ctx, point)
			_active["remaining"] = DisasterParams.CONTAMINATION_SPREAD_DAYS
		&"hurricane":
			var target := _developed_centroid(ctx.city)
			_entities.append({"kind": "hurricane", "x": point.x, "y": point.y, "frame": 0,
				"heading": _heading_toward(point, target), "tx": target.x, "ty": target.y})
			_flood_remaining = DisasterParams.HURRICANE_FLOOD_DAYS
			_active["remaining"] = DisasterParams.HURRICANE_DAYS
		&"plane_crash":
			var edge := _edge_point(ctx)
			_entities.append({"kind": "plane", "x": edge.x, "y": edge.y, "frame": 0,
				"heading": _heading_toward(edge, point), "tx": point.x, "ty": point.y})
			_active["remaining"] = PLANE_MAX_DAYS
	if not ok:
		if major:
			_active = {}
			_entities.clear()
		return false
	var args := {"kind": String(kind), "x": point.x, "y": point.y}
	ctx.events.report(&"disaster_started", args, 3)
	ctx.events.notify(&"disaster", args)
	if major and _count_anchors(ctx.city, Buildings.FIRE_STATION) == 0 \
			and _count_anchors(ctx.city, Buildings.POLICE_STATION) == 0 \
			and not _has_category(ctx.city, Buildings.Category.MILITARY):
		ctx.events.notify(&"national_guard", {})
	_sync_stats(ctx)
	return true


func _pick_point(ctx: SimContext, kind: StringName, at: Vector2i, survey: Dictionary) -> Vector2i:
	var city := ctx.city
	var given := city.in_bounds(at.x, at.y)
	match kind:
		&"fire":
			if given:
				return _spiral_find(city, at, FUEL_SEARCH_RADIUS, func(p: Vector2i) -> bool:
					return not city.is_water(p.x, p.y) and _spread_odds(city.building_at(p.x, p.y)) > 0)
			# An unplaced fire breaks out where there is something to burn
			# together: a built-up lot first, a thicket of trees otherwise.
			var built := _random_tile_where(ctx, func(p: Vector2i) -> bool:
				return Buildings.is_developed(city.building_at(p.x, p.y)) and _spread_odds(city.building_at(p.x, p.y)) > 0)
			if built.x >= 0:
				return built
			var thicket := _random_tile_where(ctx, func(p: Vector2i) -> bool:
				if city.is_water(p.x, p.y) or _spread_odds(city.building_at(p.x, p.y)) <= 0:
					return false
				var burnable := 0
				for d in DIRS_4:
					if _spread_odds(city.building_at(p.x + d.x, p.y + d.y)) > 0:
						burnable += 1
				return burnable >= 2)
			if thicket.x >= 0:
				return thicket
			return _random_tile_where(ctx, func(p: Vector2i) -> bool:
				return not city.is_water(p.x, p.y) and _spread_odds(city.building_at(p.x, p.y)) > 0)
		&"flood", &"major_flood", &"hurricane":
			var shore := _shoreline(city)
			if shore.is_empty():
				return Vector2i(-1, -1)
			if given:
				return _nearest_of(shore, at)
			return ctx.rng.pick(shore)
		&"riot", &"mass_riots":
			var center := at if given else _random_developed_tile(ctx)
			return _spiral_find(city, center, ROAD_SEARCH_RADIUS, func(p: Vector2i) -> bool:
				return Buildings.is_road_like(city.building_at(p.x, p.y)))
		&"hazard":
			if given:
				return at
			if int(survey["max_pollution"]) < DisasterParams.HAZARD_POLLUTION:
				return Vector2i(-1, -1)
			return survey["polluted"]
		&"meltdown":
			return _plant_anchor(ctx, Buildings.NUCLEAR_PLANT, at)
		&"microwave":
			return _plant_anchor(ctx, Buildings.MICROWAVE_PLANT, at)
		&"volcano":
			return at if given else survey["peak"]
		&"chemical_spill":
			if given and Buildings.category(city.building_at(at.x, at.y)) == Buildings.Category.INDUSTRIAL:
				return city.anchor_of(at.x, at.y)
			var found := _random_tile_where(ctx, func(p: Vector2i) -> bool:
				return Buildings.category(city.building_at(p.x, p.y)) == Buildings.Category.INDUSTRIAL)
			return city.anchor_of(found.x, found.y) if found.x >= 0 else found
		&"monster":
			return at if given else _developed_centroid(city)
	if given:
		return at
	return _random_developed_tile(ctx)


func _plant_anchor(ctx: SimContext, plant_id: int, at: Vector2i) -> Vector2i:
	var city := ctx.city
	if city.in_bounds(at.x, at.y) and city.building_at(at.x, at.y) == plant_id:
		return city.anchor_of(at.x, at.y)
	var found := _random_tile_where(ctx, func(p: Vector2i) -> bool:
		return city.building_at(p.x, p.y) == plant_id)
	return city.anchor_of(found.x, found.y) if found.x >= 0 else found


# ── Onsets ───────────────────────────────────────────────────────────────

func _begin_flood(ctx: SimContext, point: Vector2i, seeds: int, days: int) -> void:
	var shore := _shoreline(ctx.city)
	shore.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, point) < _chebyshev(b, point))
	for i in mini(seeds, shore.size()):
		_flood_tile(ctx, shore[i])
	_flood_remaining = days


func _begin_mass_riots(ctx: SimContext, center: Vector2i) -> bool:
	var city := ctx.city
	var placed := 0
	for i in DisasterParams.MASS_RIOT_SEEDS:
		var spread := DisasterParams.MASS_RIOT_SPREAD
		var probe := center + Vector2i(ctx.rng.below(spread * 2 + 1) - spread, ctx.rng.below(spread * 2 + 1) - spread)
		var road := _spiral_find(city, probe, 8, func(p: Vector2i) -> bool:
			return Buildings.is_road_like(city.building_at(p.x, p.y)))
		if road.x < 0:
			continue
		_riots[road] = ctx.rng.below(4)
		ctx.events.mark_tile(road.x, road.y)
		placed += 1
	return placed > 0


func _begin_hazard(ctx: SimContext, point: Vector2i) -> void:
	_contaminate(ctx, point, 0)
	for d in DIRS_4:
		var n := point + d
		_ignite(ctx, n.x, n.y)


func _begin_meltdown(ctx: SimContext, anchor: Vector2i) -> void:
	var city := ctx.city
	var size := Buildings.size(Buildings.NUCLEAR_PLANT)
	_wreck(ctx, anchor.x, anchor.y)
	for dy in size.y:
		for dx in size.x:
			_contaminate(ctx, anchor + Vector2i(dx, dy), DisasterParams.CONTAMINATION_SPREAD_DAYS)
	var center := anchor + size / 2
	var r := DisasterParams.MELTDOWN_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := center + Vector2i(dx, dy)
			if not city.in_bounds(p.x, p.y) or not ctx.rng.chance(1, DisasterParams.MELTDOWN_HIT_ODDS):
				continue
			if ctx.rng.chance(1, DisasterParams.MELTDOWN_FIRE_ODDS):
				_ignite(ctx, p.x, p.y)
			elif _wreck(ctx, p.x, p.y) > 0 and ctx.rng.chance(1, 2):
				_contaminate(ctx, p, 0)


func _begin_spill(ctx: SimContext, anchor: Vector2i) -> void:
	var city := ctx.city
	var id := city.building_at(anchor.x, anchor.y)
	var size := Buildings.size(id)
	_wreck(ctx, anchor.x, anchor.y)
	for dy in size.y:
		for dx in size.x:
			_contaminate(ctx, anchor + Vector2i(dx, dy), DisasterParams.CONTAMINATION_SPREAD_DAYS)
	var r := DisasterParams.SPILL_RADIUS
	for i in DisasterParams.SPILL_SCATTER:
		var p := anchor + Vector2i(ctx.rng.below(r * 2 + 1) - r, ctx.rng.below(r * 2 + 1) - r)
		if city.in_bounds(p.x, p.y) and not city.is_water(p.x, p.y):
			_contaminate(ctx, p, 0)


func _shake(ctx: SimContext, center: Vector2i) -> void:
	var city := ctx.city
	var r := DisasterParams.EARTHQUAKE_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := center + Vector2i(dx, dy)
			if not city.in_bounds(p.x, p.y) or not ctx.rng.chance(1, DisasterParams.EARTHQUAKE_HIT_ODDS):
				continue
			if not _is_built(city.building_at(p.x, p.y)):
				continue
			if ctx.rng.chance(1, DisasterParams.EARTHQUAKE_FIRE_ODDS):
				_ignite(ctx, p.x, p.y)
			else:
				_wreck(ctx, p.x, p.y)


## Lift the vent by VOLCANO_RISE; the ground around it is pulled up into a
## cone one level per ring and every tile the cone touches is cleared.
func _raise_cone(ctx: SimContext, vent: Vector2i) -> void:
	var city := ctx.city
	var peak := clampi(city.ground_height(vent.x, vent.y) + DisasterParams.VOLCANO_RISE, 0, City.ALT_MASK)
	var changed: Array[Vector2i]
	if city.terrain_surface is TerrainSurface:
		changed = _raise_lattice_cone(city, city.terrain_surface as TerrainSurface, vent, peak)
	else:
		changed = Builder.set_ground_height(city, vent.x, vent.y, peak)
	var rect := Rect2i(vent, Vector2i.ONE)
	for p in changed:
		rect = rect.expand(p)
		var id := city.building_at(p.x, p.y)
		if id == Buildings.NONE or city.is_water(p.x, p.y):
			continue
		_wreck(ctx, p.x, p.y, false)
		city.building.put(p.x, p.y, Buildings.NONE)
	ctx.events.mark_dirty(rect)


## Raise the vent on a city's ground lattice, the editable truth its 3D ground
## and saves follow: pin the vent's corners at `peak`, let the lattice pull
## its neighbours into a cone, drain water the ground rose through and
## re-project. Unlike TerrainEditor the eruption does not stop for buildings;
## the caller clears them. Returns the tiles whose terrain or height changed,
## in map order.
static func _raise_lattice_cone(city: City, lattice: TerrainSurface, vent: Vector2i, peak: int) -> Array[Vector2i]:
	var terrain := city.terrain.data.duplicate()
	var altitude := city.altitude.data.duplicate()
	var pins: Dictionary = {}
	for v in TerrainSurface.tile_vertices(vent.x, vent.y):
		lattice.set_vertex(v.x, v.y, peak)
		pins[v] = true
	var repair := lattice.normalize(Rect2i(vent, Vector2i.ONE), pins)
	# The ring around the vent shares its corners and changes shape with it.
	var rect := TerrainSurface.clamp_rect(Rect2i(vent - Vector2i.ONE, Vector2i(3, 3)))
	var ripple: Rect2i = repair["rect"]
	if ripple.size.x > 0:
		rect = TerrainSurface.clamp_rect(rect.merge(ripple))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var w := lattice.water_level(x, y)
			if w != TerrainSurface.NO_WATER and w <= lattice.tile_base(x, y):
				lattice.clear_water(x, y)
	lattice.project(city, rect)
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * City.WIDTH + x
			if city.terrain.data[i] != terrain[i] or city.altitude.data[i] != altitude[i]:
				out.append(Vector2i(x, y))
	return out


# ── Daily progression of the running disaster ────────────────────────────

func _step_active(ctx: SimContext) -> void:
	match String(_active["kind"]):
		"earthquake":
			if ctx.rng.chance(1, 2):
				var t := _random_developed_tile(ctx)
				if t.x >= 0:
					_wreck(ctx, t.x, t.y)
		"tornado":
			_step_tornado(ctx)
		"monster":
			_step_monster(ctx)
		"hurricane":
			_step_hurricane(ctx)
		"plane_crash":
			_step_plane(ctx)
		"microwave":
			_step_beam(ctx)
		"volcano":
			_step_volcano(ctx)
	_active["remaining"] = int(_active["remaining"]) - 1


func _step_tornado(ctx: SimContext) -> void:
	var e := _entity("tornado")
	if e.is_empty():
		return
	var pos := Vector2i(int(e["x"]), int(e["y"]))
	_wreck_wind(ctx, pos)
	var heading := int(e["heading"])
	if ctx.rng.chance(1, 3):
		heading = posmod(heading + ctx.rng.below(3) - 1, 8)
	for i in DisasterParams.TORNADO_STEP:
		pos += DIRS_8[heading]
		if not ctx.city.in_bounds(pos.x, pos.y):
			_remove_entity("tornado")
			return
		_wreck_wind(ctx, pos)
	e["x"] = pos.x
	e["y"] = pos.y
	e["heading"] = heading
	e["frame"] = int(e["frame"]) + 1
	if ctx.rng.chance(1, DisasterParams.TORNADO_VANISH_ODDS):
		_remove_entity("tornado")


func _step_monster(ctx: SimContext) -> void:
	var e := _entity("monster")
	if e.is_empty():
		return
	var pos := Vector2i(int(e["x"]), int(e["y"]))
	var target := Vector2i(int(e["tx"]), int(e["ty"]))
	if not bool(e["arrived"]) and _chebyshev(pos, target) <= DisasterParams.MONSTER_HOVER_RADIUS:
		e["arrived"] = true
	if bool(e["arrived"]):
		e["heading"] = ctx.rng.below(8)
		pos += DIRS_8[int(e["heading"])] * (1 + ctx.rng.below(DisasterParams.MONSTER_STEP))
	else:
		var diff := target - pos
		pos += Vector2i(clampi(diff.x, -DisasterParams.MONSTER_STEP, DisasterParams.MONSTER_STEP),
			clampi(diff.y, -DisasterParams.MONSTER_STEP, DisasterParams.MONSTER_STEP))
		e["heading"] = _heading_toward(pos, target)
	pos = Vector2i(clampi(pos.x, 0, City.WIDTH - 1), clampi(pos.y, 0, City.HEIGHT - 1))
	e["x"] = pos.x
	e["y"] = pos.y
	e["frame"] = int(e["frame"]) + 1
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := pos + Vector2i(dx, dy)
			if not ctx.city.in_bounds(p.x, p.y):
				continue
			var id := ctx.city.building_at(p.x, p.y)
			if id == Buildings.NONE or Buildings.is_rubble(id):
				continue
			if ctx.rng.chance(1, DisasterParams.MONSTER_WRECK_ODDS):
				_wreck_wind(ctx, p)
			elif ctx.rng.chance(1, DisasterParams.MONSTER_IGNITE_ODDS):
				_ignite(ctx, p.x, p.y)
	if bool(e["arrived"]) and ctx.rng.chance(1, DisasterParams.MONSTER_LEAVE_ODDS):
		_remove_entity("monster")


func _step_hurricane(ctx: SimContext) -> void:
	var e := _entity("hurricane")
	if e.is_empty():
		return
	if int(_active["remaining"]) <= 1:
		_remove_entity("hurricane")
		return
	var city := ctx.city
	var pos := Vector2i(int(e["x"]), int(e["y"]))
	var target := Vector2i(int(e["tx"]), int(e["ty"]))
	var heading := _heading_toward(pos, target)
	if ctx.rng.chance(1, 4):
		heading = posmod(heading + ctx.rng.below(3) - 1, 8)
	pos += DIRS_8[heading]
	pos = Vector2i(clampi(pos.x, 0, City.WIDTH - 1), clampi(pos.y, 0, City.HEIGHT - 1))
	e["x"] = pos.x
	e["y"] = pos.y
	e["heading"] = heading
	e["frame"] = int(e["frame"]) + 1
	var r := DisasterParams.HURRICANE_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := pos + Vector2i(dx, dy)
			if not city.in_bounds(p.x, p.y):
				continue
			var id := city.building_at(p.x, p.y)
			if id == Buildings.NONE or Buildings.is_rubble(id):
				continue
			if ctx.rng.chance(1, DisasterParams.HURRICANE_WRECK_ODDS):
				_wreck_wind(ctx, p)
	var candidates: Array[Vector2i] = []
	var fr := DisasterParams.HURRICANE_FLOOD_RADIUS
	for dy in range(-fr, fr + 1):
		for dx in range(-fr, fr + 1):
			var p := pos + Vector2i(dx, dy)
			if city.in_bounds(p.x, p.y) and not city.is_water(p.x, p.y) and _touches_water(city, p.x, p.y):
				candidates.append(p)
	for i in mini(DisasterParams.HURRICANE_FLOOD_SEEDS, candidates.size()):
		var pick: Vector2i = candidates[ctx.rng.below(candidates.size())]
		_flood_tile(ctx, pick)


func _step_plane(ctx: SimContext) -> void:
	var e := _entity("plane")
	if e.is_empty():
		return
	var pos := Vector2i(int(e["x"]), int(e["y"]))
	var target := Vector2i(int(e["tx"]), int(e["ty"]))
	e["frame"] = int(e["frame"]) + 1
	if _chebyshev(pos, target) > DisasterParams.PLANE_STEP:
		var diff := target - pos
		pos += Vector2i(clampi(diff.x, -DisasterParams.PLANE_STEP, DisasterParams.PLANE_STEP),
			clampi(diff.y, -DisasterParams.PLANE_STEP, DisasterParams.PLANE_STEP))
		e["x"] = pos.x
		e["y"] = pos.y
		e["heading"] = _heading_toward(pos, target)
		return
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			var p := target + Vector2i(dx, dy)
			if dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1:
				_wreck(ctx, p.x, p.y)
			else:
				_ignite(ctx, p.x, p.y)
	_remove_entity("plane")
	_active["remaining"] = 1


func _step_beam(ctx: SimContext) -> void:
	var e := _entity("beam")
	if e.is_empty():
		return
	var city := ctx.city
	var pos := Vector2i(int(e["x"]), int(e["y"]))
	var heading := posmod(int(e["heading"]) + ctx.rng.below(3) - 1, 8)
	for i in DisasterParams.BEAM_STEP:
		pos += DIRS_8[heading]
		if not city.in_bounds(pos.x, pos.y):
			_remove_entity("beam")
			return
		if not _ignite(ctx, pos.x, pos.y) and _is_built(city.building_at(pos.x, pos.y)):
			_wreck(ctx, pos.x, pos.y)
	e["x"] = pos.x
	e["y"] = pos.y
	e["heading"] = heading
	e["frame"] = int(e["frame"]) + 1


func _step_volcano(ctx: SimContext) -> void:
	var vent := Vector2i(int(_active["x"]), int(_active["y"]))
	var r := DisasterParams.VOLCANO_EMBER_RADIUS
	for i in DisasterParams.VOLCANO_FIRES_PER_DAY:
		var p := vent + Vector2i(ctx.rng.below(r * 2 + 1) - r, ctx.rng.below(r * 2 + 1) - r)
		_ignite(ctx, p.x, p.y)


func _finish_if_done(ctx: SimContext) -> void:
	if _active.is_empty():
		return
	var remaining := int(_active["remaining"])
	var going := remaining > 0
	match String(_active["kind"]):
		"flood", "major_flood":
			going = _flood_remaining > 0 or not _flooded.is_empty()
		"hurricane":
			going = remaining > 0 or _flood_remaining > 0 or not _flooded.is_empty()
		"riot", "mass_riots":
			going = remaining > 0 and not _riots.is_empty()
		"tornado":
			going = remaining > 0 and not _entity("tornado").is_empty()
		"monster":
			going = remaining > 0 and not _entity("monster").is_empty()
		"plane_crash":
			going = remaining > 0 and not _entity("plane").is_empty()
		"microwave":
			going = remaining > 0 and not _entity("beam").is_empty()
		"meltdown", "chemical_spill":
			going = remaining > 0 or not _hot.is_empty()
	if going:
		return
	var args := {"kind": String(_active["kind"]), "x": int(_active["x"]), "y": int(_active["y"]),
		"wrecked": int(_active["wrecked"]), "burned": int(_active["burned"])}
	ctx.events.report(&"disaster_ended", args, 2)
	_active = {}
	_entities.clear()
	for t in _riots.keys():
		var p: Vector2i = t
		ctx.events.mark_tile(p.x, p.y)
	_riots.clear()


# ── Fires ────────────────────────────────────────────────────────────────

func _step_fires(ctx: SimContext) -> void:
	if _fires.is_empty():
		return
	var burning: Array = _fires.keys()
	for key_tile in burning:
		var t: Vector2i = key_tile
		if not _fires.has(t):
			continue
		var fuel := int(_fires[t]) - 1
		if fuel <= 0:
			_fires.erase(t)
			if _wreck(ctx, t.x, t.y) > 0 and not _active.is_empty():
				_active["burned"] = int(_active["burned"]) + 1
			ctx.events.mark_tile(t.x, t.y)
			continue
		_fires[t] = fuel
		var out_chance := DisasterParams.FIRE_SELF_EXTINGUISH \
			+ _fire_strength(ctx, t) / DisasterParams.FIRE_COVER_DIVISOR + _crew_odds(t, true)
		if ctx.rng.below(256) < out_chance:
			_fires.erase(t)
			ctx.events.mark_tile(t.x, t.y)
			continue
		for d in DIRS_4:
			var n := t + d
			if not ctx.city.in_bounds(n.x, n.y) or _fires.has(n) or ctx.city.is_water(n.x, n.y):
				continue
			var id := ctx.city.building_at(n.x, n.y)
			var odds := _spread_odds(id)
			if odds > 0 and ctx.rng.below(DisasterParams.SPREAD_DENOMINATOR) < odds:
				_ignite(ctx, n.x, n.y)


func _ignite(ctx: SimContext, x: int, y: int) -> bool:
	var city := ctx.city
	if not city.in_bounds(x, y):
		return false
	var t := Vector2i(x, y)
	if _fires.has(t) or city.is_water(x, y):
		return false
	var id := city.building_at(x, y)
	if _spread_odds(id) <= 0:
		return false
	_fires[t] = _fuel_days(id)
	ctx.events.mark_tile(x, y)
	if not _outbreak_reported:
		_outbreak_reported = true
		ctx.events.report(&"fire_reported", {"x": x, "y": y}, 2)
	return true


## Ignite up to `count` tiles in rings around `center`. Returns how many caught.
func _ignite_spiral(ctx: SimContext, center: Vector2i, count: int) -> int:
	var lit := 0
	for r in range(0, 13):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if _ignite(ctx, center.x + dx, center.y + dy):
					lit += 1
					if lit >= count:
						return lit
	return lit


func _spread_odds(id: int) -> int:
	var cat := Buildings.category(id)
	var base: int = DisasterParams.SPREAD_ODDS_BY_CATEGORY.get(cat, 0)
	if base <= 0:
		return 0
	if cat == Buildings.Category.TREE:
		return base / 2 if id == Buildings.SMALL_PARK else base
	var width := Buildings.size(id).x
	return maxi(1, base - (width - 1) * DisasterParams.SPREAD_FOOTPRINT_PENALTY)


func _fuel_days(id: int) -> int:
	if Buildings.category(id) == Buildings.Category.TREE:
		return DisasterParams.FUEL_DAYS_TREES
	return DisasterParams.FUEL_DAYS_BY_FOOTPRINT.get(Buildings.size(id).x, 6)


func _fire_strength(ctx: SimContext, t: Vector2i) -> int:
	var services := ctx.system(&"services")
	if services != null and services.has_method("fire_strength_at"):
		return int(services.call("fire_strength_at", t.x, t.y))
	return ctx.city.fire_cover_at(t.x, t.y)


func _police_strength(ctx: SimContext, t: Vector2i) -> int:
	var services := ctx.system(&"services")
	if services != null and services.has_method("police_strength_at"):
		return int(services.call("police_strength_at", t.x, t.y))
	return ctx.city.police_at(t.x, t.y)


## Best crew effect on a tile, out of 256, for fires or (when false) riots.
func _crew_odds(t: Vector2i, for_fire: bool) -> int:
	var best := 0
	for c in _crews:
		if _chebyshev(Vector2i(int(c["x"]), int(c["y"])), t) > DisasterParams.CREW_RADIUS:
			continue
		match String(c["kind"]):
			"fire":
				if for_fire:
					best = maxi(best, DisasterParams.CREW_FIRE_ODDS)
			"police":
				if not for_fire:
					best = maxi(best, DisasterParams.CREW_POLICE_ODDS)
			"military":
				best = maxi(best, DisasterParams.CREW_MILITARY_ODDS)
	return best


# ── Riots ────────────────────────────────────────────────────────────────

func _step_riots(ctx: SimContext) -> void:
	if _riots.is_empty():
		return
	var city := ctx.city
	var rioting: Array = _riots.keys()
	for key_tile in rioting:
		var t: Vector2i = key_tile
		if not _riots.has(t):
			continue
		var heading := int(_riots[t])
		var disperse := 0
		if _police_strength(ctx, t) >= DisasterParams.RIOT_POLICE_SUPPRESS:
			disperse = DisasterParams.RIOT_DISPERSE_ODDS
		disperse = maxi(disperse, _crew_odds(t, false))
		if disperse > 0 and ctx.rng.below(256) < disperse:
			_riots.erase(t)
			ctx.events.mark_tile(t.x, t.y)
			continue
		if ctx.rng.chance(1, DisasterParams.RIOT_FADE_ODDS):
			_riots.erase(t)
			ctx.events.mark_tile(t.x, t.y)
			continue
		if ctx.rng.chance(1, DisasterParams.RIOT_WRECK_ODDS):
			var victim := t + DIRS_4[ctx.rng.below(4)]
			if city.in_bounds(victim.x, victim.y) and Buildings.is_zone_building(city.building_at(victim.x, victim.y)):
				_wreck(ctx, victim.x, victim.y)
				continue
		if ctx.rng.chance(1, DisasterParams.RIOT_IGNITE_ODDS):
			var victim := t + DIRS_4[ctx.rng.below(4)]
			if _ignite(ctx, victim.x, victim.y):
				continue
		var options: Array[Vector2i] = []
		for d in DIRS_4:
			var n := t + d
			if city.in_bounds(n.x, n.y) and _walkable(city, n) and not _riots.has(n):
				options.append(n)
		if options.is_empty():
			continue
		var next := t + DIRS_4[heading]
		if not options.has(next):
			next = options[ctx.rng.below(options.size())]
		if not ctx.rng.chance(1, DisasterParams.RIOT_SPLIT_ODDS):
			_riots.erase(t)
		_riots[next] = heading
		ctx.events.mark_tile(t.x, t.y)
		ctx.events.mark_tile(next.x, next.y)


func _walkable(city: City, t: Vector2i) -> bool:
	var id := city.building_at(t.x, t.y)
	return (Buildings.is_road_like(id) or Buildings.is_rubble(id)) and not city.is_water(t.x, t.y)


# ── Contamination ────────────────────────────────────────────────────────

func _step_hot(ctx: SimContext) -> void:
	if _hot.is_empty():
		return
	var hot: Array = _hot.keys()
	for key_tile in hot:
		var t: Vector2i = key_tile
		if not _hot.has(t):
			continue
		var days := int(_hot[t])
		if ctx.rng.chance(1, 2):
			var target := _lowest_neighbor(ctx, t)
			if target.x >= 0:
				_contaminate(ctx, target, days - 1)
		days -= 1
		if days <= 0:
			_hot.erase(t)
		else:
			_hot[t] = days


## Lowest cardinal land neighbor that is not yet contaminated, or (-1,-1).
func _lowest_neighbor(ctx: SimContext, t: Vector2i) -> Vector2i:
	var city := ctx.city
	var best := Vector2i(-1, -1)
	var best_h := 1 << 8
	var start := ctx.rng.below(4)
	for i in 4:
		var n := t + DIRS_4[(start + i) % 4]
		if not city.in_bounds(n.x, n.y) or city.is_water(n.x, n.y):
			continue
		if city.building_at(n.x, n.y) == Buildings.CONTAMINATION:
			continue
		var h := city.ground_height(n.x, n.y)
		if h < best_h:
			best_h = h
			best = n
	return best


## Turn a tile into contaminated ground, wrecking whatever stood there.
func _contaminate(ctx: SimContext, t: Vector2i, hot_days: int) -> void:
	var city := ctx.city
	if not city.in_bounds(t.x, t.y) or city.is_water(t.x, t.y):
		return
	var id := city.building_at(t.x, t.y)
	if id != Buildings.NONE and not Buildings.is_rubble(id):
		_wreck(ctx, t.x, t.y, false)
	city.building.put(t.x, t.y, Buildings.CONTAMINATION)
	city.set_flag(t.x, t.y, SERVICE_BITS, false)
	_fires.erase(t)
	if hot_days > 0:
		_hot[t] = maxi(int(_hot.get(t, 0)), hot_days)
	ctx.events.mark_tile(t.x, t.y)


# ── Floods ───────────────────────────────────────────────────────────────

func _step_flood(ctx: SimContext) -> void:
	if _flooded.is_empty() and _flood_remaining <= 0:
		return
	var city := ctx.city
	var wet: Array = _flooded.keys()
	if _flood_remaining > DisasterParams.FLOOD_RECEDE_DAYS:
		for key_tile in wet:
			var t: Vector2i = key_tile
			if ctx.rng.chance(1, DisasterParams.FLOOD_SPREAD_ODDS):
				var n := t + DIRS_4[ctx.rng.below(4)]
				if city.in_bounds(n.x, n.y) and not city.is_water(n.x, n.y) \
						and city.ground_height(n.x, n.y) <= city.ground_height(t.x, t.y):
					_flood_tile(ctx, n)
			var id := city.building_at(t.x, t.y)
			if Buildings.is_developed(id) and ctx.rng.chance(1, DisasterParams.FLOOD_WRECK_ODDS):
				_wreck(ctx, t.x, t.y)
	elif _flood_remaining > 0:
		for key_tile in wet:
			var t: Vector2i = key_tile
			if ctx.rng.chance(1, DisasterParams.FLOOD_DRAIN_ODDS):
				_drain_tile(ctx, t)
	else:
		for key_tile in wet:
			var t: Vector2i = key_tile
			_drain_tile(ctx, t)
	_flood_remaining = maxi(0, _flood_remaining - 1)


func _flood_tile(ctx: SimContext, t: Vector2i) -> void:
	if _flooded.has(t):
		return
	_flooded[t] = 1
	ctx.city.flood_overlay[t] = 1
	_fires.erase(t)
	_flood_total += 1
	ctx.events.mark_tile(t.x, t.y)


func _drain_tile(ctx: SimContext, t: Vector2i) -> void:
	_flooded.erase(t)
	ctx.city.flood_overlay.erase(t)
	ctx.events.mark_tile(t.x, t.y)


# ── Damage ───────────────────────────────────────────────────────────────

## Clear the footprint under (x, y) and leave rubble on its dry tiles.
## Returns the number of tiles cleared.
func _wreck(ctx: SimContext, x: int, y: int, rubble: bool = true) -> int:
	var city := ctx.city
	if not city.in_bounds(x, y):
		return 0
	var id := city.building_at(x, y)
	if id == Buildings.NONE or Buildings.is_rubble(id):
		return 0
	var rect := city.clear_footprint(x, y)
	var n := 0
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if not city.in_bounds(tx, ty):
				continue
			n += 1
			_fires.erase(Vector2i(tx, ty))
			city.set_flag(tx, ty, SERVICE_BITS, false)
			if rubble and not city.is_water(tx, ty):
				city.building.put(tx, ty, Buildings.RUBBLE_1 + ctx.rng.below(4))
	ctx.events.mark_dirty(rect)
	if not _active.is_empty():
		_active["wrecked"] = int(_active["wrecked"]) + n
	return n


## Wind damage: trees are blown away, everything else becomes rubble.
func _wreck_wind(ctx: SimContext, p: Vector2i) -> void:
	var id := ctx.city.building_at(p.x, p.y)
	if id == Buildings.NONE or Buildings.is_rubble(id):
		return
	_wreck(ctx, p.x, p.y, Buildings.category(id) != Buildings.Category.TREE)


## Anything constructed: networks and buildings, not ground cover or rubble.
func _is_built(id: int) -> bool:
	return id > Buildings.SMALL_PARK


# ── Advisor ──────────────────────────────────────────────────────────────

func _compute_advice(ctx: SimContext) -> Array[StringName]:
	var out: Array[StringName] = []
	var stats := ctx.stats
	var city := ctx.city
	var pop := stats.population
	var anchors := PackedInt32Array()
	anchors.resize(Buildings.COUNT)
	var industrial_tiles := 0
	var commercial_tiles := 0
	var has_water := false
	var buildings := city.building.data
	var zones := city.zone.data
	var terrain := city.terrain.data
	var multi := UtilityParams.multi_tile_table()
	var categories := ScanTables.categories()
	for i: int in buildings.size():
		var id := buildings[i]
		if id != Buildings.NONE and (not multi[id] or (zones[i] & Zones.CORNER_NW)):
			anchors[id] += 1
		var cat := categories[id]
		if cat == Buildings.Category.INDUSTRIAL:
			industrial_tiles += 1
		elif cat == Buildings.Category.COMMERCIAL:
			commercial_tiles += 1
		if not has_water and (Terrain.is_water(terrain[i]) or city.flood_overlay.has(Vector2i(i % City.WIDTH, i / City.WIDTH))):
			has_water = true
	if _usage_high(stats.power_demand, stats.power_capacity) or stats.unpowered_buildings > 0:
		out.append(&"needs_power")
	var transit := anchors[Buildings.BUS_DEPOT] + anchors[Buildings.RAIL_STATION] + anchors[Buildings.SUBWAY_STATION]
	if transit < pop / DisasterParams.TRANSIT_PER_RESIDENT:
		out.append(&"needs_transit")
	if pop < DisasterParams.ADVICE_POPULATION_1:
		return out
	if anchors[Buildings.POLICE_STATION] + anchors[Buildings.PRISON] <= pop / DisasterParams.POLICE_PER_RESIDENT:
		out.append(&"needs_police")
	if anchors[Buildings.FIRE_STATION] <= pop / DisasterParams.FIRE_PER_RESIDENT:
		out.append(&"needs_fire_protection")
	if _usage_high(stats.water_demand, stats.water_capacity) or stats.unwatered_buildings > 0:
		out.append(&"needs_water")
	if pop < DisasterParams.ADVICE_POPULATION_2:
		return out
	if anchors[Buildings.HOSPITAL] <= pop / DisasterParams.HOSPITAL_PER_RESIDENT:
		out.append(&"needs_hospital")
	if anchors[Buildings.SCHOOL] <= pop / DisasterParams.SCHOOL_PER_RESIDENT:
		out.append(&"needs_school")
	if pop < DisasterParams.ADVICE_POPULATION_3:
		return out
	if industrial_tiles >= DisasterParams.SEAPORT_INDUSTRY_TILES and anchors[Buildings.CRANE] == 0:
		if has_water:
			out.append(&"needs_seaport")
		elif _neighbor_links(ctx) == 0:
			# A dry map's industry trades by road or rail with the neighbors.
			out.append(&"needs_industry_connections")
	if commercial_tiles >= DisasterParams.AIRPORT_COMMERCE_TILES \
			and anchors[Buildings.RUNWAY] + anchors[Buildings.RUNWAY_CROSS] == 0:
		out.append(&"needs_airport")
	# The same venues that raise the residential cap (ZoneParams.RECREATION_KEYS).
	var recreation := 0
	for k in ZoneParams.RECREATION_KEYS:
		recreation += anchors[Buildings.id_of(k)]
	if recreation < pop / DisasterParams.RECREATION_PER_RESIDENT:
		out.append(&"needs_recreation")
	return out


## Road and rail links to the neighbors, from the neighbor system.
func _neighbor_links(ctx: SimContext) -> int:
	var neighbors := ctx.system(&"neighbors")
	if neighbors != null and neighbors.has_method("link_count"):
		return int(neighbors.call("link_count"))
	return 0


func _usage_high(demand: int, capacity: int) -> bool:
	if demand <= 0:
		return false
	if capacity <= 0:
		return true
	return demand * 100 / capacity > DisasterParams.USAGE_WARNING_PERCENT


# ── Helpers ──────────────────────────────────────────────────────────────

func _sync_stats(ctx: SimContext) -> void:
	ctx.stats.active_fires = _fires.size()
	if _fires.is_empty():
		_outbreak_reported = false
	if not _active.is_empty():
		ctx.stats.active_disaster = StringName(String(_active["kind"]))
	elif not _fires.is_empty():
		ctx.stats.active_disaster = &"fire"
	else:
		ctx.stats.active_disaster = &""


func _is_fire_only(kind: StringName) -> bool:
	return DisasterParams.FIRE_ONLY_KINDS.has(kind)


func _entity(kind: String) -> Dictionary:
	for e in _entities:
		if String(e["kind"]) == kind:
			return e
	return {}


func _remove_entity(kind: String) -> void:
	for i in range(_entities.size() - 1, -1, -1):
		if String(_entities[i]["kind"]) == kind:
			_entities.remove_at(i)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _heading_toward(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	var step := Vector2i(signi(d.x), signi(d.y))
	for i in DIRS_8.size():
		if DIRS_8[i] == step:
			return i
	return 0


func _touches_water(city: City, x: int, y: int) -> bool:
	for d in DIRS_4:
		if city.in_bounds(x + d.x, y + d.y) and city.is_water(x + d.x, y + d.y):
			return true
	return false


## Dry tiles that touch water.
func _shoreline(city: City) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if not city.is_water(x, y) and _touches_water(city, x, y):
				out.append(Vector2i(x, y))
	return out


func _nearest_of(tiles: Array[Vector2i], to: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 20
	for t in tiles:
		var d := _chebyshev(t, to)
		if d < best_d:
			best_d = d
			best = t
	return best


## First tile in growing square rings around `center` that satisfies `test`.
func _spiral_find(city: City, center: Vector2i, max_radius: int, test: Callable) -> Vector2i:
	for r in range(0, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := center + Vector2i(dx, dy)
				if city.in_bounds(p.x, p.y) and test.call(p):
					return p
	return Vector2i(-1, -1)


## A random tile satisfying `test`: sampled first, then a full scan.
func _random_tile_where(ctx: SimContext, test: Callable) -> Vector2i:
	for i in 48:
		var p := Vector2i(ctx.rng.below(City.WIDTH), ctx.rng.below(City.HEIGHT))
		if test.call(p):
			return p
	var all: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var p := Vector2i(x, y)
			if test.call(p):
				all.append(p)
	if all.is_empty():
		return Vector2i(-1, -1)
	return all[ctx.rng.below(all.size())]


## A random developed tile, or any tile when nothing is built.
func _random_developed_tile(ctx: SimContext) -> Vector2i:
	var city := ctx.city
	var found := _random_tile_where(ctx, func(p: Vector2i) -> bool:
		return Buildings.is_developed(city.building_at(p.x, p.y)))
	if found.x >= 0:
		return found
	return Vector2i(ctx.rng.below(City.WIDTH), ctx.rng.below(City.HEIGHT))


## Average position of developed tiles, or the map centre.
func _developed_centroid(city: City) -> Vector2i:
	var sx := 0
	var sy := 0
	var n := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if Buildings.is_developed(city.building_at(x, y)):
				sx += x
				sy += y
				n += 1
	if n == 0:
		return Vector2i(City.WIDTH / 2, City.HEIGHT / 2)
	return Vector2i(sx / n, sy / n)


func _edge_point(ctx: SimContext) -> Vector2i:
	match ctx.rng.below(4):
		0: return Vector2i(ctx.rng.below(City.WIDTH), 0)
		1: return Vector2i(City.WIDTH - 1, ctx.rng.below(City.HEIGHT))
		2: return Vector2i(ctx.rng.below(City.WIDTH), City.HEIGHT - 1)
	return Vector2i(0, ctx.rng.below(City.HEIGHT))


func _count_anchors(city: City, id: int) -> int:
	var n := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.building_at(x, y) != id:
				continue
			if Buildings.is_multi_tile(id) and not (Zones.corners(city.zone.at(x, y)) & Zones.CORNER_NW):
				continue
			n += 1
	return n


func _has_category(city: City, cat: int) -> bool:
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if Buildings.category(city.building_at(x, y)) == cat:
				return true
	return false
