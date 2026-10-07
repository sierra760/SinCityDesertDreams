# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _height(faces: PackedVector3Array, point: Vector2) -> float:
	var found := -INF
	for i: int in range(0,faces.size(),3):
		var a := faces[i]; var b := faces[i+1]; var c := faces[i+2]
		var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
		var area := ab.cross(ac)
		if area<.00000001: continue
		var ap := point-Vector2(a.x,a.z)
		var v := ap.cross(ac)/area; var w := ab.cross(ap)/area
		if v>=-.00001 and w>=-.00001 and v+w<=1.00001:
			found = maxf(found,a.y+(b.y-a.y)*v+(c.y-a.y)*w)
	return found

func test_straight_flat_and_grade_rail_has_solid_terrain_bound_shoulders() -> void:
	var cell := Vector2i(20,20)
	for terrain: int in [0,Terrain.CORNER_NE,Terrain.CORNER_NW,1,2,3,4]:
		var city := flat_city()
		city.terrain.putv(cell,terrain)
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
		var before := SaveFormat.encode_city(city)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var data := layer.physical_data()
		for offset: Vector2 in [Vector2(.15,.5),Vector2(.85,.5)]:
			var ground := CityGeometry3D.point_on_ground(city,cell,offset).y
			var at := Vector2(cell)+offset
			var rendered := _height(layer._faces,at)
			var physical := _height(data.physical_floor_faces,at)
			check(is_finite(rendered) and rendered>ground+.005,"visible rail berm joins terrain on grade "+str(terrain))
			check(is_finite(physical) and absf(physical-rendered)<.0001,"rail berm physical surface follows visible slope")
		var center := CityGeometry3D.point_on_ground(city,cell,Vector2(.5,.5)).y
		check(absf(_height(data.physical_floor_faces,Vector2(cell)+Vector2(.5,.5))-center-.055)<.0001,"running height preserved")
		check_eq(SaveFormat.encode_city(city),before,"berm is presentation only")
		layer.free()

func test_curved_and_branch_rail_foundations_fill_only_track_outline() -> void:
	var city := flat_city(); var cell := Vector2i(20,20)
	for mask: int in [3,6,9,12,7,11,13,14,15]:
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,mask))
		var layer := CityNetworks3D.new(); layer.rebuild(city)
		var physical := layer.physical_data().physical_floor_faces as PackedVector3Array
		var offset := Vector2(.85,.15)
		if mask in [3,6,9,12]:
			var pivot: Vector2 = {3:Vector2(1,0),6:Vector2(1,1),12:Vector2(0,1),9:Vector2(0,0)}[mask]
			var angle: float = {3:PI,6:-PI/2.0,12:0.0,9:PI/2.0}[mask]-PI/4.0
			offset = pivot+Vector2(cos(angle),sin(angle))*.84
		var ground := CityGeometry3D.point_on_ground(city,cell,offset).y
		check(_height(physical,Vector2(cell)+offset)>ground+.005,"curve/branch shoulder has solid support "+str(mask))
		layer.free()

func test_bridge_water_and_portal_cells_keep_open_spans() -> void:
	var cell := Vector2i(20,20)
	for code: int in [90,91,Buildings.SUBWAY_PORTAL_FIRST]:
		var city := flat_city()
		city.building.putv(cell,code)
		var layer := CityNetworks3D.new(); layer.rebuild(city)
		check(not layer._colors.has(Color(.44,.40,.33)),"bridge/portal receives no ground berm "+str(code))
		layer.free()
	var city := flat_city()
	city.terrain.putv(cell,Terrain.SUBMERGED)
	city.set_heights(cell.x,cell.y,2,4)
	city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	var layer := CityNetworks3D.new(); layer.rebuild(city)
	check(not layer._colors.has(Color(.44,.40,.33)),"wet rail receives no solid earth dam")
	layer.free()

func test_connections_and_road_crossing_remain_passable() -> void:
	var city := flat_city(); var cell := Vector2i(20,20)
	for y: int in range(19,22): city.building.put(20,y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	city.building.putv(cell,NetworkShapes.CROSS_ROAD_EW_RAIL_NS)
	var layer := CityNetworks3D.new(); layer.rebuild(city)
	var data := layer.physical_data()
	for z: float in [20.0,21.0]:
		for i: int in range(0,data.physical_obstacle_faces.size(),3):
			var a: Vector3 = data.physical_obstacle_faces[i]
			var b: Vector3 = data.physical_obstacle_faces[i+1]
			var c: Vector3 = data.physical_obstacle_faces[i+2]
			check(not (absf(a.z-z)<.00001 and absf(b.z-z)<.00001 and absf(c.z-z)<.00001),"reciprocal rail connections have no foundation end wall")
	for x: float in [20.05,20.15,20.5,20.85,20.95]:
		var y := _height(data.physical_floor_faces,Vector2(x,20.5))
		var ground := CityGeometry3D.point_on_ground(city,cell,Vector2(x-20,.5)).y
		check(is_finite(y) and y-ground>=.039 and y-ground<=.056,"road crossing retains existing accessible floor elevations")
	layer.free()
