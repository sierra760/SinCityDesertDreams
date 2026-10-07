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
## offer, arcology intake and the exodus. The systems are driven directly
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
	for s in systems:
		var sys: SimSystem = s
		sys.setup(ctx)
		ctx.systems[sys.key] = sys


## Run whole days the way the simulation schedules them: daily, then the
## day-25 monthly job, then the year-end job. Notices and news are collected.
func _run_days(ctx: SimContext, systems: Array, days: int) -> void:
	for _i in days:
		ctx.events.clear()
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


func _serve(c: City, x: int, y: int) -> void:
	c.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)


# ── Milestones and gifts ─────────────────────────────────────────────────

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
	ctx.stats.population = 40000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_MONTH)
	check_eq(rewards.available(), [&"mayors_residence"], "first month offers only the first prize")
	_run_days(ctx, [rewards], 2 * GameClock.DAYS_PER_MONTH)
	check_eq(rewards.available(), [&"mayors_residence", &"city_hall", &"monument"])
	_run_days(ctx, [rewards], 2 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 0, "60,000 not reached")
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
	c.founded_year = 1990
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	check(not rewards.arcology_available(&"arcology_comstock"), "not before its year")
	check_eq(rewards.available_arcologies(), [])
	ctx.clock.day = 10 * GameClock.DAYS_PER_YEAR
	check(rewards.arcology_available(&"arcology_comstock"))
	check(not rewards.arcology_available(&"arcology_junction"))
	ctx.stats.inventions[&"arcology_junction"] = 1995
	check(rewards.arcology_available(&"arcology_junction"), "the economy's invention year wins")
	check_eq(rewards.available_arcologies(), [&"arcology_comstock", &"arcology_junction"])
	check(not rewards.arcology_available(&"city_hall"), "only arcology keys")


func test_powered_arcology_fills() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_COMSTOCK)
	_serve(c, 10, 10)
	ctx.stats.population = 100000
	rewards.networks_changed(ctx, Rect2i(10, 10, 4, 4))
	var report := rewards.arcology_report()
	check_eq(report.size(), 1)
	check_eq(report[0].key, &"arcology_comstock")
	check_eq(report[0].capacity, 55000)
	check_eq(report[0].residents, 0, "new arcologies start empty")
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	report = rewards.arcology_report()
	var first := int(report[0].residents)
	check_gt(first, 0, "residents move in after a served year")
	check_lt(first, 55000 / RewardParams.INTAKE_CAPACITY_SHARE + RewardParams.INTAKE_JITTER, "intake is capped")
	check_eq(ctx.stats.arcology_population, first)
	check_gt(int(report[0].condition), 0)
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	report = rewards.arcology_report()
	check_gt(int(report[0].residents), first, "and keep coming")
	check_ge(int(report[0].pollution), 0)
	var rec := c.facility(Vector2i(10, 10))
	check_eq(int(rec.residents), int(report[0].residents), "state lives in the facility record")


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
	ctx.stats.population = 200000
	ctx.stats.tax_residential = 20
	ctx.stats.tax_commercial = 20
	ctx.stats.tax_industrial = 20
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	var taxed := int(rewards.arcology_report()[0].residents)
	var c2 := flat_city()
	var ctx2 := _context(c2)
	var rewards2 := RewardSystem.new()
	_register(ctx2, [rewards2])
	c2.stamp_building(10, 10, Buildings.ARCOLOGY_ORBIT)
	_serve(c2, 10, 10)
	ctx2.stats.population = 200000
	_run_days(ctx2, [rewards2], GameClock.DAYS_PER_YEAR)
	var untaxed := int(rewards2.arcology_report()[0].residents)
	check_lt(taxed, untaxed, "a heavy tax burden deters residents")


func test_demolished_arcology_leaves_the_census() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	_register(ctx, [rewards])
	c.stamp_building(10, 10, Buildings.ARCOLOGY_COMSTOCK)
	_serve(c, 10, 10)
	ctx.stats.population = 100000
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	check_gt(ctx.stats.arcology_population, 0)
	c.clear_footprint(10, 10)
	rewards.networks_changed(ctx, Rect2i(10, 10, 4, 4))
	check_eq(ctx.stats.arcology_population, 0)
	check_eq(rewards.arcology_report().size(), 0)


func test_exodus_launches_the_orbit_fleet() -> void:
	var c := flat_city()
	c.founded_year = RewardParams.LAUNCH_YEAR
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
	c.stamp_building(100, 100, Buildings.ARCOLOGY_COMSTOCK)
	rewards.networks_changed(ctx, Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	var inhabited := 0
	for anchor in c.facilities:
		var rec: Dictionary = c.facilities[anchor]
		if rec.key == &"arcology_orbit" and inhabited < 10:
			rec["residents"] = 1000
			inhabited += 1
	rewards.networks_changed(ctx, Rect2i())
	check_eq(ctx.stats.arcology_population, 10000)
	var funds_before := c.funds
	_run_days(ctx, [rewards], GameClock.DAYS_PER_YEAR)
	var exodus := 0
	for notice in _notices:
		if notice.kind == &"exodus":
			exodus += 1
			check_eq(int(notice.payload.resorts), RewardParams.LAUNCH_COUNT)
			check_eq(int(notice.payload.residents), 10000)
	check_eq(exodus, 1, "one exodus notice")
	check_eq(c.building.count(Buildings.ARCOLOGY_ORBIT), 0, "the fleet is gone")
	check(Buildings.is_rubble(c.building_at(0, 0)), "launch sites are rubble")
	check_eq(c.building_at(100, 100), Buildings.ARCOLOGY_COMSTOCK, "other designs stay")
	check_eq(c.funds, funds_before + 10 * RewardParams.LAUNCH_REFUND, "compensation for inhabited arcologies")
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
	var saved := rewards.save()
	var text := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(text)
	var c2 := c.duplicate_city()
	c2.facilities.clear()
	var ctx2 := _context(c2)
	ctx2.stats.from_dict(ctx.stats.to_dict())
	ctx2.clock.day = ctx.clock.day
	var restored := RewardSystem.new()
	_register(ctx2, [restored])
	restored.load(parsed)
	check_eq(restored.available(), rewards.available())
	check_eq(restored.military_offer(), rewards.military_offer())
	check_eq(restored.military_kind(), &"army")
	check_eq(restored.arcology_report(), rewards.arcology_report())
	check_eq(ctx2.stats.arcology_population, ctx.stats.arcology_population)
	check_gt(ctx2.stats.arcology_population, 0)
	_run_days(ctx2, [restored], 6 * GameClock.DAYS_PER_MONTH)
	check_eq(_offers(&"military_base"), 1, "restored state does not repeat the offer")
