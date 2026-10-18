# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

class ClockOnlyTourism extends TourismSystem:
	func reconcile_now() -> void: pass
	func finish_restore(_snapshot: Dictionary) -> Error: return OK


func _admission() -> Simulation:
	var sim := make_simulation(flat_city())
	sim.set_process(false)
	sim.systems.clear()
	sim._system_index.clear()
	sim._system_index[&"tourism"] = ClockOnlyTourism.new()
	sim.set_speed(GameClock.Speed.FASTEST)
	return sim


func test_fastest_admits_days_without_elapsed_debt_and_caps_each_frame() -> void:
	for delta: float in [0.0, 1.0 / 60.0]:
		var sim := _admission()
		for frame in 3:
			var before := sim.city.day
			sim._process(delta)
			check_between(sim.city.day - before, 1, 8, "each frame advances without exceeding the eight-day cap")
			check_eq(sim._accumulator, 0.0, "unpaced frames do not manufacture wall-clock debt")
		sim.free()


func test_fastest_preserves_existing_backlog_and_yields_after_heavy_atomic_day() -> void:
	var sim := _admission()
	sim._accumulator = 0.173125
	sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: OS.delay_usec(6000))
	for frame in 3:
		sim._process(0.25)
		check_eq(sim.city.day, frame + 1, "the four-millisecond budget is checked between atomic days")
		check_eq(sim._accumulator, 0.173125, "fastest neither adds nor consumes saved debt")
	sim.free()


func test_pause_modal_and_year_review_stop_unpaced_admission() -> void:
	for stop in ["pause", "modal", "year"]:
		var sim := _admission()
		sim._accumulator = 0.173125
		if stop == "year":
			sim.clock.day = 299
			sim.city.day = 299
		else:
			sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void:
				if stop == "pause": sim.set_speed(GameClock.Speed.PAUSED)
				else: sim.budget_review_pending = true
			, CONNECT_ONE_SHOT)
		sim._process(0.0)
		var stopped_day := 300 if stop == "year" else 1
		check_eq(sim.city.day, stopped_day, stop + " blocks the next day")
		sim._process(0.25)
		check_eq(sim.city.day, stopped_day, stop + " continues holding")
		check_eq(sim._accumulator, 0.173125, stop + " preserves debt")
		if stop != "pause": check(sim.budget_review_pending, stop)
		sim.free()


func test_speed_changes_apply_before_next_atomic_day() -> void:
	var interval: float = GameClock.SECONDS_PER_DAY[GameClock.Speed.FAST]
	var slow := _admission()
	slow._accumulator = 0.173125
	slow.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: slow.set_speed(GameClock.Speed.SLOW), CONNECT_ONE_SHOT)
	slow._process(0.25)
	check_eq(slow.city.day, 1, "switching to Slow immediately reinstates its interval")
	check_eq(slow._accumulator, 0.173125, "a frame that began unpaced adds no elapsed debt")
	slow.free()
	var paced := _admission()
	paced.set_speed(GameClock.Speed.FAST)
	paced._accumulator = interval
	paced.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: paced.set_speed(GameClock.Speed.FASTEST), CONNECT_ONE_SHOT)
	paced._process(0.0)
	check_between(paced.city.day, 2, 8, "switching to Fastest admits more cheap days without debt")
	check_eq(paced._accumulator, 0.0)
	paced.free()
	var debt := _admission()
	debt._accumulator = 2.0 * interval
	debt.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: debt.set_speed(GameClock.Speed.FAST), CONNECT_ONE_SHOT)
	debt._process(0.25)
	check_eq(debt.city.day, 3, "new paced speed may spend previously saved debt")
	check(is_zero_approx(debt._accumulator), "exactly two paced days consume the old debt")
	debt.free()


func test_paced_speeds_use_the_faster_intervals() -> void:
	for choice: Array in [[GameClock.Speed.SLOW, 0.8], [GameClock.Speed.MEDIUM, 0.32], [GameClock.Speed.FAST, 0.08]]:
		var sim := _admission()
		sim.set_speed(choice[0])
		sim._accumulator = float(choice[1]) - 0.001
		sim._process(0.0)
		check_eq(sim.city.day, 0, "paced days still wait for their interval")
		sim._process(0.002)
		check_eq(sim.city.day, 1, "paced interval is " + str(choice[1]) + " seconds")
		check(is_equal_approx(sim._accumulator, 0.001), "only one interval is spent")
		sim.free()


func test_invalid_delta_is_rejected_even_at_fastest() -> void:
	var sim := _admission()
	sim._accumulator = 0.173125
	for delta: float in [-1.0, INF, NAN]:
		sim._process(delta)
		check_eq(sim.city.day, 0)
		check_eq(sim._accumulator, 0.173125)
	sim.free()


func test_json_resume_keeps_fastest_review_hold_and_saved_debt() -> void:
	var sim := _admission()
	sim.clock.day = 299
	sim.city.day = 299
	sim._accumulator = 0.173125
	sim._process(0.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var restored := _admission()
	check_eq(restored.restore(saved), OK)
	check_eq(restored.speed, GameClock.Speed.FASTEST)
	check_eq(restored.city.day, 300)
	check(restored.budget_review_pending)
	restored._process(0.0)
	check_eq(restored.city.day, 300, "restored year review holds unpaced simulation")
	restored.finish_budget_review()
	restored._process(0.0)
	check_between(restored.city.day, 301, 308, "acknowledgement resumes without waiting for elapsed time")
	check_eq(restored._accumulator, 0.173125)
	sim.free()
	restored.free()


func _real_simulation(path: String) -> Simulation:
	var loaded := SaveFormat.load(path)
	check(loaded.ok, path)
	if not loaded.ok: return null
	var sim := Simulation.new()
	root.add_child(sim)
	sim.set_process(false)
	var saved: Dictionary = loaded.get("snapshot", {})
	sim.setup(loaded.city, 4729, null, saved)
	if not saved.is_empty(): check_eq(sim.restore(saved), OK, path)
	sim.set_speed(GameClock.Speed.FASTEST)
	sim._accumulator = 0.173125
	return sim


func test_real_city_fixed_days_equal_direct_work_including_json_resume() -> void:
	for name in ["La Presa", "Foothills Ranch"]:
		var path: String = "res://assets/cities/" + name + ".sc2d"
		var sim := _real_simulation(path)
		var direct := _real_simulation(path)
		if sim == null or direct == null:
			if sim != null: sim.free()
			if direct != null: direct.free()
			continue
		var actual_days: Array = []
		var expected_days: Array = []
		sim.day_advanced.connect(func(y: int, m: int, d: int) -> void:
			actual_days.append([y, m, d])
			if actual_days.size() == 1: sim.set_speed(GameClock.Speed.PAUSED)
		)
		sim.finish_budget_review()
		sim._process(0.0)
		check_eq(actual_days.size(), 1, name + " advances immediately")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
		check_eq(sim.restore(saved), OK, name + " JSON continuation")
		sim.set_speed(GameClock.Speed.FASTEST)
		sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void:
			if actual_days.size() == 17: sim.set_speed(GameClock.Speed.PAUSED)
		)
		direct.day_advanced.connect(func(y: int, m: int, d: int) -> void:
			expected_days.append([y, m, d])
			if expected_days.size() == 17: direct.set_speed(GameClock.Speed.PAUSED)
		)
		direct.advance_days(17)
		for frame in 30:
			if actual_days.size() >= 17: break
			if sim.budget_review_pending: sim.finish_budget_review()
			sim._process(1.0 / 60.0)
		check_eq(actual_days, expected_days, name + " ordered atomic days")
		check(SaveFormat.encode_city(sim.city) == SaveFormat.encode_city(direct.city), name + " every city field")
		check(sim.snapshot() == direct.snapshot(), name + " systems, stats, clock, RNG and debt")
		sim.free()
		direct.free()
