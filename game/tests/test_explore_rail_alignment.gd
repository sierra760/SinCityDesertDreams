# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Grades := preload("res://tests/test_explore_transit_grade_carry.gd")
var host: Node3D

static func bend_city() -> City:
	var city:=flat_city()
	for x:int in range(18,26):city.building.put(x,24,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	city.building.put(26,24,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,9))
	for z:int in range(17,24):city.building.put(26,z,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	return city

func after_each() -> void:
	if is_instance_valid(host):host.free()
	await physics_frame

func setup_actor(city:City, kind:StringName, start:Vector2i, forward:Vector3) -> ExploreRouteVehicle:
	host=Node3D.new();root.add_child(host)
	var traffic:=CityTraffic3D.new();host.add_child(traffic);traffic.bind_city(city)
	var route:=traffic.get_drive_route(kind,traffic.graph.point(start,&"rail"),forward)
	var actor:=ExploreRouteVehicle.new();host.add_child(actor)
	check(actor.configure(kind,traffic.graph,route),"drive route configures")
	return actor

func test_surface_drive_route_follows_drawn_diagonal_instead_of_tile_center() -> void:
	var city:=bend_city()
	var actor:=setup_actor(city,&"train",Vector2i(20,24),Vector3.RIGHT)
	var worst:=0.0
	for point:Vector3 in actor._points:
		var cell:=Vector2i(floori(point.x),floori(point.z))
		if cell!=Vector2i(26,24):continue
		var local:=Vector2(point.x-cell.x,point.z-cell.y)
		# Actual mask-9 rail joins the west edge to the north edge.
		worst=maxf(worst,absf(local.x+local.y-.5)/sqrt(2.0))
	check(worst<.00002,"drive route leaves the rendered diagonal by "+str(worst)+" tiles")

func test_surface_drive_route_preserves_actual_grade_breaks() -> void:
	var city:=Grades.grade_city()
	var actor:=setup_actor(city,&"train",Vector2i(20,20),Vector3.RIGHT)
	var worst:=0.0
	for index:int in range(1,actor._points.size()):
		for i:int in 11:
			var at:=actor._points[index-1].lerp(actor._points[index],float(i)/10)
			var cell:=Vector2i(floori(at.x),floori(at.z))
			var expected:Vector3=actor.graph.point(cell,&"rail",Vector2(at.x-cell.x,at.z-cell.y))
			worst=maxf(worst,absf(expected.y-at.y))
	check(worst<.00002,"drive path cuts across the rendered grade by "+str(worst)+" tiles")

static func subway_bend_city() -> City:
	var city:=flat_city()
	for x:int in range(18,26):city.underground.put(x,24,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,10,0))
	city.underground.put(26,24,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,9,0))
	for z:int in range(17,24):city.underground.put(26,z,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,5,0))
	for at:Vector2i in [Vector2i(20,24),Vector2i(26,19)]:
		city.building.putv(at,Buildings.SUBWAY_STATION);city.underground.putv(at,Underground.STATION_LINK)
	return city

func test_drive_subway_accepts_the_prepared_curved_route() -> void:
	var city:=subway_bend_city()
	host=Node3D.new();root.add_child(host)
	var graph:=CityTrafficGraph.new();graph.bind_city(city)
	var network:=ExploreTransitNetwork.new();network.rebuild(city,graph,1)
	var route:=network.route(0,1)
	check(not route.is_empty(),"bent subway route exists")
	route.transit=true
	var actor:=ExploreRouteVehicle.new();host.add_child(actor)
	check(actor.configure(&"subway",network,route),"drawn curved subway is a valid driving route")

func test_driven_wheels_stay_at_the_steel_height_across_grades() -> void:
	var city:=Grades.grade_city()
	var renderer:=CityNetworks3D.new();renderer.rebuild(city)
	var steel:=_steel_faces(renderer)
	check(not steel.is_empty(),"rendered grade steel is checked")
	for reverse:bool in [false,true]:
		for kind:StringName in [&"train",&"subway"]:
			var actor:=setup_actor(city,kind,Vector2i(29,20) if reverse else Vector2i(20,20),Vector3.LEFT if reverse else Vector3.RIGHT)
			var worst_below:=0.0;var worst_above:=0.0;var misses:=0;var worst_body:=0.0
			for i:int in 161:
				actor._distance=3.5+3.0*float(i)/160
				actor.step(ExploreInputFrame.idle(),0,1.0/60)
				for entry:Dictionary in actor._visual._wheel_metadata:
					var wheel:=actor._visual.find_child(entry.node,true,false) as Node3D
					var contact:=wheel.global_position-wheel.global_basis.orthonormalized().y*(float(entry.radius_m)/16.0)
					var height:=_steel_height(steel,contact)
					if not is_finite(height):misses+=1;continue
					var difference:=contact.y-height
					worst_below=maxf(worst_below,-difference);worst_above=maxf(worst_above,difference)
				for point:Vector3 in actor._rail_path.points:
					var local:=actor.to_local(point+Vector3.UP*.014)
					if absf(local.z)<=actor._size.z*.5:worst_body=maxf(worst_body,local.y)
			check_eq(misses,0,"every wheel lies on the rendered grade steel")
			check(worst_body<=.0181,"rigid underframe clears steel at crest and valley")
			check(worst_below<.004,"%s wheels penetrate the rail by %f tiles"%[kind,worst_below])
			check(worst_above<.004,"%s wheels hover over the rail by %f tiles"%[kind,worst_above])
			host.free()

	renderer.free()

func _steel_faces(renderer: CityNetworks3D) -> PackedVector3Array:
	var faces:=PackedVector3Array()
	for node: Node in renderer.find_children("*","MeshInstance3D",true,false):
		var mesh:Mesh=node.mesh
		for surface:int in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_COLOR]==null:continue
			var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			for i:int in range(0,vertices.size(),3):
				var color:=colors[i]
				if absf(color.r-.72)<.005 and absf(color.g-.75)<.005 and absf(color.b-.71)<.005:
					faces.append_array(vertices.slice(i,i+3))
	return faces

func _steel_height(faces:PackedVector3Array, contact:Vector3) -> float:
	for i:int in range(0,faces.size(),3):
		var a:=Vector2(faces[i].x,faces[i].z)
		var b:=Vector2(faces[i+1].x,faces[i+1].z)-a
		var c:=Vector2(faces[i+2].x,faces[i+2].z)-a
		var at:=Vector2(contact.x,contact.z)-a
		var area:=b.cross(c)
		if absf(area)<.000000001:continue
		var v:=at.cross(c)/area;var w:=b.cross(at)/area
		if v>=-.0002 and w>=-.0002 and v+w<=1.0002:
			return faces[i].y+v*(faces[i+1].y-faces[i].y)+w*(faces[i+2].y-faces[i].y)
	return INF

func _on_steel(faces:PackedVector3Array, contact:Vector3) -> bool:
	var height:=_steel_height(faces,contact)
	return is_finite(height) and absf(contact.y-height)<.004

static func rotated_cell(at:Vector2i, turns:int) -> Vector2i:
	var delta:=at-Vector2i(26,24)
	for i:int in turns:delta=Vector2i(-delta.y,delta.x)
	return Vector2i(26,24)+delta

func test_wheels_follow_actual_rendered_steel_through_all_surface_turns() -> void:
	for turns:int in 4:
		var city:=flat_city();var source:=bend_city()
		for z:int in range(17,25):
			for x:int in range(18,27):
				var code:=source.building.at(x,z)
				if code==0:continue
				var mask:=CityNetworks3D.network_mask(code,NetworkShapes.Family.RAIL)
				mask=((mask<<turns)|(mask>>(4-turns)))&15
				city.building.putv(rotated_cell(Vector2i(x,z),turns),NetworkShapes.shape_id(NetworkShapes.Family.RAIL,mask))
		var renderer:=CityNetworks3D.new();renderer.rebuild(city)
		var steel:=_steel_faces(renderer)
		check(not steel.is_empty(),"actual steel mesh is checked")
		for kind:StringName in [&"train",&"subway"]:
			for reverse:bool in [false,true]:
				var start:=rotated_cell(Vector2i(26,19) if reverse else Vector2i(20,24),turns)
				var forward:Vector3=Vector3.BACK if reverse else Vector3.RIGHT
				forward=forward.rotated(Vector3.UP,-float(turns)*PI*.5)
				var actor:=setup_actor(city,kind,start,forward)
				var misses:=0;var worst_body:=0.0
				for i:int in 101:
					actor._distance=actor._length*.2+actor._length*.6*float(i)/100
					actor.step(ExploreInputFrame.idle(),0,1.0/60)
					for entry:Dictionary in actor._visual._wheel_metadata:
						var wheel:=actor._visual.find_child(entry.node,true,false) as Node3D
						var contact:=wheel.global_position-wheel.global_basis.orthonormalized().y*(float(entry.radius_m)/16)
						if not _on_steel(steel,contact):misses+=1
					for point:Vector3 in actor._rail_path.points:
						var local:=actor.to_local(point+Vector3.UP*.014)
						if absf(local.z)<=actor._size.z*.5 and absf(local.x)<=actor._size.x*.5:
							worst_body=maxf(worst_body,local.y)
				check_eq(misses,0,"%s wheels meet rendered steel in turn %d reverse=%s"%[kind,turns,reverse])
				check(worst_body<=.0181,"body clears track through turn")
				host.free()
		renderer.free()

func test_surface_route_rechecks_geometry_after_graph_changes() -> void:
	var city:=Grades.grade_city()
	var actor:=setup_actor(city,&"train",Vector2i(20,20),Vector3.RIGHT)
	city.building.put(5,5,Buildings.SMALL_PARK)
	actor.graph.refresh()
	check(actor.has_support(),"unrelated city growth keeps the rail route")
	city.building.put(25,20,0)
	actor.graph.refresh()
	check(not actor.has_support(),"a removed rail ahead invalidates its cached geometry")

func test_subway_curve_rejects_changed_nodes_and_forged_points() -> void:
	var city:=subway_bend_city()
	host=Node3D.new();root.add_child(host)
	var graph:=CityTrafficGraph.new();graph.bind_city(city)
	var network:=ExploreTransitNetwork.new();network.rebuild(city,graph,1)
	var route:=network.route(0,1);route.transit=true
	var actor:=ExploreRouteVehicle.new();host.add_child(actor)
	check(actor.configure(&"subway",network,route))
	var forged:=route.duplicate(true);forged.points[10]+=Vector3.RIGHT*.04
	check(not actor.configure(&"subway",network,forged),"a forged curve cannot bypass route validation")
	check(actor.configure(&"subway",network,route))
	network.nodes[route.nodes[1]].point.y+=.1;network.serial+=1
	check(not actor.has_support(),"changed subway geometry invalidates the prepared route")

func test_blocked_motion_restores_body_and_wheels_together() -> void:
	var actor:=setup_actor(Grades.grade_city(),&"train",Vector2i(20,20),Vector3.RIGHT)
	actor._distance=4.7;actor.global_transform=actor._rail_pose(actor._distance)
	actor._align_rail_wheels()
	var before:=actor.global_transform
	var wheel_before:Array[Transform3D]=[]
	for entry:Dictionary in actor._rail_wheels:wheel_before.append(entry.node.global_transform)
	var obstacle:=StaticBody3D.new();obstacle.collision_layer=ExploreActorProfile.OBSTACLE
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*.4
	collision.shape=box;obstacle.add_child(collision);host.add_child(obstacle)
	obstacle.global_position=actor.global_transform*Vector3(0,actor._size.y*.5,-(actor._size.z*.5+.21))
	await physics_frame
	actor._speed=.7
	var frame:=ExploreInputFrame.idle();frame.move=Vector2(0,-1)
	actor.step(frame,0,.1)
	check_eq(actor.global_transform,before,"collision rejects attempted body movement")
	for index:int in actor._rail_wheels.size():
		check(actor._rail_wheels[index].node.global_transform.is_equal_approx(wheel_before[index]),"rejected movement also restores wheel placement")

func test_driven_subway_crosses_the_actual_curved_tunnel_in_both_directions() -> void:
	var fixture_script:=preload("res://tests/exploration/traversal_fixture.gd")
	var city:=subway_bend_city()
	host=Node3D.new();root.add_child(host)
	var fixture:Node3D=fixture_script.attach(self,city);fixture.reparent(host)
	var view:=CityView3D.new();host.add_child(view);view.bind_city(city)
	var graph:=CityTrafficGraph.new();graph.bind_city(city)
	var network:=ExploreTransitNetwork.new();network.rebuild(city,graph,1)
	for reverse:bool in [false,true]:
		var route:=network.route(1,0) if reverse else network.route(0,1)
		route.transit=true
		var world:=ExploreTransitWorld3D.new();host.add_child(world)
		world.bind(view,fixture.get_node("traversal"),network);world.build(route)
		var actor:=ExploreRouteVehicle.new();host.add_child(actor)
		check(actor.configure(&"subway",network,route))
		var reports:Array[String]=[]
		actor.recovery_requested.connect(func(reason):reports.append(reason))
		actor._distance=.75;actor.global_transform=actor._rail_pose(.75)
		await physics_frame
		var frame:=ExploreInputFrame.idle();frame.move=Vector2(0,-1)
		for i:int in 180:
			actor.step(frame,0,.1)
			await physics_frame
			if actor._distance>actor._length-.8:break
		check(actor._distance>actor._length-.8,"driven subway passes the physical corner, reverse="+str(reverse))
		check(reports.is_empty(),"curve does not request recovery")
		actor.free();world.clear();world.free()
		await physics_frame

func test_transit_itinerary_uses_surface_steel_when_above_ground() -> void:
	var city:=Grades.grade_city()
	host=Node3D.new();root.add_child(host)
	var renderer:=CityNetworks3D.new();host.add_child(renderer);renderer.rebuild(city)
	var steel:=_steel_faces(renderer)
	var graph:=CityTrafficGraph.new();graph.bind_city(city)
	var network:=ExploreTransitNetwork.new();network.rebuild(city,graph,1)
	var route:=network.route(0,1);route.transit=true
	for kind:StringName in [&"train",&"subway"]:
		var actor:=ExploreRouteVehicle.new();host.add_child(actor)
		check(actor.configure(kind,network,route))
		var misses:=0
		for i:int in 81:
			actor._distance=3.5+float(i)*3/80
			actor.global_transform=actor._rail_pose(actor._distance);actor._align_rail_wheels()
			for entry:Dictionary in actor._rail_wheels:
				var wheel:Node3D=entry.node
				var contact:=wheel.global_position-wheel.global_basis.orthonormalized().y*float(entry.radius)
				if not _on_steel(steel,contact):misses+=1
		check_eq(misses,0,"transit itinerary keeps driven "+String(kind)+" on surface steel")
		actor.free()

func test_cross_slope_contacts_match_the_rendered_steel() -> void:
	var city:=Grades.grade_city()
	var terrain:=TerrainSurface.new(4)
	for z:int in range(21,TerrainSurface.VERTS_Y):
		for x:int in TerrainSurface.VERTS_X:terrain.vertices[TerrainSurface.vertex_index(x,z)]=5
	city.terrain_surface=terrain
	var actor:=setup_actor(city,&"train",Vector2i(20,20),Vector3.RIGHT)
	var renderer:=CityNetworks3D.new();renderer.rebuild(city)
	var steel:=_steel_faces(renderer)
	var misses:=0
	for i:int in 31:
		actor._distance=1+float(i)*5/30
		actor.global_transform=actor._rail_pose(actor._distance);actor._align_rail_wheels()
		for entry:Dictionary in actor._rail_wheels:
			var wheel:Node3D=entry.node
			var contact:=wheel.global_position-wheel.global_basis.orthonormalized().y*float(entry.radius)
			if not _on_steel(steel,contact):misses+=1
	check_eq(misses,0,"banked rail contacts stay on both steel heads")
	check(absf(actor.global_basis.x.y)>.1,"body follows the track bank")
	renderer.free()

func test_subway_converter_contacts_match_the_exposed_ramp_steel() -> void:
	var city:City=preload("res://tests/test_explore_transit_network.gd").mixed_city()
	host=Node3D.new();root.add_child(host)
	var renderer:=CityNetworks3D.new();host.add_child(renderer);renderer.rebuild(city)
	var steel:=_steel_faces(renderer)
	var graph:=CityTrafficGraph.new();graph.bind_city(city)
	var network:=ExploreTransitNetwork.new();network.rebuild(city,graph,1)
	var first:=1 if network.stations[0].subway else 0
	var route:=network.route(first,1-first);route.transit=true
	var actor:=ExploreRouteVehicle.new();host.add_child(actor)
	check(actor.configure(&"subway",network,route))
	var misses:=0;var checked:=0
	for i:int in 61:
		actor._distance=3.4+float(i)*1.2/60
		actor.global_transform=actor._rail_pose(actor._distance);actor._align_rail_wheels()
		for entry:Dictionary in actor._rail_wheels:
			var wheel:Node3D=entry.node
			var contact:=wheel.global_position-wheel.global_basis.orthonormalized().y*float(entry.radius)
			if contact.x<24.01 or contact.x>24.79:continue
			checked+=1
			if not _on_steel(steel,contact):misses+=1
	check(checked>100,"the actual portal ramp is sampled")
	check_eq(misses,0,"converter wheels follow the exposed steel")
