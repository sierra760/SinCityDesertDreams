# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

class TubeFixture extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

func test_riding_view_turns_with_the_cabin_and_keeps_mouse_orbit() -> void:
	var traveler := ExplorePedestrian.new()
	var rig := CityExploreCamera3D.new()
	root.add_child(traveler)
	root.add_child(rig)
	rig.configure_target(traveler,0)
	rig.yaw=.3
	rig.set_cabin(ExploreTransitTrain.CABIN,Transform3D.IDENTITY,true)
	var turn := Transform3D(Basis(Vector3.UP,PI*.5),Vector3(2,1,2))
	rig.set_cabin(ExploreTransitTrain.CABIN,turn,true)
	check(absf(wrapf(rig.yaw-(.3+PI*.5),-PI,PI))<.001,"rider's local heading is carried through a train turn")
	rig.orbit(Vector2(100,0),1,false)
	var orbit_yaw := rig.yaw
	rig.set_cabin(ExploreTransitTrain.CABIN,turn,true)
	check_eq(rig.yaw,orbit_yaw,"same pose does not apply carry twice or erase orbit")
	rig.set_cabin(AABB(),Transform3D.IDENTITY,false)
	check_eq(rig.yaw,orbit_yaw,"alighting retains the user's view direction")
	rig.free()
	traveler.free()
	await physics_frame

func test_track_palette_keeps_the_surface_railway_color_space() -> void:
	var world := TubeFixture.new()
	root.add_child(world)
	world.network=ExploreTransitNetwork.new()
	var key := Vector3i(10,1,10)
	var next := Vector3i(10,1,11)
	world.network.nodes[key]={"point":Vector3(10.5,2,10.5),"links":[next]}
	world.network.nodes[next]={"point":Vector3(10.5,2,11.5),"links":[key]}
	world.build({"nodes":[key],"stops":[]})
	var found := false
	for child: Node in world.get_children():
		if not child is MeshInstance3D: continue
		for surface: int in child.mesh.get_surface_count():
			var material: Material=child.get_active_material(surface)
			if material.resource_name=="transit_textured_track":
				found=true
				check(material is ShaderMaterial and material.shader.code.contains("linear_color(base)"),"ballast/timber/steel retain the surface railway sRGB palette")
				var uv: PackedVector2Array=child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
				check(not uv.is_empty(),"track has metre-scaled texture coordinates")
	check(found,"running track material found")
	world.free()
	await physics_frame

func test_train_doors_use_the_authored_window_apertures() -> void:
	var train := ExploreTransitTrain.new()
	root.add_child(train)
	var authored := 0
	for door: Node in train._door_bodies:
		for child: Node in door.get_children():
			if child.has_meta("authored_passenger_door"): authored+=1
	check_eq(authored,2,"both physical sliding doors use the editable windowed source")
	train.free()
	await physics_frame

func test_minor_wayfinding_uses_biorhyme_on_a_solid_sign() -> void:
	var station := Node3D.new()
	root.add_child(station)
	for words: String in ["TICKETS","BOARD AT OPEN DOORS","EXIT · ELEVATOR","STREET","PLATFORM","LIFT","← ELEVATOR","ELEVATOR →"]:
		var label := ExploreStationInterior.add_plaque(station,Transform3D.IDENTITY,words)
		check(label.mesh.font.get_font_name().begins_with("BioRhyme"),words+" uses the requested font")
		var displayed: String=label.mesh.text
		for index: int in displayed.length():
			check(label.mesh.font.has_char(displayed.unicode_at(index)),"every displayed glyph belongs to BioRhyme")
		if words.contains("←") or words.contains("→"):
			check(station.has_node("TransitDirectionArrow"),"wayfinding arrow is drawn on its sign without a fallback font")
		check(label.has_meta("sign_backing"),words+" is mounted on a solid sign")
		if label.has_meta("sign_backing"):
			var backing: Node3D=label.get_meta("sign_backing").get_ref()
			check(is_instance_valid(backing) and backing is MeshInstance3D and backing.mesh is BoxMesh,words+" has a real plate")
		station.free()
		station=Node3D.new()
		root.add_child(station)
	station.free()
	await physics_frame

func test_tunnel_walls_are_textured_and_lit_on_both_sides() -> void:
	var world := ExploreTransitWorld3D.new()
	root.add_child(world)
	check(world.has_method("_tunnel_shell"),"subway has a finished enclosed tunnel shell")
	if world.has_method("_tunnel_shell"):
		world._tunnel_shell(Transform3D.IDENTITY,1.0)
		var lights := [false,false]
		var textured := false
		for child: Node in world.get_children():
			if not child is MeshInstance3D: continue
			for surface: int in child.mesh.get_surface_count():
				var material: Material=child.get_active_material(surface)
				if material is ShaderMaterial: textured=true
				var arrays: Array=child.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var paint: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
				for i: int in points.size():
					if not paint.is_empty() and paint[i].a>.7 and points[i].y>.19 and absf(points[i].x)>.28:
						lights[0 if points[i].x<0 else 1]=true
		check(textured,"tunnel uses the metre-scaled finish shader")
		check(lights[0] and lights[1],"continuous warm fixtures run along both tunnel walls")
		for side: int in [-1,1]:
			var hit := false
			for i: int in range(0,world._physical.size(),3):
				if Geometry3D.ray_intersects_triangle(Vector3(0,.14,0),Vector3(side,0,0),world._physical[i],world._physical[i+1],world._physical[i+2])!=null: hit=true
			check(hit,"finished tunnel retains a solid side wall")
	world.free()
	await physics_frame

func test_underground_camera_classification_follows_the_tube_at_any_grade() -> void:
	var world := ExploreTransitWorld3D.new()
	root.add_child(world)
	world.active_stations=[{"subway":true,"surface":1.0}]
	world.supports=[{"at":Transform3D(Basis.IDENTITY,Vector3(10,5,10)),"bounds":AABB(Vector3(-.30,-.073,-.50),Vector3(.60,.30,1.0)),"floor":-.015,"track_bed":true}]
	check(world.indoors(Vector3(10,5.025,10)),"higher tunnel remains indoors regardless of station surface height")
	check(not world.indoors(Vector3(11,5.025,10)),"classification does not extend beyond the finite tube")
	world.free()
	await physics_frame

func test_riding_camera_stays_within_the_rotating_cabin_during_orbit() -> void:
	var traveler := ExplorePedestrian.new()
	var rig := CityExploreCamera3D.new()
	root.add_child(traveler)
	root.add_child(rig)
	rig.configure_target(traveler,0)
	for frame: int in 48:
		var at := Transform3D(Basis(Vector3.UP,float(frame)*.07)*Basis(Vector3.RIGHT,.14),Vector3(10+frame*.03,2+frame*.01,10))
		traveler.global_transform=at*Transform3D(Basis.IDENTITY,Vector3(.10,.027,.27))
		rig.set_cabin(ExploreTransitTrain.CABIN,at,true)
		rig.orbit(Vector2(97,frame%3-1),1.0,false)
		rig.update_follow(1.0/60.0)
		var local: Vector3=at.affine_inverse()*rig.camera.global_position
		check(ExploreTransitTrain.CABIN.grow(-.012).has_point(local),"ride camera remains inside the moving cabin at orbit "+str(frame))
		check(rig.cabin_first_person,"riding retains the interior eye view")
	rig.set_cabin(AABB(),Transform3D.IDENTITY,false)
	rig.set_interior(false)
	rig.update_follow(.1)
	check(traveler._visual.visible,"leaving the cabin restores outdoor avatar framing")
	rig.free()
	traveler.free()
	await physics_frame

func test_closed_track_approach_has_floor_all_the_way_to_its_end_wall() -> void:
	var world := TubeFixture.new()
	root.add_child(world)
	world.network=ExploreTransitNetwork.new()
	var key := Vector3i(10,1,10)
	var next := Vector3i(10,1,11)
	var origin := Vector3(10.5,2,10.5)
	world.network.nodes[key]={"point":origin,"links":[next]}
	world.network.nodes[next]={"point":origin+Vector3.BACK,"links":[key]}
	world.build({"nodes":[key],"stops":[]})
	var visible := PackedVector3Array()
	for child: Node in world.get_children():
		if child is MeshInstance3D:
			for point: Vector3 in child.mesh.get_faces(): visible.append(child.transform*point)
	for distance: float in [.51,.55,.59]:
		var ray := origin+Vector3(0,.027,distance)
		for faces: PackedVector3Array in [visible,world._physical]:
			var hit := false
			for i: int in range(0,faces.size(),3):
				var point: Variant=Geometry3D.ray_intersects_triangle(ray,Vector3.DOWN,faces[i],faces[i+1],faces[i+2])
				if point!=null and ray.distance_to(point)<.10: hit=true
			check(hit,"closed approach has rendered and physical ground to its end wall")
		check(not world.support_for(ray).is_empty(),"support reaches the same end as the enclosed approach")
	world.free()
	await physics_frame
