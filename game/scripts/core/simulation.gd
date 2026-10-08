# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The simulation driver.
##
## Owns the city, the stats, the clock and the systems, advances time and turns
## queued events into signals. The UI talks to this node and nothing below it.
class_name Simulation
extends Node

signal day_advanced(year: int, month: int, day: int)
signal month_ended(year: int, month: int)
signal year_ended(year: int)
signal funds_changed(funds: int)
signal population_changed(population: int)
signal budget_review_due(year: int)
signal news_published(story: Dictionary)
signal notice_raised(kind: StringName, payload: Dictionary)
signal disaster_started(kind: StringName, center: Vector2i)
signal disaster_ended(kind: StringName)
signal map_changed(rect: Rect2i)
signal speed_changed(speed: int)

## Which systems run their monthly job on which day of the month. A key listed
## more than once gets a later phase number each time.
const SCHEDULE := {
	1: [&"power"],
	3: [&"water"],
	5: [&"zones"],
	6: [&"zones"],
	8: [&"transport"],
	10: [&"environment"],
	12: [&"services"],
	14: [&"population"],
	16: [&"economy"],
	18: [&"budget", &"ordinances", &"wear"],
	20: [&"disasters"],
	22: [&"statistics", &"casino", &"newspaper"],
	24: [&"neighbors"],
	25: [&"rewards", &"ports"],
}

## Registration order also decides the daily() call order.
const SYSTEM_SCRIPTS := [
	"res://scripts/sim/power_system.gd",
	"res://scripts/sim/water_system.gd",
	"res://scripts/sim/zone_system.gd",
	"res://scripts/sim/transport_system.gd",
	"res://scripts/sim/environment_system.gd",
	"res://scripts/sim/services_system.gd",
	"res://scripts/sim/population_system.gd",
	"res://scripts/sim/economy_system.gd",
	"res://scripts/sim/budget_system.gd",
	"res://scripts/sim/ordinance_system.gd",
	"res://scripts/sim/wear_system.gd",
	"res://scripts/sim/disaster_system.gd",
	"res://scripts/sim/statistics_system.gd",
	"res://scripts/sim/newspaper_system.gd",
	"res://scripts/sim/neighbor_system.gd",
	"res://scripts/sim/reward_system.gd",
	"res://scripts/sim/casino_system.gd",
	"res://scripts/sim/port_system.gd",
]

var city: City
var stats := CityStats.new()
var rng := SimRng.new()
var clock := GameClock.new()
var events := CityEvents.new()
var systems: Array[SimSystem] = []
var speed: int = GameClock.Speed.PAUSED:
	set(value):
		if value != speed:
			speed = value
			clock.speed = value
			speed_changed.emit(speed)

## Admission is bounded between atomic days; one day may exceed this budget.
const INTERACTIVE_BUDGET_USEC := 4000
const MAX_DAYS_PER_FRAME := 8

var budget_review_pending := false
var _system_index: Dictionary = {}
var _ctx := SimContext.new()
var _accumulator := 0.0
var _ready_to_run := false
var _last_population := -1
var _last_funds := -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Systems hold the context and the context holds the systems. Break the
		# cycle when this Node is freed so a replaced city can be released.
		_ctx.systems.clear()


func _process(delta: float) -> void:
	if not _ready_to_run or speed == GameClock.Speed.PAUSED or budget_review_pending:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	_accumulator += minf(delta, 0.25)
	var started := Time.get_ticks_usec()
	var guard := 0
	while guard < MAX_DAYS_PER_FRAME:
		# Signals emitted by a day can pause, change speed, or open a modal.
		if not _ready_to_run or speed == GameClock.Speed.PAUSED or budget_review_pending:
			break
		var per_day: float = GameClock.SECONDS_PER_DAY[speed]
		if _accumulator < per_day:
			break
		if guard > 0 and Time.get_ticks_usec() - started >= INTERACTIVE_BUDGET_USEC:
			break
		_accumulator -= per_day
		advance_day()
		guard += 1


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(new_city: City, seed_value: int = -1, restored_stats: CityStats = null, restored_snapshot: Dictionary = {}) -> void:
	_ready_to_run = false
	_accumulator = 0.0
	budget_review_pending = false
	city = new_city
	stats = restored_stats if restored_stats else CityStats.new()
	rng = SimRng.new(seed_value)
	clock = GameClock.new()
	clock.founded_year = city.founded_year
	clock.day = city.day
	clock.speed = speed
	events = CityEvents.new()
	_ctx = SimContext.new()
	_ctx.city = city
	_ctx.stats = stats
	_ctx.rng = rng
	_ctx.clock = clock
	_ctx.events = events
	_load_systems()
	var saved_systems: Dictionary = restored_snapshot.get("systems", {})
	for s in systems:
		if s is PowerSystem and saved_systems.has("power"):
			(s as PowerSystem).setup_from_save(_ctx, saved_systems["power"])
		else:
			s.setup(_ctx)
	_ready_to_run = true
	_last_population = -1
	_last_funds = -1
	_emit_scalars()


func _load_systems() -> void:
	systems.clear()
	_system_index.clear()
	for path in SYSTEM_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var script: Script = load(path)
		var instance: SimSystem = script.new()
		systems.append(instance)
		_system_index[instance.key] = instance
	_ctx.systems = _system_index


func get_system(system_key: StringName) -> SimSystem:
	return _system_index.get(system_key, null)


func set_speed(value: int) -> void:
	speed = clampi(value, GameClock.Speed.PAUSED, GameClock.Speed.FASTEST)


func toggle_pause() -> void:
	if speed == GameClock.Speed.PAUSED:
		set_speed(GameClock.Speed.SLOW)
	else:
		set_speed(GameClock.Speed.PAUSED)


# ── Time ─────────────────────────────────────────────────────────────────

## Run one simulated day. Safe to call directly from tests and tools.
func advance_day() -> void:
	if city == null or budget_review_pending:
		return
	events.clear()
	for s in systems:
		s.daily(_ctx)
	var dom := clock.day_of_month()
	var scheduled: Array = SCHEDULE.get(dom, [])
	for k in scheduled:
		var s: SimSystem = _system_index.get(k, null)
		if s == null:
			continue
		s.monthly(_ctx, _phase_of(k, dom))
	if clock.is_year_end():
		for s in systems:
			s.yearly(_ctx)
	_drain_events()
	var y := clock.year()
	var m := clock.month()
	var d := clock.day_of_month()
	day_advanced.emit(y, m, d)
	if clock.is_month_end():
		month_ended.emit(y, m)
	if clock.is_year_end():
		year_ended.emit(y)
		budget_review_pending = true
		budget_review_due.emit(y)
	clock.advance()
	city.day = clock.day
	_emit_scalars()


## The UI calls this when the player closes the January budget window.
func finish_budget_review() -> void:
	budget_review_pending = false


func advance_days(n: int) -> void:
	for _i in n:
		if budget_review_pending:
			finish_budget_review()
		advance_day()


func advance_months(n: int) -> void:
	advance_days(n * GameClock.DAYS_PER_MONTH)


func _phase_of(system_key: StringName, day_of_month: int) -> int:
	var phase := 0
	for d in SCHEDULE:
		if d >= day_of_month:
			break
		if system_key in SCHEDULE[d]:
			phase += 1
	return phase


# ── Player-driven changes ────────────────────────────────────────────────

## Tell the systems that construction changed the map inside `rect`.
func networks_changed(rect: Rect2i = Rect2i(0, 0, City.WIDTH, City.HEIGHT)) -> void:
	if city == null:
		return
	for s in systems:
		s.networks_changed(_ctx, rect)
	map_changed.emit(rect)
	_emit_scalars()


func request_disaster(kind: StringName, at: Vector2i = Vector2i(-1, -1)) -> bool:
	var d := get_system(&"disasters")
	if d == null or not d.has_method("request"):
		return false
	var ok: bool = d.call("request", _ctx, kind, at)
	_drain_events()
	return ok


## Apply a deliberately entered secret code, publish effects immediately even
## while paused, and leave the clock and ordinary simulation rules alone.
func redeem_cheat(code: String) -> Dictionary:
	var cheats := preload("res://scripts/core/cheat_codes.gd")
	var result: Dictionary = cheats.redeem(_ctx, code)
	if city != null:
		_emit_scalars()
		_drain_events()
	return result


## The casino system (treasury transactions and the play ledger).
func casino() -> CasinoSystem:
	return get_system(&"casino") as CasinoSystem


## Debit a casino round's stake from the treasury. Publishes the new balance
## immediately, even while paused. False when the system refuses it.
func casino_commit(resort: StringName, game: StringName, staked: int) -> bool:
	var system := casino()
	if system == null or city == null:
		return false
	var ok := system.commit_round(_ctx, resort, game, staked)
	_emit_scalars()
	_drain_events()
	return ok


## Credit what a settled round returned and record it in the ledger.
func casino_settle(resort: StringName, game: StringName, staked: int, returned: int) -> void:
	var system := casino()
	if system == null or city == null:
		return
	system.settle_round(_ctx, resort, game, staked, returned)
	_emit_scalars()
	_drain_events()


## Return a committed stake whose round was abandoned (the city is closing).
func casino_refund(resort: StringName, game: StringName, staked: int) -> void:
	var system := casino()
	if system == null or city == null:
		return
	system.refund_round(_ctx, resort, game, staked)
	_emit_scalars()
	_drain_events()


func adjust_funds(delta: int) -> void:
	city.funds += delta
	funds_changed.emit(city.funds)


# ── Events ───────────────────────────────────────────────────────────────

func _drain_events() -> void:
	var paper: SimSystem = _system_index.get(&"newspaper", null)
	if paper != null and paper.has_method("absorb"):
		paper.call("absorb", _ctx)
	for n in events.notices:
		notice_raised.emit(n.kind, n.payload)
	for story in events.news:
		news_published.emit(story)
		var kind: StringName = story.get("kind", &"")
		var args: Dictionary = story.get("args", {})
		if kind == &"disaster_started":
			disaster_started.emit(StringName(String(args.get("kind", ""))),
				Vector2i(int(args.get("x", -1)), int(args.get("y", -1))))
		elif kind == &"disaster_ended":
			disaster_ended.emit(StringName(String(args.get("kind", ""))))
	if events.map_dirty.size != Vector2i.ZERO:
		map_changed.emit(events.map_dirty)
	events.clear()


func _emit_scalars() -> void:
	if city == null:
		return
	if city.funds != _last_funds:
		_last_funds = city.funds
		funds_changed.emit(city.funds)
	var p := stats.total_population()
	if p != _last_population:
		_last_population = p
		population_changed.emit(p)


# ── Persistence ──────────────────────────────────────────────────────────

func snapshot() -> Dictionary:
	var sys := {}
	for s in systems:
		sys[String(s.key)] = s.save()
	return {
		"clock_day": clock.day,
		"speed": speed,
		# 64-bit values go through JSON as strings; doubles would round them.
		"rng_seed": str(rng.seed_value()),
		"rng_state": str(rng.state()),
		"budget_review_pending": budget_review_pending,
		"accumulator": _accumulator,
		"stats": stats.to_dict(),
		"systems": sys,
	}


func restore(data: Dictionary) -> void:
	var pending_seconds := float(data.get("accumulator", 0.0))
	_accumulator = pending_seconds if is_finite(pending_seconds) and pending_seconds >= 0.0 else 0.0
	clock.day = int(data.get("clock_day", city.day))
	city.day = clock.day
	rng = SimRng.from_saved_seed(int(String(str(data.get("rng_seed", "0")))))
	rng.set_state(int(String(str(data.get("rng_state", str(rng.state()))))))
	_ctx.rng = rng
	budget_review_pending = bool(data.get("budget_review_pending", false))
	if budget_review_pending and clock.is_year_end():
		# The automatic backup is written while the year-end day is still being
		# reported, before the clock moves on. That day has already run.
		clock.advance()
		city.day = clock.day
	if data.has("stats"):
		stats.from_dict(data["stats"])
	var sys: Dictionary = data.get("systems", {})
	for s in systems:
		if sys.has(String(s.key)):
			s.load(sys[String(s.key)])
	set_speed(int(data.get("speed", GameClock.Speed.PAUSED)))
	_emit_scalars()


func date_text() -> String:
	return clock.date_text()
