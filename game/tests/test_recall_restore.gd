# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A recall campaign restored from an older or damaged save behaves the same
## on every load and never stalls the clock.
extends "res://tests/test_case.gd"


const DIR := "user://test_recall_restore"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## A saved city read back from disk, three days into its life.
func _saved() -> Dictionary:
	var sim := make_simulation(flat_city(), 4242)
	sim.advance_days(3)
	var path := DIR.path_join("city.sc2d")
	check_eq(SaveFormat.save(path, sim.city, sim.snapshot()), OK, "save")
	sim.free()
	var result := SaveFormat.load(path)
	check(bool(result["ok"]), "load: %s" % String(result["error"]))
	return result


func _load(saved: Dictionary) -> Simulation:
	var sim := Simulation.new()
	root.add_child(sim)
	# The session loads a city with no seed of its own; the snapshot supplies it.
	sim.setup(saved["city"], -1, null, saved["snapshot"])
	check_eq(sim.restore(saved["snapshot"]), OK, "restore")
	return sim


func _recall_draw(sim: Simulation) -> String:
	return String(sim.casino().recall.save()["rng_state"])


func _election(sim: Simulation) -> Dictionary:
	var recall := sim.casino().recall
	recall.due_day = sim.clock.day
	sim.stats.approval = 50
	sim.advance_day()
	return recall.result


func test_recall_without_a_saved_draw_plays_out_the_same_on_every_load() -> void:
	var saved := _saved()
	# An earlier version wrote the recall without a draw of its own.
	(saved["snapshot"]["systems"]["casino"]["recall"] as Dictionary).erase("rng_state")
	var first := _load(saved)
	var second := _load(saved)
	check_eq(_recall_draw(first), _recall_draw(second), "the same draw is waiting after each load")
	var a := _election(first)
	var b := _election(second)
	check_eq(a.get("luck"), b.get("luck"), "the same luck")
	check_eq(a.get("roll"), b.get("roll"), "the same roll")
	first.free()
	second.free()


func test_save_with_no_casino_record_plays_out_the_same_on_every_load() -> void:
	var saved := _saved()
	(saved["snapshot"]["systems"] as Dictionary).erase("casino")
	var first := _load(saved)
	var second := _load(saved)
	check_eq(_recall_draw(first), _recall_draw(second))
	first.free()
	second.free()


func test_saved_draw_is_kept() -> void:
	var saved := _saved()
	var expected := String(saved["snapshot"]["systems"]["casino"]["recall"]["rng_state"])
	var loaded := _load(saved)
	check_eq(_recall_draw(loaded), expected)
	loaded.free()


func test_monthly_update_far_in_the_past_is_brought_into_the_campaign() -> void:
	var recall := MayoralRecall.new()
	recall.load({"due_day": 400, "next_update": -9000000000000000000})
	check_ge(recall.next_update, 400 - MayoralRecall.DELAY, "no earlier than the day the recall was called")
	check_lt(recall.next_update, 401)
	recall.load({"due_day": 400, "next_update": 9000000000000000000})
	check_lt(recall.next_update, 401, "no later than election day")
	recall.load({"due_day": -1, "next_update": 77})
	check_eq(recall.next_update, -1, "no campaign, no update")


func test_overdue_update_catches_up_in_one_step() -> void:
	var ctx := make_context(flat_city())
	ctx.clock.day = 1000
	var recall := MayoralRecall.new()
	recall.setup(ctx)
	recall.due_day = 1100
	recall.next_update = -9000000000000000000
	var started := Time.get_ticks_msec()
	recall.advance(ctx)
	check_lt(Time.get_ticks_msec() - started, 1000, "the catch-up does not walk every month")
	check_gt(recall.next_update, 1000, "the next update is in the future")
	check_lt(recall.next_update, 1001 + GameClock.DAYS_PER_MONTH)
	check_eq((recall.next_update + 9000000000000000000) % GameClock.DAYS_PER_MONTH, 0, "updates keep their monthly rhythm")
