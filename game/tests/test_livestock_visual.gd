# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const VISUAL := "res://scripts/view/livestock_visual.gd"
func rig(node:Node)->Skeleton3D:
	if node is Skeleton3D:return node
	for child:Node in node.get_children():
		var found:=rig(child)
		if found!=null:return found
	return null
func test_independent_imported_poses_preserve_rests_and_root() -> void:
	check(ResourceLoader.exists(VISUAL),"missing livestock visual")
	if not ResourceLoader.exists(VISUAL):return
	var catalog:=AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	for species:StringName in [&"beef_cattle",&"dairy_cattle",&"sheep"]:
		var a:Node3D=load(VISUAL).new();var b:Node3D=load(VISUAL).new()
		a.configure(species,0,catalog);b.configure(species,1,catalog);root.add_child(a);root.add_child(b)
		var source_before:=resource_snapshot(a)
		var ar:=rig(a);var br:=rig(b);var rests:Array=[];var baseline:Array=[]
		for i:int in ar.get_bone_count():rests.append(ar.get_bone_rest(i));baseline.append(ar.get_bone_pose(i))
		var state:Dictionary={"position":Vector3(1,.14,2),"heading":.6,"speed":1.0,"activity":"walk","gait_phase":.7,"species":species}
		a.apply_state(state,.05)
		check_eq(a.position,state["position"]);check(is_equal_approx(a.rotation.y,state["heading"]))
		check_ne(ar.get_bone_pose_rotation(ar.find_bone("FrontLeftUpper")),br.get_bone_pose_rotation(br.find_bone("FrontLeftUpper")),"independent gait")
		for i:int in ar.get_bone_count():
			check_eq(ar.get_bone_rest(i),rests[i]);check_eq(br.get_bone_pose(i),baseline[i],"other instance untouched")
		for name:String in ["Root","Body"]:check_eq(ar.get_bone_pose(ar.find_bone(name)),baseline[ar.find_bone(name)])
		var fresh:Node3D=catalog.make_animal(species);var fr:=rig(fresh)
		for i:int in fr.get_bone_count():check_eq(fr.get_bone_pose(i),baseline[i],"source scene unchanged")
		check_eq(resource_snapshot(fresh),source_before,"shared mesh skin and material bytes unchanged")
		fresh.free();a.free();b.free()
func test_invalid_visual_state_and_delta_are_noops() -> void:
	check(ResourceLoader.exists(VISUAL),"missing livestock visual")
	if not ResourceLoader.exists(VISUAL):return
	var c:=AgricultureAssetCatalog.new();check_eq(c.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	var a:Node3D=load(VISUAL).new();a.configure(&"sheep",0,c);root.add_child(a)
	var state:Dictionary={"position":Vector3.ZERO,"heading":0.0,"speed":0.0,"activity":"graze","gait_phase":1.0}
	for delta:float in [NAN,INF,-1.0]:a.apply_state(state,delta);check_eq(a.transform,Transform3D.IDENTITY)
	state["position"]=Vector3.INF;a.apply_state(state,.05);check_eq(a.transform,Transform3D.IDENTITY)
	a.free()
func meshes(node:Node)->Array[MeshInstance3D]:
	var result:Array[MeshInstance3D]=[]
	if node is MeshInstance3D:result.append(node)
	for child:Node in node.get_children():result.append_array(meshes(child))
	return result
func lowest_skinned(a:Node3D)->float:
	var skeleton:=rig(a);var low:=INF
	skeleton.force_update_all_bone_transforms()
	for mesh:MeshInstance3D in meshes(a):
		if mesh.skin==null:continue
		for surface:int in mesh.mesh.get_surface_count():
			var arrays:=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var stride:int=weights.size()/vertices.size()
			for v:int in vertices.size():
				var point:=Vector3.ZERO
				for w:int in stride:
					var weight:float=weights[v*stride+w]
					if weight<=0:continue
					var bind:int=bones[v*stride+w]
					var bone:int=skeleton.find_bone(mesh.skin.get_bind_name(bind))
					if bone<0:bone=mesh.skin.get_bind_bone(bind)
					point+=skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind)*vertices[v]*weight
				low=minf(low,(a.global_transform.affine_inverse()*skeleton.global_transform*point).y)
	return low
func test_walk_graze_and_drink_skin_stays_above_ground() -> void:
	check(ResourceLoader.exists(VISUAL),"missing livestock visual")
	if not ResourceLoader.exists(VISUAL):return
	var catalog:=AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	for species:StringName in [&"beef_cattle",&"dairy_cattle",&"sheep"]:
		var a:Node3D=load(VISUAL).new();a.configure(species,2,catalog);root.add_child(a)
		for activity:String in ["walk","graze","drink","idle"]:
			for i:int in 24:
				a.apply_state({"position":Vector3.ZERO,"heading":0.0,"speed":1.0 if activity=="walk" else 0.0,"activity":activity,"gait_phase":TAU*float(i)/24.0},.05)
				check_ge(lowest_skinned(a),-.002,"actual skinned vertices below ground: %s %s %d"%[species,activity,i])
		a.free()

func resource_snapshot(a:Node3D)->String:
	var values:Array=[]
	for mesh:MeshInstance3D in meshes(a):
		for surface:int in mesh.mesh.get_surface_count():
			values.append(mesh.mesh.surface_get_arrays(surface))
			var material:Material=mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D:values.append([material.albedo_color,material.roughness,material.metallic])
		if mesh.skin!=null:
			for bind:int in mesh.skin.get_bind_count():values.append([mesh.skin.get_bind_name(bind),mesh.skin.get_bind_pose(bind)])
	return var_to_bytes(values).hex_encode().sha256_text()

func test_secondary_poses_are_continuous_across_gait_wrap() -> void:
	var catalog:=AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	var a:Node3D=load(VISUAL).new();a.configure(&"beef_cattle",1,catalog);root.add_child(a)
	var skeleton:=rig(a)
	var state:Dictionary={"position":Vector3.ZERO,"heading":0.0,"speed":1.2,"activity":"walk","gait_phase":TAU-.0001}
	a.apply_state(state,.0001)
	var before:Dictionary={}
	for bone:String in ["Neck","Head","Tail"]:before[bone]=skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
	state["gait_phase"]=.0001;a.apply_state(state,.0001)
	for bone:String in before:
		var after:=skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
		check_lt((before[bone] as Quaternion).angle_to(after),.001,"secondary pose snaps across gait wrap: "+bone)
	a.free()

func test_repeated_frozen_state_and_invalid_delta_preserve_every_pose() -> void:
	var catalog:=AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	var a:Node3D=load(VISUAL).new();a.configure(&"sheep",1,catalog);root.add_child(a)
	var skeleton:=rig(a)
	var state:Dictionary={"position":Vector3(1,.14,2),"heading":.6,"speed":1.2,"activity":"walk","gait_phase":TAU-.0001}
	a.apply_state(state,.05)
	var before:Array=[]
	for i:int in skeleton.get_bone_count():before.append(skeleton.get_bone_pose(i))
	var transform_before:=a.transform
	for delta:float in [0.0,.05,.5,1.0,NAN,INF,-INF,-.05]:
		a.apply_state(state,delta)
		check_eq(a.transform,transform_before)
		for i:int in before.size():check_eq(skeleton.get_bone_pose(i),before[i],"frozen input cannot advance secondary poses")
	for field:String in ["heading","speed","gait_phase"]:
		var invalid:=state.duplicate(true);invalid[field]=NAN;a.apply_state(invalid,.05)
		for i:int in before.size():check_eq(skeleton.get_bone_pose(i),before[i],"invalid state cannot inject bad pose")
	a.free()


func test_generated_motion_drives_actual_skeleton_without_changing_rest_or_ground() -> void:
	var fixture := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
	var catalog := AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	for key: StringName in [&"cattle_range",&"sheep_pasture"]:
		var record := fixture.record(1,fixture.expanded(fixture.ring()),key,&"active")
		var profile: Dictionary = AgriculturalParcelGeometry.plan(record).profile
		var motion := LivestockMotion.new();motion.configure(profile,12)
		check_eq(motion.states().size(),12)
		var animal := LivestockVisual.new();animal.configure(profile.species,12,catalog);root.add_child(animal)
		var skeleton := rig(animal);check(skeleton!=null)
		var rests := [];var initial := []
		for i in skeleton.get_bone_count(): rests.append(skeleton.get_bone_rest(i));initial.append(skeleton.get_bone_pose(i))
		var changed := false
		for tick in 600:
			motion.advance(.05);var state: Dictionary = motion.states()[0]
			animal.apply_state(state,0)
			check_eq(animal.position,state.position)
			for i in skeleton.get_bone_count():
				check_eq(skeleton.get_bone_rest(i),rests[i])
				changed = changed or skeleton.get_bone_pose(i)!=initial[i]
			if tick%100==0: check_ge(lowest_skinned(animal),-.002,"generated ground offset does not sink the skin")
		check(changed,"generated motion reaches actual rig poses")
		animal.free()
