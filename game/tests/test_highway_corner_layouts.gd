# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Saved footprint orientations must retain connected highway curves and lanes.
extends "res://tests/test_case.gd"

const Smoothness := preload("res://tests/test_highway_smoothness.gd")
const LAYOUTS := [[16,32,128,64], [32,64,16,128], [64,128,32,16], [128,16,64,32]]
const ORO_BLOCKS := [[38,10,102], [54,10,105], [32,12,102], [38,12,104], [10,14,105],
	[32,14,104], [54,104,101], [56,104,103], [56,106,101], [60,106,103],
	[10,112,101], [12,112,103], [12,114,101], [14,114,103], [14,116,101],
	[16,116,103], [16,118,101], [18,118,103], [18,120,101], [20,120,103]]


static func stamp(city: City, anchor: Vector2i, code: int, flags: Array) -> void:
	for dy: int in 2:
		for dx: int in 2:
			city.building.putv(anchor+Vector2i(dx,dy),code)
			city.zone.putv(anchor+Vector2i(dx,dy),flags[dy*2+dx])


## Independent concentric lane centers in each authored quarter turn.
static func lane_point(anchor: Vector2i, code: int, radius: float, t: float) -> Vector2:
	var quarter := code-101
	var pivot: Vector2 = [Vector2(2,0),Vector2(2,2),Vector2(0,2),Vector2.ZERO][quarter]
	var angle: float = [PI,-PI*.5,0.0,PI*.5][quarter]-t*PI*.5
	return Vector2(anchor)+pivot+Vector2(cos(angle),sin(angle))*radius


func test_all_saved_flag_orientations_keep_complete_curves_and_junctions() -> void:
	var gaps := 0
	for flags: Array in LAYOUTS:
		for anchor: Vector2i in [Vector2i(30,30),Vector2i(47,47)]:
			for code: int in range(101,106):
				var city := flat_city()
				stamp(city,anchor,code,flags)
				var before := var_to_bytes([city.building.data,city.zone.data,city.flags.data])
				for dy: int in 2:
					for dx: int in 2:
						check_eq(CityNetworks3D.highway_footprint(city,anchor+Vector2i(dx,dy),code),anchor,
							"every quadrant resolves the same complete block")
				var layer := CityNetworks3D.new()
				layer._build_region(city,Rect2i(anchor,Vector2i(2,2)))
				for radius: float in [.28,.72,1.28,1.72]:
					for step: int in 33:
						var point := lane_point(anchor,code,radius,step/32.0) if code<105 else Vector2(anchor)+Vector2(radius,step/16.0)
						if Smoothness.pavement_hit(layer,point).is_empty():gaps += 1
						if code==105 and Smoothness.pavement_hit(layer,Vector2(point.y-anchor.y+anchor.x,radius+anchor.y)).is_empty():gaps += 1
				check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data]),before,"layout recognition is read-only")
				layer.free()
	check_eq(gaps,0,"both carriageways and junction axes have continuous pavement for every retained layout")


func test_partial_mirrored_and_mixed_flags_do_not_merge_blocks() -> void:
	for anchor: Vector2i in [Vector2i(30,30),Vector2i(47,47)]:
		for flags: Array in LAYOUTS:
			var city := flat_city()
			stamp(city,anchor,101,flags)
			city.building.putv(anchor+Vector2i.ONE,0)
			check_eq(CityNetworks3D.highway_footprint(city,anchor,101),Vector2i(-1,-1),"missing quadrant is rejected")
			city.building.putv(anchor+Vector2i.ONE,102)
			check_eq(CityNetworks3D.highway_footprint(city,anchor,101),Vector2i(-1,-1),"mixed shapes are rejected")
			stamp(city,anchor,101,[flags[0],flags[1],flags[3],flags[2]])
			check_eq(CityNetworks3D.highway_footprint(city,anchor,101),Vector2i(-1,-1),"a mirrored permutation is not a saved orientation")
			stamp(city,anchor,101,[flags[0],flags[1],flags[2],flags[0]])
			check_eq(CityNetworks3D.highway_footprint(city,anchor,101),Vector2i(-1,-1),"duplicated flags are rejected")


func test_corner_pillars_meet_the_pavement_across_their_complete_top() -> void:
	var missing := 0
	for code: int in range(101,105):
		var city := flat_city()
		var anchor := Vector2i(30,30)
		stamp(city,anchor,code,LAYOUTS[2])
		var layer := CityNetworks3D.new()
		layer._build_region(city,Rect2i(anchor,Vector2i(2,2)))
		check_eq(layer._physical_boxes.size(),4,"each curve retains four support pillars")
		for box: Dictionary in layer._physical_boxes:
			var transform: Transform3D = box.transform
			var size: Vector3 = box.size
			for x: float in [-.5,.5]:
				for z: float in [-.5,.5]:
					var top := transform*Vector3(x*size.x,size.y*.5,z*size.z)
					var hit := Smoothness.pavement_hit(layer,Vector2(top.x,top.z))
					if hit.is_empty():missing+=1;continue
					check_ge(top.y,hit.height-.095,"pier top overlaps the deck underside")
		layer.free()
	check_eq(missing,0,"no pillar projects beyond the curved pavement and stands disconnected")


func test_oro_canyon_all_twenty_blocks_have_connected_pavement() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Oro Canyon.sc2")
	check(loaded.ok,"supplied Oro Canyon imports")
	if not loaded.ok:return
	var city: City = loaded.city
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var gaps := 0
	for block: Array in ORO_BLOCKS:
		var anchor := Vector2i(block[0],block[1])
		var code: int = block[2]
		for dy: int in 2:
			for dx: int in 2:
				var cell := anchor+Vector2i(dx,dy)
				check_eq(city.building.atv(cell),code,"independently inventoried Oro Canyon block")
				check_eq(CityNetworks3D.highway_footprint(city,cell,code),anchor,"Oro Canyon quadrant belongs to its complete block")
		var layer := CityNetworks3D.new()
		layer._prepare_bridge_decks(city)
		layer._build_region(city,Rect2i(anchor,Vector2i(2,2)))
		for radius: float in [.28,.72,1.28,1.72]:
			for step: int in 65:
				var point := lane_point(anchor,code,radius,step/64.0) if code<105 else Vector2(anchor)+Vector2(radius,step/32.0)
				if Smoothness.pavement_hit(layer,point).is_empty():gaps += 1
		layer.free()
	check_eq(gaps,0,"actual city corners and junctions retain their complete lane floors")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"projection preserves complete native city payload")
	print("ORO_PAVEMENT blocks=20 samples=5200 missing=",gaps)


func test_saved_oro_flags_resolve_after_native_roundtrip_and_each_view_rotation() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Oro Canyon.sc2").city
	var path := "user://oro-corner-roundtrip.sc2d"
	check_eq(SaveFormat.save(path,city,{}),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok,"native Oro Canyon reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not loaded.ok:return
	var restored: City = loaded.city
	check_eq(SaveFormat.encode_city(restored),SaveFormat.encode_city(city),"retained layout survives native file without rewriting flags")
	for rotation: int in 4:
		restored.rotation = rotation
		for block: Array in ORO_BLOCKS:
			var anchor := Vector2i(block[0],block[1])
			for dy: int in 2:
				for dx: int in 2:
					check_eq(CityNetworks3D.highway_footprint(restored,anchor+Vector2i(dx,dy),block[2]),anchor,
						"view choice cannot reinterpret retained footprint flags")


func test_oro_traffic_uses_all_four_curved_lanes_and_matching_pavement() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Oro Canyon.sc2").city
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var count := 0
	var gaps := 0
	var maximum_error := .0
	for block: Array in ORO_BLOCKS:
		if block[2]==105:continue
		var anchor := Vector2i(block[0],block[1])
		var layer := CityNetworks3D.new()
		layer._prepare_bridge_decks(city)
		layer._build_region(city,Rect2i(anchor,Vector2i(2,2)))
		var block_segments := 0
		for dy: int in 2:
			for dx: int in 2:
				var cell := anchor+Vector2i(dx,dy)
				for segment: Dictionary in graph.highways.routes.get(cell,[]):
					if not segment.has("radius"):continue
					block_segments += 1
					check(graph.neighbors(cell,&"highway").has(segment.previous),"lane entrance stays connected")
					check(graph.traffic_choices(cell,&"highway",segment.previous,segment.lane).has(segment.next),"directed exit retains its lane")
					for step: int in 17:
						var angle: float = lerpf(segment.start,segment.end,step/16.0)
						var point := lane_point(anchor,block[2],segment.radius,angle/(PI*.5))
						var hit := Smoothness.pavement_hit(layer,point)
						if hit.is_empty():gaps+=1;continue
						var traffic := graph.point(cell,&"highway",point-Vector2(cell))
						maximum_error = maxf(maximum_error,absf(traffic.y-hit.height))
		check_eq(block_segments,8,"two inner and six outer segments serve four lanes in each actual curve")
		count += block_segments
		layer.free()
	check_eq(count,144,"all eighteen actual corners retain their directed arcs")
	check_eq(gaps,0,"ambient lane arcs stay on the rendered pavement")
	check_lt(maximum_error,.0015,"ambient highway height matches actual pavement between vertices")
	print("ORO_TRAFFIC segments=",count," missing=",gaps," height_error=",maximum_error)
