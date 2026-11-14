# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## At night every drive-in plays the film on its actual screen and fills its
## rows with parked cars, which Explore can take and drive off the lot.
extends "res://tests/exploration/explore_session_case.gd"

func _drive_in_city() -> City:
	var value := flat_city()
	value.stamp_building(20,20,DriveInNightShow.code())
	for x in range(17,27):
		value.building.putv(Vector2i(x,23),NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return value

func _show() -> DriveInNightShow:
	return view.night.drive_ins if view.night != null and is_instance_valid(view.night.drive_ins) else null

func _lot() -> Node3D:
	for lot: Node in view.buildings.get_children():
		if int(lot.get_meta("code",-1)) == DriveInNightShow.code(): return lot
	return null

## World-space bounds of the authored screen face, from the model itself.
func _authored_screen(lot: Node3D) -> AABB:
	var model := (load(CityModelCatalog.ROOT+"182-blender.glb") as PackedScene).instantiate() as Node3D
	var bounds := AABB()
	var found := false
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var source := node as MeshInstance3D
		var local := _relative(source,model)
		for surface: int in source.mesh.get_surface_count():
			var material := source.mesh.surface_get_material(surface)
			if material == null or material.resource_name != "screen": continue
			for vertex: Vector3 in source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := local*vertex
				if not found: bounds = AABB(point,Vector3.ZERO)
				else: bounds = bounds.expand(point)
				found = true
	model.free()
	check(found,"the drive-in model has its authored screen")
	# Model metres to the lot's tile frame.
	return lot.global_transform*Transform3D(Basis.IDENTITY.scaled(Vector3.ONE/16.0),Vector3.ZERO)*bounds

func _relative(node: Node3D, top: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != top:
		if at is Node3D: out = (at as Node3D).transform*out
		at = at.get_parent()
	return out

func test_night_fills_the_rows_and_projects_the_film_on_the_screen() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	var lot := _lot()
	check(lot != null,"the drive-in lot is projected")
	if lot == null: return
	check(_show() == null or _show().parked_slots().is_empty(),"no cars or film by day")
	view.set_night_mode(true,true)
	var show := _show()
	check(show != null,"night builds the drive-in show")
	if show == null: return
	check_eq(show.screen_count(),1,"one screen per drive-in")
	var anchor: Vector2i = lot.get_meta("cell")
	var expected := 0
	for index: int in DriveInNightShow.spaces().size():
		if DriveInNightShow.occupied(anchor,index): expected += 1
	var slots := show.parked_slots()
	check_eq(slots.size(),expected,"every taken space holds a car")
	check_between(expected,6,17,"a busy night, never a full or empty lot")
	var kinds := {}
	for slot: Node3D in slots:
		kinds[slot.get_meta("kind")] = true
		# Vehicle meshes face -Z; the screen stands at the lot's -Z end.
		check_gt(slot.global_basis.z.dot(Vector3.BACK),.99,"cars face the screen")
		var local := (lot.global_transform.affine_inverse()*slot.global_position)*16.0
		check_between(local.z,-14.5,10.0,"cars park between the screen and the snack bar")
		check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,CityModelCatalog.SHELL_LAYER,"parked cars are solid")
	check_gt(kinds.size(),1,"moviegoers drive different cars")
	# The picture sits just in front of the actual screen and inside it.
	var screen := show.find_child("Screen",true,false) as MeshInstance3D
	check(screen != null,"the film has a screen surface")
	var authored := _authored_screen(lot)
	if screen != null:
		var face := screen.global_transform*(screen.mesh as QuadMesh).get_aabb()
		check_gt(face.position.z,authored.end.z-.001,"the picture is in front of the screen face")
		check_lt(face.position.z-authored.end.z,.01,"and does not float away from it")
		check(authored.grow(.001).encloses(AABB(Vector3(face.position.x,face.position.y,authored.position.z),Vector3(face.size.x,face.size.y,0))),"the 4:3 picture stays inside the screen")
		check_gt(face.size.y/authored.size.y,.95,"the picture uses the full screen height")
	check(show.film_texture() != null,"the projector decodes the film")
	if show.film_texture() != null: check_eq(show.film_texture().get_size(),Vector2(320,240))
	# The same lot fills the same spaces with the same cars every night.
	var before := slots.map(func(s: Node3D) -> Array: return [s.get_meta("index"),s.get_meta("kind")])
	view.set_night_mode(false,true)
	check(show.parked_slots().is_empty() and show.screen_count() == 0,"day removes the cars and the picture")
	view.set_night_mode(true,true)
	check_eq(show.parked_slots().map(func(s: Node3D) -> Array: return [s.get_meta("index"),s.get_meta("kind")]),before,"stable without any game random stream")
	await after_each()

func test_parked_cars_keep_their_lamps_off() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.set_night_mode(true,true)
	var show := _show()
	if show == null: return
	var slots := show.parked_slots()
	check(not slots.is_empty())
	await process_frame
	var lamps := 0
	for slot: Node3D in slots:
		var mesh := DriveInNightShow.parked_mesh(slot.get_meta("kind"))
		var source := CityTrafficCatalog.mesh_for(slot.get_meta("kind"))
		check(mesh != source,"parked cars use their own lamp materials")
		for surface: int in mesh.get_surface_count():
			var original := source.surface_get_material(surface)
			var role := CityNightMode.role_for(original.resource_name)
			if role not in [CityNightMode.Role.HEADLIGHT,CityNightMode.Role.TAILLIGHT]: continue
			lamps += 1
			check(not CityNightMode.lights(mesh.surface_get_material(surface)),"a parked car's lamps stay dark")
			check(not (mesh.surface_get_material(surface) as BaseMaterial3D).emission_enabled)
	check_gt(lamps,0,"the cars have head and tail lamps to switch off")
	await after_each()

func test_explore_steals_a_parked_car_and_drives_it_off_the_lot() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.set_night_mode(true,true)
	var show := _show()
	if show == null: return
	await physics_frame
	check(session.enter(city,Vector3(21.5,GROUND,23.5)))
	session.set_physics_process(false)
	# A car in the middle row, beside the centre lane.
	var slot: Node3D = null
	for candidate: Node3D in show.parked_slots():
		if slot == null or absf(candidate.position.x) < absf(slot.position.x): slot = candidate
	if slot == null: return
	var kind: StringName = slot.get_meta("kind")
	var index: int = slot.get_meta("index")
	session.pedestrian.global_position = slot.global_position+slot.global_basis.x*.2
	await physics_frame
	var reach: Dictionary = session._vehicle_in_reach()
	check(reach.has("service") and reach.service == slot,"the walker reaches the parked car")
	check(session.request_interaction(),"F takes the moviegoer's car")
	var actor := session.occupied as ExploreCar
	check(actor != null,"the player now drives it")
	if actor == null: return
	check_eq(actor.kind,kind,"the same make of car")
	check(slot.get_meta("claimed",false) and not show.car_drawn(slot),"its space is empty")
	check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,0)
	check(actor.on_drivable_ground(),"the car may move on the drive-in lot")
	var parked := actor.global_transform
	var behind := parked
	behind.origin = Vector3(21.5,parked.origin.y,20.05)
	actor.apply_safe_pose(behind)
	check(not actor.on_drivable_ground(),"but not behind the screen")
	# Turn round in the centre lane and drive out through the frontage.
	var lane := Transform3D(Basis(Vector3.UP,PI),Vector3(21.5,parked.origin.y,22.3))
	actor.apply_safe_pose(lane)
	check(actor.on_drivable_ground(),"the centre lane is open")
	var drive := ExploreInputFrame.idle()
	drive.move = Vector2(0,-1)
	for tick in 150:
		actor.step(drive,0,1.0/60.0)
		await physics_frame
	check_gt(actor.global_position.z,23.0,"the car reaches the street")
	# Night falling again leaves the space empty while the car is out.
	view.set_night_mode(false,true)
	view.set_night_mode(true,true)
	var again: Node3D = null
	for candidate: Node3D in show.parked_slots():
		if candidate.get_meta("index") == index: again = candidate
	check(again != null and again.get_meta("claimed",false) and not show.car_drawn(again),"a rebuilt show keeps the space empty")
	session.leave()
	for candidate: Node3D in show.parked_slots():
		check(not candidate.get_meta("claimed",false) and show.car_drawn(candidate),"leaving Explore parks the car again")
	await after_each()

func test_the_film_decodes_only_while_a_screen_is_on_camera() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.set_night_mode(true,true)
	var show := _show()
	if show == null: return
	await process_frame
	var notifier := show.find_child("OnCamera",true,false) as VisibleOnScreenNotifier3D
	check(notifier != null,"each screen watches whether a camera sees it")
	if notifier == null: return
	check(not show.is_playing(),"no decoding while no screen is in view")
	notifier.screen_entered.emit()
	check(show.is_playing(),"the film runs once its screen is seen")
	view.buildings.visible = false
	check(not show.visible and not show.is_playing(),"no film while buildings are hidden")
	check(show.nearest(show.parked_slots()[0].global_position,.5).is_empty(),"and no car to take")
	view.buildings.visible = true
	check(show.visible and show.is_playing())
	notifier.screen_exited.emit()
	check(not show.is_playing(),"looking away stops the decoder again")
	await after_each()

func test_moviegoers_sit_in_the_chairs_facing_the_screen() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.set_night_mode(true,true)
	var show := _show()
	if show == null: return
	var lot := _lot()
	var seated := show.audience_count()
	check_between(seated,6,20,"a good part of the 24 chairs are taken, never all of them")
	for i in 240:
		if show.seated_drawn() == seated: break
		await process_frame
	check_eq(show.seated_drawn(),seated,"every moviegoer is drawn once the posed figures load")
	# One batch per car make and per figure; no per-car or per-person nodes.
	var kinds := {}
	for slot: Node3D in show.parked_slots(): kinds[slot.get_meta("kind")] = true
	var batches := show.find_children("*","MultiMeshInstance3D",false,false)
	check_eq(show.find_children("*","MeshInstance3D",true,false).size(),1,"only the screen is a plain mesh")
	var figures := 0
	for batch: MultiMeshInstance3D in batches:
		if batch.name.begins_with("Moviegoers_"):
			figures += 1
			check_eq(batch.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"seated people cast no shadow maps")
	check_eq(batches.size(),kinds.size()+figures,"one draw per make and per figure")
	# Each person sits on an authored chair, just above the cushion.
	var chairs: Array[Vector2] = []
	for row: float in DriveInNightShow.CHAIR_ROWS:
		for column: float in DriveInNightShow.CHAIR_COLUMNS: chairs.append(Vector2(column,row))
	var places := show.audience_places()
	check_eq(places.size(),seated)
	var taken := {}
	for place: Transform3D in places:
		var local := (lot.global_transform.affine_inverse()*place.origin)*16.0
		var nearest := -1
		for c: int in chairs.size():
			if Vector2(local.x,local.z).distance_to(chairs[c]) < .1: nearest = c
		check(nearest >= 0,"on a chair")
		check(not taken.has(nearest),"one person per chair")
		taken[nearest] = true
		check_between(local.y,DriveInNightShow.SEAT_TOP,DriveInNightShow.SEAT_TOP+.2,"seated on the cushion")
		check_gt(place.basis.z.dot(lot.global_basis.z),.99,"facing the screen")
	await after_each()

func test_a_seated_figure_has_its_legs_forward() -> void:
	var host := Node.new()
	root.add_child(host)
	var mesh := DriveInNightShow.seated_mesh(2,host) as ArrayMesh
	check(mesh != null,"the crowd figure poses sitting without a renderer")
	if mesh == null:
		host.free()
		return
	var box := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*16.0),Vector3.ZERO)*mesh.get_aabb()
	check_lt(box.size.y,1.45,"shorter than a standing figure")
	check_lt(box.position.z,-.35,"knees forward, toward the screen")
	check_between(box.position.y,-.75,-.3,"shins hang below the seat")
	check_gt(box.end.y,.5,"torso and head above the pelvis")
	check(DriveInNightShow.seated_mesh(2,host) == mesh,"posed once per figure for the session")
	# The shipped library holds exactly these poses (re-bake it when they change).
	var library := load(DriveInNightShow.AUDIENCE_LIBRARY) as MeshLibrary
	check(library != null,"the posed audience ships with the game")
	if library != null:
		check_eq(library.get_item_list().size(),CityTrafficCatalog.pedestrian_variants(),"every crowd figure has a seated pose")
		for figure: int in CityTrafficCatalog.pedestrian_variants():
			var shipped := library.get_item_mesh(figure)
			var posed := DriveInNightShow.seated_mesh(figure,host)
			check(shipped != null and posed != null,"figure %d" % figure)
			if shipped == null or posed == null: continue
			check_eq(shipped.get_surface_count(),posed.get_surface_count(),"figure %d surfaces" % figure)
			check_lt(shipped.get_aabb().position.distance_to(posed.get_aabb().position)+shipped.get_aabb().size.distance_to(posed.get_aabb().size),.0005,"figure %d matches its current pose" % figure)
	host.free()
	await process_frame

func test_a_drive_in_built_at_night_joins_the_reel_already_showing() -> void:
	if not _setup(_drive_in_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.set_night_mode(true,true)
	var show := _show()
	if show == null: return
	var projector := show.find_child("Projector",false,false)
	check(projector != null,"one projector serves the screens")
	city.stamp_building(26,20,DriveInNightShow.code())
	view.buildings.rebuild(city,view.catalog)
	check(show.refresh(),"the new lot rebuilds the show")
	check_eq(show.screen_count(),2,"both drive-ins have the picture")
	check_eq(show.find_child("Projector",false,false),projector,"the reel keeps running instead of restarting")
	check_eq(show.find_children("Projector","VideoStreamPlayer",false,false).size(),1)
	check(not show.refresh(),"nothing to rebuild when no drive-in changed")
	await after_each()
