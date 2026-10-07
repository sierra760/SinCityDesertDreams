# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rigid bridges meet smoothly graded dry roads across their full pavement width.
extends "res://tests/test_case.gd"
const Surface := preload("res://tests/test_highway_smoothness.gd")

static func bank_city(ew: bool, length: int, code: int = 87, skew: bool = false) -> City:
	var city := flat_city()
	var vertices := TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in TerrainSurface.VERTS_X:
			var along := x if ew else y
			var across := y if ew else x
			var raised := 1 if along>=22 and along<=22+length else 0
			if skew and across>=23 and along>=21 and along<=23+length: raised += 1
			vertices.set_vertex(x,y,2 if along>22 and along<22+length else 4+raised)
	vertices.project(city)
	city.terrain_surface = vertices
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	for step: int in range(-2,length+2):
		var cell := Vector2i(22,22)+direction*step
		city.building.putv(cell,code if step>=0 and step<length else NetworkShapes.shape_id(NetworkShapes.Family.RAIL if code in [90,91] else NetworkShapes.Family.ROAD,10 if ew else 5))
		city.flags.putv(cell,2 if ew else 0)
		if step>=0 and step<length:
			city.terrain.putv(cell,Terrain.SURFACE)
			city.set_heights(cell.x,cell.y,2,3)
	return city

func _joint_errors(city: City, networks: CityNetworks3D, start: Vector2i) -> Vector2:
	var profile: Dictionary = networks._deck_profiles[start]
	var direction := Vector2i.RIGHT if profile.ew else Vector2i.DOWN
	var errors := Vector2.ZERO
	var previous_group := networks._physical_group
	networks._physical_group = NetworkShapes.Family.RAIL if NetworkShapes.is_rail_bridge(city.building.atv(start)) else NetworkShapes.Family.ROAD
	for side: int in 2:
		var cell := start if side==0 else start+direction*(int(profile.length)-1)
		var bank := cell-direction if side==0 else cell+direction
		if not city.in_bounds(bank.x,bank.y) or city.is_water(bank.x,bank.y): continue
		for across: float in [.20,.275,.35,.50,.65,.725,.80]:
			var edge := Vector2(0 if side==0 else 1,across) if profile.ew else Vector2(across,0 if side==0 else 1)
			var bank_edge := edge+Vector2(direction)*(1 if side==0 else -1)
			var a := networks._point(city,cell,edge,.65).y
			var want := networks._point(city,bank,bank_edge,.04).y
			var inward := Vector2(direction)*(.001 if side==0 else -.001)
			var inner := networks._point(city,bank,bank_edge-inward,.04).y
			var deck_inner := networks._point(city,cell,edge+inward,.65).y
			errors.x = maxf(errors.x,absf(a-want))
			errors.y = maxf(errors.y,absf(atan2(deck_inner-a,.001)-atan2(want-inner,.001)))
	networks._physical_group = previous_group
	return errors

func test_sloping_banks_join_full_road_width_and_grade_in_both_axes() -> void:
	for ew: bool in [false,true]:
		for code: int in [83,86,87,88,90,91,106,107]:
			var city := bank_city(ew,6,code,true)
			var encoded := var_to_bytes(SaveFormat.encode_city(city))
			var networks := CityNetworks3D.new()
			networks._prepare_bridge_decks(city)
			var errors := _joint_errors(city,networks,Vector2i(22,22))
			check_lt(errors.x,.00001,"entire bank joint meets pavement, not only the center: %s/%d"%[ew,code])
			check_lt(rad_to_deg(errors.y),.25,"graded approach enters the rigid deck level: %s/%d"%[ew,code])
			check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"road projection never edits the city")
			networks.free()

func test_short_and_long_bridges_keep_a_level_physical_contact_plane() -> void:
	for ew: bool in [false,true]:
		for length: int in [1,2,6,19]:
			var city := bank_city(ew,length)
			var networks := CityNetworks3D.new()
			networks.rebuild(city)
			var maximum := .0
			var missing := 0
			for across: float in [.275,.5,.725]:
				var previous := Vector3.UP
				for step: int in length*128:
					var along := 22+(step+.31)/128.0
					var p := Vector2(along,22+across) if ew else Vector2(22+across,along)
					var hit := Surface.pavement_hit(networks,p)
					if hit.is_empty():
						missing += 1
						continue
					maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
					previous = hit.normal
				var exit_normal := Vector3.UP
				maximum = maxf(maximum,rad_to_deg(previous.angle_to(exit_normal)))
			print("BANK_CONTACT ew=%s length=%d maximum_normal_change=%.4f"%[ew,length,maximum])
			check_eq(missing,0,"bridge mouth and whole span retain pavement")
			check_lt(maximum,4.0,"bridge physical contact stays level without a pitch jolt")
			networks.free()

## Imported cities with real bridges: the bundled classic cities, or the
## "|"-separated paths in BRIDGE_APPROACH_CITY when it is set.
static func bridge_cities() -> PackedStringArray:
	var external := OS.get_environment("BRIDGE_APPROACH_CITY")
	if not external.is_empty(): return external.split("|",false)
	var paths := PackedStringArray()
	for city_name: String in ["Aliso Niguel","Foothills Ranch","Grant Pass - Soledad","La Presa","Lawndale","Oro Canyon","Salton Shores","Valle del Mar"]:
		paths.append("res://assets/cities/%s.sc2" % city_name)
	return paths

func test_imported_city_road_and_rail_banks_join_across_the_map() -> void:
	var total := 0
	for path: String in bridge_cities():
		var loaded := Sc2Import.load(path)
		check(loaded.ok,"read-only import of "+path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var encoded := var_to_bytes(SaveFormat.encode_city(city))
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		var count := 0
		var maximum := Vector2.ZERO
		for cell: Vector2i in networks._deck_profiles:
			var p: Dictionary = networks._deck_profiles[cell]
			var code := city.building.atv(cell)
			# Highway bridges join highway approaches and are covered by the highway bridge tests.
			if p.index!=0 or not (NetworkShapes.is_road_bridge(code) or NetworkShapes.is_rail_bridge(code)): continue
			count += 1
			var errors := _joint_errors(city,networks,cell)
			maximum.x = maxf(maximum.x,errors.x)
			maximum.y = maxf(maximum.y,errors.y)
			check_lt(errors.x,.00001,"full pavement joint: %s %s"%[path.get_file(),cell])
			check_lt(rad_to_deg(errors.y),.25,"bank tangent: %s %s"%[path.get_file(),cell])
		print("BRIDGE_JOINTS %s spans=%d max_gap=%.8f max_grade_change=%.4f"%[path.get_file(),count,maximum.x,rad_to_deg(maximum.y)])
		total += count
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"checking bridges leaves the city unchanged")
		networks.free()
	check_gt(total,0,"the checked cities contain road or rail bridge spans")

func test_sloping_bank_pylons_reach_the_actual_deck_on_both_sides() -> void:
	for ew: bool in [false,true]:
		var city := bank_city(ew,6,87,true)
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		var cell := Vector2i(22,22)
		networks._bridge_structure(city,cell,87)
		var count := 0
		for child: MeshInstance3D in networks.get_children():
			if not is_equal_approx(child.mesh.size.x,.13): continue
			count += 1
			var top := child.transform*Vector3(0,child.mesh.size.y*.5,0)
			var want := networks._point(city,cell,Vector2(top.x-cell.x,top.z-cell.y),.65).y-.07
			check_lt(absf(top.y-want),.00001,"each bridge pier reaches its rigid deck")
		check_eq(count,2,"both actual load-bearing piers are checked")
		networks.free()

func test_dry_approach_roads_round_the_foot_of_the_bank_above_the_terrain() -> void:
	for ew: bool in [false,true]:
		var city := bank_city(ew,6)
		var networks := CityNetworks3D.new()
		networks.rebuild(city)
		var maximum := .0
		var minimum_lift := INF
		var previous := Vector3.UP
		for step: int in 257:
			var along := 20.001+step*1.998/256.0
			var p := Vector2(along,22.35) if ew else Vector2(22.35,along)
			var hit := Surface.pavement_hit(networks,p)
			check(not hit.is_empty(),"actual approach pavement")
			if hit.is_empty(): continue
			maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
			previous = hit.normal
			var cell := Vector2i(floori(p.x),floori(p.y))
			minimum_lift = minf(minimum_lift,hit.height-CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell)).y)
		print("APPROACH_CONTACT ew=%s maximum_normal_change=%.4f minimum_ground_lift=%.8f"%[ew,maximum,minimum_lift])
		check_lt(maximum,4.0,"the bank's low road entrance must be rounded too")
		check_ge(minimum_lift,.039,"smoothed approach stays above its unmodified terrain")
		networks.free()

func test_approach_and_span_edits_refresh_their_dependent_regions() -> void:
	var city := flat_city()
	var vertices := TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in TerrainSurface.VERTS_X:
			vertices.set_vertex(x,y,2 if x>32 and x<67 else 5 if x>=32 and x<=67 else 4)
	vertices.project(city)
	city.terrain_surface = vertices
	for x: int in range(30,69):
		city.building.put(x,30,87 if x>=32 and x<67 else 30)
		city.flags.put(x,30,2)
		if x>=32 and x<67:
			city.terrain.put(x,30,Terrain.SURFACE)
			city.set_heights(x,30,2,3)
	var networks := CityNetworks3D.new()
	var requested: Array[Rect2i] = [Rect2i(64,16,16,16)]
	networks.update_regions(city,requested)
	var distant: int = networks._regions[Vector2i(96,96)].get_instance_id()
	vertices.set_vertex(67,30,6)
	var changed := networks.update_regions(city,requested)
	check(changed.size()>=3,"far bank grade invalidates the span and approach regions")
	check_eq(networks._regions[Vector2i(96,96)].get_instance_id(),distant,"distant empty region remains retained")
	for region: Rect2i in changed:
		var full := CityNetworks3D.new()
		full._prepare_bridge_decks(city)
		full._build_region(city,region)
		var incremental: CityNetworks3D = networks._regions[region.position]
		check_eq(incremental._faces,full._faces,"regional road surfaces match a fresh projection")
		check_eq(incremental._colors,full._colors,"regional road materials match a fresh projection")
		full.free()
	networks.free()

func test_one_cell_bank_joins_a_flat_corner_without_an_outer_grade_kink() -> void:
	for ew: bool in [false,true]:
		var city := bank_city(ew,6)
		var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
		var corner := Vector2i(22,22)-direction*2
		city.building.putv(corner,35 if ew else 36)
		for step: int in [1,2]:
			city.building.putv(corner+(Vector2i.UP if ew else Vector2i.RIGHT)*step,29 if ew else 30)
		var networks := CityNetworks3D.new()
		networks.rebuild(city)
		var points: Array[Vector2] = []
		for step: int in 129:
			var along := 20.001+step*1.998/128.0
			points.append(Vector2(20.5,along) if ew else Vector2(44.999-along,20.5))
		for step: int in 129:
			var t := step/128.0
			points.append(Vector2(21,22)+Vector2(-.5,0).rotated(-PI*t*.5) if ew else Vector2(23,21)+Vector2(0,-.5).rotated(-PI*t*.5))
		for step: int in 129:
			var along := 21.001+step*.998/128.0
			points.append(Vector2(along,22.5) if ew else Vector2(22.5,along))
		var maximum := .0
		var previous := Vector3.UP
		for p: Vector2 in points:
			var hit := Surface.pavement_hit(networks,p)
			check(not hit.is_empty(),"connected branch/corner/bank pavement")
			if hit.is_empty(): continue
			maximum = maxf(maximum,rad_to_deg(previous.angle_to(hit.normal)))
			previous = hit.normal
		maximum = maxf(maximum,rad_to_deg(previous.angle_to(Vector3.UP)))
		print("CORNER_BANK_CONTACT ew=%s maximum_normal_change=%.4f"%[ew,maximum])
		check_lt(maximum,4.0,"connected land branch and bend ease into the rigid bridge")
		networks.free()
