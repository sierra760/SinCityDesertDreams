# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_every_non_building_terrain_input_rejects_growth_reuse() -> void:
	var city := flat_city()
	city.stamp_building(8,8,112)
	var view := CityView3D.new()
	var before := view._geometry_inputs(city)
	city.building.put(8,8,113)
	var ordinary := view._geometry_inputs(city)
	check(CityView3D._ordinary_growth_only(before,ordinary),"occupied ordinary growth admits reuse")
	for layer: int in [0,1,5,7]:
		var changed: Array = ordinary.duplicate(true)
		if changed[layer].is_empty(): changed[layer] = PackedByteArray([1])
		else: changed[layer][0] = int(changed[layer][0])+1
		check(not CityView3D._ordinary_growth_only(before,changed),"public terrain input rejects reuse: "+str(layer))
	var flooded: Array = ordinary.duplicate(true)
	flooded[6][Vector2i(8,8)] = 4
	check(not CityView3D._ordinary_growth_only(before,flooded),"adding flood rejects reuse")
	var dry: Array = flooded.duplicate(true)
	dry[6].clear()
	check(not CityView3D._ordinary_growth_only(flooded,dry),"removing flood rejects reuse")
	var malformed: Array = ordinary.duplicate(true)
	malformed[2].resize(1)
	check(not CityView3D._ordinary_growth_only(before,malformed),"changed layer shape rejects reuse")
	check(not CityView3D._ordinary_growth_only([],ordinary),"uninitialized snapshots reject reuse")
	view.free()

func test_spawn_removal_portals_and_unoccupied_changes_reject_reuse() -> void:
	var city := flat_city()
	var view := CityView3D.new()
	var index := 8*City.WIDTH+8
	for code: int in [Buildings.NONE,Buildings.POWER_LINE_FIRST,Buildings.TUNNEL_FIRST,Buildings.SUBWAY_PORTAL_FIRST,Buildings.RAIL_FIRST,Buildings.MARINA]:
		city.building.put(8,8,code)
		var before := view._geometry_inputs(city)
		city.building.put(8,8,112)
		var after := view._geometry_inputs(city)
		check(not CityView3D._ordinary_growth_only(before,after),"nonordinary predecessor rejects reuse: "+str(code))
		check(not CityView3D._ordinary_growth_only(after,before),"nonordinary successor rejects reuse: "+str(code))
	city.building.put(8,8,112)
	var occupied := view._geometry_inputs(city)
	var zone_edit: Array = occupied.duplicate(true)
	zone_edit[3][index] = Zones.COM_HIGH
	check(CityView3D._ordinary_growth_only(occupied,zone_edit),"occupied ground is untinted despite zone changes")
	var flags_edit: Array = occupied.duplicate(true)
	flags_edit[4][index] = RotationMapper.AXIS_FLAG
	check(CityView3D._ordinary_growth_only(occupied,flags_edit),"ordinary lot flags cannot alter portal geometry")
	for layer: int in [3,4]:
		var neighbor_edit: Array = occupied.duplicate(true)
		neighbor_edit[layer][index+1] = 1
		check(not CityView3D._ordinary_growth_only(occupied,neighbor_edit),"unoccupied adjacent input rejects reuse: "+str(layer))
	view.free()
