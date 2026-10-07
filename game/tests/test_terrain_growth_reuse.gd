# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Growth that leaves terrain unchanged keeps its chunks; zone tint changes
## recolour the affected chunk in place.
extends "res://tests/exploration/async_test_case.gd"


func _level_city() -> City:
	var city := City.new()
	city.altitude.data.fill(4)
	return city

class CountedView extends CityView3D:
	var replacements := 0
	func _replace_terrain_chunk(region: Rect2i) -> void:
		replacements += 1
		super._replace_terrain_chunk(region)

func test_growth_reuses_terrain_chunks() -> void:
	var city := _level_city()
	city.stamp_building(8,8,112)
	var view := CountedView.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var held := view.traversal_snapshot()
	var ids: Array[int] = []
	for child: Node in view.chunks.get_children(): ids.append(child.get_instance_id())
	view.replacements = 0
	city.building.put(8,8,113)
	city.zone.put(8,8,Zones.COM_HIGH)
	city.flags.put(8,8,RotationMapper.AXIS_FLAG)
	view.refresh()
	check_eq(view.replacements,0,"occupied ordinary growth does not rebuild identical terrain")
	var current_ids: Array[int] = []
	for child: Node in view.chunks.get_children(): current_ids.append(child.get_instance_id())
	check_eq(current_ids,ids,"terrain and picking bodies retain identity")
	for region: Rect2i in [Rect2i(0,0,16,16)]:
		var scope := CityGeometry3D.begin_ground_sampling(city)
		var fresh := CityGeometry3D.build_chunk(city,region)
		CityGeometry3D.end_ground_sampling(scope)
		for field: String in ["faces","face_cells","physical_floor_faces","physical_obstacle_faces","water_regions"]:
			check_eq(view.traversal_snapshot().chunks[0][field],fresh[field],"retained terrain equals full fresh "+field)
	check_eq(held.chunks[0].faces,view.traversal_snapshot().chunks[0].faces,"completed traversal history remains exact")
	view.replacements = 0
	var far_chunk: MeshInstance3D = view._terrain_nodes[Vector2i(96,96)][0]
	city.building.put(8,8,112)
	city.stamp_building(100,100,112)
	view.refresh()
	check_eq(view.replacements,0,"mixed growth replaces no terrain chunk")
	check_eq(view.refresh_statistics.terrain_recolored_chunks,1,"mixed growth recolours only the chunk with a newly occupied tile")
	check_eq(view._terrain_nodes[Vector2i(96,96)][0],far_chunk,"the recoloured chunk keeps its mesh node")
	check_eq(view._terrain_nodes[Vector2i.ZERO][0].get_instance_id(),ids[0],"mixed distant placement retains unchanged occupied terrain")
	view.replacements = 0
	city.building.put(8,8,0)
	view.refresh()
	check_eq(view.replacements,0,"removing occupied zoned ground replaces no terrain chunk")
	check_eq(view.refresh_statistics.terrain_recolored_chunks,1,"removing occupied zoned ground recolours its newly visible tint")
	held.clear()
	view.free()
	await process_frame
	await process_frame
