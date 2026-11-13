# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Farm jobs and farm counts follow damage on the day it happens instead of
## waiting for the next monthly farm pass.
extends "res://tests/test_case.gd"


func _city() -> City:
	var c := flat_city()
	for x in range(20, 26):
		c.building.put(x, 9, Buildings.ROAD_FIRST)
		c.stamp_building(x, 10, AgricultureParams.building_id(&"greenhouse"), Zones.AGR_HIGH)
		c.stamp_building(x, 12, AgricultureParams.building_id(&"vegetables"), Zones.AGR_LOW)
	return c


func test_fixture_counts_both_densities() -> void:
	var sim := make_simulation(_city())
	check_eq(sim.stats.agricultural_jobs, 6 * 10 + 6 * 4)
	check_eq(sim.stats.agricultural_lots, 12)
	sim.free()


## A fire burning far from the farms keeps the emergency going.
func _start_fire(sim: Simulation) -> void:
	sim.city.stamp_building(100, 100, Buildings.RES_1X1_FIRST)
	check(sim.request_disaster(&"fire", Vector2i(100, 100)), "a fire starts")


func test_destroyed_high_density_lot_leaves_the_counts_that_day() -> void:
	var sim := make_simulation(_city())
	_start_fire(sim)
	var rect := sim.city.clear_footprint(20, 10)
	sim.city.building.put(20, 10, Buildings.RUBBLE_1)
	sim.events.mark_dirty(rect)
	sim.advance_day()
	check_eq(sim.stats.agricultural_jobs, 5 * 10 + 6 * 4, "jobs follow the damage")
	check_eq(sim.stats.agricultural_lots, 11, "so does the farm count")
	sim.free()


func test_destroyed_parcel_leaves_the_counts_that_day() -> void:
	var sim := make_simulation(_city())
	_start_fire(sim)
	sim.city.building.put(20, 12, Buildings.RUBBLE_1)
	var cut: Dictionary = (sim.get_system(&"agriculture") as AgricultureSystem).repair_parcels(PackedInt32Array([12 * City.WIDTH + 20]))
	check(bool(cut.get("ok", false)), "the parcel is cut")
	sim.events.mark_tile(20, 12)
	sim.advance_day()
	check_eq(sim.stats.agricultural_jobs, 6 * 10 + 5 * 4)
	check_eq(sim.stats.agricultural_lots, 11)
	sim.free()


func test_requested_disaster_damage_is_counted_at_once() -> void:
	var sim := make_simulation(_city())
	var before := sim.stats.agricultural_jobs
	check(sim.request_disaster(&"plane_crash", Vector2i(22, 10)), "the crash starts")
	var standing := 0
	for x in range(20, 26):
		if sim.city.building_at(x, 10) == AgricultureParams.building_id(&"greenhouse"): standing += 1
		if sim.city.building_at(x, 12) == AgricultureParams.building_id(&"vegetables"): standing += 1
	var ag := sim.get_system(&"agriculture") as AgricultureSystem
	check_eq(sim.stats.agricultural_jobs, ag.jobs(), "published jobs match the farms left standing")
	if standing < 12:
		check_lt(sim.stats.agricultural_jobs, before, "the wrecked farm no longer counts")
	sim.free()
