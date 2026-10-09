# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Saving and loading a city in play must not change how it continues: the
## reloaded city runs the same days as one that never stopped.
extends "res://tests/test_case.gd"

const DIR := "user://test_save_continuation"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)


func _sim_from(path: String) -> Simulation:
	var result := SaveFormat.load(path)
	check(bool(result["ok"]), "loads %s" % path)
	var sim := Simulation.new()
	sim.setup(result["city"], -1, null, result["snapshot"])
	if not (result["snapshot"] as Dictionary).is_empty():
		sim.restore(result["snapshot"])
	return sim


func _norm(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func _canon(v: Variant) -> String:
	return JSON.stringify(_norm(v), "", true)


## Names of everything that differs between two running cities.
func _differences(a: Simulation, b: Simulation) -> Array:
	var out: Array = []
	var sa: Dictionary = _norm(a.snapshot())
	var sb: Dictionary = _norm(b.snapshot())
	for k in sa["systems"]:
		if _canon(sa["systems"][k]) != _canon(sb["systems"].get(k)):
			out.append("system." + String(k))
	for k in sa["stats"]:
		if _canon(sa["stats"][k]) != _canon(sb["stats"].get(k)):
			out.append("stat." + String(k))
	for k in ["clock_day", "rng_state"]:
		if _canon(sa[k]) != _canon(sb[k]):
			out.append(k)
	var ca: Dictionary = _norm(SaveFormat.encode_city(a.city))
	var cb: Dictionary = _norm(SaveFormat.encode_city(b.city))
	for k in ca:
		if k == "layers":
			for layer in ca["layers"]:
				if ca["layers"][layer] != cb["layers"][layer]:
					out.append("layer." + String(layer))
		elif _canon(ca[k]) != _canon(cb[k]):
			out.append("city." + String(k))
	return out


func _check_continuation(city_name: String, disaster: StringName) -> void:
	var a := _sim_from("res://assets/cities/%s.sc2d" % city_name)
	a.advance_days(20)
	if disaster != &"":
		a.request_disaster(disaster)
	a.advance_days(3)
	var path := DIR.path_join("continuation.sc2d")
	check(SaveFormat.save(path, a.city, a.snapshot()) == OK, "saves")
	var b := _sim_from(path)
	check_eq(_differences(a, b), [], "%s %s right after the load" % [city_name, disaster])
	for day in 40:
		a.advance_day()
		b.advance_day()
		if a.budget_review_pending:
			a.finish_budget_review()
		if b.budget_review_pending:
			b.finish_budget_review()
	check_eq(_differences(a, b), [], "%s %s forty days after the load" % [city_name, disaster])
	a.free()
	b.free()


func test_reload_after_an_earthquake_continues_like_the_running_city() -> void:
	_check_continuation("Oro Canyon", &"earthquake")


func test_reload_after_a_chemical_spill_continues_like_the_running_city() -> void:
	_check_continuation("Oro Canyon", &"chemical_spill")


func test_reload_on_an_ordinary_day_continues_like_the_running_city() -> void:
	_check_continuation("La Presa", &"")


func test_loaded_growth_and_density_maps_are_the_saved_ones() -> void:
	var a := _sim_from("res://assets/cities/Oro Canyon.sc2d")
	a.advance_days(20)
	a.request_disaster(&"earthquake")
	a.advance_days(3)
	var path := DIR.path_join("maps.sc2d")
	SaveFormat.save(path, a.city, a.snapshot())
	var b := _sim_from(path)
	check_eq(b.city.density.data, a.city.density.data, "density kept")
	check_eq(b.city.growth.data, a.city.growth.data, "growth kept")
	a.free()
	b.free()


func test_water_window_matches_the_saved_figures_right_after_a_load() -> void:
	var a := _sim_from("res://assets/cities/La Presa.sc2d")
	a.advance_days(30)
	var path := DIR.path_join("water.sc2d")
	SaveFormat.save(path, a.city, a.snapshot())
	var b := _sim_from(path)
	var summary: Dictionary = (b.get_system(&"water") as WaterSystem).network_summary()
	check_gt(a.stats.water_capacity, 0, "the city has water capacity")
	check_eq(int(summary["capacity"]), a.stats.water_capacity, "capacity")
	check_eq(int(summary["capacity"]), b.stats.water_capacity, "capacity matches the loaded stats")
	check_eq(int(summary["unwatered_buildings"]), a.stats.unwatered_buildings, "unwatered buildings")
	check_eq(int(summary["stored"]), a.stats.water_stored, "stored")
	check_eq(b.city.flags.data, a.city.flags.data, "the load leaves the service flags alone")
	var running: Dictionary = (a.get_system(&"water") as WaterSystem).network_summary()
	check_eq(_canon(summary), _canon(running), "same summary as the running city")
	a.free()
	b.free()


## A city founded today, its first homes already up but nobody counted yet
## (the first population pass is day 14).
func _young_city() -> City:
	var c := flat_city()
	c.name = "Young Town"
	for row in 5:
		for i in 20:
			c.stamp_building(10 + i, 10 + row, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	return c


func _young_save(path: String, keep_flag: bool) -> Simulation:
	var a := Simulation.new()
	a.setup(_young_city(), 4242)
	a.advance_days(8)
	var snap: Dictionary = a.snapshot()
	if not keep_flag:
		snap = snap.duplicate(true)
		(snap["systems"]["population"] as Dictionary).erase("settled")
	check(SaveFormat.save(path, a.city, snap) == OK, "saves")
	return a


func test_a_save_before_the_first_head_count_keeps_its_population() -> void:
	var path := DIR.path_join("young.sc2d")
	var a := _young_save(path, true)
	check_eq(a.stats.population, 0, "nobody is counted before day 14")
	var b := _sim_from(path)
	check_eq(b.stats.population, a.stats.population, "the reload does not move anyone in")
	check_eq(b.stats.cohorts, a.stats.cohorts, "cohorts unchanged by the reload")
	check_eq(_differences(a, b), [], "young city right after the load")
	for day in 30:
		a.advance_day()
		b.advance_day()
		if a.budget_review_pending:
			a.finish_budget_review()
		if b.budget_review_pending:
			b.finish_budget_review()
	check_gt(a.stats.population, 0, "the first population pass counts the homes")
	check_eq(_differences(a, b), [], "young city thirty days after the load")
	a.free()
	b.free()


func test_a_legacy_save_without_a_head_count_is_settled_on_load() -> void:
	var path := DIR.path_join("young-legacy.sc2d")
	var a := _young_save(path, false)
	var b := _sim_from(path)
	check_gt(b.stats.population, 0, "a save from before the flag gets its residents at once")
	a.free()
	b.free()
