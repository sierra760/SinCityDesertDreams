# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const CAMERA_PATH := "res://scripts/exploration/city_explore_camera_3d.gd"

func test_camera_script_and_perspective_contract() -> void:
	check(ResourceLoader.exists(CAMERA_PATH), "exploration camera script exists")
	if not ResourceLoader.exists(CAMERA_PATH): return
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	check(rig.camera is Camera3D)
	check_eq(rig.camera.projection, Camera3D.PROJECTION_PERSPECTIVE)
	check(rig.camera.near <= .005)
	rig.free()

func test_modes_orbit_and_recenter_remain_finite() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var rig: Node3D = load(CAMERA_PATH).new()
	var target := Node3D.new()
	root.add_child(target)
	root.add_child(rig)
	for row in [[0,.35,.10,65.0],[1,.55,.18,70.0],[2,.95,.30,75.0]]:
		rig.configure_target(target,row[0])
		check(is_equal_approx(rig.camera.fov,row[3]))
		rig.update_follow(.1)
		check(rig.camera.global_position.is_finite())
		check(rig.camera.global_basis.is_finite())
	rig.orbit(Vector2(20000,-20000),1.0,false)
	rig.update_follow(.1)
	check(is_finite(rig.yaw))
	check(rig.camera.global_basis.is_finite())
	var yaw_before: float = rig.yaw
	target.rotation.y = 1.1
	rig.update_follow(.1)
	check(is_equal_approx(rig.yaw,yaw_before),"target heading does not cancel recent orbit")
	rig.recenter()
	rig.update_follow(.1)
	check(rig.camera.global_basis.is_finite())
	rig.clear_target()
	rig.free()
	target.free()

func test_world_obstacle_pulls_in_and_query_lot_does_not() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	var clear_distance: float = rig.camera.global_position.distance_to(target.global_position)
	var lot := _box(Vector3(0,.08,.18),Vector3(.22,.25,.035),2)
	await physics_frame
	rig.update_follow(.1)
	check(rig.camera.global_position.distance_to(target.global_position) >= clear_distance-.01,"lot query proxy ignored")
	lot.free()
	var wall := _box(Vector3(0,.08,.18),Vector3(.22,.25,.035),16)
	await physics_frame
	rig.update_follow(.1)
	var blocked_distance: float = rig.camera.global_position.distance_to(target.global_position)
	check(blocked_distance < clear_distance-.04,"world obstacle pulls camera in")
	check(rig.camera.global_position.z < .1505,"pull-in cuts to target side of obstructing wall")
	check(_focus_line_clear(rig,Vector3(0,.10,0)),"camera has clear focus line after wall appears")
	wall.free()
	await physics_frame
	rig.update_follow(.1)
	var first_return: float = rig.camera.global_position.distance_to(target.global_position)
	check(first_return > blocked_distance,"clearance returns")
	check(first_return < clear_distance+.01,"clearance returns with bounded easing")
	rig.free()
	target.free()

func test_actor_mask_is_ignored_and_tight_target_requests_recovery() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	var clear_distance: float = rig.camera.global_position.distance_to(target.global_position)
	var actor := _box(Vector3(0,.10,.18),Vector3(.22,.25,.035),32)
	await physics_frame
	rig.update_follow(.1)
	check(rig.camera.global_position.distance_to(target.global_position) >= clear_distance-.01,"actor mask ignored")
	actor.free()
	var recovery_events: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recovery_events.append(1))
	var tight := _box(Vector3(0,.10,0),Vector3(.07,.07,.07),16)
	await physics_frame
	rig.update_follow(.1)
	check_eq(recovery_events.size(),1,"embedded follow pivot requests recovery once")
	check(rig.camera.global_position.is_finite())
	check(rig.camera.global_position.distance_to(tight.global_position) >= .035+.012-.001,"camera depenetrates tight obstacle")
	rig.update_follow(.1)
	check_eq(recovery_events.size(),1,"persistent obstruction does not spam recovery")
	tight.free()
	rig.free()
	target.free()

func test_orbit_chord_never_crosses_world_obstacle() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	var wall := _box(Vector3(.18,.13,.18),Vector3(.09,.2,.09),4)
	await physics_frame
	rig.orbit(Vector2(-524,0),1.0,false)
	for i in 8:
		rig.update_follow(.1)
		check(not _camera_overlaps_world(rig),"orbit chord sphere stays outside layer-4 shell step %d" % i)
	wall.free()
	rig.free()
	target.free()

func test_full_enclosure_withholds_view_or_keeps_clear_previous_position() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	rig.camera.current = true
	var recovery_events: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recovery_events.append(1))
	var enclosure := _box(Vector3(0,.1,0),Vector3(.3,.3,.3),16)
	await physics_frame
	rig.update_follow(.1)
	check_eq(recovery_events.size(),1)
	check(not rig.camera.current or not _camera_overlaps_world(rig),"fully enclosed focus never shows a camera inside solid")
	enclosure.free()
	rig.free()
	target.free()

func test_target_change_while_withheld_restores_explore_camera() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	rig.camera.current = true
	var enclosure := _box(Vector3(0,.1,0),Vector3(1.2,1.2,1.2),16)
	await physics_frame
	rig.update_follow(.1)
	check(not rig.camera.current,"enclosed target withholds the explore camera")
	# Entering/leaving a vehicle, selecting one or recovering retargets while
	# the view is withheld. The next clear follow must reclaim the view.
	rig.configure_target(target,1)
	enclosure.free()
	await physics_frame
	rig.update_follow(.1)
	check(rig.camera.current,"clear follow after retarget makes the explore camera current again")
	rig.clear_target()
	var second := _box(Vector3(0,.1,0),Vector3(1.2,1.2,1.2),16)
	rig.configure_target(target,0)
	await physics_frame
	rig.update_follow(.1)
	check(not rig.camera.current,"second enclosure withholds again")
	rig.clear_target()
	second.free()
	await physics_frame
	rig.configure_target(target,0)
	rig.update_follow(.1)
	check(rig.camera.current,"clear_target keeps the withheld state for the next target")
	rig.free()
	target.free()

func test_camera_collapsed_over_pivot_keeps_orbit_heading() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.yaw = .7
	rig.pitch = .2
	rig.camera.global_position = target.global_position + Vector3.UP * .3
	rig._frame_actor()
	var first: Basis = rig.camera.global_basis
	rig._frame_actor()
	rig._frame_actor()
	var expected := Vector3(-sin(.7)*cos(.2),-sin(.2),-cos(.7)*cos(.2))
	check(first.is_finite(),"vertical framing stays finite")
	check((-rig.camera.global_basis.z).distance_to(expected) < .0001,"vertical framing aims along the orbit heading")
	check(rig.camera.global_basis.is_equal_approx(first),"repeated vertical framing does not accumulate tilt")
	rig.free()
	target.free()

func test_target_collision_exclusions_follow_subtree_changes() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	var probe := Vector3(0,.1,.3)
	await physics_frame
	check(rig._point_clear(probe),"empty space is clear")
	var body := StaticBody3D.new()
	body.collision_layer = 16
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.1,.1,.1)
	shape.shape = box
	body.add_child(shape)
	body.position = probe
	target.add_child(body)
	var outsider := _box(Vector3(0,.1,-.3),Vector3(.1,.1,.1),16)
	await physics_frame
	check(rig._point_clear(probe),"collision added under the target stays excluded")
	check(not rig._point_clear(Vector3(0,.1,-.3)),"other world collision still blocks")
	target.remove_child(body)
	root.add_child(body)
	await physics_frame
	check(not rig._point_clear(probe),"collision moved out of the target subtree blocks again")
	body.free()
	outsider.free()
	rig.free()
	target.free()

func test_floor_layer_also_blocks_camera() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	var clear_distance: float = rig.camera.global_position.distance_to(target.global_position)
	var floor_wall := _box(Vector3(0,.10,.18),Vector3(.22,.25,.035),8)
	await physics_frame
	rig.update_follow(.1)
	check(rig.camera.global_position.distance_to(target.global_position) < clear_distance-.04,"layer-8 floor geometry obstructs camera")
	floor_wall.free()
	rig.free()
	target.free()

func test_distant_target_relocation_cuts_to_clear_side_of_world_wall() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,ExploreActorProfile.Mode.WALK)
	rig.update_follow(.1)
	var wall := _box(Vector3(0,.15,.5),Vector3(2,.5,.03),16)
	await physics_frame
	check(_focus_line_clear(rig,Vector3(0,.10,0)),"initial camera has a clear focus line")
	# Recovery can relocate a target across a shell. The radial
	# focus-to-endpoint sweep is clear, while the previous camera position is
	# still a collision-free point on the wall's opposite side.
	target.global_position = Vector3(0,0,1)
	rig.update_follow(.1)
	check(rig.camera.global_position.z > .55,"large relocation cuts to the new target side")
	check(_focus_line_clear(rig,Vector3(0,.10,1)),"camera keeps an unobstructed line to relocated focus")
	check(not _camera_overlaps_world(rig),"new follow point remains sphere clear")
	wall.free()
	rig.free()
	target.free()

func test_flying_actor_below_ceiling_does_not_recover_for_high_camera_focus() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var underside := 14.02719
	var deck_top := 14.12219
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(0,13.71836,0)
	var roof := _box(Vector3(0,(underside+deck_top)*.5,0),Vector3(3,deck_top-underside,3),16)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,ExploreActorProfile.Mode.FLY)
	var recovery_events: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recovery_events.append(1))
	await physics_frame
	var body_top: float = target.global_position.y + float((ExploreActorProfile.geometry(ExploreActorProfile.Mode.FLY)["size"] as Vector3).y)
	var nominal_focus: Vector3 = target.global_position + Vector3.UP * float(CityExploreCamera3D.FOLLOW_HEIGHT[ExploreActorProfile.Mode.FLY])
	check(body_top + CityExploreCamera3D.CAMERA_RADIUS < underside,"declared helicopter body has physical ceiling clearance")
	check(_sphere_overlaps_world(rig,nominal_focus),"high nominal camera focus touches the ceiling")
	for tick in 3:
		rig.update_follow(.1)
		check_eq(recovery_events.size(),0,"camera focus alone must not relocate a valid helicopter")
		check(not _camera_overlaps_world(rig),"camera remains physically clear beneath roof")
		target.global_position.y += .01
	# Later the nominal pivot passes cleanly above this thin deck while the
	# entire actor remains below it. Point-clear focus alone must not pull the
	# camera across the solid roof and hide its target.
	target.global_position.y = 13.886529
	body_top = target.global_position.y + float((ExploreActorProfile.geometry(ExploreActorProfile.Mode.FLY)["size"] as Vector3).y)
	nominal_focus = target.global_position + Vector3.UP * float(CityExploreCamera3D.FOLLOW_HEIGHT[ExploreActorProfile.Mode.FLY])
	var body_center := target.global_position + Vector3.UP * .07
	var rise := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CityExploreCamera3D.CAMERA_RADIUS
	rise.shape = sphere
	rise.collision_mask = 28
	rise.transform = Transform3D(Basis.IDENTITY,body_center)
	rise.motion = nominal_focus - body_center
	var rise_cast := rig.get_world_3d().direct_space_state.cast_motion(rise)
	check(body_top < underside,"high legal helicopter body still clears underside")
	check(not _sphere_overlaps_world(rig,nominal_focus),"nominal focus has passed through and is point-clear above deck")
	check(rise_cast.size() > 0 and rise_cast[0] < .999,"vertical body-to-focus path crosses roof")
	rig.update_follow(.1)
	check_eq(recovery_events.size(),0,"crossed camera focus never requests actor recovery")
	check(rig.camera.global_position.y < underside - CityExploreCamera3D.CAMERA_RADIUS,
		"camera stays on actor side of thin highway deck")
	check(_focus_line_clear(rig,body_center),"camera keeps physical line of sight to actor center")
	var horizontal_standoff := Vector2(rig.camera.global_position.x-target.global_position.x,
		rig.camera.global_position.z-target.global_position.z).length()
	check(horizontal_standoff >= .30,"camera retains an external third-person view below deck")
	roof.free()
	rig.free()
	target.free()

func test_near_wall_without_valid_offsets_requests_recovery() -> void:
	if not ResourceLoader.exists(CAMERA_PATH): return
	var target := Node3D.new()
	root.add_child(target)
	var rig: Node3D = load(CAMERA_PATH).new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.update_follow(.1)
	var recovery_events: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recovery_events.append(1))
	var solids: Array[StaticBody3D] = []
	solids.append(_box(Vector3(0,.10,.016),Vector3(.2,.2,.004),16))
	for offset in [Vector3.UP*.035,Vector3.FORWARD*.035,Vector3.BACK*.035,
		Vector3.LEFT*.035,Vector3.RIGHT*.035,Vector3.UP*.07]:
		solids.append(_box(Vector3(0,.10,0)+offset,Vector3(.01,.01,.01),16))
	await physics_frame
	check(not _sphere_overlaps_world(rig,Vector3(0,.10,0)),"focus remains clear")
	rig.update_follow(.1)
	check_eq(recovery_events.size(),1,"no finite fallback requests recovery")
	check(not rig.camera.current or not _camera_overlaps_world(rig),"no invalid camera point committed")
	rig.update_follow(.1)
	check_eq(recovery_events.size(),1,"recovery request stays latched")
	for solid in solids: solid.free()
	rig.free()
	target.free()

func _camera_overlaps_world(rig: Node3D) -> bool:
	return _sphere_overlaps_world(rig,rig.camera.global_position)

func _sphere_overlaps_world(rig: Node3D,position: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = .012
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,position)
	query.collision_mask = 28
	return not rig.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _focus_line_clear(rig: Node3D,focus: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = .012
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,focus)
	query.collision_mask = 28
	query.motion = rig.camera.global_position-focus
	var cast := rig.get_world_3d().direct_space_state.cast_motion(query)
	return cast.size() > 0 and cast[0] >= .999

func _box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	return body

func test_closing_passenger_door_keeps_camera_inside_without_actor_recovery() -> void:
	var train := ExploreTransitTrain.new()
	root.add_child(train)
	train.global_transform = Transform3D(Basis.looking_at(Vector3.RIGHT),Vector3(20.5,4*CityGeometry3D.HEIGHT+.055,20.5))
	var target := ExplorePedestrian.new()
	root.add_child(target)
	target.global_position = train.global_position+Vector3(0,.02591,.01326)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.yaw = 0
	rig.set_cabin(ExploreTransitTrain.CABIN,train.global_transform,true)
	var recoveries: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recoveries.append(1))
	for index in 121:
		train.set_doors(1.0-float(index)/120.0,Vector3.BACK)
		await physics_frame
		rig.update_follow(1.0/60.0)
		check(rig._point_clear(rig.camera.global_position),"closing door camera remains physically clear")
	check_eq(recoveries.size(),0,"camera squeeze cannot recover a supported passenger out of carriage")
	check(rig.cabin_first_person,"tight closed door uses unobstructed eye view")
	check(target.visible and not target._visual.visible,"only close avatar mesh hides; walking root remains active")
	train.set_doors(1.0,Vector3.BACK)
	await physics_frame
	rig.update_follow(1.0/60.0)
	check(rig.cabin_first_person and not target._visual.visible,"open doorway keeps the passenger eye inside the cabin")
	check(ExploreTransitTrain.CABIN.grow(-CityExploreCamera3D.CAMERA_RADIUS).has_point(train.global_transform.affine_inverse()*rig.camera.global_position),"an open door does not release the cabin camera bounds")
	rig.set_cabin(AABB(),Transform3D.IDENTITY,false)
	rig.update_follow(1.0/60.0)
	check(target._visual.visible,"leaving cabin restores pedestrian model")
	rig.free()
	target.free()
	train.free()
	await physics_frame
