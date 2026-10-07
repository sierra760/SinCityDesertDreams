# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

class CountingCity extends City:
	var ground_reads := 0
	func ground_height(x: int,y: int) -> int:
		ground_reads += 1
		return super.ground_height(x,y)

func test_profile_samples_reuse_vertices_with_exact_results() -> void:
	var city := CountingCity.new()
	city.altitude.data.fill(4)
	for x: int in range(40,88):
		city.building.put(x,64,Buildings.ROAD_FIRST+1)
	for x: int in range(58,70):
		city.building.put(x,64,Buildings.BRIDGE_FIRST)
		city.flags.put(x,64,RotationMapper.AXIS_FLAG)
		city.terrain.put(x,64,Terrain.SURFACE)
	city.set_heights(70,64,6,0)
	# A paired sloping highway exercises the repeated grade stencil samples.
	for x: int in range(40,88):
		for y: int in [80,81]:
			city.building.put(x,y,Buildings.HIGHWAY_FIRST+1)
			city.set_heights(x,y,4+int(x%7==0),0)
	var saved := var_to_bytes(SaveFormat.encode_city(city))
	var helper := CityNetworks3D.new()
	helper._prepare_bridge_decks(city)
	var unscoped_reads := city.ground_reads
	var profiles := [helper._deck_profiles.duplicate(true),helper._approach_profiles.duplicate(true)]
	helper.free()
	city.ground_reads=0
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	check_gt(unscoped_reads,100,"fixture has repeated imported ground sampling")
	check_lt(city.ground_reads,unscoped_reads,"a complete graph uses fewer ground reads than one uncached profile pass")
	check_eq(var_to_bytes([graph._decks,graph._approaches]),var_to_bytes(profiles),"complete bridge/approach profiles retain exact values/order")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),saved,"sampling does not change city data")
	check(CityGeometry3D._ground_sampling_city==null,"fresh helper scope does not survive graph binding")

func test_other_city_scope_is_restored_and_raw_edits_are_fresh() -> void:
	var owner := flat_city()
	var previous := CityGeometry3D.begin_ground_sampling(owner)
	CityGeometry3D.point_on_ground(owner,Vector2i(1,1),Vector2(.2,.3))
	CityGeometry3D.road_tunnel_profiles(owner)
	var owner_bytes := var_to_bytes([CityGeometry3D._ground_vertex_cache,CityGeometry3D._ground_corner_cache,CityGeometry3D._road_tunnel_cache])
	var city := flat_city()
	city.building.put(8,8,Buildings.BRIDGE_FIRST)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	check(CityGeometry3D._ground_sampling_city==owner,"outer city sampling owner is restored")
	check_eq(var_to_bytes([CityGeometry3D._ground_vertex_cache,CityGeometry3D._ground_corner_cache,CityGeometry3D._road_tunnel_cache]),owner_bytes,"outer vertex/corner/tunnel caches restore exactly")
	city.altitude.put(8,8,city.altitude.at(8,8)+1)
	city.flood_overlay[Vector2i(8,8)]=4
	graph.refresh()
	var fresh := CityTrafficGraph.new()
	fresh.bind_city(city)
	check_eq(graph._decks,fresh._decks,"raw grade/flood refresh reads current bridge inputs")
	check_eq(graph._approaches,fresh._approaches,"raw grade/flood refresh reads current approach inputs")
	check(CityGeometry3D._ground_sampling_city==owner,"raw refresh also restores the outer city owner")
	check_eq(var_to_bytes([CityGeometry3D._ground_vertex_cache,CityGeometry3D._ground_corner_cache,CityGeometry3D._road_tunnel_cache]),owner_bytes,"raw refresh retains the exact outer caches")
	CityGeometry3D.end_ground_sampling(previous)

func test_same_city_scope_keeps_its_completed_cache_entries() -> void:
	var city := flat_city()
	city.building.put(8,8,Buildings.ROAD_FIRST)
	var previous := CityGeometry3D.begin_ground_sampling(city)
	CityGeometry3D.point_on_ground(city,Vector2i(120,120),Vector2(.2,.3))
	CityGeometry3D.road_tunnel_profiles(city)
	var corners := CityGeometry3D._ground_corner_cache[Vector2i(120,120)] as PackedVector3Array
	var vertices := CityGeometry3D._ground_vertex_cache.duplicate(true)
	var tunnels := CityGeometry3D._road_tunnel_cache.duplicate(true)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	check(CityGeometry3D._ground_sampling_city==city,"existing same-city sampling scope remains active")
	check_eq(CityGeometry3D._ground_corner_cache.get(Vector2i(120,120)),corners,"distant completed corner samples remain available")
	for vertex: Vector2i in vertices:
		check_eq(CityGeometry3D._ground_vertex_cache.get(vertex),vertices[vertex],"completed vertex remains available")
	check_eq(CityGeometry3D._road_tunnel_cache,tunnels,"same-city helper retains completed tunnel profiles")
	CityGeometry3D.end_ground_sampling(previous)
