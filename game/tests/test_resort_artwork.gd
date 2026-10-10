# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

func test_all_ten_sets_have_complete_distinct_illustrations() -> void:
	var seen := {}
	for key: StringName in ResortThemes.keys():
		for asset: String in ResortArtwork.ASSETS:
			var texture := ResortArtwork.texture(key,asset)
			check(texture != null,"%s %s loads" % [key,asset])
			if texture == null: continue
			check_ge(texture.get_width(),256,"small-screen and 3D resolution")
			if asset == "cabinet-reels":
				check_eq(texture.get_size(),Vector2(480,280),"complete three-reel face")
			else:
				check_eq(texture.get_width(),texture.get_height(),"square illustration")
			check(not seen.has(texture.resource_path),"each resort owns a separate illustration")
			seen[texture.resource_path] = true
		for symbol: String in CasinoParams.SLOT_SYMBOLS:
			check(ResortArtwork.symbol(key,symbol) != null,"all payout symbols illustrated")
		for rank: int in [11,12,13]:
			check(ResortArtwork.court(key,rank) != null,"all three court ranks illustrated")

func test_invalid_art_and_number_cards_have_no_court_portrait() -> void:
	check(ResortArtwork.texture(&"unknown","card-back") == null)
	check(ResortArtwork.texture(&"arcology_orbit","unknown") == null)
	for rank: int in range(1,11):
		check(ResortArtwork.court(&"arcology_orbit",rank) == null)

func test_floor_art_is_batched_on_the_interior_layer() -> void:
	for key: StringName in ResortThemes.keys():
		var world := ResortInteriorWorld3D.new()
		root.add_child(world)
		world.build(key,ResortThemes.building(key),Vector2i(20,20))
		var batch := world.find_child("ResortArtworkBatch",true,false) as MeshInstance3D
		check(batch != null,"floor has wall paintings and cabinet inserts")
		if batch != null:
			check_eq(batch.layers,ResortInteriorWorld3D.LAYER)
			check_eq(batch.mesh.get_surface_count(),5,"three paintings and two cabinet art materials")
			check_eq(batch.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var triangles := 0
			for index: int in batch.mesh.get_surface_count():
				var material := batch.mesh.surface_get_material(index) as StandardMaterial3D
				check(material != null and material.albedo_texture != null,"real imported bitmap on every surface")
				var arrays := batch.mesh.surface_get_arrays(index)
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
			check_eq(triangles,198,"all 48 cabinets dressed with full reels and header, plus three paintings")
		world.free()

func test_payouts_keep_transparent_backgrounds_and_subject_bounds() -> void:
	for key: StringName in ResortThemes.keys():
		for symbol: String in CasinoParams.SLOT_SYMBOLS:
			var raw := ResortArtwork.texture(key,"payout-"+symbol)
			var image := raw.get_image()
			for corner: Vector2i in [Vector2i.ZERO,Vector2i(image.get_width()-1,0),Vector2i(0,image.get_height()-1),Vector2i(image.get_width()-1,image.get_height()-1)]:
				check_eq(image.get_pixelv(corner).a,0.0,"payout corner remains transparent")
			var centered := ResortArtwork.payout(key,symbol) as AtlasTexture
			check(centered != null and centered.atlas == raw,"cutout retains original generated alpha")
			check(centered.region.has_area(),"cutout has visible subject bounds")

func test_centered_art_uses_valid_visible_regions() -> void:
	for key: StringName in ResortThemes.keys():
		for asset: String in ResortArtwork.ASSETS:
			var raw := ResortArtwork.texture(key,asset)
			var bounds := ResortArtwork.region(key,asset)
			check(bounds.has_area() and Rect2(Vector2.ZERO,raw.get_size()).encloses(bounds),"visible region stays inside source pixels")
		for rank: int in [11,12,13]:
			var portrait := ResortArtwork.court(key,rank) as AtlasTexture
			check(portrait != null and portrait.region.size.x < portrait.atlas.get_width(),"court portrait removes outer cell padding")

func test_comstock_trim_clears_the_resort_sign() -> void:
	var lettering_room := AABB(Vector3(-6.9,5.45,21.90),Vector3(13.8,1.5,.07))
	var intrusions := 0
	for row: Dictionary in ResortPropDresser.parts("hall_251").surfaces:
		if row.material != "resort_metal": continue
		var faces: PackedVector3Array = (row.mesh as Mesh).get_faces()
		for index: int in range(0,faces.size(),3):
			var at: Transform3D = row.transform
			var point := at*faces[index]
			var bounds := AABB(point,Vector3.ZERO)
			bounds = bounds.expand(at*faces[index+1]).expand(at*faces[index+2])
			if bounds.intersects(lettering_room): intrusions += 1
	check_eq(intrusions,0,"metal wall bands do not pass in front of sign lettering")

func test_court_portraits_have_transparent_outer_edges() -> void:
	for key: StringName in ResortThemes.keys():
		for asset: String in ["court-jack","court-queen","court-king"]:
			var image := ResortArtwork.texture(key,asset).get_image()
			for corner: Vector2i in [Vector2i.ZERO,Vector2i(image.get_width()-1,0),Vector2i(0,image.get_height()-1),Vector2i(image.get_width()-1,image.get_height()-1)]:
				# Generated alpha may carry one 8-bit quantization unit of noise.
				check(image.get_pixelv(corner).a <= 1.0/255.0+0.00001,"portrait has no paper rectangle or neighboring cell edge")

func test_velvet_ornament_clears_the_complete_framed_painting() -> void:
	var room := AABB(Vector3(-21.30,4.20,-14.30),Vector3(.36,4.72,4.60))
	var intrusions := 0
	for row: Dictionary in ResortPropDresser.parts("hall_258").surfaces:
		if row.material not in ["resort_carpet","resort_lamp"]: continue
		var faces: PackedVector3Array = (row.mesh as Mesh).get_faces()
		for index: int in range(0,faces.size(),3):
			var at: Transform3D = row.transform
			var bounds := AABB(at*faces[index],Vector3.ZERO)
			bounds = bounds.expand(at*faces[index+1]).expand(at*faces[index+2])
			if bounds.intersects(room): intrusions += 1
	check_eq(intrusions,0,"scallops and valance lamps leave the framed painting visible")
