# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Terrain tools: raise, lower, level, water, trees and the sea level.
##
## Every operation edits the city's `TerrainSurface`, re-normalizes the
## neighbourhood it disturbed, re-projects the affected tiles and returns
## a result Dictionary:
##
##   {ok: bool, cost: int, rect: Rect2i, reason: String}
##
## `rect` is the tile rect that changed (empty when nothing did) and `cost`
## is the price the caller should debit; the editor never touches funds.
## Operations refuse tiles that hold anything other than trees; trees on the
## target tile are cleared as part of the work. Tiles reshaped by the ripple
## of a repair must be free of buildings too (trees may stay).
class_name TerrainEditor
extends RefCounted

const RAISE_COST := 25
const LOWER_COST := 25
const LEVEL_COST := 25
const WATER_COST := 100
const TREE_COST := 3
const SEA_LEVEL_COST := 25

const MIN_SEA_LEVEL := 1
const MAX_SEA_LEVEL := 30
## A water click may fill the enclosed hollow around it up to this many
## tiles; a larger or open area gets a single pond tile instead.
const BASIN_LIMIT := 64

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var city: City


func _init(target: City = null) -> void:
	if target != null:
		attach(target)


## Bind a city, building its lattice from the layers when it has none.
func attach(target: City) -> void:
	city = target
	if city != null and city.terrain_surface == null:
		var s := TerrainSurface.from_city(city)
		var repair := s.normalize()
		var r: Rect2i = repair["rect"]
		if r.size.x > 0:
			s.project(city, r)


func surface() -> TerrainSurface:
	return city.terrain_surface


## Why the tile refuses editing, or an empty string when it may be edited.
func can_edit(x: int, y: int) -> String:
	return String(_check_target(x, y).get("reason", ""))


# ── Tool dispatch ────────────────────────────────────────────────────────

## Run a terrain tool from `Tools.Kind` over a drag. Point tools use `from`,
## Level and Forest cover the rectangle from `from` to `to`, the sea tools
## ignore both. Water on a water tile drains it. Returns
## {ok, cost, rect, reason, tiles}: `cost` sums the price of every tile that
## changed and `tiles` lists them.
func apply_tool(tool: int, from: Vector2i, to: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var end := to if to.x >= 0 else from
	match tool:
		Tools.Kind.RAISE_LAND:
			return _with_tiles(raise(from.x, from.y), [from])
		Tools.Kind.LOWER_LAND:
			return _with_tiles(lower(from.x, from.y), [from])
		Tools.Kind.LEVEL_LAND:
			return level_area(from, end)
		Tools.Kind.PLACE_WATER:
			var gate := _check_target(from.x, from.y)
			if not gate.is_empty():
				return _with_tiles(gate, [])
			if surface().has_water(from.x, from.y):
				return _with_tiles(remove_water(from.x, from.y), [from])
			return _with_tiles(place_water(from.x, from.y, true), [from])
		Tools.Kind.FOREST:
			return plant_area(from, end)
		Tools.Kind.PLANT_TREE:
			return _with_tiles(add_tree(from.x, from.y), [from])
		Tools.Kind.RAISE_SEA:
			return _with_tiles(raise_sea_level(), [])
		Tools.Kind.LOWER_SEA:
			return _with_tiles(lower_sea_level(), [])
	return _with_tiles(_refuse("Not a terrain tool."), [])


## The tiles a tool would touch and whether its first tile may be edited,
## without changing anything: {ok, cost, tiles, reason}. `cost` is 0; the
## caller decides what to charge.
func preview_tool(tool: int, from: Vector2i, to: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var end := to if to.x >= 0 else from
	var tiles: Array[Vector2i] = []
	var reason := ""
	match tool:
		Tools.Kind.RAISE_SEA, Tools.Kind.LOWER_SEA:
			if city == null or city.sea_level < 0:
				reason = "This map has no sea level."
		Tools.Kind.LEVEL_LAND, Tools.Kind.FOREST:
			tiles = drag_area(from, end)
			reason = can_edit(from.x, from.y)
		Tools.Kind.PLANT_TREE:
			tiles = [from]
			reason = can_edit(from.x, from.y)
			if reason.is_empty() and city.building.at(from.x, from.y) == Buildings.TREES_7:
				reason = "The trees here are as dense as they grow."
		Tools.Kind.RAISE_LAND, Tools.Kind.LOWER_LAND, Tools.Kind.PLACE_WATER:
			tiles = [from]
			reason = can_edit(from.x, from.y)
		_:
			reason = "Not a terrain tool."
	return {"ok": reason.is_empty(), "cost": 0, "tiles": tiles, "reason": reason}


## Level every tile of the dragged rectangle to the height of its first
## tile. Tiles that are already flat at that height are skipped.
func level_area(from: Vector2i, to: Vector2i) -> Dictionary:
	var gate := _check_target(from.x, from.y)
	if not gate.is_empty():
		return _with_tiles(gate, [])
	var target := surface().tile_base(from.x, from.y)
	return _run_line(drag_area(from, to), func(p: Vector2i) -> Dictionary: return level(p.x, p.y, target))


## Plant trees over the dragged rectangle, each tile as dense as the trees
## around it.
func plant_area(from: Vector2i, to: Vector2i) -> Dictionary:
	return _run_line(drag_area(from, to), func(p: Vector2i) -> Dictionary: return plant_trees(p.x, p.y, natural_density(p.x, p.y)))


## Tree density (1..7) that fits a tile: one plus the tree tiles around it.
func natural_density(x: int, y: int) -> int:
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and city.in_bounds(x + dx, y + dy) \
					and Buildings.is_tree(city.building.at(x + dx, y + dy)):
				count += 1
	return clampi(1 + count, 1, 7)


## Every tile of the rectangle from `from` to `to`, rows walked outward from
## `from` so an area edit starts where the player pressed. Clamped to the map.
func drag_area(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var end := to
	if city != null:
		end = Vector2i(clampi(to.x, 0, City.WIDTH - 1), clampi(to.y, 0, City.HEIGHT - 1))
	var sx := 1 if end.x >= from.x else -1
	var sy := 1 if end.y >= from.y else -1
	for y in range(from.y, end.y + sy, sy):
		for x in range(from.x, end.x + sx, sx):
			out.append(Vector2i(x, y))
	return out


## Apply `op` to each tile in turn and merge the results.
func _run_line(tiles: Array[Vector2i], op: Callable) -> Dictionary:
	var changed: Array[Vector2i] = []
	var rect := Rect2i()
	var cost := 0
	var reason := ""
	for p in tiles:
		var r: Dictionary = op.call(p)
		if bool(r["ok"]):
			changed.append(p)
			cost += int(r["cost"])
			var tile_rect: Rect2i = r["rect"]
			rect = tile_rect if not rect.has_area() else rect.merge(tile_rect)
		elif reason.is_empty():
			reason = String(r["reason"])
	if changed.is_empty():
		return _with_tiles(_refuse(reason if not reason.is_empty() else "Nothing to change."), [])
	return {"ok": true, "cost": cost, "rect": rect, "reason": "", "tiles": changed}


static func _with_tiles(result: Dictionary, tiles: Array[Vector2i]) -> Dictionary:
	var out := result.duplicate()
	out["tiles"] = tiles if bool(result["ok"]) else ([] as Array[Vector2i])
	return out


# ── Ground ───────────────────────────────────────────────────────────────

## Lift the tile one level: its lowest corners rise to the base plus one, so
## a slope becomes flat ground one level up and flat ground rises whole.
func raise(x: int, y: int) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	var s := surface()
	var base := s.tile_base(x, y)
	if base >= TerrainSurface.MAX_HEIGHT:
		return _refuse("Cannot raise land any higher.")
	return _reshape(x, y, base + 1, RAISE_COST)


## Drop the tile one level: its highest corners fall to the top minus one.
func lower(x: int, y: int) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	var s := surface()
	var top := s.tile_top(x, y)
	if top <= TerrainSurface.MIN_HEIGHT:
		return _refuse("Cannot lower land any further.")
	return _reshape(x, y, top - 1, LOWER_COST)


## Flatten the tile at an exact height.
func level(x: int, y: int, to_height: int) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	var h := clampi(to_height, TerrainSurface.MIN_HEIGHT, TerrainSurface.MAX_HEIGHT)
	var s := surface()
	if s.is_tile_flat(x, y) and s.tile_base(x, y) == h:
		return _refuse("Already level.")
	return _reshape(x, y, h, LEVEL_COST)


## Set all four corners of a tile to `h`, pin them, repair the ripple and
## re-project. Refuses when a neighbouring built tile would change shape.
func _reshape(x: int, y: int, h: int, cost: int) -> Dictionary:
	var s := surface()
	var backup := s.duplicate_surface()
	var pins: Dictionary = {}
	for v in TerrainSurface.tile_vertices(x, y):
		s.set_vertex(v.x, v.y, h)
		pins[v] = true
	var repair := s.normalize(Rect2i(x, y, 1, 1), pins)
	# The ring around the tile shares its corners and changes shape with it.
	var rect := _around(x, y)
	var ripple: Rect2i = repair["rect"]
	if ripple.size.x > 0:
		rect = rect.merge(ripple)
	var blocked := _built_tile_in(rect, Vector2i(x, y))
	if blocked.x >= 0:
		s.copy_from(backup)
		return _refuse("Land under %s would move." % Buildings.display_name(city.building.at(blocked.x, blocked.y)))
	_settle_water(rect)
	_clear_trees(x, y)
	s.project(city, rect)
	return {"ok": true, "cost": cost, "rect": rect, "reason": ""}


# ── Water ────────────────────────────────────────────────────────────────

## Fill the tile with water one level above its base: a pond on flat ground,
## a shore on a slope. Brackish when it touches salt water. With `fill_basin`
## the water spreads through the enclosed hollow around the tile (every
## connected dry tile whose ground lies below the water), up to BASIN_LIMIT
## tiles; a wider area gets the single tile.
func place_water(x: int, y: int, fill_basin: bool = false) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	var s := surface()
	if s.has_water(x, y):
		return _refuse("Already water.")
	var base := s.tile_base(x, y)
	if base >= TerrainSurface.MAX_HEIGHT:
		return _refuse("Too high for water.")
	var level := base + 1
	var tiles: Array[Vector2i] = _basin(x, y, level) if fill_basin else ([Vector2i(x, y)] as Array[Vector2i])
	var brackish := false
	for t in tiles:
		for d in DIRECTIONS:
			var n: Vector2i = t + d
			if s.has_water(n.x, n.y) and s.is_salt(n.x, n.y):
				brackish = true
	var rect := Rect2i(x, y, 1, 1)
	for t in tiles:
		s.set_water(t.x, t.y, level, brackish)
		_clear_trees(t.x, t.y)
		rect = rect.merge(Rect2i(t, Vector2i.ONE))
	rect = TerrainSurface.clamp_rect(rect.grow(1))
	s.project(city, rect)
	return {"ok": true, "cost": WATER_COST, "rect": rect, "reason": ""}


## The enclosed hollow around a tile: the tile plus every dry, unbuilt tile
## reachable through neighbours whose ground lies below `level`. The map edge
## and higher ground bound it. An oversized hollow yields the tile alone.
func _basin(x: int, y: int, level: int) -> Array[Vector2i]:
	var s := surface()
	var origin := Vector2i(x, y)
	var seen := {origin: true}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in DIRECTIONS:
			var n: Vector2i = p + d
			if seen.has(n) or not city.in_bounds(n.x, n.y):
				continue
			if s.tile_base(n.x, n.y) >= level or s.has_water(n.x, n.y):
				continue
			var id := city.building.at(n.x, n.y)
			if id != Buildings.NONE and not Buildings.is_tree(id):
				continue
			seen[n] = true
			queue.append(n)
			if queue.size() > BASIN_LIMIT:
				return [origin]
	return queue


## Drain the tile, including a stream or waterfall segment.
func remove_water(x: int, y: int) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	var s := surface()
	if not s.has_water(x, y):
		return _refuse("No water here.")
	s.clear_water(x, y)
	var rect := _around(x, y)
	s.project(city, rect)
	return {"ok": true, "cost": WATER_COST, "rect": rect, "reason": ""}


# ── Trees ────────────────────────────────────────────────────────────────

## Plant a tree tile of the given density (1..7) on dry, empty ground.
func plant_trees(x: int, y: int, density: int = 1) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	if surface().has_water(x, y):
		return _refuse("Trees do not grow in water.")
	var id := Buildings.TREES_1 + clampi(density, 1, 7) - 1
	if city.building.at(x, y) == id:
		return _refuse("Already planted.")
	city.building.put(x, y, id)
	return {"ok": true, "cost": TREE_COST, "rect": Rect2i(x, y, 1, 1), "reason": ""}


## One tree on open ground, or one step denser on a tile already wooded.
func add_tree(x: int, y: int) -> Dictionary:
	var gate := _check_target(x, y)
	if not gate.is_empty():
		return gate
	if surface().has_water(x, y):
		return _refuse("Trees do not grow in water.")
	var id := city.building.at(x, y)
	if id == Buildings.TREES_7:
		return _refuse("The trees here are as dense as they grow.")
	city.building.put(x, y, Buildings.TREES_1 if id == Buildings.NONE else id + 1)
	return {"ok": true, "cost": TREE_COST, "rect": Rect2i(x, y, 1, 1), "reason": ""}


# ── Sea level ────────────────────────────────────────────────────────────

## Raise the sea one level. Standing water rises with it and floods onto
## neighbouring dry ground that lies below the new level; built tiles stay
## dry. Streams and waterfalls are untouched.
func raise_sea_level() -> Dictionary:
	if city.sea_level < 0:
		return _refuse("This map has no sea level.")
	if city.sea_level >= MAX_SEA_LEVEL:
		return _refuse("The sea is as high as it goes.")
	var s := surface()
	var old := city.sea_level
	var new_level := old + 1
	var queue: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if s.feature_at(x, y) != TerrainSurface.Feature.NONE:
				continue
			if s.has_water(x, y) and s.water_level(x, y) == old:
				s.set_water(x, y, new_level, s.is_salt(x, y))
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in DIRECTIONS:
			var n: Vector2i = p + d
			if not city.in_bounds(n.x, n.y) or s.has_water(n.x, n.y):
				continue
			if s.tile_base(n.x, n.y) >= new_level:
				continue
			var id := city.building.at(n.x, n.y)
			if id != Buildings.NONE and not Buildings.is_tree(id):
				continue
			s.set_water(n.x, n.y, new_level, s.is_salt(p.x, p.y))
			_clear_trees(n.x, n.y)
			queue.append(n)
	city.sea_level = new_level
	var rect := Rect2i(0, 0, City.WIDTH, City.HEIGHT)
	s.project(city, rect)
	return {"ok": true, "cost": SEA_LEVEL_COST, "rect": rect, "reason": ""}


## Lower the sea one level. Water at the old level drops with it and tiles
## left with no water above their ground become dry land.
func lower_sea_level() -> Dictionary:
	if city.sea_level < 0:
		return _refuse("This map has no sea level.")
	if city.sea_level <= MIN_SEA_LEVEL:
		return _refuse("The sea is as low as it goes.")
	var s := surface()
	var old := city.sea_level
	var new_level := old - 1
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if s.feature_at(x, y) != TerrainSurface.Feature.NONE:
				continue
			if s.has_water(x, y) and s.water_level(x, y) == old:
				if new_level > s.tile_base(x, y):
					s.set_water(x, y, new_level, s.is_salt(x, y))
				else:
					s.clear_water(x, y)
	city.sea_level = new_level
	var rect := Rect2i(0, 0, City.WIDTH, City.HEIGHT)
	s.project(city, rect)
	return {"ok": true, "cost": SEA_LEVEL_COST, "rect": rect, "reason": ""}


# ── Helpers ──────────────────────────────────────────────────────────────

## Empty when the tile may be edited, otherwise a refusal result.
func _check_target(x: int, y: int) -> Dictionary:
	if city == null:
		return _refuse("No city.")
	if not city.in_bounds(x, y):
		return _refuse("Off the map.")
	if city.terrain_surface == null:
		attach(city)
	var id := city.building.at(x, y)
	if id != Buildings.NONE and not Buildings.is_tree(id):
		return _refuse("Demolish %s first." % Buildings.display_name(id))
	return {}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "cost": 0, "rect": Rect2i(), "reason": reason}


func _clear_trees(x: int, y: int) -> void:
	if Buildings.is_tree(city.building.at(x, y)):
		city.building.put(x, y, Buildings.NONE)


## The tile and its four neighbours, clamped to the map.
static func _around(x: int, y: int) -> Rect2i:
	return TerrainSurface.clamp_rect(Rect2i(x - 1, y - 1, 3, 3))


## First tile in `rect` other than `target` that holds a building (trees
## excepted), or (-1, -1).
func _built_tile_in(rect: Rect2i, target: Vector2i) -> Vector2i:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x == target.x and y == target.y:
				continue
			var id := city.building.at(x, y)
			if id != Buildings.NONE and not Buildings.is_tree(id):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## After ground moves: water that no longer stands above its tile drains,
## and a tile that dropped below neighbouring standing water floods.
func _settle_water(rect: Rect2i) -> void:
	var s := surface()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var base := s.tile_base(x, y)
			var w := s.water_level(x, y)
			if w != TerrainSurface.NO_WATER and w <= base:
				s.clear_water(x, y)
			elif w == TerrainSurface.NO_WATER:
				for d in DIRECTIONS:
					var n: Vector2i = Vector2i(x, y) + d
					if s.feature_at(n.x, n.y) != TerrainSurface.Feature.NONE:
						continue
					var nw := s.water_level(n.x, n.y)
					if nw > base and s.has_water(n.x, n.y):
						s.set_water(x, y, nw, s.is_salt(n.x, n.y))
						break
