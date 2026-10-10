# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const ASSETS := "res://assets/desert-dreams-traffic/"
func test_crowd_roster_ground_contact_and_clips() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS+"catalog.json"))
	for index: int in 16:
		var stem := "pedestrian_%02d" % index
		var entry: Dictionary = catalog.models[stem]
		check(entry.has("detail_path"),stem+" has detailed rig")
		if not entry.has("detail_path"): continue
		var node: Node3D = load(entry.detail_path).instantiate()
		root.add_child(node)
		var skeletons := node.find_children("*","Skeleton3D",true,false)
		check_eq(skeletons.size(),1,stem+" one skeleton")
		if not skeletons.is_empty(): check_eq(skeletons[0].get_bone_count(),18)
		var players := node.find_children("*","AnimationPlayer",true,false)
		check_eq(players.size(),1)
		if not players.is_empty():
			check_eq(players[0].get_animation("wave").length,float(entry.animation.wave_duration_s),"owner gesture duration matches imported wave")
			for clip: String in ["idle","walk","run","jump","wave"]: check(players[0].has_animation(clip),stem+" "+clip)
		check(node.find_children("*","CollisionObject3D",true,false).is_empty(),"art does not embed physics")
		node.free()
func test_player_wave_cancels_for_movement_and_jump() -> void:
	for file: String in ["pedestrian","pedestrian_woman"]:
		var visual := ExploreActorVisual.new()
		visual.add_child(load("res://assets/desert-dreams-exploration/"+file+".glb").instantiate())
		root.add_child(visual)
		check(visual.play_gesture(&"wave"),"player has wave")
		visual.set_motion(.09,0,false)
		check_eq(visual.debug_state().clip,"walk","walking cancels wave")
		visual.set_motion(0,0,false)
		check(visual.play_gesture(&"wave"))
		visual.set_motion(0,0,true)
		check_eq(visual.debug_state().clip,"jump","jump cancels wave")
		visual.free()

func test_imported_tier_budgets_weights_and_contact() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS+"catalog.json"))
	for index: int in 16:
		var stem := "pedestrian_%02d" % index
		var entry: Dictionary = catalog.models[stem]
		if not entry.has("tiers"): continue
		for tier: String in ["detailed","middle","far"]:
			var suffix := "_detail" if tier=="detailed" else "_far" if tier=="far" else ""
			var node: Node3D = load(ASSETS+stem+suffix+".glb").instantiate()
			root.add_child(node)
			var triangles := 0
			var materials := {}
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
				for surface: int in mesh.mesh.get_surface_count():
					materials[mesh.mesh.surface_get_material(surface)]=true
					var arrays := mesh.mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					triangles+=indices.size()/3 if not indices.is_empty() else vertices.size()/3
					for vertex: Vector3 in vertices:
						var point := mesh.global_transform*vertex
						low=low.min(point);high=high.max(point)
					if tier=="detailed":
						var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
						var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
						check_eq(weights.size(),vertices.size()*4)
						check_eq(bones.size(),weights.size())
						var valid := true
						for v: int in vertices.size():
							var total := 0.0
							for slot: int in 4:
								var w := weights[v*4+slot]
								valid=valid and is_finite(w) and w>=0 and (w==0 or (bones[v*4+slot]>=0 and bones[v*4+slot]<mesh.skin.get_bind_count()))
								total+=w
							valid=valid and absf(total-1)<.001 # Godot imports normalized weights as half floats.
						check(valid,"normalized valid imported influences "+stem)
			check_eq(triangles,int(entry.tiers[tier].triangles),"actual imported triangles")
			check(triangles<= (13000 if tier=="detailed" else 3500 if tier=="middle" else 1500))
			if tier=="middle": check(triangles<=int(entry.original_middle_triangles),"do not inflate original middle complexity")
			check(not entry.tiers[tier].accessory_connections.is_empty(),"every variant retains its accessory")
			for attachment: Dictionary in entry.tiers[tier].accessory_connections:
				check(float(attachment.bounds_gap_m)<=.005,"authored accessory reaches its named support")
			check_eq(materials.size(),int(entry.tiers[tier].materials))
			check(materials.size()<= (12 if tier=="detailed" else 6))
			check(low.y>=-.002 and high.y<=1.84,"unchanged actor rest height")
			check(low.x>=-.288001 and high.x<=.288001 and low.z>=-.288001 and high.z<=.288001,"unchanged actor rest width")
			if tier!="detailed":
				check(node.find_children("*","Skeleton3D",true,false).is_empty(),"static batch has no skeleton")
				check(absf(low.y)<.00001,"static soles contact zero")
			else:
				_check_posed_feet(node,stem)
			node.free()

func _check_posed_feet(node: Node3D, stem: String) -> void:
	var player: AnimationPlayer = node.find_children("*","AnimationPlayer",true,false)[0]
	var skeleton: Skeleton3D = node.find_children("*","Skeleton3D",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Cache actual imported sole vertices and every influence, not just the dominant bone.
	var soles: Array = []
	var binds: Array = []
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var offset := binds.size()
		for bind: int in mesh.skin.get_bind_count():
			binds.append([skeleton.find_bone(mesh.skin.get_bind_name(bind)),mesh.skin.get_bind_pose(bind)])
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for v: int in vertices.size():
				var is_sole := false
				for slot: int in 4:
					if weights[v*4+slot]>.9 and String(mesh.skin.get_bind_name(bones[v*4+slot])).ends_with("Foot"): is_sole=true
				if is_sole:
					var influences: Array = []
					for slot: int in 4:
						if weights[v*4+slot]>0: influences.append([offset+bones[v*4+slot],weights[v*4+slot]])
					soles.append([vertices[v],influences])
	for clip: String in ["idle","walk","run","jump","wave"]:
		player.play(clip)
		var worst := 0.0
		var worst_time := 0.0
		# 960 Hz includes authored 240 Hz keys, ordinary 60 Hz owner ticks,
		# four samples per authored interval, including half-cycle transition times.
		for sample: int in range(int(round(player.get_animation(clip).length*960))+1):
			var time := sample/960.0
			if clip=="jump" and time>7.0/24 and time<15.0/24: continue
			player.seek(time,true)
			skeleton.force_update_all_bone_transforms()
			var transforms: Array[Transform3D] = []
			for bind: Array in binds:
				transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bind[0])*bind[1])
			var low := INF
			for sole: Array in soles:
				var point := Vector3.ZERO
				for influence: Array in sole[1]: point+=(transforms[influence[0]]*sole[0])*influence[1]
				low=minf(low,point.y)
			if absf(low)>absf(worst):
				worst=low;worst_time=time
		check(absf(worst)<.003,"posed imported stance sole "+stem+" "+clip+" t="+str(worst_time)+" gap="+str(worst))
