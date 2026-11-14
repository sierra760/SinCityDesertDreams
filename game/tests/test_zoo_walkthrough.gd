# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Zoo (218) is the Mirage Menagerie: an open gate faces the street, a
## promenade runs between four railed pens and each pen keeps a fictional
## animal that moves on its own clock. Explore visitors walk in, cannot climb
## into the pens, and can read each pen's plaque to make its animal show off.
extends "res://tests/exploration/explore_session_case.gd"

const ANCHOR := Vector2i(20,20)

func _zoo_city(street_side: Vector2i = Vector2i.DOWN) -> City:
	var value := flat_city()
	value.stamp_building(ANCHOR.x,ANCHOR.y,Buildings.ZOO)
	var road := NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10)
	if street_side == Vector2i.DOWN:
		for x in range(17,27): value.building.putv(Vector2i(x,24),road)
	else:
		for y in range(17,27): value.building.putv(Vector2i(24,y),NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	return value

func _lot() -> Node3D:
	for lot: Node in view.buildings.get_children():
		if int(lot.get_meta("code",-1)) == Buildings.ZOO: return lot
	return null

## World point of a lot-model metre position.
func _world(local: Vector3) -> Vector3:
	var lot := _lot()
	return view.buildings.global_transform*(lot.get_meta("authored_transform") as Transform3D)*local

func _local(world: Vector3) -> Vector3:
	var lot := _lot()
	return (view.buildings.global_transform*(lot.get_meta("authored_transform") as Transform3D)).affine_inverse()*world

func _camera_over(point: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(point+Vector3(0,6,4),point)
	return camera

func _trees() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/desert-dreams-3d/landscaping.json"))
	for row: Dictionary in data.entries:
		if int(row.code) == Buildings.ZOO: return row.palms
	return []

func test_the_zoo_faces_its_street_with_four_animals_in_their_pens() -> void:
	for side: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT]:
		if not _setup(_zoo_city(side)): return
		view.buildings.rebuild(city,view.catalog)
		var lot := _lot()
		check(lot != null,"the zoo lot is projected")
		if lot == null: return
		var want := 0.0 if side == Vector2i.DOWN else PI/2.0
		check(is_equal_approx(wrapf(lot.rotation.y-want,-PI,PI),0.0),"the gate faces the street")
		# The gate's outside, on the authored +Z front, is next to the street.
		var gate := _world(Vector3(0,.2,33.0))
		check(Vector2(gate.x,gate.z).distance_to(Vector2(22,22)+Vector2(side)*2.0) < .2,"the open gate sits on the street side")
		view.zoo.sync()
		check_eq(view.zoo.zoo_count(),1,"one zoo")
		var animals := view.zoo.animals()
		check_eq(animals.size(),4,"four residents")
		var kinds := {}
		for animal: ZooAnimal in animals:
			kinds[animal.species] = true
			check(animal.get_node_or_null("Model") is Skeleton3D and animal.has_part(&"Head"),"the animal has its skeleton and moving parts")
			check(ZooAnimal.inside_pen(animal.quadrant,animal.position),"%s starts inside its pen" % animal.display_name())
		check_eq(kinds.size(),4,"four different species")
		await after_each()

func test_animals_roam_their_pens_clear_of_trees_and_hold_still_when_paused() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	var camera := _camera_over(Vector3(22,.3,22))
	view.zoo.advance(0.0,camera,false)
	var animals := view.zoo.animals()
	check_eq(animals.size(),4)
	var trees := _trees()
	check_gt(trees.size(),3,"the pens are planted")
	var start := {}
	var travelled := {}
	for animal: ZooAnimal in animals:
		start[animal.species] = animal.position
		travelled[animal.species] = 0.0
	var last := start.duplicate()
	for step: int in 3600:
		view.zoo.advance(1.0/30.0,camera,false)
		for animal: ZooAnimal in animals:
			var at := animal.position
			travelled[animal.species] = float(travelled[animal.species])+Vector2(at.x,at.z).distance_to(Vector2(last[animal.species].x,last[animal.species].z))
			last[animal.species] = at
			if step % 30 != 0: continue
			var x := at.x*animal.quadrant.x
			var z := at.z*animal.quadrant.y
			check(x > ZooAnimal.RAIL+.8 and x < ZooAnimal.INNER-.8 and z > ZooAnimal.RAIL+.8 and z < ZooAnimal.INNER-.8,"%s keeps inside its rails and walls" % animal.display_name())
			for tree: Array in trees:
				var trunk := Vector2(float(tree[0]),float(tree[2]))*16.0
				check(Vector2(at.x,at.z).distance_to(trunk) > 1.2,"%s keeps clear of the trees" % animal.display_name())
	for animal: ZooAnimal in animals:
		check_gt(float(travelled[animal.species]),8.0,"%s moves about" % animal.display_name())
	# Paused, nothing moves; resuming carries on.
	var held := {}
	for animal: ZooAnimal in animals: held[animal.species] = animal.transform
	for step: int in 60: view.zoo.advance(1.0/30.0,camera,true)
	for animal: ZooAnimal in animals: check_eq(animal.transform,held[animal.species],"paused animals hold still")
	# A far camera leaves them hidden and still.
	camera.look_at_from_position(Vector3(110,6,110),Vector3(110,0,106))
	view.zoo.advance(1.0/30.0,camera,false)
	for animal: ZooAnimal in animals: check(not animal.visible,"a far zoo's animals are not drawn")
	camera.free()
	await after_each()

func test_each_animal_is_one_draw_with_shadows_only_up_close() -> void:
	if not _setup(_zoo_city()): return
	# Detail follows on-screen size, so judge it in an ordinary window.
	var window_size := root.size
	root.size = Vector2i(1280,800)
	view.buildings.rebuild(city,view.catalog)
	var camera := _camera_over(Vector3(22,.3,22))
	camera.look_at_from_position(Vector3(22,1.5,24.5),Vector3(22,0,22))
	view.zoo.advance(0.0,camera,false)
	var animals := view.zoo.animals()
	check_eq(animals.size(),4)
	var meshes := {}
	for animal: ZooAnimal in animals:
		var instances := animal.find_children("*","MeshInstance3D",true,false)
		check_eq(instances.size(),1,"%s draws as one mesh" % animal.display_name())
		var mesh := animal.mesh_instance()
		check_eq(mesh.mesh.get_surface_count(),1,"with one surface")
		check(mesh.skin != null and (animal.get_node("Model") as Skeleton3D).get_bone_count() >= 4,"skinned to its jointed parts")
		check_eq(mesh.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"close up it casts a shadow")
		meshes[animal.species] = mesh.mesh
	# A second zoo shares each species' mesh instead of building another.
	city.stamp_building(26,20,Buildings.ZOO)
	view.buildings.rebuild(city,view.catalog)
	view.zoo.advance(0.0,camera,false)
	check_eq(view.zoo.animals().size(),8)
	for animal: ZooAnimal in view.zoo.animals():
		check(animal.mesh_instance().mesh == meshes[animal.species],"%s shares one mesh across zoos" % animal.display_name())
	# Moving parts still move: the hop lifts the Saguaroo's legs off its rest pose.
	var saguaroo: ZooAnimal = null
	for animal: ZooAnimal in view.zoo.animals():
		if animal.species == &"saguaroo": saguaroo = animal
	var rests := {}
	for step: int in 120:
		view.zoo.advance(1.0/30.0,camera,false)
		if not saguaroo.part_pose(&"LegL").is_equal_approx((saguaroo.get_node("Model") as Skeleton3D).get_bone_rest((saguaroo.get_node("Model") as Skeleton3D).find_bone("LegL"))): rests["moved"] = true
	check(rests.has("moved"),"the bones are posed")
	check(((saguaroo.get_node("Model") as Skeleton3D).get_bone_pose((saguaroo.get_node("Model") as Skeleton3D).find_bone("LegL"))).is_equal_approx(saguaroo.part_pose(&"LegL")),"and the skeleton carries the pose")
	# Farther off: still drawn and moving, but no shadow.
	camera.look_at_from_position(Vector3(22,3,48),Vector3(22,0,22))
	var held := saguaroo.transform
	view.zoo.advance(1.0/30.0,camera,false)
	for animal: ZooAnimal in view.zoo.animals():
		check(animal.visible,"a zoo a few dozen tiles off is still drawn")
		check_eq(animal.mesh_instance().cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"without a shadow")
	# Looking away, animals hold still.
	camera.look_at_from_position(Vector3(22,2,30),Vector3(22,2,60))
	held = saguaroo.transform
	for step: int in 30: view.zoo.advance(1.0/30.0,camera,false)
	check_eq(saguaroo.transform,held,"an off-camera zoo does no animation work")
	camera.free()
	root.size = window_size
	await after_each()

func test_the_same_zoo_looks_the_same_every_time() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	var camera := _camera_over(Vector3(22,.3,22))
	for step: int in 90: view.zoo.advance(1.0/30.0,camera,false)
	var first := view.zoo.animals().map(func(a: ZooAnimal) -> Transform3D: return a.transform)
	view.buildings.rebuild(city,view.catalog)
	for step: int in 90: view.zoo.advance(1.0/30.0,camera,false)
	var again := view.zoo.animals().map(func(a: ZooAnimal) -> Transform3D: return a.transform)
	check_eq(view.zoo.zoo_count(),1,"a rebuilt lot replaces its animals")
	for i: int in first.size():
		check((first[i] as Transform3D).is_equal_approx(again[i]),"no game random stream decides where they are")
	camera.free()
	await after_each()

func test_visitors_walk_in_through_the_gate_but_not_into_the_pens() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(22.0,GROUND,24.5)),"Explore starts on the street")
	session.set_physics_process(false)
	var walker: CharacterBody3D = session.pedestrian
	# Entry picks a road tile centre; line up with the gate on the same street.
	walker.global_position = Vector3(_world(Vector3(0,.2,40.0)).x,walker.global_position.y,walker.global_position.z)
	check_lt(absf(_local(walker.global_position).x),.01,"in front of the gate")
	await physics_frame
	var forward := ExploreInputFrame.idle()
	forward.move = Vector2(0,-1)
	forward.sprint = true
	for tick in 330:
		walker.step(forward,0.0,1.0/60.0)
		await physics_frame
	var inside := _local(walker.global_position)
	check_lt(inside.z,24.0,"the walker passes through the open gate")
	check_lt(absf(inside.x),4.5,"along the promenade")
	# Try to climb into the Saguaroo pen from beside its plaque.
	walker.global_position = _world(Vector3(3.2,.2,17.95))+Vector3(0,.01,0)
	walker.velocity = Vector3.ZERO
	await physics_frame
	var east := ExploreInputFrame.idle()
	east.move = Vector2(1,0)
	east.sprint = true
	for tick in 120:
		walker.step(east,0.0,1.0/60.0)
		await physics_frame
	check_lt(_local(walker.global_position).x,ZooAnimal.RAIL,"the rail keeps the visitor out")
	check(not ZooAnimal.inside_pen(Vector2(1,1),_local(walker.global_position)))
	# Jumping does not clear it either.
	east.jump = true
	for tick in 90:
		walker.step(east,0.0,1.0/60.0)
		await physics_frame
	check_lt(_local(walker.global_position).x,ZooAnimal.RAIL,"nor does a jump")
	# The east end of the cross promenade stops at the wall.
	walker.global_position = _world(Vector3(26.0,.2,0.0))+Vector3(0,.01,0)
	walker.velocity = Vector3.ZERO
	east.jump = false
	await physics_frame
	for tick in 150:
		walker.step(east,0.0,1.0/60.0)
		await physics_frame
	check_lt(_local(walker.global_position).x,ZooAnimal.INNER,"the zoo wall stands")
	await after_each()

func test_reading_a_plaque_shows_its_fact_and_the_animal_does_a_trick() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(22.0,GROUND,24.5)))
	session.set_physics_process(false)
	var statuses: Array[Dictionary] = []
	session.status_changed.connect(func(status: Dictionary) -> void: statuses.append(status))
	session.pedestrian.global_position = _world(ZooAnimal.plaque_point(Vector2(-1,1)))+Vector3(0,.01,0)
	await physics_frame
	var exhibit: Dictionary = session._zoo_exhibit()
	check_eq(String(exhibit.get("name","")),"Flamingoat","the visitor stands at the Flamingoat's plaque")
	session._publish_status()
	check(not statuses.is_empty() and String(statuses[-1].prompt) == "F to read about the Flamingoat","the prompt names the animal")
	var goat: ZooAnimal = exhibit.get("animal")
	check(goat != null and not goat.tricking())
	check(session.request_interaction(),"F reads the plaque")
	check(goat != null and goat.tricking(),"the Flamingoat shows off")
	check(String(session._message).begins_with("Flamingoat"),"the plaque's text is shown")
	session._tick_message(0.0)
	session._tick_message(5.0)
	check(not String(session._message).is_empty(),"long enough to read")
	session._tick_message(5.0)
	check(String(session._message).is_empty(),"and then it clears")
	# Far from any plaque there is nothing to read.
	session.pedestrian.global_position = _world(Vector3(0,.2,8.0))+Vector3(0,.01,0)
	await physics_frame
	check(session._zoo_exhibit().is_empty(),"no plaque in the middle of the promenade")
	await after_each()

func test_demolishing_the_zoo_lets_its_animals_go() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.zoo.sync()
	check_eq(view.zoo.animals().size(),4)
	for y in range(ANCHOR.y,ANCHOR.y+4):
		for x in range(ANCHOR.x,ANCHOR.x+4): city.building.put(x,y,0)
	view.buildings.rebuild(city,view.catalog)
	view.zoo.sync()
	check_eq(view.zoo.zoo_count(),0,"no zoo, no animals")
	check_eq(view.zoo.get_child_count(),0)
	await after_each()

func test_analytic_views_hide_the_animals() -> void:
	if not _setup(_zoo_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.zoo.sync()
	view.set_underground(true)
	check(not view.zoo.visible,"underground view hides the animals")
	view.set_underground(false)
	check(view.zoo.visible)
	await after_each()
