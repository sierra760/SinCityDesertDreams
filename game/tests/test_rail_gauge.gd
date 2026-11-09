# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const STEEL := Color(.72,.75,.71)
const TIMBER := Color(.40,.33,.26)

func test_ambient_train_and_subway_wheels_land_on_the_same_running_rails() -> void:
	for kind: StringName in [&"train",&"subway"]:
		for far: bool in [false,true]:
			var mesh := CityTrafficCatalog.mesh_for(kind,0,far)
			var low := INF
			var high := -INF
			for surface: int in mesh.get_surface_count():
				var material: Material = mesh.surface_get_material(surface)
				if material.resource_name!="traffic_rubber": continue
				var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for point: Vector3 in vertices:
					# The lowest tread vertices exclude the higher axle housings.
					if point.y>.08/16.0: continue
					low = minf(low,absf(point.x))
					high = maxf(high,absf(point.x))
			check(is_finite(low),"actual ambient wheel treads inspected: "+String(kind))
			check(absf((low+high)*.5-1.04/16.0)<.025/16.0,"ambient wheel centre stays over the rail head: "+String(kind)+" far="+str(far))

func test_surface_and_subway_overlay_join_straights_to_diagonals_without_gaps() -> void:
	for subway: bool in [false,true]:
		var city := flat_city()
		for record: Vector3i in [Vector3i(20,19,5),Vector3i(20,20,3),Vector3i(21,20,10)]:
			if subway: city.underground.put(record.x,record.y,Underground.subway_code(record.z))
			else: city.building.put(record.x,record.y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,record.z))
		var layer: CityNetworks3D = CityUnderground3D.RailwayOverlay.new() if subway else CityNetworks3D.new()
		if subway:
			for record: Vector3i in [Vector3i(20,19,5),Vector3i(20,20,3),Vector3i(21,20,10)]:
				layer._draw_network(city,Vector2i(record.x,record.y),NetworkShapes.Family.RAIL,record.z,.04)
		else: layer._build_region(city,Rect2i(19,18,4,4))
		# Offset-line intersections at the 45-degree joins. Sample the steel
		# on each side of both tile borders, including the outer miter pieces.
		var diagonal_offset := sqrt(2.0)*1.04/16.0
		for delta: float in [-.0002,.0002]:
			for point: Vector2 in [Vector2(20.5-.065,20+delta),Vector2(20.5+diagonal_offset+delta,20+delta),
				Vector2(21+delta,20.5+.065),Vector2(21+delta,20.5-diagonal_offset+delta)]:
				check(_steel_hit(layer,point),"steel stays connected through the straight/diagonal join, subway="+str(subway)+" at "+str(point))
		layer.free()

func test_subway_tunnel_straights_and_curves_share_the_carriage_gauge() -> void:
	for curved: bool in [false,true]:
		var world := ExploreTransitWorld3D.new()
		if curved:
			var points := PackedVector3Array()
			for i: int in 25:
				var angle := (PI*.5)*i/24.0
				points.append(Vector3(sin(angle),0,1-cos(angle)))
			world._curved_track(points)
		else: world._track(Transform3D.IDENTITY,1.0)
		var count := 0
		var wrong := 0
		var steel_points := PackedVector3Array()
		var highest := -INF
		for node: Node in world.get_children():
			if not node is MeshInstance3D: continue
			for surface: int in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				for i: int in vertices.size():
					if colors[i].r<.70 or colors[i].g<.73 or colors[i].b<.69: continue
					steel_points.append(vertices[i])
					highest = maxf(highest,vertices[i].y)
		for point: Vector3 in steel_points:
			if point.y<highest-.0031: continue
			count += 1
			var distance := absf(Vector2(point.x,point.z-1).length()-1.0) if curved else absf(point.x)
			if absf(distance-1.04/16.0)>.088/16.0+.00002: wrong += 1
		check(absf(highest+.001)<.00001,"tunnel rail tops meet the same wheel-contact height as surface rail")
		check_gt(count,0,"actual tunnel rail heads were inspected")
		check_eq(wrong,0,"underground rail heads follow the wheel gauge, curved="+str(curved))
		world.free()

func test_surface_rails_and_sleepers_fit_the_train_wheels_on_both_axes_and_diagonals() -> void:
	var starts := {5:Vector2(.5,0),10:Vector2(0,.5),3:Vector2(.5,0),6:Vector2(1,.5),12:Vector2(.5,1),9:Vector2(0,.5)}
	var ends := {5:Vector2(.5,1),10:Vector2(1,.5),3:Vector2(1,.5),6:Vector2(.5,1),12:Vector2(0,.5),9:Vector2(.5,0)}
	for mask: int in starts:
		var city := flat_city()
		var cell := Vector2i(20,20)
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,mask))
		var layer := CityNetworks3D.new()
		layer._build_region(city,Rect2i(cell,Vector2i.ONE))
		var tangent: Vector2 = (ends[mask]-starts[mask]).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var rail_samples := 0
		var wrong_rails := 0
		var wrong_sleepers := 0
		for i: int in layer._faces.size():
			var point := Vector2(layer._faces[i].x,layer._faces[i].z)-Vector2(cell)
			var distance := absf((point-Vector2(starts[mask])).dot(normal))
			if layer._colors[i].is_equal_approx(STEEL):
				rail_samples += 1
				# 2.08 m wheel-centre spacing, with a 17.6 cm rail head.
				if absf(distance-1.04/16.0)>.088/16.0+.00001: wrong_rails += 1
			elif layer._colors[i].is_equal_approx(TIMBER):
				if distance>1.88/16.0+.00001: wrong_sleepers += 1
		check_gt(rail_samples,0,"actual steel was emitted for mask "+str(mask))
		check_eq(wrong_rails,0,"rails meet the wheel treads at the same gauge for mask "+str(mask))
		check_eq(wrong_sleepers,0,"sleepers fit the carriage instead of spanning half the tile for mask "+str(mask))
		layer.free()

func test_passenger_carriage_wheel_treads_match_the_running_rails() -> void:
	var carriage := (load("res://assets/desert-dreams-traffic/transit/passenger_carriage.glb") as PackedScene).instantiate()
	var faces := PackedVector3Array()
	_wheels(carriage,Transform3D.IDENTITY,faces)
	check_gt(faces.size(),0,"authored carriage has wheel-tread geometry")
	var misplaced := 0
	for vertex: Vector3 in faces:
		if absf(absf(vertex.x)-1.04)>.1001: misplaced += 1
	check_eq(misplaced,0,"actual passenger wheel treads sit over the rails at 1.04 m either side of centre")
	carriage.free()

static func _wheels(node: Node, parent: Transform3D, faces: PackedVector3Array) -> void:
	var at: Transform3D = parent*node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material == null or material.resource_name!="traffic_rubber": continue
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: faces.append(at*vertex)
	for child: Node in node.get_children(): _wheels(child,at,faces)

static func _steel_hit(layer: CityNetworks3D, point: Vector2) -> bool:
	for i: int in range(0,layer._faces.size(),3):
		if not layer._colors[i].is_equal_approx(STEEL): continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(point.x,100,point.y),Vector3(point.x,-100,point.y),layer._faces[i],layer._faces[i+1],layer._faces[i+2])
		if hit != null: return true
	return false
