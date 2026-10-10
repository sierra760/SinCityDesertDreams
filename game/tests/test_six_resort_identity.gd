# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const KEYS := [&"arcology_fix", &"arcology_alibi", &"arcology_velvet", &"arcology_afterglow", &"arcology_last", &"arcology_dust"]
const COSTS := [320000, 140000, 220000, 500000, 60000, 95000]
const CAPACITIES := [35000, 30000, 30000, 45000, 35000, 40000]

func _city() -> City:
	var city := City.new()
	city.funds = 2000000
	city.founded_year = 2100
	city.terrain.fill(Terrain.FLAT)
	return city

func test_all_build_demolish_and_classify() -> void:
	for i in KEYS.size():
		var city := _city()
		var stats := CityStats.new()
		stats.inventions[&"arcology_comstock"] = 2050
		var tool := Tools.Kind.ARCOLOGY_FIX + i
		var builder := Builder.new(city, stats)
		var pos := Vector2i(12, 12)
		var built := builder.apply(tool, pos)
		check(built.ok, str(built))
		check_eq(city.building.at(15, 15), 256 + i)
		check_eq(city.funds, 2000000 - COSTS[i])
		check_eq(Buildings.cost(256 + i), COSTS[i], "roster and construction cost agree")
		check_eq(Buildings.id_of(KEYS[i]), 256 + i)
		check(Buildings.is_arcology(256 + i))
		check(UtilityParams.draws_power(256 + i))
		check(UtilityParams.draws_water(256 + i))
		check_eq(RewardParams.ARCOLOGIES[KEYS[i]].capacity, CAPACITIES[i])
		check_eq(Tools.available_year(tool, stats), 2050)
		var removed := builder.apply(Tools.Kind.BULLDOZE, Vector2i(15, 15))
		check(removed.ok, str(removed))
		check_eq(city.building.count(256 + i), 0)

func test_adjacent_anchors_and_packed_consumers() -> void:
	var city := _city()
	city.stamp_building(12, 12, 256)
	city.stamp_building(16, 12, 256)
	city.stamp_building(12, 16, 256)
	check_eq(city.anchor_of(19, 15), Vector2i(16, 12))
	check_eq(city.anchor_of(15, 19), Vector2i(12, 16))
	check_eq(city.building_census()[256], 3)
	check_eq(city.duplicate_city().building.at(19, 15), 256)
	var before := city.building.data.duplicate()
	city.building.put(60, 60, 261)
	check_eq(CityTrafficGraph.changed_cells(before, city.building.data, city.flags.data, city.flags.data), PackedInt32Array([60 * 128 + 60]))

func test_v2_roundtrip_and_v1_load() -> void:
	var city := _city()
	for i in KEYS.size(): city.stamp_building(12 + 4 * i, 12, 256 + i)
	city.imported_power_links[12 * 128 + 32] = Vector2i(261, city.zone.at(32, 12) & Zones.KIND_MASK)
	var path := "user://six-resorts-v2.sc2d"
	var snapshot := {"stats": {"inventions": {"arcology_comstock": 2037}}}
	check_eq(SaveFormat.save(path, city, snapshot), OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded))
	if loaded.ok:
		check_eq(loaded.city.building.data, city.building.data)
		check_eq(loaded.city.imported_power_links, city.imported_power_links)
		check_eq(int(loaded.snapshot.stats.inventions.arcology_comstock), 2037)
	var legacy := _city()
	legacy.stamp_building(12, 12, Buildings.ARCOLOGY_COMSTOCK)
	check_eq(SaveFormat.save(path, legacy, snapshot), OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc.version = 1
	doc.city.layers.building = SaveFormat.encode_bytes(PackedByteArray(Array(legacy.building.data)))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	loaded = SaveFormat.load(path)
	check(loaded.ok, str(loaded))
	if loaded.ok:
		check_eq(loaded.city.building.data, legacy.building.data)
		check_eq(int(loaded.snapshot.stats.inventions.arcology_comstock), 2037)
	DirAccess.remove_absolute(path)


func test_v2_rejects_unknown_codes_before_topology_scan() -> void:
	var city := _city()
	var doc := SaveFormat.encode_city(city)
	city.building.put(12, 12, 65535)
	doc.layers.building = SaveFormat.encode_bytes(city.building.to_bytes())
	check(SaveFormat.decode_city(doc).city == null)
