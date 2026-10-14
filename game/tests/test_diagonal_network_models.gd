# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const Smoothness := preload("res://tests/test_highway_smoothness.gd")
const Corners := preload("res://tests/test_highway_corner_layouts.gd")
const MASKS := [3,6,12,9]
const STARTS := [Vector2(.5,0),Vector2(1,.5),Vector2(.5,1),Vector2(0,.5)]
const ENDS := [Vector2(1,.5),Vector2(.5,1),Vector2(0,.5),Vector2(.5,0)]

func test_road_and_rail_diagonal_surfaces_and_details_stay_in_straight_bands() -> void:
	for family: int in [NetworkShapes.Family.ROAD,NetworkShapes.Family.RAIL]:
		for quarter: int in 4:
			var city := flat_city();var cell := Vector2i(20,20)
			city.building.putv(cell,NetworkShapes.shape_id(family,MASKS[quarter]))
			var before := var_to_bytes(SaveFormat.encode_city(city))
			var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(cell,Vector2i.ONE))
			var normal := Vector2(-(ENDS[quarter]-STARTS[quarter]).y,(ENDS[quarter]-STARTS[quarter]).x).normalized()
			var outside := 0;var samples := 0
			for i: int in layer._faces.size():
				var color: Color = layer._colors[i]
				if not color.is_equal_approx(Color(.34,.38,.40) if family==NetworkShapes.Family.ROAD else Color(.51,.50,.45)):continue
				var p := Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(cell)
				var distance := absf((p-STARTS[quarter]).dot(normal))
				if distance>(.30 if family==NetworkShapes.Family.ROAD else .295)/sqrt(2.0)+.00001:outside+=1
				samples+=1
			check_gt(samples,0,"actual diagonal model emitted")
			check_eq(outside,0,"all roadbed vertices lie between parallel diagonal edges")
			if family==NetworkShapes.Family.RAIL:
				var escaped := 0
				for i: int in layer._faces.size():
					if not layer._colors[i].is_equal_approx(Color(.40,.33,.26)):continue
					var p := Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(cell)
					if p.x<-.00001 or p.y<-.00001 or p.x>1.00001 or p.y>1.00001:escaped+=1
				check_eq(escaped,0,"diagonal sleepers stay inside their authored tile")
			var bent_details := 0
			for i: int in layer._faces.size():
				var detail_color: Color = layer._colors[i]
				if not detail_color.is_equal_approx(Color(.86,.72,.36) if family==NetworkShapes.Family.ROAD else Color(.72,.75,.71)):continue
				var p := Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(cell)
				var distance := absf((p-STARTS[quarter]).dot(normal))
				if family==NetworkShapes.Family.ROAD:
					if distance>.011/sqrt(2.0)+.00001:bent_details+=1
				elif absf(distance-.156/sqrt(2.0))>.013/sqrt(2.0)+.00001:bent_details+=1
			check_eq(bent_details,0,"markings and steel rails follow straight diagonal bands")
			if family==NetworkShapes.Family.ROAD:
				for t: float in [.05,.25,.5,.75,.95]:
					check(not Smoothness.pavement_hit(layer,Vector2(cell)+STARTS[quarter].lerp(ENDS[quarter],t)).is_empty(),"straight centerline has pavement")
			check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"model does not rewrite the city")
			layer.free()

func test_highway_carriageways_have_parallel_diagonal_edges() -> void:
	for quarter: int in 4:
		var city := flat_city();var anchor := Vector2i(30,30)
		Corners.stamp(city,anchor,101+quarter,Corners.LAYOUTS[1])
		var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(anchor,Vector2i(2,2)))
		var outside := 0
		for i: int in layer._faces.size():
			if not layer._colors[i].is_equal_approx(Smoothness.PAVEMENT):continue
			var p := Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(anchor)-Vector2.ONE
			match quarter:
				1:p=Vector2(p.y,-p.x)
				2:p=-p
				3:p=Vector2(-p.y,p.x)
			p+=Vector2.ONE
			var across := 2-p.x+p.y
			if minf(absf(across-.5),absf(across-1.5))>.46001:outside+=1
		check_eq(outside,0,"both carriageways are straight parallel diagonal strips")
		layer.free()

func test_road_and_train_poses_follow_straight_diagonal_centerlines() -> void:
	for family: int in [NetworkShapes.Family.ROAD,NetworkShapes.Family.RAIL]:
		var city := flat_city();var cell := Vector2i(20,20)
		city.building.putv(cell,NetworkShapes.shape_id(family,3))
		var traffic := CityTraffic3D.new();traffic.bind_city(city)
		var domain: StringName = &"road" if family==NetworkShapes.Family.ROAD else &"rail"
		var actor := {"type":domain,"domain":domain,"cell":cell,"previous":cell+Vector2i.UP,"next":cell+Vector2i.RIGHT,"side":1.0,"t":0.0}
		var start := traffic.actor_pose(actor).origin
		actor.t=1.0;var end := traffic.actor_pose(actor).origin
		for t: float in [.125,.25,.5,.75,.875]:
			actor.t=t
			check(traffic.actor_pose(actor).origin.distance_to(start.lerp(end,t))<.00001,"vehicle stays on its straight diagonal lane")
		traffic.free()

func test_partial_highway_diagonals_keep_their_supports_under_pavement() -> void:
	for quarter: int in 4:
		var city := flat_city();var cell := Vector2i(20,20)
		city.building.putv(cell,101+quarter)
		var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(cell,Vector2i.ONE))
		check_eq(layer._physical_boxes.size(),1,"partial diagonal retains a support")
		for box: Dictionary in layer._physical_boxes:
			var transform: Transform3D = box.transform;var size: Vector3 = box.size
			for x: float in [-.5,.5]:
				for z: float in [-.5,.5]:
					var top := transform*Vector3(x*size.x,size.y*.5,z*size.z)
					check(not Smoothness.pavement_hit(layer,Vector2(top.x,top.z)).is_empty(),"all support top corners meet the diagonal deck")
		layer.free()

func test_degree_one_diagonal_terminals_reverse_within_their_road_or_track() -> void:
	for family: int in [NetworkShapes.Family.ROAD,NetworkShapes.Family.RAIL,NetworkShapes.Family.HIGHWAY]:
		for quarter: int in 4:
			var city := flat_city();var cell := Vector2i(20,20)
			var previous: Vector2i = cell+[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT][quarter]
			city.building.putv(cell,NetworkShapes.shape_id(family,MASKS[quarter]))
			city.building.putv(previous,NetworkShapes.shape_id(family,5 if quarter%2==0 else 10))
			var traffic := CityTraffic3D.new();traffic.bind_city(city)
			var domain: StringName = &"highway" if family==NetworkShapes.Family.HIGHWAY else &"road" if family==NetworkShapes.Family.ROAD else &"rail"
			check_eq(traffic.graph.degree(cell,domain),1,"actual diagonal terminal has one reciprocal neighbor")
			check(traffic.graph.traffic_choices(cell,domain,previous,0).has(previous),"normal routing backs out of this terminal")
			var normal := Vector2(-(ENDS[quarter]-STARTS[quarter]).y,(ENDS[quarter]-STARTS[quarter]).x).normalized()
			var actor := {"type":domain,"domain":domain,"cell":cell,"previous":previous,"next":previous,"side":1.0,"t":0.0}
			for step: int in 33:
				actor.t=step/32.0
				var pose := traffic.actor_pose(actor)
				var p := Vector2(pose.origin.x,pose.origin.z)-Vector2(cell)
				check(absf((p-STARTS[quarter]).dot(normal))<=(.46 if family==NetworkShapes.Family.HIGHWAY else .30 if family==NetworkShapes.Family.ROAD else .295)/sqrt(2.0)+.00001,"terminal excursion stays over its diagonal floor")
			traffic.free()

func test_incomplete_highway_traffic_follows_its_diagonal() -> void:
	var city := flat_city();var cell := Vector2i(20,20)
	city.building.putv(cell,101)
	city.building.putv(cell+Vector2i.UP,73)
	city.building.putv(cell+Vector2i.RIGHT,74)
	var traffic := CityTraffic3D.new();traffic.bind_city(city)
	check(not traffic.graph.highways.routes.has(cell),"incomplete footprint uses fallback traffic")
	check_eq(traffic.graph.degree(cell,&"highway"),2,"both diagonal edge neighbors connect")
	var actor := {"type":&"highway","domain":&"highway","cell":cell,"previous":cell+Vector2i.UP,"next":cell+Vector2i.RIGHT,"lane":0,"side":1.0,"t":0.0}
	var start := traffic.actor_pose(actor).origin
	actor.t=1.0;var end := traffic.actor_pose(actor).origin
	for t: float in [.125,.25,.5,.75,.875]:
		actor.t=t
		check(traffic.actor_pose(actor).origin.distance_to(start.lerp(end,t))<.00001,"fallback highway vehicle follows a straight diagonal")
	traffic.free()
