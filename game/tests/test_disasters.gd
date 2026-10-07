# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Most tests drive the disaster system alone through a hand-built context so
## the other systems cannot repopulate or redevelop the synthetic city. The
## Simulation round trips at the end prove the real wiring.

var _contexts: Array[SimContext] = []
var _news: Array[Dictionary] = []
var _notices: Array[StringName] = []


func before_each() -> void:
	_news.clear()
	_notices.clear()


func after_each() -> void:
	# Hand-built fixtures own the context table without a Simulation Node.
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func _make(c: City, seed_value: int) -> Dictionary:
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	ctx.clock.day = c.day
	var sys := DisasterSystem.new()
	ctx.systems = {&"disasters": sys}
	sys.setup(ctx)
	return {"sys": sys, "ctx": ctx}


func _advance(h: Dictionary, days: int) -> void:
	var sys: DisasterSystem = h["sys"]
	var ctx: SimContext = h["ctx"]
	for i in days:
		ctx.events.clear()
		sys.daily(ctx)
		if ctx.clock.day_of_month() == 20:
			sys.monthly(ctx)
		if ctx.clock.is_year_end():
			sys.yearly(ctx)
		_collect(ctx)
		ctx.clock.advance()
		ctx.city.day = ctx.clock.day


func _collect(ctx: SimContext) -> void:
	for n in ctx.events.news:
		_news.append(n)
	for n in ctx.events.notices:
		_notices.append(n["kind"])


func _request(h: Dictionary, kind: StringName, at: Vector2i = Vector2i(-1, -1)) -> bool:
	var sys: DisasterSystem = h["sys"]
	var ctx: SimContext = h["ctx"]
	ctx.events.clear()
	var ok := sys.request(ctx, kind, at)
	_collect(ctx)
	return ok


func _stats(h: Dictionary) -> CityStats:
	var ctx: SimContext = h["ctx"]
	return ctx.stats


func _news_count(kind: StringName) -> int:
	var n := 0
	for s in _news:
		if s["kind"] == kind:
			n += 1
	return n


func _fill_houses(c: City, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)


func _fill_trees(c: City, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			c.building.put(x, y, Buildings.TREES_1 + 2)


func _water_columns(c: City, x0: int, x1: int) -> void:
	for y in City.HEIGHT:
		for x in range(x0, x1 + 1):
			c.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			c.set_heights(x, y, 2, 4)


func _count_in(c: City, x0: int, y0: int, w: int, h: int, test: Callable) -> int:
	var n := 0
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if test.call(c.building_at(x, y)):
				n += 1
	return n


func _is_rubble(id: int) -> bool:
	return Buildings.is_rubble(id)


func test_fire_spreads_across_trees_and_stops_at_water() -> void:
	var c := flat_city()
	_fill_trees(c, 10, 10, 15, 11)
	_water_columns(c, 25, 27)
	_fill_trees(c, 28, 10, 13, 11)
	var h := _make(c, 7)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"fire", Vector2i(12, 15)), "fire request accepted")
	check_gt(_stats(h).active_fires, 0, "a fire is burning")
	check_eq(_stats(h).active_disaster, &"fire")
	check_eq(_news_count(&"fire_reported"), 1)
	check_eq(_news_count(&"disaster_started"), 1)
	check(_notices.has(&"disaster"))
	_advance(h, 40)
	var far_side := _count_in(c, 20, 10, 5, 11, _is_rubble)
	for t in sys.fires():
		if t.x >= 20 and t.x <= 24:
			far_side += 1
	check_gt(far_side, 0, "fire reached the water's edge")
	var beyond := _count_in(c, 28, 10, 13, 11, _is_rubble)
	for t in sys.fires():
		if t.x >= 28:
			beyond += 1
	check_eq(beyond, 0, "nothing burned past the water")
	check(c.is_water(26, 15), "water untouched")
	check_eq(c.building_at(26, 15), Buildings.NONE)


func test_unplaced_fire_starts_where_there_is_something_to_burn() -> void:
	# A lone palm in the open would burn out on its own; a fire called down
	# from the menu goes for a built-up lot when the town has one.
	var c := flat_city()
	c.stamp_building(90, 90, Buildings.TREES_1)
	for x in range(20, 30):
		for y in range(20, 24):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	var h := _make(c, 11)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"fire", Vector2i(-1, -1)), "fire request accepted")
	var first: Vector2i = sys.fires()[0]
	check(first.x >= 20 and first.x < 30 and first.y >= 20 and first.y < 24, "fire started on the built-up block, not on the lone palm")
	_advance(h, 6)
	check_gt(sys.fires().size() + _count_in(c, 20, 20, 10, 4, _is_rubble), 1, "the fire spread or burned a lot")


func test_fire_crews_put_it_out() -> void:
	var with_crew := _burn_grove(true)
	var without_crew := _burn_grove(false)
	check_eq(with_crew["fires"], 0, "crew extinguished every fire")
	check_lt(with_crew["rubble"], without_crew["rubble"], "crew saved trees")
	check_eq(with_crew["crews_after"], 0, "crews released after the emergency")


func _burn_grove(dispatch: bool) -> Dictionary:
	var c := flat_city()
	_fill_trees(c, 30, 30, 5, 5)
	c.stamp_building(10, 10, Buildings.FIRE_STATION)
	var h := _make(c, 11)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"fire", Vector2i(32, 32)))
	if dispatch:
		check(sys.dispatch(&"fire", Vector2i(32, 32)), "crew placed")
		check_eq(sys.crews().size(), 1)
	_advance(h, 20)
	var rubble := _count_in(c, 30, 30, 5, 5, _is_rubble)
	return {"fires": _stats(h).active_fires, "rubble": rubble, "crews_after": sys.crews().size()}


func test_fire_coverage_slows_the_burn() -> void:
	var covered := _burn_houses(255)
	var bare := _burn_houses(0)
	check_lt(covered, bare, "coverage saves houses")


func _burn_houses(cover: int) -> int:
	var c := flat_city()
	_fill_houses(c, 40, 40, 12, 12)
	c.fire_cover.fill(cover)
	var h := _make(c, 61)
	check(_request(h, &"fire", Vector2i(45, 45)))
	_advance(h, 30)
	return _count_in(c, 40, 40, 12, 12, _is_rubble)


func test_tornado_moves_and_leaves_rubble() -> void:
	var c := flat_city()
	_fill_houses(c, 40, 40, 20, 20)
	var h := _make(c, 3)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"tornado", Vector2i(50, 50)))
	check_eq(_stats(h).active_disaster, &"tornado")
	var start := sys.entities()
	check_eq(start.size(), 1)
	check_eq(start[0]["kind"], &"tornado")
	check_eq(Vector2i(start[0]["x"], start[0]["y"]), Vector2i(50, 50))
	_advance(h, 2)
	var later := sys.entities()
	check_eq(later.size(), 1, "tornado still on the map")
	check_ne(Vector2i(later[0]["x"], later[0]["y"]), Vector2i(50, 50), "tornado moved")
	check_gt(_count_in(c, 40, 40, 20, 20, _is_rubble), 0, "houses wrecked along its path")
	_advance(h, 60)
	check(sys.active().is_empty(), "tornado over")
	check_eq(sys.entities().size(), 0)
	check_eq(_stats(h).active_disaster, &"" if _stats(h).active_fires == 0 else &"fire")
	check_eq(_news_count(&"disaster_ended"), 1)


func test_earthquake_clears_buildings() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 30, 30)
	var h := _make(c, 5)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"earthquake", Vector2i(45, 45)))
	var houses := _count_in(c, 30, 30, 30, 30, func(id: int) -> bool: return id == Buildings.RES_1X1_FIRST)
	check_lt(houses, 900, "some houses fell")
	var rubble := _count_in(c, 30, 30, 30, 30, _is_rubble)
	check_gt(rubble, 0)
	check_gt(rubble + _stats(h).active_fires, 50, "a real quake, not a tremor")
	_advance(h, 10)
	check(sys.active().is_empty(), "aftershocks over")


func test_flood_raises_overlay_then_recedes() -> void:
	var c := flat_city()
	_water_columns(c, 60, 63)
	_fill_houses(c, 50, 30, 10, 20)
	var h := _make(c, 9)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"flood", Vector2i(58, 40)))
	check_gt(c.flood_overlay.size(), 0, "shoreline flooded at once")
	_advance(h, 8)
	check_gt(c.flood_overlay.size(), 4, "flood spread inland")
	check_eq(sys.flooded().size(), c.flood_overlay.size())
	for t in sys.flooded():
		check(c.is_water(t.x, t.y), "flooded tile reads as water")
	_advance(h, 60)
	check_eq(c.flood_overlay.size(), 0, "flood receded")
	check(sys.active().is_empty(), "flood over")
	check_eq(c.building_at(61, 40), Buildings.NONE)
	check(c.is_water(61, 40), "real water stays")


func test_meltdown_needs_a_nuclear_plant() -> void:
	var c := flat_city()
	_fill_houses(c, 40, 40, 20, 20)
	var h := _make(c, 13)
	var sys: DisasterSystem = h["sys"]
	check(not _request(h, &"meltdown"), "no plant, no meltdown")
	c.stamp_building(60, 60, Buildings.NUCLEAR_PLANT)
	check(_request(h, &"meltdown"), "plant melts down")
	check_eq(_stats(h).active_disaster, &"meltdown")
	check_ne(c.building_at(61, 61), Buildings.NUCLEAR_PLANT, "plant destroyed")
	var contaminated := _count_in(c, 40, 40, 30, 30, func(id: int) -> bool: return id == Buildings.CONTAMINATION)
	check_ge(contaminated, 16, "footprint contaminated")
	_advance(h, 40)
	check(sys.active().is_empty(), "meltdown over")
	var later := _count_in(c, 40, 40, 30, 30, func(id: int) -> bool: return id == Buildings.CONTAMINATION)
	check_gt(later, contaminated, "contamination spread")


func test_no_disasters_roll_when_disabled() -> void:
	check_eq(_natural_starts(false), 0, "nothing while disabled")
	check_gt(_natural_starts(true), 0, "nature strikes when enabled")


func _natural_starts(enabled: bool) -> int:
	var c := flat_city()
	_fill_houses(c, 30, 30, 30, 30)
	c.difficulty = City.Difficulty.HARD
	c.day = 800
	var h := _make(c, 21)
	_stats(h).disasters_enabled = enabled
	_stats(h).population = 400000
	_advance(h, 40 * GameClock.DAYS_PER_MONTH)
	return _news_count(&"disaster_started")


func test_natural_roll_waits_for_the_grace_period() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 30, 30)
	c.difficulty = City.Difficulty.EASY
	var h := _make(c, 21)
	_stats(h).population = 400000
	_advance(h, 24 * GameClock.DAYS_PER_MONTH)
	check_eq(_news_count(&"disaster_started"), 0, "young cities are spared")


func test_only_one_major_disaster_at_a_time() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 30, 30)
	var h := _make(c, 23)
	check(_request(h, &"earthquake", Vector2i(45, 45)))
	check(not _request(h, &"tornado", Vector2i(45, 45)), "second major refused")
	check(_request(h, &"fire", Vector2i(31, 31)), "fires may overlap")
	check_eq(_stats(h).active_disaster, &"earthquake")
	check(not _request(h, &"typhoon"), "unknown kind refused")


func test_dispatch_needs_an_emergency_and_respects_limits() -> void:
	var c := flat_city()
	_fill_trees(c, 30, 30, 10, 10)
	c.stamp_building(10, 10, Buildings.FIRE_STATION)
	c.stamp_building(20, 10, Buildings.FIRE_STATION)
	var h := _make(c, 29)
	var sys: DisasterSystem = h["sys"]
	check(not sys.dispatch(&"fire", Vector2i(32, 32)), "no emergency yet")
	check(_request(h, &"fire", Vector2i(32, 32)))
	check_eq(sys.crews_available(&"fire"), 2)
	check_eq(sys.crews_available(&"police"), 0)
	check_eq(sys.crews_available(&"military"), 0)
	check(sys.dispatch(&"fire", Vector2i(31, 31)))
	check(sys.dispatch(&"fire", Vector2i(33, 33)))
	check(sys.dispatch(&"fire", Vector2i(35, 35)), "third placement moves the oldest crew")
	check_eq(sys.crews().size(), 2)
	check_eq(Vector2i(sys.crews()[0]["x"], sys.crews()[0]["y"]), Vector2i(33, 33))
	check(not sys.dispatch(&"police", Vector2i(32, 32)), "no police station")
	check(not sys.dispatch(&"fire", Vector2i(-1, 5)), "off the map")


func test_crews_summary_matches_per_kind_counts() -> void:
	var c := flat_city()
	_fill_trees(c, 30, 30, 10, 10)
	var h := _make(c, 29)
	var sys: DisasterSystem = h["sys"]
	check_eq(sys.crews_summary(), {&"fire": 0, &"police": 0, &"military": 1}, "guard only")
	for i in 7:
		c.stamp_building(4 + i * 4, 4, Buildings.FIRE_STATION)
	for i in 3:
		c.stamp_building(4 + i * 4, 70, Buildings.POLICE_STATION)
	var summary := sys.crews_summary()
	check_eq(summary[&"fire"], mini(7, DisasterParams.MAX_CREWS))
	check_eq(summary[&"police"], mini(3, DisasterParams.MAX_CREWS))
	check_eq(summary[&"military"], 0)
	c.stamp_building(90, 90, Buildings.PARKING_MILITARY)
	summary = sys.crews_summary()
	check_eq(summary[&"military"], DisasterParams.MILITARY_CREWS)
	for kind in DisasterSystem.CREW_KINDS:
		check_eq(sys.crews_available(kind), int(summary[kind]), String(kind))
	check_eq(sys.crews_available(&"unknown"), 0)


func test_national_guard_when_city_has_no_crews() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 10, 10)
	var h := _make(c, 31)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"earthquake", Vector2i(35, 35)))
	check(_notices.has(&"disaster"), "disaster notice raised")
	check(_notices.has(&"national_guard"), "guard offered")
	check_eq(sys.crews_available(&"military"), 1)
	check(sys.dispatch(&"military", Vector2i(35, 35)))
	check_eq(sys.crews()[0]["kind"], &"military")


func test_riot_needs_roads_and_walks_them() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 20, 20)
	var h := _make(c, 37)
	var sys: DisasterSystem = h["sys"]
	check(not _request(h, &"riot", Vector2i(40, 40)), "no road to riot on")
	for x in range(30, 50):
		c.building.put(x, 40, Buildings.ROAD_FIRST)
	check(_request(h, &"riot", Vector2i(40, 40)))
	check_eq(_stats(h).active_disaster, &"riot")
	check(not sys.active().is_empty())
	_advance(h, 60)
	check(sys.active().is_empty(), "riot over")
	check_eq(_news_count(&"disaster_ended"), 1)
	check(_request(h, &"mass_riots", Vector2i(40, 40)))
	_advance(h, 20)
	var damage := _count_in(c, 30, 30, 20, 20, _is_rubble) + _stats(h).active_fires
	check_gt(damage, 0, "rioters wreck and burn what they pass")


func test_police_disperse_riots() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 20, 20)
	for x in range(30, 50):
		c.building.put(x, 40, Buildings.ROAD_FIRST)
	for i in 4:
		c.stamp_building(10 + i * 4, 10, Buildings.POLICE_STATION)
	var h := _make(c, 67)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"mass_riots", Vector2i(40, 40)))
	check_eq(_stats(h).active_disaster, &"mass_riots")
	check_eq(sys.crews_available(&"police"), 4)
	for i in 4:
		check(sys.dispatch(&"police", Vector2i(32 + i * 6, 40)))
	_advance(h, 12)
	check(sys.active().is_empty(), "police crews broke up the riot")
	c.police.fill(255)
	check(_request(h, &"mass_riots", Vector2i(40, 40)))
	_advance(h, 20)
	check(sys.active().is_empty(), "strong police coverage disperses riots on its own")


func test_plane_crash_hits_its_target() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 40, 40)
	var h := _make(c, 41)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"plane_crash", Vector2i(50, 50)))
	check_eq(sys.entities()[0]["kind"], &"plane")
	_advance(h, 30)
	check(Buildings.is_rubble(c.building_at(50, 50)), "impact site wrecked")
	check(Buildings.is_rubble(c.building_at(51, 51)))
	check_eq(sys.entities().size(), 0)
	check(sys.active().is_empty())


func test_volcano_raises_a_cone() -> void:
	var c := flat_city()
	_fill_houses(c, 50, 50, 20, 20)
	var h := _make(c, 43)
	check(_request(h, &"volcano", Vector2i(60, 60)))
	check_eq(c.ground_height(60, 60), 9)
	check_eq(c.ground_height(63, 60), 6)
	check_eq(c.ground_height(70, 60), 4)
	check_eq(c.building_at(60, 60), Buildings.NONE, "vent cleared")
	check_eq(c.building_at(62, 62), Buildings.NONE, "slope cleared")
	check_eq(c.building_at(53, 53), Buildings.RES_1X1_FIRST, "beyond the foot of the cone untouched")
	check(not c.is_flat(61, 60), "slopes recomputed")
	_advance(h, 15)
	check(h["sys"].active().is_empty())


func test_volcano_keeps_a_lattice_city_in_sync() -> void:
	var c := flat_city()
	TerrainEditor.new(c)
	_fill_houses(c, 50, 50, 20, 20)
	var h := _make(c, 43)
	check(_request(h, &"volcano", Vector2i(60, 60)))
	var s: TerrainSurface = c.terrain_surface
	check_eq(c.ground_height(60, 60), 9)
	check_eq(s.tile_base(60, 60), 9, "the lattice rose with the vent")
	check_gt(c.ground_height(63, 60), 4, "the cone spreads around the vent")
	check_eq(c.building_at(60, 60), Buildings.NONE, "vent cleared")
	check_eq(c.building_at(53, 53), Buildings.RES_1X1_FIRST, "beyond the foot of the cone untouched")
	var mismatched := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if s.tile_base(x, y) != c.ground_height(x, y) or s.tile_code(x, y) != c.terrain.at(x, y):
				mismatched += 1
			elif c.building_at(x, y) == Buildings.RES_1X1_FIRST and not s.is_tile_flat(x, y):
				mismatched += 1
	check_eq(mismatched, 0, "every tile matches the lattice, and no house stands on moved ground")
	var loaded: City = SaveFormat.decode_city(SaveFormat.encode_city(c))["city"]
	check(loaded != null)
	if loaded == null:
		return
	check_eq(loaded.altitude.data, c.altitude.data, "the cone survives a save")
	check_eq(loaded.terrain.data, c.terrain.data)
	check_eq((loaded.terrain_surface as TerrainSurface).vertices, s.vertices, "saved vertices carry the cone")


func test_plant_and_industry_preconditions() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 10, 10)
	var h := _make(c, 47)
	var sys: DisasterSystem = h["sys"]
	check(not _request(h, &"microwave"))
	check(not _request(h, &"chemical_spill"))
	check(not _request(h, &"hazard"), "no pollution, no accident")
	check(not _request(h, &"flood"), "no shoreline, no flood")
	c.stamp_building(60, 60, Buildings.MICROWAVE_PLANT)
	check(_request(h, &"microwave"))
	check_eq(sys.entities()[0]["kind"], &"beam")
	_advance(h, 20)
	check(sys.active().is_empty())
	c.stamp_building(20, 20, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	check(_request(h, &"chemical_spill"))
	check_eq(c.building_at(20, 20), Buildings.CONTAMINATION)
	_advance(h, 20)
	check(_request(h, &"hazard", Vector2i(35, 35)), "a requested point is enough")
	check_eq(c.building_at(35, 35), Buildings.CONTAMINATION)
	_advance(h, 5)
	check(_request(h, &"monster", Vector2i(35, 35)))
	check_eq(sys.entities()[0]["kind"], &"monster")
	_advance(h, 80)
	check(sys.active().is_empty(), "monster left")


func test_hurricane_brings_wind_then_flood() -> void:
	var c := flat_city()
	_water_columns(c, 70, 73)
	_fill_houses(c, 40, 30, 30, 30)
	var h := _make(c, 71)
	var sys: DisasterSystem = h["sys"]
	check(_request(h, &"hurricane", Vector2i(69, 45)))
	check_eq(sys.entities()[0]["kind"], &"hurricane")
	_advance(h, 10)
	check_gt(c.flood_overlay.size(), 0, "storm surge floods the shore")
	check_gt(_count_in(c, 40, 30, 30, 30, _is_rubble), 0, "wind damage")
	_advance(h, 80)
	check(sys.active().is_empty(), "storm over")
	check_eq(c.flood_overlay.size(), 0)


func test_advisor_reports_needs() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 10, 10)
	var h := _make(c, 53)
	var sys: DisasterSystem = h["sys"]
	_stats(h).population = 5000
	_stats(h).power_demand = 100
	_stats(h).power_capacity = 0
	_advance(h, GameClock.DAYS_PER_MONTH)
	var advice := sys.advice()
	check_eq(advice[0], &"needs_power")
	check(advice.has(&"needs_police"))
	check(advice.has(&"needs_fire_protection"))
	check(advice.has(&"needs_hospital"))
	check(not advice.has(&"needs_seaport"), "too small for a seaport")
	check_eq(_news_count(&"advisor_need"), 1)
	check_eq(_news[0]["args"]["need"], "needs_power")
	c.stamp_building(10, 10, Buildings.POLICE_STATION)
	_stats(h).power_capacity = 1000
	_advance(h, GameClock.DAYS_PER_MONTH)
	advice = sys.advice()
	check(not advice.has(&"needs_power"))
	check(not advice.has(&"needs_police"))


func test_contamination_clears_over_years() -> void:
	var c := flat_city()
	for y in range(40, 50):
		for x in range(40, 50):
			c.building.put(x, y, Buildings.CONTAMINATION)
	var h := _make(c, 59)
	_advance(h, GameClock.DAYS_PER_YEAR * 3)
	var left := _count_in(c, 40, 40, 10, 10, func(id: int) -> bool: return id == Buildings.CONTAMINATION)
	check_lt(left, 100, "some ground recovered")
	check_gt(left, 20, "but it lingers for years")


func test_save_load_round_trip_mid_disaster() -> void:
	var c := flat_city()
	_fill_houses(c, 30, 30, 40, 40)
	_water_columns(c, 80, 83)
	c.stamp_building(10, 10, Buildings.FIRE_STATION)
	var sim := make_simulation(c, 17)
	var sys := sim.get_system(&"disasters") as DisasterSystem
	check(sim.request_disaster(&"tornado", Vector2i(50, 50)))
	check(sim.request_disaster(&"fire", Vector2i(35, 35)))
	sim.advance_days(2)
	check(sys.dispatch(&"fire", Vector2i(36, 36)))
	var snapshot := sim.snapshot()
	var c2 := c.duplicate_city()
	var sim2 := make_simulation(c2, 1)
	sim2.restore(snapshot)
	var sys2 := sim2.get_system(&"disasters") as DisasterSystem
	check_eq(sys2.save(), sys.save(), "state restored")
	check_eq(sys2.fires(), sys.fires())
	check_eq(sys2.entities(), sys.entities())
	check_eq(sys2.crews(), sys.crews())
	check_eq(sim2.stats.active_disaster, &"tornado")
	check_eq(sim2.stats.active_fires, sim.stats.active_fires)
	sim.advance_days(6)
	sim2.advance_days(6)
	check(c.building.data == c2.building.data, "both cities evolve the same way")
	check_eq(sys2.save(), sys.save(), "state stays in step")


func test_flood_survives_save_and_load() -> void:
	var c := flat_city()
	_water_columns(c, 60, 63)
	var sim := make_simulation(c, 19)
	check(sim.request_disaster(&"flood", Vector2i(58, 40)))
	sim.advance_days(5)
	var snapshot := sim.snapshot()
	var c2 := c.duplicate_city()
	c2.flood_overlay.clear()
	var sim2 := make_simulation(c2, 1)
	sim2.restore(snapshot)
	check_eq(c2.flood_overlay, c.flood_overlay, "overlay rebuilt on load")
	sim.advance_days(70)
	sim2.advance_days(70)
	check_eq(c.flood_overlay.size(), 0)
	check_eq(c2.flood_overlay.size(), 0)


## Every menu kind must start with its physical ingredients, change state,
## survive JSON restoration and terminate without leaving crews or entities.
func test_all_sixteen_kinds_progress_restore_and_finish() -> void:
	for kind: StringName in DisasterParams.KINDS:
		var city := flat_city()
		_fill_houses(city, 35, 35, 24, 24)
		for x in range(32, 64): city.building.put(x, 40, Buildings.ROAD_FIRST)
		_water_columns(city, 65, 68)
		city.stamp_building(15, 15, Buildings.NUCLEAR_PLANT)
		city.stamp_building(22, 15, Buildings.MICROWAVE_PLANT)
		city.stamp_building(45, 45, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
		city.pollution.fill(200)
		var fixture := _make(city, 17)
		_stats(fixture).disasters_enabled = false
		var sys: DisasterSystem = fixture.sys
		var at := Vector2i(48, 48)
		if kind in [&"riot", &"mass_riots"]: at = Vector2i(48, 40)
		check(_request(fixture, kind, at), "%s starts" % kind)
		check(sys.is_emergency(), "%s enters emergency state" % kind)
		var started := sys.save()
		_advance(fixture, 3)
		check_ne(sys.save(), started, "%s advances" % kind)
		var path := "user://test_disaster_continuation.sc2d"
		check_eq(SaveFormat.save(path, city, {"systems": {"disasters": sys.save()}}), OK)
		var native := SaveFormat.load(path)
		check(native.ok, "native disaster fixture reloads")
		var restored := _make(native.city, 17)
		var ctx: SimContext = fixture.ctx
		var other: SimContext = restored.ctx
		other.rng.set_state(ctx.rng.state())
		other.clock.day = ctx.clock.day
		other.stats.disasters_enabled = false
		var sys2: DisasterSystem = restored.sys
		sys2.load(native.snapshot.systems.disasters)
		_advance(fixture, 5)
		_advance(restored, 5)
		check_eq(sys2.save(), sys.save(), "%s restored continuation matches" % kind)
		check_eq(SaveFormat.encode_city(other.city), SaveFormat.encode_city(city), "%s damage continuation matches" % kind)
		_advance(fixture, 300)
		check(not sys.is_emergency(), "%s ends" % kind)
		check(sys.entities().is_empty() and sys.crews().is_empty(), "%s releases transient records" % kind)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
