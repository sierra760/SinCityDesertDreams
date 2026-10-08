# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const MARCH_DAY := 2 * GameClock.DAYS_PER_MONTH + 13


## A context wired to only the population system, so behavior tests do not
## depend on what the other systems do to the map.
func make_ctx(c: City, seed_value: int = 7) -> SimContext:
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	var pop := PopulationSystem.new()
	ctx.systems = {&"population": pop}
	pop.setup(ctx)
	return ctx


func pop_of(ctx: SimContext) -> PopulationSystem:
	return ctx.system(&"population") as PopulationSystem


func run_months(ctx: SimContext, months: int) -> void:
	for _m in months:
		ctx.events.clear()
		pop_of(ctx).monthly(ctx)


func stamp_row(c: City, id: int, zone_kind: int, count: int, x0: int, y: int) -> void:
	var edge := Buildings.size(id).x
	for i in count:
		c.stamp_building(x0 + i * edge, y, id, zone_kind)


## One hundred bungalows: a thousand residents.
func thousand_city() -> City:
	var c := flat_city()
	for row in 5:
		stamp_row(c, Buildings.RES_1X1_FIRST, Zones.RES_LOW, 20, 10, 10 + row)
	return c


func stamp_powered(c: City, id: int, count: int, x0: int, y0: int) -> void:
	var edge := Buildings.size(id).x
	for i in count:
		var a := c.stamp_building(x0 + i * edge, y0, id)
		c.set_flag(a.x, a.y, TileFlags.POWERED, true)


func news_kinds(ctx: SimContext) -> Array:
	var kinds := []
	for story in ctx.events.news:
		kinds.append(story["kind"])
	return kinds


func test_population_tracks_building_capacity() -> void:
	var c := flat_city()
	stamp_row(c, Buildings.RES_1X1_FIRST, Zones.RES_LOW, 10, 10, 10)
	c.stamp_building(20, 20, Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	c.stamp_building(30, 20, Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	var ctx := make_ctx(c)
	run_months(ctx, 1)
	check_eq(ctx.stats.population, 100 + 2 * 360)
	var total := 0
	for n in ctx.stats.cohorts:
		total += n
	check_eq(total, ctx.stats.population, "cohorts sum to the residents")
	check_eq(pop_of(ctx).residents(), 820)
	c.clear_footprint(31, 21)
	run_months(ctx, 1)
	check_eq(ctx.stats.population, 460, "demolition removes residents")
	total = 0
	for n in ctx.stats.cohorts:
		total += n
	check_eq(total, 460)
	var tall := Buildings.RES_2X2_LAST
	check_gt(PopulationParams.lot_capacity(tall), PopulationParams.lot_capacity(Buildings.RES_2X2_FIRST))
	check_eq(PopulationParams.lot_capacity(Buildings.COAL_PLANT), 0)


func test_cohorts_age_over_the_years() -> void:
	var ctx := make_ctx(thousand_city())
	run_months(ctx, 1)
	check_eq(ctx.stats.cohorts[15], 0, "nobody is seventy-five on day one")
	var young_start := ctx.stats.cohorts[4]
	run_months(ctx, 120)
	check_eq(ctx.stats.population, 1000, "capacity unchanged, population unchanged")
	check_gt(ctx.stats.cohorts[13], 0, "ten years later some residents are past sixty-five")
	check_lt(ctx.stats.cohorts[4], young_start + ctx.stats.cohorts[3], "the original young adults have moved on")
	check_gt(ctx.stats.cohorts[0], 0, "children are born")
	var total := 0
	for n in ctx.stats.cohorts:
		total += n
	check_eq(total, 1000)


func test_schools_raise_education() -> void:
	var with_schools := thousand_city()
	stamp_powered(with_schools, Buildings.SCHOOL, 4, 40, 40)
	var a := make_ctx(with_schools)
	var b := make_ctx(thousand_city())
	run_months(a, 300)
	run_months(b, 300)
	check_eq(a.stats.population, b.stats.population)
	check_gt(a.stats.education_quotient, b.stats.education_quotient, "schooled generation lifts the quotient")
	check_between(a.stats.education_quotient, 0, PopulationParams.EQ_MAX)
	check_between(b.stats.education_quotient, 0, PopulationParams.EQ_MAX)
	var reading := make_ctx(thousand_city())
	reading.stats.ordinances[&"pro_reading_campaign"] = true
	run_months(reading, 300)
	check_gt(reading.stats.education_quotient, b.stats.education_quotient, "reading campaign stops the decay")


func test_libraries_raise_education_directly() -> void:
	var c := thousand_city()
	stamp_powered(c, Buildings.LIBRARY, 12, 40, 40)
	stamp_powered(c, Buildings.MUSEUM, 4, 40, 50)
	var a := make_ctx(c)
	var b := make_ctx(thousand_city())
	run_months(a, 3)
	run_months(b, 3)
	check_gt(a.stats.education_quotient, b.stats.education_quotient)


func test_hospitals_raise_life_expectancy() -> void:
	var c := thousand_city()
	for row in 5:
		stamp_powered(c, Buildings.HOSPITAL, 8, 40, 40 + row * 3)
	var a := make_ctx(c)
	var b := make_ctx(thousand_city())
	run_months(a, 12)
	run_months(b, 12)
	check_eq(a.stats.health_index, 100, "forty funded hospitals cover a thousand people")
	check_eq(b.stats.health_index, 0)
	check_ge(a.stats.life_expectancy, b.stats.life_expectancy + 5)
	check_between(a.stats.life_expectancy, 0, PopulationParams.LE_MAX)
	# Cutting health funding removes the coverage.
	a.stats.set_funding(&"health", 0)
	run_months(a, 1)
	check_eq(a.stats.health_index, 0)
	var clinics := make_ctx(thousand_city())
	clinics.stats.ordinances[&"free_clinics"] = true
	clinics.stats.ordinances[&"anti_drug_campaign"] = true
	clinics.stats.ordinances[&"public_smoking_ban"] = true
	run_months(clinics, 12)
	check_gt(clinics.stats.life_expectancy, b.stats.life_expectancy, "health ordinances lengthen lives")


func test_pollution_shortens_lives() -> void:
	var dirty := make_ctx(thousand_city())
	dirty.stats.average_pollution = 200
	var clean := make_ctx(thousand_city())
	run_months(dirty, 24)
	run_months(clean, 24)
	check_eq(dirty.stats.population, clean.stats.population)
	check_lt(dirty.stats.life_expectancy, clean.stats.life_expectancy)


func test_settlement_class_rises_with_population() -> void:
	var c := flat_city()
	for i in 6:
		c.stamp_building(10 + i * 3, 10, Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	var ctx := make_ctx(c)
	run_months(ctx, 1)
	check_eq(ctx.stats.population, 2160)
	check_eq(c.status, 1, "past two thousand residents the village becomes a town")
	check(&"status_upgrade" in news_kinds(ctx), "the upgrade is news")
	for story in ctx.events.news:
		if story["kind"] == &"status_upgrade":
			check_eq(story["args"]["name"], "Town")
	run_months(ctx, 1)
	check_eq(c.status, 1, "a town needs ten thousand to become a city")
	check(not (&"status_upgrade" in news_kinds(ctx)))
	ctx.stats.arcology_population = 9000
	run_months(ctx, 1)
	check_eq(c.status, 2, "arcology residents count toward the class")
	check_eq(PopulationSystem.status_name(5), "Megalopolis")


func test_march_vote_reflects_taxes_and_conditions() -> void:
	var content := make_ctx(thousand_city())
	content.clock.day = MARCH_DAY
	content.stats.tax_residential = 0
	content.stats.average_land_value = 250
	run_months(content, 1)
	check_between(content.stats.approval, 0, 100)
	check(&"approval_vote" in news_kinds(content), "the vote is reported")
	check_gt(pop_of(content).complaints().size(), 0)
	var unhappy := make_ctx(thousand_city())
	unhappy.clock.day = MARCH_DAY
	unhappy.stats.tax_residential = 20
	unhappy.stats.average_pollution = 200
	unhappy.stats.average_crime = 200
	unhappy.stats.average_traffic = 150
	unhappy.stats.average_land_value = 20
	run_months(unhappy, 1)
	check_gt(content.stats.approval, unhappy.stats.approval, "taxes, smog and crime cost votes")
	var top: Dictionary = pop_of(unhappy).complaints()[0]
	check(top["key"] in [&"pollution", &"crime", &"traffic", &"taxes"], "the loudest complaint is a real one")
	# No vote outside March, and none for a hamlet.
	var quiet := make_ctx(thousand_city())
	quiet.clock.day = 13
	run_months(quiet, 1)
	check_eq(quiet.stats.approval, 50)
	check(not (&"approval_vote" in news_kinds(quiet)))
	var hamlet := flat_city()
	stamp_row(hamlet, Buildings.RES_1X1_FIRST, Zones.RES_LOW, 5, 10, 10)
	var h := make_ctx(hamlet)
	h.clock.day = MARCH_DAY
	run_months(h, 1)
	check_eq(h.stats.approval, 50, "fifty residents do not hold a vote")


func test_ordinances_move_the_vote_weights() -> void:
	var stats := CityStats.new()
	var plain := PopulationSystem.vote_weights(stats)
	var tax_index := PopulationParams.COMPLAINT_KEYS.find(&"taxes")
	check_eq(int(plain["complaints"][tax_index]), 7 * PopulationParams.VOTE_TAX_WEIGHT)
	stats.ordinances[&"income_tax"] = true
	stats.ordinances[&"parking_fines"] = true
	stats.ordinances[&"homeless_shelters"] = true
	var policy := PopulationSystem.vote_weights(stats)
	check_eq(int(policy["complaints"][tax_index]),
		8 * PopulationParams.VOTE_TAX_WEIGHT + PopulationParams.VOTE_PARKING_FINES_WEIGHT,
		"income tax and parking tickets are felt as taxes")
	check_eq(int(policy["content"]) - int(plain["content"]), PopulationParams.VOTE_SHELTER_CONTENT,
		"shelters make the city feel kinder")
	stats.ordinances[&"tree_planting"] = true
	check_eq(int(PopulationSystem.vote_weights(stats)["complaints"][tax_index]),
		7 * PopulationParams.VOTE_TAX_WEIGHT + PopulationParams.VOTE_PARKING_FINES_WEIGHT,
		"tree planting lowers the felt residential rate")


## A context whose population system starts from the given cohort counts.
func cohort_ctx(cohorts: Dictionary, seed_value: int, ordinance: StringName) -> SimContext:
	var c := thousand_city()
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = 13
	var counts := PackedInt32Array()
	counts.resize(PopulationSystem.COHORTS)
	for i in cohorts:
		counts[i] = cohorts[i]
	ctx.stats.cohorts = counts
	ctx.stats.life_expectancy = 40
	ctx.stats.education_quotient = 50
	if ordinance != &"":
		ctx.stats.ordinances[ordinance] = true
	var pop := PopulationSystem.new()
	ctx.systems = {&"population": pop}
	pop.setup(ctx)
	return ctx


func test_cpr_training_saves_some_lives() -> void:
	var plain := cohort_ctx({15: 1000}, 5, &"")
	var trained := cohort_ctx({15: 1000}, 5, &"cpr_training")
	run_months(plain, 1)
	run_months(trained, 1)
	var survivors_plain := plain.stats.cohorts[15] + plain.stats.cohorts[16]
	var survivors_trained := trained.stats.cohorts[15] + trained.stats.cohorts[16]
	check_lt(survivors_plain, 1000, "the frail elderly cohort loses people")
	check_gt(survivors_trained, survivors_plain, "CPR training saves some of them")


func test_junior_sports_teaches_children() -> void:
	var plain := cohort_ctx({0: 1000}, 5, &"")
	var sporty := cohort_ctx({0: 1000}, 5, &"junior_sports")
	run_months(plain, 1)
	run_months(sporty, 1)
	check_gt(plain.stats.cohorts[1], 0, "children age into the next cohort")
	check_eq(pop_of(sporty).cohort_education(1, sporty.stats)
		- pop_of(plain).cohort_education(1, plain.stats), PopulationParams.JUNIOR_SPORTS_EQ_GAIN)


func test_employment_counts_jobs_and_abandonment() -> void:
	var c := thousand_city()
	stamp_row(c, Buildings.COM_1X1_FIRST, Zones.COM_LOW, 5, 10, 30)
	for i in 3:
		c.stamp_building(10 + i * 3, 40, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	var ctx := make_ctx(c)
	run_months(ctx, 1)
	check_eq(ctx.stats.jobs, 50 + 3 * 360)
	check_eq(pop_of(ctx).commercial_units(), 50)
	check_eq(pop_of(ctx).industrial_units(), 1080)
	check_eq(ctx.stats.unemployment, 0)
	check_eq(ctx.stats.employment_rate, 100.0)
	stamp_row(c, Buildings.ABANDONED_1X1_A, Zones.RES_LOW, 50, 10, 60)
	run_months(ctx, 1)
	check_eq(pop_of(ctx).abandoned_units(), 50)
	check_eq(ctx.stats.unemployment, 33)
	check_eq(ctx.stats.employment_rate, 67.0)


func test_save_and_load_round_trip() -> void:
	var ctx := make_ctx(thousand_city())
	run_months(ctx, 24)
	var saved := pop_of(ctx).save()
	var json := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json)
	var restored := PopulationSystem.new()
	restored.load(parsed)
	check_eq(restored.save(), saved)
	check_eq(restored.residents(), 1000)
	for i in 20:
		check_eq(restored.cohort_education(i, ctx.stats), pop_of(ctx).cohort_education(i, ctx.stats), "cohort %d education" % i)
		check_eq(restored.cohort_health(i, ctx.stats), pop_of(ctx).cohort_health(i, ctx.stats), "cohort %d health" % i)
	# Both copies continue identically from the same random state.
	var twin := make_ctx(thousand_city())
	twin.stats.cohorts = ctx.stats.cohorts.duplicate()
	twin.stats.education_quotient = ctx.stats.education_quotient
	twin.stats.life_expectancy = ctx.stats.life_expectancy
	twin.systems[&"population"] = restored
	twin.rng.set_state(ctx.rng.state())
	run_months(ctx, 6)
	run_months(twin, 6)
	check_eq(twin.stats.cohorts, ctx.stats.cohorts)
	check_eq(twin.stats.education_quotient, ctx.stats.education_quotient)
	check_eq(twin.stats.life_expectancy, ctx.stats.life_expectancy)


func test_simulation_snapshot_restores_population_state() -> void:
	var sim := make_simulation(thousand_city())
	sim.advance_days(GameClock.DAYS_PER_MONTH)
	var system := sim.get_system(&"population")
	check(system != null, "population system registered")
	if system == null:
		return
	check_gt(sim.stats.population, 0)
	var snap := sim.snapshot()
	var copy := make_simulation(thousand_city())
	copy.restore(snap)
	check_eq(copy.get_system(&"population").save(), system.save())
	check_eq(copy.stats.cohorts, sim.stats.cohorts)
	root.remove_child(sim)
	root.remove_child(copy)
	sim.free()
	copy.free()


func test_untreated_water_costs_health_once_treatment_exists() -> void:
	var c := thousand_city()
	var ctx := make_ctx(c)
	var water := WaterSystem.new()
	ctx.systems[&"water"] = water
	water.setup(ctx)
	water.load({"treatment_adequate": false, "consumed": 500})
	ctx.stats.inventions[&"water_treatment"] = 1940
	ctx.clock.founded_year = 1900
	ctx.clock.day = 10
	check(not PopulationSystem._untreated_water(ctx), "no penalty before treatment is invented")
	ctx.clock.day = 50 * GameClock.DAYS_PER_YEAR
	check(PopulationSystem._untreated_water(ctx), "untreated water counts once plants can be built")
	water.load({"treatment_adequate": true, "consumed": 500})
	check(not PopulationSystem._untreated_water(ctx))
	ctx.systems.clear()


class FakeLinks extends SimSystem:
	func _init() -> void:
		key = &"neighbors"

	func link_count() -> int:
		return 4


func test_too_few_jobs_means_unemployment_and_commuting_helps() -> void:
	var homes_only := make_ctx(thousand_city())
	run_months(homes_only, 3)
	check_eq(homes_only.stats.jobs, 0)
	var workers := 0
	for i in range(PopulationParams.WORK_COHORT_MIN, PopulationParams.WORK_COHORT_MAX + 1):
		workers += homes_only.stats.cohorts[i]
	check_gt(workers, 0)
	check_eq(homes_only.stats.unemployment, 100, "a bedroom town with no jobs anywhere")
	var linked := make_ctx(thousand_city())
	linked.systems[&"neighbors"] = FakeLinks.new()
	run_months(linked, 3)
	check_lt(linked.stats.unemployment, homes_only.stats.unemployment,
		"road and rail links let residents commute to the neighbors")
	check_eq(PopulationSystem.job_shortfall_percent(linked.stats, 1000000), 0)
	linked.systems.clear()


func test_a_mass_departure_is_news_once() -> void:
	var ctx := cohort_ctx({5: 2000}, 5, &"")
	run_months(ctx, 1)
	var news := ctx.events.news.filter(func(n): return n["kind"] == &"exodus")
	check_eq(news.size(), 1, "a thousand people leaving a two-thousand town is news")
	if news.size() == 1:
		check_gt(int(news[0]["args"]["count"]), 0)
	run_months(ctx, 1)
	check(ctx.events.news.filter(func(n): return n["kind"] == &"exodus").is_empty(), "a settled town is quiet")
