# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Highway bridges use ordinary highway ids over water, not BRIDGE-category ids.
## Removing their wet-span recognition must fail clearance, rigidity and joins.
extends "res://tests/test_case.gd"
const Surface := preload("res://tests/test_city_3d_network_structures.gd")

static func crossing(ew: bool, length: int, skew: bool = false) -> City:
	var city := flat_city()
	var vertices := TerrainSurface.new(4)
	var start := Vector2i(22,22)
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in TerrainSurface.VERTS_X:
			var along := x if ew else y
			var across := y if ew else x
			var h := 1 if along>22 and along<22+length else 4
			if skew and across>=23 and along>=21 and along<=23+length: h += 1
			vertices.set_vertex(x,y,h)
	vertices.project(city)
	city.terrain_surface = vertices
	for lane: int in 2:
		for step: int in range(-8,length+8):
			var cell := start+direction*step+transverse*lane
			city.building.putv(cell,74 if ew else 73)
			# Deliberately opposite flags: highway axis comes from the tile id.
			city.flags.putv(cell,0 if ew else RotationMapper.AXIS_FLAG)
			if step>=0 and step<length:
				city.terrain.putv(cell,Terrain.SURFACE)
				city.set_heights(cell.x,cell.y,1,4)
	return city

func _measure(city: City, start: Vector2i, length: int, ew: bool) -> void:
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var networks := CityNetworks3D.new()
	networks._prepare_bridge_decks(city)
	networks._physical_group = NetworkShapes.Family.HIGHWAY
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	var minimum := INF
	var maximum := -INF
	var clearance := INF
	var joint := .0
	var tangent := .0
	for step: int in length*8+1:
		var index := mini(step/8,length-1)
		var along := step/8.0-index
		for across: float in [.04,.28,.5,.72,.96]:
			var offset := Vector2(along,across) if ew else Vector2(across,along)
			var cell := start+direction*index
			var p := graph.point(cell,&"highway",offset)
			minimum = minf(minimum,p.y)
			maximum = maxf(maximum,p.y)
			clearance = minf(clearance,p.y-CityGeometry3D.water_surface_height(city,cell))
			check_lt(absf(networks._point(city,cell,offset,.65).y-p.y),.00001,"highway traffic uses its visible rigid bridge deck")
	for side: int in 2:
		var cell := start if side==0 else start+direction*(length-1)
		var bank := cell-direction if side==0 else cell+direction
		for across: float in [.04,.28,.5,.72,.96]:
			var offset := Vector2(side,across) if ew else Vector2(across,side)
			var edge := offset+Vector2(direction)*(1 if side==0 else -1)
			var p := graph.point(cell,&"highway",offset)
			var q := graph.point(bank,&"highway",edge)
			joint = maxf(joint,absf(p.y-q.y))
			var inward := Vector2(direction)*(.001 if side==0 else -.001)
			tangent = maxf(tangent,absf(q.y-graph.point(bank,&"highway",edge-inward).y)/.001)
	check_lt(maximum-minimum,.00001,"highway bridge stays level above the seabed")
	check_gt(clearance,.08,"whole highway deck clears the water")
	check_lt(joint,.00001,"full highway mouths meet their dry approaches")
	check_lt(rad_to_deg(atan(tangent)),.25,"land grade meets level span smoothly")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"bridge projection leaves imported/native city bytes exact")
	print("HIGHWAY_SPAN start=%s length=%d ew=%s bend=%.8f clearance=%.6f joint=%.8f tangent=%.6f"%[start,length,ew,maximum-minimum,clearance,joint,rad_to_deg(atan(tangent))])
	networks.free()

func test_paired_highway_spans_on_both_axes_keep_level_decks_and_smooth_banks() -> void:
	for ew: bool in [false,true]:
		for length: int in [1,2,6,19]:
			var city := crossing(ew,length,true)
			var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
			_measure(city,Vector2i(22,22),length,ew)
			_measure(city,Vector2i(22,22)+transverse,length,ew)
			var graph := CityTrafficGraph.new()
			graph.bind_city(city)
			check_lt(absf(graph.center(Vector2i(22,22),&"highway").y-graph.center(Vector2i(22,22)+transverse,&"highway").y),.00001,"paired carriageways share one level span")

func test_every_wet_highway_tile_in_valle_del_mar_clears_water_and_is_rigid() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Valle del Mar.sc2")
	check(loaded.ok,"bundled Valle del Mar imports")
	if not loaded.ok: return
	var city: City = loaded.city
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var count := 0
	var submerged := 0
	var bent := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			if not NetworkShapes.is_highway(city.building.atv(cell)) or not city.is_water(x,y):continue
			count += 1
			var a := graph.point(cell,&"highway",Vector2(.1,.1))
			var b := graph.point(cell,&"highway",Vector2(.9,.9))
			if minf(a.y,b.y)<=CityGeometry3D.water_surface_height(city,cell)+.08:submerged += 1
			if absf(a.y-b.y)>.00001:bent += 1
	check_eq(count,144,"every wet highway tile is covered")
	check_eq(submerged,0,"Valle del Mar highway bridges must clear water")
	check_eq(bent,0,"Valle del Mar highway bridge cells must be level")
	print("VALLE_WET_HIGHWAYS count=%d submerged=%d bent=%d"%[count,submerged,bent])

func test_dry_highway_hill_retains_its_existing_rounded_height() -> void:
	var city := preload("res://tests/test_highway_smoothness.gd").hill_city(true)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var p := graph.point(Vector2i(22,22),&"highway",Vector2(.31,.72))
	var expected := preload("res://scripts/view/city_highway_height_3d.gd").height(preload("res://scripts/view/city_highway_height_3d.gd").stencil(city,Vector2i(22,22)),Vector2(.31,.72))+.38
	check_lt(absf(p.y-expected),.00001,"ordinary dry highway still uses its rounded terrain field")

func test_all_six_valle_crossings_join_both_banks_and_both_carriageways() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Valle del Mar.sc2")
	check(loaded.ok,"bundled Valle del Mar imports")
	if not loaded.ok:return
	for span: Array in [[86,104,5,false],[8,112,7,false],[86,114,4,false],[14,122,18,true],[55,122,27,true],[92,122,12,true]]:
		var transverse := Vector2i.DOWN if span[3] else Vector2i.RIGHT
		for lane: int in 2: _measure(loaded.city,Vector2i(span[0],span[1])+transverse*lane,span[2],span[3])

func test_highway_bridge_heights_survive_native_city_roundtrip() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city
	var decoded := SaveFormat.decode_city(SaveFormat.encode_city(city))
	check(decoded.city!=null and decoded.error.is_empty(),"native city decode")
	if decoded.city==null:return
	var a := CityTrafficGraph.new();a.bind_city(city)
	var b := CityTrafficGraph.new();b.bind_city(decoded.city)
	var maximum := .0
	for cell: Vector2i in a._decks:
		if int(a._decks[cell].get("family",0))!=NetworkShapes.Family.HIGHWAY:continue
		maximum=maxf(maximum,absf(a.center(cell,&"highway").y-b.center(cell,&"highway").y))
	check_lt(maximum,.00001,"native reload keeps the imported highway bridge heights")

func test_distant_bank_and_span_demolition_refresh_every_dependent_region() -> void:
	var city := flat_city()
	for y: int in [30,31]:
		for x: int in range(8,79):
			city.building.put(x,y,74)
			if x>=14 and x<=66:
				city.terrain.put(x,y,Terrain.SURFACE)
				city.set_heights(x,y,1,4)
	var layer := CityNetworks3D.new()
	layer.update_regions(city,[])
	var old: float = layer._deck_profiles[Vector2i(14,30)].deck
	city.set_heights(67,30,8)
	var changed := layer.update_regions(city,[Rect2i(64,16,16,16)])
	check_gt(layer._deck_profiles[Vector2i(14,30)].deck,old,"distant dry bank revises the complete highway crossing")
	check_ge(changed.size(),5,"bank edit refreshes all five span ownership regions")
	var graph := CityTrafficGraph.new();graph.bind_city(city)
	var before := graph.center(Vector2i(14,30),&"highway").y
	city.set_heights(67,30,9)
	check(graph.refresh(),"traffic sees changed highway bank")
	check_gt(graph.center(Vector2i(14,30),&"highway").y,before,"ambient height follows changed shared profile")
	for y: int in [30,31]:city.building.put(40,y,0)
	layer.update_regions(city,[Rect2i(32,16,16,16)])
	check(not layer._deck_profiles.has(Vector2i(40,30)),"demolished highway deck is removed")
	var full := CityNetworks3D.new();full._prepare_bridge_decks(city)
	check_eq(layer._deck_profiles,full._deck_profiles,"incremental split agrees with fresh projection")
	check_eq(layer._approach_profiles,full._approach_profiles,"incremental grading agrees with fresh projection")
	full.free();layer.free()

func test_temporary_flood_does_not_add_permanent_highway_bridge_guards() -> void:
	var city := flat_city()
	for y: int in [22,23]:
		for x: int in range(18,30):city.building.put(x,y,74)
	var dry := CityNetworks3D.new();dry.rebuild(city)
	for y: int in [22,23]:
		for x: int in range(22,26):city.flood_overlay[Vector2i(x,y)]=1
	var flooded := CityNetworks3D.new();flooded.rebuild(city)
	check_eq(flooded._physical_boxes.size(),dry._physical_boxes.size(),"temporary flood does not build extra structural bridge obstacles")
	check(flooded._deck_profiles.is_empty(),"temporary flooded dry pavement keeps ordinary highway ownership")
	flooded.free();dry.free()

func test_a_hole_in_one_carriageway_keeps_the_surviving_lane_level() -> void:
	for ew: bool in [false,true]:
		var city := crossing(ew,6)
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		var start := Vector2i(22,22)
		var hole := start+d*3
		city.building.putv(hole,0)
		city.terrain_surface.set_vertex(22 if not ew else 28,28 if not ew else 22,8)
		city.terrain_surface.set_vertex(22 if not ew else 29,29 if not ew else 22,8)
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		var minimum := INF;var maximum := -INF
		for step: int in 6:
			for carriageway: int in 2:
				var cell := start+d*step+transverse*carriageway
				if cell==hole:continue
				var h := graph.center(cell,&"highway").y
				minimum=minf(minimum,h);maximum=maxf(maximum,h)
		check_lt(maximum-minimum,.00001,"partial damage leaves one continuous level connected structure")
		check(not graph._decks.has(hole),"missing highway tile stays missing")
		var networks := CityNetworks3D.new();networks._prepare_bridge_decks(city);networks._build_region(city,Rect2i(21,21,9,9))
		var floors := 0
		for patch: Dictionary in networks.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT)):
			if patch.cell==hole and patch.role==CityNetworks3D.PhysicalRole.FLOOR:floors += 1
		check_eq(floors,0,"damage does not gain an invisible replacement floor")
		networks.free()

func test_dry_shore_ground_inside_a_paired_crossing_clears_the_solid_deck() -> void:
	for ew: bool in [false,true]:
		var city := crossing(ew,6)
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		for step: int in [2,3]:
			var cell := Vector2i(22,22)+d*step
			city.terrain.putv(cell,Terrain.FLAT);city.set_heights(cell.x,cell.y,6,0)
		for step: int in [2,3,4]:
			var vertex := Vector2i(22,22)+d*step
			city.terrain_surface.set_vertex(vertex.x,vertex.y,6)
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		var cell := Vector2i(22,22)+d*3
		for across: float in [.04,.28,.72,.96]:
			var offset := Vector2(.5,across) if ew else Vector2(across,.5)
			check_ge(graph.point(cell,&"highway",offset).y-CityGeometry3D.point_on_ground(city,cell,offset).y,.12,"dry shore keeps slab clearance")

func test_native_wet_shore_relief_clears_the_whole_rigid_slab() -> void:
	for ew: bool in [false,true]:
		var city := crossing(ew,6)
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		for step: int in [2,3]:
			var cell := Vector2i(22,22)+d*step
			city.terrain.putv(cell,Terrain.SHORE|(Terrain.SLOPE_N if ew else Terrain.SLOPE_W))
			city.set_heights(cell.x,cell.y,4,4)
		for step: int in [2,3,4]:
			var vertex := Vector2i(22,22)+d*step
			city.terrain_surface.set_vertex(vertex.x,vertex.y,5)
			vertex += transverse
			city.terrain_surface.set_vertex(vertex.x,vertex.y,4)
		var graph := CityTrafficGraph.new();graph.bind_city(city)
		for step: int in [2,3]:
			var cell := Vector2i(22,22)+d*step
			for across: float in [.04,.28,.72,.96]:
				var offset := Vector2(.5,across) if ew else Vector2(across,.5)
				check_ge(graph.point(cell,&"highway",offset).y-CityGeometry3D.visible_ground_height(city,cell,offset),.12,"native partially wet shore remains below the solid bridge slab")

func test_imported_wet_shore_pillars_stay_beneath_the_pavement() -> void:
	for ew: bool in [false,true]:
		for shape: int in [Terrain.VALLEY_SW,Terrain.VALLEY_NW,Terrain.VALLEY_SE,Terrain.VALLEY_NE]:
			var city := flat_city()
			var d := Vector2i.RIGHT if ew else Vector2i.DOWN
			var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
			for lane: int in 2:
				for step: int in range(-4,10):
					var cell := Vector2i(22,22)+d*step+transverse*lane
					city.building.putv(cell,74 if ew else 73)
					if step>=0 and step<6:
						city.terrain.putv(cell,Terrain.SURFACE);city.set_heights(cell.x,cell.y,1,4)
			var cell := Vector2i(22,22)+d*3
			city.terrain.putv(cell,Terrain.SHORE|shape);city.set_heights(cell.x,cell.y,4,4)
			var networks := CityNetworks3D.new();networks._prepare_bridge_decks(city)
			networks._highway_supports(city,cell,city.building.atv(cell))
			var pillar: Dictionary = networks._physical_boxes[0]
			check_gt(pillar.size.y,0,"imported shoreline pillar has positive physical dimensions")
			var mesh: MeshInstance3D = networks.get_child(0)
			var top := -INF
			for vertex: Vector3 in mesh.mesh.get_faces():top=maxf(top,(mesh.transform*vertex).y)
			check_lt(top-float(networks._deck_profiles[cell].deck),.00001,"imported shoreline pillar mesh stays below pavement")
			networks.free()
