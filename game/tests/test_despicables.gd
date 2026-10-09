# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"

const STORE := &"com_corner_store"
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)

func test_store_offers_only_slots_and_video_poker() -> void:
	check_eq(Buildings.id_of(STORE),126)
	check_eq(ResortThemes.key_for_building(126),STORE)
	check_eq(ResortThemes.resort_name(STORE),"Despicable's")
	check_eq(ResortThemes.games(STORE),[&"slots",&"video_poker"])
	for kind: StringName in ResortThemes.KINDS:
		check_eq(ResortThemes.offers(STORE,kind),kind in [&"slots",&"video_poker"])

func test_one_dollar_minimum_and_thousand_dollar_cap() -> void:
	var sim := make_simulation(flat_city(),7)
	check_eq(sim.casino().limits(STORE,20000),{"minimum":1,"maximum":1000})
	check_eq(sim.casino().limits(STORE,17),{"minimum":1,"maximum":17})
	check(bool(sim.casino().can_play(STORE,1).ok))
	check(not bool(sim.casino().can_play(STORE,0).ok))
	check(not sim.casino_commit(STORE,&"slots",1001))
	check(not sim.casino_commit(STORE,&"blackjack",10))
	check_eq(sim.city.funds,20000)
	check(sim.casino_commit(STORE,&"slots",1000))
	sim.casino_settle(STORE,&"slots",1000,2000)
	check_eq(sim.city.funds,21000)
	check_eq(int(sim.casino().ledger(STORE).rounds),1)
	sim.free()

func test_store_history_roundtrips_and_old_saves_start_empty() -> void:
	var sim := make_simulation(flat_city(),7)
	check(sim.casino_commit(STORE,&"video_poker",1))
	sim.casino_settle(STORE,&"video_poker",1,2)
	var data := sim.casino().save()
	var other := CasinoSystem.new()
	other.load(data)
	check_eq(other.ledger(STORE),sim.casino().ledger(STORE))
	other.load({})
	check_eq(int(other.ledger(STORE).rounds),0)
	sim.free()

func test_small_half_store_plan_has_six_individually_playable_machines() -> void:
	var plan := ResortInteriorLayouts.layout(STORE)
	check(not plan.is_empty(),"store has an interior plan")
	if plan.is_empty(): return
	check_eq(plan.bounds.size.x,12.0/16.0)
	check_eq(plan.bounds.size.z,10.0/16.0)
	check_eq(plan.tables.size(),6)
	var counts := {}
	for table: Dictionary in plan.tables:
		counts[table.game] = int(counts.get(table.game,0))+int(table.count)
		check_eq(int(table.count),1,"each machine has its own interaction seat")
		check_gt(table.pose.origin.x,0.0,"machines occupy the right half")
		check(plan.bounds.has_point(table.seat),"seat inside store")
		for obstacle: Dictionary in plan.obstacles:
			var rect := Rect2(obstacle.center-obstacle.half,obstacle.half*2.0)
			check(not rect.grow(.018).has_point(Vector2(table.seat.x,table.seat.z)),"seat clear of "+String(obstacle.name))
	check_eq(counts.get(&"slots",0),4)
	check_eq(counts.get(&"video_poker",0),2)
	check_ge(plan.obstacles.size(),6,"stocked store fixtures have physical footprints")

func test_paintings_clear_the_ceiling_and_badges_clear_the_cabinet_body() -> void:
	var plan := ResortInteriorLayouts.layout(STORE)
	for art: Dictionary in plan.art:
		check(art.pose.origin.y+art.size.y*.5+.05<=3.05,"painting and frame below 3.2 m ceiling with clearance")
	var badge: Dictionary = plan.get("slot_badge",{})
	check(not badge.is_empty(),"small cabinet has an explicit unobstructed badge placement")
	if badge.is_empty(): return
	check_ge(badge.position.y-badge.size.y*.5,1.58,"badge fits the header plate lower edge")
	check_gt(badge.position.z,.20,"badge sits in front of cabinet body and trim")
	check(badge.position.y+badge.size.y*.5<=1.78,"badge fits the lit header plate")

func test_store_door_uses_its_own_one_tile_lot() -> void:
	var city := flat_city()
	city.stamp_building(ANCHOR.x,ANCHOR.y,126)
	var pose := Access.threshold(city,ANCHOR,126)
	check_eq(pose.origin.x,ANCHOR.x+.5,"visible central door")
	check_between(pose.origin.z,ANCHOR.y+.72,ANCHOR.y+.80,"outside the shop shell")
	var found := Access.nearby(city,pose.origin)
	check_eq(found.get("key",&""),STORE)
	check_eq(found.get("rect",Rect2i()),Rect2i(ANCHOR,Vector2i.ONE))
	check(Access.nearby(city,pose.origin+Vector3(0,-2.6,0)).is_empty())
	city.building.putv(ANCHOR,Buildings.NONE)
	check(not Access.exists(city,ANCHOR,126))

func test_store_world_uses_small_bounds_and_real_assets() -> void:
	if ResortInteriorLayouts.layout(STORE).is_empty():
		check(false,"store interior is missing")
		return
	var world := ResortInteriorWorld3D.new()
	root.add_child(world)
	world.build(STORE,126,ANCHOR)
	check_eq(world.position,Vector3(ANCHOR.x+.5,-2.5,ANCHOR.y+.5))
	check(not bool(world.stats.placeholder),"authored Blender store hall")
	check_eq(int(world.stats.slots),4)
	check(world.contains(world.mat_transform().origin))
	check(not world.contains(world.position+Vector3(1,0,0)),"containment uses store bounds")
	check_eq(world.tables().size(),6)
	world.free()

func test_own_reel_card_and_payout_art_loads() -> void:
	for asset: String in ResortArtwork.ASSETS:
		check(ResortArtwork.texture(STORE,asset)!=null,"Despicable's "+asset)
	for rank: int in [11,12,13]:
		check(ResortArtwork.court(STORE,rank)!=null)
	for symbol: String in CasinoParams.SLOT_SYMBOLS:
		var texture := ResortArtwork.texture(STORE,"payout-"+symbol)
		if texture == null: continue
		check_eq(texture.get_image().get_pixel(0,0).a,0.0,"transparent icon background")

func test_closed_street_door_prevents_walking_out_of_the_pocket() -> void:
	var world := ResortInteriorWorld3D.new()
	root.add_child(world)
	world.build(STORE,126,ANCHOR)
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(world.position+Vector3(0,1,4)/16.0,world.position+Vector3(0,1,6)/16.0,ExploreActorProfile.OBSTACLE)
	check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"closed street door keeps walker inside until Interact")
	world.free()

const STEP := .04

func _support(space: PhysicsDirectSpaceState3D, world: Node3D, local: Vector2) -> float:
	var top := world.position+Vector3(local.x,.1,local.y)
	var query := PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*.2,ExploreActorProfile.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<.57: return NAN
	return float(hit.position.y)

func _capsule(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK)
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*(.0575+.004))
	query.collision_mask = ExploreActorProfile.WORLD
	query.margin = .001
	return query

func _clear(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	return space.intersect_shape(_capsule(at),1).is_empty()

func _path_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := _capsule(from)
	query.motion = to-from
	var result := space.cast_motion(query)
	return result.size()>0 and result[0]>=.999

func test_all_six_seats_and_store_aisles_are_physically_reachable() -> void:
	for code: int in [126]:
		var key := ResortInteriorLayouts.key_for_building(code)
		var world := ResortInteriorWorld3D.new()
		root.add_child(world)
		world.build(key,code,Vector2i(20,18))
		await physics_frame
		await physics_frame
		var stats := world.stats
		print("  hall %d: %d triangles, %d draw surfaces, %d lights, built in %.1f ms" % [code,int(stats.triangles),int(stats.draw_surfaces),int(stats.lights),world.build_usec/1000.0])
		check(not bool(stats.placeholder),"%d uses the authored hall" % code)
		check_between(int(stats.triangles),1000,150000,"%d populated triangle budget" % code)
		check_between(int(stats.draw_surfaces),1,40,"%d draw surface budget" % code)
		check_between(int(stats.lights),2,7,"%d fill plus at most six lamps" % code)
		check_eq(int(stats.slots),4,"%d slot multimesh instances" % code)
		var space := world.get_world_3d().direct_space_state
		var mat: Vector3 = world.mat_transform().origin
		check(abs(_support(space,world,Vector2(mat.x,mat.z)-Vector2(world.position.x,world.position.z))-world.position.y)<.005,"%d mat stands on the floor" % code)
		check(_clear(space,mat),"%d mat is clear" % code)
		# Walkable floor grid at 0.04 tile, joined by unobstructed capsule moves.
		var bounds: AABB = world.plan.bounds
		var cells := {}
		var xs := int(bounds.size.x/STEP)
		var zs := int(bounds.size.z/STEP)
		for i: int in xs:
			for j: int in zs:
				var local := Vector2(bounds.position.x+(i+.5)*STEP,bounds.position.z+(j+.5)*STEP)
				var height := _support(space,world,local)
				if is_nan(height): continue
				var at := Vector3(world.position.x+local.x,height,world.position.z+local.y)
				if _clear(space,at): cells[Vector2i(i,j)] = at
		var start := Vector2i(int((mat.x-world.position.x-bounds.position.x)/STEP),int((mat.z-world.position.z-bounds.position.z)/STEP))
		check(cells.has(start),"%d mat cell is walkable" % code)
		var reached := {start: true}
		var frontier: Array[Vector2i] = [start]
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next := cell+step
				if reached.has(next) or not cells.has(next): continue
				var a: Vector3 = cells[cell]
				var b: Vector3 = cells[next]
				if absf(a.y-b.y)>ExplorePedestrian.STEP: continue
				if not _path_clear(space,a+Vector3.UP*maxf(0,b.y-a.y),b): continue
				reached[next] = true
				frontier.append(next)
		check_gt(reached.size(),cells.size()*3/5,"%d most of the walkable floor is reachable" % code)
		for table: Dictionary in world.tables():
			var seat: Vector3 = table.seat
			var seated := _support(space,world,Vector2(seat.x,seat.z)-Vector2(world.position.x,world.position.z))
			check(absf(seated-seat.y)<.005,"%d %s seat on the floor" % [code,table.game])
			seat.y = seated
			check(_clear(space,seat),"%d %s seat is clear" % [code,table.game])
			var joined := false
			for cell: Vector2i in reached:
				var at: Vector3 = cells[cell]
				if Vector2(at.x-seat.x,at.z-seat.z).length()<=.15 and absf(at.y-seat.y)<=ExplorePedestrian.STEP and _path_clear(space,at+Vector3.UP*maxf(0,seat.y-at.y),seat):
					joined = true
					break
			check(joined,"%d %s seat reachable from the mat" % [code,table.game])
		world.free()
		await physics_frame
