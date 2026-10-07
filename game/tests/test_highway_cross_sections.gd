# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Highway deck shape must not inherit independent terrain humps across lanes.
extends "res://tests/test_case.gd"

func test_valle_straight_highways_have_one_stable_cross_section() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Valle del Mar.sc2")
	check(loaded.ok,"included Valle del Mar city imports")
	if not loaded.ok: return
	var city: City = loaded.city
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new(); graph.bind_city(city)
	var maximum := .0
	var count := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			var code := city.building.atv(cell)
			if not NetworkShapes.is_highway(code): continue
			var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.HIGHWAY)
			if mask not in [5,10]: continue
			count += 1
			for along: float in [.0,.25,.5,.75,1.0]:
				var low := INF; var high := -INF
				for across: float in [.04,.28,.5,.72,.96]:
					var p := graph.point(cell,&"highway",Vector2(along,across) if mask==10 else Vector2(across,along))
					low=minf(low,p.y); high=maxf(high,p.y)
				maximum=maxf(maximum,high-low)
	print("VALLE_CROSS_SECTION cells=%d maximum_twist=%.9f"%[count,maximum])
	check_gt(count,300,"covers actual straightaways, crossings and bank approaches")
	check_lt(maximum,.00001,"straight deck has one grade across its entire width")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"surface correction preserves city bytes")

func test_sideways_hills_do_not_twist_either_highway_axis() -> void:
	for ew: bool in [false,true]:
		var city := flat_city()
		var surface := TerrainSurface.new(4)
		for y: int in TerrainSurface.VERTS_Y:
			for x: int in TerrainSurface.VERTS_X:
				var along := x if ew else y
				var across := y if ew else x
				surface.set_vertex(x,y,4+clampi(along-23,0,2)+(1 if across>=23 and along>=21 and along<29 else 0))
		surface.project(city); city.terrain_surface=surface
		for across: int in 2:
			for along: int in range(19,32):
				city.building.putv(Vector2i(along,22+across) if ew else Vector2i(22+across,along),74 if ew else 73)
		var graph := CityTrafficGraph.new(); graph.bind_city(city)
		var maximum := .0; var clearance := INF
		for step: int in 193:
			var along := 19.02+step/16.0
			var low := INF; var high := -INF
			for across: float in [22.04,22.28,22.72,23.28,23.72,23.96]:
				var p := Vector2(along,across) if ew else Vector2(across,along)
				var cell := Vector2i(floori(p.x),floori(p.y))
				var h := graph.point(cell,&"highway",p-Vector2(cell)).y
				low=minf(low,h);high=maxf(high,h)
				clearance=minf(clearance,h-CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell)).y)
			maximum=maxf(maximum,high-low)
		check_lt(maximum,.00001,"paired highway stays level across sideways hills")
		check_ge(clearance,.12,"stable slab remains clear of actual hillside")

func test_valle_connected_highway_mouths_share_their_full_grade() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city
	var graph := CityTrafficGraph.new();graph.bind_city(city)
	var maximum := .0;var count := 0
	for cell: Vector2i in graph.cells(&"highway"):
		if NetworkShapes.is_onramp(city.building.atv(cell)):continue
		for direction: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
			var other := cell+direction
			if not graph.neighbors(cell,&"highway").has(other) or NetworkShapes.is_onramp(city.building.atv(other)):continue
			for across: float in [.12,.28,.5,.72,.88]:
				var edge := Vector2(1,across) if direction.x else Vector2(across,1)
				maximum=maxf(maximum,absf(graph.point(cell,&"highway",edge).y-graph.point(other,&"highway",edge-Vector2(direction)).y))
				count+=1
	print("VALLE_HIGHWAY_MOUTHS samples=%d maximum_step=%.9f"%[count,maximum])
	check_gt(count,1500,"checks full city highway joins")
	check_lt(maximum,.00001,"all adjoining corners, grades and spans meet without steps")

func test_valle_short_grades_stay_within_the_actual_bank_height_envelope() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city
	var graph := CityTrafficGraph.new();graph.bind_city(city)
	var envelopes := {}
	for cell: Vector2i in graph._approaches:
		var p: Dictionary = graph._approaches[cell]
		if not p.has("grade_near"):continue
		var direction := Vector2i.RIGHT if p.ew else Vector2i.DOWN
		var key := cell-direction*int(p.index)
		# Valle's saved paired corridors have even transverse anchors. Their
		# shared level surface must clear the highest terrain of BOTH lanes.
		if p.ew: key.y=(key.y/2)*2
		else: key.x=(key.x/2)*2
		var envelope := maxf(p.grade_near.x,p.grade_far.x)
		for corner: Vector3 in CityGeometry3D.ground_corners(city,cell):envelope=maxf(envelope,corner.y+CityNetworks3D.HIGHWAY_ELEVATION)
		envelopes[key]=maxf(envelopes.get(key,-INF),envelope)
	var maximum_excess := .0
	for cell: Vector2i in graph._approaches:
		var p: Dictionary = graph._approaches[cell]
		if not p.has("grade_near"):continue
		var key := cell-(Vector2i.RIGHT if p.ew else Vector2i.DOWN)*int(p.index)
		if p.ew: key.y=(key.y/2)*2
		else: key.x=(key.x/2)*2
		for step: int in 65:
			var offset := Vector2(step/64.0,.5) if p.ew else Vector2(.5,step/64.0)
			maximum_excess=maxf(maximum_excess,graph.point(cell,&"highway",offset).y-envelopes[key])
	print("VALLE_GRADE_ENVELOPE maximum_excess=%.9f"%maximum_excess)
	check_lt(maximum_excess,.001,"short grades cannot turn imported neighboring lots into towering pavement humps")

func test_missing_carriageway_tile_keeps_surviving_corner_approach_and_native_replay() -> void:
	const Corners := preload("res://tests/test_highway_corner_layouts.gd")
	for ew: bool in [false,true]:
		var city := flat_city()
		var anchor := Vector2i(18,22) if ew else Vector2i(22,18)
		Corners.stamp(city,anchor,101 if ew else 103,Corners.LAYOUTS[0])
		for along: int in range(20,33):
			for lane: int in 2:city.building.putv(Vector2i(along,22+lane) if ew else Vector2i(22+lane,along),74 if ew else 73)
		var hole := Vector2i(25,22) if ew else Vector2i(22,25)
		city.building.putv(hole,0)
		var before := var_to_bytes(SaveFormat.encode_city(city))
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		check(not graph.has_cell(hole,&"highway"),"damage does not acquire an invisible highway")
		var first := Vector2i(20,23) if ew else Vector2i(23,20)
		var offset := Vector2(0,.5) if ew else Vector2(.5,0)
		var corner := first-(Vector2i.RIGHT if ew else Vector2i.DOWN)
		check_lt(absf(graph.point(first,&"highway",offset).y-graph.point(corner,&"highway",offset+(Vector2.RIGHT if ew else Vector2.DOWN)).y),.00001,"surviving lane keeps its corner mouth")
		var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
		check(restored.city!=null,"damaged highway reloads")
		var replay := CityTrafficGraph.new();replay.bind_city(restored.city)
		check_eq(graph._approaches,replay._approaches,"native replay retains stable grades and the damage hole")
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"projection preserves damaged city bytes")

func test_one_level_bumps_do_not_create_giant_highway_hump() -> void:
	for ew: bool in [false,true]:
		var city := flat_city()
		var surface := TerrainSurface.new(4)
		for y: int in TerrainSurface.VERTS_Y:
			for x: int in TerrainSurface.VERTS_X:
				var along := x if ew else y
				surface.set_vertex(x,y,5 if along>=21 and along<=31 and along%2 else 4)
		surface.project(city);city.terrain_surface=surface
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		var first := Vector2i(20,22) if ew else Vector2i(22,20)
		for step: int in 12:
			for lane: int in 2:city.building.putv(first+d*step+transverse*lane,74 if ew else 73)
		for side: int in 2:
			var anchor := first-d*2 if side==0 else first+d*12
			var code := (101 if side==0 else 104) if ew else (103 if side==0 else 101)
			for dy: int in 2:
				for dx: int in 2:city.building.putv(anchor+Vector2i(dx,dy),code)
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		var maximum := -INF;var clearance := INF
		for step: int in 12*1024+1:
			var along := step/1024.0
			var index := mini(floori(along),11)
			var cell := first+d*index
			var offset := Vector2(along-index,.5) if ew else Vector2(.5,along-index)
			var h := graph.point(cell,&"highway",offset).y
			maximum=maxf(maximum,h)
			clearance=minf(clearance,h-CityGeometry3D.point_on_ground(city,cell,offset).y)
		var envelope := 5*CityGeometry3D.HEIGHT+.38
		print("SHORT_NATIVE_HUMP ew=",ew," maximum=",maximum," envelope=",envelope," excess=",maximum-envelope," clearance=",clearance)
		check_lt(maximum-envelope,.001,"one-level native bumps must not create a towering roadway dome")
		check_ge(clearance,.119,"grade stays clear of actual road terrain")

func test_resolved_endpoint_slope_keeps_hermite_inside_ceiling() -> void:
	for ew: bool in [false,true]:
		var city := flat_city()
		var surface := TerrainSurface.new(5)
		for y: int in TerrainSurface.VERTS_Y:
			for x: int in TerrainSurface.VERTS_X:surface.set_vertex(x,y,5 if (x if ew else y)<=26 else 4)
		surface.project(city);city.terrain_surface=surface
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		var first := Vector2i(20,22) if ew else Vector2i(22,20)
		for step: int in 13:
			for lane: int in 2:city.building.putv(first+d*step+transverse*lane,74 if ew else 73)
		var anchor := first-d*2
		for dy: int in 2:
			for dx: int in 2:city.building.putv(anchor+Vector2i(dx,dy),101 if ew else 103)
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		var maximum := -INF;var clearance := INF
		for step: int in 6*1024+1:
			var along := step/1024.0
			var index := mini(floori(along),5)
			var cell := first+d*index
			var offset := Vector2(along-index,.5) if ew else Vector2(.5,along-index)
			var h := graph.point(cell,&"highway",offset).y
			maximum=maxf(maximum,h)
			clearance=minf(clearance,h-CityGeometry3D.point_on_ground(city,cell,offset).y)
		var ceiling := 5*CityGeometry3D.HEIGHT+.38
		print("HERMITE_CEILING ew=",ew," maximum=",maximum," ceiling=",ceiling," excess=",maximum-ceiling," clearance=",clearance," profile=",graph._approaches.get(first,{}))
		check_lt(maximum-ceiling,.001,"flat bank approach stays below its real terrain/endpoints ceiling")
		check_ge(clearance,.119,"grade clears owned ground")
