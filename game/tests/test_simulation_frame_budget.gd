# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _simulation() -> Simulation:
	var sim := make_simulation(flat_city())
	sim.set_process(false)
	# These tests isolate admission; exact whole-system comparison is recorded
	# separately by the real-city fixed-work profile.
	sim.systems.clear()
	sim._system_index.clear()
	sim.set_speed(GameClock.Speed.FASTEST)
	return sim

func test_expensive_day_yields_and_keeps_backlog() -> void:
	var sim := _simulation()
	sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: OS.delay_usec(6000))
	sim._process(0.25)
	check_eq(sim.city.day, 1, "an expensive atomic day prevents admission of another day")
	check(is_equal_approx(sim._accumulator, 0.17), "unspent elapsed time remains queued")
	sim._process(0.0)
	check_eq(sim.city.day, 2, "retained backlog advances without new elapsed time")
	sim._ctx.systems.clear()
	sim.free()

func test_pause_and_speed_changes_during_day_take_effect_before_next_day() -> void:
	for next_speed: int in [GameClock.Speed.PAUSED, GameClock.Speed.SLOW]:
		var sim := _simulation()
		sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: sim.set_speed(next_speed), CONNECT_ONE_SHOT)
		sim._process(0.25)
		check_eq(sim.city.day, 1, "callback speed change stops admission using stale per-day interval")
		check(is_equal_approx(sim._accumulator, 0.17), "speed change preserves queued seconds")
		sim._ctx.systems.clear()
		sim.free()

func test_pending_review_and_paused_frames_preserve_elapsed_backlog() -> void:
	var sim := _simulation()
	sim.clock.day = 299
	sim.city.day = 299
	sim._process(0.25)
	check_eq(sim.city.day, 300)
	check(sim.budget_review_pending)
	var queued := sim._accumulator
	sim._process(1.0)
	check_eq(sim._accumulator, queued, "modal hold neither spends nor accumulates time")
	sim.finish_budget_review()
	sim.set_speed(GameClock.Speed.PAUSED)
	sim._process(1.0)
	check_eq(sim._accumulator, queued, "pause neither spends nor accumulates time")
	sim._ctx.systems.clear()
	sim.free()

func test_backlog_survives_json_save_and_legacy_defaults_cleanly() -> void:
	var sim := _simulation()
	sim._accumulator = 0.173125
	sim.budget_review_pending = true
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var restored := _simulation()
	restored.restore(saved)
	check(is_equal_approx(restored._accumulator, 0.173125), "save/reload retains pending wall-clock seconds")
	check(restored.budget_review_pending)
	saved.erase("accumulator")
	restored.restore(saved)
	check_eq(restored._accumulator, 0.0, "legacy snapshots have no inherited backlog")
	for bad: float in [-2.0, INF, NAN]:
		saved["accumulator"] = bad
		restored.restore(saved)
		check_eq(restored._accumulator, 0.0, "invalid saved backlog is discarded")
	restored._accumulator = 3.0
	restored.setup(flat_city(), 12345)
	check_eq(restored._accumulator, 0.0, "new city discards previous city backlog")
	check(not restored.budget_review_pending, "new city discards old review hold")
	sim._ctx.systems.clear()
	sim.free()
	restored._ctx.systems.clear()
	restored.free()

func test_invalid_delta_does_not_poison_clock() -> void:
	var sim := _simulation()
	sim._accumulator = 0.04
	for delta: float in [-1.0, NAN, INF]:
		sim._process(delta)
		check_eq(sim.city.day, 0, "invalid elapsed time admits no days")
		check_eq(sim._accumulator, 0.04, "invalid elapsed time leaves backlog intact")
	sim._ctx.systems.clear()
	sim.free()

func test_free_releases_system_context_graph() -> void:
	var sim := make_simulation(flat_city())
	sim.set_process(false)
	var port_owner: WeakRef = weakref(sim.get_system(&"ports"))
	var context: WeakRef = weakref(sim._ctx)
	sim.free()
	check(port_owner.get_ref() == null, "free releases owners retaining the shared context")
	check(context.get_ref() == null, "free releases shared context after the owner table")

func test_real_pending_backlog_reload_matches_exact_direct_work() -> void:
	var source_city := flat_city()
	source_city.stamp_building(10, 10, Buildings.COAL_PLANT)
	source_city.stamp_building(14, 10, Buildings.RES_2X2_FIRST, Zones.RES_HIGH)
	var sim := make_simulation(source_city, 742)
	sim.set_process(false)
	sim.set_speed(GameClock.Speed.FASTEST)
	sim._accumulator = 17 * 0.08 + 0.001
	var initial := sim.snapshot()
	var direct := make_simulation(source_city.duplicate_city(), 742)
	direct.set_process(false)
	direct.restore(initial)
	direct._accumulator = 0.0
	var expected_days: Array = []
	var actual_days: Array = []
	direct.day_advanced.connect(func(y: int, m: int, d: int) -> void: expected_days.append([y, m, d]))
	direct.advance_days(17)
	# Save after a real atomic day with the remaining admission backlog intact.
	sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: sim.set_speed(GameClock.Speed.PAUSED), CONNECT_ONE_SHOT)
	sim._process(0.0)
	check_eq(sim.city.day, 1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var resumed := Simulation.new()
	root.add_child(resumed)
	resumed.set_process(false)
	resumed.setup(sim.city.duplicate_city(), 742, null, saved)
	resumed.restore(saved)
	resumed.set_speed(GameClock.Speed.FASTEST)
	actual_days.append([1900, 1, 1])
	resumed.day_advanced.connect(func(y: int, m: int, d: int) -> void: actual_days.append([y, m, d]))
	for frame: int in 30:
		resumed._process(0.0)
		if resumed.city.day == 17:
			break
	check_eq(resumed.city.day, 17, "all saved pending work completes")
	check_eq(actual_days, expected_days, "same ordered day signal boundaries")
	check_eq(SaveFormat.encode_city(resumed.city), SaveFormat.encode_city(direct.city), "all city fields exactly equal direct work")
	var resumed_snapshot := resumed.snapshot()
	var direct_snapshot := direct.snapshot()
	resumed_snapshot.erase("accumulator")
	direct_snapshot.erase("accumulator")
	check_eq(resumed_snapshot, direct_snapshot, "systems, stats, clock and RNG exactly equal")
	check(is_equal_approx(resumed._accumulator, 0.001), "fractional backlog survives continuation")
	sim.free()
	direct.free()
	resumed.free()
