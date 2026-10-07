# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var _contexts: Array[SimContext] = []


func after_each() -> void:
	# Hand-built fixtures own the context table without a Simulation Node.
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()

## Behavior tests for the port system: airport and seaport development,
## operating rules, demand and jobs, vehicles and persistence. The system is
## driven directly through a hand-built context.

const PortSystem := preload("res://scripts/sim/port_system.gd")

var _news: Array[Dictionary] = []


func before_each() -> void:
	_news.clear()


func _context(c: City, seed_value: int = 11) -> SimContext:
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


func _make_ports(ctx: SimContext) -> PortSystem:
	var ports: PortSystem = PortSystem.new()
	ports.setup(ctx)
	ctx.systems[ports.key] = ports
	return ports


## One day as the simulation schedules it; returns the vehicles seen afterwards.
func _run_day(ctx: SimContext, ports: PortSystem) -> void:
	ctx.events.clear()
	ports.daily(ctx)
	if ctx.clock.day_of_month() == GameClock.DAYS_PER_MONTH:
		ports.monthly(ctx, 0)
	if ctx.clock.is_year_end():
		ports.yearly(ctx)
	for n in ctx.events.news:
		_news.append(n)
	ctx.clock.advance()
	ctx.city.day = ctx.clock.day


func _run_days(ctx: SimContext, ports: PortSystem, days: int) -> void:
	for _i in days:
		_run_day(ctx, ports)


func _zone_rect(c: City, rect: Rect2i, kind: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.zone.put(x, y, Zones.make(kind))


func _power_rect(c: City, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.set_flag(x, y, TileFlags.POWERED, true)


## Open water of navigable depth over a rectangle.
func _flood_rect(c: City, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			c.set_heights(x, y, 2, 4)


func _count_in(c: City, rect: Rect2i, id: int) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if c.building_at(x, y) == id:
				n += 1
	return n


func _count_kind(vehicles: Array[Dictionary], kind: StringName) -> int:
	var n := 0
	for v in vehicles:
		if v.kind == kind:
			n += 1
	return n


func _airport_city() -> Array:
	var c := flat_city()
	var ctx := _context(c)
	var rect := Rect2i(20, 20, 12, 12)
	_zone_rect(c, rect, Zones.AIRPORT)
	_power_rect(c, rect)
	return [c, ctx, rect]


## A seaport zone on a west shore; the sea reaches the east map edge.
func _harbour_city() -> Array:
	var c := flat_city()
	_flood_rect(c, Rect2i(40, 0, City.WIDTH - 40, City.HEIGHT))
	var ctx := _context(c)
	var rect := Rect2i(34, 20, 6, 8)
	_zone_rect(c, rect, Zones.SEAPORT)
	_power_rect(c, rect)
	return [c, ctx, rect]


# ── Airports ─────────────────────────────────────────────────────────────

func test_airport_zone_develops_runways_and_spawns_a_plane() -> void:
	var parts := _airport_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var rect: Rect2i = parts[2]
	var ports := _make_ports(ctx)
	var report := ports.port_report()
	check_eq(report.size(), 1)
	check_eq(report[0].kind, Zones.AIRPORT)
	check_eq(report[0].tiles, 144)
	check(not report[0].operating, "nothing built yet")
	check_eq(ports.demand_bonus(), Vector3i.ZERO)
	_run_days(ctx, ports, 12 * GameClock.DAYS_PER_MONTH)
	var runway := _count_in(c, rect, Buildings.RUNWAY) + _count_in(c, rect, Buildings.RUNWAY_CROSS)
	check_ge(runway, PortParams.RUNWAY_LENGTH, "at least one runway is laid")
	check_eq(runway % PortParams.RUNWAY_LENGTH, 0, "runways come in whole lengths")
	report = ports.port_report()
	check(report[0].operating, "a powered airport with a runway operates")
	check_gt(int(report[0].developed), runway, "support buildings appear too")
	check_gt(ports.demand_bonus().y, 0, "commercial demand rises")
	check_eq(ports.demand_bonus().x, 0)
	check_eq(ports.demand_bonus().z, 0)
	check_gt(ports.jobs(), 0)
	check_gt(int(report[0].pollution), 0)
	var opened := false
	for story in _news:
		if story.kind == &"port_opened" and story.args.kind == Zones.AIRPORT:
			opened = true
	check(opened, "the opening makes the news")
	var seen_plane := false
	var seen_helicopter := false
	for _i in 12 * GameClock.DAYS_PER_MONTH:
		_run_day(ctx, ports)
		for v in ports.vehicles():
			check(c.in_bounds(int(v.x), int(v.y)), "vehicles stay on the map")
			check_between(int(v.heading), 0, 7)
			if v.kind == &"plane":
				seen_plane = true
			elif v.kind == &"helicopter":
				seen_helicopter = true
		check_le_planes(ports.vehicles())
	check(seen_plane, "an operating airport sends out planes")
	check(seen_helicopter, "and a helicopter")
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			check_eq(c.zone_kind_at(x, y), Zones.AIRPORT, "development keeps the zone")


func check_le_planes(vehicles: Array[Dictionary]) -> void:
	check(_count_kind(vehicles, &"plane") <= PortParams.MAX_PLANES, "plane count is capped")
	check(_count_kind(vehicles, &"helicopter") <= 1, "one helicopter at most")


func test_unpowered_airport_stays_empty() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rect := Rect2i(20, 20, 12, 12)
	_zone_rect(c, rect, Zones.AIRPORT)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 12 * GameClock.DAYS_PER_MONTH)
	check_eq(int(ports.port_report()[0].developed), 0, "no power, no construction")
	check_eq(ports.vehicles().size(), 0)
	check_eq(ports.jobs(), 0)


func test_small_airport_does_not_operate() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rect := Rect2i(20, 20, 6, 2)
	_zone_rect(c, rect, Zones.AIRPORT)
	_power_rect(c, rect)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	var report := ports.port_report()
	check_gt(int(report[0].developed), 0, "a strip still develops")
	check(not report[0].operating, "but is too small to operate")
	check_eq(ports.vehicles().size(), 0)


func test_plane_leaves_when_airport_loses_power() -> void:
	var parts := _airport_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var rect: Rect2i = parts[2]
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check(ports.port_report()[0].operating)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.set_flag(x, y, TileFlags.POWERED, false)
	ports.networks_changed(ctx, rect)
	check(not ports.port_report()[0].operating)
	check_eq(ports.demand_bonus(), Vector3i.ZERO)
	_run_days(ctx, ports, 3 * GameClock.DAYS_PER_MONTH)
	check_eq(_count_kind(ports.vehicles(), &"helicopter"), 0, "the helicopter lands for good")
	var closed := false
	for story in _news:
		if story.kind == &"port_closed":
			closed = true
	check(closed)


func test_cruising_plane_leaves_without_an_airport() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var ports := _make_ports(ctx)
	ports.load({"vehicles": [{
		"kind": "plane", "x": 60, "y": 60, "heading": 2, "frame": 0,
		"altitude": PortParams.PLANE_CRUISE_ALTITUDE, "phase": "cruise",
		"days": PortParams.PLANE_CRUISE_DAYS, "target": [60, 60], "port": [20, 20],
	}]})
	check_eq(_count_kind(ports.vehicles(), &"plane"), 1)
	_run_days(ctx, ports, 2)
	check_eq(_count_kind(ports.vehicles(), &"plane"), 0, "no runway to return to, so the plane leaves")


func _openings() -> int:
	var n := 0
	for story in _news:
		if story.kind == &"port_opened":
			n += 1
	return n


func test_growing_port_is_not_reopened() -> void:
	var parts := _airport_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check(ports.port_report()[0].operating)
	check_eq(_openings(), 1)
	# Zoning a row to the north and a column to the west moves the first tile.
	var grown := Rect2i(19, 19, 13, 13)
	_zone_rect(c, Rect2i(19, 19, 13, 1), Zones.AIRPORT)
	_zone_rect(c, Rect2i(19, 19, 1, 13), Zones.AIRPORT)
	_power_rect(c, grown)
	ports.networks_changed(ctx, grown)
	_run_days(ctx, ports, 2 * GameClock.DAYS_PER_MONTH)
	check(ports.port_report()[0].operating)
	check_eq(_openings(), 1, "an expanded port is the same port")
	# The identity survives a save and load.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(ports.save()))
	var restored := _make_ports(ctx)
	restored.load(parsed)
	_run_days(ctx, restored, 2 * GameClock.DAYS_PER_MONTH)
	check_eq(_openings(), 1, "a loaded port is not reopened")

# ── Seaports ─────────────────────────────────────────────────────────────

func test_seaport_needs_shoreline() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rect := Rect2i(20, 20, 6, 8)
	_zone_rect(c, rect, Zones.SEAPORT)
	_power_rect(c, rect)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check_eq(_count_in(c, rect, Buildings.CRANE), 0, "no water, no cranes")
	check_eq(c.building.count(Buildings.PIER), 0)
	var report := ports.port_report()
	check(not report[0].operating, "an inland seaport never operates")
	check_gt(int(report[0].developed), 0, "warehouses still fill the yard")
	check_eq(ports.demand_bonus(), Vector3i.ZERO)


func test_coastal_seaport_builds_piers_and_operates() -> void:
	var parts := _harbour_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var rect: Rect2i = parts[2]
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	var cranes := _count_in(c, rect, Buildings.CRANE)
	check_ge(cranes, 1, "a crane stands on the shore")
	check_eq(c.building.count(Buildings.PIER), cranes * PortParams.PIER_LENGTH, "each crane has its piers")
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if c.building_at(x, y) == Buildings.PIER:
				check(c.is_open_water(x, y), "piers stand over water")
				check_eq(c.zone_kind_at(x, y), Zones.SEAPORT, "and belong to the port")
			elif c.building_at(x, y) == Buildings.CRANE:
				check(not c.is_water(x, y), "cranes stand on land")
	var report := ports.port_report()
	check(report[0].operating)
	check_gt(ports.demand_bonus().z, 0, "industrial demand rises")
	check_eq(ports.demand_bonus().y, 0)


func test_shallow_berth_blocks_piers() -> void:
	var c := flat_city()
	_flood_rect(c, Rect2i(40, 0, City.WIDTH - 40, City.HEIGHT))
	for y in City.HEIGHT:
		for x in range(40, City.WIDTH):
			c.set_heights(x, y, 3, 4)
	var ctx := _context(c)
	var rect := Rect2i(34, 20, 6, 8)
	_zone_rect(c, rect, Zones.SEAPORT)
	_power_rect(c, rect)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check_eq(c.building.count(Buildings.PIER), 0, "shallows cannot berth a ship")


func test_ships_move_on_water_only() -> void:
	var parts := _harbour_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check(ports.port_report()[0].operating)
	var seen := false
	var positions := 0
	var docked_at_berth := false
	var steps_checked := 0
	var previous := Vector2i(-1, -1)
	for _i in 500:
		_run_day(ctx, ports)
		var ships := 0
		for v in ports.vehicles():
			if v.kind != &"ship":
				continue
			ships += 1
			seen = true
			positions += 1
			var p := Vector2i(int(v.x), int(v.y))
			check(c.is_open_water(p.x, p.y), "ship at %s is on open water" % [p])
			check_eq(c.building_at(p.x, p.y), Buildings.NONE, "ship never sails through a building")
			if previous.x >= 0:
				check_between(maxi(absi(p.x - previous.x), absi(p.y - previous.y)), 0, PortParams.SHIP_SPEED, "ships move one tile at a time")
				steps_checked += 1
			previous = p
			if c.building_at(p.x - 1, p.y) == Buildings.PIER:
				docked_at_berth = true
		check(ships <= 1, "one ship at a time")
		if ships == 0:
			previous = Vector2i(-1, -1)
	check(seen, "an operating seaport is visited by a ship")
	check(docked_at_berth, "the ship reaches the berth beyond the piers")
	check_gt(steps_checked, 10)


func test_no_ship_without_a_route_to_the_edge() -> void:
	var c := flat_city()
	_flood_rect(c, Rect2i(40, 10, 20, 20))
	var ctx := _context(c)
	var rect := Rect2i(34, 14, 6, 8)
	_zone_rect(c, rect, Zones.SEAPORT)
	_power_rect(c, rect)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	check_ge(_count_in(c, rect, Buildings.CRANE), 1, "the lake still gets a crane")
	_run_days(ctx, ports, 12 * GameClock.DAYS_PER_MONTH)
	check_eq(_count_kind(ports.vehicles(), &"ship"), 0, "no ship can reach a landlocked port")


# ── Military zones ───────────────────────────────────────────────────────

func test_military_zone_develops_without_power() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rect := Rect2i(50, 50, 8, 8)
	_zone_rect(c, rect, Zones.MILITARY)
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 24 * GameClock.DAYS_PER_MONTH)
	var report := ports.port_report()
	check_eq(report[0].kind, Zones.MILITARY)
	check_gt(int(report[0].developed), 0)
	check_ge(_count_in(c, rect, Buildings.RUNWAY), PortParams.RUNWAY_LENGTH, "an air base lays a runway")
	check(report[0].operating)
	check_eq(ports.demand_bonus(), Vector3i.ZERO, "bases do not drive demand")
	check_gt(int(report[0].crime), 0)
	check_eq(_count_kind(ports.vehicles(), &"plane"), 0, "no airliners from a base")


# ── Persistence ──────────────────────────────────────────────────────────

func test_save_load_round_trip() -> void:
	var parts := _harbour_city()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	_zone_rect(c, Rect2i(10, 40, 12, 12), Zones.AIRPORT)
	_power_rect(c, Rect2i(10, 40, 12, 12))
	var ports := _make_ports(ctx)
	_run_days(ctx, ports, 18 * GameClock.DAYS_PER_MONTH)
	var found := 0
	for _i in 200:
		_run_day(ctx, ports)
		if ports.vehicles().size() >= 2:
			found = ports.vehicles().size()
			break
	check_gt(found, 1, "vehicles are out")
	var saved := ports.save()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var c2 := c.duplicate_city()
	var ctx2 := _context(c2)
	ctx2.clock.day = ctx.clock.day
	var restored := _make_ports(ctx2)
	restored.load(parsed)
	check_eq(restored.vehicles(), ports.vehicles())
	check_eq(restored.port_report(), ports.port_report())
	check_eq(restored.jobs(), ports.jobs())
	check_eq(restored.demand_bonus(), ports.demand_bonus())
	ctx2.rng.set_state(ctx.rng.state())
	_run_days(ctx, ports, 5)
	_run_days(ctx2, restored, 5)
	check_eq(restored.vehicles(), ports.vehicles(), "restored vehicles continue identically")
