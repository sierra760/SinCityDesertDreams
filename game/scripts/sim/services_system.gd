# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Services system: police and fire coverage, prisons and civic facilities.
##
## Once a month it locates every service building, runs the prisons, and
## rebuilds the quarter-resolution `police` and `fire_cover` maps from the
## funded, powered stations. Facility counts are kept current for the
## population system. The building scan walks the packed layers directly.
## Rules: docs/simulation/services.md.
class_name ServicesSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/services_params.gd")

const CELLS := City.QUARTER
const BLOCKS := City.HALF

## Buildings the monthly scan keeps track of.
const TRACKED: Array[int] = [
	Buildings.POLICE_STATION, Buildings.FIRE_STATION, Buildings.PRISON,
	Buildings.HOSPITAL, Buildings.SCHOOL, Buildings.COLLEGE,
	Buildings.LIBRARY, Buildings.MUSEUM,
]

## Civic facilities reported through service_counts(), with their funding key.
const FACILITY_FUNDING := {
	Buildings.HOSPITAL: &"health", Buildings.SCHOOL: &"schools",
	Buildings.COLLEGE: &"colleges", Buildings.LIBRARY: &"", Buildings.MUSEUM: &"",
}

## Prison records keyed by anchor tile key.
var _prisons: Dictionary = {}
var _police_modifier := 0
var _last_arrests := 0
## Last scan: building id -> Array of {"anchor": Vector2i, "powered": bool}.
var _scan: Dictionary = {}
## Coverage ring index for each offset within reach, built once.
var _ring_offsets: Array[Array] = []
## The city and stats seen on the last call, for the getters.
var _city: City = null
var _stats: CityStats = null
## One byte per building id: whether the monthly scan tracks it.
var _tracked_tbl := PackedByteArray()


func _init() -> void:
	key = &"services"
	_build_rings()
	_tracked_tbl.resize(Buildings.COUNT)
	for id in TRACKED:
		_tracked_tbl[id] = 1


func setup(ctx: SimContext) -> void:
	_remember(ctx)
	_scan = _scan_buildings(ctx.city)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_remember(ctx)
	_scan = _scan_buildings(ctx.city)
	_update_prisons(ctx)
	_build_coverage(ctx)


func yearly(_ctx: SimContext) -> void:
	for k in _prisons:
		_prisons[k]["escapes"] = 0


func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_remember(ctx)
	_scan = _scan_buildings(ctx.city)


func _remember(ctx: SimContext) -> void:
	_city = ctx.city
	_stats = ctx.stats


# ── Getters ──────────────────────────────────────────────────────────────

## Police coverage at a tile, 0..255.
func police_strength_at(x: int, y: int) -> int:
	return _city.police_at(x, y) if _city != null else 0


## Fire coverage at a tile, 0..255.
func fire_strength_at(x: int, y: int) -> int:
	return _city.fire_cover_at(x, y) if _city != null else 0


## The bonus prisons add to police effectiveness: 0 or 1.
func police_modifier() -> int:
	return _police_modifier


## City-wide prison figures plus one record per prison.
func prison_report() -> Dictionary:
	var records: Array[Dictionary] = []
	var inmates := 0
	var guards := 0
	var capacity := 0
	var escapes := 0
	for k in _prisons:
		var rec: Dictionary = _prisons[k]
		var at := parse_tile_key(k)
		records.append({
			"x": at.x, "y": at.y,
			"inmates": int(rec["inmates"]), "guards": int(rec["guards"]),
			"capacity": int(rec["capacity"]), "utilization": int(rec["utilization"]),
			"escapes": int(rec["escapes"]), "powered": bool(rec["powered"]),
		})
		inmates += int(rec["inmates"])
		guards += int(rec["guards"])
		capacity += int(rec["capacity"])
		escapes += int(rec["escapes"])
	@warning_ignore("integer_division")
	var utilization := inmates * 100 / capacity if capacity > 0 else 0
	return {
		"prisons": records.size(), "inmates": inmates, "guards": guards,
		"capacity": capacity, "utilization": utilization, "escapes": escapes,
		"modifier": _police_modifier, "arrests": _last_arrests, "records": records,
	}


## Counts of hospitals, schools, colleges, libraries and museums, keyed by
## building key, with how many are powered and the funding that applies.
func service_counts() -> Dictionary:
	var out := {}
	for id in FACILITY_FUNDING:
		var found: Array = _scan.get(id, [])
		var powered := 0
		for entry in found:
			if bool(entry["powered"]):
				powered += 1
		var fund: StringName = FACILITY_FUNDING[id]
		var funding := 100
		if fund != &"" and _stats != null:
			funding = _stats.funding_of(fund)
		out[Buildings.key(id)] = {"count": found.size(), "powered": powered, "funding": funding}
	return out


# ── Scan ─────────────────────────────────────────────────────────────────

func _scan_buildings(city: City) -> Dictionary:
	var found := {}
	for id in TRACKED:
		found[id] = []
	var bld := city.building.data
	var zn := city.zone.data
	var flags := city.flags.data
	var i := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := bld[i]
			# The CORNER_NW tile picks each lot once; its position is the lot's
			# anchor, which a city saved at another rotation keeps elsewhere.
			if _tracked_tbl[id] != 0 and (zn[i] & Zones.CORNER_NW) != 0:
				var anchor := City.footprint_anchor(bld, zn, x, y)
				var list: Array = found[id]
				list.append({"anchor": anchor,
					"powered": _footprint_powered(flags, anchor.x, anchor.y, Buildings.size(id))})
			i += 1
	return found


## True when any tile of the footprint received power.
static func _footprint_powered(flags: PackedByteArray, ax: int, ay: int, s: Vector2i) -> bool:
	for dy in s.y:
		var y := ay + dy
		if y >= City.HEIGHT:
			break
		for dx in s.x:
			var x := ax + dx
			if x < City.WIDTH and (flags[y * City.WIDTH + x] & TileFlags.POWERED) != 0:
				return true
	return false


# ── Coverage ─────────────────────────────────────────────────────────────

## Group every offset within three cells into rings: the centre, the cardinal
## neighbours, the diagonals, the band two steps out and the band three out.
func _build_rings() -> void:
	_ring_offsets.clear()
	for _i in Params.RING_PERCENT.size():
		_ring_offsets.append([])
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var far := maxi(absi(dx), absi(dy))
			var near := mini(absi(dx), absi(dy))
			var ring := -1
			if far == 0:
				ring = 0
			elif far == 1:
				ring = 1 if near == 0 else 2
			elif far == 2:
				ring = 3 if near <= 1 else 4
			elif far == 3 and near <= 1:
				ring = 4
			if ring >= 0:
				_ring_offsets[ring].append(Vector2i(dx, dy))


func _build_coverage(ctx: SimContext) -> void:
	var city := ctx.city
	city.police.fill(0)
	city.fire_cover.fill(0)
	var police_funding := ctx.stats.funding_of(&"police")
	var fire_funding := ctx.stats.funding_of(&"fire")
	@warning_ignore("integer_division")
	var police_strength := police_funding * (Params.POLICE_BASE_EFFECT + _police_modifier) / 2
	@warning_ignore("integer_division")
	var fire_strength := fire_funding * Params.FIRE_BASE_EFFECT / 2
	var police_list: Array = _scan.get(Buildings.POLICE_STATION, [])
	for entry in police_list:
		_stamp(city.police, entry, Buildings.POLICE_STATION, police_strength, police_funding)
	var fire_list: Array = _scan.get(Buildings.FIRE_STATION, [])
	for entry in fire_list:
		_stamp(city.fire_cover, entry, Buildings.FIRE_STATION, fire_strength, fire_funding)
	if bool(ctx.stats.ordinances.get(&"volunteer_fire", false)):
		for cy in CELLS:
			for cx in CELLS:
				city.fire_cover.put(cx, cy, mini(255,
					city.fire_cover.at(cx, cy) + Params.VOLUNTEER_FIRE_COVERAGE))


## Stamp one station's coverage rings onto a quarter-resolution map.
func _stamp(map: Grid8, entry: Dictionary, id: int, strength: int, funding: int) -> void:
	if strength <= 0:
		return
	if not bool(entry["powered"]):
		@warning_ignore("integer_division")
		strength /= Params.UNPOWERED_DIVISOR
	var anchor: Vector2i = entry["anchor"]
	var s := Buildings.size(id)
	@warning_ignore("integer_division")
	var centre := Vector2i((anchor.x + s.x / 2) >> 2, (anchor.y + s.y / 2) >> 2)
	@warning_ignore("integer_division")
	var reach := 1 + funding * Params.MAX_RING / 100
	for ring in _ring_offsets.size():
		if ring > reach:
			break
		@warning_ignore("integer_division")
		var amount := strength * Params.RING_PERCENT[ring] / 100
		if amount <= 0:
			continue
		for offset in _ring_offsets[ring]:
			var p: Vector2i = centre + offset
			if not map.in_bounds(p.x, p.y):
				continue
			map.put(p.x, p.y, mini(255, map.at(p.x, p.y) + amount))


# ── Prisons ──────────────────────────────────────────────────────────────

func _update_prisons(ctx: SimContext) -> void:
	var city := ctx.city
	var found: Array = _scan.get(Buildings.PRISON, [])
	var live := {}
	for entry in found:
		live[tile_key(entry["anchor"])] = entry
	for k in _prisons.keys():
		if not live.has(k):
			_prisons.erase(k)
	if found.is_empty():
		_police_modifier = 0
		_last_arrests = 0
		return
	var crime_total := 0
	for v in city.crime.data:
		crime_total += v
	@warning_ignore("integer_division")
	_last_arrests = crime_total / Params.CRIME_PER_ARREST
	@warning_ignore("integer_division")
	var share := _last_arrests / found.size()
	var funding := ctx.stats.funding_of(&"police")
	var guards := funding * Params.GUARDS_PER_FUNDING_POINT
	var capacity := maxi(guards, Params.MIN_GUARDS) * Params.INMATES_PER_GUARD
	var utilization_sum := 0
	var any_powered := false
	for k in live:
		var entry: Dictionary = live[k]
		var rec: Dictionary = _prisons.get(k, {"inmates": 0, "escapes": 0})
		var inmates := int(rec["inmates"])
		@warning_ignore("integer_division")
		inmates = mini(Params.MAX_INMATES,
			inmates - inmates / Params.RELEASE_DIVISOR + share)
		@warning_ignore("integer_division")
		var utilization := inmates * 100 / capacity
		var escapes := 0
		if utilization > Params.ESCAPE_UTILIZATION:
			@warning_ignore("integer_division")
			var spread := utilization - Params.ESCAPE_UTILIZATION + (100 - funding) / 10
			escapes = 1 + ctx.rng.below(spread)
			escapes = mini(escapes, inmates)
			inmates -= escapes
			var anchor: Vector2i = entry["anchor"]
			ctx.events.report(&"prison_escape", {"count": escapes, "x": anchor.x, "y": anchor.y}, 2)
			_bump_crime(city, anchor)
		rec["inmates"] = inmates
		rec["guards"] = guards
		rec["capacity"] = capacity
		rec["utilization"] = utilization
		rec["escapes"] = int(rec["escapes"]) + escapes
		rec["powered"] = bool(entry["powered"])
		_prisons[k] = rec
		utilization_sum += utilization
		if bool(entry["powered"]):
			any_powered = true
		_mirror_record(city, entry["anchor"], rec)
	@warning_ignore("integer_division")
	var mean_utilization := utilization_sum / live.size()
	_police_modifier = 1 if any_powered and mean_utilization < Params.STRAINED_UTILIZATION else 0


## Escaped inmates raise crime in the developed blocks around the prison.
func _bump_crime(city: City, anchor: Vector2i) -> void:
	var cx := anchor.x >> 1
	var cy := anchor.y >> 1
	var r := Params.ESCAPE_CRIME_RADIUS
	for by in range(maxi(0, cy - r), mini(BLOCKS, cy + r + 1)):
		for bx in range(maxi(0, cx - r), mini(BLOCKS, cx + r + 1)):
			if absi(bx - cx) + absi(by - cy) > r:
				continue
			if not _block_developed(city, bx, by):
				continue
			city.crime.put(bx, by, mini(255, city.crime.at(bx, by) + Params.ESCAPE_CRIME_BUMP))


static func _block_developed(city: City, bx: int, by: int) -> bool:
	for oy in 2:
		for ox in 2:
			var x := bx * 2 + ox
			var y := by * 2 + oy
			if city.zone_kind_at(x, y) != Zones.NONE:
				return true
			var id := city.building.at(x, y)
			if id == Buildings.NONE or Buildings.is_rubble(id):
				continue
			var cat := Buildings.category(id)
			if cat != Buildings.Category.TREE and cat != Buildings.Category.POWER_LINE:
				return true
	return false


## Keep the city's facility record for the prison in step with ours.
static func _mirror_record(city: City, anchor: Vector2i, rec: Dictionary) -> void:
	var facility := city.facility(anchor)
	if facility.is_empty():
		return
	for field in ["inmates", "guards", "capacity", "utilization", "escapes"]:
		facility[field] = rec[field]


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var prisons := {}
	for k in _prisons:
		prisons[String(k)] = _prisons[k].duplicate()
	return {
		"prisons": prisons,
		"police_modifier": _police_modifier,
		"last_arrests": _last_arrests,
	}


func load(data: Dictionary) -> void:
	_prisons.clear()
	var prisons: Dictionary = data.get("prisons", {})
	for k in prisons:
		var src: Dictionary = prisons[k]
		_prisons[String(k)] = {
			"inmates": int(src.get("inmates", 0)),
			"guards": int(src.get("guards", 0)),
			"capacity": int(src.get("capacity", 0)),
			"utilization": int(src.get("utilization", 0)),
			"escapes": int(src.get("escapes", 0)),
			"powered": bool(src.get("powered", false)),
		}
	_police_modifier = int(data.get("police_modifier", 0))
	_last_arrests = int(data.get("last_arrests", 0))
