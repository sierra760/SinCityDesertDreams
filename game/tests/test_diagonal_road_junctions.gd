# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const Smoothness := preload("res://tests/test_highway_smoothness.gd")
const Reuse := preload("res://tests/test_network_cell_reuse.gd")
const CENTER := Vector2i(31,31)
const YELLOW := Color(.86,.72,.36)

static func rotated(p: Vector2, quarter: int) -> Vector2:
	for i: int in quarter: p = Vector2(1-p.y,p.x)
	return p

static func mask_rotated(mask: int, quarter: int) -> int:
	for i: int in quarter: mask = ((mask<<1)&15)|(mask>>3)
	return mask

static func stamp(city: City, cell: Vector2i, mask: int) -> void:
	city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))

static func fixture(quarter: int = 0, extra: int = 4) -> City:
	var city := flat_city()
	stamp(city,CENTER,mask_rotated(3|extra,quarter))
	for direction: int in [0,1]:
		stamp(city,CENTER+NetworkShapes.DIRECTIONS[(direction+quarter)%4],mask_rotated(12,quarter))
	return city

static func layer_for(city: City, cell: Vector2i = CENTER) -> CityNetworks3D:
	var layer := CityNetworks3D.new()
	layer._build_region(city,Rect2i(cell,Vector2i.ONE))
	return layer

func test_diagonal_lane_and_lines_continue_through_every_junction_orientation() -> void:
	for quarter: int in 4:
		for extra: int in [4,8,12]:
			var city := fixture(quarter,extra)
			var saved := var_to_bytes(SaveFormat.encode_city(city))
			var layer := layer_for(city)
			for p: Vector2 in [Vector2(.89,.11),Vector2(.94,.16),Vector2(.84,.06)]:
				check(not Smoothness.pavement_hit(layer,Vector2(CENTER)+rotated(p,quarter)).is_empty(),"full diagonal lane crosses the former notch")
			for p: Vector2 in [Vector2(.06,.06),Vector2(.94,.94),Vector2(.06,.94),Vector2(.19,.19),Vector2(.81,.81),Vector2(.19,.81)]:
				check(Smoothness.pavement_hit(layer,Vector2(CENTER)+rotated(p,quarter)).is_empty(),"the other sand corners remain outside the junction pavement")
			var diagonal_vertices := 0
			var inward_stubs := 0
			for i: int in layer._faces.size():
				if not layer._colors[i].is_equal_approx(YELLOW): continue
				var p := rotated(Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(CENTER),(4-quarter)%4)
				if absf(p.x-p.y-.5)<.01101: diagonal_vertices+=1
				elif p.y<.18 or p.x>.82: inward_stubs+=1
			check_gt(diagonal_vertices,0,"junction dashes follow the diagonal centerline")
			check_eq(inward_stubs,0,"diagonal entry and exit have no inward-turning lane-line stubs")
			for direction: int in 4:
				if mask_rotated(3|extra,quarter)&(1<<direction):
					var p := Vector2(.5,.5)+Vector2(NetworkShapes.DIRECTIONS[direction])*.47
					check(not Smoothness.pavement_hit(layer,Vector2(CENTER)+p).is_empty(),"side-street mouths retain their pavement")
			check_eq(var_to_bytes(SaveFormat.encode_city(city)),saved,"projection preserves saved city")
			layer.free()

func test_orthogonal_and_unconfirmed_junctions_keep_their_shape() -> void:
	for wrong: int in [0,3,6,9]:
		var city := fixture()
		city.building.putv(CENTER+Vector2i.UP,Buildings.NONE if wrong==0 else NetworkShapes.shape_id(NetworkShapes.Family.ROAD,wrong))
		var layer := layer_for(city)
		check(Smoothness.pavement_hit(layer,Vector2(CENTER)+Vector2(.89,.11)).is_empty(),"missing or misaligned diagonal neighbor cannot round a junction")
		layer.free()

func test_consecutive_junctions_keep_a_diagonal_between_authored_bends() -> void:
	var city := fixture()
	# Three junctions along one staircase; the outer bends anchor its direction.
	stamp(city,CENTER+Vector2i.UP,13)
	stamp(city,CENTER+Vector2i(-1,-1),7)
	stamp(city,CENTER+Vector2i(-1,-2),12)
	for cell: Vector2i in [CENTER,CENTER+Vector2i.UP,CENTER+Vector2i(-1,-1)]:
		var layer := layer_for(city,cell)
		var p := Vector2(.11,.89) if cell==CENTER+Vector2i.UP else Vector2(.89,.11)
		check(not Smoothness.pavement_hit(layer,Vector2(cell)+p).is_empty(),"diagonal survives consecutive junctions")
		layer.free()

func test_pedestrian_heights_follow_the_filled_lane_and_shoulder() -> void:
	for quarter: int in 4:
		var city := fixture(quarter)
		var graph := CityTrafficGraph.new(); graph.bind_city(city)
		for sample: Vector3 in [Vector3(.89,.04,.11),Vector3(.91,.032,.09),Vector3(.94,.024,.06)]:
			var p := rotated(Vector2(sample.x,sample.z),quarter)
			var ground := CityGeometry3D.point_on_ground(city,CENTER,p).y
			check(absf(graph.walk_point(CENTER,p).y-ground-sample.y)<.00001,"feet follow the actual diagonal material height")

func test_neighbor_edits_across_region_boundaries_match_fresh_emission() -> void:
	var city := fixture()
	var root := CityNetworks3D.new(); Reuse._project(root,city)
	for mask: int in [10,12]:
		stamp(city,CENTER+Vector2i.RIGHT,mask)
		Reuse._project(root,city)
		var fresh := CityNetworks3D.new(); Reuse._project(fresh,city)
		for origin: Vector2i in root._regions:
			check(var_to_bytes(Reuse._layer(root._regions[origin]))==var_to_bytes(Reuse._layer(fresh._regions[origin])),"neighbor edit refreshes all dependent region arrays at %s" % origin)
		fresh.free()
	root.free()

func test_valle_del_mar_junctions_have_continuous_diagonal_lanes() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Valle del Mar.sc2")
	check(loaded.ok,"Valle del Mar imports")
	if not loaded.ok: return
	for sample: Vector3 in [Vector3(43,0,12),Vector3(44,0,13),Vector3(38,2,6),Vector3(39,2,7)]:
		var cell := Vector2i(sample.x,sample.z)
		var layer := layer_for(loaded.city,cell)
		check(not Smoothness.pavement_hit(layer,Vector2(cell)+rotated(Vector2(.89,.11),int(sample.y))).is_empty(),"real Valle diagonal no longer pinches inward at %s" % cell)
		layer.free()

func test_street_signs_stay_out_of_the_continuous_diagonal_lane() -> void:
	for quarter: int in 4:
		var city := fixture(quarter)
		var graph := CityTrafficGraph.new(); graph.bind_city(city)
		var faces: Array[Dictionary] = [{"direction":Vector2i.UP},{"direction":Vector2i.RIGHT}]
		var placement := StreetSignPlacement3D.intersection(city,{"channel":&"open","position":Vector3(CENTER.x+.5,0,CENTER.y+.5)},faces,graph)
		check(placement.ok,"diagonal junction still has a safe sign corner")
		if not placement.ok: continue
		var filled := PackedVector2Array()
		for p: Vector2 in [Vector2(.8,0),Vector2(1,.2),Vector2(.8,.2)]: filled.append(Vector2(CENTER)+rotated(p,quarter))
		for box: AABB in placement.support.component_bounds:
			var polygon := PackedVector2Array([Vector2(box.position.x,box.position.z),Vector2(box.end.x,box.position.z),Vector2(box.end.x,box.end.z),Vector2(box.position.x,box.end.z)])
			check(Geometry2D.intersect_polygons(polygon,filled).is_empty(),"the complete street sign clears the newly filled diagonal lane")


func test_street_lamp_posts_remain_on_sand_at_diagonal_junctions() -> void:
	for quarter: int in 4:
		var city := fixture(quarter)
		var graph := CityTrafficGraph.new(); graph.bind_city(city)
		var lamps := CityStreetLamps3D.new()
		var placed := lamps._road_lamp(graph,city,CENTER)
		check(not placed.is_empty(),"diagonal junction keeps its lamp")
		if not placed.is_empty():
			var at: Vector3 = placed.transform.origin
			var layer := layer_for(city)
			check(Smoothness.pavement_hit(layer,Vector2(at.x,at.z)).is_empty(),"lamp post remains outside the continuous diagonal lane")
			layer.free()
		lamps.free()

func test_lamp_corner_updates_when_a_distant_diagonal_anchor_is_removed() -> void:
	var city := fixture(1)
	stamp(city,CENTER+Vector2i.RIGHT,11)
	stamp(city,CENTER+Vector2i(1,-1),7)
	stamp(city,CENTER+Vector2i(2,-1),9)
	var graph := CityTrafficGraph.new(); graph.bind_city(city)
	var lamps := CityStreetLamps3D.new(); root.add_child(lamps); lamps.sync(graph)
	var before: Vector3 = lamps._road_lamps[CENTER].transform.origin
	stamp(city,CENTER+Vector2i(2,-1),10)
	graph.refresh(); lamps.sync(graph)
	check(lamps.last_sync_incremental,"third-neighbor edit uses incremental lamp planning")
	var after: Vector3 = lamps._road_lamps[CENTER].transform.origin
	check(Vector2(before.x,before.z) != Vector2(after.x,after.z),"removing the diagonal restores its original lamp corner")
	check(var_to_bytes(lamps.placements)==var_to_bytes(lamps.plan(graph)),"incremental lamps equal a complete plan after distant anchor edit")
	lamps.free()
