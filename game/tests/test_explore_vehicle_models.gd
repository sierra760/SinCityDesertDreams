# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const Catalog := preload("res://scripts/traffic/city_traffic_catalog.gd")

func test_all_vehicle_exports_fit_original_catalog_envelopes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.ASSET_ROOT+"catalog.json"))
	for kind: StringName in Catalog.KINDS:
		var entry: Dictionary = manifest.models[String(kind)]
		check(entry.has("tiers"),String(kind)+" has three measured tiers")
		check(entry.has("detail_path"),String(kind)+" has articulated detail export")
		if not entry.has("tiers"): continue
		for suffix: String in ["","_far","_detail"]:
			var path := Catalog.ASSET_ROOT+String(kind)+suffix+".glb"
			check(ResourceLoader.exists(path),path)
			if not ResourceLoader.exists(path): continue
			var instance: Node3D = (load(path) as PackedScene).instantiate()
			var measured := _measure(instance)
			var bounds: AABB = measured.bounds
			var size := Catalog.dimensions(kind)*16.0
			check(bounds.size.x<=size.x+.00001 and bounds.size.y<=size.y+.00001 and bounds.size.z<=size.z+.00001,String(kind)+suffix+" fits retained physical size")
			if kind not in [&"ship",&"sailboat"]: check(absf(bounds.position.y)<.00001,String(kind)+suffix+" tire/skid contact")
			else: check(bounds.position.y<0 and bounds.end.y>0,"waterline crosses hull")
			var tier: String = "detailed" if suffix=="_detail" else "far" if suffix=="_far" else "middle"
			var contact_parts: Array = entry.tiers[tier].contact_parts
			var expected := 0 if kind in [&"ship",&"sailboat"] else 2 if kind==&"helicopter" else 3 if kind==&"plane" else 6 if kind in [&"truck",&"fire_engine",&"military",&"train",&"subway"] else 4
			check_eq(contact_parts.size(),expected,"every tire/skid survives tier export")
			for part: Dictionary in contact_parts:
				var lo: Array = part.bounds_source_m[0]
				var hi: Array = part.bounds_source_m[1]
				var region := AABB(Vector3(lo[0],lo[2],-hi[1]),Vector3(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1])).grow(.00001)
				var lowest := INF
				var found := 0
				for point: Vector3 in measured.points:
					if region.has_point(point):
						lowest=minf(lowest,point.y)
						found+=1
				check(found>=8 and absf(lowest)<.00001,"actual tire/skid contact: "+String(kind)+suffix+" "+part.node)
			for sample: Array in entry.tiers[tier].motion_bounds_source_m:
				check(float(sample[0][0])>=-size.x*.5-.00001 and float(sample[1][0])<=size.x*.5+.00001,"steered/rotating width stays in physical envelope")
				check(float(sample[0][1])>=-size.z*.5-.00001 and float(sample[1][1])<=size.z*.5+.00001,"steered/rotating length stays in physical envelope")
			check_eq(measured.triangles,int(entry.tiers[tier].triangles),"actual imported triangles")
			check_eq(measured.materials,int(entry.tiers[tier].materials),"actual imported material count")
			check(instance.find_children("*","CollisionObject3D",true,false).is_empty(),"visual has no physics")
			instance.free()

func test_detailed_wheels_and_rotors_follow_manual_motion_metadata() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.ASSET_ROOT+"catalog.json"))
	for kind: StringName in Catalog.KINDS:
		var entry: Dictionary = manifest.models[String(kind)]
		if not entry.has("detail_path"): continue
		var visual := ExploreActorVisual.new()
		var imported: Node3D = (load(entry.detail_path) as PackedScene).instantiate()
		imported.scale=Vector3.ONE/16.0
		visual.add_child(imported)
		visual.configure_animation(entry.animation)
		visual.set_motion(.05,1.0,false)
		visual.advance_visual(.1)
		for wheel: Dictionary in entry.animation.get("wheels",[]):
			var pivot := visual.find_child(wheel.node,true,false) as Node3D
			check(pivot!=null,"named wheel pivot "+wheel.node)
			if pivot==null: continue
			var spin := visual._wheel_spin(pivot)
			check(spin!=null,"separate steering and spin pivots")
			if spin==null: continue
			check(absf(spin.rotation.x-(-.005*16.0/float(wheel.radius_m)))<.00001,"wheel radius controls rolling distance")
			if wheel.steer: check(pivot.rotation.y>0.0,"front axle steering")
		for rotor: Dictionary in entry.animation.get("rotors",[]):
			var part := visual.find_child(rotor.node,true,false) as Node3D
			check(part!=null,"named rotor exists")
			if part!=null:
				var axis: int = {"X":0,"Y":1,"Z":2}[rotor.axis]
				check(absf(part.rotation[axis]-wrapf(.1*float(rotor.radians_per_second),-PI,PI))<.00001,"rotor correct converted axis")
		visual.set_motion(-.05,0,false)
		visual.advance_visual(.1)
		for phase: float in visual.debug_state().wheel_phases.values(): check(absf(phase)<.00001,"reverse unwinds each radius")
		visual.free()

func _measure(instance: Node3D) -> Dictionary:
	var points: Array[Vector3] = []
	var total := 0
	var materials := {}
	for mesh_node: MeshInstance3D in instance.find_children("*","MeshInstance3D",true,false):
		var transform := mesh_node.transform
		var parent := mesh_node.get_parent()
		while parent!=null and parent!=instance:
			if parent is Node3D: transform=(parent as Node3D).transform*transform
			parent=parent.get_parent()
		for surface: int in mesh_node.mesh.get_surface_count():
			materials[mesh_node.mesh.surface_get_material(surface)]=true
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total+=indices.size()/3 if not indices.is_empty() else vertices.size()/3
			for vertex in vertices: points.append(transform*vertex)
	var bounds := AABB(points[0],Vector3.ZERO)
	for point in points: bounds=bounds.expand(point)
	return {"bounds":bounds,"triangles":total,"materials":materials.size(),"points":points}

func test_factory_loads_detail_with_one_scale_and_missing_detail_falls_back() -> void:
	for kind: StringName in Catalog.KINDS:
		var actor := TrafficActorVisual.new()
		actor.configure(kind,0)
		var imported := actor.get_node_or_null("DetailedModel") as Node3D
		check(imported!=null,"factory uses detailed catalog resource: "+String(kind))
		if imported!=null: check(imported.scale.is_equal_approx(Vector3.ONE/16.0),"one meter-to-tile conversion")
		actor.free()
	for invalid: Variant in [null,[],{"detail_path":12},{"detail_path":"res://assets/desert-dreams-traffic/missing_detail.glb"},{"detail_path":"res://assets/desert-dreams-traffic/car_detail.glb","animation":{"wheels":12}}]:
		var actor := TrafficActorVisual.new()
		check(not actor._try_detail(invalid),"invalid detail is refused without resource error")
		check_eq(actor.get_child_count(),0,"invalid detail leaves fallback available")
		actor.free()
	var unknown := TrafficActorVisual.new()
	unknown.configure(&"unknown",0)
	check(unknown.get_node_or_null("CatalogModel")!=null,"absent detailed entry preserves middle fallback")
	unknown.free()

func test_imported_cruiser_rolls_every_wheel_and_reverse_unwinds() -> void:
	var actor: ExploreActorVisual = (load("res://assets/desert-dreams-exploration/car.tscn") as PackedScene).instantiate()
	root.add_child(actor)
	actor.set_motion(.015,.75,false)
	actor.advance_visual(.1)
	for name in ["WheelFrontLeft","WheelFrontRight","WheelRearLeft","WheelRearRight"]:
		var wheel := actor.find_child(name,true,false) as Node3D
		var spin := actor._wheel_spin(wheel)
		check(spin!=null,"all four imported cruiser spin pivots resolve")
		if spin!=null: check(absf(spin.rotation.x+.1)<.00001,"each cruiser tire rolls exact signed distance")
		if name.begins_with("WheelFront"): check(wheel.rotation.y>0,"front cruiser wheel steers")
		else: check(wheel.rotation.is_zero_approx(),"rear cruiser axle stays fixed")
	actor.set_motion(-.015,0,false)
	actor.advance_visual(.1)
	for name in ["WheelFrontLeft","WheelFrontRight","WheelRearLeft","WheelRearRight"]:
		var spin := actor._wheel_spin(actor.find_child(name,true,false) as Node3D)
		if spin!=null: check(absf(spin.rotation.x)<.00001,"reverse unwinds every cruiser wheel")
	actor.free()

func test_spin_suffix_resolution_is_local_unambiguous_and_radius_specific() -> void:
	var actor := ExploreActorVisual.new()
	for index in 2:
		var wheel := Node3D.new()
		wheel.name="Wheel%d"%index
		actor.add_child(wheel)
		var spin := Node3D.new()
		spin.name="Spin2" if index==0 else "Spin_12"
		wheel.add_child(spin)
	actor.configure_animation({"wheels":[{"node":"Wheel0","radius_m":.2,"axis":"X","steer":true},{"node":"Wheel1","radius_m":.4,"axis":"X","steer":false}]})
	actor.set_motion(.025,1,false)
	actor.advance_visual(.1)
	check(absf(actor.debug_state().wheel_phases.Wheel0+.2)<.00001,"small radius rolls twice as fast")
	check(absf(actor.debug_state().wheel_phases.Wheel1+.1)<.00001,"large radius rolls by its own radius")
	actor.set_motion(-.025,0,false)
	actor.advance_visual(.1)
	for phase: float in actor.debug_state().wheel_phases.values():check(absf(phase)<.00001,"reverse independently unwinds radii")
	var wheel := Node3D.new()
	actor.add_child(wheel)
	var decoration := Node3D.new();decoration.name="SpinDecoration";wheel.add_child(decoration)
	var nested := Node3D.new();nested.name="Spin";decoration.add_child(nested)
	check(actor._wheel_spin(wheel)==null,"no decorative or recursive spin match")
	var first := Node3D.new();first.name="Spin.002";wheel.add_child(first)
	check(actor._wheel_spin(wheel)==first,"numeric dot suffix accepted")
	var second := Node3D.new();second.name="Spin3";wheel.add_child(second)
	check(actor._wheel_spin(wheel)==null,"ambiguous numeric children are refused")
	var exact := Node3D.new();exact.name="Spin";wheel.add_child(exact)
	check(actor._wheel_spin(wheel)==exact,"exact local pivot wins")
	actor.free()

func test_malformed_top_level_radius_refuses_detail_without_partial_nodes() -> void:
	for bad_radius: Variant in [{},[],".24",true,null,0,-.2,INF,-INF,NAN]:
		for overridden: bool in [false,true]:
			var wheels: Array = [{"node":"WheelFrontLeft","radius_m":.2,"axis":"X","steer":true}] if overridden else []
			var actor := TrafficActorVisual.new()
			var entry := {"detail_path":"res://assets/desert-dreams-traffic/car_detail.glb","animation":{"wheel_radius_m":bad_radius,"wheels":wheels}}
			check(not actor._try_detail(entry),"invalid top-level radius refused even with empty/overridden wheels")
			check_eq(actor.get_child_count(),0,"radius rejection leaves no partial imported nodes")
			actor.free()
