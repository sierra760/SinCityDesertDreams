# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Political consequences of settled gambling losses during one resort visit.
## Persisted by CasinoSystem; the recall's draw never consumes the city's RNG.
class_name MayoralRecall
extends RefCounted

const DELAY := 6 * GameClock.DAYS_PER_MONTH
## Percentage points; the election-day swing is uniform and inclusive.
const LUCK_SWING := 15
var visit_resort: StringName = &""
var entry_funds := 0
var visit_loss := 0
var visit_prosecuted := false
var due_day := -1
var next_update := -1
var dismissed := false
var result: Dictionary = {}
var _rng := SimRng.new(0)

func setup(ctx: SimContext) -> void:
	_rng = SimRng.from_saved_seed(ctx.rng.seed_value() ^ 0x524543414c4c)

func begin_visit(ctx: SimContext, resort: StringName) -> void:
	if dismissed or not ResortThemes.has(resort): return
	# A new doorway cannot silently replace an unfinished saved visit.
	if visit_resort != &"": end_visit(ctx)
	visit_resort = resort
	entry_funds = maxi(0, ctx.city.funds)
	visit_loss = 0
	visit_prosecuted = false

## A temporary loss only warns. The final net loss is judged at departure.
func end_visit(ctx: SimContext) -> void:
	if not dismissed and due_day < 0 and not visit_prosecuted and _at_risk():
		due_day = ctx.clock.day + DELAY
		next_update = ctx.clock.day + GameClock.DAYS_PER_MONTH
		result = {}
		var args := _args(ctx)
		args["place"] = ResortThemes.resort_name(visit_resort)
		args["amount"] = visit_loss
		args["entry_funds"] = entry_funds
		ctx.events.report(&"recall_called", args)
	visit_resort = &""
	entry_funds = 0
	visit_loss = 0
	visit_prosecuted = false

func _at_risk() -> bool:
	return visit_resort != &"" and entry_funds > 0 and visit_loss > entry_funds / 2

func settle(ctx: SimContext, resort: StringName, stake: int, paid: int) -> void:
	if dismissed or resort != visit_resort or visit_resort == &"": return
	var was_at_risk := _at_risk()
	visit_loss += stake - paid
	if not was_at_risk and _at_risk() and not visit_prosecuted:
		ctx.events.notify(&"recall_warning", {"entry_funds": entry_funds, "loss": visit_loss})

## Run after the day's systems, so March's approval vote is already current.
func advance(ctx: SimContext) -> void:
	if dismissed or due_day < 0: return
	if ctx.clock.day >= due_day:
		var approval := clampi(ctx.stats.approval, 0, 100)
		var base_chance := 100 - approval
		var luck := _rng.range_int(-LUCK_SWING, LUCK_SWING)
		var chance := clampi(base_chance + luck, 0, 100)
		var roll := _rng.below(100)
		dismissed = roll < chance
		result = {"day": ctx.clock.day, "approval": approval, "base_chance": base_chance,
			"luck": luck, "chance": chance,
			"roll": roll, "removed": dismissed, "date": _date(due_day, ctx.clock.founded_year)}
		due_day = -1
		next_update = -1
		# Any visit during the campaign is covered by this election too.
		if visit_resort != &"": visit_prosecuted = true
		ctx.events.report(&"recall_removed" if dismissed else &"recall_survived", result.duplicate())
	elif ctx.clock.day >= next_update:
		ctx.events.report(&"recall_update", _args(ctx))
		# The first monthly step after today, however far behind the update is.
		@warning_ignore("integer_division")
		next_update += ((ctx.clock.day - next_update) / GameClock.DAYS_PER_MONTH + 1) * GameClock.DAYS_PER_MONTH

func _args(ctx: SimContext) -> Dictionary:
	var approval := clampi(ctx.stats.approval, 0, 100)
	return {"date": _date(due_day, ctx.clock.founded_year), "approval": approval,
		"chance": 100 - approval, "luck_limit": LUCK_SWING, "months": maxi(1, ceili(float(due_day - ctx.clock.day) / GameClock.DAYS_PER_MONTH))}

static func _date(day: int, founded_year: int) -> String:
	var clock := GameClock.new()
	clock.day = day
	clock.founded_year = founded_year
	return "%s %d, %d" % [GameClock.MONTH_NAMES[clock.month() - 1], clock.day_of_month(), clock.year()]

func save() -> Dictionary:
	return {"visit_resort": String(visit_resort), "entry_funds": entry_funds, "visit_loss": visit_loss,
		"visit_prosecuted": visit_prosecuted, "due_day": due_day, "next_update": next_update,
		"dismissed": dismissed, "result": result.duplicate(true), "rng_state": str(_rng.state())}

func load(data: Dictionary) -> void:
	visit_resort = StringName(String(data.get("visit_resort", "")))
	if not ResortThemes.has(visit_resort): visit_resort = &""
	entry_funds = maxi(0, int(data.get("entry_funds", 0)))
	visit_loss = int(data.get("visit_loss", 0))
	visit_prosecuted = bool(data.get("visit_prosecuted", false))
	due_day = maxi(-1, int(data.get("due_day", -1)))
	next_update = int(data.get("next_update", due_day))
	# Updates run from the day the recall was called to election day.
	next_update = clampi(next_update, due_day - DELAY, due_day) if due_day >= 0 else -1
	dismissed = bool(data.get("dismissed", false))
	result = (data.get("result", {}) as Dictionary).duplicate(true)
	# JSON numbers arrive as floats; retain the resolved election's integer fields.
	for field in ["day", "approval", "base_chance", "luck", "chance", "roll"]:
		if result.has(field): result[field] = int(result[field])
	if data.has("rng_state"): _rng.set_state(int(str(data.rng_state)))
