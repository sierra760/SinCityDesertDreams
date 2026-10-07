# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const TABLE_PATH := "res://scripts/sim/data/public_scan_tables.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")

func test_scan_tables_follow_public_roster() -> void:
	check(ResourceLoader.exists(TABLE_PATH), "shared classification tables must exist")
	if not ResourceLoader.exists(TABLE_PATH):
		return
	var table: Script = load(TABLE_PATH)
	var categories: PackedByteArray = table.categories()
	for id: int in Buildings.COUNT:
		check_eq(categories[id], Buildings.category(id), "every building category")

func test_capacity_tables_and_custom_zone_owner() -> void:
	if not ResourceLoader.exists(TABLE_PATH):
		return
	var table: Script = load(TABLE_PATH)
	check(table.has_method("capacities"), "roster capacity table exists")
	if not table.has_method("capacities"):
		return
	for use_zones: bool in [false, true]:
		var capacities: PackedInt32Array = table.capacities(use_zones)
		for id: int in Buildings.COUNT:
			var expected := ZoneParams.population_of(id) if use_zones else 0
			if expected <= 0:
				expected = PopulationParams.lot_capacity(id)
			check_eq(capacities[id], expected, "capacity matches public owner and fallback")
	var city := flat_city()
	city.building.put(10, 10, Buildings.RES_1X1_FIRST)
	city.building.put(11, 10, Buildings.RES_1X1_FIRST)
	var ctx := _context(city)
	ctx.systems[&"zones"] = CustomZones.new()
	var owner := PopulationSystem.new()
	owner.setup(ctx)
	owner._run_census(ctx)
	check_eq(owner.residents(), 33, "custom zone calls remain per-lot and ordered")

class CustomZones extends SimSystem:
	var count := 0
	func population_of(_id: int) -> int:
		count += 1
		return count * 11

func _context(city: City) -> SimContext:
	var ctx := SimContext.new()
	ctx.city = city
	ctx.stats = CityStats.new()
	ctx.rng = SimRng.new(12345)
	ctx.clock = GameClock.new()
	ctx.events = CityEvents.new()
	ctx.systems[&"zones"] = ZoneSystem.new()
	return ctx

func test_monthly_scans_match_golden_outputs_on_mixed_raw_layers() -> void:
	var city := flat_city()
	# Every byte value, damaged footprints, flags, and borders. These systems'
	# NW-corner census rule deliberately differs from footprint anchor recovery.
	for i: int in city.building.data.size():
		city.building.data[i] = i % Buildings.COUNT
		city.zone.data[i] = (i * 29 + i / 256) % 256
		city.flags.data[i] = (i * 31) % 256
	city.flood_overlay[Vector2i(127, 127)] = 1
	for key: String in ["economy", "population", "budget", "disaster"]:
		var system: SimSystem = load("res://scripts/sim/" + key + "_system.gd").new()
		var ctx := _context(city)
		system.setup(ctx)
		var outputs := []
		for pop: int in [0, 2500, 25000, 250000]:
			ctx.stats.population = pop
			var result: Variant = null
			match key:
				"economy":
					system._assess_city(ctx)
				"population":
					system._run_census(ctx)
				"budget":
					result = system._survey(city)
				"disaster":
					result = system._compute_advice(ctx)
			outputs.append([result, system.save(), ctx.stats.to_dict(), ctx.rng.state(), SaveFormat.encode_city(city)])
		check(Hashes.matches("monthly_scan/" + key, Hashes.unordered_sha(outputs)), key + " results, saved state, stats, RNG and city layers match the golden hash")
