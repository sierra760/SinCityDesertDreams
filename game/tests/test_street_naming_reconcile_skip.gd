# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Reconciliation skipped for unrelated growth commits exactly what a fresh binding computes.
extends "res://tests/test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")
## Fresh complete computation from the same pre-edit metadata.
static func _reference(city: City) -> Dictionary:
	var copy := city.duplicate_city()
	var topology := StreetTopology.new()
	topology.rebuild(copy)
	var service := StreetNamingService.new()
	service.set_station_allocator(StationNameResolver.reconcile)
	var bound := service.bind_city(copy, topology)
	return {"ok": bound.ok, "metadata": copy.street_naming.duplicate(true)}
func test_skipped_reconciliation_matches_fresh_binding() -> void:
	for subway: bool in [false, true]:
		var city := Fixtures.subway_city() if subway else Fixtures.rail_city()
		preload("res://tests/fixtures/street_names_fixtures.gd").road(city, Vector2i(18, 23), Vector2i(33, 23))
		var topology := StreetTopology.new()
		topology.rebuild(city)
		var service := StreetNamingService.new()
		service.set_station_allocator(StationNameResolver.reconcile)
		check(service.bind_city(city, topology).ok, "fixture binds")
		var label := "subway" if subway else "rail"
		# 1. Lot growth far from every station: nothing to reconcile.
		var revision_before := service.revision
		for x: int in range(60, 70): city.building.put(x, 60, Buildings.RES_1X1_FIRST + x % 8)
		var expected := _reference(city)
		var result := service.reconcile(Rect2i(60, 60, 10, 1))
		check(result.ok and not result.changed and service.revision == revision_before, label + ": distant growth reconciles to no change")
		check(city.street_naming == expected.metadata, label + ": distant growth keeps the fresh binding's metadata")
		# 2. A lot beside a station changes its street access: full reconciliation.
		city.building.put(18, 22, Buildings.RES_1X1_FIRST)
		city.building.put(19, 22, Buildings.RES_1X1_FIRST)
		expected = _reference(city)
		result = service.reconcile(Rect2i(18, 22, 2, 1))
		check(result.ok and city.street_naming == expected.metadata, label + ": growth beside a station matches a fresh binding")
		# 3. A removed road changes the topology.
		city.building.put(24, 23, Buildings.NONE)
		expected = _reference(city)
		result = service.reconcile(Rect2i(24, 23, 1, 1))
		check(result.ok and city.street_naming == expected.metadata, label + ": a structural change matches a fresh binding")
		# 4. A custom facility name reserves its title.
		var anchor := Vector2i(20, 20 if subway else 21)
		city.facilities[anchor] = {"key": Buildings.key(city.building.atv(anchor)), "name": "Original Station"}
		expected = _reference(city)
		result = service.reconcile(Rect2i(anchor, Vector2i.ONE))
		check(result.ok and city.street_naming == expected.metadata, label + ": a custom facility name matches a fresh binding")
		# 5. Growth far away again after those changes still commits nothing new.
		revision_before = service.revision
		for x: int in range(60, 70): city.building.put(x, 62, Buildings.RES_1X1_FIRST + x % 8)
		expected = _reference(city)
		result = service.reconcile(Rect2i(60, 62, 10, 1))
		check(result.ok and not result.changed and service.revision == revision_before and city.street_naming == expected.metadata, label + ": later distant growth reconciles to no change")
		# 6. Floods near a station are reconciled.
		city.flood_overlay[Vector2i(23, 22)] = 1
		expected = _reference(city)
		result = service.reconcile(Rect2i(23, 22, 1, 1))
		check(result.ok and city.street_naming == expected.metadata, label + ": a flood beside a station matches a fresh binding")
