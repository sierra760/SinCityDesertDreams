# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Transport maintenance and wear. See docs/simulation/maintenance.md.
##
## Underfunded transport categories accrue wear each month; every time a
## category's wear passes its threshold one random piece of that network is
## lost. Full funding stops the decay but repairs nothing. The system also
## answers the budget's questions about network size and upkeep.
class_name WearSystem
extends SimSystem

const WIDTH := City.WIDTH
const HEIGHT := City.HEIGHT
const TILES := City.WIDTH * City.HEIGHT
const COUNT := TransportParams.CATEGORY_COUNT

const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]

var _city: City
var _funding_source: CityStats

## Category and losability by building id, filled once.
var _category := PackedByteArray()
var _losable := PackedByteArray()

## Accrued wear points and tiles lost so far, per category.
var _wear := PackedInt32Array()
var _losses := PackedInt32Array()

## Cached network scan: tiles per category and the tiles wear may remove.
var _counts := PackedInt32Array()
var _candidates: Array[Array] = []
var _scan_valid := false
## Content hashes of the building and underground layers at the last scan.
## Disasters, ports, rewards and growth edit the map without a networks
## change; a differing hash makes the cached scan stale.
var _scan_building_hash := 0
var _scan_underground_hash := 0


func _init() -> void:
	key = &"wear"
	_category.resize(Buildings.COUNT)
	_losable.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		_category[id] = TransportParams.wear_category(id)
		_losable[id] = 1 if TransportParams.is_losable(id) else 0
	_wear.resize(COUNT)
	_losses.resize(COUNT)
	_counts.resize(COUNT)
	for _i in COUNT:
		_candidates.append([])


# ── Schedule ─────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_city = ctx.city
	_funding_source = ctx.stats
	_scan_valid = false
	_scan()


func networks_changed(_ctx: SimContext, _rect: Rect2i) -> void:
	_scan_valid = false


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_city = ctx.city
	_funding_source = ctx.stats
	_scan()
	for cat in COUNT:
		var name: StringName = TransportParams.CATEGORY_KEYS[cat]
		if _counts[cat] == 0:
			_wear[cat] = 0
			continue
		var shortfall := 100 - clampi(ctx.stats.funding_of(name), 0, 100)
		if shortfall > 0:
			var jitter := ctx.rng.range_int(100 - TransportParams.WEAR_JITTER_PERCENT,
				100 + TransportParams.WEAR_JITTER_PERCENT)
			@warning_ignore("integer_division")
			_wear[cat] += _counts[cat] * shortfall * jitter / 100
		var threshold: int = TransportParams.WEAR_THRESHOLD[name]
		var candidates: Array = _candidates[cat]
		while _wear[cat] >= threshold and not candidates.is_empty():
			var pick := ctx.rng.below(candidates.size())
			var tile: int = candidates[pick]
			candidates[pick] = candidates[candidates.size() - 1]
			candidates.pop_back()
			# An earlier loss this month (a whole bridge or highway block) may
			# already have removed this tile; it costs no wear and is not news.
			if not _still_candidate(cat, tile):
				continue
			_wear[cat] -= threshold
			_lose(ctx, cat, tile)


# ── Getters ──────────────────────────────────────────────────────────────

## Tiles per category, keyed by the six category names.
func network_counts() -> Dictionary:
	_scan()
	var out := {}
	for cat in COUNT:
		out[TransportParams.CATEGORY_KEYS[cat]] = _counts[cat]
	return out


## Yearly upkeep of one category in dollars at the given funding level.
func maintenance_cost(category: StringName, funding_percent: int = 100) -> int:
	var cat := TransportParams.category_index(category)
	if cat < 0:
		return 0
	_scan()
	var cents: int = TransportParams.UPKEEP_CENTS[category]
	@warning_ignore("integer_division")
	return _counts[cat] * cents * clampi(funding_percent, 0, 100) / 100 / 100


## Upkeep of all categories together, at the current sliders or at full funding.
func maintenance_total(at_current_funding: bool = true) -> int:
	var total := 0
	for cat in COUNT:
		var name: StringName = TransportParams.CATEGORY_KEYS[cat]
		var funding := 100
		if at_current_funding and _city != null:
			funding = _current_funding(name)
		total += maintenance_cost(name, funding)
	return total


## How close a category is to its next loss, 0–100.
func wear_percent(category: StringName) -> int:
	var cat := TransportParams.category_index(category)
	if cat < 0:
		return 0
	var threshold: int = TransportParams.WEAR_THRESHOLD[category]
	@warning_ignore("integer_division")
	return clampi(_wear[cat] * 100 / threshold, 0, 100)


## Tiles lost so far per category.
func losses() -> Dictionary:
	var out := {}
	for cat in COUNT:
		out[TransportParams.CATEGORY_KEYS[cat]] = _losses[cat]
	return out


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var wear := {}
	var lost := {}
	for cat in COUNT:
		wear[String(TransportParams.CATEGORY_KEYS[cat])] = _wear[cat]
		lost[String(TransportParams.CATEGORY_KEYS[cat])] = _losses[cat]
	return {"wear": wear, "losses": lost}


func load(data: Dictionary) -> void:
	var wear: Dictionary = data.get("wear", {})
	var lost: Dictionary = data.get("losses", {})
	for cat in COUNT:
		var name := String(TransportParams.CATEGORY_KEYS[cat])
		_wear[cat] = int(wear.get(name, 0))
		_losses[cat] = int(lost.get(name, 0))
	_scan_valid = false


# ── Network scan ─────────────────────────────────────────────────────────

func _current_funding(name: StringName) -> int:
	if _funding_source == null:
		return 100
	return _funding_source.funding_of(name)


func _scan() -> void:
	if _city == null:
		return
	var buildings := _city.building.data
	var underground := _city.underground.data
	var building_hash := hash(buildings)
	var underground_hash := hash(underground)
	if _scan_valid and building_hash == _scan_building_hash \
			and underground_hash == _scan_underground_hash:
		return
	_scan_building_hash = building_hash
	_scan_underground_hash = underground_hash
	_counts.fill(0)
	for cat in COUNT:
		_candidates[cat].clear()
	var road_list: Array = _candidates[TransportParams.ROADS]
	var highway_list: Array = _candidates[TransportParams.HIGHWAYS]
	var bridge_list: Array = _candidates[TransportParams.BRIDGES]
	var rail_list: Array = _candidates[TransportParams.RAIL]
	var subway_list: Array = _candidates[TransportParams.SUBWAY]
	var tunnel_list: Array = _candidates[TransportParams.TUNNELS]
	for t in TILES:
		var id := buildings[t]
		var cat := _category[id]
		if cat != TransportParams.NO_CATEGORY:
			_counts[cat] += 1
			if _losable[id] != 0:
				match cat:
					TransportParams.ROADS: road_list.append(t)
					TransportParams.HIGHWAYS: highway_list.append(t)
					TransportParams.BRIDGES: bridge_list.append(t)
					TransportParams.RAIL: rail_list.append(t)
					TransportParams.TUNNELS: tunnel_list.append(t)
		var code := underground[t]
		if UtilityParams.is_subway(code):
			_counts[TransportParams.SUBWAY] += 1
			if TransportParams.is_losable_subway(code):
				subway_list.append(t)
	_scan_valid = true


## Whether a scanned candidate tile is still a losable piece of its category.
func _still_candidate(cat: int, tile: int) -> bool:
	if cat == TransportParams.SUBWAY:
		return TransportParams.is_losable_subway(_city.underground.data[tile])
	var id := _city.building.data[tile]
	return _category[id] == cat and _losable[id] != 0


# ── Losses ───────────────────────────────────────────────────────────────

func _lose(ctx: SimContext, cat: int, tile: int) -> void:
	@warning_ignore("integer_division")
	var y := tile / WIDTH
	var x := tile - y * WIDTH
	var name := String(TransportParams.CATEGORY_KEYS[cat])
	match cat:
		TransportParams.ROADS, TransportParams.TUNNELS:
			_to_rubble(ctx, x, y)
			_losses[cat] += 1
			ctx.events.report(&"road_decay", {"x": x, "y": y, "category": name}, 1)
		TransportParams.RAIL:
			_to_rubble(ctx, x, y)
			_losses[cat] += 1
			ctx.events.report(&"rail_decay", {"x": x, "y": y, "category": name}, 1)
		TransportParams.HIGHWAYS:
			var lost := _lose_highway_block(ctx, x & ~1, y & ~1)
			_losses[cat] += lost
			if lost > 0:
				ctx.events.report(&"road_decay", {"x": x, "y": y, "category": name, "tiles": lost}, 2)
		TransportParams.BRIDGES:
			var lost := _collapse_bridge(ctx, x, y)
			_losses[cat] += lost
			if lost > 0:
				ctx.events.report(&"bridge_collapse", {"x": x, "y": y, "tiles": lost}, 3)
		TransportParams.SUBWAY:
			_city.underground.put(x, y, UtilityParams.UNDERGROUND_NONE)
			ctx.events.mark_tile(x, y)
			_losses[cat] += 1
			ctx.events.report(&"rail_decay", {"x": x, "y": y, "category": name}, 1)
	_scan_valid = false


func _to_rubble(ctx: SimContext, x: int, y: int) -> void:
	if _city.is_water(x, y):
		_city.building.put(x, y, Buildings.NONE)
	else:
		_city.building.put(x, y, Buildings.RUBBLE_1 + ctx.rng.below(Buildings.RUBBLE_4 - Buildings.RUBBLE_1 + 1))
	_city.flags.set_bits(x, y, TileFlags.CONDUCTS_POWER | TileFlags.POWERED, false)
	ctx.events.mark_tile(x, y)


## Remove every highway tile in the 2×2 block anchored at (x, y). Returns the
## number of tiles lost.
func _lose_highway_block(ctx: SimContext, x: int, y: int) -> int:
	var lost := 0
	for dy in 2:
		for dx in 2:
			var id := _city.building.at(x + dx, y + dy)
			if _category[id] == TransportParams.HIGHWAYS and _losable[id] != 0:
				_to_rubble(ctx, x + dx, y + dy)
				lost += 1
	return lost


## Remove every bridge tile connected to (x, y). Returns the number removed.
func _collapse_bridge(ctx: SimContext, x: int, y: int) -> int:
	var stack: Array[int] = [y * WIDTH + x]
	var seen := {}
	var lost := 0
	while not stack.is_empty():
		var t: int = stack.pop_back()
		if seen.has(t):
			continue
		seen[t] = true
		@warning_ignore("integer_division")
		var ty := t / WIDTH
		var tx := t - ty * WIDTH
		if _category[_city.building.at(tx, ty)] != TransportParams.BRIDGES:
			continue
		_city.building.put(tx, ty, Buildings.NONE)
		_city.flags.set_bits(tx, ty, TileFlags.CONDUCTS_POWER | TileFlags.POWERED, false)
		ctx.events.mark_tile(tx, ty)
		lost += 1
		for d in 4:
			var nx := tx + DX[d]
			var ny := ty + DY[d]
			if _city.in_bounds(nx, ny):
				stack.append(ny * WIDTH + nx)
	return lost
