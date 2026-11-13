# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The military base proposal waits for a site instead of being spent on a
## city that has no room for one.
extends "res://tests/test_case.gd"

const RewardSystem := preload("res://scripts/sim/reward_system.gd")

var _contexts: Array[SimContext] = []
var _notices: Array[Dictionary] = []
var _news: Array[Dictionary] = []


func before_each() -> void:
	_notices.clear()
	_news.clear()


func after_each() -> void:
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func _context(c: City) -> SimContext:
	var ctx := make_context(c)
	_contexts.append(ctx)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


## A city with no usable ground anywhere: every tile is zoned.
func _full_city() -> City:
	var c := flat_city()
	for y in City.HEIGHT:
		for x in City.WIDTH:
			c.zone.put(x, y, Zones.make(Zones.RES_LOW))
	return c


func _clear_ground(c: City) -> void:
	for y in City.HEIGHT:
		for x in City.WIDTH:
			c.zone.put(x, y, 0)


func _month(ctx: SimContext, rewards: RewardSystem) -> void:
	ctx.events.clear()
	rewards.daily(ctx)
	rewards.monthly(ctx, 0)
	for n in ctx.events.notices:
		_notices.append(n)
	for n in ctx.events.news:
		_news.append(n)


func _military_offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for notice in _notices:
		if notice.kind == &"reward_offered" and notice.payload.get("key", &"") == RewardParams.MILITARY_KEY:
			out.append(notice.payload)
	return out


func _milestone_stories() -> int:
	var n := 0
	for story in _news:
		if story.kind == &"city_milestone" and story.args.get("key", &"") == RewardParams.MILITARY_KEY:
			n += 1
	return n


func _reached(c: City) -> Array:
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	rewards.setup(ctx)
	for gift: StringName in [&"mayors_residence", &"city_hall", &"monument"]:
		ctx.stats.rewards_offered[gift] = true
	ctx.stats.population = 26000
	return [ctx, rewards]


func test_no_site_makes_no_offer_and_keeps_the_reward() -> void:
	var c := _full_city()
	var pair := _reached(c)
	var ctx: SimContext = pair[0]
	var rewards: RewardSystem = pair[1]
	for _i in 3:
		_month(ctx, rewards)
	check_eq(_military_offers().size(), 0, "no proposal without a site")
	check_eq(_milestone_stories(), 0, "no story about a base nobody can site")
	var offer := rewards.military_offer()
	check(not bool(offer.pending), "nothing to answer")
	check(not bool(offer.answered), "the one-time proposal is not spent")
	check(not rewards.accept_military(), "nothing to accept")
	check(bool(offer.searching), "the search continues")
	check_eq(Toolbar.reward_lock_reason(Tools.Kind.REWARD_MILITARY_BASE, "not yet offered to the city", rewards),
		"the military has not found a site for a base yet")
	check_eq(c.zone.count(Zones.make(Zones.MILITARY)), 0)


func test_offer_arrives_once_a_site_exists() -> void:
	var c := _full_city()
	var pair := _reached(c)
	var ctx: SimContext = pair[0]
	var rewards: RewardSystem = pair[1]
	_month(ctx, rewards)
	check_eq(_military_offers().size(), 0)
	_clear_ground(c)
	_month(ctx, rewards)
	var offers := _military_offers()
	check_eq(offers.size(), 1, "proposed in a later month")
	if offers.size() == 1:
		check_ne(StringName(offers[0].kind), &"none", "a real kind of base")
		var site: Array = offers[0].site
		check_eq(int(site[2]), RewardParams.MILITARY_SITE_SIZE, "a real site")
	check_eq(_milestone_stories(), 1, "the story runs with the proposal")
	check(bool(rewards.military_offer().pending))
	_month(ctx, rewards)
	check_eq(_military_offers().size(), 1, "proposed once")
	check(rewards.accept_military(), "the base can be accepted")
	check_gt(c.zone.count(Zones.make(Zones.MILITARY)), 0)


func test_later_milestones_are_not_held_up() -> void:
	var c := _full_city()
	var pair := _reached(c)
	var ctx: SimContext = pair[0]
	var rewards: RewardSystem = pair[1]
	ctx.stats.population = 45000
	_month(ctx, rewards)
	_month(ctx, rewards)
	var domes := 0
	for notice in _notices:
		if notice.kind == &"reward_offered" and notice.payload.get("key", &"") == &"neon_dome":
			domes += 1
	check_eq(domes, 1, "the next gift is still offered")
	check_eq(_military_offers().size(), 0)


func test_saved_wait_survives_a_reload() -> void:
	var c := _full_city()
	var pair := _reached(c)
	var ctx: SimContext = pair[0]
	var rewards: RewardSystem = pair[1]
	_month(ctx, rewards)
	check_eq(_military_offers().size(), 0, "no proposal without a site")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rewards.save()))
	var again := RewardSystem.new()
	again.setup(ctx)
	again.load(saved)
	_clear_ground(c)
	_month(ctx, again)
	check_eq(_military_offers().size(), 1, "the wait continues after loading")


## Earlier versions spent the proposal when no site was found.
func test_proposal_spent_without_a_site_is_offered_again() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var rewards := RewardSystem.new()
	rewards.setup(ctx)
	for milestone in RewardParams.MILESTONES:
		ctx.stats.rewards_offered[milestone.key] = true
	ctx.stats.population = 60000
	rewards.load({"milestones_passed": RewardParams.MILESTONES.size(),
		"military": {"kind": "none", "answered": true, "accepted": false, "site": [0, 0, 0, 0], "sites": []}})
	_month(ctx, rewards)
	check_eq(_military_offers().size(), 1, "offered now that a site exists")
	check(bool(rewards.military_offer().pending))


func test_declined_base_is_not_offered_again() -> void:
	var c := flat_city()
	var pair := _reached(c)
	var ctx: SimContext = pair[0]
	var rewards: RewardSystem = pair[1]
	_month(ctx, rewards)
	check_eq(_military_offers().size(), 1)
	rewards.decline_military()
	for _i in 3:
		_month(ctx, rewards)
	check_eq(_military_offers().size(), 1, "a refusal is final")
