# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
const PATH := "res://scripts/core/agricultural_parcel_geometry.gd"

func geometry() -> Script:
	check(ResourceLoader.exists(PATH), "exact-member geometry contract exists")
	return load(PATH) if ResourceLoader.exists(PATH) else null

func ring() -> PackedInt32Array:
	return F.ring()

func test_ring_has_inner_fence_and_no_hole_shortcut() -> void:
	var g = geometry()
	if g == null: return
	var r := F.record(1,ring(),&"cattle_range")
	var layout: Dictionary = g.plan(r)
	check(layout.ok)
	if layout.profile.is_empty(): check(false,"prospective prepared pasture profile"); return
	var pen: Dictionary = layout.profile.pens[0]
	check(g.navigation_clear(Vector2(8,24),pen,2.7))
	check(g.navigation_clear(Vector2(40,24),pen,2.7))
	check(not g.navigation_clear(Vector2(24,24),pen,2.7))
	check(not g.navigation_segment(Vector2(8,24),Vector2(40,24),pen,2.7))
	check_eq(g.boundary(r.members).size(),16)
	var perimeter := 0.0
	var gates := 0
	for fence: Dictionary in pen.fences:
		var length := Vector2(fence.a[0],fence.a[1]).distance_to(Vector2(fence.b[0],fence.b[1]))
		perimeter+=length
		if fence.gate: gates+=1;check_eq(length,3.0)
	check_eq(perimeter,256.0,"outer and hole fence cover entire exposed perimeter")
	check_eq(gates,1)
	check_eq(r.modules,[],"planning must not mutate input")

func test_boundary_loops_are_oriented_and_deterministic() -> void:
	var g = geometry()
	if g == null: return
	var members := ring()
	var edges: Array = g.boundary(members)
	members.reverse()
	check_eq(g.boundary(members),edges)
	var areas: Array = []
	var area := 0
	var first: Vector2i = edges[0].a
	for n in edges.size():
		var e: Dictionary = edges[n]
		check_eq((e.b-e.a).length_squared(),1)
		area += e.a.x*e.b.y-e.b.x*e.a.y
		if e.b == first:
			areas.append(area)
			area = 0
			if n+1 < edges.size(): first=edges[n+1].a
		else: check_eq(e.b,edges[n+1].a)
	check_eq(areas,[18,-2],"outer clockwise in +Z; hole opposite")
	var diagonal: Array = g.boundary(F.mask([[20,20],[21,21]]))
	check_eq(diagonal.size(),8)
	check_eq(diagonal[3].b,diagonal[0].a,"vertex-touch must close first loop")
	check_eq(diagonal[7].b,diagonal[4].a)

func test_concave_u_and_l_do_not_fill_missing_land() -> void:
	var g = geometry()
	if g == null: return
	var u := F.u_shape()
	var layout: Dictionary = g.plan(F.record(1,u,&"sheep_pasture"))
	check(layout.ok)
	var pen: Dictionary = layout.profile.pens[0]
	check(g.navigation_clear(Vector2(8,24),pen,1.74))
	check(g.navigation_clear(Vector2(40,24),pen,1.74))
	check(not g.navigation_segment(Vector2(8,24),Vector2(40,24),pen,1.74))
	check_eq(g.boundary(u).size(),16)
	var l: Dictionary = g.plan(F.record(2,F.l_shape()))
	check_eq(l.edges.size(),8)
	check(l.ok)

func test_shared_fence_ownership_does_not_open_logical_pen() -> void:
	var g = geometry()
	if g == null: return
	check_eq(g.fence_owner(7,3),3)
	check_eq(g.fence_owner(3,7),3)
	check_eq(g.fence_owner(7,0),7,"empty, crop, or different support plane")
	check_eq(g.fence_owner(7,-1),7)
	var layout: Dictionary = g.plan(F.record(7,ring(),&"cattle_range"))
	check(not g.navigation_segment(Vector2(40,24),Vector2(56,24),layout.profile.pens[0],2.64))

func test_module_fit_reuse_and_stale_obstacles() -> void:
	var g = geometry()
	if g == null: return
	var r := F.record(1,ring(),&"cattle_range")
	var a: Dictionary = g.plan(r)
	check_eq(a.modules.size(),2)
	var moved: Array = a.modules.duplicate(true)
	moved[0].at = Vector3(40,.14,40)
	var b: Dictionary = g.plan(r,moved)
	check(b.ok)
	check_eq(b.modules[0],moved[0],"valid retained placement has priority")
	check_ne(b.obstacles,a.obstacles,"collision rebuilt from placements")
	var bad: Array = moved.duplicate(true)
	bad[0].at = Vector3(24,.14,24)
	var c: Dictionary = g.plan(r,bad)
	check(c.ok)
	check_ne(c.modules[0],bad[0],"hole placement cannot be retained")
	var crop: Dictionary = g.plan(F.record(2,F.mask([[20,20]])))
	check(crop.ok)
	check_eq(crop.modules[0].key,&"farm_shed")
	check_eq(crop.obstacles[0].size[0],10.5,"full roof width blocks movement")
	check_eq(crop.obstacles[0].size[2],7.5)

func test_stock_grid_and_targets_are_bounded_connected_and_separated() -> void:
	var g = geometry()
	if g == null: return
	var m := PackedInt32Array()
	for z in range(20,25):
		for x in range(20,32): m.append(z*128+x)
	var r := F.record(1,m,&"cattle_range")
	var layout: Dictionary = g.plan(r)
	check(layout.ok)
	var p: Dictionary = layout.profile.pens[0]
	check_eq(p.count,12)
	check_eq(g.max_safe_stock(r,layout),12)
	check(p.bounds[2]>24,"large local coordinates stay legal")
	check(p.navigation_nodes.size()<=4096)
	check(p.navigation_edges.size()<=8192)
	check_eq(p.grid_step,2.0)
	for i in p.spawns.size():
		var a := Vector2(p.spawns[i][0],p.spawns[i][1])
		check(g.navigation_clear(a,p,2.64))
		for j in i:
			check(a.distance_to(Vector2(p.spawns[j][0],p.spawns[j][1]))>=4.92)
	for points in [p.feed_targets,p.drink_targets]:
		for a in points: check(a in p.navigation_nodes,"targets on selected safe component")
	var reachable := {0:true}
	var queue: Array = [0]
	var cursor := 0
	while cursor<queue.size():
		var current: int = queue[cursor]
		for edge: Array in p.navigation_edges:
			var next := -1
			if edge[0]==current: next=edge[1]
			elif edge[1]==current: next=edge[0]
			if next>=0 and not reachable.has(next): reachable[next]=true;queue.append(next)
		cursor+=1
	check_eq(reachable.size(),p.navigation_nodes.size(),"every spawn and target shares one connected component")
	for spawn: Array in p.spawns: check(spawn in p.navigation_nodes)
	for i in r.stock_units: r.stock_units[i]=0
	check(g.plan(r).profile.is_empty(),"zero entitlement never fakes herd")

func test_store_rejects_invalid_and_missing_required_modules_atomically() -> void:
	var g = geometry()
	if g == null: return
	var c = flat_city()
	var r := F.record(1,ring(),&"cattle_range",&"active")
	F.zone(c,r.members)
	r.modules = g.plan(r).modules
	for kind in ["missing","unknown","hole","yaw","nan","height","overlap","off_lattice"]:
		var bad := r.duplicate(true)
		match kind:
			"missing": bad.modules.clear()
			"unknown": bad.modules[0].key=&"unknown"
			"hole": bad.modules[0].at=Vector3(24,.14,24)
			"yaw": bad.modules[0].yaw=4
			"nan": bad.modules[0].at.x=NAN
			"height": bad.modules[0].at.y=3
			"overlap": bad.modules[1].at=bad.modules[0].at
			"off_lattice": bad.modules[0].at.x+=.1
		check_ne(c.agricultural_parcels.put(c,bad),OK,kind)
		check(c.agricultural_parcels.records().is_empty())
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var lost: Dictionary = c.agricultural_parcels.record(1)
	lost.modules.clear()
	lost.state=&"prepared"
	check_eq(c.agricultural_parcels.put(c,lost),OK,"module-loss prepared records remain eligible")
	check(g.plan(lost).ok)

func test_legacy_profile_is_unchanged() -> void:
	var g = geometry()
	if g == null: return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agriculture/enclosures.json"))
	var m := ring()
	m.append(21*128+21)
	m.sort()
	for mode in [&"legacy",&"square"]:
		var r := F.record(1,m,&"cattle_range")
		r.mode=mode
		r.legacy_code=269
		var p: Dictionary = g.plan(r).profile
		var expected: Dictionary = source.profiles.cattle_range.duplicate(true)
		expected.animal_profile=source.species.beef_cattle
		check_eq(p,expected)

func test_dumbbell_neck_and_reflex_corner_use_whole_body_clearance() -> void:
	var g = geometry()
	if g == null: return
	var m := F.dumbbell()
	var layout: Dictionary = g.plan(F.record(1,m,&"cattle_range"))
	check(layout.ok)
	var pen: Dictionary = layout.profile.pens[0]
	check(g.navigation_segment(Vector2(24,24),Vector2(56,24),pen,2.64))
	check(not g.navigation_clear(Vector2(40,24),pen,8.0),"neck must fit entire radius plus fence")
	check(not g.navigation_clear(Vector2(33,17),pen,2.64),"reflex corner blocks body outside mask")
	check(not g.navigation_clear(Vector2(NAN,1),pen,2.64))
	check(not g.navigation_clear(Vector2(40,24),pen,-1))

func test_catalog_dispatch_uses_generated_boundary_at_large_coordinates() -> void:
	var g = geometry()
	if g == null: return
	var r := F.record(1,ring(),&"cattle_range")
	r.origin_index=18*128+18
	var layout: Dictionary = g.plan(r)
	var pen: Dictionary = layout.profile.pens[0]
	var catalog := AgricultureAssetCatalog.new()
	check(catalog.navigation_clear(Vector2(72,56),pen,2.64))
	check(not catalog.navigation_segment(Vector2(40,56),Vector2(72,56),pen,2.64))

func test_cut_square_cannot_reuse_authored_enclosure() -> void:
	var g = geometry()
	if g == null: return
	var r := F.record(1,ring(),&"cattle_range")
	r.mode=&"square"
	r.legacy_code=269
	var layout: Dictionary = g.plan(r)
	check(not layout.ok,"missing center cannot retain complete square profile")
	check(layout.profile.is_empty())

func test_layout_cache_inputs_are_exact_bounded_and_detached() -> void:
	var r := F.record(1,F.square(3),&"cattle_range")
	AgriculturalParcelGeometry._layouts.clear()
	var before: int = AgriculturalParcelGeometry._compilations
	var plan := AgriculturalParcelGeometry.plan(r)
	check(plan.ok)
	var expected := plan.duplicate(true)
	r.modules = plan.modules.duplicate(true)
	r.last_month = 22;r.failed_months = 2;r.revision = 90;r.state = &"active"
	check_eq(AgriculturalParcelGeometry.plan(r),expected)
	check_eq(AgriculturalParcelGeometry._compilations,before+1,"placement, validation and bookkeeping share one proof")
	plan.modules.clear();plan.profile.pens[0].navigation_nodes.clear()
	check_eq(AgriculturalParcelGeometry.plan(r),expected,"callers cannot corrupt cached geometry")
	var original := r.duplicate(true)
	for field in ["members","origin_index","mode","archetype","modules","stock_units"]:
		r = original.duplicate(true)
		match field:
			"members": r.members.remove_at(r.members.size()-1)
			"origin_index": r.origin_index -= 1
			"mode": r.mode = &"square"
			"archetype": r.archetype = &"sheep_pasture"
			"modules": r.modules[0].at.x += .5
			"stock_units": r.stock_units[r.members[0]] = 0
		var count: int = AgriculturalParcelGeometry._compilations
		AgriculturalParcelGeometry.plan(r)
		check_eq(AgriculturalParcelGeometry._compilations,count+1,"changed geometry input recompiles: "+field)
	for offset in 40:
		r = original.duplicate(true);r.origin_index -= offset*128
		AgriculturalParcelGeometry.plan(r)
	check(AgriculturalParcelGeometry._layouts.size()<=AgriculturalParcelGeometry.LAYOUT_CACHE_LIMIT)

func test_lattice_graph_equals_full_swept_reference() -> void:
	for members in [F.l_shape(),F.ring(),F.u_shape(),F.dumbbell()]:
		for radius in [.01,.73,1.4,2.1]:
			var r := F.record(1,members,&"cattle_range")
			var edges := AgriculturalParcelGeometry.boundary(members)
			var obstacles: Array = [{"bounds":[10.5,3.0,11.0,20.5]}]
			var pen := AgriculturalParcelGeometry._pen(r,edges,obstacles)
			var graph := AgriculturalParcelGeometry._graph(pen,radius)
			var nodes: Array = [];var lookup := {};var links: Array = []
			var box: Array = pen.bounds
			for z in range(ceili(box[1]/2),floori(box[3]/2)+1):
				for x in range(ceili(box[0]/2),floori(box[2]/2)+1):
					var point := Vector2(x,z)*2
					if AgriculturalParcelGeometry.navigation_clear(point,pen,radius): lookup[Vector2i(x,z)]=nodes.size();nodes.append(point)
			for cell: Vector2i in lookup:
				for offset in [Vector2i.RIGHT,Vector2i.DOWN]:
					if not lookup.has(cell+offset): continue
					var a: int = lookup[cell];var b: int = lookup[cell+offset]
					if AgriculturalParcelGeometry.navigation_segment(nodes[a],nodes[b],pen,radius): links.append([a,b])
			check_eq(graph.nodes,nodes,"identical safe lattice nodes")
			check_eq(graph.edges,links,"identical full swept graph edges, including thin intervening box")
