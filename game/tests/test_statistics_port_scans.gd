# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Statistics := preload("res://scripts/sim/statistics_system.gd")
const Ports := preload("res://scripts/sim/port_system.gd")

func test_all_roster_tiles_count_without_anchor_or_zone_requirements() -> void:
	var city := flat_city()
	for i: int in city.building.data.size():
		city.building.data[i] = i % 256
		city.zone.data[i] = (i * 37) % 256
	var before := SaveFormat.encode_city(city)
	# Authored roster contains 24 residential, 28 commercial and 18
	# industrial ids; each appears on 64 tiles, regardless of lot corners.
	check_eq(Statistics._zone_tile_counts(city), Vector3i(1536, 1792, 1152), "every occupied tile is sampled")
	check_eq(SaveFormat.encode_city(city), before, "sampling does not mutate city")

func test_raw_writes_refresh_centroid_and_counts_without_changing_city() -> void:
	var city := flat_city()
	check_eq(Ports._city_centre(city), Vector2i(64, 64), "empty city uses map centre")
	city.building.put(2, 4, Buildings.RES_1X1_FIRST)
	city.building.put(100, 90, Buildings.RES_3X3_FIRST)
	city.building.put(126, 127, Buildings.IND_2X2_FIRST)
	city.building.put(6, 4, Buildings.COM_1X1_FIRST)
	city.building.put(127, 127, Buildings.ARCOLOGY_COMSTOCK)
	city.building.put(0, 127, Buildings.CONSTRUCTION_1X1_A)
	city.building.put(127, 0, Buildings.HOSPITAL)
	var before := SaveFormat.encode_city(city)
	check_eq(Ports._city_centre(city), Vector2i(58, 56), "only zone-building tiles influence centre")
	check_eq(Statistics._zone_tile_counts(city), Vector3i(2, 1, 1), "civic, arcology and construction tiles excluded")
	check_eq(SaveFormat.encode_city(city), before, "queries leave all city fields unchanged")
	# Unannounced raw write must be visible on the next scan.
	city.building.data[127] = Buildings.RES_1X1_FIRST
	check_eq(Ports._city_centre(city), Vector2i(72, 45), "raw replacement immediately changes centre")
	check_eq(Statistics._zone_tile_counts(city), Vector3i(3, 1, 1), "raw replacement immediately changes counts")
