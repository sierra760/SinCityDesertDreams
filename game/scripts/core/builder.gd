# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Every player edit of the map.
##
## `preview` prices a drag without touching the city; `apply` prices it the
## same way, then writes it, debits funds, records facilities and tells the
## simulation what changed. The UI never writes to the layers directly.
##
## A plan is a Dictionary: ok, cost, tiles, rect, reason, plus a private list
## of write operations that `apply` executes in order.
class_name Builder
extends RefCounted

## Longest water gap a causeway may cross; longer spans need a suspension bridge.
const CAUSEWAY_MAX_SPAN := 6
## Longest span of any bridge, in water tiles.
const BRIDGE_MAX_SPAN := 24
const BRIDGE_COST_CAUSEWAY := 25
const BRIDGE_COST_SUSPENSION := 75
const BRIDGE_COST_RAIL := 75
const BRIDGE_COST_POWER := 10
## Longest tunnel bore including both portals.
const TUNNEL_MAX_LENGTH := 30
const SIGN_LIMIT := 50
const SIGN_TEXT_MAX := 24
const MAX_GROUND_HEIGHT := 31
## Price of one raise, lower or level step on one tile.
const TERRAIN_STEP_COST := 25
## Price of carrying a network across the city limit to a neighboring town,
## keyed by NetworkShapes family.
const NEIGHBOR_LINK_COST := {
	NetworkShapes.Family.ROAD: 100,
	NetworkShapes.Family.RAIL: 250,
	NetworkShapes.Family.POWER: 50,
	NetworkShapes.Family.PIPE: 50,
}
## Buildings whose neighbours may object to them: heavy plants, the prison
## and the treatment works.
const OPPOSITION_BUILDINGS: Array[int] = [Buildings.NUCLEAR_PLANT, Buildings.COAL_PLANT,
	Buildings.OIL_PLANT, Buildings.GAS_PLANT, Buildings.PRISON, Buildings.WATER_TREATMENT]
## Residential zoning is counted this many tiles around the footprint.
const OPPOSITION_RADIUS := 8
## The objection threshold is drawn from 0 .. RANGE-1 and compared with the count.
const OPPOSITION_THRESHOLD_RANGE := 200
## Clearing more tree tiles than this in one drag draws a protest.
const TREE_PROTEST_THRESHOLD := 5
const FACILITY_NAME_MAX := 24
## Most ramp sites `onramp_sites` offers at once.
const ONRAMP_OFFER_LIMIT := 4

const REASON_FUNDS := "insufficient funds"
const REASON_BOUNDS := "outside the city"
const REASON_LIMIT := "reaches the city limit"
const REASON_BEFORE_FOUNDING := "the sea level is set before the city is founded"
## Dispatch tools outside an emergency, or with no station of that kind.
const REASON_NO_EMERGENCY := "crews go out only during an emergency"
const REASON_NO_CREWS := "no crews available"

const _AXIS_NS := NetworkShapes.AXIS_NS
const _AXIS_EW := NetworkShapes.AXIS_EW
const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var city: City
var stats: CityStats
var sim: Simulation
## When true, every placement that can draw an objection does.
var forced_opposition := false

## Year of the last tree protest, so citizens complain at most once a year.
var _tree_protest_year := -1
## Randomness when no simulation is attached.
var _local_rng := SimRng.new(1)


func _init(p_city: City, p_stats: CityStats, p_sim: Simulation = null) -> void:
	city = p_city
	stats = p_stats
	sim = p_sim


# ── Public API ───────────────────────────────────────────────────────────

## Price a drag without changing anything. `options` may carry a `choice`
## (bridge or tunnel style), `connect` (carry the last tile across the city
## limit) or `proceed` (build despite an objection).
func preview(tool: int, from: Vector2i, to: Vector2i = Vector2i(-1, -1), options: Dictionary = {}) -> Dictionary:
	var plan := _plan(tool, from, to if to != Vector2i(-1, -1) else from, options)
	plan.erase("ops")
	return plan


## Price and perform a drag. `applied` reports whether the city changed. A
## plan that needs the player's answer first comes back with
## `needs_confirmation` and nothing charged; answer it through `options`.
func apply(tool: int, from: Vector2i, to: Vector2i = Vector2i(-1, -1), options: Dictionary = {}) -> Dictionary:
	var plan := _plan(tool, from, to if to != Vector2i(-1, -1) else from, options)
	plan["applied"] = false
	if not bool(plan["ok"]):
		plan.erase("ops")
		return plan
	if _objection_raised(plan, options):
		plan["needs_confirmation"] = true
		plan["choice_kind"] = &"opposition"
		plan.erase("ops")
		return plan
	var ops: Array = plan["ops"]
	var touched := _commit(ops)
	city.funds -= int(plan["cost"])
	var rect: Rect2i = plan["rect"]
	if not touched.is_empty():
		rect = _bounds(touched).grow(1).intersection(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
		plan["rect"] = rect
	if sim != null:
		sim.networks_changed(rect)
	if plan.has("neighbor_link"):
		_record_neighbor_link(plan["neighbor_link"])
	_tree_protest(plan)
	plan["applied"] = true
	plan.erase("ops")
	return plan


## Give a facility a name of its own (shown by the query panel). Empty text
## clears it. Returns {ok, reason}.
func rename_facility(at: Vector2i, text: String) -> Dictionary:
	if not city.in_bounds(at.x, at.y):
		return {"ok": false, "reason": REASON_BOUNDS}
	var anchor := city.anchor_of(at.x, at.y)
	if not city.facilities.has(anchor):
		return {"ok": false, "reason": "no facility here"}
	var record: Dictionary = city.facilities[anchor]
	var trimmed := text.strip_edges().left(FACILITY_NAME_MAX)
	if trimmed.is_empty():
		record.erase("name")
	else:
		record["name"] = trimmed
	return {"ok": true, "reason": ""}


## The map edge a border tile lies on, indexed like the neighbor system
## (0 north, 1 east, 2 south, 3 west), or -1 inland. Corners count for the
## north or south edge.
static func border_edge(p: Vector2i) -> int:
	if p.y == 0:
		return 0
	if p.y == City.HEIGHT - 1:
		return 2
	if p.x == 0:
		return 3
	if p.x == City.WIDTH - 1:
		return 1
	return -1


## Whether the objection gate stops this placement. Draws the threshold from
## the simulation's random stream; only sites near homes can fail it.
func _objection_raised(plan: Dictionary, options: Dictionary) -> bool:
	if bool(options.get("proceed", false)):
		return false
	if not plan.has("opposition_exposure"):
		return false
	var exposure := int(plan["opposition_exposure"])
	var rng: SimRng = sim.rng if sim != null and sim.rng != null else _local_rng
	var threshold := rng.below(OPPOSITION_THRESHOLD_RANGE)
	return forced_opposition or exposure > threshold


func _record_neighbor_link(link: Dictionary) -> void:
	if sim == null:
		return
	var neighbors := sim.get_system(&"neighbors")
	if neighbors != null and neighbors.has_method("record_connection"):
		neighbors.call("record_connection", int(link["edge"]), StringName(String(link["kind"])))


## Attach a once-a-year protest notice when a drag felled too many trees.
func _tree_protest(plan: Dictionary) -> void:
	var felled := int(plan.get("trees_cleared", 0))
	if felled <= TREE_PROTEST_THRESHOLD:
		return
	var year := city.current_year()
	if year == _tree_protest_year:
		return
	_tree_protest_year = year
	var notices: Array = plan.get("notices", [])
	notices.append({"kind": &"tree_protest", "payload": {"count": felled}})
	plan["notices"] = notices


## Write a sign. Empty text removes it. Returns {ok, reason}.
func place_sign(at: Vector2i, text: String) -> Dictionary:
	if not city.in_bounds(at.x, at.y):
		return {"ok": false, "reason": REASON_BOUNDS}
	var trimmed := text.strip_edges().left(SIGN_TEXT_MAX)
	if trimmed.is_empty():
		city.signs.erase(at)
		return {"ok": true, "reason": ""}
	if not city.signs.has(at) and city.signs.size() >= SIGN_LIMIT:
		return {"ok": false, "reason": "sign limit reached"}
	city.signs[at] = trimmed
	return {"ok": true, "reason": ""}


# ── Planning ─────────────────────────────────────────────────────────────

func _plan(tool: int, from: Vector2i, to: Vector2i, options: Dictionary = {}) -> Dictionary:
	var locked := Tools.locked_reason(tool, city, stats)
	if not locked.is_empty():
		return _fail(locked)
	if Tools.is_editing_only(tool):
		return _fail(REASON_BEFORE_FOUNDING)
	if Tools.mode(tool) != Tools.Mode.GLOBAL and not city.in_bounds(from.x, from.y):
		return _fail(REASON_BOUNDS)
	to = Vector2i(clampi(to.x, 0, City.WIDTH - 1), clampi(to.y, 0, City.HEIGHT - 1))
	var plan: Dictionary
	match tool:
		Tools.Kind.QUERY:
			plan = _ok([from], 0, [])
		Tools.Kind.SIGN:
			plan = _ok([from], 0, [])
		Tools.Kind.ROAD:
			plan = _plan_network(NetworkShapes.Family.ROAD, Tools.cost(tool), from, to, options)
		Tools.Kind.RAIL:
			plan = _plan_network(NetworkShapes.Family.RAIL, Tools.cost(tool), from, to, options)
		Tools.Kind.POWER_LINE:
			plan = _plan_network(NetworkShapes.Family.POWER, Tools.cost(tool), from, to, options)
		Tools.Kind.WATER_PIPE:
			plan = _plan_underground(NetworkShapes.Family.PIPE, Tools.cost(tool), from, to, options)
		Tools.Kind.SUBWAY:
			plan = _plan_underground(NetworkShapes.Family.SUBWAY, Tools.cost(tool), from, to, options)
		Tools.Kind.HIGHWAY:
			plan = _plan_highway(Tools.cost(tool), from, to)
		Tools.Kind.ONRAMP:
			plan = _plan_onramp(Tools.cost(tool), from)
		Tools.Kind.TUNNEL:
			plan = _plan_tunnel(Tools.cost(tool), from)
		Tools.Kind.SUBWAY_PORTAL:
			plan = _plan_subway_portal(Tools.cost(tool), from)
		Tools.Kind.SUBWAY_STATION:
			plan = _plan_subway_station(Tools.cost(tool), from)
		Tools.Kind.DEZONE:
			plan = _plan_dezone(Tools.cost(tool), from, to)
		Tools.Kind.BULLDOZE:
			plan = _plan_bulldoze(Tools.cost(tool), from, to)
		Tools.Kind.TREES:
			plan = _plan_trees(Tools.cost(tool), _line_tiles(from, to))
		Tools.Kind.FOREST:
			plan = _plan_trees(Tools.cost(tool), _area_tiles(from, to))
		Tools.Kind.PLANT_TREE:
			plan = _plan_tree(Tools.cost(tool), from)
		Tools.Kind.RAISE_LAND:
			plan = _plan_raise_lower(from, 1)
		Tools.Kind.LOWER_LAND:
			plan = _plan_raise_lower(from, -1)
		Tools.Kind.LEVEL_LAND:
			plan = _plan_level(from, to)
		Tools.Kind.PLACE_WATER:
			plan = _plan_water(Tools.cost(tool), from)
		_:
			if Tools.is_dispatch_tool(tool):
				plan = _plan_dispatch(Tools.dispatch_kind(tool), from)
			elif Tools.is_zone_tool(tool):
				plan = _plan_zone(Tools.zone_kind(tool), Tools.cost(tool), from, to)
			elif Tools.is_building_tool(tool):
				plan = _plan_building(tool, from)
			else:
				plan = _fail("unknown tool")
	if bool(plan["ok"]) and int(plan["cost"]) > city.funds:
		plan["ok"] = false
		plan["reason"] = REASON_FUNDS
	return plan


func _fail(reason: String, tiles: Array[Vector2i] = []) -> Dictionary:
	return {"ok": false, "cost": 0, "tiles": tiles, "rect": _bounds(tiles), "reason": reason, "ops": []}


func _ok(tiles: Array[Vector2i], cost: int, ops: Array) -> Dictionary:
	return {"ok": true, "cost": cost, "tiles": tiles, "rect": _bounds(tiles), "reason": "", "ops": ops}


## Record why a drag that still builds something stopped short of its end,
## so the preview and the result can tell the player. Changes nothing else.
static func _note_stop(plan: Dictionary, stop_reason: String) -> Dictionary:
	if not stop_reason.is_empty():
		plan["stopped"] = stop_reason
	return plan


static func _bounds(tiles: Array[Vector2i]) -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	var r := Rect2i(tiles[0], Vector2i.ONE)
	for t in tiles:
		r = r.merge(Rect2i(t, Vector2i.ONE))
	return r


# ── Drag geometry ────────────────────────────────────────────────────────

## L-shaped walk from `from` to `to`, longer axis first. Each step records
## the axis it travels on and whether the walk turns there.
static func _line(from: Vector2i, to: Vector2i, step: int = 1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := to - from
	var x_first := absi(d.x) >= absi(d.y)
	var first_axis := _AXIS_EW if x_first else _AXIS_NS
	var corner := Vector2i(to.x, from.y) if x_first else Vector2i(from.x, to.y)
	var p := from
	out.append({"pos": p, "axis": first_axis, "turn": false})
	while p != corner:
		p += Vector2i(signi(corner.x - p.x), signi(corner.y - p.y)) * step
		out.append({"pos": p, "axis": first_axis, "turn": false})
	var second_axis := _AXIS_NS if x_first else _AXIS_EW
	if corner != to:
		out[out.size() - 1]["turn"] = out.size() > 1
	while p != to:
		p += Vector2i(signi(to.x - p.x), signi(to.y - p.y)) * step
		out.append({"pos": p, "axis": second_axis, "turn": false})
	return out


static func _line_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for step in _line(from, to):
		out.append(step["pos"])
	return out


## Every tile of the dragged rectangle, rows walked outward from `from`, so
## an area edit works from the tile the player started on.
static func _area_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sx := 1 if to.x >= from.x else -1
	var sy := 1 if to.y >= from.y else -1
	for y in range(from.y, to.y + sy, sy):
		for x in range(from.x, to.x + sx, sx):
			out.append(Vector2i(x, y))
	return out


static func _rect_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			out.append(Vector2i(x, y))
	return out


# ── Tile predicates ──────────────────────────────────────────────────────

## Ground that construction may take over for free: open, rubble or trees.
static func _clearable(id: int) -> bool:
	return id == Buildings.NONE or (id >= Buildings.RUBBLE_1 and id <= Buildings.RUBBLE_4) or Buildings.is_tree(id)


## Buildings replace standalone lines; transport crossings and bridges stay blocked.
static func _building_clearable(id: int) -> bool:
	return _clearable(id) or NetworkShapes.is_plain_power(id)


func _dry(p: Vector2i) -> bool:
	return not city.is_water(p.x, p.y)


func _protected(p: Vector2i) -> bool:
	return city.flags.has_bits(p.x, p.y, TileFlags.LANDMARK) or city.zone_kind_at(p.x, p.y) == Zones.MILITARY


func _slope(p: Vector2i) -> int:
	return Terrain.slope(city.terrain.at(p.x, p.y))


## Whether a straight slope may carry a run along `axis`. A run of no fixed
## axis (a single-tile drag inland) fits any straight slope.
static func _slope_fits(slope: int, axis: int) -> bool:
	if axis == NetworkShapes.AXIS_ANY:
		return Terrain.is_edge_slope(slope)
	if slope == Terrain.SLOPE_N or slope == Terrain.SLOPE_S:
		return axis == _AXIS_NS
	if slope == Terrain.SLOPE_E or slope == Terrain.SLOPE_W:
		return axis == _AXIS_EW
	return false


func _touches_water(p: Vector2i) -> bool:
	for d in _DIRS:
		var n := p + d
		if city.in_bounds(n.x, n.y) and city.is_water(n.x, n.y):
			return true
	return false


## Axis a one-tile drag runs on: across the city limit at the map edge (the
## way a neighbor link leaves town), otherwise any.
static func _single_tile_axis(p: Vector2i) -> int:
	match border_edge(p):
		0, 2: return _AXIS_NS
		1, 3: return _AXIS_EW
	return NetworkShapes.AXIS_ANY


## Axis of a straight road, rail or power line tile, or AXIS_ANY.
static func _straight_axis(id: int) -> int:
	if id == Buildings.ROAD_FIRST + NetworkShapes.SHAPE_NS or id == Buildings.POWER_LINE_FIRST + NetworkShapes.SHAPE_NS \
			or id == NetworkShapes.RAIL_BY_SHAPE[NetworkShapes.SHAPE_NS]:
		return _AXIS_NS
	if id == Buildings.ROAD_FIRST + NetworkShapes.SHAPE_EW or id == Buildings.POWER_LINE_FIRST + NetworkShapes.SHAPE_EW \
			or id == NetworkShapes.RAIL_BY_SHAPE[NetworkShapes.SHAPE_EW]:
		return _AXIS_EW
	return NetworkShapes.AXIS_ANY


## Axis of a straight pipe or subway run, or AXIS_ANY.
static func _underground_straight_axis(code: int) -> int:
	var mask := code if code <= NetworkShapes.PIPE_LAST else code - NetworkShapes.SUBWAY_OFFSET
	if code >= NetworkShapes.PIPE_FIRST and code <= NetworkShapes.SUBWAY_LAST:
		if mask == NetworkShapes.NORTH | NetworkShapes.SOUTH:
			return _AXIS_NS
		if mask == NetworkShapes.EAST | NetworkShapes.WEST:
			return _AXIS_EW
	return NetworkShapes.AXIS_ANY


## A new run may cross an existing straight only straight through it, at
## right angles: never where the drag turns, never running along it.
static func _crosses_at_right_angle(step: Dictionary, axis: int, existing_axis: int) -> bool:
	if bool(step["turn"]) or existing_axis == NetworkShapes.AXIS_ANY:
		return false
	return axis == NetworkShapes.AXIS_ANY or axis != existing_axis


# ── Roads, rail, power ───────────────────────────────────────────────────

## Bridge styles a family may use, in the order offered; the first allowed
## one is the default when the caller makes no choice.
const _BRIDGE_STYLES := {
	NetworkShapes.Family.ROAD: [&"causeway", &"suspension"],
	NetworkShapes.Family.RAIL: [&"rail"],
	NetworkShapes.Family.POWER: [&"elevated"],
}
const _BRIDGE_STYLE_COST := {
	&"causeway": BRIDGE_COST_CAUSEWAY,
	&"suspension": BRIDGE_COST_SUSPENSION,
	&"rail": BRIDGE_COST_RAIL,
	&"elevated": BRIDGE_COST_POWER,
}


func _plan_network(family: int, price: int, from: Vector2i, to: Vector2i, options: Dictionary = {}) -> Dictionary:
	var path := _line(from, to)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var cost := 0
	var stop_reason := ""
	var spans: Array[Dictionary] = []
	var neighbor := _neighbor_candidate(family, to)
	var connect := bool(options.get("connect", false))
	var prompt: Dictionary = {}
	var link: Dictionary = {}
	# The far bank of the last bridge until the drag lands on it; a bridge
	# whose landing is refused is not built.
	var landing := Vector2i(-1, -1)
	var stopped_on_landing := false
	var i := 0
	while i < path.size():
		var step: Dictionary = path[i]
		var p: Vector2i = step["pos"]
		var axis: int = step["axis"]
		if path.size() == 1:
			axis = _single_tile_axis(p)
		stopped_on_landing = p == landing
		var id := city.building_at(p.x, p.y)
		var terrain := city.terrain.at(p.x, p.y)
		if city.is_water(p.x, p.y) and Terrain.water_kind(terrain) != Terrain.WATERFALL:
			if i == 0:
				stop_reason = "start a bridge from the shore"
				break
			var direction: Vector2i = p - (path[i - 1]["pos"] as Vector2i)
			var bridge := _plan_bridge(family, p, direction)
			if not bool(bridge["ok"]):
				stop_reason = bridge["reason"]
				break
			spans.append(bridge)
			var bank: Vector2i = bridge["bank"]
			var resume := -1
			for j in range(i, path.size()):
				if path[j]["pos"] == bank:
					resume = j
					break
			if resume < 0:
				# The drag ended over the water: land on the far bank as the
				# main walk would, or not build this bridge at all.
				var bank_id := city.building_at(bank.x, bank.y)
				if not NetworkShapes.in_family(bank_id, family):
					var refusal := _landing_refusal(family, bank, bridge["axis"])
					if not refusal.is_empty():
						spans.pop_back()
						stop_reason = refusal
						break
					tiles.append(bank)
					ops.append(_surface_op(bank, NetworkShapes.shape_id(family, 0, city.terrain.at(bank.x, bank.y)), family))
					cost += price
				break
			landing = bank
			i = resume
			continue
		if NetworkShapes.in_family(id, family):
			if Buildings.is_developed(id):
				break
			i += 1
			continue
		if _protected(p):
			stop_reason = "protected land"
			break
		var at_limit := border_edge(p) >= 0 and NEIGHBOR_LINK_COST.has(family)
		if at_limit and p != neighbor.get("tile", Vector2i(-1, -1)):
			stop_reason = REASON_LIMIT
			break
		if NetworkShapes.is_highway(id):
			# A highway is two tiles wide: the run crosses both at once.
			var over := _highway_overpass(family, path, i)
			if not bool(over["ok"]):
				stop_reason = over["reason"]
				break
			for k in 2:
				var t: Vector2i = path[i + k]["pos"]
				tiles.append(t)
				ops.append(_surface_op(t, int(over["id"]), family))
				cost += price
			i += 2
			continue
		var crossing := NetworkShapes.crossing_id(family, id)
		if crossing != Buildings.NONE and city.is_flat(p.x, p.y) \
				and _crosses_at_right_angle(step, axis, _straight_axis(id)):
			tiles.append(p)
			ops.append(_surface_op(p, crossing, family))
			cost += price
			i += 1
			continue
		if not _clearable(id):
			stop_reason = "blocked by %s" % Buildings.display_name(id)
			break
		var slope := _slope(p)
		if not city.is_flat(p.x, p.y):
			if not _slope_fits(slope, axis) or bool(step["turn"]):
				stop_reason = "the slope runs across the path"
				break
		if at_limit:
			# The last tile of the drag lies on the city limit: it is built
			# only as an accepted connection to the neighboring town.
			if not connect:
				prompt = neighbor
				break
			link = {"edge": int(neighbor["edge"]), "kind": neighbor["kind"]}
			tiles.append(p)
			ops.append(_surface_op(p, NetworkShapes.shape_id(family, 0, terrain), family))
			cost += int(neighbor["cost"])
			i += 1
			continue
		tiles.append(p)
		ops.append(_surface_op(p, NetworkShapes.shape_id(family, 0, terrain), family))
		cost += price
		i += 1
	if stopped_on_landing and not stop_reason.is_empty() and not spans.is_empty():
		spans.pop_back()
	var plan: Dictionary
	if tiles.is_empty() and spans.is_empty():
		if prompt.is_empty():
			return _fail(stop_reason if not stop_reason.is_empty() else "nothing to build", [from])
		plan = _ok([], 0, [])
	else:
		plan = _ok(tiles, cost, ops)
		_note_stop(plan, stop_reason)
	if not spans.is_empty():
		var bridged := _price_bridges(family, spans, plan, StringName(String(options.get("choice", ""))))
		if not bridged.is_empty():
			return _fail(bridged, tiles)
	if not prompt.is_empty():
		plan["neighbor"] = prompt
		plan["needs_confirmation"] = true
		plan["choice_kind"] = &"neighbor"
	if not link.is_empty():
		plan["neighbor_link"] = link
	return plan


## Why a bridge may not land on `bank` past the end of the drag, or "".
## The same rules as the walk itself: protected land, the city limit (a
## neighbor link needs the drag to end there) and a slope across the span.
func _landing_refusal(family: int, bank: Vector2i, axis: int) -> String:
	var id := city.building_at(bank.x, bank.y)
	if _protected(bank):
		return "protected land"
	if border_edge(bank) >= 0 and NEIGHBOR_LINK_COST.has(family):
		return REASON_LIMIT
	if not _clearable(id):
		return "the far bank is blocked"
	if not city.is_flat(bank.x, bank.y) and not _slope_fits(_slope(bank), axis):
		return "the slope runs across the path"
	return ""


## A road, rail or power run meeting a highway at path step `i`: it crosses
## a straight, level highway at right angles, over both tiles of the same
## block in one go. Returns {ok, id} with the crossing id for both tiles, or
## {ok: false, reason}.
func _highway_overpass(family: int, path: Array[Dictionary], i: int) -> Dictionary:
	var step: Dictionary = path[i]
	var p: Vector2i = step["pos"]
	var id := city.building_at(p.x, p.y)
	var what: String = {NetworkShapes.Family.ROAD: "a road", NetworkShapes.Family.RAIL: "a railway",
		NetworkShapes.Family.POWER: "a power line"}.get(family, "it")
	var crossing := NetworkShapes.highway_overpass_id(family, id)
	if crossing == Buildings.NONE or not city.is_flat(p.x, p.y):
		return {"ok": false, "reason": "%s can only cross a straight, level highway" % what}
	var highway_axis := _AXIS_NS if id == NetworkShapes.HIGHWAY_NS else _AXIS_EW
	if not _crosses_at_right_angle(step, int(step["axis"]), highway_axis):
		return {"ok": false, "reason": "%s must cross the highway at right angles" % what}
	if i + 1 >= path.size():
		return {"ok": false, "reason": "%s must cross the whole highway" % what}
	var next: Dictionary = path[i + 1]
	var q: Vector2i = next["pos"]
	var direction := q - p
	if absi(direction.x) + absi(direction.y) != 1 or bool(next["turn"]) \
			or NetworkShapes.block_anchor(q) != NetworkShapes.block_anchor(p):
		return {"ok": false, "reason": "%s must cross the whole highway" % what}
	if (highway_axis == _AXIS_NS) == (direction.x == 0):
		return {"ok": false, "reason": "%s must cross the highway at right angles" % what}
	if city.building_at(q.x, q.y) != id or not city.is_flat(q.x, q.y):
		return {"ok": false, "reason": "%s can only cross a straight, level highway" % what}
	if _protected(p) or _protected(q):
		return {"ok": false, "reason": "protected land"}
	return {"ok": true, "id": crossing}


## The neighbor connection a drag ending at `to` would ask about, or empty.
func _neighbor_candidate(family: int, to: Vector2i) -> Dictionary:
	var edge := border_edge(to)
	if edge < 0 or not NEIGHBOR_LINK_COST.has(family):
		return {}
	var kind := &"road"
	match family:
		NetworkShapes.Family.RAIL: kind = &"rail"
		NetworkShapes.Family.POWER: kind = &"power"
		NetworkShapes.Family.PIPE: kind = &"water"
	var name := ""
	if sim != null:
		var neighbors := sim.get_system(&"neighbors")
		if neighbors != null and neighbors.has_method("neighbor_name"):
			name = String(neighbors.call("neighbor_name", edge))
	return {"edge": edge, "tile": to, "kind": kind, "cost": int(NEIGHBOR_LINK_COST[family]), "name": name}


func _surface_op(p: Vector2i, id: int, family: int) -> Dictionary:
	# Roads, rail and highways take the land; power lines leave the zone kind.
	var keep_zone := family == NetworkShapes.Family.POWER
	return {"op": "surface", "at": p, "id": id, "keep_zone": keep_zone}


## Survey the water from the first wet tile `p` in `direction` to the far
## bank: the span, the bank and the styles that may cross it.
func _plan_bridge(family: int, p: Vector2i, direction: Vector2i) -> Dictionary:
	var near := p - direction
	var span: Array[Vector2i] = []
	var q := p
	while city.in_bounds(q.x, q.y) and city.is_water(q.x, q.y):
		span.append(q)
		if span.size() > BRIDGE_MAX_SPAN:
			return {"ok": false, "reason": "the water is too wide to bridge"}
		q += direction
	if not city.in_bounds(q.x, q.y):
		return {"ok": false, "reason": "no far shore for a bridge"}
	if city.ground_height(q.x, q.y) != city.ground_height(near.x, near.y):
		return {"ok": false, "reason": "the banks are not level"}
	for t in span:
		var id := city.building_at(t.x, t.y)
		if id != Buildings.NONE and not NetworkShapes.in_family(id, family):
			return {"ok": false, "reason": "blocked by %s" % Buildings.display_name(id)}
	var styles: Array[StringName] = []
	for style in _BRIDGE_STYLES.get(family, []):
		if style == &"causeway" and span.size() > CAUSEWAY_MAX_SPAN:
			continue
		styles.append(style)
	var axis := NetworkShapes.AXIS_EW if direction.x != 0 else NetworkShapes.AXIS_NS
	return {"ok": true, "reason": "", "span": span, "bank": q, "styles": styles, "axis": axis}


## Price every surveyed span, offer the styles they all allow and write the
## chosen (or default) style into the plan. Returns a refusal or "".
func _price_bridges(family: int, spans: Array[Dictionary], plan: Dictionary, choice: StringName) -> String:
	var allowed: Array[StringName] = []
	for style in _BRIDGE_STYLES.get(family, []):
		var everywhere := true
		for bridge in spans:
			if not (style in bridge["styles"]):
				everywhere = false
		if everywhere:
			allowed.append(style)
	if allowed.is_empty():
		return "the water is too wide to bridge"
	var water_tiles := 0
	var choices: Array[Dictionary] = []
	for style in allowed:
		var extra := 0
		for bridge in spans:
			extra += _bridge_ops(family, bridge["span"], style, bridge["axis"])["cost"]
		choices.append({"key": style, "cost": int(plan["cost"]) + extra})
	var picked := allowed[0]
	if choice != &"":
		if not (choice in allowed):
			return "the water is too wide for a %s" % String(choice)
		picked = choice
	var tiles: Array[Vector2i] = plan["tiles"]
	var ops: Array = plan["ops"]
	for bridge in spans:
		var span: Array[Vector2i] = bridge["span"]
		water_tiles += span.size()
		var built := _bridge_ops(family, span, picked, bridge["axis"])
		for t in built["tiles"]:
			tiles.append(t)
		for op in built["ops"]:
			ops.append(op)
		plan["cost"] = int(plan["cost"]) + int(built["cost"])
	plan["tiles"] = tiles
	plan["rect"] = _bounds(tiles)
	plan["needs_confirmation"] = true
	plan["choice_kind"] = &"bridge"
	plan["choices"] = choices
	plan["choice"] = picked
	plan["span"] = water_tiles
	return ""


## The bridge pieces for one span in one style: tiles already carrying the
## network are kept and cost nothing.
func _bridge_ops(family: int, span: Array[Vector2i], style: StringName, axis: int) -> Dictionary:
	var n := span.size()
	var per_tile := int(_BRIDGE_STYLE_COST[style])
	var ids: Array[int] = []
	match style:
		&"causeway":
			for k in n:
				ids.append(87)
		&"suspension":
			for k in n:
				var id := 83
				if k == 0: id = 81
				elif k == 1: id = 82
				elif k == n - 2: id = 84
				elif k == n - 1: id = 85
				ids.append(id)
		&"rail":
			for k in n:
				ids.append(90 if k == 0 or k == n - 1 else 91)
		_:
			for k in n:
				ids.append(92)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var cost := 0
	for k in n:
		if city.building_at(span[k].x, span[k].y) != Buildings.NONE:
			continue
		tiles.append(span[k])
		ops.append({"op": "surface", "at": span[k], "id": ids[k], "keep_zone": true, "axis": axis})
		cost += per_tile
	return {"tiles": tiles, "ops": ops, "cost": cost}


# ── Pipes and subways ────────────────────────────────────────────────────

func _plan_underground(family: int, price: int, from: Vector2i, to: Vector2i, options: Dictionary = {}) -> Dictionary:
	var path := _line(from, to)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var cost := 0
	var stop_reason := ""
	var neighbor := _neighbor_candidate(family, to)
	var connect := bool(options.get("connect", false))
	var prompt: Dictionary = {}
	var link: Dictionary = {}
	for step in path:
		var p: Vector2i = step["pos"]
		var axis: int = step["axis"]
		if path.size() == 1:
			axis = _single_tile_axis(p)
		var code := city.underground.at(p.x, p.y)
		if city.is_open_water(p.x, p.y):
			stop_reason = "cannot dig under open water"
			break
		if NetworkShapes.underground_in_family(code, family):
			continue
		if _protected(p):
			stop_reason = "protected land"
			break
		var at_limit := border_edge(p) >= 0 and NEIGHBOR_LINK_COST.has(family)
		if at_limit and p != neighbor.get("tile", Vector2i(-1, -1)):
			stop_reason = REASON_LIMIT
			break
		var crossing := NetworkShapes.underground_crossing(family, code)
		if crossing != 0 and _crosses_at_right_angle(step, axis, _underground_straight_axis(code)):
			tiles.append(p)
			ops.append({"op": "underground", "at": p, "code": crossing})
			cost += price
			continue
		if code != 0:
			stop_reason = "blocked underground"
			break
		if at_limit:
			if not connect:
				prompt = neighbor
				break
			link = {"edge": int(neighbor["edge"]), "kind": neighbor["kind"]}
			tiles.append(p)
			ops.append({"op": "underground", "at": p, "code": NetworkShapes.underground_straight(family, axis)})
			cost += int(neighbor["cost"])
			continue
		tiles.append(p)
		ops.append({"op": "underground", "at": p, "code": NetworkShapes.underground_straight(family, axis)})
		cost += price
	var plan: Dictionary
	if tiles.is_empty():
		if prompt.is_empty():
			return _fail(stop_reason if not stop_reason.is_empty() else "nothing to build", [from])
		plan = _ok([], 0, [])
	else:
		plan = _ok(tiles, cost, ops)
		_note_stop(plan, stop_reason)
	if not prompt.is_empty():
		plan["neighbor"] = prompt
		plan["needs_confirmation"] = true
		plan["choice_kind"] = &"neighbor"
	if not link.is_empty():
		plan["neighbor_link"] = link
	return plan


func _plan_subway_portal(price: int, at: Vector2i) -> Dictionary:
	var site := _single_site(at)
	if not site.is_empty():
		return _fail(site, [at])
	var facing := -1
	for d in 4:
		var n := at + _DIRS[d]
		if not city.in_bounds(n.x, n.y):
			continue
		if NetworkShapes.in_rail_family(city.building_at(n.x, n.y)):
			facing = d
			break
	if facing < 0:
		for d in 4:
			var n := at + _DIRS[d]
			if city.in_bounds(n.x, n.y) and NetworkShapes.underground_in_family(city.underground.at(n.x, n.y), NetworkShapes.Family.SUBWAY):
				facing = (d + 2) % 4
				break
	if facing < 0:
		return _fail("a portal must touch a rail line or a subway", [at])
	var vertical := facing == 0 or facing == 2
	var ops: Array = [
		{"op": "surface", "at": at, "id": Buildings.SUBWAY_PORTAL_FIRST + facing, "keep_zone": false},
		{"op": "underground", "at": at, "code": NetworkShapes.underground_straight(NetworkShapes.Family.SUBWAY, _AXIS_NS if vertical else _AXIS_EW)},
	]
	return _ok([at], price, ops)


func _plan_subway_station(price: int, at: Vector2i) -> Dictionary:
	var site := _single_site(at, true)
	if not site.is_empty():
		return _fail(site, [at])
	var ops: Array = [
		{"op": "building", "at": at, "id": Buildings.SUBWAY_STATION},
		{"op": "underground", "at": at, "code": NetworkShapes.STATION_LINK},
	]
	return _ok([at], price, ops)


## Reason a single flat, dry, open tile is unusable, or empty.
func _single_site(at: Vector2i, replace_power_line: bool = false) -> String:
	if not _dry(at):
		return "cannot build on water"
	if not city.is_flat(at.x, at.y):
		return "the ground is not level"
	var id := city.building_at(at.x, at.y)
	if not (_building_clearable(id) if replace_power_line else _clearable(id)):
		return "blocked by %s" % Buildings.display_name(city.building_at(at.x, at.y))
	if city.underground.at(at.x, at.y) != 0:
		return "blocked underground"
	if _protected(at):
		return "protected land"
	return ""


# ── Highways, ramps, tunnels ─────────────────────────────────────────────

func _plan_highway(price: int, from: Vector2i, to: Vector2i) -> Dictionary:
	var start := NetworkShapes.block_anchor(from)
	var end := NetworkShapes.block_anchor(to)
	start = Vector2i(mini(start.x, City.WIDTH - 2), mini(start.y, City.HEIGHT - 2))
	end = Vector2i(mini(end.x, City.WIDTH - 2), mini(end.y, City.HEIGHT - 2))
	var path := _line(start, end, 2)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var cost := 0
	var stop_reason := ""
	for step in path:
		var anchor: Vector2i = step["pos"]
		var axis: int = step["axis"]
		var block := _plan_highway_block(anchor, axis, bool(step["turn"]))
		if not bool(block["ok"]):
			stop_reason = block["reason"]
			break
		if bool(block["existing"]):
			continue
		for t in block["tiles"]:
			tiles.append(t)
		ops.append({"op": "highway", "at": anchor, "ids": block["ids"], "axis": axis, "ground": block.get("ground", [])})
		cost += price
	if tiles.is_empty():
		return _fail(stop_reason if not stop_reason.is_empty() else "nothing to build", [start])
	return _note_stop(_ok(tiles, cost, ops), stop_reason)


func _plan_highway_block(anchor: Vector2i, axis: int, turn: bool) -> Dictionary:
	var ids: Array[int] = []
	var tiles: Array[Vector2i] = []
	var existing := 0
	var slopes: Array[int] = []
	var crossings := 0
	for dy in 2:
		for dx in 2:
			var p := anchor + Vector2i(dx, dy)
			if not city.in_bounds(p.x, p.y):
				return {"ok": false, "reason": REASON_BOUNDS}
			var id := city.building_at(p.x, p.y)
			if NetworkShapes.is_highway(id):
				existing += 1
				continue
			if not _dry(p):
				return {"ok": false, "reason": "highways cannot cross water here"}
			if _protected(p):
				return {"ok": false, "reason": "protected land"}
			var crossing := NetworkShapes.highway_crossing_id(axis, id)
			if crossing != Buildings.NONE:
				crossings += 1
				if turn or not city.is_flat(p.x, p.y):
					return {"ok": false, "reason": "a highway can only cross a straight run"}
				ids.append(crossing)
				tiles.append(p)
				continue
			if not _clearable(id):
				return {"ok": false, "reason": "blocked by %s" % Buildings.display_name(id)}
			slopes.append(_slope(p))
			ids.append(NetworkShapes.highway_id(0, axis))
			tiles.append(p)
	if existing == 4:
		return {"ok": true, "existing": true}
	if existing > 0:
		return {"ok": false, "reason": "the block overlaps another highway"}
	var slope := slopes[0] if not slopes.is_empty() else Terrain.FLAT
	var uniform := true
	for s in slopes:
		if s != slope:
			uniform = false
	if not uniform:
		if crossings > 0 or turn:
			return {"ok": false, "reason": "the ground is not level"}
		var hillside := _highway_hillside(anchor, axis)
		if not bool(hillside["ok"]):
			return hillside
		slope = int(hillside["slope"])
		for k in ids.size():
			ids[k] = NetworkShapes.highway_id(0, axis, slope)
		return {"ok": true, "existing": false, "ids": ids, "tiles": tiles, "ground": hillside["ground"]}
	if slope != Terrain.FLAT and slope != Terrain.PLATEAU:
		if crossings > 0 or turn or not _slope_fits(slope, axis):
			return {"ok": false, "reason": "the slope runs across the path"}
		for k in ids.size():
			ids[k] = NetworkShapes.highway_id(0, axis, slope)
	return {"ok": true, "existing": false, "ids": ids, "tiles": tiles}


## A highway block climbing one level along its axis: one row of two
## matching edge slopes and one level row. On the slope's raised side the
## level row is the hilltop, one level above the slope's base; on its low
## side it is the foot, at the slope's base. All four tiles take the slope
## piece. A hilltop is stored as a plateau on the slope's base height (the
## same ground, so the lattice is untouched); a foot recorded as a plateau
## one level lower becomes plain ground.
## Returns {ok, slope, ground: [[tile, terrain code, ground height], ...]}
## or {ok: false, reason}.
func _highway_hillside(anchor: Vector2i, axis: int) -> Dictionary:
	# Rows across the travel axis: [near row, far row], each of two tiles.
	var rows: Array = []
	for r in 2:
		var row: Array[Vector2i] = []
		for c in 2:
			row.append(anchor + (Vector2i(c, r) if axis == _AXIS_NS else Vector2i(r, c)))
		rows.append(row)
	for row: Array in rows:
		for t: Vector2i in row:
			if Terrain.is_edge_slope(_slope(t)) and not _slope_fits(_slope(t), axis):
				return {"ok": false, "reason": "the slope runs across the path"}
	for r in 2:
		var row: Array = rows[r]
		var other: Array = rows[1 - r]
		var a: Vector2i = row[0]
		var b: Vector2i = row[1]
		var slope := _slope(a)
		if not Terrain.is_edge_slope(slope) or _slope(b) != slope:
			continue
		var base := city.ground_height(a.x, a.y)
		if city.ground_height(b.x, b.y) != base:
			continue
		# The far row lies on the slope's raised side when the slope rises
		# toward it: north/west slopes rise toward the near row.
		var rises_far := slope == Terrain.SLOPE_S or slope == Terrain.SLOPE_E
		var level := base + 1 if rises_far == (r == 0) else base
		var ground: Array = []
		var fits := true
		for t: Vector2i in other:
			var shape := _slope(t)
			if shape != Terrain.FLAT and shape != Terrain.PLATEAU:
				fits = false
				break
			var top := city.ground_height(t.x, t.y) + (1 if shape == Terrain.PLATEAU else 0)
			if top != level:
				fits = false
				break
			var want_shape := Terrain.PLATEAU if level > base else Terrain.FLAT
			var want_height := base
			if shape != want_shape or city.ground_height(t.x, t.y) != want_height:
				ground.append([t, Terrain.make(want_shape, Terrain.DRY), want_height])
		if fits:
			return {"ok": true, "slope": slope, "ground": ground}
	return {"ok": false, "reason": "the ground is not level"}


func _plan_onramp(price: int, at: Vector2i) -> Dictionary:
	var site := _single_site(at)
	if not site.is_empty():
		return _fail(site, [at])
	var touches_highway := false
	var touches_road := false
	for d in 4:
		var n := at + _DIRS[d]
		if not city.in_bounds(n.x, n.y):
			continue
		var id := city.building_at(n.x, n.y)
		if NetworkShapes.is_highway(id):
			touches_highway = true
		elif NetworkShapes.in_road_family(id):
			touches_road = true
	if not touches_highway:
		return _fail("a ramp must touch a highway", [at])
	if not touches_road:
		return _fail("a ramp must touch a road", [at])
	var fit := _onramp_fit(at)
	if fit.is_empty():
		return _fail("place a ramp on an empty tile next to both the road and the highway, where they meet", [at])
	# The ramp piece and its axis bit name which sides carry the road and the
	# highway (NetworkShapes.onramp_endpoints), as traffic and the view read them.
	var ops: Array = [{"op": "surface", "at": at, "id": int(fit["id"]), "keep_zone": false,
		"axis": _AXIS_EW if bool(fit["axis"]) else _AXIS_NS}]
	return _ok([at], price, ops)


## The ramp piece joining a road and a highway that meet at right angles
## beside `at`: {id, axis, road, highway} with the neighbouring road and
## highway tiles, or empty when no such pair touches it.
func _onramp_fit(at: Vector2i) -> Dictionary:
	for axis: bool in [false, true]:
		for id in range(Buildings.ONRAMP_FIRST, Buildings.ONRAMP_LAST + 1):
			var ends := NetworkShapes.onramp_endpoints(id, axis)
			var road: Vector2i = at + (ends[0] as Vector2i)
			var highway: Vector2i = at + (ends[1] as Vector2i)
			if not city.in_bounds(road.x, road.y) or not city.in_bounds(highway.x, highway.y):
				continue
			var road_id := city.building_at(road.x, road.y)
			if NetworkShapes.is_highway(city.building_at(highway.x, highway.y)) \
					and NetworkShapes.in_road_family(road_id) and not NetworkShapes.is_highway(road_id) \
					and not NetworkShapes.is_onramp(road_id):
				return {"id": id, "axis": axis, "road": road, "highway": highway}
	return {}


## The road and highway tiles a ramp at `site` would join ({road, highway}),
## or empty when no ramp fits there.
func onramp_junction(site: Vector2i) -> Dictionary:
	if not city.in_bounds(site.x, site.y):
		return {}
	var fit := _onramp_fit(site)
	if fit.is_empty():
		return {}
	return {"road": fit["road"], "highway": fit["highway"]}


## Open tiles beside the `near` tiles where an on-ramp could join a road to
## the highway right where the two meet, nearest `toward` first. A site
## counts only when its road tile itself touches the highway, and a road
## tile that already has a ramp beside it is not offered another.
func onramp_sites(near: Array, toward: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not Tools.locked_reason(Tools.Kind.ONRAMP, city, stats).is_empty():
		return out
	var seen := {}
	for entry: Variant in near:
		if not entry is Vector2i:
			continue
		var tile: Vector2i = entry
		for d in 4:
			var site: Vector2i = tile + _DIRS[d]
			if seen.has(site) or not city.in_bounds(site.x, site.y):
				continue
			seen[site] = true
			if not _single_site(site).is_empty():
				continue
			var fit := _onramp_fit(site)
			if fit.is_empty():
				continue
			var road: Vector2i = fit["road"]
			var highway: Vector2i = fit["highway"]
			var beyond: Vector2i = road + (highway - site)
			if not city.in_bounds(beyond.x, beyond.y) or not NetworkShapes.is_highway(city.building_at(beyond.x, beyond.y)):
				continue
			var served := false
			for e in 4:
				var n: Vector2i = road + _DIRS[e]
				if city.in_bounds(n.x, n.y) and NetworkShapes.is_onramp(city.building_at(n.x, n.y)):
					served = true
			if not served:
				out.append(site)
	var target := toward if toward.x >= 0 else (out[0] if not out.is_empty() else Vector2i.ZERO)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - target).length_squared()
		var db := (b - target).length_squared()
		if da != db:
			return da < db
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	if out.size() > ONRAMP_OFFER_LIMIT:
		out.resize(ONRAMP_OFFER_LIMIT)
	return out


func _plan_tunnel(price: int, at: Vector2i) -> Dictionary:
	var slope := _slope(at)
	if not Terrain.is_edge_slope(slope) or not _dry(at):
		return _fail("a tunnel starts on a straight hillside", [at])
	var site := _portal_site(at)
	if not site.is_empty():
		return _fail(site, [at])
	# The hill rises toward the raised edge of the slope.
	var direction: Vector2i = _DIRS[Terrain.edge_index(slope)]
	var base := city.ground_height(at.x, at.y)
	var cells: Array[Vector2i] = [at]
	var p := at
	while true:
		if city.tunnel_bits(p.x, p.y) != 0:
			return _fail("another tunnel is in the way", cells)
		p += direction
		if not city.in_bounds(p.x, p.y):
			return _fail("the tunnel would leave the city", cells)
		cells.append(p)
		if cells.size() > TUNNEL_MAX_LENGTH:
			return _fail("the hill is too wide for a tunnel", cells)
		if city.ground_height(p.x, p.y) <= base:
			break
	var opposite := Terrain.edge_shape(Terrain.edge_index(slope) + 2)
	if _slope(p) != opposite or not _dry(p):
		return _fail("no matching hillside for the exit", cells)
	site = _portal_site(p)
	if not site.is_empty():
		return _fail(site, cells)
	var vertical := direction.y != 0
	var ops: Array = [{
		"op": "tunnel", "cells": cells,
		"entrance": at, "entrance_id": Buildings.TUNNEL_FIRST + (slope - Terrain.SLOPE_W),
		"exit": p, "exit_id": Buildings.TUNNEL_FIRST + (opposite - Terrain.SLOPE_W),
		"axis": _AXIS_NS if vertical else _AXIS_EW,
	}]
	var plan := _ok(cells, price * cells.size(), ops)
	plan["needs_confirmation"] = true
	plan["choice_kind"] = &"tunnel"
	plan["choices"] = [{"key": &"tunnel", "cost": int(plan["cost"])}] as Array[Dictionary]
	plan["choice"] = &"tunnel"
	plan["span"] = cells.size()
	return plan


func _portal_site(p: Vector2i) -> String:
	if not _clearable(city.building_at(p.x, p.y)):
		return "blocked by %s" % Buildings.display_name(city.building_at(p.x, p.y))
	if city.underground.at(p.x, p.y) != 0:
		return "blocked underground"
	if _protected(p):
		return "protected land"
	return ""


# ── Zoning ───────────────────────────────────────────────────────────────

func _zone_eligible(p: Vector2i) -> bool:
	var id := city.building_at(p.x, p.y)
	if not city.is_flat(p.x, p.y) or not _dry(p):
		return false
	if (id >= Buildings.POWER_LINE_FIRST and not NetworkShapes.is_plain_power(id)) \
			or id == Buildings.CONTAMINATION or id == Buildings.SMALL_PARK:
		return false
	return city.zone_kind_at(p.x, p.y) != Zones.MILITARY


func _plan_zone(kind: int, price: int, from: Vector2i, to: Vector2i) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var shore := false
	for p in _rect_tiles(from, to):
		if not _zone_eligible(p) or city.zone_kind_at(p.x, p.y) == kind:
			continue
		if _touches_water(p):
			shore = true
		tiles.append(p)
		ops.append({"op": "zone", "at": p, "kind": kind})
	if tiles.is_empty():
		return _fail("no tile here can be zoned", [from])
	if kind == Zones.SEAPORT and not shore:
		return _fail("a seaport needs a shoreline", tiles)
	return _ok(tiles, price * tiles.size(), ops)


func _plan_dezone(price: int, from: Vector2i, to: Vector2i) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	for p in _rect_tiles(from, to):
		var kind := city.zone_kind_at(p.x, p.y)
		if kind == Zones.NONE or kind == Zones.MILITARY:
			continue
		var id := city.building_at(p.x, p.y)
		if id >= Buildings.POWER_LINE_FIRST and not NetworkShapes.is_plain_power(id):
			continue
		tiles.append(p)
		ops.append({"op": "zone", "at": p, "kind": Zones.NONE})
	if tiles.is_empty():
		return _fail("nothing to dezone", [from])
	return _ok(tiles, price * tiles.size(), ops)


# ── Buildings ────────────────────────────────────────────────────────────

func _plan_building(tool: int, at: Vector2i) -> Dictionary:
	var id := Tools.building_id(tool)
	var size := Buildings.size(id)
	var tiles: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			tiles.append(at + Vector2i(dx, dy))
	if at.x + size.x > City.WIDTH or at.y + size.y > City.HEIGHT:
		return _fail(REASON_BOUNDS, tiles)
	var reason := ""
	match tool:
		Tools.Kind.MARINA:
			reason = _marina_site(tiles)
		Tools.Kind.HYDRO_PLANT:
			reason = _hydro_site(at)
		_:
			reason = _footprint_site(tiles)
			if reason.is_empty() and tool == Tools.Kind.DESALINATION:
				var shore := false
				for t in tiles:
					if _touches_water(t):
						shore = true
				if not shore:
					reason = "a desalination plant must touch the water"
	if not reason.is_empty():
		return _fail(reason, tiles)
	var ops: Array = [{"op": "building", "at": at, "id": id}]
	if Tools.is_reward_tool(tool):
		ops.append({"op": "reward", "key": Tools.reward_key(tool)})
	var plan := _ok(tiles, Tools.cost(tool), ops)
	if id in OPPOSITION_BUILDINGS:
		plan["opposition_exposure"] = _homes_near(at, size)
	return plan


## Residential zone tiles within OPPOSITION_RADIUS of a footprint.
func _homes_near(at: Vector2i, size: Vector2i) -> int:
	var count := 0
	for y in range(maxi(0, at.y - OPPOSITION_RADIUS), mini(City.HEIGHT, at.y + size.y + OPPOSITION_RADIUS)):
		for x in range(maxi(0, at.x - OPPOSITION_RADIUS), mini(City.WIDTH, at.x + size.x + OPPOSITION_RADIUS)):
			if Zones.is_residential(city.zone_kind_at(x, y)):
				count += 1
	return count


func _footprint_site(tiles: Array[Vector2i]) -> String:
	var height := city.ground_height(tiles[0].x, tiles[0].y)
	for t in tiles:
		if not _dry(t):
			return "cannot build on water"
		if not city.is_flat(t.x, t.y) or city.ground_height(t.x, t.y) != height:
			return "the ground is not level"
		var id := city.building_at(t.x, t.y)
		if not _building_clearable(id):
			return "blocked by %s" % Buildings.display_name(id)
		if _protected(t):
			return "protected land"
	return ""


func _marina_site(tiles: Array[Vector2i]) -> String:
	var land := 0
	var water := 0
	for t in tiles:
		var id := city.building_at(t.x, t.y)
		if not _building_clearable(id):
			return "blocked by %s" % Buildings.display_name(id)
		if _protected(t):
			return "protected land"
		if _dry(t):
			land += 1
		else:
			water += 1
	if land == 0 or water == 0:
		return "a marina needs both shore and water"
	return ""


func _hydro_site(at: Vector2i) -> String:
	if Terrain.water_kind(city.terrain.at(at.x, at.y)) != Terrain.WATERFALL:
		return "a dam needs a waterfall"
	var id := city.building_at(at.x, at.y)
	if id != Buildings.NONE and not NetworkShapes.is_plain_power(id):
		return "blocked by %s" % Buildings.display_name(city.building_at(at.x, at.y))
	return ""


# ── Bulldozer ────────────────────────────────────────────────────────────

func _plan_bulldoze(price: int, from: Vector2i, to: Vector2i) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var seen := {}
	var cost := 0
	var refused := ""
	var trees := 0
	var buried := {}
	for step in _line(from, to):
		var p: Vector2i = step["pos"]
		if seen.has(p):
			continue
		if _protected(p):
			refused = "protected land"
			continue
		var id := city.building_at(p.x, p.y)
		if Buildings.is_tree(id):
			trees += 1
		if id == Buildings.NONE:
			var code := city.underground.at(p.x, p.y)
			if code != 0:
				if NetworkShapes.underground_in_family(code, NetworkShapes.Family.PIPE):
					buried["water pipe"] = true
				if NetworkShapes.underground_in_family(code, NetworkShapes.Family.SUBWAY):
					buried["subway track"] = true
				seen[p] = true
				tiles.append(p)
				ops.append({"op": "underground", "at": p, "code": 0})
				cost += price
			continue
		var footprint: Array[Vector2i] = []
		var rubble := Buildings.is_developed(id)
		if NetworkShapes.is_tunnel(id):
			footprint = _tunnel_bore(p, id)
			ops.append({"op": "tunnel_clear", "cells": footprint})
		elif NetworkShapes.is_highway(id):
			var a := NetworkShapes.block_anchor(p)
			for dy in 2:
				for dx in 2:
					if NetworkShapes.is_highway(city.building_at(a.x + dx, a.y + dy)):
						footprint.append(a + Vector2i(dx, dy))
			ops.append({"op": "remove", "tiles": footprint, "rubble": false})
		else:
			var anchor := city.anchor_of(p.x, p.y)
			var size := Buildings.size(id)
			for dy in size.y:
				for dx in size.x:
					footprint.append(anchor + Vector2i(dx, dy))
			ops.append({"op": "remove", "tiles": footprint, "rubble": rubble})
		for t in footprint:
			seen[t] = true
			tiles.append(t)
		cost += price * footprint.size()
	if tiles.is_empty():
		return _fail(refused if not refused.is_empty() else "nothing to clear", [from])
	var plan := _ok(tiles, cost, ops)
	plan["trees_cleared"] = trees
	if not buried.is_empty():
		# What bare-ground bulldozing takes from underground, for the caption.
		var kinds: Array[String] = []
		for kind in ["water pipe", "subway track"]:
			if buried.has(kind): kinds.append(kind)
		plan["clears_underground"] = kinds
	return plan


## Every tile of the bore a portal belongs to, following the tunnel bits.
func _tunnel_bore(portal: Vector2i, id: int) -> Array[Vector2i]:
	# Portal ids follow the slope codes: the bore runs toward the raised side.
	var facing := Terrain.edge_index(Terrain.SLOPE_W + (id - Buildings.TUNNEL_FIRST))
	var direction: Vector2i = _DIRS[facing]
	var cells: Array[Vector2i] = [portal]
	var p := portal + direction
	while city.in_bounds(p.x, p.y) and cells.size() <= TUNNEL_MAX_LENGTH:
		cells.append(p)
		if NetworkShapes.is_tunnel(city.building_at(p.x, p.y)):
			break
		if city.tunnel_bits(p.x, p.y) == 0:
			break
		p += direction
	return cells


# ── Trees and terrain ────────────────────────────────────────────────────

func _plan_trees(price: int, drag: Array[Vector2i]) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	for p in drag:
		if not _dry(p) or city.building_at(p.x, p.y) != Buildings.NONE or _protected(p):
			continue
		tiles.append(p)
		ops.append({"op": "trees", "at": p})
	if tiles.is_empty():
		return _fail("no open ground for trees", [drag[0]])
	return _ok(tiles, price * tiles.size(), ops)


## One tree on open ground, or one step denser on a tile already wooded.
func _plan_tree(price: int, at: Vector2i) -> Dictionary:
	if not _dry(at) or _protected(at):
		return _fail("no open ground for a tree", [at])
	var id := city.building_at(at.x, at.y)
	if id == Buildings.TREES_7:
		return _fail("the trees here are as dense as they grow", [at])
	if id != Buildings.NONE and not Buildings.is_tree(id):
		return _fail("no open ground for a tree", [at])
	var next := Buildings.TREES_1 if id == Buildings.NONE else id + 1
	return _ok([at], price, [{"op": "tree", "at": at, "id": next}])


func _terrain_editable(p: Vector2i) -> String:
	if not _dry(p):
		return "use the water tools on water"
	if city.building_at(p.x, p.y) > Buildings.TREES_7:
		return "clear the land first"
	if _protected(p):
		return "protected land"
	return ""


## The city's shared-vertex ground lattice, or null for a city kept as
## imported per-tile terrain. With a lattice the land tools edit it
## through TerrainEditor, so the 3D ground and saves follow every change.
func _lattice() -> TerrainSurface:
	return city.terrain_surface as TerrainSurface if city.terrain_surface is TerrainSurface else null


## A scratch copy of the layers the terrain tools read and write, so a plan
## can try an edit (and its ripple) without touching the city.
func _terrain_scratch() -> City:
	var c := City.new()
	c.terrain = city.terrain.duplicate_grid()
	c.altitude = city.altitude.duplicate_grid()
	c.building = city.building.duplicate_grid()
	c.zone = city.zone.duplicate_grid()
	c.flags = city.flags.duplicate_grid()
	c.sea_level = city.sea_level
	var lattice := _lattice()
	if lattice != null:
		c.terrain_surface = lattice.duplicate_surface()
	return c


## Why moving the ground of `t` (or only reshaping it when `moved` is false)
## would damage something, or "". Only open ground and trees may change.
func _ground_blocker(t: Vector2i, moved: bool) -> String:
	var id := city.building_at(t.x, t.y)
	if id != Buildings.NONE and not Buildings.is_tree(id):
		return "land under %s would move" % Buildings.display_name(id)
	if _protected(t):
		return "protected land would move"
	if moved and city.tunnel_bits(t.x, t.y) != 0:
		return "a tunnel runs under this land"
	return ""


## Try one per-tile height change on `scratch` and return why its 3×3 reshape
## or its cascade would disturb something, or "". The scratch keeps the
## change either way; callers restore it on refusal.
func _reshape_blocked(scratch: City, at: Vector2i, height: int) -> String:
	var before := scratch.altitude.data.duplicate()
	for t in set_ground_height(scratch, at.x, at.y, height):
		var i := t.y * City.WIDTH + t.x
		var moved := (before[i] & City.ALT_MASK) != scratch.ground_height(t.x, t.y)
		if moved and t != at and city.is_water(t.x, t.y):
			return "the shoreline would move"
		var reason := _ground_blocker(t, moved)
		if not reason.is_empty():
			return reason
	return ""


func _plan_raise_lower(at: Vector2i, delta: int) -> Dictionary:
	var reason := _terrain_editable(at)
	if not reason.is_empty():
		return _fail(reason, [at])
	if _lattice() != null:
		return _plan_lattice_land(Tools.Kind.RAISE_LAND if delta > 0 else Tools.Kind.LOWER_LAND, at, at)
	var h := city.ground_height(at.x, at.y)
	if delta > 0 and h >= MAX_GROUND_HEIGHT:
		return _fail("the land is as high as it goes", [at])
	if delta < 0 and h <= 0:
		return _fail("the land is as low as it goes", [at])
	var blocked := _reshape_blocked(_terrain_scratch(), at, h + delta)
	if not blocked.is_empty():
		return _fail(blocked, [at])
	return _ok([at], TERRAIN_STEP_COST, [{"op": "height", "at": at, "height": h + delta}])


func _plan_level(from: Vector2i, to: Vector2i) -> Dictionary:
	if _lattice() != null:
		return _plan_lattice_land(Tools.Kind.LEVEL_LAND, from, to)
	var target := city.ground_height(from.x, from.y)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var refused := ""
	# Tiles are tried in drag order on a scratch copy, each after the ones
	# before it, exactly as `apply` will run them.
	var scratch := _terrain_scratch()
	for p in _area_tiles(from, to):
		if not _terrain_editable(p).is_empty():
			continue
		if scratch.ground_height(p.x, p.y) == target and scratch.is_flat(p.x, p.y):
			continue
		var altitude := scratch.altitude.data.duplicate()
		var terrain := scratch.terrain.data.duplicate()
		var blocked := _reshape_blocked(scratch, p, target)
		if not blocked.is_empty():
			scratch.altitude.data = altitude
			scratch.terrain.data = terrain
			if refused.is_empty():
				refused = blocked
			continue
		tiles.append(p)
		ops.append({"op": "height", "at": p, "height": target})
	if tiles.is_empty():
		return _fail(refused if not refused.is_empty() else "the land is already level", [from])
	return _ok(tiles, TERRAIN_STEP_COST * tiles.size(), ops)


## Raise, lower or level land on a city with a ground lattice: each tile is
## tried through TerrainEditor on a scratch copy in drag order, so the price
## and the tiles match what `apply` then does to the city.
func _plan_lattice_land(kind: int, from: Vector2i, to: Vector2i) -> Dictionary:
	var scratch := _terrain_scratch()
	var editor := TerrainEditor.new(scratch)
	var target := city.ground_height(from.x, from.y)
	var tiles: Array[Vector2i] = []
	var ops: Array = []
	var refused := ""
	for p in _area_tiles(from, to):
		var reason := _terrain_editable(p)
		if reason.is_empty() and scratch.is_water(p.x, p.y):
			reason = "use the water tools on water"
		if not reason.is_empty():
			if refused.is_empty():
				refused = reason
			continue
		if kind == Tools.Kind.LEVEL_LAND and scratch.is_flat(p.x, p.y) and scratch.ground_height(p.x, p.y) == target:
			continue
		var surface := (scratch.terrain_surface as TerrainSurface).duplicate_surface()
		var layers := [scratch.terrain.data.duplicate(), scratch.altitude.data.duplicate(),
			scratch.building.data.duplicate(), scratch.flags.data.duplicate()]
		var r := _lattice_land_step(editor, kind, p, target)
		if bool(r["ok"]):
			reason = _lattice_blocker(scratch, r["rect"], layers)
		else:
			reason = _editor_reason(String(r["reason"]))
		if not reason.is_empty():
			(scratch.terrain_surface as TerrainSurface).copy_from(surface)
			scratch.terrain.data = layers[0]
			scratch.altitude.data = layers[1]
			scratch.building.data = layers[2]
			scratch.flags.data = layers[3]
			if refused.is_empty():
				refused = reason
			continue
		tiles.append(p)
		ops.append({"op": "lattice_land", "kind": kind, "at": p, "height": target})
	if tiles.is_empty():
		return _fail(refused if not refused.is_empty() else "the land is already level", [from])
	return _ok(tiles, TERRAIN_STEP_COST * tiles.size(), ops)


static func _lattice_land_step(editor: TerrainEditor, kind: int, p: Vector2i, target: int) -> Dictionary:
	match kind:
		Tools.Kind.RAISE_LAND:
			return editor.raise(p.x, p.y)
		Tools.Kind.LOWER_LAND:
			return editor.lower(p.x, p.y)
	return editor.level(p.x, p.y, target)


## TerrainEditor already refuses built tiles in the reshaped area; refuse
## protected land there too, and ground moving over a tunnel bore. `layers`
## holds the scratch terrain and altitude before the step.
func _lattice_blocker(scratch: City, rect: Rect2i, layers: Array) -> String:
	var terrain: PackedByteArray = layers[0]
	var altitude: PackedInt32Array = layers[1]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * City.WIDTH + x
			var moved := (altitude[i] & City.ALT_MASK) != scratch.ground_height(x, y)
			if not moved and terrain[i] == scratch.terrain.at(x, y):
				continue
			if _protected(Vector2i(x, y)):
				return "protected land would move"
			if moved and city.tunnel_bits(x, y) != 0:
				return "a tunnel runs under this land"
	return ""


## TerrainEditor writes sentences; plans carry lower-case phrases.
static func _editor_reason(text: String) -> String:
	var t := text.strip_edges().trim_suffix(".")
	return t if t.is_empty() else t[0].to_lower() + t.substr(1)


func _plan_water(price: int, at: Vector2i) -> Dictionary:
	if not _dry(at):
		return _fail("already water", [at])
	if city.building_at(at.x, at.y) != Buildings.NONE or _protected(at):
		return _fail("clear the land first", [at])
	if not city.is_flat(at.x, at.y):
		return _fail("the ground is not level", [at])
	var lattice := _lattice()
	if lattice != null:
		if lattice.tile_base(at.x, at.y) >= TerrainSurface.MAX_HEIGHT:
			return _fail("too high for water", [at])
		return _ok([at], price, [{"op": "lattice_water", "at": at}])
	return _ok([at], price, [{"op": "water", "at": at}])


# ── Dispatch ─────────────────────────────────────────────────────────────

## Why a crew of `kind` cannot be sent now, or "" when it can. The toolbar
## locks its dispatch buttons with the same reasons. A Builder without a
## disaster system (a bare test fixture) does not check.
func dispatch_refusal(kind: StringName) -> String:
	var disasters: Object = sim.get_system(&"disasters") if sim != null else null
	if disasters == null or not disasters.has_method("is_emergency"):
		return ""
	if not bool(disasters.call("is_emergency")):
		return REASON_NO_EMERGENCY
	if disasters.has_method("crews_available") and int(disasters.call("crews_available", kind)) <= 0:
		return REASON_NO_CREWS
	return ""


func _plan_dispatch(kind: StringName, at: Vector2i) -> Dictionary:
	var refusal := dispatch_refusal(kind)
	if not refusal.is_empty():
		return _fail(refusal, [at])
	if not _dry(at):
		return _fail("cannot send crews onto water", [at])
	return _ok([at], 0, [{"op": "dispatch", "kind": kind, "at": at}])


# ── Commit ───────────────────────────────────────────────────────────────

## Execute the plan's operations. Returns every tile whose layers changed.
func _commit(ops: Array) -> Array[Vector2i]:
	var touched: Array[Vector2i] = []
	var blocks: Array = []
	for op in ops:
		var kind: String = op["op"]
		match kind:
			"surface":
				var p: Vector2i = op["at"]
				_write_surface(p, int(op["id"]), bool(op["keep_zone"]), int(op.get("axis", NetworkShapes.AXIS_ANY)))
				touched.append(p)
			"underground":
				var p: Vector2i = op["at"]
				var code := int(op["code"])
				city.underground.put(p.x, p.y, code)
				city.set_flag(p.x, p.y, TileFlags.CONDUCTS_WATER, NetworkShapes.underground_in_family(code, NetworkShapes.Family.PIPE) or Buildings.category(city.building_at(p.x, p.y)) == Buildings.Category.UTILITY)
				touched.append(p)
			"highway":
				var anchor: Vector2i = op["at"]
				var ids: Array = op["ids"]
				for g: Array in op.get("ground", []):
					var at: Vector2i = g[0]
					city.terrain.put(at.x, at.y, int(g[1]))
					city.set_heights(at.x, at.y, int(g[2]))
				var k := 0
				for dy in 2:
					for dx in 2:
						var p := anchor + Vector2i(dx, dy)
						_write_surface(p, int(ids[k]), false)
						touched.append(p)
						k += 1
				if int(ids[0]) >= NetworkShapes.HIGHWAY_SLOPE_W and int(ids[0]) <= NetworkShapes.HIGHWAY_SLOPE_S:
					_mark_highway_lot(anchor)
				blocks.append([anchor, int(op["axis"])])
			"building":
				var p: Vector2i = op["at"]
				var id := int(op["id"])
				_place_building(p, id)
				var size := Buildings.size(id)
				for dy in size.y:
					for dx in size.x:
						touched.append(p + Vector2i(dx, dy))
			"zone":
				var p: Vector2i = op["at"]
				var zk := int(op["kind"])
				if zk == Zones.NONE and Buildings.is_rubble(city.building_at(p.x, p.y)):
					city.building.put(p.x, p.y, Buildings.NONE)
				city.zone.put(p.x, p.y, Zones.make(zk, Zones.ALL_CORNERS if zk != Zones.NONE else 0))
				touched.append(p)
			"remove":
				var rubble := bool(op["rubble"])
				for t in op["tiles"]:
					var p: Vector2i = t
					_clear_tile(p, rubble)
					touched.append(p)
			"tunnel":
				var cells: Array[Vector2i] = op["cells"]
				var axis := int(op["axis"])
				for c in cells:
					city.set_tunnel_bits(c.x, c.y, axis)
				var entrance: Vector2i = op["entrance"]
				var exit: Vector2i = op["exit"]
				_write_surface(entrance, int(op["entrance_id"]), false)
				_write_surface(exit, int(op["exit_id"]), false)
				touched.append(entrance)
				touched.append(exit)
			"tunnel_clear":
				var cells: Array[Vector2i] = op["cells"]
				for c in cells:
					city.set_tunnel_bits(c.x, c.y, 0)
					if NetworkShapes.is_tunnel(city.building_at(c.x, c.y)):
						_clear_tile(c, false)
						touched.append(c)
			"trees":
				var p: Vector2i = op["at"]
				city.building.put(p.x, p.y, Buildings.TREES_1 + mini(6, _tree_neighbours(p)))
				touched.append(p)
			"tree":
				var p: Vector2i = op["at"]
				city.building.put(p.x, p.y, int(op["id"]))
				touched.append(p)
			"height":
				var p: Vector2i = op["at"]
				for t in set_ground_height(city, p.x, p.y, int(op["height"])):
					touched.append(t)
			"water":
				var p: Vector2i = op["at"]
				city.terrain.put(p.x, p.y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
				city.set_heights(p.x, p.y, city.ground_height(p.x, p.y), city.ground_height(p.x, p.y))
				city.zone.put(p.x, p.y, 0)
				touched.append(p)
			"lattice_land", "lattice_water":
				for t in _commit_lattice(op):
					touched.append(t)
			"reward":
				stats.rewards_built[op["key"]] = true
			"dispatch":
				_dispatch(op["kind"], op["at"])
	for t in touched:
		NetworkShapes.reshape(city, t.x, t.y)
	for b in blocks:
		var anchor: Vector2i = b[0]
		NetworkShapes.reshape_highway_block(city, anchor.x, anchor.y, int(b[1]))
	return touched


## Run one lattice terrain operation on the city through TerrainEditor, the
## same call the plan tried on its scratch copy. Returns the tiles whose
## terrain, height or trees changed; ground that became water loses its zone.
func _commit_lattice(op: Dictionary) -> Array[Vector2i]:
	var editor := TerrainEditor.new(city)
	var terrain := city.terrain.data.duplicate()
	var altitude := city.altitude.data.duplicate()
	var buildings := city.building.data.duplicate()
	var r: Dictionary
	match String(op["op"]):
		"lattice_land":
			r = _lattice_land_step(editor, int(op["kind"]), op["at"], int(op["height"]))
		_:
			var at: Vector2i = op["at"]
			r = editor.place_water(at.x, at.y, false)
	var out: Array[Vector2i] = []
	if not bool(r["ok"]):
		return out
	var rect := TerrainSurface.clamp_rect(r["rect"])
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * City.WIDTH + x
			var code := city.terrain.data[i]
			if code == terrain[i] and city.altitude.data[i] == altitude[i] and city.building.data[i] == buildings[i]:
				continue
			if Terrain.is_water(code) and not Terrain.is_water(terrain[i]):
				city.zone.data[i] = 0
			out.append(Vector2i(x, y))
	return out


func _write_surface(p: Vector2i, id: int, keep_zone: bool, axis: int = NetworkShapes.AXIS_ANY) -> void:
	city.building.put(p.x, p.y, id)
	if not keep_zone:
		city.zone.put(p.x, p.y, 0)
	city.set_flag(p.x, p.y, TileFlags.CONDUCTS_POWER, Buildings.carries_power(id))
	if axis != NetworkShapes.AXIS_ANY:
		# Bridges share a tile ID between axes; the stored axis bit orients the span.
		city.set_flag(p.x, p.y, TileFlags.RESERVED_A, axis == NetworkShapes.AXIS_EW)


## A sloped highway block is one 2×2 picture. Each tile gets one corner
## flag, cycling north-west, north-east, south-east, south-west in the city's
## saved view, so the map draws the block once as a lot.
func _mark_highway_lot(anchor: Vector2i) -> void:
	const RING := [Zones.CORNER_NW, Zones.CORNER_NE, Zones.CORNER_SE, Zones.CORNER_SW]
	const CELLS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for c in 4:
		var p: Vector2i = anchor + CELLS[c]
		city.zone.put(p.x, p.y, Zones.make(Zones.NONE, RING[(c + posmod(city.rotation, 4)) % 4]))


func _place_building(at: Vector2i, id: int) -> void:
	var size := Buildings.size(id)
	for dy in size.y:
		for dx in size.x:
			var p := at + Vector2i(dx, dy)
			city.facilities.erase(city.anchor_of(p.x, p.y))
	city.stamp_building(at.x, at.y, id, Zones.NONE)
	var category := Buildings.category(id)
	for dy in size.y:
		for dx in size.x:
			var p := at + Vector2i(dx, dy)
			city.set_flag(p.x, p.y, TileFlags.CONDUCTS_POWER, Buildings.carries_power(id))
			if category == Buildings.Category.UTILITY:
				city.set_flag(p.x, p.y, TileFlags.CONDUCTS_WATER, true)
	if category in [Buildings.Category.PLANT, Buildings.Category.CIVIC, Buildings.Category.UTILITY,
			Buildings.Category.TRANSIT, Buildings.Category.REWARD, Buildings.Category.ARCOLOGY]:
		city.add_facility(at, {"key": Buildings.key(id), "built_day": city.day})


func _clear_tile(p: Vector2i, rubble: bool) -> void:
	city.facilities.erase(city.anchor_of(p.x, p.y))
	var zk := city.zone_kind_at(p.x, p.y)
	city.building.put(p.x, p.y, Buildings.RUBBLE_1 + _rubble_variant(p) if rubble else Buildings.NONE)
	city.zone.put(p.x, p.y, Zones.make(zk, Zones.ALL_CORNERS if zk != Zones.NONE else 0))
	var pipe := NetworkShapes.underground_in_family(city.underground.at(p.x, p.y), NetworkShapes.Family.PIPE)
	city.set_flag(p.x, p.y, TileFlags.CONDUCTS_POWER | TileFlags.POWERED | TileFlags.WATERED, false)
	city.set_flag(p.x, p.y, TileFlags.CONDUCTS_WATER, pipe)
	if city.underground.at(p.x, p.y) == NetworkShapes.STATION_LINK:
		city.underground.put(p.x, p.y, 0)


func _rubble_variant(p: Vector2i) -> int:
	if sim != null and sim.rng != null:
		return sim.rng.below(4)
	return (p.x * 3 + p.y * 5) % 4


func _tree_neighbours(p: Vector2i) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and Buildings.is_tree(city.building_at(p.x + dx, p.y + dy)):
				n += 1
	return n


func _dispatch(kind: StringName, at: Vector2i) -> void:
	if sim == null:
		return
	var system := sim.get_system(&"disasters")
	if system != null and system.has_method("dispatch"):
		system.call("dispatch", kind, at)


# ── Terrain helpers ──────────────────────────────────────────────────────

## Set one tile's ground height and pull its surroundings along so no two
## adjacent tiles differ by more than one level. Slope shapes of every
## touched tile are recomputed. Returns the tiles whose heights or shapes
## changed.
static func set_ground_height(target: City, x: int, y: int, height: int) -> Array[Vector2i]:
	height = clampi(height, 0, MAX_GROUND_HEIGHT)
	var changed := {}
	var queue: Array[Vector2i] = [Vector2i(x, y)]
	target.set_heights(x, y, height)
	changed[Vector2i(x, y)] = true
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		var h := target.ground_height(p.x, p.y)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := p + Vector2i(dx, dy)
				if not target.in_bounds(n.x, n.y):
					continue
				var hn := target.ground_height(n.x, n.y)
				var want := hn
				if hn < h - 1:
					want = h - 1
				elif hn > h + 1:
					want = h + 1
				if want != hn:
					target.set_heights(n.x, n.y, want)
					changed[n] = true
					queue.append(n)
	var affected := {}
	for p in changed:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = p + Vector2i(dx, dy)
				if target.in_bounds(n.x, n.y):
					affected[n] = true
	var out: Array[Vector2i] = []
	for p in affected:
		refresh_shape(target, p.x, p.y)
		out.append(p)
	return out


## Recompute a dry tile's slope shape from the heights around it: a corner is
## raised when any neighbour touching that corner stands higher.
static func refresh_shape(target: City, x: int, y: int) -> void:
	var code := target.terrain.at(x, y)
	if Terrain.is_water(code):
		return
	var h := target.ground_height(x, y)
	var mask := 0
	if _higher(target, x, y - 1, h) or _higher(target, x + 1, y - 1, h) or _higher(target, x + 1, y, h):
		mask |= 1
	if _higher(target, x + 1, y, h) or _higher(target, x + 1, y + 1, h) or _higher(target, x, y + 1, h):
		mask |= 2
	if _higher(target, x, y + 1, h) or _higher(target, x - 1, y + 1, h) or _higher(target, x - 1, y, h):
		mask |= 4
	if _higher(target, x - 1, y, h) or _higher(target, x - 1, y - 1, h) or _higher(target, x, y - 1, h):
		mask |= 8
	var shape := Terrain.shape_from_corners(mask)
	if shape < 0 or shape == Terrain.PLATEAU:
		shape = Terrain.FLAT
	target.terrain.put(x, y, Terrain.make(shape, Terrain.DRY))


static func _higher(target: City, x: int, y: int, h: int) -> bool:
	return target.in_bounds(x, y) and target.ground_height(x, y) > h
