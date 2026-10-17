# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

## Tourism skips a reconcile whose inputs are unchanged since the last one.
## With verification on, every skipped reconcile runs anyway; it must not
## change any input, news, notice, dirty area or attendance signal.

func _empty_line(c: City, b: Builder) -> Array:
	for y in range(20, City.HEIGHT - 20):
		for x in range(20, City.WIDTH - 26):
			var ok := true
			for dx in 6:
				var bid := c.building_at(x + dx, y)
				if (bid != Buildings.NONE and (bid < Buildings.TREES_1 or bid > Buildings.TREES_7)) \
						or c.zone_kind_at(x + dx, y) != Zones.NONE or c.is_water(x + dx, y):
					ok = false
					break
			if ok and bool(b.preview(Tools.Kind.ROAD, Vector2i(x, y), Vector2i(x + 5, y)).get("ok", false)):
				return [Vector2i(x, y), Vector2i(x + 5, y)]
	return []

func _first_zone_lot(c: City) -> Vector2i:
	for r in 60:
		for y in range(64 - r, 64 + r + 1):
			for x in range(64 - r, 64 + r + 1):
				if c.in_bounds(x, y) and Buildings.is_zone_building(c.building_at(x, y)):
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _venue(sim: Simulation, index: int) -> Dictionary:
	var operating: Array[Dictionary] = []
	for row in sim.tourism()._state.records():
		if row.operating: operating.append(row)
	return operating[index] if index < operating.size() else {}

func _run_verified(path: String, days: int) -> Dictionary:
	var done := {}
	var loaded := SaveFormat.load(path)
	check(loaded.ok, path)
	if not loaded.ok: return done
	var sim := Simulation.new()
	sim.setup(loaded.city, 31, null, loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot), OK)
	var builder := Builder.new(sim.city, sim.stats, sim)
	TourismSystem.verify_skips = true
	TourismSystem.skip_checks = 0
	TourismSystem.skip_mismatches.clear()
	for i in days:
		match i:
			5:
				sim.stats.tax_occupancy = 12
				sim.stats.tax_gaming = 4
			12: sim.request_disaster(&"fire")
			20, 21:
				sim.city.funds = maxi(sim.city.funds, 100000)
				var line := _empty_line(sim.city, builder)
				if not line.is_empty(): builder.apply(Tools.Kind.ROAD, line[0], line[1])
			25:
				# A venue loses power mid-month (the utility pass restores it later).
				var venue := _venue(sim, 0)
				if not venue.is_empty():
					var size := Buildings.size(venue.code)
					for dy in size.y:
						for dx in size.x:
							sim.city.set_flag(venue.anchor.x + dx, venue.anchor.y + dy, TileFlags.POWERED, false)
					done["unpowered"] = true
			30:
				sim.stats.ordinances[&"annual_carnival"] = true
			35:
				# A venue is demolished.
				sim.city.funds = maxi(sim.city.funds, 100000)
				var venue := _venue(sim, 1)
				if not venue.is_empty():
					done["demolished"] = bool(builder.apply(Tools.Kind.BULLDOZE, venue.anchor, venue.anchor).get("applied", false))
			40:
				sim.city.funds = maxi(sim.city.funds, 100000)
				var at := _first_zone_lot(sim.city)
				if at.x >= 0: builder.apply(Tools.Kind.BULLDOZE, at, at + Vector2i(3, 3))
		if sim.budget_review_pending: sim.finish_budget_review()
		sim.advance_day()
	TourismSystem.verify_skips = false
	check_gt(TourismSystem.skip_checks, 50, "%s skips most daily reconciles" % path)
	check_eq(TourismSystem.skip_mismatches, [] as Array[String], "%s skipped reconciles were no-ops" % path)
	sim.free()
	return done

func test_skipped_reconciles_change_nothing_in_a_resort_city() -> void:
	var done := _run_verified("res://assets/cities/Adaven.sc2d", 75)
	check(done.get("unpowered", false), "a venue lost power")
	check(done.get("demolished", false), "a venue was demolished")

func test_skipped_reconciles_change_nothing_in_an_ordinary_city() -> void:
	_run_verified("res://assets/cities/La Presa.sc2d", 45)
