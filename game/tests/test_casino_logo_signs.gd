# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## The signs keep their colors through compilation, dusk/dawn and construction.
extends "res://tests/exploration/async_test_case.gd"

const Edges := preload("res://scripts/view/casino_neon_edges.gd")
const CODES := [251,252,253,254,256,257,258,259,260,261,262,263,264,265]
const LIGHT_NAMES := ["sign_logo_letters","sign_logo_neon_a","sign_logo_neon_b","sign_logo_bulbs"]

class StubView extends Node:
	var world := Node3D.new()
	func exploration_camera() -> Camera3D: return null

func _materials(node: Node) -> Dictionary:
	var result := {}
	for child: Node in node.find_children("*","MeshInstance3D",true,false):
		var instance := child as MeshInstance3D
		if instance.mesh == null or instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		for s: int in instance.mesh.get_surface_count():
			var material := instance.get_active_material(s) as StandardMaterial3D
			if material != null and material.resource_name.begins_with("sign_logo_"):
				result[material.resource_name] = material
	return result

func _named(name: String, color: Color, glow: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = .035
	return material

func test_logo_roles_light_letters_and_tubes_but_keep_enamel_dark() -> void:
	for name: String in LIGHT_NAMES:
		check_ne(CityNightMode.role_for(name),CityNightMode.Role.NONE,"authored light %s"%name)
		check_eq(CityNightMode.role_for(name+".001"),CityNightMode.role_for(name),"import suffix")
	for name: String in ["sign_logo_face","sign_logo_case","sign_logo_metal","sign_logo_enamel"]:
		check_eq(CityNightMode.role_for(name),CityNightMode.Role.NONE,"unlit cabinet %s"%name)
		check(Edges.excluded(name) and Edges.is_sign(name),"cabinet excluded from building edge neon")

func test_multicolor_logo_fades_and_restores_exact_day_settings() -> void:
	var view := StubView.new()
	view.add_child(view.world)
	root.add_child(view)
	var night := CityNightMode.new()
	night.bind(view)
	view.add_child(night)
	var pink := _named("sign_logo_neon_a",Color("ff43b0"),Color("ff43b0"))
	var cyan := _named("sign_logo_neon_b",Color("31edec"),Color("31edec"))
	var letters := _named("sign_logo_letters",Color("fff0bf"),Color("ffc347"))
	var before := {}
	for material: StandardMaterial3D in [pink,cyan,letters]:
		before[material] = CityNightMode._save(material)
		var mesh := BoxMesh.new()
		mesh.material = material
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		view.world.add_child(instance)
	night.set_enabled(true)
	night._process(CityNightMode.FADE_SECONDS*.5)
	check_gt(pink.emission_energy_multiplier,.035,"half dusk lights the glass")
	check_lt(pink.emission_energy_multiplier,2.0,"letters stay restrained")
	check_eq(pink.emission,Color("ff43b0"))
	check_eq(cyan.emission,Color("31edec"))
	night.set_enabled(true,true)
	check_gt(letters.emission_energy_multiplier,.035)
	check_lt(letters.emission_energy_multiplier,2.0)
	# New signs constructed while it is night are discovered by the same watcher.
	var late := _named("sign_logo_neon_b",Color("5aff8f"),Color("5aff8f"))
	var late_before := CityNightMode._save(late)
	var late_mesh := BoxMesh.new()
	late_mesh.material = late
	var late_instance := MeshInstance3D.new()
	late_instance.mesh = late_mesh
	view.world.add_child(late_instance)
	await process_frame
	await process_frame
	check_gt(late.emission_energy_multiplier,.035,"newly constructed sign lights at night")
	night.set_enabled(false,true)
	for material: StandardMaterial3D in [pink,cyan,letters]:
		check_eq(CityNightMode._save(material),before[material],"exact day restore")
	check_eq(CityNightMode._save(late),late_before)
	view.free()
	check(not CityNightMode.materials_modified(),"cache can store daytime models again")

func test_all_fourteen_keep_sign_materials_when_compiled() -> void:
	var catalog := CityModelCatalog.new()
	catalog.compiled_cache_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	for code: int in CODES:
		catalog.runtime_compilation_enabled = false
		var source := catalog.instantiate_model(code)
		check(source != null,"source %d"%code)
		if source == null: continue
		var originals := _materials(source)
		check(originals.has("sign_logo_letters"),"raised letters %d"%code)
		var values := {}
		for key: String in originals:
			values[key] = [originals[key].albedo_color,CityNightMode._save(originals[key])]
		catalog.runtime_compilation_enabled = true
		var compiled := catalog.instantiate_model(code)
		check(compiled != null,"compiled %d"%code)
		if compiled != null:
			var kept := _materials(compiled)
			check_eq(kept.size(),originals.size(),"all logo surfaces compiled %d"%code)
			for key: String in values:
				check(kept.has(key),"material %s"%key)
				if kept.has(key):check_eq([kept[key].albedo_color,CityNightMode._save(kept[key])],values[key])
			if kept.has("sign_logo_letters"):
				var light := CityNightMode.new()
				light.amount=1.0
				light._consider(kept["sign_logo_letters"],code)
				check_gt((kept["sign_logo_letters"].emission as Color).r,.7,"imported light-map gain is not baked dim %d"%code)
				light._restore_all()
				light.free()
			compiled.free()
		source.free()
	check_eq(catalog.errors.size(),0)

func _texture_fingerprint(texture: Texture2D) -> Array:
	if texture==null:return []
	var image := texture.get_image()
	if image==null:return [texture.resource_path]
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return [texture.resource_path,image.get_size(),image.get_format(),hash.finish()]

func _logo_fingerprint(model: Node) -> Dictionary:
	var result := {}
	for name: String in _materials(model):
		var material: StandardMaterial3D = _materials(model)[name]
		var state := CityNightMode._save(material)
		state.erase("emission_texture")
		result[name]=[material.albedo_color,state,_texture_fingerprint(material.albedo_texture),_texture_fingerprint(material.emission_texture)]
	return result

func test_all_fourteen_restore_color_and_light_maps_from_disk_cache() -> void:
	var writer := CityModelCatalog.new()
	writer.load_manifest(CityModelCatalog.ROOT+"catalog.json")
	var expected := {}
	for code: int in CODES:
		var path := writer.compiled_cache_path(code,true)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var model := writer.instantiate_model(code)
		check(model!=null)
		if model==null:continue
		expected[code]=_logo_fingerprint(model)
		check(FileAccess.file_exists(path),"logo scene serialized %d"%code)
		model.free()
	check_eq(writer.compiled_cache_misses,14)
	var reader := CityModelCatalog.new()
	reader.load_manifest(CityModelCatalog.ROOT+"catalog.json")
	for code: int in CODES:
		var model := reader.instantiate_model(code)
		check(model!=null)
		if model==null:continue
		check(not reader.scenes.has(code),"disk restore does not load source %d"%code)
		check_eq(_logo_fingerprint(model),expected[code],"colors, emission state and both image channels survive disk restore %d"%code)
		model.free()
	check_eq(reader.compiled_cache_hits,14)
	check_eq(reader.compiled_cache_misses,0)

func test_architecture_neon_cannot_cross_the_middle_of_a_textured_logo() -> void:
	var plane := PlaneMesh.new()
	plane.size=Vector2(10,4)
	var arrays := plane.get_mesh_arrays()
	var signs := {}
	Edges._add_logo_cabinet(signs,arrays,Transform3D.IDENTITY)
	var middle_key := Vector3i.ZERO
	check(signs.has(middle_key),"cabinet interior is reserved even without letter vertices")

func test_rotated_lots_new_construction_and_removal_during_night() -> void:
	var city := flat_city(20000000)
	city.founded_year=2010
	var origin := Vector2i(20,20)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.set_night_mode(true,true)
	var rotations := {}
	for road: Vector2i in [Vector2i(21,24),Vector2i(19,21),Vector2i(21,19),Vector2i(24,21)]:
		city.stamp_building(origin.x,origin.y,254)
		city.building.put(road.x,road.y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
		view.refresh(true)
		await process_frame
		await process_frame
		var found := false
		for lot: Node in view.buildings.get_children():
			if int(lot.get_meta("code",-1))!=254:continue
			found=true
			rotations[snappedf((lot as Node3D).rotation.y,.01)]=true
			var materials := _materials(lot)
			check(materials.has("sign_logo_letters"),"new rotated lot carries the textured sign")
			if materials.has("sign_logo_letters"):
				check_gt(materials["sign_logo_letters"].emission_energy_multiplier,1.0,"constructed at night")
		check(found)
		for y: int in range(20,24):
			for x: int in range(20,24):city.building.put(x,y,Buildings.NONE)
		city.building.put(road.x,road.y,Buildings.NONE)
		view.refresh(true)
		await process_frame
		await process_frame
		check_eq(view.night.casinos.lots.size(),0,"demolished sign releases the casino light record")
	check_eq(rotations.size(),4,"all four street facings")
	view.set_night_mode(false,true)
	view.free()
	check(not CityNightMode.materials_modified(),"no lit materials remain after the city closes")
