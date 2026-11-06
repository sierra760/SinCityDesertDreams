# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name HighwayGantryPlacement3D
extends RefCounted

## Overhead exit and distance gantries. Every gantry stands entirely on one
## straight highway carriageway tile: both posts on that tile's shoulders and
## the truss and boards above its lanes. Nothing else can occupy a highway
## tile, so neighbouring lots never hide or clip a gantry.

const METRES := 16.0
const CONTRACT := "res://assets/street-name-signs/gantry-templates.json"
## Exaggerated sign scale: one tile reads as a sixteenth of a mile.
const TILES_PER_MILE := 16.0
## The shoulder is drawn this far below the carriageway's pavement.
const SHOULDER_DROP := .008
## Exit gantries prefer two tiles before the exit, then one.
const EXIT_LEADS: Array[int] = [2, 1]
## Distance gantries follow an interchange by two to five tiles.
const AFTER_INTERCHANGE: Array[int] = [2, 3, 4, 5]
const MIN_SPACING := 3.0
## Open highway repeats a distance gantry about once a mile.
const STRETCH := 16.0
## A listed destination is at least this far ahead of its gantry.
const MIN_LISTED := 3.0
const MAX_ROWS := 3
const LOOKAHEAD := 192.0

static var _contract: Dictionary = {}

static func contract() -> Dictionary:
	if _contract.is_empty(): _contract = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	return _contract

static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

## "¼ MI", "1½ MI": nearest quarter mile at the exaggerated sign scale.
static func distance_text(tiles: float) -> String:
	var quarters := maxi(1, roundi(tiles / TILES_PER_MILE * 4.0))
	var whole := quarters / 4
	var fraction: String = ["", "¼", "½", "¾"][quarters % 4]
	return (str(whole) if whole > 0 else "") + fraction + " MI"

static func _key(cell: Vector2i, previous: Vector2i) -> Vector4i:
	return Vector4i(cell.x, cell.y, previous.x, previous.y)

## The carriageway's own lane route through `cell` arriving from `previous`,
## preferring straight on at a highway-highway crossing.
static func _route(routes: Dictionary, cell: Vector2i, previous: Vector2i) -> Dictionary:
	var best: Dictionary = {}
	for route: Dictionary in routes.get(cell, []):
		if int(route.lane) != 1 or route.previous != previous: continue
		if route.next == cell + (cell - previous): return route
		if best.is_empty() or (route.next.y < best.next.y or (route.next.y == best.next.y and route.next.x < best.next.x)): best = route
	return best

## Can a rigid gantry stand on this carriageway tile facing traffic that
## travels `direction`? Returns its transform and stretched-post feet.
static func site(city: City, graph: CityTrafficGraph, cell: Vector2i, direction: Vector2i) -> Dictionary:
	if city == null or graph == null: return _failed("No city")
	if not city.in_bounds(cell.x, cell.y): return _failed("Map edge")
	var code := city.building.atv(cell)
	if not NetworkShapes.is_highway(code): return _failed("Not a highway")
	var mask := CityNetworks3D.network_mask(code, NetworkShapes.Family.HIGHWAY)
	if not ((mask == 5 and direction.x == 0) or (mask == 10 and direction.y == 0)): return _failed("Not straight along travel")
	if code in [NetworkShapes.HIGHWAY_NS_ROAD_EW, NetworkShapes.HIGHWAY_EW_ROAD_NS, NetworkShapes.HIGHWAY_NS_RAIL_EW,
			NetworkShapes.HIGHWAY_EW_RAIL_NS, NetworkShapes.HIGHWAY_NS_POWER_EW, NetworkShapes.HIGHWAY_EW_POWER_NS]:
		return _failed("Crossing")
	if city.is_water(cell.x, cell.y): return _failed("Bridge deck")
	if not graph.has_cell(cell, &"highway"): return _failed("No carriageway")
	if _route(graph.highways.routes, cell, cell - direction).is_empty(): return _failed("Opposite carriageway")
	var right := Vector2i(-direction.y, direction.x)
	for side: Vector2i in [right, -right]:
		var n := cell + side
		if not city.in_bounds(n.x, n.y) or not NetworkShapes.is_onramp(city.building.atv(n)): continue
		var ends := NetworkShapes.onramp_endpoints(city.building.atv(n), bool(city.flags.atv(n) & RotationMapper.AXIS_FLAG))
		if n + Vector2i(ends[1]) == cell or n + Vector2i(ends[0]) == cell: return _failed("Ramp mouth")
	var template: Dictionary = contract().templates["highway-gantry"]
	var center := graph.point(cell, &"highway", Vector2(.5, .5))
	var front := Vector3(-direction.x, 0, -direction.y)
	var basis := Basis(Vector3.UP.cross(front), Vector3.UP, front)
	var transform := Transform3D(basis, center)
	var feet: Dictionary = {}
	var contacts: Array[Vector3] = []
	var lateral := float(template.post_x_m) / METRES
	var half_shoe := float(template.shoe_size_m) * .5 / METRES
	for entry: Array in [["L", -1.0], ["R", 1.0]]:
		var foot := Vector2(.5, .5) + Vector2(right) * lateral * float(entry[1])
		var lowest := INF
		var corners: Array[Vector3] = []
		for delta: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := graph.point(cell, &"highway", foot + delta * half_shoe)
			p.y -= SHOULDER_DROP
			corners.append(p)
			lowest = minf(lowest, p.y)
		if not is_finite(lowest): return _failed("No shoulder support")
		if (lowest - center.y) * METRES > 1.5: return _failed("Shoulder above deck")
		feet[entry[0]] = (lowest - center.y) * METRES
		contacts.append_array(corners)
	return {"ok": true, "reason": "", "transform": transform,
		"support": {"kind": "highway_shoulders", "highway_cell": cell, "deck_height": center.y, "feet_m": feet, "contacts": contacts, "clearance_checked": true}}

## Gantry records keyed by carriageway tile and travel direction. `exits` are
## exit approaches annotated with "text" (named destination or "") and "ids".
static func plan(city: City, graph: CityTrafficGraph, exits: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	var diagnostics: Array[Dictionary] = []
	if city == null or graph == null: return {"gantries": result, "diagnostics": diagnostics}
	var routes: Dictionary = graph.highways.routes
	var taken: Dictionary = {}
	var by_state: Dictionary = {}
	# Exit gantries first: they own the tiles just before their exit.
	for exit: Dictionary in exits:
		var high: Vector2i = exit.highway
		var direction: Vector2i = exit.direction
		by_state[_key(high, high - direction)] = exit
		if String(exit.text).is_empty(): continue
		var key := "exit:" + str(high) + ":" + str(direction)
		if result.has(key): continue
		var placed := false
		var reasons: Array[String] = []
		var cells: Array = exit.upstream_cells
		for lead: int in EXIT_LEADS:
			if lead >= cells.size(): continue
			var cell: Vector2i = cells[lead]
			var travel: Vector2i = cells[lead - 1] - cell if lead > 0 else direction
			if travel != direction: reasons.append("Bend before exit");continue
			if taken.has(_key(cell, travel)): reasons.append("Taken");continue
			var spot := site(city, graph, cell, travel)
			if not spot.ok: reasons.append(spot.reason);continue
			var side := 1.0 if Vector2(exit.ramp - exit.highway).dot(Vector2(-direction.y, direction.x)) > 0 else -1.0
			result[key] = {"kind": "exit", "cell": cell, "direction": travel, "placed": spot,
				"text": exit.text, "ids": exit.ids, "arrow": "→" if side > 0 else "←", "side": side}
			taken[_key(cell, travel)] = true
			placed = true
			break
		if not placed: diagnostics.append({"key": key, "reason": "No straight carriageway tile before exit: " + ", ".join(reasons)})
	# Distance gantries along each carriageway, from its upstream end.
	var states: Dictionary = {}
	var has_previous: Dictionary = {}
	for cell: Vector2i in routes:
		for route: Dictionary in routes[cell]:
			if int(route.lane) != 1: continue
			states[_key(cell, route.previous)] = true
			has_previous[_key(route.next, cell)] = true
	var starts: Array[Vector4i] = []
	var rest: Array[Vector4i] = []
	for state: Vector4i in states: (rest if has_previous.has(state) else starts).append(state)
	var order := func(a: Vector4i, b: Vector4i) -> bool:
		if a.y != b.y: return a.y < b.y
		if a.x != b.x: return a.x < b.x
		if a.w != b.w: return a.w < b.w
		return a.z < b.z
	starts.sort_custom(order)
	rest.sort_custom(order)
	starts.append_array(rest)
	var visited: Dictionary = {}
	for start: Vector4i in starts:
		if visited.has(start): continue
		var entries: Array[Dictionary] = []
		var state := start
		var s := 0.0
		while states.has(state) and not visited.has(state):
			visited[state] = true
			var cell := Vector2i(state.x, state.y)
			var previous := Vector2i(state.z, state.w)
			entries.append({"cell": cell, "direction": cell - previous, "state": state, "s": s})
			var route := _route(routes, cell, previous)
			if route.is_empty(): break
			s += float(route.length)
			state = _key(route.next, cell)
		_place_distances(city, graph, entries, routes, states, by_state, taken, result)
	return {"gantries": result, "diagnostics": diagnostics}

static func _place_distances(city: City, graph: CityTrafficGraph, entries: Array[Dictionary], routes: Dictionary,
		states: Dictionary, by_state: Dictionary, taken: Dictionary, result: Dictionary) -> void:
	var last := -INF
	var pending := -1
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var s: float = entry.s
		if taken.has(_key(entry.cell, entry.direction)): last = s
		var after := pending >= 0 and i - pending in AFTER_INTERCHANGE
		if pending >= 0 and i - pending > AFTER_INTERCHANGE[-1]: pending = -1
		var stretch := last > -INF and s - last >= STRETCH
		if last == -INF and i == 0: last = s
		if after or stretch:
			if s - last >= MIN_SPACING and not _taken_ahead(entries, i, taken):
				var rows := _ahead(routes, states, by_state, entry.state)
				if not rows.is_empty() and (after or float(rows[0].tiles) >= STRETCH * .5):
					var spot := site(city, graph, entry.cell, entry.direction)
					if spot.ok:
						var lines: Array = []
						var ids: Array[int] = []
						for row: Dictionary in rows:
							lines.append([row.text, distance_text(row.tiles)])
							for id: int in row.ids:
								if not ids.has(id): ids.append(id)
						result["distance:" + str(entry.cell) + ":" + str(entry.direction)] = {"kind": "distance",
							"cell": entry.cell, "direction": entry.direction, "placed": spot, "rows": lines, "ids": ids}
						taken[_key(entry.cell, entry.direction)] = true
						last = s
						if after: pending = -1
		if by_state.has(entry.state): pending = i

static func _taken_ahead(entries: Array[Dictionary], i: int, taken: Dictionary) -> bool:
	for j: int in range(i + 1, entries.size()):
		if float(entries[j].s) - float(entries[i].s) >= MIN_SPACING: return false
		if taken.has(_key(entries[j].cell, entries[j].direction)): return true
	return false

## The next named exits ahead of a carriageway state, following its lanes past
## crossings and around rings, with travelled distance in tiles.
static func _ahead(routes: Dictionary, states: Dictionary, by_state: Dictionary, from: Vector4i) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var state := from
	var travelled := 0.0
	while states.has(state) and not seen.has(state) and travelled <= LOOKAHEAD:
		seen[state] = true
		if by_state.has(state) and travelled >= MIN_LISTED:
			var exit: Dictionary = by_state[state]
			if not String(exit.text).is_empty():
				rows.append({"text": exit.text, "ids": exit.ids, "tiles": travelled})
				if rows.size() == MAX_ROWS: break
		var cell := Vector2i(state.x, state.y)
		var route := _route(routes, cell, Vector2i(state.z, state.w))
		if route.is_empty(): break
		travelled += float(route.length)
		state = _key(route.next, cell)
	return rows
