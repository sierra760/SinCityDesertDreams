# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const UtilityParams := preload("res://scripts/sim/data/utility_params.gd")

func imported_city() -> City:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.COAL_PLANT)
	city.building.put(14,10,Buildings.ROAD_FIRST)
	city.building.put(16,10,Buildings.BRIDGE_FIRST)
	city.building.put(17,10,Buildings.POWER_LINE_FIRST)
	city.stamp_building(18,10,Buildings.RES_1X1_FIRST)
	var chunks := {"ALTM":PackedByteArray(),"XTER":PackedByteArray(),"XBLD":PackedByteArray(),"XZON":PackedByteArray(),"XBIT":PackedByteArray()}
	for x: int in 128:
		for y: int in 128:
			chunks.ALTM.append(0);chunks.ALTM.append(4)
			chunks.XTER.append(city.terrain.at(x,y))
			chunks.XBLD.append(city.building.at(x,y))
			chunks.XZON.append(city.zone.at(x,y))
			# In the imported flag byte, bit 128 marks a conductor and bit 64 a powered tile.
			chunks.XBIT.append(128 if y==10 and x>=10 and x<=18 else 0)
	return Sc2Import.import_chunks(chunks,"Power links").city

func test_imported_single_power_bits_are_independent() -> void:
	check_eq(Sc2Import._map_flags(128)&(TileFlags.CONDUCTS_POWER|TileFlags.POWERED),TileFlags.CONDUCTS_POWER)
	check_eq(Sc2Import._map_flags(64)&(TileFlags.CONDUCTS_POWER|TileFlags.POWERED),TileFlags.POWERED)

func test_imported_road_and_open_ground_links_survive_monthly_power() -> void:
	var city := imported_city();var ctx := make_context(city);var power := PowerSystem.new()
	power.setup(ctx)
	check(city.is_powered(18,10),"saved conductive road, open ground and bridge carry power")
	power.monthly(ctx)
	check(city.is_powered(18,10),"monthly refresh retains unchanged imported links")
	check_eq(ctx.stats.power_demand,1,"links add no consumers")
	check(not city.conducts_power(14,11),"ordinary open ground is not made conductive")

func test_imported_links_round_trip_and_changed_tile_invalidates() -> void:
	var city := imported_city();var ctx := make_context(city);var power := PowerSystem.new();power.setup(ctx)
	var decoded: Dictionary = SaveFormat.decode_city(SaveFormat.encode_city(city))
	check(decoded.city!=null)
	city=decoded.city;ctx=make_context(city);power=PowerSystem.new();power.setup(ctx)
	check(city.is_powered(18,10),"saved link survives native reload")
	city.building.put(14,10,Buildings.TREES_1)
	power.monthly(ctx)
	check(not city.conducts_power(14,10),"changed imported link expires")
	check(not city.is_powered(18,10),"broken network loses supply")
	city.building.put(14,10,Buildings.ROAD_FIRST)
	power.monthly(ctx)
	check(not city.is_powered(18,10),"recreating ordinary road cannot resurrect old link")

func test_explicit_demolition_erases_even_open_ground_imported_link() -> void:
	var city := imported_city();var ctx := make_context(city);var power := PowerSystem.new();power.setup(ctx)
	city.clear_footprint(15,10)
	power.networks_changed(ctx,Rect2i(15,10,1,1))
	check(not city.conducts_power(15,10),"bulldozing imported open-ground link removes it")
	check(not city.is_powered(18,10))

func test_all_bridge_types_transmit_without_demand() -> void:
	for code: int in 256:
		if Buildings.category(code)!=Buildings.Category.BRIDGE:continue
		var city := flat_city();city.stamp_building(10,10,Buildings.COAL_PLANT)
		city.building.put(14,10,code);city.stamp_building(15,10,Buildings.RES_1X1_FIRST)
		var ctx := make_context(city);var power := PowerSystem.new();power.setup(ctx)
		check(city.is_powered(15,10),"bridge %d carries power"%code)
		check_eq(ctx.stats.power_demand,1)
		city.clear_footprint(14,10);power.networks_changed(ctx,Rect2i(14,10,1,1))
		check(not city.is_powered(15,10),"removed bridge interrupts power")

func test_native_power_link_metadata_validation_and_absent_links() -> void:
	var city := imported_city()
	var doc := SaveFormat.encode_city(city)
	var unlinked := doc.duplicate(true);unlinked.erase("imported_power_links")
	check(SaveFormat.decode_city(unlinked).city!=null,"a city without imported links loads")
	for bad: Variant in [[], {"-1":[29,0]}, {"16384":[29,0]}, {"14":["road",0]}, {"14":[29.5,0]}, {"x":[29,0]}, {"14":[29]}]:
		var invalid := doc.duplicate(true);invalid["imported_power_links"]=bad
		check(SaveFormat.decode_city(invalid).city==null,"malformed power link rejected")
