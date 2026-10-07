# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT
var fixture: Node3D
var world: Variant
var no_exclusions: Array[RID] = []

func setup(city: City) -> bool:
	fixture = Fixture.attach(self,city)
	world = fixture.get_node("traversal")
	return true

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	world = null
	await physics_frame

func ray(from: Vector3, to: Vector3, mask: int = ExploreActorProfile.WORLD) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,mask)
	query.hit_back_faces = true
	return fixture.get_world_3d().direct_space_state.intersect_ray(query)

func test_bridge_support_bounded_and_underside_solid() -> void:
	if not setup(Fixture.bridge_city()): return
	await physics_frame
	var deck := GROUND+.12
	var feet := Vector3(22.5,deck+.02,20.5)
	var hit: Dictionary = world.support_near(feet,.045,.08,no_exclusions)
	check(not hit.is_empty(),"bridge 83 interior deck supports feet")
	if not hit.is_empty():
		check(absf(hit.position.y-deck)<.0001,"deck matches the independently computed bridge 83 height")
		check(hit.normal.y>.99)
		check(hit.rid is RID)
		check(not world.touches_water(hit.position+Vector3.UP*.002))
	check(world.support_near(Vector3(22.5,GROUND-.2,20.5),.045,.08,no_exclusions).is_empty(),"bounded support never teleports up to deck or down to seabed")
	var up := ray(Vector3(22.5,GROUND-.1,20.5),Vector3(22.5,deck+.2,20.5))
	check(not up.is_empty(),"actual upward ray hits deck underside")
	if not up.is_empty(): check(up.position.y<deck and up.normal.y<-.9,"underside has real thickness")

func test_underpass_retains_lower_road_and_clearance() -> void:
	if not setup(Fixture.underpass_city()): return
	await physics_frame
	var feet := Vector3(22.5,GROUND+.04,20.5)
	var support: Dictionary = world.support_near(feet+Vector3.UP*.01,.045,.08,no_exclusions)
	check(not support.is_empty())
	if not support.is_empty(): check(absf(support.position.y-feet.y)<.001,"lower road chosen beneath upper highway")
	check(world.has_clearance(Transform3D(Basis.IDENTITY,feet+Vector3.UP*.059),ExploreActorProfile.shape(0),no_exclusions),"walk capsule fits below crossing")
	var hit := ray(feet+Vector3.UP*.2,feet+Vector3.UP)
	check(not hit.is_empty(),"underpass ceiling blocks upward cast")

func test_water_contact_stream_dry_corner_and_shore_shelf() -> void:
	var city := flat_city()
	city.terrain.put(20,20,0x40)
	city.terrain.put(21,20,0x33)
	city.set_heights(21,20,4,5)
	if not setup(city): return
	await physics_frame
	var top := CityGeometry3D.water_surface_height(city,Vector2i(20,20))
	check(world.touches_water(Vector3(20.5,top,20.5)),"stream center at water surface is wet")
	check(not world.touches_water(Vector3(20.1,top,20.1)),"stream corner remains dry")
	check(not world.touches_water(Vector3(20.5,top+.15,20.5)),"feet above water are dry")
	check(not world.touches_water(Vector3(21.9,GROUND+.2,20.5)),"shore shelf is outside water polygon")

func test_clearance_shell_query_and_actor_masks() -> void:
	if not setup(flat_city()): return
	var center := Vector3(22.5,GROUND+.2,20.5)
	var query_body := Fixture.box(fixture,center,Vector3(.2,.2,.2),2)
	await physics_frame
	var at := Transform3D(Basis.IDENTITY,center)
	check(world.has_clearance(at,ExploreActorProfile.shape(0),no_exclusions),"query layer2 ignored")
	query_body.free()
	var shell := Fixture.box(fixture.get_node("shells"),center,Vector3(.2,.2,.2),4)
	await physics_frame
	check(not world.has_clearance(at,ExploreActorProfile.shape(0),no_exclusions),"existing shell layer4 blocks")
	shell.free()
	var actor := Fixture.box(fixture,center,Vector3(.2,.2,.2),32)
	await physics_frame
	check(not world.has_clearance(at,ExploreActorProfile.shape(0),no_exclusions),"parked actor blocks clearance")
	var exclude: Array[RID] = [actor.get_rid()]
	check(world.has_clearance(at,ExploreActorProfile.shape(0),exclude),"explicit own actor RID is excluded")
	check(world.support_near(center,.02,.03,no_exclusions).is_empty(),"actors never serve as environmental floor")

func test_safe_pose_uses_feet_offsets_and_avoids_blocked_spawn() -> void:
	if not setup(flat_city()): return
	Fixture.box(fixture.get_node("shells"),Vector3(22.5,GROUND+.2,20.5),Vector3(.8,.4,.8),4)
	await physics_frame
	for mode: int in 3:
		var result: Dictionary = world.safe_pose(Vector3(22.5,GROUND,20.5),mode,no_exclusions)
		check(not result.is_empty(),"blocked origin finds bounded nearby safe candidate")
		if result.is_empty(): continue
		var at: Transform3D = result.transform
		check(at.is_finite())
		var feet := at.origin
		check(not world.touches_water(feet))
		at.origin.y += ExploreActorProfile.geometry(mode).foot_offset
		check(world.has_clearance(at,ExploreActorProfile.shape(mode),no_exclusions),"mode-specific shape fits returned foot-root pose")
		check(not world.support_near(feet,.045,.08,no_exclusions).is_empty(),"returned feet have checked support")

func test_safe_pose_exhaustion_nonfinite_and_city_bounds() -> void:
	if not setup(flat_city()): return
	await physics_frame
	check(world.safe_pose(Vector3(NAN,0,0),0,no_exclusions).is_empty())
	check(world.safe_pose(Vector3(INF,0,0),0,no_exclusions).is_empty())
	check(world.safe_pose(Vector3(-1,GROUND,20),0,no_exclusions).is_empty())
	check(world.safe_pose(Vector3(City.WIDTH+.1,GROUND,20),0,no_exclusions).is_empty())
	check(not world.has_clearance(Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),ExploreActorProfile.shape(0),no_exclusions))
	var no_chunks: Array[Dictionary] = []
	world.rebuild(flat_city(),no_chunks,{},2)
	await physics_frame
	for mode: int in 3: check(world.safe_pose(Vector3(22.5,GROUND,20.5),mode,no_exclusions).is_empty(),"exhausted search with no support cannot return unchecked fallback")

func test_revision_removes_old_bridge_synchronously_and_clear_releases() -> void:
	if not setup(Fixture.bridge_city()): return
	await physics_frame
	var feet := Vector3(22.5,GROUND+.13,20.5)
	check(not world.support_near(feet,.045,.08,no_exclusions).is_empty())
	var city := flat_city()
	var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	world.rebuild(city,chunks,{},2)
	check_eq(world.revision,2)
	check(world.support_near(feet,.01,.03,no_exclusions).is_empty(),"old bridge gone immediately after rebuild")
	await physics_frame
	check(world.support_near(feet,.01,.03,no_exclusions).is_empty(),"old bridge remains absent after physics sync")
	world.clear()
	await physics_frame
	check(world.support_near(Vector3(22.5,GROUND+.01,20.5),.02,.04,no_exclusions).is_empty(),"clear removes physical bodies")
	check_eq(world.get_child_count(),0,"clear releases owned shape references")

func test_ceiling_includes_transformed_shell_and_thin_obstacle_sweep() -> void:
	if not setup(flat_city()): return
	var shell := Fixture.box(fixture.get_node("shells"),Vector3(23,GROUND+3,20),Vector3(1,2,1),4)
	shell.rotation.z = PI/4
	world.rebuild(flat_city(),fixture.get_meta("chunks"),{},2)
	check(world.max_flight_y()>=GROUND+4+8,"flight ceiling includes transformed shell top")
	Fixture.box(fixture,Vector3(22.5,GROUND+.2,20.5),Vector3(.004,.4,1),16)
	await physics_frame
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ExploreActorProfile.shape(1)
	query.transform = Transform3D(Basis.IDENTITY,Vector3(22,GROUND+.06,20.5))
	query.motion = Vector3(1,0,0)
	query.collision_mask = ExploreActorProfile.WORLD
	var fractions := fixture.get_world_3d().direct_space_state.cast_motion(query)
	check(fractions[0]<.5,"swept car shape cannot cross thin wall")

func test_semantic_bridge_boxes_are_instantiated_and_block_rays() -> void:
	if not setup(Fixture.bridge_city()): return
	await physics_frame
	var networks := fixture.get_node("networks") as CityNetworks3D
	var records: Array = networks.physical_data().physical_boxes
	check(records.size()>=16,"bridge fixture contains actual parapet/support shape records")
	var boxes := 0
	for body: Node in world.get_children():
		for collision: Node in body.get_children():
			if collision is CollisionShape3D and collision.shape is BoxShape3D:
				boxes += 1
				check_eq(body.collision_layer,16)
	check_eq(boxes,records.size(),"every semantic structure box is instantiated")
	if not records.is_empty():
		var record: Dictionary = records[0]
		var at: Transform3D = record.transform
		var half_width: float = record.size.x*.5
		var hit := ray(at*Vector3(-half_width-.02,0,0),at*Vector3(half_width+.02,0,0),16)
		check(not hit.is_empty(),"actual bridge parapet stops a transverse physics cast")
	var count: int = world.rebuild_count
	for i: int in 20: world.support_near(Vector3(22.5,GROUND+.13,20.5),.045,.08,no_exclusions)
	check_eq(world.rebuild_count,count,"movement queries never rebuild geometry")

func test_unchanged_collision_revisions_retain_bodies_and_only_replace_changed_faces() -> void:
	if not setup(flat_city()): return
	var chunks: Array[Dictionary] = fixture.get_meta("chunks")
	var before: Array = world.get_children()
	var ids: Array[int] = []
	for body: Node in before: ids.append(body.get_instance_id())
	world.rebuild(flat_city(),chunks,{},2)
	var after_ids: Array[int] = []
	for body: Node in world.get_children(): after_ids.append(body.get_instance_id())
	check_eq(after_ids,ids,"identical collision contents retain their physics bodies")
	var changed := chunks.duplicate(true)
	var faces: PackedVector3Array = changed[0].physical_floor_faces
	for i: int in faces.size(): faces[i].y += .1
	changed[0].physical_floor_faces = faces
	world.rebuild(flat_city(),changed,{},3)
	check_eq(world.get_child_count(),ids.size(),"replacing faces does not accumulate bodies")
	var changed_ids: Array[int] = []
	for body: Node in world.get_children(): changed_ids.append(body.get_instance_id())
	check(changed_ids!=ids,"changed geometry replaces its body synchronously")
	world.clear()
	check_eq(world.get_child_count(),0)

func test_shell_bounds_match_shape_geometry_and_invalidate_after_shape_change() -> void:
	if not setup(flat_city()): return
	var at := Transform3D(Basis.from_euler(Vector3(.2,.4,.6)),Vector3(4,7,2))
	for shape: Shape3D in [BoxShape3D.new(),CylinderShape3D.new(),ConvexPolygonShape3D.new(),ConcavePolygonShape3D.new()]:
		var points := PackedVector3Array([Vector3(-1,0,-2),Vector3(2,0,1),Vector3(0,3,1),Vector3(2,0,1),Vector3(-1,0,-2),Vector3(0,-2,1)])
		if shape is ConvexPolygonShape3D: shape.points=points
		if shape is ConcavePolygonShape3D: shape.set_faces(points)
		var expected: float = (at*shape.get_debug_mesh().get_aabb()).end.y
		check(absf(world._shape_top(shape,at)-expected)<.00001,"direct bounds preserve transformed collision height")
		if shape is BoxShape3D: shape.size.y = 9
		elif shape is CylinderShape3D: shape.height = 9
		else:
			for i: int in points.size(): points[i].y += 4
			if shape is ConvexPolygonShape3D: shape.points=points
			else: shape.set_faces(points)
		expected = (at*shape.get_debug_mesh().get_aabb()).end.y
		check(absf(world._shape_top(shape,at)-expected)<.00001,"changed shared shape invalidates retained bounds")

func test_retained_geometry_detects_in_place_packed_array_mutation() -> void:
	if not setup(flat_city()): return
	var chunks: Array[Dictionary] = fixture.get_meta("chunks")
	var points: PackedVector3Array = chunks[0].physical_floor_faces
	var body: Node = world._retained[Vector2i(0,0)].body
	var prior_id := body.get_instance_id()
	points[0].y += .2
	world.rebuild(flat_city(),chunks,{},2)
	var replacement: Node = world._retained[Vector2i(0,0)].body
	check(replacement.get_instance_id()!=prior_id,"caller in-place packed-array edit invalidates retained collision")
	var shape: ConcavePolygonShape3D = replacement.get_child(0).shape
	check_eq(shape.get_faces()[0],points[0],"physics uses the changed vertex rather than stale cached faces")
