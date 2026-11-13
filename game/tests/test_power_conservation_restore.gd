# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A loaded city keeps the Energy Conservation bonus its last power pass used.
extends "res://tests/test_case.gd"

const DIR := "user://test_power_conservation_restore"
const HOUSE := Buildings.RES_1X1_FIRST


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## One gas plant (176) beside 180 houses: fully served only with the bonus.
func _tight_city() -> Simulation:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.GAS_PLANT)
	for y in range(10, 19):
		for x in range(14, 34):
			c.stamp_building(x, y, HOUSE)
	var sim := make_simulation(c)
	sim.get_system(&"ordinances").call("set_enabled", &"energy_conservation", true)
	# Day 1 of the month is the scheduled power pass.
	sim.advance_day()
	return sim


func _reload(sim: Simulation, drop_saved_flag: bool) -> Simulation:
	var snapshot := sim.snapshot()
	if drop_saved_flag:
		(snapshot["systems"]["power"] as Dictionary).erase("conservation")
	var path := DIR.path_join("flag.sc2d" if not drop_saved_flag else "older.sc2d")
	check_eq(SaveFormat.save(path, sim.city, snapshot), OK, "save")
	var result := SaveFormat.load(path)
	check(bool(result["ok"]), "load: %s" % String(result["error"]))
	var loaded := Simulation.new()
	root.add_child(loaded)
	loaded.setup(result["city"], -1, null, result["snapshot"])
	check_eq(loaded.restore(result["snapshot"]), OK, "restore")
	return loaded


func _available(sim: Simulation) -> int:
	return int((sim.get_system(&"power").call("network_summary") as Dictionary)["available_capacity"])


func _check_reloaded(loaded: Simulation, label: String) -> void:
	check_eq(_available(loaded), 190, "%s: capacity with the bonus after load" % label)
	check_eq(loaded.stats.unpowered_buildings, 0, "%s: everything powered after load" % label)
	# Any construction redistributes the established generation.
	loaded.networks_changed(Rect2i(0, 0, 1, 1))
	check_eq(_available(loaded), 190, "%s: capacity with the bonus after an edit" % label)
	check_eq(loaded.stats.unpowered_buildings, 0, "%s: everything still powered after an edit" % label)


func test_running_city_uses_the_bonus() -> void:
	var sim := _tight_city()
	check_eq(sim.stats.unpowered_buildings, 0)
	check_eq(_available(sim), 190)
	sim.free()


func test_loaded_city_keeps_the_bonus() -> void:
	var sim := _tight_city()
	var loaded := _reload(sim, false)
	_check_reloaded(loaded, "saved flag")
	loaded.free()
	sim.free()


func test_older_save_derives_the_bonus_from_its_ordinances() -> void:
	var sim := _tight_city()
	var loaded := _reload(sim, true)
	_check_reloaded(loaded, "no saved flag")
	loaded.free()
	sim.free()


## The bonus follows the last scheduled pass, not an ordinance changed since.
func test_ordinance_repealed_after_the_pass_keeps_established_bonus() -> void:
	var sim := _tight_city()
	sim.get_system(&"ordinances").call("set_enabled", &"energy_conservation", false)
	var loaded := _reload(sim, false)
	_check_reloaded(loaded, "repealed since")
	loaded.free()
	sim.free()
