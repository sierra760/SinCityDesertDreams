# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## End-to-end: generate a map, lay out a small town with the Builder, run the
## whole simulation for several years and check that the systems cooperate.
extends "res://tests/test_case.gd"

const YEARS := 6


func _build_town(city: City, stats: CityStats, sim: Simulation) -> Dictionary:
	var b := Builder.new(city, stats, sim)
	var log := {}
	# A plant and pump in the west, streets running east, lines reaching each block.
	log["plant"] = b.apply(Tools.Kind.COAL_PLANT, Vector2i(30, 40))
	log["pump"] = b.apply(Tools.Kind.WATER_PUMP, Vector2i(34, 43))
	log["road"] = b.apply(Tools.Kind.ROAD, Vector2i(36, 44), Vector2i(70, 44))
	log["road2"] = b.apply(Tools.Kind.ROAD, Vector2i(36, 50), Vector2i(70, 50))
	log["cross"] = b.apply(Tools.Kind.ROAD, Vector2i(36, 41), Vector2i(36, 56))
	log["line"] = b.apply(Tools.Kind.POWER_LINE, Vector2i(34, 44), Vector2i(36, 44))
	log["line2"] = b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 44), Vector2i(35, 51))
	log["line3"] = b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 45), Vector2i(37, 45))
	log["line4"] = b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 51), Vector2i(37, 51))
	# Residential above the street, commercial and industry below.
	log["res"] = b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(37, 45), Vector2i(70, 49))
	log["com"] = b.apply(Tools.Kind.ZONE_COM_LOW, Vector2i(37, 51), Vector2i(52, 55))
	log["ind"] = b.apply(Tools.Kind.ZONE_IND_LOW, Vector2i(53, 51), Vector2i(70, 55))
	# Pipes under the streets.
	log["pipe"] = b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 43), Vector2i(35, 51))
	log["pipe2"] = b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 44), Vector2i(70, 44))
	log["pipe3"] = b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 50), Vector2i(70, 50))
	log["police"] = b.apply(Tools.Kind.POLICE, Vector2i(72, 45))
	log["fire"] = b.apply(Tools.Kind.FIRE, Vector2i(72, 51))
	return log


func test_town_grows_over_years() -> void:
	var city := flat_city(20000)
	city.founded_year = 1950
	city.name = "Testbed"
	var sim := make_simulation(city, 777)
	var log := _build_town(city, sim.stats, sim)
	for k in log:
		check(bool(log[k]["ok"]), "%s should apply: %s" % [k, str(log[k].get("reason", ""))])
	var spent := 20000 - city.funds
	check_gt(spent, 4000, "construction should cost money")
	check(city.building_at(30, 40) == Buildings.COAL_PLANT)
	check(Buildings.is_road_like(city.building_at(50, 44)))

	var news := [0]
	var reviews := [0]
	sim.news_published.connect(func(_s: Dictionary) -> void: news[0] += 1)
	sim.budget_review_due.connect(func(_y: int) -> void: reviews[0] += 1)

	var populations: Array[int] = []
	for year in YEARS:
		sim.advance_days(GameClock.DAYS_PER_YEAR)
		populations.append(sim.stats.total_population())
	check_eq(reviews[0], YEARS, "one budget review per year")
	check_gt(news[0], 0, "the town makes news")
	check_gt(populations[YEARS - 1], 0, "people moved in")
	check_ge(populations[YEARS - 1], populations[0], "population does not collapse")
	check_gt(sim.stats.power_capacity, 0)
	check_lt(sim.stats.unpowered_buildings, 10, "the plant reaches the zones")
	check_gt(sim.stats.water_capacity, 0)
	var developed := 0
	for y in range(45, 56):
		for x in range(37, 71):
			if Buildings.is_zone_building(city.building_at(x, y)):
				developed += 1
	check_gt(developed, 20, "zones developed")
	check(sim.stats.ledger.size() > 0 or sim.stats.last_year_ledger.size() > 0, "budget kept books")
	check_ne(sim.stats.last_year_ledger.get(&"taxes_residential", 0), 0, "residential taxes were collected")
	check_gt(sim.stats.history.get(&"population", PackedInt32Array()).size(), 12, "statistics sampled")
	check_gt(sim.stats.newspaper_archive.size(), 0, "issues were published")
	print("    population by year: %s, funds %d, demand %s" % [str(populations), city.funds, str(sim.stats.demand)])
	sim.queue_free()


func test_snapshot_round_trip_mid_game() -> void:
	var city := flat_city(20000)
	city.founded_year = 1950
	var sim := make_simulation(city, 4242)
	_build_town(city, sim.stats, sim)
	sim.advance_days(GameClock.DAYS_PER_YEAR * 2 + 7)
	var snap := sim.snapshot()
	var json := JSON.stringify(snap)
	var back: Dictionary = JSON.parse_string(json)
	var twin := city.duplicate_city()
	var sim2 := make_simulation(twin, 1)
	sim2.restore(back)
	check_eq(sim2.clock.day, sim.clock.day)
	check_eq(sim2.stats.population, sim.stats.population)
	check_eq(sim2.stats.demand, sim.stats.demand)
	check_eq(sim2.stats.ledger, sim.stats.ledger)
	# Both continue identically for a month.
	sim.advance_days(GameClock.DAYS_PER_MONTH)
	sim2.advance_days(GameClock.DAYS_PER_MONTH)
	check_eq(sim2.stats.population, sim.stats.population, "restored run diverged")
	check_eq(twin.funds, city.funds, "restored funds diverged")
	check_eq(twin.building.data, city.building.data, "restored map diverged")
	sim.queue_free()
	sim2.queue_free()


func test_generated_map_saves_and_loads() -> void:
	var rng := SimRng.new(99)
	var city: City = TerrainGenerator.new().generate({"hills": 40, "water": 40, "trees": 40, "coast": "east", "river": true, "name": "Mesa Verde"}, rng)
	check_eq(city.name, "Mesa Verde")
	var water := 0
	var trees := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.is_water(x, y): water += 1
			if Buildings.is_tree(city.building_at(x, y)): trees += 1
	check_gt(water, 200, "map has water")
	check_gt(trees, 200, "map has trees")
	var sim := make_simulation(city, 5)
	sim.advance_days(40)
	var path := "user://playthrough_test.sc2d"
	check_eq(SaveFormat.save(path, city, sim.snapshot()), OK)
	var loaded: Dictionary = SaveFormat.load(path)
	check(bool(loaded["ok"]), str(loaded.get("error", "")))
	var city2: City = loaded["city"]
	check_eq(city2.terrain.data, city.terrain.data)
	check_eq(city2.altitude.data, city.altitude.data)
	check_eq(city2.building.data, city.building.data)
	check_eq(city2.day, city.day)
	sim.queue_free()
