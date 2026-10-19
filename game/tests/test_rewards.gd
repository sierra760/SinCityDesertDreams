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

## Behavior tests for the rewards system: milestones, gifts, the military
## offer, tourism compatibility and the exodus. The systems are driven directly
## through a hand-built context so the checks do not depend on other systems.

const RewardSystem := preload("res://scripts/sim/reward_system.gd")
const PortSystem := preload("res://scripts/sim/port_system.gd")

var _notices: Array[Dictionary] = []
var _news: Array[Dictionary] = []


func before_each() -> void:
	_notices.clear()
	_news.clear()


func _context(c: City, seed_value: int = 7) -> SimContext:
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


func _register(ctx: SimContext, systems: Array) -> void:
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	for s in systems:
		var sys: SimSystem = s
		sys.setup(ctx)
		ctx.systems[sys.key] = sys
	tourism.finish_restore({})


## Run whole days the way the simulation schedules them: daily, then the
## day-25 monthly job, then the year-end job. Notices and news are collected.
func _run_days(ctx: SimContext, systems: Array, days: int) -> void:
	for _i in days:
		ctx.events.clear()
		var tourism := ctx.system(&"tourism") as TourismSystem
		tourism.daily(ctx)
		if ctx.clock.day_of_month() == 17:
			tourism.monthly(ctx)
		if ctx.clock.day_of_month() == 18:
			tourism.acknowledge_booking(ctx.clock.day / GameClock.DAYS_PER_MONTH)
		for s in systems:
			var sys: SimSystem = s
			sys.daily(ctx)
		if ctx.clock.day_of_month() == GameClock.DAYS_PER_MONTH:
			for s in systems:
				var sys: SimSystem = s
				sys.monthly(ctx, 0)
		if ctx.clock.is_year_end():
			for s in systems:
				var sys: SimSystem = s
				sys.yearly(ctx)
		for n in ctx.events.notices:
			_notices.append(n)
		for n in ctx.events.news:
			_news.append(n)
		ctx.clock.advance()
		ctx.city.day = ctx.clock.day


func _offers(gift_key: StringName) -> int:
	var n := 0
	for notice in _notices:
		if notice.kind == &"reward_offered" and notice.payload.get("key", &"") == gift_key:
			n += 1
	return n


func _count_zone(c: City, kind: int) -> int:
	var n := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if c.zone_kind_at(x, y) == kind:
				n += 1
	return n


## Visitors arrive through a regional gateway, so the frontage road runs
## beside the lot up to the north map edge (docs/simulation/tourism.md).
func _serve(c: City, x: int, y: int) -> void:
	TourismFixture.set_served(c, Vector2i(x, y), true, true)
	for row in range(y + 1):
		c.building.put(x - 1, row, Buildings.ROAD_FIRST)


## Ordinary residents of working age staff the resorts; tourism shares this
## resident labor pool (docs/simulation/tourism.md), so the synthetic
## population is given matching workers.
func _populate(ctx: SimContext, residents: int) -> void:
	ctx.stats.population = residents
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = residents


# ── Milestones and gifts ─────────────────────────────────────────────────

## Each threshold is tested through the actual offer/news path, with the prior
## progress restored as an existing save would be. Visitors cannot earn gifts.
func test_resident_targets_unlock_at_the_boundary_even_after_restore() -> void:
	var milestones := [[&"mayors_residence", 2000], [&"city_hall", 10000],
		[&"monument", 15000], [&"military_base", 25000], [&"neon_dome", 40000]]
	for index in milestones.size():
		var gift_key: StringName = milestones[index][0]
		var target: int = milestones[index][1]
		var ctx := _context(flat_city())
		for prior in index:
			ctx.stats.rewards_offered[milestones[prior][0]] = true
		var rewards := RewardSystem.new()
		_register(ctx, [rewards])
		rewards.load({"milestones_passed": index})
		ctx.stats.population = target - 1
		ctx.stats.tourists = 100000
		rewards.monthly(ctx)
		check(not ctx.stats.rewards_offered.get(gift_key, false), String(gift_key) + " waits for residents")
		check(ctx.events.notices.is_empty(), "tourists do not satisfy the milestone")
		ctx.stats.population = target
		rewards.monthly(ctx)
		check(ctx.stats.rewards_offered.get(gift_key, false), String(gift_key) + " unlocks at the target")
		check_eq(ctx.events.notices.size(), 1, "one reward notice at the boundary")
		if not ctx.events.notices.is_empty():
			check_eq(ctx.events.notices[0].payload.key, gift_key)
		check_eq(ctx.events.news.size(), 1, "one milestone story")
		if not ctx.events.news.is_empty():
			check_eq(ctx.events.news[0].args, {"key": gift_key, "population": target})
		ctx.events.clear()
		ctx.stats.population = 0
		rewards.monthly(ctx)
		check(ctx.stats.rewards_offered.get(gift_key, false), "a later population fall keeps the reward earned")
		check(ctx.events.notices.is_empty(), "an earned reward is never offered twice")


func test_existing_city_receives_lowered_rewards_in_order_without_repeats() -> void:
	var ctx := _context(flat_city())
	ctx.stats.population = 40000
	ctx.stats.rewards_offered = {&"mayors_residence": true, &"city_hall": true}
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	rewards.load({"milestones_passed": 2})
	for gift_key: StringName in [&"monument", &"military_base", &"neon_dome"]:
		ctx.events.clear()
		rewards.monthly(ctx)
		check_eq(ctx.events.notices.size(), 1, "one new reward per month")
		if not ctx.events.notices.is_empty():
			check_eq(ctx.events.notices[0].payload.key, gift_key)
	var saved := rewards.save()
	var restored := RewardSystem.new()
	_register(ctx, [restored])
	restored.load(saved)
	ctx.events.clear()
	restored.monthly(ctx)
	check(ctx.events.notices.is_empty(), "restoring earned progress does not repeat any offer")
	check_eq(restored.available(), [&"mayors_residence", &"city_hall", &"monument", &"neon_dome"])


func test_milestones_offer_rewards_once() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	ctx.stats.population = 2500
	_run_days(ctx, [rewards], 3 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"mayors_residence"), 1, "residence offered exactly once")
	check_eq(_offers(&"city_hall"), 0, "city hall needs more people")
	check(ctx.stats.rewards_offered.get(&"mayors_residence", false))
	check_eq(rewards.available(), [&"mayors_residence"])
	ctx.stats.population = 12000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"city_hall"), 1)
	check_eq(rewards.available(), [&"mayors_residence", &"city_hall"])
	var milestones := 0
	for story in _news:
		if story.kind == &"city_milestone":
			milestones += 1
	check_eq(milestones, 2, "one story per milestone")


func test_milestones_pass_in_order_one_per_month() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	ctx.stats.population = 20000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(rewards.available(), [&"mayors_residence"], "first month offers only the first prize")
	_run_days(ctx, [rewards], 2 * GameClock.DAYS_PER_MONTH)
	check_eq(rewards.available(), [&"mayors_residence", &"city_hall", &"monument"])
	_run_days(ctx, [rewards], 2 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 0, "25,000 not reached")
	check_eq(_offers(&"monument"), 1)


func test_gift_built_and_demolished() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	ctx.stats.population = 3000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(rewards.available(), [&"mayors_residence"])
	rewards.mark_built(&"mayors_residence")
	check_eq(rewards.available(), [], "marked gifts are no longer available")
	c.stamp_building(20, 20, Buildings.MAYORS_RESIDENCE)
	rewards.networks_changed(ctx, Rect2i(20, 20, 2, 2))
	check(ctx.stats.rewards_built.get(&"mayors_residence", false))
	c.clear_footprint(20, 20)
	rewards.networks_changed(ctx, Rect2i(20, 20, 2, 2))
	check_eq(rewards.available(), [&"mayors_residence"], "demolition makes the gift available again")
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"mayors_residence"), 1, "still offered only once")


func test_standing_gifts_are_already_earned_without_repeat_notices() -> void:
	var c := flat_city()
	for gift in [Buildings.MAYORS_RESIDENCE, Buildings.CITY_HALL, Buildings.MONUMENT, Buildings.NEON_DOME]:
		c.stamp_building(gift % 100, 20, gift)
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	for gift_key in [&"mayors_residence", &"city_hall", &"monument", &"neon_dome"]:
		check(ctx.stats.rewards_offered.get(gift_key, false), "standing %s was already earned" % gift_key)
		check(ctx.stats.rewards_built.get(gift_key, false))
	check_eq(rewards.available(), [])
	ctx.stats.population = 130000
	_run_days(ctx, [rewards], 8 * GameClock.DAYS_PER_MONTH)
	for gift_key in [&"mayors_residence", &"city_hall", &"monument", &"neon_dome"]:
		check_eq(_offers(gift_key), 0, "standing %s is not offered again" % gift_key)
	for story in _news:
		if story.kind == &"city_milestone":
			check_eq(story.args.key, &"military_base", "existing gifts do not create new milestone stories")


func test_existing_later_gifts_do_not_skip_missing_earlier_rewards() -> void:
	var c := flat_city()
	c.stamp_building(20, 20, Buildings.CITY_HALL)
	c.stamp_building(40, 40, Buildings.NEON_DOME)
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	ctx.stats.population = 130000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"mayors_residence"), 1)
	check_eq(_offers(&"monument"), 0, "only one missing reward is offered per month")
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"monument"), 1, "known city hall does not delay the next missing gift")
	_run_days(ctx, [rewards], 4 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"city_hall"), 0)
	check_eq(_offers(&"neon_dome"), 0)
	check_eq(_offers(&"military_base"), 1)
	check_eq(rewards.available(), [&"mayors_residence", &"monument"])


func test_existing_gift_replacement_waits_until_last_copy_is_demolished() -> void:
	var c := flat_city()
	c.stamp_building(20, 20, Buildings.CITY_HALL)
	c.stamp_building(40, 40, Buildings.CITY_HALL)
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.clear_footprint(20, 20)
	rewards.networks_changed(ctx, Rect2i(20, 20, 3, 3))
	check_eq(rewards.available(), [], "another copy still stands")
	c.clear_footprint(40, 40)
	rewards.networks_changed(ctx, Rect2i(40, 40, 3, 3))
	check_eq(rewards.available(), [&"city_hall"], "imported gift remains earned below its population threshold")
	ctx.stats.population = 12000
	_run_days(ctx, [rewards], 4 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"mayors_residence"), 1)
	check_eq(_offers(&"city_hall"), 0, "replacement needs no new milestone notice")


func test_load_repairs_legacy_reward_flags_from_standing_buildings() -> void:
	var c := flat_city()
	c.stamp_building(20, 20, Buildings.CITY_HALL)
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	# Simulation restores stats after system setup; old imported saves may lack
	# both reward dictionaries and the system's seen-standing history.
	ctx.stats.from_dict({"rewards_offered": {}, "rewards_built": {}})
	rewards.load({"milestones_passed": 0, "seen_standing": []})
	check(ctx.stats.rewards_offered.get(&"city_hall", false))
	check(ctx.stats.rewards_built.get(&"city_hall", false))
	c.clear_footprint(20, 20)
	rewards.networks_changed(ctx, Rect2i(20, 20, 3, 3))
	check_eq(rewards.available(), [&"city_hall"], "reload retains demolition tracking")


func test_monthly_detects_existing_gift_before_its_offer() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	# A restored/imported layer can be replaced without a construction signal.
	c.stamp_building(20, 20, Buildings.MAYORS_RESIDENCE)
	ctx.stats.population = 3000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"mayors_residence"), 0)
	check(ctx.stats.rewards_offered.get(&"mayors_residence", false))


func test_existing_military_zone_or_unique_piece_prevents_second_proposal() -> void:
	for piece in [Buildings.NONE, Buildings.MISSILE_SILO]:
		_notices.clear()
		_news.clear()
		var c := flat_city()
		if piece == Buildings.NONE:
			c.zone.put(20, 20, Zones.make(Zones.MILITARY, Zones.CORNER_NW))
		else:
			c.stamp_building(20, 20, piece)
		var ctx := _context(c)
		var rewards := RewardSystem.new()
		_register(ctx, [rewards])
		ctx.stats.population = 130000
		_run_days(ctx, [rewards], 8 * GameClock.DAYS_PER_MONTH)
		check_eq(_offers(&"military_base"), 0)
		check(ctx.stats.rewards_offered.get(&"military_base", false))
		check(ctx.stats.rewards_built.get(&"military_base", false), "existing base stays unavailable in the reward toolbar")
		check(not rewards.military_offer().pending)
		check_eq(_offers(&"neon_dome"), 1, "an existing base does not swallow later missing gifts")


func test_civilian_airport_does_not_consume_military_reward() -> void:
	var c := flat_city()
	c.stamp_building(20, 20, Buildings.RUNWAY, Zones.AIRPORT)
	c.stamp_building(25, 25, Buildings.HANGAR_SMALL, Zones.AIRPORT)
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	_reach_military(ctx, rewards)
	check_eq(_offers(&"military_base"), 1)
	check(rewards.military_offer().pending)


func test_restored_pending_proposal_is_closed_when_base_already_exists() -> void:
	var c := flat_city()
	c.zone.put(20, 20, Zones.make(Zones.MILITARY))
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	rewards.load({"military": {"kind": "army", "answered": false, "accepted": false}})
	check(not rewards.military_offer().pending, "map ownership overrides a stale saved proposal")
	check(rewards.military_offer().answered)
	ctx.stats.rewards_offered.clear()
	rewards.networks_changed(ctx, Rect2i())
	check(ctx.stats.rewards_offered.get(&"military_base", false), "a consumed base remains earned")


# ── Military base ────────────────────────────────────────────────────────

func _reach_military(ctx: SimContext, rewards: SimSystem) -> void:
	ctx.stats.population = 65000
	_run_days(ctx, [rewards], 4 * GameClock.DAYS_PER_MONTH)


## The per-tile scans the native lookups replace, kept as the reference.
static func _reference_military(city: City) -> bool:
	for code in city.zone.data:
		if Zones.kind(code) == Zones.MILITARY:
			return true
	for id in Buildings.COUNT:
		if Buildings.category(id) == Buildings.Category.MILITARY and city.building.data.has(id):
			return true
	return false


@warning_ignore("integer_division")
static func _reference_anchors(city: City) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in city.building.data.size():
		var id := city.building.data[i]
		if id >= Buildings.ARCOLOGY_COMSTOCK and id <= Buildings.ARCOLOGY_ORBIT \
				and city.zone.data[i] & Zones.CORNER_NW:
			out.append(Vector2i(i % City.WIDTH, i / City.WIDTH))
	return out


func test_map_lookups_match_the_tile_scans() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for trial in 24:
		var c := flat_city()
		# Arcologies of every design in scattered order, some overlapping.
		for _n in rng.randi_range(0, 6):
			var id := rng.randi_range(Buildings.ARCOLOGY_COMSTOCK, Buildings.ARCOLOGY_ORBIT)
			c.stamp_building(rng.randi_range(0, City.WIDTH - 5), rng.randi_range(0, City.HEIGHT - 5), id, Zones.NONE)
		# Stray arcology tiles without a north-west corner.
		for _n in rng.randi_range(0, 4):
			c.building.put(rng.randi_range(0, City.WIDTH - 1), rng.randi_range(0, City.HEIGHT - 1), Buildings.ARCOLOGY_JUNCTION)
		if trial % 3 == 1:
			c.zone.put(rng.randi_range(0, City.WIDTH - 1), rng.randi_range(0, City.HEIGHT - 1),
				(rng.randi_range(0, 15) << 4) | Zones.MILITARY)
		elif trial % 3 == 2:
			var military := RewardSystem._military_ids()
			c.building.put(rng.randi_range(0, City.WIDTH - 1), rng.randi_range(0, City.HEIGHT - 1),
				military[rng.randi_range(0, military.size() - 1)])
		check_eq(RewardSystem._arcology_anchors(c), _reference_anchors(c), "anchors in map order")
		check_eq(RewardSystem._has_military_base(c), _reference_military(c), "military base detection")
		check_eq(RewardSystem._has_military_base(c), trial % 3 != 0)

func test_military_offer_is_proposed_once() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	_reach_military(ctx, rewards)
	check_eq(_offers(&"military_base"), 1)
	var offer := rewards.military_offer()
	check(offer.pending, "offer waits for an answer")
	check_eq(offer.kind, &"army", "a flat empty map yields an army base")
	check_eq(offer.site.size, Vector2i(RewardParams.MILITARY_SITE_SIZE, RewardParams.MILITARY_SITE_SIZE))
	check(not rewards.available().has(&"military_base"), "the base is not a placeable gift")
	_run_days(ctx, [rewards], 3 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 1, "not offered again while pending")
	check_eq(rewards.military_kind(), &"", "no base until accepted")


func test_military_accept_zones_and_develops() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	var ports := PortSystem.new()
	_register(ctx, [rewards, ports])
	_reach_military(ctx, rewards)
	var offer := rewards.military_offer()
	var site: Rect2i = offer.site
	check(rewards.accept_military())
	check_eq(_count_zone(c, Zones.MILITARY), site.size.x * site.size.y, "the whole site is zoned")
	check_eq(rewards.military_kind(), &"army")
	check(not rewards.military_offer().pending)
	check(not rewards.accept_military(), "a second answer is refused")
	_run_days(ctx, [rewards, ports], 1)
	var reported := false
	for story in _news:
		if story.kind == &"military_base" and story.args.accepted:
			reported = true
	check(reported, "acceptance is reported")
	_run_days(ctx, [rewards, ports], 30 * GameClock.DAYS_PER_MONTH)
	var pieces := 0
	var military_pieces := 0
	for y in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			var id := c.building_at(x, y)
			if id == Buildings.NONE:
				continue
			pieces += 1
			if Buildings.category(id) == Buildings.Category.MILITARY:
				military_pieces += 1
	check_gt(pieces, 0, "the base develops on its own without power")
	check_gt(military_pieces, 0, "an army base grows motor pools")
	var report := ports.port_report()
	check_eq(report.size(), 1)
	check_eq(report[0].kind, Zones.MILITARY)
	check(report[0].operating)
	check_gt(ports.jobs(), 0, "the base provides jobs")
	check_gt(int(report[0].crime), 0, "and brings crime")


func test_military_decline_is_final() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	_reach_military(ctx, rewards)
	rewards.decline_military()
	check(not rewards.military_offer().pending)
	check(not rewards.accept_military(), "cannot accept after declining")
	check_eq(_count_zone(c, Zones.MILITARY), 0)
	_run_days(ctx, [rewards], 6 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 1, "never offered again")


func test_military_accept_custom_rect_skips_occupied_ground() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	_reach_military(ctx, rewards)
	c.stamp_building(52, 52, Buildings.COAL_PLANT)
	check(rewards.accept_military(Rect2i(50, 50, 8, 8)))
	check_eq(_count_zone(c, Zones.MILITARY), 64 - 16, "the plant's footprint is left alone")
	check_eq(c.zone_kind_at(53, 53), Zones.NONE)


# ── Arcologies ───────────────────────────────────────────────────────────

func test_arcology_availability_by_year() -> void:
	var c := flat_city()
	c.founded_year = 1940
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	var neighborhood: Array[StringName] = [&"arcology_boddy", &"arcology_woolier", &"arcology_stockgrowers", &"arcology_fremont"]
	var fifties: Array[StringName] = [&"arcology_comstock", &"arcology_junction", &"arcology_boulder", &"arcology_fix", &"arcology_alibi", &"arcology_velvet"]
	var millennium: Array[StringName] = [&"arcology_orbit", &"arcology_afterglow", &"arcology_last", &"arcology_dust"]
	check(not rewards.arcology_available(&"arcology_comstock"), "not before its batch")
	check_eq(rewards.available_arcologies(), neighborhood, "only the neighborhood resorts at founding")
	ctx.clock.day = 10 * GameClock.DAYS_PER_YEAR
	var open: Array[StringName] = []
	open.assign(rewards.available_arcologies())
	check_eq(open, [&"arcology_comstock", &"arcology_junction", &"arcology_boulder", &"arcology_fix", &"arcology_alibi", &"arcology_velvet", &"arcology_boddy", &"arcology_woolier", &"arcology_stockgrowers", &"arcology_fremont"], "the 1950s batch opens together")
	check(not rewards.arcology_available(&"city_hall"), "only arcology keys")
	ctx.stats.inventions[&"resorts_midcentury"] = 1957
	for key in fifties:
		check(not rewards.arcology_available(key), "%s follows the economy's 1950s year" % key)
	ctx.clock.day = 17 * GameClock.DAYS_PER_YEAR
	for key in fifties:
		check(rewards.arcology_available(key), "%s opens in the rolled 1950s year" % key)
	for key in millennium:
		check(not rewards.arcology_available(key), "%s waits for 2000" % key)
	ctx.stats.inventions[&"resorts_millennium"] = 2000
	ctx.clock.day = 59 * GameClock.DAYS_PER_YEAR
	for key in millennium:
		check(not rewards.arcology_available(key), "%s is still closed in 1999" % key)
	ctx.clock.day = 60 * GameClock.DAYS_PER_YEAR
	for key in millennium:
		check(rewards.arcology_available(key), "%s opens in 2000" % key)


func test_powered_resort_fills_with_tourists_only() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_COMSTOCK)
	_serve(c, 10, 10)
	_populate(ctx, 100000)
	var tourism := ctx.system(&"tourism") as TourismSystem
	tourism.reconcile_now()
	check_eq(rewards.arcology_report()[0].tourists, 0)
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	var report := rewards.arcology_report()[0]
	check_gt(report.guests, 0, "monthly guests arrive")
	check_eq(report.capacity, TourismParams.guest_capacity(&"arcology_comstock"))
	check_eq(report.residents, report.tourists, "deprecated alias means tourists")
	check_eq(ctx.stats.arcology_population, 0)
	check_eq(ctx.stats.total_population(), 100000)
	check(not c.facility(Vector2i(10, 10)).has("residents"))
	var previous := tourism.save()
	var rng_before := ctx.rng.state()
	rewards.yearly(ctx)
	check_eq(tourism.save(), previous, "annual reward processing never grows attendance")
	check_eq(ctx.rng.state(), rng_before, "annual resort growth no longer consumes shared RNG")


func test_unpowered_arcology_stays_empty() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_JUNCTION)
	c.stamp_building(30, 30, Buildings.ARCOLOGY_BOULDER)
	c.set_flag(30, 30, TileFlags.POWERED, true)
	ctx.stats.population = 100000
	_run_days(ctx, [rewards], 2 * GameClock.DAYS_PER_YEAR)
	for entry in rewards.arcology_report():
		check_eq(int(entry.residents), 0, "%s without full service stays empty" % entry.key)
	check_eq(ctx.stats.arcology_population, 0)


func test_high_taxes_slow_intake() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_ORBIT)
	_serve(c, 10, 10)
	_populate(ctx, 200000)
	ctx.stats.tax_occupancy = 20
	ctx.stats.tax_gaming = 20
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	var taxed := int(rewards.arcology_report()[0].residents)
	var c2 := flat_city()
	var ctx2 := _context(c2)
	var rewards2 := RewardSystem.new()
	_register(ctx2, [rewards2])
	c2.stamp_building(10, 10, Buildings.ARCOLOGY_ORBIT)
	_serve(c2, 10, 10)
	_populate(ctx2, 200000)
	_run_days(ctx2, [rewards2], GameClock.DAYS_PER_YEAR)
	var untaxed := int(rewards2.arcology_report()[0].residents)
	check_lt(taxed, untaxed, "visitor taxes deter tourists")


func test_demolished_arcology_leaves_the_census() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_COMSTOCK)
	_serve(c, 10, 10)
	_populate(ctx, 100000)
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	check_gt(ctx.stats.tourists, 0)
	c.clear_footprint(10, 10)
	rewards.networks_changed(ctx, Rect2i(10, 10, 4, 4))
	(ctx.system(&"tourism") as TourismSystem).reconcile_now()
	check_eq(ctx.stats.tourists, 0)
	check_eq(rewards.arcology_report().size(), 0)


func test_orbit_departure_preserves_resident_population_and_refund() -> void:
	var c := flat_city()
	c.founded_year = RewardParams.LAUNCH_YEAR
	for i in RewardParams.LAUNCH_COUNT:
		var a := Vector2i((i % 25) * 5, (i / 25) * 5)
		c.stamp_building(a.x, a.y, Buildings.ARCOLOGY_ORBIT)
		TourismFixture.set_served(c, a, true, true)
		c.stamp_building(a.x + 4, a.y, Buildings.ROAD_FIRST)
		if i < 10:
			c.add_facility(a, {"key": &"arcology_orbit", "residents": 1000})
	c.stamp_building(100, 100, Buildings.ARCOLOGY_COMSTOCK)
	var ctx := _context(c)
	ctx.stats.population = 1234
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	check_eq(ctx.stats.tourists, 10000)
	var funds_before := c.funds
	rewards.yearly(ctx)
	check_eq(ctx.events.notices.size(), 1)
	var notice: Dictionary = ctx.events.notices[0]
	check_eq(notice.kind, &"exodus")
	check_eq(notice.payload.resorts, RewardParams.LAUNCH_COUNT)
	check_eq(notice.payload.tourists, 10000)
	check_eq(notice.payload.residents, 10000, "event compatibility alias preserved")
	check_eq(c.building.count(Buildings.ARCOLOGY_ORBIT), 0)
	check(Buildings.is_rubble(c.building_at(0, 0)))
	check_eq(c.building_at(100, 100), Buildings.ARCOLOGY_COMSTOCK)
	check_eq(c.funds, funds_before + 10 * RewardParams.LAUNCH_REFUND)
	check_eq(ctx.stats.population, 1234)
	check_eq(ctx.stats.tourists, 0)
	check_eq(ctx.stats.arcology_population, 0)
	check_eq(rewards.arcology_report().size(), 1)


func test_no_exodus_before_launch_year() -> void:
	var c := flat_city()
	c.founded_year = RewardParams.LAUNCH_YEAR - 5
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	var placed := 0
	var y := 0
	while placed < RewardParams.LAUNCH_COUNT:
		for x in range(0, City.WIDTH - 3, 4):
			if placed >= RewardParams.LAUNCH_COUNT:
				break
			c.stamp_building(x, y, Buildings.ARCOLOGY_ORBIT)
			placed += 1
		y += 4
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	check_eq(c.building.count(Buildings.ARCOLOGY_ORBIT), RewardParams.LAUNCH_COUNT * 16, "too early to launch")


# ── Persistence ──────────────────────────────────────────────────────────

func test_save_load_round_trip() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_COMSTOCK)
	_serve(c, 10, 10)
	_reach_military(ctx, rewards)
	check(rewards.accept_military())
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	rewards.mark_built(&"city_hall")
	var tourism_saved := ctx.system(&"tourism").save()
	var saved := rewards.save()
	var text := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(text)
	var c2 := c.duplicate_city()
	var ctx2 := _context(c2)
	ctx2.stats.from_dict(ctx.stats.to_dict())
	ctx2.clock.day = ctx.clock.day
	var restored := RewardSystem.new()
	_register(ctx2, [restored])
	restored.load(parsed)
	# This rewards-only clock explicitly acknowledges every completed period in
	# _run_days; restoration must include that booking identity as well.
	check_eq((ctx2.system(&"tourism") as TourismSystem).finish_restore({"systems": {
		"tourism": tourism_saved, "budget": {"tourism_booked_month": tourism_saved.last_month}}}), OK)
	check_eq(restored.available(), rewards.available())
	check_eq(restored.military_offer(), rewards.military_offer())
	check_eq(restored.military_kind(), &"army")
	check_eq(restored.arcology_report(), rewards.arcology_report())
	check_eq(ctx2.stats.arcology_population, ctx.stats.arcology_population)
	check_gt(ctx2.stats.tourists, 0)
	_run_days(ctx2, [restored], 6 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 1, "restored state does not repeat the offer")


func test_all_six_new_resorts_join_tourist_reports() -> void:
	var city := flat_city()
	var ctx := _context(city)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	var capacities := [3200, 1400, 2200, 5000, 600, 950]
	for i in 6:
		city.stamp_building(12 + i * 5, 12, 256 + i)
		_serve(city, 12 + i * 5, 12)
	_populate(ctx, 200000)
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	var reports := rewards.arcology_report()
	check_eq(reports.size(), 6)
	for i in mini(6, reports.size()):
		check_eq(reports[i].capacity, capacities[i])
		check_gt(reports[i].residents, 0, "served new resorts admit tourists")
	check_gt(ctx.stats.tourists, 0)

func test_orbit_departure_copy_describes_tourists() -> void:
	var notice := NoticeLines.render(&"exodus", {"tourists": 42, "residents": 42}, "Test City", "Mayor", 2250)
	check(String(notice.body).contains("42 tourists"))
	for headline: String in NewsStories.STORIES[&"resort_launch"].headlines:
		check(not headline.to_lower().contains("resident"), "departure headline describes tourists")
