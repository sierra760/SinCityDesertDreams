# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rewards, arcologies and the military base.
##
## Population milestones unlock gift buildings the player places for free and,
## once, a proposal for a military base. Arcologies become buildable by year,
## fill with residents once a year while served, and a large enough fleet of
## Desert Orbit arcologies eventually leaves the city. Rules are in
## docs/simulation/rewards.md; constants in RewardParams.
extends SimSystem

const KIND_NONE := &"none"
const KIND_AIR := &"air"
const KIND_ARMY := &"army"
const KIND_NAVAL := &"naval"
const KIND_MISSILE := &"missile"

var _ctx: SimContext
var _milestones_passed := 0
var _military: Dictionary = _empty_offer()
## Gifts seen standing on the map; used to notice their demolition.
var _seen_standing: Dictionary = {}
## Reports and dirty rectangles queued by calls made between days.
var _pending_news: Array[Dictionary] = []
var _pending_dirty: Array[Rect2i] = []


func _init() -> void:
	key = &"rewards"


static func _empty_offer() -> Dictionary:
	return {"kind": KIND_NONE, "answered": false, "accepted": false, "site": Rect2i(), "sites": []}


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_ctx = ctx
	_reconcile_rewards(ctx)
	_reconcile_arcologies(ctx)


func daily(ctx: SimContext) -> void:
	for story in _pending_news:
		ctx.events.report(story.kind, story.args)
	_pending_news.clear()
	for rect in _pending_dirty:
		ctx.events.mark_dirty(rect)
	_pending_dirty.clear()


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_reconcile_rewards(ctx)
	_check_milestone(ctx)
	_reconcile_arcologies(ctx)


func yearly(ctx: SimContext) -> void:
	_reconcile_arcologies(ctx)
	_grow_arcologies(ctx)
	_check_exodus(ctx)
	_reconcile_arcologies(ctx)


func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_reconcile_rewards(ctx)
	_reconcile_arcologies(ctx)


# ── Gifts ────────────────────────────────────────────────────────────────

## Gift keys that have been offered and are not standing in the city.
func available() -> Array[StringName]:
	var out: Array[StringName] = []
	if _ctx == null:
		return out
	for milestone in RewardParams.MILESTONES:
		var k: StringName = milestone.key
		if k == RewardParams.MILITARY_KEY:
			continue
		if _ctx.stats.rewards_offered.get(k, false) and not _ctx.stats.rewards_built.get(k, false):
			out.append(k)
	return out


## Deliberate jackpot grants permits, preserving standing gifts and the
## one-time military decision. The base still uses the ordinary site proposal.
func unlock_for_cheat() -> void:
	if _ctx == null: return
	_reconcile_rewards(_ctx)
	for milestone in RewardParams.MILESTONES:
		var k: StringName = milestone.key
		if k == RewardParams.MILITARY_KEY:
			if _ctx.stats.rewards_offered.get(k, false): continue
			_ctx.stats.rewards_offered[k] = true
			_propose_military(_ctx)
			if military_offer().pending:
				_ctx.events.notify(&"reward_offered", {"key": k, "kind": _military.kind,
					"site": _rect_to_array(_military.site), "sites": _rects_to_array(_military.sites)})
		else:
			_ctx.stats.rewards_offered[k] = true


## Record that the player placed a gift.
func mark_built(gift_key: StringName) -> void:
	if _ctx == null:
		return
	_ctx.stats.rewards_built[gift_key] = true


func _check_milestone(ctx: SimContext) -> void:
	# Map reconciliation or a restored offer may already own a milestone.
	# Skip only known rewards, so missing earlier gifts still earn normally.
	while _milestones_passed < RewardParams.MILESTONES.size():
		var known: StringName = RewardParams.MILESTONES[_milestones_passed].key
		if not ctx.stats.rewards_offered.get(known, false):
			break
		_milestones_passed += 1
	if _milestones_passed >= RewardParams.MILESTONES.size():
		return
	var next: Dictionary = RewardParams.MILESTONES[_milestones_passed]
	var needed := int(next.population)
	if ctx.stats.population < needed:
		return
	_milestones_passed += 1
	var k: StringName = next.key
	ctx.stats.rewards_offered[k] = true
	ctx.events.report(&"city_milestone", {"key": k, "population": needed}, 2)
	if k == RewardParams.MILITARY_KEY:
		_propose_military(ctx)
		ctx.events.notify(&"reward_offered", {
			"key": k,
			"kind": _military.kind,
			"site": _rect_to_array(_military.site),
			"sites": _rects_to_array(_military.sites),
		})
	else:
		ctx.events.notify(&"reward_offered", {"key": k})


## Standing imported rewards were already earned. Keep civic gifts replaceable
## after demolition, while an existing military base consumes its one proposal.
func _reconcile_rewards(ctx: SimContext) -> void:
	for milestone in RewardParams.MILESTONES:
		var k: StringName = milestone.key
		if k == RewardParams.MILITARY_KEY:
			if ctx.stats.rewards_built.get(k, false) or _has_military_base(ctx.city):
				ctx.stats.rewards_offered[k] = true
				ctx.stats.rewards_built[k] = true
				_military.answered = true
			continue
		var id := Buildings.id_of(k)
		var standing := ctx.city.building.count(id) > 0
		if standing:
			ctx.stats.rewards_offered[k] = true
			ctx.stats.rewards_built[k] = true
			_seen_standing[k] = true
		elif _seen_standing.get(k, false):
			ctx.stats.rewards_built.erase(k)
			_seen_standing.erase(k)


## Shared airport/seaport pieces alone do not identify a military base.
## Each military zone code and building id is looked up with one native scan
## of its layer instead of a per-tile script loop.
static func _has_military_base(city: City) -> bool:
	var zones := city.zone.data
	for corners in 16:
		if zones.has((corners << 4) | Zones.MILITARY):
			return true
	var buildings := city.building.data
	for id in _military_ids():
		if buildings.has(id):
			return true
	return false


static var _military_id_table := PackedInt32Array()
static var _military_id_table_ready := false


## Building ids of the military category, found once.
static func _military_ids() -> PackedInt32Array:
	if not _military_id_table_ready:
		for id in Buildings.COUNT:
			if Buildings.category(id) == Buildings.Category.MILITARY:
				_military_id_table.append(id)
		_military_id_table_ready = true
	return _military_id_table


# ── Military base ────────────────────────────────────────────────────────

## The current proposal. `pending` is true while the city has not answered.
func military_offer() -> Dictionary:
	var sites: Array[Rect2i] = []
	for r in _military.sites:
		sites.append(r)
	return {
		"kind": _military.kind,
		"pending": not _military.answered and _military.kind != KIND_NONE,
		"answered": _military.answered,
		"accepted": _military.accepted,
		"site": _military.site,
		"sites": sites,
	}


## The kind of base the city accepted, or an empty name.
func military_kind() -> StringName:
	if _military.accepted:
		return _military.kind
	return &""


## Zone the base. An empty rect uses the proposed site(s). Returns false when
## there is no pending offer or nothing could be zoned.
func accept_military(rect: Rect2i = Rect2i()) -> bool:
	if _ctx == null or _military.answered or _military.kind == KIND_NONE:
		return false
	var rects: Array[Rect2i] = []
	if rect.size == Vector2i.ZERO:
		if not _military.sites.is_empty():
			for r in _military.sites:
				rects.append(r)
		else:
			rects.append(_military.site)
	else:
		rects.append(rect)
	var city := _ctx.city
	var zoned := 0
	for r in rects:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if _usable(city, x, y):
					city.zone.put(x, y, Zones.make(Zones.MILITARY))
					zoned += 1
		_pending_dirty.append(r)
	_military.answered = true
	_military.accepted = zoned > 0
	_pending_news.append({"kind": &"military_base", "args": {"kind": _military.kind, "accepted": _military.accepted}})
	return _military.accepted


## Refuse the base for good.
func decline_military() -> void:
	if _military.answered or _military.kind == KIND_NONE:
		return
	_military.answered = true
	_military.accepted = false
	_pending_news.append({"kind": &"military_base", "args": {"kind": _military.kind, "accepted": false}})


func _propose_military(ctx: SimContext) -> void:
	var city := ctx.city
	_military = _empty_offer()
	if _has_open_water(city) and ctx.rng.chance(1, 2):
		var naval := _find_square_site(ctx, true)
		if not naval.is_empty():
			_military.kind = KIND_NAVAL
			_military.site = naval.rect
	if _military.kind == KIND_NONE:
		var land := _find_square_site(ctx, false)
		if not land.is_empty():
			_military.kind = land.kind
			_military.site = land.rect
	if _military.kind == KIND_NONE:
		var silos := _find_missile_sites(ctx)
		if not silos.is_empty():
			_military.kind = KIND_MISSILE
			_military.sites = silos
	if _military.kind == KIND_NONE:
		_military.answered = true


## Ground that may become part of a base: unzoned, dry, bare, nothing beneath.
static func _usable(city: City, x: int, y: int) -> bool:
	if not city.in_bounds(x, y):
		return false
	if city.zone_kind_at(x, y) != Zones.NONE or city.is_water(x, y):
		return false
	if city.building_at(x, y) > Buildings.TREES_7:
		return false
	if city.underground.at(x, y) != 0:
		return false
	return not city.flags.has_bits(x, y, TileFlags.LANDMARK)


static func _touches_open_water(city: City, x: int, y: int) -> bool:
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		if city.in_bounds(x + d.x, y + d.y) and city.is_open_water(x + d.x, y + d.y):
			return true
	return false


static func _has_open_water(city: City) -> bool:
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.is_open_water(x, y):
				return true
	return false


func _find_square_site(ctx: SimContext, naval: bool) -> Dictionary:
	var city := ctx.city
	var size := RewardParams.MILITARY_SITE_SIZE
	for _attempt in RewardParams.MILITARY_SITE_ATTEMPTS:
		var ox := ctx.rng.below(City.WIDTH - size)
		var oy := ctx.rng.below(City.HEIGHT - size)
		var level := city.ground_height(ox, oy)
		var usable := 0
		var same_height := 0
		var shore := 0
		for y in range(oy, oy + size):
			for x in range(ox, ox + size):
				if not _usable(city, x, y):
					continue
				usable += 1
				if city.ground_height(x, y) == level:
					same_height += 1
				if naval and _touches_open_water(city, x, y):
					shore += 1
		if usable < RewardParams.MILITARY_SITE_MIN_USABLE:
			continue
		var rect := Rect2i(ox, oy, size, size)
		if naval:
			if shore >= RewardParams.MILITARY_NAVAL_MIN_SHORE:
				return {"rect": rect, "kind": KIND_NAVAL}
			continue
		return {"rect": rect, "kind": KIND_ARMY if same_height == usable else KIND_AIR}
	return {}


func _find_missile_sites(ctx: SimContext) -> Array[Rect2i]:
	var city := ctx.city
	var size := RewardParams.MILITARY_MISSILE_SITE_SIZE
	var sites: Array[Rect2i] = []
	for _attempt in RewardParams.MILITARY_MISSILE_ATTEMPTS:
		var ox := ctx.rng.below(City.WIDTH - size)
		var oy := ctx.rng.below(City.HEIGHT - size)
		var rect := Rect2i(ox, oy, size, size)
		var level := city.ground_height(ox, oy)
		var ok := true
		for y in range(oy, oy + size):
			for x in range(ox, ox + size):
				if not _usable(city, x, y) or city.ground_height(x, y) != level:
					ok = false
		if not ok:
			continue
		for other in sites:
			if other.intersects(rect):
				ok = false
		if ok:
			sites.append(rect)
		if sites.size() >= RewardParams.MILITARY_MISSILE_SITES:
			break
	return sites


# ── Arcologies ───────────────────────────────────────────────────────────

## Whether a design may be built this year.
func arcology_available(arcology_key: StringName) -> bool:
	if _ctx == null or not RewardParams.ARCOLOGIES.has(arcology_key):
		return false
	var design: Dictionary = RewardParams.ARCOLOGIES[arcology_key]
	var year := int(design.year)
	var technology: StringName = design.get("technology", arcology_key)
	if _ctx.stats.inventions.has(technology):
		year = int(_ctx.stats.inventions[technology])
	return _ctx.year() >= year


func available_arcologies() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in RewardParams.ARCOLOGIES:
		if arcology_available(k):
			out.append(k)
	return out


## One entry per standing arcology.
@warning_ignore("integer_division")
func arcology_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ctx == null:
		return out
	var city := _ctx.city
	for anchor in _arcology_anchors(city):
		var rec := city.facility(anchor)
		var residents := int(rec.get("residents", 0))
		out.append({
			"anchor": anchor,
			"key": rec.get("key", Buildings.key(city.building_at(anchor.x, anchor.y))),
			"residents": residents,
			"capacity": int(rec.get("capacity", 0)),
			"built_year": int(rec.get("built_year", city.current_year())),
			"condition": int(rec.get("condition", 0)),
			"pollution": residents / 1000 * RewardParams.POLLUTION_PER_THOUSAND,
			"crime": residents / 1000 * RewardParams.CRIME_PER_THOUSAND,
		})
	return out


## Anchors (north-west corners) of every arcology footprint on the map, in
## map order. Native searches find the few arcology tiles without walking
## every tile in script. The CORNER_NW tile picks each lot once and
## `City.anchor_of` places it, so a city saved at another rotation, whose
## CORNER_NW flag sits on another corner, still names each arcology by its
## top-left tile.
@warning_ignore("integer_division")
static func _arcology_anchors(city: City) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var data := city.building.data
	var zones := city.zone.data
	var found := PackedInt32Array()
	for key in RewardParams.ARCOLOGIES:
		var id := Buildings.id_of(key)
		var i := data.find(id)
		while i >= 0:
			if zones[i] & Zones.CORNER_NW:
				var a := City.footprint_anchor(data, zones, i % City.WIDTH, i / City.WIDTH)
				found.append(a.y * City.WIDTH + a.x)
			i = data.find(id, i + 1)
	found.sort()
	for i in found:
		out.append(Vector2i(i % City.WIDTH, i / City.WIDTH))
	return out


static func _capacity_of(arcology_key: StringName) -> int:
	var design: Dictionary = RewardParams.ARCOLOGIES.get(arcology_key, {})
	return int(design.get("capacity", 0))


## Give every standing arcology a record, drop records of vanished ones and
## refresh the arcology population total.
func _reconcile_arcologies(ctx: SimContext) -> void:
	var city := ctx.city
	var live: Dictionary = {}
	var total := 0
	for anchor in _arcology_anchors(city):
		var k := Buildings.key(city.building_at(anchor.x, anchor.y))
		var rec := city.facility(anchor)
		if rec.is_empty() or rec.get("key", &"") != k:
			rec = {"key": k, "built_day": city.day}
			city.add_facility(anchor, rec)
		if not rec.has("residents"):
			rec["residents"] = 0
			rec["capacity"] = _capacity_of(k)
			rec["built_year"] = city.current_year()
			rec["condition"] = 0
		live[anchor] = true
		total += int(rec.residents)
	for anchor in city.facilities.keys():
		var rec: Dictionary = city.facilities[anchor]
		if RewardParams.ARCOLOGIES.has(rec.get("key", &"")) and not live.has(anchor):
			city.facilities.erase(anchor)
	ctx.stats.arcology_population = total


@warning_ignore("integer_division")
func _grow_arcologies(ctx: SimContext) -> void:
	var city := ctx.city
	var stats := ctx.stats
	var anchors := _arcology_anchors(city)
	var count := maxi(1, anchors.size())
	var tax_factor := (RewardParams.TAX_FACTOR_BASE - stats.tax_residential - stats.tax_commercial - stats.tax_industrial) / RewardParams.TAX_FACTOR_DIVISOR
	for anchor in anchors:
		var rec := city.facility(anchor)
		var div := RewardParams.DESIRABILITY_DIVISOR
		var condition := RewardParams.DESIRABILITY_BASE - city.pollution_at(anchor.x, anchor.y) / div - city.crime_at(anchor.x, anchor.y) / div + city.land_value_at(anchor.x, anchor.y) / div
		condition = clampi(condition, 0, RewardParams.DESIRABILITY_BASE)
		rec["condition"] = condition
		if not (city.is_powered(anchor.x, anchor.y) and city.is_watered(anchor.x, anchor.y)):
			continue
		var capacity := int(rec.capacity)
		var residents := int(rec.residents)
		var intake := mini(capacity / RewardParams.INTAKE_CAPACITY_SHARE, stats.population / (count * RewardParams.INTAKE_CITY_SHARE))
		intake = mini(intake, (tax_factor + condition) * RewardParams.INTAKE_PER_POINT - RewardParams.INTAKE_OFFSET)
		intake = maxi(intake, 0)
		var next := residents + residents / RewardParams.RETENTION_GROWTH_SHARE + intake
		if next > residents:
			next += ctx.rng.below(RewardParams.INTAKE_JITTER)
		rec["residents"] = mini(capacity, next)


func _check_exodus(ctx: SimContext) -> void:
	if ctx.year() < RewardParams.LAUNCH_YEAR:
		return
	var city := ctx.city
	var fleet: Array[Vector2i] = []
	for anchor in _arcology_anchors(city):
		if Buildings.key(city.building_at(anchor.x, anchor.y)) == RewardParams.LAUNCH_KEY:
			fleet.append(anchor)
	if fleet.size() < RewardParams.LAUNCH_COUNT:
		return
	var residents := 0
	var refund := 0
	for anchor in fleet:
		var rec := city.facility(anchor)
		var aboard := int(rec.get("residents", 0))
		residents += aboard
		if aboard > 0:
			refund += RewardParams.LAUNCH_REFUND
		var rect := city.clear_footprint(anchor.x, anchor.y)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				city.building.put(x, y, Buildings.RUBBLE_1 + ctx.rng.below(4))
		ctx.events.mark_dirty(rect)
	city.funds += refund
	# "residents" is the head count the notice and story print; "resorts" is
	# the number of departing buildings.
	var args := {"resorts": fleet.size(), "residents": residents, "refund": refund}
	ctx.events.notify(&"exodus", args)
	ctx.events.report(&"resort_launch", args, 3)


# ── Persistence ──────────────────────────────────────────────────────────

static func _rect_to_array(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


static func _rects_to_array(rects: Array) -> Array:
	var out: Array = []
	for r in rects:
		out.append(_rect_to_array(r))
	return out


static func _rect_from_array(a: Array) -> Rect2i:
	if a.size() != 4:
		return Rect2i()
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


func save() -> Dictionary:
	var arcologies: Dictionary = {}
	if _ctx != null:
		var city := _ctx.city
		for anchor in _arcology_anchors(city):
			var rec := city.facility(anchor)
			arcologies[tile_key(anchor)] = {
				"residents": int(rec.get("residents", 0)),
				"capacity": int(rec.get("capacity", 0)),
				"built_year": int(rec.get("built_year", city.current_year())),
				"condition": int(rec.get("condition", 0)),
			}
	var seen: Array = []
	for k in _seen_standing:
		seen.append(String(k))
	return {
		"milestones_passed": _milestones_passed,
		"military": {
			"kind": String(_military.kind),
			"answered": _military.answered,
			"accepted": _military.accepted,
			"site": _rect_to_array(_military.site),
			"sites": _rects_to_array(_military.sites),
		},
		"seen_standing": seen,
		"arcologies": arcologies,
	}


func load(data: Dictionary) -> void:
	_milestones_passed = int(data.get("milestones_passed", 0))
	var m: Dictionary = data.get("military", {})
	var sites: Array[Rect2i] = []
	for entry in m.get("sites", []):
		sites.append(_rect_from_array(entry))
	_military = {
		"kind": StringName(String(m.get("kind", String(KIND_NONE)))),
		"answered": bool(m.get("answered", false)),
		"accepted": bool(m.get("accepted", false)),
		"site": _rect_from_array(m.get("site", [])),
		"sites": sites,
	}
	_seen_standing.clear()
	for k in data.get("seen_standing", []):
		_seen_standing[StringName(String(k))] = true
	_pending_news.clear()
	_pending_dirty.clear()
	if _ctx == null:
		return
	var city := _ctx.city
	var arcologies: Dictionary = data.get("arcologies", {})
	for tk in arcologies:
		var anchor := parse_tile_key(String(tk))
		var id := city.building_at(anchor.x, anchor.y)
		if not Buildings.is_arcology(id):
			continue
		var saved: Dictionary = arcologies[tk]
		var rec := city.facility(anchor)
		if rec.is_empty():
			rec = {"key": Buildings.key(id), "built_day": city.day}
			city.add_facility(anchor, rec)
		rec["residents"] = int(saved.get("residents", 0))
		rec["capacity"] = int(saved.get("capacity", _capacity_of(Buildings.key(id))))
		rec["built_year"] = int(saved.get("built_year", city.current_year()))
		rec["condition"] = int(saved.get("condition", 0))
	_reconcile_rewards(_ctx)
	_reconcile_arcologies(_ctx)
