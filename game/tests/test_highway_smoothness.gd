# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Sample actual emitted pavement between vertices, including both triangles.
extends "res://tests/test_case.gd"

const PAVEMENT := Color(.34,.38,.40)

static func hill_city(ew: bool, imported: bool = false) -> City:
	var city := flat_city()
	var surface := TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in TerrainSurface.VERTS_X:
			surface.set_vertex(x,y,4+clampi((x if ew else y)-22,0,2))
	surface.project(city)
	city.terrain_surface = null if imported else surface
	for lane: int in 2:
		for along: int in range(19,28):
			var cell := Vector2i(along,22+lane) if ew else Vector2i(22+lane,along)
			city.building.putv(cell,NetworkShapes.highway_id(10 if ew else 5,NetworkShapes.AXIS_EW if ew else NetworkShapes.AXIS_NS,city.terrain.atv(cell)))
	return city

static func pavement_hit(layer: Node3D, p: Vector2) -> Dictionary:
	for i: int in range(0,layer._faces.size(),3):
		if not layer._colors[i].is_equal_approx(PAVEMENT): continue
		var a: Vector3 = layer._faces[i]
		var b: Vector3 = layer._faces[i+1]
		var c: Vector3 = layer._faces[i+2]
		var ab := Vector2(b.x-a.x,b.z-a.z)
		var ac := Vector2(c.x-a.x,c.z-a.z)
		var area := ab.cross(ac)
		if absf(area)<.000000001: continue
		var ap := p-Vector2(a.x,a.z)
		var v := ap.cross(ac)/area
		var w := ab.cross(ap)/area
		if v<-.00001 or w<-.00001 or v+w>1.00001: continue
		return {"height":a.y+(b.y-a.y)*v+(c.y-a.y)*w,"normal":(c-a).cross(b-a).normalized()}
	return {}

func test_ramp_contact_normals_change_gradually_between_both_triangle_halves() -> void:
	var pairs := [[Vector2.RIGHT,Vector2.UP],[Vector2.LEFT,Vector2.UP],[Vector2.LEFT,Vector2.DOWN],[Vector2.RIGHT,Vector2.DOWN]]
	for axis: bool in [false,true]:
		for index: int in 4:
			var city := flat_city()
			city.building.put(22,22,93+index)
			city.flags.put(22,22,2 if axis else 0)
			var road: Vector2 = pairs[index][0]
			var high: Vector2 = pairs[index][1]
			if axis:
				road = Vector2(road.y,road.x)
				high = Vector2(high.y,high.x)
			var pivot := Vector2(22.5,22.5)+(road+high)*.5
			var layer := CityNetworks3D.new()
			layer.rebuild(city)
			var maximum := 0.0
			var missing := 0
			for radius: float in [.38,.50,.62]:
				var previous := Vector3.UP
				for step: int in 513:
					var t := (step+.17)/513.0
					var p := pivot+(-high).rotated((-high).angle_to(-road)*t)*radius
					var hit := pavement_hit(layer,p)
					if hit.is_empty():
						missing += 1
						continue
					maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
					previous = hit.normal
				maximum = maxf(maximum,rad_to_deg(previous.angle_to(Vector3.UP)))
			print("RAMP_NORMAL_JUMP index=%d axis=%s maximum_degrees=%.4f" % [index,axis,maximum])
			check_eq(missing,0,"continuous pavement between tessellation vertices")
			check_lt(maximum,4.0,"contact plane changes smoothly instead of alternating across wide triangles")
			layer.free()

func test_hill_base_and_crest_have_continuous_gradual_highway_grades() -> void:
	for ew: bool in [false,true]:
		for imported: bool in [false,true]:
			var city := hill_city(ew,imported)
			var before := SaveFormat.encode_city(city)
			var layer := CityNetworks3D.new()
			layer.rebuild(city)
			var maximum := 0.0
			var missing := 0
			var minimum_clearance := INF
			for across: float in [22.26,22.74,23.26,23.74]:
				var previous := Vector3.UP
				for step: int in 401:
					var along := 20.013+step*.015
					var p := Vector2(along,across) if ew else Vector2(across,along)
					var hit := pavement_hit(layer,p)
					if hit.is_empty():
						missing += 1
						continue
					maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
					previous = hit.normal
					var cell := Vector2i(floori(p.x),floori(p.y))
					minimum_clearance = minf(minimum_clearance,hit.height-CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell)).y)
			print("HILL_NORMAL_JUMP ew=%s imported=%s maximum_degrees=%.4f clearance=%.4f" % [ew,imported,maximum,minimum_clearance])
			check_eq(missing,0,"both carriageways retain continuous floor")
			check_lt(maximum,4.0,"round the foot and crest without tile-boundary pitch jolts")
			check_ge(minimum_clearance,.20,"rounded deck stays above hillside and its solid underside")
			check_eq(SaveFormat.encode_city(city),before,"projection preserves city/save data")
			layer.free()

func test_ambient_highway_height_matches_smoothed_pavement_between_vertices() -> void:
	for ew: bool in [false,true]:
		var city := hill_city(ew)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var graph := CityTrafficGraph.new()
		graph.bind_city(city)
		var maximum := 0.0
		for step: int in 129:
			var along := 21.03+step*.031
			var p := Vector2(along,22.72) if ew else Vector2(22.72,along)
			var hit := pavement_hit(layer,p)
			check(not hit.is_empty(),"ambient lane has rendered pavement")
			if hit.is_empty(): continue
			var cell := Vector2i(floori(p.x),floori(p.y))
			maximum = maxf(maximum,absf(graph.point(cell,&"highway",p-Vector2(cell)).y-hit.height))
		check_lt(maximum,.001,"traffic follows rounded driving deck, including between vertices")
		layer.free()

static func uneven_bridge_city(ew: bool, code: int = 87) -> City:
	var city := flat_city()
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if (x if ew else y)>=27: city.set_heights(x,y,7,0)
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	var start := Vector2i(22,22)
	for step: int in 6:
		var cell := start+direction*step
		city.building.putv(cell,code)
		city.flags.putv(cell,2 if ew else 0)
		city.terrain.putv(cell,Terrain.SURFACE)
		city.set_heights(cell.x,cell.y,2,3)
	for step: int in range(-6,9):
		if step>=0 and step<6: continue
		var cell := start+direction*step
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10 if ew else 5))
	return city

func test_unequal_bridge_banks_keep_a_rigid_level_span() -> void:
	for ew: bool in [false,true]:
		for code: int in [83,87,107]:
			var city := uneven_bridge_city(ew,code)
			var before := SaveFormat.encode_city(city)
			var layer := CityNetworks3D.new()
			layer.rebuild(city)
			var graph := CityTrafficGraph.new()
			graph.bind_city(city)
			var previous := Vector3.UP
			var maximum := 0.0
			var height_error := 0.0
			var missing := 0
			for step: int in 601:
				var along := 22.001+step*.00999
				var p := Vector2(along,22.5) if ew else Vector2(22.5,along)
				var hit := pavement_hit(layer,p)
				if hit.is_empty():
					missing += 1
					continue
				maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
				previous = hit.normal
				check_gt(hit.height,3*CityGeometry3D.HEIGHT+.12,"bridge floor clears water throughout")
				var cell := Vector2i(floori(p.x),floori(p.y))
				height_error = maxf(height_error,absf(graph.point(cell,&"road",p-Vector2(cell)).y-hit.height))
			maximum = maxf(maximum,rad_to_deg(previous.angle_to(Vector3.UP)))
			print("BRIDGE_NORMAL_JUMP ew=%s code=%d maximum_degrees=%.4f" % [ew,code,maximum])
			check_eq(missing,0,"bridge floor has no holes")
			check_lt(maximum,4.0,"bridge floor remains level across the span")
			check_lt(height_error,.001,"bridge traffic and physical/render deck share their level")
			var direction := Vector2.RIGHT if ew else Vector2.DOWN
			var start := Vector2(22.5,22.5)-direction*.5
			check(absf(pavement_hit(layer,start).height-(7*CityGeometry3D.HEIGHT+.04))<.00001,"near graded bank meets the rigid road joint")
			check(absf(pavement_hit(layer,start+direction*6).height-(7*CityGeometry3D.HEIGHT+.04))<.00001,"far bank retains exact road joint")
			check_eq(SaveFormat.encode_city(city),before,"bridge geometry preserves city bytes")
			layer.free()

func test_unusual_bridge_water_readings_keep_decks_within_the_bank_clearance_envelope() -> void:
	for ew: bool in [false,true]:
		var city := uneven_bridge_city(ew)
		for i: int in 6:
			var cell := Vector2i(22+i,22) if ew else Vector2i(22,22+i)
			city.set_heights(cell.x,cell.y,2,5)
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var maximum := -INF
		var minimum := INF
		for i: int in 121:
			var p := Vector2(22+i/20.0,22.5) if ew else Vector2(22.5,22+i/20.0)
			var hit := pavement_hit(layer,p)
			check(not hit.is_empty(),"unusual water reading retains continuous bridge")
			if not hit.is_empty():
				maximum = maxf(maximum,hit.height)
				minimum = minf(minimum,hit.height)
		check(maximum<=7*CityGeometry3D.HEIGHT+.04001,"water must not create an unbounded arch")
		check_ge(minimum,4*CityGeometry3D.HEIGHT+.03999,"bank connections remain fixed")
		layer.free()
