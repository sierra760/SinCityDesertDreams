# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Behavior tests for the zone system: development, decline, demand, dense
## footprints, chapels and persistence. The system is driven directly with a
## hand-built context so the results do not depend on the other systems.

const ZoneSys := preload("res://scripts/sim/zone_system.gd")
const Params := preload("res://scripts/sim/data/zone_params.gd")

const ROAD_Y := 30
const NORTH_ROWS := Rect2i(20, 27, 20, 3)   ## zone block just north of the road
const SOUTH_ROWS := Rect2i(20, 31, 20, 3)   ## zone block just south of the road

var _news: Array[StringName] = []


func make_system(ctx: SimContext) -> ZoneSys:
	var sys := ZoneSys.new()
	sys.setup(ctx)
	return sys


func run_months(sys: ZoneSys, ctx: SimContext, months: int) -> void:
	for _i in months:
		ctx.events.clear()
		sys.monthly(ctx, 0)
		sys.monthly(ctx, 1)
		for story in ctx.events.news:
			_news.append(story["kind"])
		ctx.clock.day += GameClock.DAYS_PER_MONTH
		ctx.city.day = ctx.clock.day


func zone_block(c: City, rect: Rect2i, kind: int, serviced: bool = true) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.zone.put(x, y, Zones.make(kind))
			if serviced:
				c.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)


func road_row(c: City, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		c.building.put(x, y, Buildings.ROAD_FIRST)


func count_in(c: City, rect: Rect2i, predicate: Callable) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if predicate.call(c.building.at(x, y)):
				n += 1
	return n


static func is_res_building(id: int) -> bool:
	return Buildings.category(id) == Buildings.Category.RESIDENTIAL


static func is_lot_activity(id: int) -> bool:
	return Buildings.is_zone_building(id) or Buildings.is_construction(id)


static func is_two_by_two_lot(id: int) -> bool:
	return Buildings.size(id) == Vector2i(2, 2) and (Buildings.is_zone_building(id)
		or Buildings.is_construction(id) or id == Buildings.CHAPEL)


## A starter town: light residential north of a road, light industry south.
func starter_town(with_road: bool = true, res_kind: int = Zones.RES_LOW) -> City:
	var c := flat_city()
	if with_road:
		road_row(c, ROAD_Y, 16, 44)
	zone_block(c, NORTH_ROWS, res_kind)
	zone_block(c, SOUTH_ROWS, Zones.IND_LOW)
	return c


func before_each() -> void:
	_news.clear()


func test_powered_residential_next_to_road_develops() -> void:
	var c := starter_town()
	var ctx := make_context(c)
	var sys := make_system(ctx)
	check_gt(ctx.stats.demand.x, 0, "a new city wants residents")
	run_months(sys, ctx, 6)
	check_gt(count_in(c, NORTH_ROWS, is_lot_activity), 0, "residential lots develop")
	check_gt(count_in(c, SOUTH_ROWS, is_lot_activity), 0, "industrial lots develop")
	run_months(sys, ctx, 18)
	check_gt(sys.residents(), 0)
	check_gt(ctx.stats.jobs, 0)
	check_eq(count_in(c, NORTH_ROWS, is_two_by_two_lot), 0, "light zones stay 1x1")
	check_gt(c.density_at(24, 28), 0, "density map shows the town")


func test_no_road_means_no_development() -> void:
	var c := starter_town(false)
	var ctx := make_context(c)
	var sys := make_system(ctx)
	run_months(sys, ctx, 12)
	check_eq(count_in(c, NORTH_ROWS, is_lot_activity), 0)
	check_eq(count_in(c, SOUTH_ROWS, is_lot_activity), 0)


func test_unpowered_zone_does_not_develop() -> void:
	var c := flat_city()
	road_row(c, ROAD_Y, 16, 44)
	zone_block(c, NORTH_ROWS, Zones.RES_LOW, false)
	zone_block(c, SOUTH_ROWS, Zones.IND_LOW, false)
	var ctx := make_context(c)
	var sys := make_system(ctx)
	run_months(sys, ctx, 12)
	check_eq(count_in(c, NORTH_ROWS, is_lot_activity), 0)
	check_eq(count_in(c, SOUTH_ROWS, is_lot_activity), 0)


func test_contamination_never_develops() -> void:
	var c := starter_town()
	c.building.put(22, 28, Buildings.CONTAMINATION)
	var ctx := make_context(c)
	var sys := make_system(ctx)
	run_months(sys, ctx, 12)
	check_eq(c.building_at(22, 28), Buildings.CONTAMINATION)


func test_negative_demand_causes_decline() -> void:
	var c := flat_city()
	road_row(c, ROAD_Y, 16, 44)
	zone_block(c, NORTH_ROWS, Zones.RES_LOW)
	var houses := 0
	for y in range(NORTH_ROWS.position.y, NORTH_ROWS.end.y):
		for x in range(NORTH_ROWS.position.x, NORTH_ROWS.end.x):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
			houses += 1
	var ctx := make_context(c)
	ctx.stats.tax_residential = 20
	var sys := make_system(ctx)
	check_eq(sys.residents(), houses * Params.PEOPLE_PER_UNIT)
	run_months(sys, ctx, 3)
	check_lt(ctx.stats.demand.x, 0, "no jobs and high taxes sink residential demand")
	run_months(sys, ctx, 12)
	check_gt(count_in(c, NORTH_ROWS, Buildings.is_abandoned), 0, "houses are abandoned")
	check_lt(count_in(c, NORTH_ROWS, is_res_building), houses)
	check_lt(sys.residents(), houses * Params.PEOPLE_PER_UNIT)


func test_lower_taxes_raise_demand() -> void:
	# A dozen occupied homes so the settled-town floor no longer saturates
	# demand and the tax term decides.
	var low_city := flat_city()
	var high_city := flat_city()
	for i in 12:
		low_city.stamp_building(10 + i, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		high_city.stamp_building(10 + i, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	var low := make_context(low_city)
	low.stats.tax_residential = 0
	var high := make_context(high_city)
	high.stats.tax_residential = 15
	var low_sys := make_system(low)
	var high_sys := make_system(high)
	low_sys.monthly(low, 0)
	high_sys.monthly(high, 0)
	check_gt(low_sys.raw_demand().x, high_sys.raw_demand().x)
	check_gt(low.stats.demand.x, high.stats.demand.x)


## A town with homes and factories whose demand sits below the meter's limit
## at a 20% residential and industrial rate.
func taxed_town(ordinance: StringName) -> ZoneSys:
	var c := flat_city()
	for i in 100:
		c.stamp_building(10 + (i % 80), 10 + i / 80, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	for i in 5:
		c.stamp_building(10 + i * 3, 40, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	var ctx := make_context(c)
	ctx.stats.tax_residential = 20
	ctx.stats.tax_industrial = 20
	if ordinance != &"":
		ctx.stats.ordinances[ordinance] = true
	var sys := make_system(ctx)
	sys.monthly(ctx, 0)
	return sys


func test_ordinance_nudges_demand() -> void:
	var base := taxed_town(&"").raw_demand()
	check_lt(base.x, Params.DEMAND_RAW_LIMIT, "the fixture is below the limit")
	check_lt(base.z, Params.DEMAND_RAW_LIMIT, "the fixture is below the limit")
	# Business advertising courts factories: industry feels a lower rate.
	check_eq(taxed_town(&"business_advertising").raw_demand().z - base.z,
		Params.tax_pressure(19) - Params.tax_pressure(20))
	# Pollution controls make industry feel a higher rate.
	check_eq(base.z - taxed_town(&"pollution_controls").raw_demand().z,
		Params.tax_pressure(20) - Params.tax_pressure(21))
	# Income tax is felt by households; tree planting eases it.
	check_eq(base.x - taxed_town(&"income_tax").raw_demand().x,
		Params.tax_pressure(20) - Params.tax_pressure(21))
	check_eq(taxed_town(&"tree_planting").raw_demand().x - base.x,
		Params.tax_pressure(19) - Params.tax_pressure(20))
	# The reading campaign draws families directly.
	check_eq(taxed_town(&"pro_reading_campaign").raw_demand().x - base.x, Params.READING_NUDGE)
	# Sales tax is felt by shops; the player's rate is unchanged. An empty map
	# keeps commercial demand below its limit.
	var plain := make_context(flat_city())
	var plain_sys := make_system(plain)
	plain_sys.monthly(plain, 0)
	var taxed := make_context(flat_city())
	taxed.stats.ordinances[&"sales_tax"] = true
	var taxed_sys := make_system(taxed)
	taxed_sys.monthly(taxed, 0)
	check_eq(plain_sys.raw_demand().y - taxed_sys.raw_demand().y,
		Params.tax_pressure(7) - Params.tax_pressure(8))
	check_eq(taxed.stats.tax_commercial, 7)


class FakePorts extends SimSystem:
	func demand_bonus() -> Vector3i:
		return Vector3i(0, 30, 20)

	func jobs() -> int:
		return 0


class FakeNeighbors extends SimSystem:
	func trade_demand_bonus() -> int:
		return 15


func test_ports_and_neighbor_links_lift_demand() -> void:
	var base := taxed_town(&"").raw_demand()
	var c := flat_city()
	for i in 100:
		c.stamp_building(10 + (i % 80), 10 + i / 80, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	for i in 5:
		c.stamp_building(10 + i * 3, 40, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	var ctx := make_context(c)
	ctx.stats.tax_residential = 20
	ctx.stats.tax_industrial = 20
	ctx.systems[&"ports"] = FakePorts.new()
	ctx.systems[&"neighbors"] = FakeNeighbors.new()
	var sys := make_system(ctx)
	sys.monthly(ctx, 0)
	check_eq(sys.raw_demand().z - base.z, 20 + 15, "a seaport and trade links draw industry")
	check_eq(sys.raw_demand().x, base.x, "residential demand is unchanged")
	ctx.systems.clear()


func test_dense_residential_forms_larger_footprints() -> void:
	var c := starter_town(true, Zones.RES_HIGH)
	c.land_value.fill(100)
	var ctx := make_context(c)
	ctx.stats.tax_residential = 0
	ctx.stats.tax_commercial = 0
	ctx.stats.tax_industrial = 0
	var sys := make_system(ctx)
	run_months(sys, ctx, 36)
	check_gt(count_in(c, NORTH_ROWS, is_two_by_two_lot), 0, "dense residential grows into 2x2 lots")
	# Every multi-tile lot must be intact: all tiles carry the same id.
	for y in range(NORTH_ROWS.position.y, NORTH_ROWS.end.y):
		for x in range(NORTH_ROWS.position.x, NORTH_ROWS.end.x):
			var id := c.building_at(x, y)
			if Buildings.size(id) == Vector2i(2, 2):
				var a := c.anchor_of(x, y)
				for dy in 2:
					for dx in 2:
						check_eq(c.building_at(a.x + dx, a.y + dy), id, "2x2 lot at %s intact" % [a])
	check_gt(count_in(c, Rect2i(0, 0, City.WIDTH, City.HEIGHT), func(id: int) -> bool: return id == Buildings.CHAPEL), 0,
		"a chapel appears once people live here")
	check(_news.has(&"chapel_built"), "chapel construction is reported")
	check_gt(c.facilities_of(&"chapel").size(), 0, "chapel gets a facility record")


func test_population_and_job_getters() -> void:
	var sys := ZoneSys.new()
	check_eq(sys.population_of(Buildings.RES_1X1_FIRST), 10)
	check_eq(sys.population_of(Buildings.RES_2X2_FIRST), 80)
	check_eq(sys.population_of(Buildings.RES_2X2_LAST), 120)
	check_eq(sys.population_of(Buildings.RES_3X3_FIRST), 360)
	check_eq(sys.population_of(Buildings.COM_1X1_FIRST), 0)
	check_eq(sys.population_of(Buildings.CONSTRUCTION_1X1_A), 0)
	check_eq(sys.population_of(Buildings.ABANDONED_3X3_A), 0)
	check_eq(sys.jobs_of(Buildings.COM_1X1_FIRST), 10)
	check_eq(sys.jobs_of(Buildings.IND_3X3_LAST), 360)
	check_eq(sys.jobs_of(Buildings.RES_3X3_FIRST), 0)
	check_eq(sys.stage_of(Buildings.NONE), 0)
	check_eq(sys.stage_of(Buildings.TREES_1), 0)
	check_eq(sys.stage_of(Buildings.COAL_PLANT), -1)
	check_eq(sys.stage_of(Buildings.CONSTRUCTION_3X3_B), 4)
	check_eq(sys.stage_of(Buildings.ABANDONED_2X2_FIRST), 2)
	check_eq(sys.stage_of(Buildings.ABANDONED_2X2_LAST), 3)
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	c.stamp_building(20, 10, Buildings.COM_2X2_FIRST, Zones.COM_HIGH)
	c.stamp_building(30, 10, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	var ctx := make_context(c)
	var counted := make_system(ctx)
	check_eq(counted.occupied_units(), Vector3i(36, 8, 1))
	check_eq(counted.residents(), 360)
	check_eq(ctx.stats.jobs, 90)
	check_eq(c.density_at(10, 10), 90)


func test_road_access_rules() -> void:
	var c := flat_city()
	var lot := Rect2i(40, 40, 1, 1)
	check(not ZoneSys.has_access(c, lot))
	c.building.put(43, 40, Buildings.ROAD_FIRST)
	check(ZoneSys.has_access(c, lot), "road three tiles away counts")
	c.building.put(43, 40, Buildings.HIGHWAY_FIRST)
	check(not ZoneSys.has_access(c, lot), "a highway lane alone does not")
	c.building.put(43, 40, Buildings.ONRAMP_FIRST)
	check(ZoneSys.has_access(c, lot), "a ramp does")
	c.building.put(43, 40, Buildings.RAIL_FIRST)
	check(not ZoneSys.has_access(c, lot), "plain rail does not")
	c.building.put(43, 40, Buildings.SUBWAY_STATION)
	check(ZoneSys.has_access(c, lot), "a station does")
	c.building.put(43, 40, Buildings.NONE)
	c.building.put(44, 40, Buildings.ROAD_FIRST)
	check(not ZoneSys.has_access(c, lot), "four tiles away is too far")


func test_save_and_load_round_trip() -> void:
	var c := starter_town()
	var ctx := make_context(c, 99)
	var sys := make_system(ctx)
	run_months(sys, ctx, 6)
	var saved := sys.save()
	var json := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json)

	var twin_city := c.duplicate_city()
	var twin_ctx := make_context(twin_city, 1)
	twin_ctx.rng.set_state(ctx.rng.state())
	var twin := ZoneSys.new()
	twin.setup(twin_ctx)
	twin.load(parsed)
	check_eq(twin.raw_demand(), sys.raw_demand())
	check_eq(twin.occupied_units(), sys.occupied_units())
	check_eq(twin.save(), saved, "save is stable through JSON")

	run_months(sys, ctx, 3)
	run_months(twin, twin_ctx, 3)
	check_eq(twin_city.building.data, c.building.data, "restored system continues identically")
	check_eq(twin.raw_demand(), sys.raw_demand())
	check_eq(twin_city.growth.data, c.growth.data)


func test_registers_as_the_zones_system() -> void:
	var sys: ZoneSys = ZoneSys.new()
	check_eq(sys.key, &"zones")
	check(sys is SimSystem)
	check(Simulation.SYSTEM_SCRIPTS.has("res://scripts/sim/zone_system.gd"),
		"the simulation loads this system")
	var days: Array = Simulation.SCHEDULE.keys()
	var scheduled := 0
	for d in days:
		if Simulation.SCHEDULE[d].has(&"zones"):
			scheduled += 1
	check_eq(scheduled, 2, "two monthly phases, one per half of the map")
