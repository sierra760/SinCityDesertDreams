# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const RESORT := &"arcology_comstock"
var sim: Simulation

func before_each() -> void:
	sim = make_simulation(flat_city(20000), 7)

func after_each() -> void:
	sim.free()

func recall() -> Variant:
	var value: Variant = sim.casino().get("recall")
	check(value != null, "casino owns persistent recall rules")
	return value

func lose(stake: int, returned: int = 0) -> void:
	check(sim.casino_commit(RESORT, &"blackjack", stake))
	sim.casino_settle(RESORT, &"blackjack", stake, returned)

## Seed 0 draws luck +11, seed 1 draws -4. Endpoint fixtures deliberately
## choose a guaranteed result; separate tests cover surprise outcomes.
func seed_recall(seed: int) -> void:
	var saved := sim.casino().recall.save()
	saved.rng_state = str(SimRng.new(seed).state())
	sim.casino().recall.load(saved)

func test_strict_half_threshold_and_unsettled_refunds() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	check(sim.casino_commit(RESORT, &"blackjack", 11000))
	check_eq(r.due_day, -1, "a held stake is not a loss")
	sim.casino_refund(RESORT, &"blackjack", 11000)
	lose(10000)
	check_eq(r.due_day, -1, "exactly half is safe")
	lose(1)
	check_eq(r.due_day, 150)
	check_eq(r.entry_funds, 20000)
	check_eq(r.visit_loss, 10001)

func test_winnings_offset_losses_and_city_expenses_do_not_count() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	lose(1000, 6000)
	sim.adjust_funds(-3000)
	lose(15000)
	check_eq(r.due_day, -1)
	lose(1)
	check_eq(r.due_day, 150)

func test_odd_baseline_and_nonpositive_entry() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.city.funds = 101
	sim.casino_begin_visit(RESORT)
	lose(50)
	check_eq(r.due_day, -1)
	lose(1)
	check_eq(r.due_day, 150)
	sim.casino_end_visit()
	r.load({})
	sim.city.funds = 0
	sim.casino_begin_visit(RESORT)
	sim.adjust_funds(100)
	lose(100)
	check_eq(r.due_day, -1)

func test_only_active_resort_and_one_pending_date() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	check(sim.casino_commit(&"arcology_orbit", &"blackjack", 11000))
	sim.casino_settle(&"arcology_orbit", &"blackjack", 11000, 0)
	check_eq(r.due_day, -1)
	sim.city.funds = 20000
	lose(11000)
	var due: int = r.due_day
	sim.casino_end_visit()
	sim.clock.day = 20
	sim.casino_begin_visit(RESORT)
	lose(5000)
	check_eq(r.due_day, due, "later loss cannot postpone election")

func test_exact_six_month_date_across_year_and_current_approval() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.clock.day = 223
	sim.city.day = 223
	sim.casino_begin_visit(RESORT)
	lose(11000)
	check_eq(r.due_day, 373)
	sim.stats.approval = 0
	seed_recall(0)
	sim.clock.day = 372
	sim.city.day = 372
	sim.advance_day()
	check(r.result.is_empty(), "not on the day before election")
	sim.stats.approval = 100
	seed_recall(1)
	sim.advance_day()
	check(not r.dismissed)
	check_eq(int(r.result.approval), 100)
	check_eq(int(r.result.chance), 0)
	check_eq(int(r.result.day), 373)

func test_dismissal_stops_direct_days_and_bets() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	lose(11000)
	sim.clock.day = 150
	sim.city.day = 150
	sim.stats.approval = 0
	seed_recall(0)
	sim.advance_day()
	check(sim.is_mayor_dismissed())
	var day := sim.city.day
	sim.advance_days(10)
	check_eq(sim.city.day, day)
	check(not sim.casino_commit(RESORT, &"blackjack", 100))
	check_eq(int(r.result.chance), 100)

func test_save_restore_preserves_campaign_rng_and_old_saves() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	lose(11000)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var city_data := SaveFormat.encode_city(sim.city)
	check_eq(SaveFormat.validate_snapshot(snapshot), "")
	var saved_rng := str(snapshot.systems.casino.recall.rng_state)
	sim.clock.day = 150
	sim.city.day = 150
	sim.stats.approval = 63
	sim.advance_day()
	var first: Dictionary = r.result.duplicate(true)
	sim.setup(SaveFormat.decode_city(city_data).city, 7, null, snapshot)
	check_eq(sim.restore(snapshot), OK)
	r = sim.casino().recall
	check_eq(str(sim.snapshot().systems.casino.recall.rng_state), saved_rng)
	sim.clock.day = 150
	sim.city.day = 150
	sim.stats.approval = 63
	sim.advance_day()
	check_eq(r.result, first, "reloading before vote cannot reroll")
	var old := snapshot.duplicate(true)
	old.systems.casino.erase("recall")
	sim.setup(SaveFormat.decode_city(city_data).city, 7, null, old)
	check_eq(sim.restore(old), OK)
	r = sim.casino().recall
	check_eq(r.due_day, -1)
	check(not r.dismissed)

func test_campaign_reports_once_and_fresh_visit_after_survival() -> void:
	var r: Variant = recall()
	if r == null: return
	var reports: Array = []
	sim.news_published.connect(func(story: Dictionary) -> void:
		if String(story.kind).begins_with("recall_"): reports.append(story.kind))
	sim.casino_begin_visit(RESORT)
	lose(11000)
	check_eq(reports.count(&"recall_called"), 1)
	for day in [25, 50, 75, 100, 125, 150]:
		sim.clock.day = day
		sim.city.day = day
		sim.stats.approval = 100
		seed_recall(1)
		sim.advance_day()
	check_eq(reports.count(&"recall_update"), 5)
	check_eq(reports.count(&"recall_survived"), 1)
	lose(1)
	check_eq(r.due_day, -1, "old prosecuted visit cannot retrigger")
	sim.casino_end_visit()
	sim.casino_begin_visit(RESORT)
	lose(sim.city.funds / 2 + 1)
	check_eq(r.due_day, 301)

func test_urgent_paper_prints_call_and_result_even_after_another_extra() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.events.report(&"disaster_started", {"kind":"fire"})
	sim._drain_events()
	sim.casino_begin_visit(RESORT)
	lose(11000)
	var paper: SimSystem = sim.get_system(&"newspaper")
	var issue: Dictionary = paper.call("latest_issue")
	check_eq(String(issue.stories[0].kind), "recall_called")
	var body := String(issue.stories[0].body)
	check(body.contains("$20,000") and body.contains("$11,000"), "paper explains both amounts")
	check(not body.contains("{"), "all placeholders resolve")
	sim.clock.day = 150
	sim.city.day = 150
	sim.stats.approval = 0
	seed_recall(0)
	sim.events.report(&"disaster_started", {"kind":"fire"})
	sim._drain_events()
	sim.advance_day()
	issue = paper.call("latest_issue")
	check_eq(String(issue.stories[0].kind), "recall_removed")
	check(String(issue.stories[0].body).contains("100%"))
	check(String(issue.stories[0].body).contains("luck"),"result explains how luck changed the base odds")

func test_monthly_campaign_updates_print_current_odds_immediately() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	lose(11000)
	for day in [25,50,75,100,125]:
		sim.clock.day = day
		sim.city.day = day
		sim.stats.approval = 80 - day / 5
		sim.advance_day()
		var issue: Dictionary = sim.get_system(&"newspaper").call("latest_issue")
		check_eq(int(issue.month), day / 25 + 1)
		check_eq(String(issue.stories[0].kind), "recall_update")
		var remaining: int = 6 - day / 25
		var unit := "Month" if remaining == 1 else "Months"
		check_eq(String(issue.stories[0].headline), "Recall Countdown: %d %s Until The Vote" % [remaining, unit])
		check(String(issue.stories[0].body).contains("%d%%" % sim.stats.approval))
		check(String(issue.stories[0].body).contains("luck") and String(issue.stories[0].body).contains("15"),"campaign explains the election-day swing")

func test_election_draw_uses_own_saved_rng_at_intermediate_approval() -> void:
	var r: Variant = recall()
	if r == null: return
	var ctx := SimContext.new()
	ctx.city = sim.city
	ctx.stats = sim.stats
	ctx.clock = sim.clock
	ctx.events = CityEvents.new()
	ctx.rng = sim.rng
	var simulation_state := sim.rng.state()
	for seed in range(10):
		var draw := SimRng.new(seed)
		var initial := str(draw.state())
		var luck := draw.range_int(-15,15)
		var roll := draw.below(100)
		r.load({"due_day":0,"rng_state":initial})
		ctx.stats.approval = 70
		r.advance(ctx)
		check_eq(int(r.result.roll), roll)
		check_eq(int(r.result.get("base_chance", -1)),30)
		check_eq(int(r.result.get("luck", -99)),luck)
		check_eq(int(r.result.chance),30+luck)
		check_eq(r.dismissed, roll < 30+luck)
		var kind := &"recall_removed" if r.dismissed else &"recall_survived"
		var values := NewsStories.values_for(kind,r.result,ctx.city.name,ctx.city.mayor,ctx.clock.year())
		var body := NewsStories.body(kind,r.result,values)
		check(body.contains("at 30%"),"result reports approval-based odds")
		check(body.contains("%+d percentage points" % luck),"result reports signed luck swing")
		check(body.contains("chance was %d%%" % (30+luck)),"result reports final odds")
		check(not body.contains("{"),"result placeholders resolve")
	check_eq(sim.rng.state(), simulation_state, "recall draw never consumes city RNG")
	for row in [[-1,"-1 percentage point."],[0,"+0 percentage points."],[1,"+1 percentage point."],[15,"+15 percentage points."]]:
		var args := {"luck":int(row[0])}
		var values := NewsStories.values_for(&"recall_removed",args,"Test City","Mayor",1900)
		check(NewsStories.body(&"recall_removed",args,values).contains(row[1]),"luck units use the correct singular or plural")


func test_march_vote_finishes_before_recall_reads_approval() -> void:
	var r: Variant = recall()
	if r == null: return
	# March 14 is the scheduled population/approval vote; at least 100 residents vote.
	sim.city.stamp_building(20,20,Buildings.RES_3X3_FIRST,Zones.RES_HIGH)
	sim.clock.day = 63
	sim.city.day = 63
	sim.stats.approval = 101
	r.load({"due_day":63})
	sim.advance_day()
	check_between(sim.stats.approval,0,100)
	check_eq(int(r.result.approval),sim.stats.approval)

func test_luck_changes_odds_in_both_directions_and_clamps_extremes() -> void:
	var r: Variant = recall()
	if r == null: return
	var ctx := SimContext.new()
	ctx.city = sim.city
	ctx.stats = sim.stats
	ctx.clock = sim.clock
	ctx.events = CityEvents.new()
	ctx.rng = sim.rng
	var seen: Dictionary = {}
	var popular_surprise := false
	var unpopular_surprise := false
	for approval in [0,50,100]:
		for seed in 1024:
			r.load({"due_day":0,"rng_state":str(SimRng.new(seed).state())})
			ctx.stats.approval = approval
			r.advance(ctx)
			check(r.result.has("luck"),"election records its separate luck draw")
			if not r.result.has("luck"): return
			var luck := int(r.result.luck)
			check_between(luck,-15,15)
			check_eq(int(r.result.base_chance),100-approval)
			check_eq(int(r.result.chance),clampi(100-approval+luck,0,100))
			check_eq(r.dismissed,int(r.result.roll)<int(r.result.chance))
			if approval == 50: seen[luck] = true
			if approval == 100 and r.dismissed: popular_surprise = true
			if approval == 0 and not r.dismissed: unpopular_surprise = true
	check_eq(seen.size(),31,"all 31 integer luck swings occur")
	check(popular_surprise,"even full approval can lose after an unlucky swing")
	check(unpopular_surprise,"even zero approval can survive a lucky swing")

func test_resolved_luck_and_roll_survive_json_restore_without_another_draw() -> void:
	var r: Variant = recall()
	if r == null: return
	sim.casino_begin_visit(RESORT)
	lose(11000)
	sim.clock.day = 150
	sim.city.day = 150
	sim.stats.approval = 70
	sim.advance_day()
	check(r.result.has("luck"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(r.save()))
	var result: Dictionary = r.result.duplicate(true)
	var rng_state: String = saved.rng_state
	r.load(saved)
	sim.advance_day()
	check_eq(r.result,result)
	check_eq(str(r.save().rng_state),rng_state,"a resolved recall never draws again")
