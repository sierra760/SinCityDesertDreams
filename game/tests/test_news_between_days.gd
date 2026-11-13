# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## News raised while the clock is between days (from the Budget window, from
## construction, from accepting a neighbor link) reaches the newspaper.
extends "res://tests/test_case.gd"

var _published: Array[StringName] = []
var _dirty: Array[Rect2i] = []


func before_each() -> void:
	_published.clear()
	_dirty.clear()


func _on_news(story: Dictionary) -> void:
	_published.append(StringName(story.get("kind", &"")))


func _on_map_changed(rect: Rect2i) -> void:
	_dirty.append(rect)


func _sim(funds: int = 200000) -> Simulation:
	var sim := make_simulation(flat_city(funds))
	sim.stats.disasters_enabled = false
	sim.news_published.connect(_on_news)
	sim.map_changed.connect(_on_map_changed)
	return sim


func _queued(sim: Simulation) -> Array:
	var kinds: Array = []
	for entry: Dictionary in sim.get_system(&"newspaper").save().get("queue", []):
		kinds.append(StringName(entry.get("kind", "")))
	return kinds


func test_bond_issued_from_the_budget_window_is_reported() -> void:
	var sim := _sim()
	sim.advance_days(2)
	check(bool(sim.get_system(&"budget").call("issue_bond")), "the bond is issued")
	check(not (&"bond_issued" in _published), "nothing is published while the clock stands still")
	sim.advance_day()
	check(&"bond_issued" in _published, "the next day reports it")
	check(&"bond_issued" in _queued(sim) or sim.stats.newspaper_archive.size() > 0, "and the newspaper has it")
	sim.free()


func test_accepted_neighbor_link_is_reported() -> void:
	var sim := _sim()
	sim.advance_days(2)
	sim.city.building.put(64, 0, Buildings.ROAD_FIRST)
	sim.get_system(&"neighbors").call("record_connection", NeighborParams.EDGE_NORTH, &"road")
	sim.advance_day()
	check(&"neighbor_connection" in _published)
	sim.free()


func test_shortage_and_recovery_caused_by_construction_are_reported() -> void:
	var sim := _sim(5000000)
	var builder := Builder.new(sim.city, sim.stats, sim)
	sim.advance_days(3)
	check(bool(builder.apply(Tools.Kind.COAL_PLANT, Vector2i(40, 40)).get("applied", false)), "plant built")
	for i in 56:
		@warning_ignore("integer_division")
		var at := Vector2i(44 + (i % 8) * 4, 40 + (i / 8) * 4)
		check(bool(builder.apply(Tools.Kind.STADIUM, at).get("applied", false)), "stadium built")
	check(bool(sim.get_system(&"power").call("is_shortage")), "construction outgrew the plant")
	sim.advance_day()
	check(&"power_shortage" in _published, "the shortage is reported")
	_published.clear()
	check(bool(builder.apply(Tools.Kind.COAL_PLANT, Vector2i(40, 44)).get("applied", false)), "second plant built")
	check(not bool(sim.get_system(&"power").call("is_shortage")), "the new plant ends the shortage")
	sim.advance_day()
	check(&"power_restored" in _published, "the recovery is reported")
	sim.free()


func test_notice_raised_between_days_is_delivered() -> void:
	var sim := _sim()
	var notices: Array[StringName] = []
	sim.notice_raised.connect(func(kind: StringName, _payload: Dictionary) -> void: notices.append(kind))
	sim.advance_days(2)
	sim.events.notify(&"fiscal_crisis", {"funds": -1, "year": 1900})
	sim.advance_day()
	check(&"fiscal_crisis" in notices)
	sim.free()


func test_map_change_marked_between_days_is_announced() -> void:
	var sim := _sim()
	sim.advance_days(2)
	_dirty.clear()
	sim.events.mark_dirty(Rect2i(10, 10, 2, 2))
	sim.advance_day()
	check(Rect2i(10, 10, 2, 2) in _dirty)
	sim.free()


## Nothing a system reports while a city is being set up or loaded is news.
func test_reports_made_during_setup_are_not_published() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.GAS_PLANT)
	for y in range(10, 19):
		for x in range(14, 34):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.news_published.connect(_on_news)
	sim.setup(c, 5)
	sim.stats.disasters_enabled = false
	check(bool(sim.get_system(&"power").call("is_shortage")), "the city starts short of power")
	check(sim.events.news.is_empty(), "setup leaves nothing queued")
	sim.free()
