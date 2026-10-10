# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Incremental projections must preserve distant identities and full-build geometry.
extends "res://tests/exploration/async_test_case.gd"

func test_water_patch_rebuilds_distant_chunks_when_its_bank_changes() -> void:
	var city := flat_city(20000, 6)
	var surface := TerrainSurface.new(6)
	for y: int in range(20, 24):
		for x: int in range(10, 58):
			surface.set_tile_height(x, y, 5)
			surface.set_water(x, y, 6)
	surface.project(city)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	# A low bank at the west end sets the water plane beyond three chunk borders.
	surface.set_vertex(10, 21, 4)
	surface.project(city)
	view.refresh()
	_compare_full(view, "distant low water bank")
	# Restore the bank; retained geometry must rise with the complete patch.
	surface.set_vertex(10, 21, 5)
	surface.project(city)
	view.refresh()
	_compare_full(view, "restored water bank")
	view.free()
	await process_frame

func _lot(view: CityView3D, cell: Vector2i) -> Node:
	for child: Node in view.buildings.get_children():
		if child.get_meta("cell", Vector2i(-1,-1)) == cell: return child
	return null
func test_incremental_refresh_matches_full_rebuild() -> void:
	var city := City.new()
	city.altitude.data.fill(4)
	city.stamp_building(8,8,Buildings.RES_1X1_FIRST)
	city.stamp_building(100,100,Buildings.RES_1X1_FIRST)
	city.stamp_building(101,100,Buildings.RES_1X1_FIRST)
	city.building.put(100,90,30)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var far_network_id: int = view.networks._regions[Vector2i(96,80)].get_instance_id()
	var far_batches := _batch_ids(view, Vector2i(3,3))
	check(not far_batches.is_empty(),"fixture has actual distant mesh batches")
	var far_id := _lot(view,Vector2i(100,100)).get_instance_id()
	var initial_full_us: int = view.refresh_statistics.microseconds
	var chunk_id := view.chunks.get_child(view.chunks.get_child_count()-1).get_instance_id()
	var rev: int = view.traversal_snapshot().revision
	city.building.put(8,8,Buildings.RES_1X1_FIRST+1)
	view.refresh()
	check(_lot(view,Vector2i(100,100)).get_instance_id() == far_id,"a local growth update preserves the distant lot and its bodies")
	check(view.chunks.get_child(view.chunks.get_child_count()-1).get_instance_id() == chunk_id,"a local growth update preserves distant terrain bodies")
	print("LOCAL_REFRESH full_us=",initial_full_us," incremental_us=",view.refresh_statistics.microseconds," chunks=",view.refresh_statistics.terrain_chunks," network_chunks=",view.refresh_statistics.network_chunks)
	check(view.networks._regions[Vector2i(96,80)].get_instance_id() == far_network_id,"local growth retains distant network nodes")
	check(_batch_ids(view,Vector2i(3,3)) == far_batches,"local growth retains distant GPU batch nodes")
	check(view.traversal_snapshot().revision == rev+1,"geometry signal revision advances exactly once")
	far_id = _lot(view,Vector2i(100,100)).get_instance_id()
	rev = view.traversal_snapshot().revision
	city.flags.put(8,8,city.flags.at(8,8)|TileFlags.POWERED|TileFlags.WATERED)
	view.refresh()
	check(view.traversal_snapshot().revision == rev,"service-only changes do not revise geometry")
	check(_lot(view,Vector2i(100,100)).get_instance_id() == far_id,"service-only changes preserve models")
	check(view.refresh_statistics.terrain_chunks == 0, "utility update does zero static chunk work")
	city.signs[Vector2i(9,9)] = "Local sign"
	view.refresh()
	check(view.traversal_snapshot().revision == rev and view._labels.get_child_count() == 1, "signs refresh labels without rebuilding geometry")
	# Direct packed-array writes have no edit notification.
	city.building.data[8*City.WIDTH+8] = Buildings.RES_1X1_FIRST+2
	view.refresh()
	check(_lot(view,Vector2i(8,8)).get_meta("code") == Buildings.RES_1X1_FIRST+2, "raw grid writes update the affected model")
	check(view.refresh_statistics.terrain_chunks == 1, "interior local growth builds one terrain chunk rather than 64")
	_compare_full(view, "raw growth")
	var held := view.traversal_snapshot()
	var held_faces: PackedVector3Array = held.chunks[0].faces.duplicate()
	city.altitude.data[8*City.WIDTH+8] = 7
	view.refresh()
	check(held.chunks[0].faces == held_faces, "old traversal snapshots retain their completed terrain revision")
	_compare_full(view, "raw terrain")
	city.stamp_building(15,15,Buildings.RES_2X2_FIRST)
	view.refresh()
	_compare_full(view,"multi-cell growth across chunk corners")
	city.clear_footprint(16,16)
	view.refresh()
	check(_lot(view,Vector2i(15,15)) == null,"removing a non-anchor cell removes canonical lot model")
	_compare_full(view,"multi-cell removal")
	# A span crossing four chunk boundaries must react to its far bank.
	for x: int in range(14,67):
		city.building.put(x,30,87)
		city.flags.put(x,30,RotationMapper.AXIS_FLAG)
		city.terrain.put(x,30,Terrain.SURFACE)
		city.set_heights(x,30,1,3)
	city.building.put(13,30,30)
	city.building.put(67,30,30)
	view.refresh()
	_compare_full(view,"cross-chunk bridge")
	city.set_heights(67,30,8)
	view.refresh()
	check(view.refresh_statistics.network_chunks >= 4,"bank edit invalidates every dependent span region")
	_compare_full(view,"distant bridge bank")
	# An odd 2x2 highway block straddles both chunk boundaries.
	for y: int in 2:
		for x: int in 2:
			city.building.put(47+x,47+y,101)
			city.zone.put(47+x,47+y,Zones.corner_flags_for(x,y,2,2))
	city.building.put(63,60,Buildings.TUNNEL_FIRST)
	city.building.put(64,60,Buildings.SUBWAY_PORTAL_FIRST)
	view.refresh()
	_compare_full(view,"highway boundary and portals")
	city.building.put(48,48,0)
	city.building.put(63,60,0)
	view.refresh()
	_compare_full(view,"partial block and removed portal")
	for cell: Vector2i in [Vector2i(80,15),Vector2i(81,15),Vector2i(81,16)]:
		city.stamp_building(cell.x,cell.y,Buildings.PIER)
		city.terrain.putv(cell,Terrain.SURFACE)
		city.set_heights(cell.x,cell.y,1,4)
	city.stamp_building(78,19,Buildings.MARINA)
	for y: int in range(19,22):
		for x: int in range(78,81):
			city.terrain.put(x,y,Terrain.SURFACE)
			city.set_heights(x,y,1,4)
	view.refresh()
	_compare_full(view,"coastal pier and marina")
	city.building.put(81,15,0)
	city.terrain.put(78,19,0)
	city.set_heights(78,19,5,4)
	view.refresh()
	_compare_full(view,"coastal orientation and berth change")
	city.flood_overlay[Vector2i(16,80)] = 1
	view.refresh()
	_compare_full(view,"flood add")
	city.flood_overlay.clear()
	view.refresh()
	_compare_full(view,"flood removal")
	city.terrain_surface = TerrainSurface.new(4)
	view.refresh()
	city.terrain_surface.vertices[16*TerrainSurface.VERTS_X+16] = 5
	view.refresh()
	check(view.refresh_statistics.terrain_chunks == 4,"shared vertex at four-chunk corner refreshes all neighbors")
	_compare_full(view,"raw shared vertex")
	# Rounded highway sampling reaches beyond a terrain cell. Edits beside a
	# chunk boundary must rebuild every dependent deck without stale seams.
	for y: int in range(46,52):
		for x: int in range(60,71):
			city.terrain_surface.set_vertex(x,y,4+clampi(x-63,0,2))
	city.terrain_surface.project(city,Rect2i(60,46,11,6))
	for y: int in [48,49]:
		for x: int in range(60,70):
			city.building.put(x,y,NetworkShapes.highway_id(10,NetworkShapes.AXIS_EW,city.terrain.at(x,y)))
	view.refresh()
	_compare_full(view,"rounded highway crosses chunk boundary")
	city.terrain_surface.set_vertex(65,49,7)
	city.terrain_surface.project(city,Rect2i(64,48,2,2))
	view.refresh()
	_compare_full(view,"edited rounded highway stencil")
	rev = view.traversal_snapshot().revision
	city.building.put(8,8,Buildings.RES_1X1_FIRST+3)
	view.queue_refresh()
	view.queue_refresh()
	await process_frame
	await process_frame
	check(view.traversal_snapshot().revision == rev+1,"repeated deferred notifications produce one geometry revision")
	view.set_active(false)
	rev = view.traversal_snapshot().revision
	city.building.put(8,8,Buildings.RES_1X1_FIRST+4)
	view.queue_refresh()
	await process_frame
	check(view.traversal_snapshot().revision == rev,"inactive refresh queue defers work")
	view.set_active(true)
	check(view.traversal_snapshot().revision == rev+1 and _lot(view,Vector2i(8,8)).get_meta("code") == Buildings.RES_1X1_FIRST+4,"activation catches raw writes while inactive")
	view.free()
	await process_frame
	await process_frame


func _triangles(faces: PackedVector3Array) -> Array:
	var values: Array = []
	for i: int in range(0,faces.size(),3):
		values.append(var_to_bytes(faces.slice(i,i+3)).hex_encode())
	values.sort()
	return values

func _physical(data: Dictionary) -> Array:
	var boxes: Array = []
	for box: Dictionary in data.physical_boxes: boxes.append(var_to_bytes([box.transform,box.size]).hex_encode())
	boxes.sort()
	return [_triangles(data.physical_floor_faces),_triangles(data.physical_obstacle_faces),boxes]

func _models(view: CityView3D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node3D in view.buildings.get_children():
		var shapes: Array = []
		_shape_snapshot(child,Transform3D.IDENTITY,shapes)
		shapes.sort()
		result[child.get_meta("cell")] = [child.get_meta("code"),child.transform,shapes]
	return result

func _shape_snapshot(node: Node, transform: Transform3D, shapes: Array) -> void:
	if node is Node3D: transform *= node.transform
	if node is CollisionShape3D:
		var data: Variant = node.shape.size if node.shape is BoxShape3D else node.shape.get_debug_mesh().get_aabb()
		shapes.append(var_to_bytes([transform,data,node.get_parent().collision_layer]).hex_encode())
	for child: Node in node.get_children(): _shape_snapshot(child,transform,shapes)

func _compare_full(view: CityView3D, label: String) -> void:
	var started := Time.get_ticks_usec()
	var work := view.refresh_statistics.duplicate()
	var incremental := view.traversal_snapshot()
	var models := _models(view)
	var physics := _physical(incremental.networks)
	var visuals := _network_faces(view.networks)
	var legacy := CityNetworks3D.new()
	legacy.rebuild(view.city)
	check(_network_faces(legacy) == visuals, label+": colored network surfaces equal original unsplit geometry")
	check(_physical(legacy.physical_data()) == physics, label+": regional networks match original unsplit physical geometry")
	legacy.free()
	view.refresh(true)
	var full := view.traversal_snapshot()
	check(_network_faces(view.networks) == visuals,label+": colored network surfaces equal forced full geometry")
	check(_models(view) == models,label+": lot transforms and collision shells equal full rebuild")
	check(_physical(full.networks) == physics,label+": network physical triangles/boxes equal full rebuild")
	var equal := true
	for i: int in full.chunks.size():
		for key: String in full.chunks[i]:
			if key == "mesh": continue
			if full.chunks[i][key] != incremental.chunks[i][key]: equal = false
	check(equal,label+": terrain/query/traversal geometry equals full rebuild")
	print("DIFFERENTIAL ",label," incremental_work=",work," full_work=",view.refresh_statistics," check_elapsed_us=",Time.get_ticks_usec()-started)


func _network_faces(layer: CityNetworks3D) -> Array:
	var values: Array = []
	for i: int in range(0,layer._faces.size(),3):
		values.append(var_to_bytes([layer._faces.slice(i,i+3),layer._colors.slice(i,i+3),layer._cells[i/3]]).hex_encode())
	for child: Node in layer.get_children():
		if child is CityNetworks3D: values.append_array(_network_faces(child))
	values.sort()
	return values


func _batch_ids(view: CityView3D, chunk: Vector2i) -> Array:
	var ids: Array = []
	for batch: Node in view.mesh_batches.get_children():
		if batch.get_meta("chunk",Vector2i(-1,-1)) == chunk: ids.append(batch.get_instance_id())
	ids.sort()
	return ids
