# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

class CountingLayer extends CityNetworks3D:
	var profile_builds := 0
	func _prepare_bridge_decks(city: City) -> void:
		profile_builds += 1
		super._prepare_bridge_decks(city)

const REGION := Rect2i(0,0,16,16)
const Tunnels := preload("res://scripts/view/city_road_tunnels_3d.gd")

func _profiles(layer: CityNetworks3D) -> Array:
	return [layer._deck_profiles,layer._approach_profiles,layer._road_tunnels]

func _fresh_profiles(city: City) -> Array:
	var fresh := CityNetworks3D.new()
	fresh._prepare_bridge_decks(city)
	var result := [fresh._deck_profiles.duplicate(true),fresh._approach_profiles.duplicate(true),Tunnels.profiles(city)]
	fresh.free()
	return result

func test_ordinary_lots_retain_profiles_meshes_and_completed_physics() -> void:
	var city := flat_city()
	city.building.put(8,8,Buildings.RES_1X1_FIRST)
	city.building.put(10,8,Buildings.ROAD_FIRST)
	var layer := CountingLayer.new()
	root.add_child(layer)
	layer.update_regions(city,[REGION])
	var profile_bytes := var_to_bytes(_profiles(layer))
	var physical_bytes := var_to_bytes(layer.physical_data())
	var region_id: int = layer._regions[Vector2i.ZERO].get_instance_id()
	city.building.put(8,8,Buildings.RES_1X1_FIRST+1)
	city.flags.put(8,8,RotationMapper.AXIS_FLAG|TileFlags.POWERED|TileFlags.WATERED)
	city.zone.put(8,8,Zones.CORNER_SE|Zones.COM_HIGH)
	check(layer.update_regions(city,[REGION]).is_empty(),"ordinary edits rebuild no network chunk")
	check_eq(layer.profile_builds,1,"ordinary edits do no repeated global projection")
	check_eq(var_to_bytes(_profiles(layer)),profile_bytes,"completed profiles are exact")
	check_eq(var_to_bytes(layer.physical_data()),physical_bytes,"completed traversal projection is exact")
	check_eq(layer._regions[Vector2i.ZERO].get_instance_id(),region_id,"existing road owner survives")
	layer.update_regions(city,[REGION])
	check_eq(layer.profile_builds,1,"repeated advisory refresh does no global projection")
	layer.free()

func test_raw_dependencies_refresh_without_notification() -> void:
	var city := flat_city()
	city.building.put(8,8,Buildings.BRIDGE_FIRST)
	city.flags.put(8,8,RotationMapper.AXIS_FLAG)
	var layer := CountingLayer.new()
	root.add_child(layer)
	layer.update_regions(city,[REGION])
	var edits: Array[Callable] = [
		func() -> void: city.building.put(8,8,Buildings.BRIDGE_FIRST+1),
		func() -> void: city.flags.put(8,8,0),
		func() -> void: city.altitude.put(8,8,city.altitude.at(8,8)+1),
		func() -> void: city.set_tunnel_bits(8,8,2),
		func() -> void: city.terrain.put(8,8,Terrain.SURFACE),
		func() -> void: city.flood_overlay[Vector2i(8,8)]=3,
		func() -> void: city.flood_overlay[Vector2i(8,8)]=4,
		func() -> void: city.flood_overlay.clear(),
		func() -> void: city.building.put(8,8,NetworkShapes.HIGHWAY_CORNER_NE),
		func() -> void: city.zone.put(8,8,Zones.CORNER_NW),
		func() -> void: city.zone.put(8,8,Zones.CORNER_SE),
		func() -> void: city.terrain_surface=TerrainSurface.from_city(city),
		func() -> void: city.terrain_surface.vertices[8*TerrainSurface.VERTS_X+8]+=1,
		func() -> void: city.sea_level+=1,
	]
	for i: int in edits.size():
		edits[i].call()
		var builds := layer.profile_builds
		layer.update_regions(city,[REGION])
		check_eq(layer.profile_builds,builds+1,"changed raw dependency rebuilds: "+str(i))
		check_eq(var_to_bytes(_profiles(layer)),var_to_bytes(_fresh_profiles(city)),"raw dependency profiles match fresh projection: "+str(i))
	layer.free()

func test_clear_full_rebuild_and_new_city_invalidate_retained_inputs() -> void:
	var city := flat_city()
	city.building.put(8,8,Buildings.ROAD_FIRST)
	var layer := CountingLayer.new()
	root.add_child(layer)
	layer.update_regions(city,[REGION])
	var before := layer.profile_builds
	var copy := city.duplicate_city()
	layer.update_regions(copy,[REGION])
	check_eq(layer.profile_builds,before+1,"another city gets its own projection even with identical bytes")
	before=layer.profile_builds
	layer.clear()
	layer.update_regions(copy,[REGION])
	check_eq(layer.profile_builds,before+1,"clear expires the completed input guard")
	before=layer.profile_builds
	layer.rebuild(copy)
	layer.update_regions(copy,[REGION])
	check_eq(layer.profile_builds,before+2,"full rebuild expires prior regional profile state")
	check_eq(var_to_bytes(_profiles(layer)),var_to_bytes(_fresh_profiles(copy)),"lifecycle profiles remain exact")
	layer.free()
