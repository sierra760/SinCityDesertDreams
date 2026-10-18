# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

## The original whole-map computation is deliberately independent of the
## candidate prefilter, so omitted zone-byte variants cannot pass by agreement.
class FullScanGrowth extends AgriculturalParcelGrowth:
	func prepare(city: City, fires: Array = []) -> void:
		_city = city
		_eligible.resize(City.WIDTH * City.HEIGHT)
		_eligible.fill(0)
		_heights.resize(_eligible.size())
		eligible_cells = _eligible.size()
		var burning := {}
		for tile in fires: burning[tile] = true
		for i in _eligible.size():
			if (city.zone.data[i] & Zones.KIND_MASK) != Zones.AGR_LOW or city.building.data[i] != Buildings.NONE: continue
			var p := AgriculturalParcels.tile(i)
			if p.x < 2 or p.y < 2 or p.x >= 126 or p.y >= 126: continue
			if city.agricultural_parcels.id_at(p) != 0 or burning.has(p): continue
			if city.is_water(p.x,p.y) or not city.is_flat(p.x,p.y) or city.flood_overlay.has(p): continue
			if city.flags.has_bits(p.x,p.y,TileFlags.LANDMARK): continue
			_heights[i] = city.ground_height(p.x,p.y)
			_eligible[i] = 1

func test_prepare_does_not_traverse_the_full_map_in_script() -> void:
	# Empty-zone iterations call no City method, so call-counting a City subclass
	# cannot observe them. This narrow structural guard covers that work bound;
	# the independent reference tests below cover actual simulation behavior.
	var source := FileAccess.get_file_as_string("res://scripts/sim/agricultural_parcel_growth.gd")
	var body := source.get_slice("func prepare(", 1).get_slice("\nfunc ", 0)
	check(not body.contains("for i in _eligible.size():"), "empty and sparse maps must not execute a scripted loop over every cell")

func _fixture(dense: bool = false) -> City:
	var city := flat_city()
	if dense:
		for i in city.zone.data.size(): city.zone.data[i] = Zones.AGR_LOW | ((i % 16) << 4)
	else:
		for high in 16:
			city.zone.put(20 + high, 20, Zones.AGR_LOW | (high << 4))
			city.zone.put(20 + high, 21, Zones.AGR_HIGH | (high << 4))
	for p in [Vector2i(0,20), Vector2i(1,20), Vector2i(126,20), Vector2i(127,20), Vector2i(20,0), Vector2i(20,1), Vector2i(20,126), Vector2i(20,127)]:
		city.zone.put(p.x,p.y,Zones.AGR_LOW)
	city.building.put(21,20,Buildings.ROAD_FIRST)
	city.flood_overlay[Vector2i(22,20)] = 1
	city.terrain.put(23,20,Terrain.make(Terrain.FLAT,Terrain.SURFACE))
	city.set_heights(23,20,2,4)
	city.flags.set_bits(24,20,TileFlags.LANDMARK,true)
	city.terrain.put(25,20,1)
	var members := PackedInt32Array([20 * City.WIDTH + 26])
	F.zone(city,members)
	check_eq(city.agricultural_parcels.put(city,F.record(1,members)),OK)
	return city

func test_masks_heights_and_report_equal_full_reference() -> void:
	var actual := AgriculturalParcelGrowth.new()
	var expected := FullScanGrowth.new()
	for city in [flat_city(), _fixture(), _fixture(true), flat_city(20000,9)]:
		var before := var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()])
		var fires: Array = [Vector2i(20,20),Vector2i(35,20)]
		actual.prepare(city,fires)
		expected.prepare(city,fires)
		check_eq(actual._eligible,expected._eligible,"every cell, including all 16 high zone-byte variants")
		check_eq(actual._heights,expected._heights,"repeated preparation retains the same unused height slots")
		check_eq(actual.eligible_cells,expected.eligible_cells,"work reporting retains its existing domain size")
		check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()]),before,"preparation is read-only")

func test_seeded_growth_and_reservations_equal_full_reference() -> void:
	var city := _fixture(true)
	for seed_value in range(1,25):
		var actual := AgriculturalParcelGrowth.new()
		var expected := FullScanGrowth.new()
		var fires: Array = [Vector2i(20,20)]
		actual.prepare(city,fires)
		expected.prepare(city,fires)
		var reserved := PackedInt32Array([30 * City.WIDTH + 31,31 * City.WIDTH + 30])
		actual.reserve(reserved)
		expected.reserve(reserved)
		var rng := SimRng.from_saved_seed(seed_value)
		var reference_rng := SimRng.from_saved_seed(seed_value)
		for archetype in [&"grain",&"cattle_range"]:
			check_eq(var_to_bytes(actual.candidate(city,Vector2i(30,30),archetype,0,rng)),var_to_bytes(expected.candidate(city,Vector2i(30,30),archetype,0,reference_rng)),"seeded shape, work counts and admission order")
			check_eq(rng.state(),reference_rng.state(),"identical RNG consumption")
