# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Stream cells pick a shoreline terrain code from their N/E/S/W water-neighbor mask.
extends "res://tests/test_case.gd"

const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const CODES := [0x3d,0x45,0x42,0x38,0x43,0x40,0x35,0x31,
	0x44,0x37,0x41,0x34,0x36,0x33,0x32,0x30]

func wet(data: Dictionary, point: Vector2) -> bool:
	for region: Dictionary in data.water_regions:
		if Geometry2D.is_point_in_polygon(point, region.polygon): return true
	return false

func check_mouths(city: City, mask: int) -> void:
	var cell := Vector2i(15,16)
	var data := CityGeometry3D.build_chunk(city,Rect2i(cell,Vector2i.ONE))
	for i: int in 4:
		var mouth := Vector2(cell)+Vector2(0.5,0.5)+Vector2(DIRECTIONS[i])*0.499
		check_eq(wet(data,mouth),bool(mask & (1<<i)),"mask %d side %d water mouth" % [mask,i])
	check(wet(data,Vector2(cell)+Vector2(0.5,0.5)),"water remains connected through tile center")
	check_eq(data.face_cells.size()*3,data.faces.size(),"canonical picking retains cell owners")

func test_imported_stream_straights_and_caps_open_their_edges() -> void:
	for mask: int in [1,2,4,5,8,10]:
		var city := flat_city()
		city.terrain.put(15,16,CODES[mask])
		city.set_heights(15,16,4,4)
		var before := SaveFormat.encode_city(city)
		check_mouths(city,mask)
		check_eq(SaveFormat.encode_city(city),before,"drawing never rewrites imported layers")

## A native stream joins neighbouring channels across its own width, but beside
## a pool (a water body) it fuses with the pool as full water.
func check_native(city: City, mask: int, neighbor_feature: int) -> void:
	if neighbor_feature == TerrainSurface.Feature.STREAM or mask == 0:
		check_mouths(city,mask)
	else:
		check_mouths(city,15)


func test_native_stream_projection_preserves_all_neighbor_connections() -> void:
	for neighbor_feature: int in [TerrainSurface.Feature.STREAM, TerrainSurface.Feature.NONE]:
		for mask: int in 16:
			var city := flat_city()
			var surface := TerrainSurface.new(4)
			surface.set_water(15,16,5,false,TerrainSurface.Feature.STREAM)
			for i: int in 4:
				if mask & (1<<i):
					var neighbor: Vector2i = Vector2i(15,16)+DIRECTIONS[i]
					surface.set_water(neighbor.x,neighbor.y,5,false,neighbor_feature)
			surface.project(city,Rect2i(14,15,3,3))
			check_eq(city.terrain.at(15,16),CODES[mask],"stream uses the shoreline table for mask %d" % mask)
			check_native(city,mask,neighbor_feature)

func test_imported_channels_join_open_water_across_chunk_boundary_and_reload() -> void:
	for mask: int in [1,2,4,5,8,10]:
		var city := flat_city()
		var cell := Vector2i(15,16)
		city.terrain.putv(cell,CODES[mask])
		city.set_heights(cell.x,cell.y,4,4)
		for i: int in 4:
			if not mask & (1<<i): continue
			var neighbor: Vector2i = cell+DIRECTIONS[i]
			city.terrain.putv(neighbor,Terrain.SURFACE)
			city.set_heights(neighbor.x,neighbor.y,4,4)
			var other := CityGeometry3D.build_chunk(city,Rect2i(neighbor,Vector2i.ONE))
			var mouth := Vector2(cell)+Vector2(0.5,0.5)+Vector2(DIRECTIONS[i])*0.501
			check(wet(other,mouth),"open pool reaches the channel's matching edge")
		check_mouths(city,mask)
		var before := CityGeometry3D.build_chunk(city,Rect2i(cell,Vector2i.ONE))
		var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
		check_eq(restored.error,"")
		check_eq(CityGeometry3D.build_chunk(restored.city,Rect2i(cell,Vector2i.ONE)).faces,before.faces,
			"save reload preserves corrected channel geometry")

func test_native_bends_and_junctions_keep_connections_after_reload_and_edit() -> void:
	for neighbor_feature: int in [TerrainSurface.Feature.STREAM, TerrainSurface.Feature.NONE]:
		for mask: int in 16:
			var city := flat_city()
			var surface := TerrainSurface.new(4)
			surface.set_water(15,16,5,false,TerrainSurface.Feature.STREAM)
			for i: int in 4:
				if not mask & (1<<i): continue
				var neighbor: Vector2i = Vector2i(15,16)+DIRECTIONS[i]
				surface.set_water(neighbor.x,neighbor.y,5,false,neighbor_feature)
			surface.project(city,Rect2i(14,15,3,3))
			var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
			check_eq(restored.error,"")
			var loaded: City = restored.city
			loaded.terrain_surface.project(loaded,Rect2i(15,16,1,1))
			check_eq(loaded.terrain.at(15,16),CODES[mask],"native shoreline survives saved-lattice projection for mask %d" % mask)
			check_native(loaded,mask,neighbor_feature)
