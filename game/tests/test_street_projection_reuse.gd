# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

class CountedTopology extends StreetTopology:
	var additions := 0
	func _add_node(cell: Vector2i, channel: StringName, mask: int) -> void:
		additions += 1
		super._add_node(cell,channel,mask)

func compare_fresh(topology: StreetTopology, city: City) -> void:
	var fresh := StreetTopology.new()
	fresh.rebuild(city)
	check_eq(topology._nodes,fresh._nodes,"nodes equal fresh full projection")
	check_eq(topology._links,fresh._links,"link identities and complete points equal fresh")
	check_eq(topology._exits,fresh._exits,"departures equal fresh")
	check_eq(topology._bores,fresh._bores,"tunnel surfaces equal fresh")

func fixture() -> City:
	var city := flat_city()
	for x: int in range(4,16): city.building.put(x,8,30)
	city.stamp_building(7,7,112)
	return city

func test_ordinary_growth_retains_completed_projection() -> void:
	var city := fixture()
	var topology := CountedTopology.new()
	topology.rebuild(city)
	var token := topology.revision
	topology.additions = 0
	city.building.put(7,7,113)
	city.zone.put(7,7,Zones.COM_HIGH)
	city.flags.put(7,7,RotationMapper.AXIS_FLAG)
	check(not topology.rebuild(city),"ordinary growth preserves selection token")
	check_eq(topology.revision,token,"token remains exact")
	check_eq(topology.additions,0,"ordinary growth avoids road projection work")
	compare_fresh(topology,city)
	city.flood_overlay[Vector2i(8,8)] = 4
	topology.rebuild(city)
	compare_fresh(topology,city)
	city.flood_overlay.clear()
	topology.rebuild(city)
	compare_fresh(topology,city)

func test_raw_geometry_roads_and_binding_refresh_immediately() -> void:
	var city := fixture()
	var topology := CountedTopology.new()
	topology.rebuild(city)
	for change: int in range(5):
		topology.additions = 0
		match change:
			0: city.altitude.put(8,8,5)
			1: city.terrain.put(9,8,1)
			2: city.building.put(10,8,0)
			3: city.building.put(9,9,Buildings.TUNNEL_FIRST)
			4: city.flags.put(8,8,RotationMapper.AXIS_FLAG)
		topology.rebuild(city)
		check(topology.additions>0,"raw structural inputs rebuild "+str(change))
		compare_fresh(topology,city)
	var new_city := city.duplicate_city()
	var token := topology.revision
	check(topology.rebuild(new_city),"distinct city binding rebuilds")
	check_ne(topology.revision,token,"distinct city invalidates selection token")
	compare_fresh(topology,new_city)
	topology.rebuild(null)
	check(topology._nodes.is_empty() and topology._links.is_empty(),"release clears projection")

func test_all_bundled_cities_retain_exact_street_points_after_ordinary_changes() -> void:
	for name: String in ["La Presa","Foothills Ranch","Aliso Niguel","Oro Canyon","Valle del Mar","Lawndale","Salton Shores","Grant Pass - Soledad"]:
		var path := "res://assets/cities/"+name+".sc2"
		check(FileAccess.file_exists(path),"bundled city exists: "+name)
		var loaded := Sc2Import.load(path)
		check(loaded.ok,"bundled city imports: "+name)
		if not loaded.ok: continue
		var city: City = loaded.city
		var source_hash := FileAccess.get_sha256(path)
		var topology := CountedTopology.new()
		var encoded := SaveFormat.encode_city(city)
		topology.rebuild(city)
		check_eq(SaveFormat.encode_city(city),encoded,"projection preserves city payload: "+name)
		topology.additions = 0
		topology.rebuild(city)
		check_eq(topology.additions,0,"identical exact inputs reuse projection: "+name)
		for i: int in city.building.data.size():
			if city.building.data[i]==112:
				city.building.data[i]=113
				break
		topology.rebuild(city)
		check_eq(topology.additions,0,"ordinary lot changes retain roads: "+name)
		compare_fresh(topology,city)
		check_eq(FileAccess.get_sha256(path),source_hash,"source bytes remain unchanged: "+name)
