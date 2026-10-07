# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const ASSET_ROOT := "res://assets/desert-dreams-exploration/"
const SCENES := ["pedestrian", "car", "helicopter", "pedestrian_woman"]
const SIZES := [Vector3(.036,.115,.036),Vector3(.12,.08,.28),Vector3(.50,.14,.28),Vector3(.036,.115,.036)]
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
var actors: Array[Node] = []

class MotionDriver extends Node:
	signal completed
	var actor: ExplorePedestrian
	var frame := ExploreInputFrame.idle()
	var ticks := 0
	var total := 20
	func _physics_process(delta: float) -> void:
		actor.step(frame,0.0,delta)
		frame.jump = false
		ticks += 1
		if ticks>=total:
			set_physics_process(false)
			completed.emit()

func after_each() -> void:
	for actor in actors:
		if is_instance_valid(actor): actor.free()
	actors.clear()
	await process_frame

func _actor(actor_name: String) -> Node3D:
	var actor: Node3D = load(ASSET_ROOT+actor_name+".tscn").instantiate()
	root.add_child(actor)
	actors.append(actor)
	return actor

func _player(actor: Node) -> AnimationPlayer:
	var players := actor.find_children("*","AnimationPlayer",true,false)
	check_eq(players.size(),1,"pedestrian imports its authored animation player")
	return players[0] as AnimationPlayer if players.size()==1 else null

# Missing GLB instances, incorrect meter conversion, bad normals/materials or
# embedded physics must fail at the actual imported resource boundary.
func test_imported_models_fit_unchanged_actor_profiles() -> void:
	for index in SCENES.size():
		var actor: Node3D = _actor(SCENES[index])
		var imported := actor.get_node_or_null("ImportedModel") as Node3D
		check(imported != null,"%s wraps its Blender GLB" % SCENES[index])
		if imported == null: continue
		check(imported.scene_file_path.ends_with(SCENES[index]+".glb"),"wrapper instantiates the authored GLB")
		check(imported.scale.is_equal_approx(Vector3.ONE/16.0),"authored meters use city scale")
		_check_bounds(actor,SIZES[index],SCENES[index])
		check(_no_physics(actor),"imported visuals own no collision body or shape")
		var meshes := actor.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()>0,"GLB contains visible meshes")
		for mesh_node: MeshInstance3D in meshes:
			check(mesh_node.mesh is ArrayMesh,"Blender topology is imported, not a primitive placeholder")
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.mesh.surface_get_material(surface)
				check(material is StandardMaterial3D,"authored material survives import")
				if material != null:
					check(material.resource_path.begins_with(ASSET_ROOT) or material.resource_path.begins_with("res://.godot/imported/"+SCENES[index]+".glb-"),"material belongs to the owned actor import")
				var arrays := mesh_node.mesh.surface_get_arrays(surface)
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				check(not normals.is_empty(),"imported mesh has lighting normals")
				for normal in normals:
					check(normal.is_finite() and normal.length_squared()>.8 and normal.length_squared()<1.2,"normal is finite and normalized")

# An idle-processing player would walk while Explore is suspended. Clip selection
# and pose changes must come only from the public session-driven visual API.
func test_pedestrian_authored_clips_advance_only_on_session_ticks() -> void:
	var actor := _actor("pedestrian")
	var player := _player(actor)
	if player == null: return
	check_eq(player.autoplay,"","authored player has no autonomous startup clip")
	for clip in ["idle","walk","run","jump"]:
		check(player.has_animation(clip),"authored %s clip exists" % clip)
		if not player.has_animation(clip): return
	var skeletons := actor.find_children("*","Skeleton3D",true,false)
	check_eq(skeletons.size(),1,"one imported deforming skeleton")
	if skeletons.size()!=1: return
	var skeleton: Skeleton3D = skeletons[0]
	check(skeleton.get_bone_count()>=15,"limbs have articulated bones")
	for bone in skeleton.get_bone_count():
		check(skeleton.get_bone_rest(bone).is_finite(),"bone rest is finite")
	var thigh := skeleton.find_bone("LeftThigh")
	check(thigh>=0,"left thigh is independently animated")
	if thigh<0: return
	var root_pose := actor.transform
	var imported := actor.get_node("ImportedModel") as Node3D
	var imported_pose := imported.transform
	var skinned := 0
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if mesh.skin == null: continue
		check(mesh.skin.get_bind_count()>0,"skin has bone bind poses")
		skinned += 1
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			check_eq(weights.size(),vertices.size()*4,"each vertex has four imported skin influences")
			check_eq(bones.size(),weights.size(),"skin indices correspond to weights")
			if weights.size()!=vertices.size()*4 or bones.size()!=weights.size(): continue
			for vertex in vertices.size():
				var total := 0.0
				for slot in 4:
					var weight := weights[vertex*4+slot]
					check(is_finite(weight) and weight>=0.0,"skin weight is finite and nonnegative")
					if weight>0.0: check(bones[vertex*4+slot]>=0 and bones[vertex*4+slot]<mesh.skin.get_bind_count(),"skin influence maps to an imported bone")
					total += weight
				check_between(total,.999,1.001,"every visible vertex follows the rig")
	check(skinned>0,"imported vertices are skin-bound, not detached limb props")
	actor.set_motion(.09,0.0,false)
	actor.advance_visual(.1)
	check_eq(player.current_animation,"walk","walking selects authored walk")
	var before := skeleton.get_bone_pose_rotation(thigh)
	var cursor := player.current_animation_position
	for frame in 4: await process_frame
	check_eq(player.current_animation_position,cursor,"render frames cannot advance paused/session-owned clips")
	actor.advance_visual(.1)
	check(not skeleton.get_bone_pose_rotation(thigh).is_equal_approx(before),"manual delta changes actual skeletal pose")
	actor.set_motion(.20,0.0,false)
	actor.advance_visual(.1)
	check_eq(player.current_animation,"run","native sprint speed selects run")
	actor.set_motion(.20,0.0,true)
	actor.advance_visual(.1)
	check_eq(player.current_animation,"jump","airborne selects distinct jump")
	check_eq(player.get_animation("jump").loop_mode,Animation.LOOP_NONE,"jump holds its terminal pose, never loops in flight")
	actor.set_motion(0.0,0.0,false)
	check_eq(player.current_animation,"idle","stop_input changes locomotion state immediately")
	for step in 20: actor.advance_visual(1.0/60.0)
	check_eq(actor.transform,root_pose,"in-place animation never moves the feet root")
	check_eq(imported.transform,imported_pose,"in-place animation preserves the imported model origin and scale")
	check(_finite_pose(actor),"animated imported transforms remain finite")

func test_gait_progress_follows_physical_distance() -> void:
	var slow := _actor("pedestrian")
	var fast := _actor("pedestrian")
	var slow_player := _player(slow)
	var fast_player := _player(fast)
	if slow_player==null or fast_player==null: return
	slow.set_motion(.045,0.0,false)
	fast.set_motion(.09,0.0,false)
	for step in 2:
		slow.advance_visual(.1)
		fast.advance_visual(.1)
	check_between(slow_player.current_animation_position,.099,.101,"half walking speed advances half a cycle second")
	check_between(fast_player.current_animation_position,.199,.201,"normal walking rate follows authored gait")

func _drive(actor: ExplorePedestrian, move: Vector2, sprint: bool, jump: bool, ticks: int) -> void:
	var driver := MotionDriver.new()
	driver.actor = actor
	driver.frame.move = move
	driver.frame.sprint = sprint
	driver.frame.jump = jump
	driver.total = ticks
	root.add_child(driver)
	await driver.completed
	await process_frame
	driver.free()

# A missing set_motion/advance_visual call in actual locomotion must fail this
# integration, even if the standalone visual API tests still pass.
func test_native_locomotion_drives_clips_and_stop_input() -> void:
	var fixture := Fixture.attach(self,flat_city())
	actors.append(fixture)
	var pedestrian := ExplorePedestrian.new()
	fixture.add_child(pedestrian)
	pedestrian.bind(fixture.get_node("traversal"))
	pedestrian.position = Vector3(22.5,4*CityGeometry3D.HEIGHT,22.5)
	var player := _player(pedestrian)
	if player==null: return
	await physics_frame
	var start := pedestrian.position
	await _drive(pedestrian,Vector2(0,-1),false,false,20)
	check(pedestrian.position.z<start.z-.01,"actual body walks through physical world")
	check_eq(player.current_animation,"walk","actual walking updates authored animation")
	check(player.current_animation_position>0.0,"actual locomotion advances animation")
	await _drive(pedestrian,Vector2(0,-1),true,false,20)
	check_eq(player.current_animation,"run","actual sprint updates authored animation")
	pedestrian.stop_input()
	check_eq(player.current_animation,"idle","native stop clears leg locomotion immediately")
	var cursor := player.current_animation_position
	for frame in 4: await process_frame
	check_eq(player.current_animation_position,cursor,"stopped/suspended body does not animate autonomously")
	await _drive(pedestrian,Vector2.ZERO,false,true,6)
	check(not pedestrian.landed(),"native jump lifts physical body")
	check_eq(player.current_animation,"jump","native airborne state selects jump")

func test_wheel_roll_uses_signed_distance_and_steering_pivot() -> void:
	var actor := _actor("car")
	var wheel := actor.find_child("WheelFrontLeft",true,false) as Node3D
	var rear := actor.find_child("WheelRearLeft",true,false) as Node3D
	check(wheel!=null and rear!=null,"imported wheel pivots exist")
	if wheel==null or rear==null: return
	var spin := wheel.get_node_or_null("Spin") as Node3D
	check(spin!=null,"wheel roll is below steering pivot")
	if spin==null: return
	var tire := _mesh_bounds(spin)
	check_between(tire.size.y,.479,.481,"authored tire diameter is .48 metres")
	check_between(tire.size.z,.479,.481,"authored roll radius agrees with distance-based motion")
	actor.set_motion(.15,1.0,false)
	actor.advance_visual(.1)
	# Travel .015 tile equals a .24m tire radius, so forward is -1 radian
	# around +X for a vehicle whose forward axis is -Z.
	check_between(spin.rotation.x,-1.001,-.999,"forward roll matches physical tire radius and direction")
	check(wheel.rotation.y>.1,"front wheel steers about vertical Y")
	check(absf(wheel.rotation.x)<.0001 and absf(wheel.rotation.z)<.0001,"steering does not tilt wheel axle")
	check(rear.rotation.is_zero_approx(),"rear pivot does not steer")
	_check_bounds(actor,SIZES[1],"car during forward roll and steering")
	actor.set_motion(-.15,0.0,false)
	actor.advance_visual(.1)
	check(absf(spin.rotation.x)<.001,"equal reverse travel unwinds roll")
	actor.set_motion(0.0,0.0,false)
	var stopped := spin.transform
	for step in 30: actor.advance_visual(1.0/60.0)
	check_eq(spin.transform,stopped,"stopped car has no tire crawl")
	_check_bounds(actor,SIZES[1],"car steered/spun")

func test_helicopter_rotor_sweep_stays_inside_profile() -> void:
	var actor := _actor("helicopter")
	var main := actor.find_child("MainRotor",true,false) as Node3D
	var tail := actor.find_child("TailRotor",true,false) as Node3D
	check(main!=null and tail!=null,"imported rotor pivots exist")
	if main==null or tail==null: return
	for degrees in range(0,360,5):
		main.rotation.y = deg_to_rad(float(degrees))
		tail.rotation.x = deg_to_rad(float(degrees))
		_check_bounds(actor,SIZES[2],"rotor phase %d" % degrees)
	var before := main.transform
	for frame in 4: await process_frame
	check_eq(main.transform,before,"inactive aircraft has no autonomous rotor tick")
	actor.set_motion(0.0,0.0,true)
	actor.advance_visual(.1)
	check(main.transform!=before,"occupied session tick turns real rotor")
	check(_finite_pose(actor),"rotor pose remains finite")

func test_visual_extreme_inputs_remain_finite() -> void:
	for actor_name in SCENES:
		var actor := _actor(actor_name)
		for speed in [1000000.0,-1000000.0,NAN]:
			actor.set_motion(speed,speed,true)
			actor.advance_visual(speed)
		check(_finite_pose(actor),"%s rejects nonfinite motion/delta" % actor_name)

func _check_bounds(actor: Node3D, size: Vector3, label: String) -> void:
	var bounds := _mesh_bounds(actor)
	check(bounds.position.x>=-size.x*.5-.002 and bounds.end.x<=size.x*.5+.002,label+" fits profile X: "+str(bounds))
	check(bounds.position.z>=-size.z*.5-.002 and bounds.end.z<=size.z*.5+.002,label+" fits profile Z: "+str(bounds))
	check(bounds.position.y>=-.002 and bounds.end.y<=size.y+.002,label+" has feet root and fits height: "+str(bounds))

func _mesh_bounds(actor: Node3D) -> AABB:
	var first := true
	var bounds := AABB()
	for mesh_node: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		var relative := actor.global_transform.affine_inverse()*mesh_node.global_transform
		for surface in mesh_node.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := relative*vertex
				if first:
					bounds = AABB(point,Vector3.ZERO)
					first = false
				else: bounds = bounds.expand(point)
	return bounds

func _no_physics(actor: Node) -> bool:
	if actor is CollisionObject3D or actor is CollisionShape3D: return false
	for child in actor.get_children():
		if not _no_physics(child): return false
	return true

func _finite_pose(actor: Node) -> bool:
	if actor is Node3D and not actor.transform.is_finite(): return false
	for child in actor.get_children():
		if not _finite_pose(child): return false
	return true
