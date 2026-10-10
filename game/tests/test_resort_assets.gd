# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Resort hall and prop assets: catalog hashes, budgets and shells, and the
## built floors: a door mat, every seat reachable from it on foot, and the
## triangle and draw-surface budgets of a populated hall.
extends "res://tests/exploration/async_test_case.gd"

const ROOT := "res://assets/desert-dreams-resorts/"
const CODES := [251,252,253,254,256,257,258,259,260,261]
const STEP := .1
const OPEN := ["bar_stool","slot_stool","standard_sign","chandelier_gaslamp","chandelier_lantern",
	"chandelier_turbine","chandelier_starburst"]

func _catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"catalog.json"))
	return parsed if parsed is Dictionary else {}

func test_catalog_hashes_budgets_and_shells() -> void:
	var catalog := _catalog()
	check(catalog.has("models") and catalog.has("halls"),"catalog lists models and halls")
	var models: Dictionary = catalog.get("models",{})
	for name: String in models:
		var row: Dictionary = models[name]
		var path := ROOT+name+".glb"
		check(FileAccess.file_exists(path),name+" exists")
		check_eq(FileAccess.get_sha256(path),String(row.sha256),name+" hash matches the catalog")
		check(ResourceLoader.exists(path),name+" imports")
		var budget := 40000 if name.begins_with("hall_") else 1500 if name == "slot_cabinet" else 4000
		check_between(int(row.triangles),12,budget,name+" triangle budget")
		for material: String in row.materials:
			check(ResortPropDresser.FINISHES.has(material),name+": known finish "+material)
		if name not in OPEN: check_gt(int(row.get("colliders",0)),0,name+" has collision shells")
		var piece := ResortPropDresser.parts(name)
		check(not piece.is_empty(),name+" loads")
		if name not in OPEN: check_gt(PackedVector3Array(piece.get("collision",PackedVector3Array())).size(),0,name+" shells import as collision")
	for code: int in CODES:
		check(models.has("hall_%d" % code),"hall %d present" % code)
		var hall: Dictionary = catalog.halls.get(str(code),{})
		check_eq(hall.get("resort",""),String(ResortInteriorLayouts.key_for_building(code)),"hall %d resort" % code)
	for prop: String in ["slot_cabinet","slot_stool","blackjack_table","roulette_table","money_wheel","video_poker_terminal",
		"faro_table","chuck_a_luck_cage","baccarat_table","trajectory_console","chandelier_gaslamp","chandelier_lantern",
		"chandelier_turbine","chandelier_starburst","banquette","bar_stool","standard_sign",
		"vault_table","route_table","encore_table","forecast_console","contract_table","common_pot_table"]:
		check(models.has(prop),prop+" in the kit")

func _support(space: PhysicsDirectSpaceState3D, world: Node3D, local: Vector2) -> float:
	var top := world.position+Vector3(local.x,.1,local.y)
	var query := PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*.2,ExploreActorProfile.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<.57: return NAN
	return float(hit.position.y)

func _capsule(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK)
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*(.0575+.004))
	query.collision_mask = ExploreActorProfile.WORLD
	query.margin = .001
	return query

func _clear(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	return space.intersect_shape(_capsule(at),1).is_empty()

func _path_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := _capsule(from)
	query.motion = to-from
	var result := space.cast_motion(query)
	return result.size()>0 and result[0]>=.999

func test_built_halls_reach_every_seat_within_budgets() -> void:
	for code: int in CODES:
		var key := ResortInteriorLayouts.key_for_building(code)
		var world := ResortInteriorWorld3D.new()
		root.add_child(world)
		world.build(key,code,Vector2i(20,18))
		await physics_frame
		await physics_frame
		var stats := world.stats
		print("  hall %d: %d triangles, %d draw surfaces, %d lights, built in %.1f ms" % [code,int(stats.triangles),int(stats.draw_surfaces),int(stats.lights),world.build_usec/1000.0])
		check(not bool(stats.placeholder),"%d uses the authored hall" % code)
		check_between(int(stats.triangles),1000,150000,"%d populated triangle budget" % code)
		check_between(int(stats.draw_surfaces),1,40,"%d draw surface budget" % code)
		check_between(int(stats.lights),2,7,"%d fill plus at most six lamps" % code)
		check_eq(int(stats.slots),48,"%d slot multimesh instances" % code)
		var space := world.get_world_3d().direct_space_state
		var mat: Vector3 = world.mat_transform().origin
		check(abs(_support(space,world,Vector2(mat.x,mat.z)-Vector2(world.position.x,world.position.z))-world.position.y)<.005,"%d mat stands on the floor" % code)
		check(_clear(space,mat),"%d mat is clear" % code)
		# Walkable floor grid at 0.1 tile, joined by unobstructed capsule moves.
		var bounds: AABB = ResortInteriorLayouts.POCKET_BOUNDS
		var cells := {}
		var xs := int(bounds.size.x/STEP)
		var zs := int(bounds.size.z/STEP)
		for i: int in xs:
			for j: int in zs:
				var local := Vector2(bounds.position.x+(i+.5)*STEP,bounds.position.z+(j+.5)*STEP)
				var height := _support(space,world,local)
				if is_nan(height): continue
				var at := Vector3(world.position.x+local.x,height,world.position.z+local.y)
				if _clear(space,at): cells[Vector2i(i,j)] = at
		var start := Vector2i(int((mat.x-world.position.x-bounds.position.x)/STEP),int((mat.z-world.position.z-bounds.position.z)/STEP))
		check(cells.has(start),"%d mat cell is walkable" % code)
		var reached := {start: true}
		var frontier: Array[Vector2i] = [start]
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next := cell+step
				if reached.has(next) or not cells.has(next): continue
				var a: Vector3 = cells[cell]
				var b: Vector3 = cells[next]
				if absf(a.y-b.y)>ExplorePedestrian.STEP: continue
				if not _path_clear(space,a+Vector3.UP*maxf(0,b.y-a.y),b): continue
				reached[next] = true
				frontier.append(next)
		check_gt(reached.size(),cells.size()*3/5,"%d most of the walkable floor is reachable" % code)
		for table: Dictionary in world.tables():
			var seat: Vector3 = table.seat
			var seated := _support(space,world,Vector2(seat.x,seat.z)-Vector2(world.position.x,world.position.z))
			check(absf(seated-seat.y)<.005,"%d %s seat on the floor" % [code,table.game])
			seat.y = seated
			check(_clear(space,seat),"%d %s seat is clear" % [code,table.game])
			var joined := false
			for cell: Vector2i in reached:
				var at: Vector3 = cells[cell]
				if Vector2(at.x-seat.x,at.z-seat.z).length()<=.15 and absf(at.y-seat.y)<=ExplorePedestrian.STEP and _path_clear(space,at+Vector3.UP*maxf(0,seat.y-at.y),seat):
					joined = true
					break
			check(joined,"%d %s seat reachable from the mat" % [code,table.game])
		world.free()
		await physics_frame

func test_props_carry_their_finish_materials_on_layer_21() -> void:
	var world := ResortInteriorWorld3D.new()
	root.add_child(world)
	world.build(&"arcology_orbit",254,Vector2i(40,40))
	var found := 0
	for node: Node in world.find_children("*","GeometryInstance3D",true,false):
		var instance := node as GeometryInstance3D
		check_eq(instance.layers,ResortInteriorWorld3D.LAYER,"%s renders on layer 21 only" % node.name)
		check_eq(instance.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		found += 1
	check_gt(found,0)
	for node: Node in world.find_children("*","Light3D",true,false):
		var light := node as Light3D
		check_eq(light.light_cull_mask,ResortInteriorWorld3D.LAYER,"%s lights only the hall" % node.name)
		check(not light.shadow_enabled,"%s casts no shadow" % node.name)
	var batch := world.find_child("ResortHallBatch",true,false) as MeshInstance3D
	check(batch != null,"hall batch")
	if batch != null:
		for surface: int in batch.mesh.get_surface_count():
			var material := batch.mesh.surface_get_material(surface)
			check(material is ShaderMaterial or material.resource_name == "resort_lettering","surface %d uses the finish or lettering material" % surface)
	world.free()

func test_every_sign_character_is_in_its_font() -> void:
	for key: StringName in ResortInteriorLayouts.keys():
		var font: Font = load(ResortInteriorLayouts.font_path(key))
		var plan := ResortInteriorLayouts.layout(key)
		var texts: Array[String] = []
		for sign: Dictionary in plan.signs: texts.append(String(sign.text))
		for standard: Dictionary in plan.standards: texts.append("%s $0123456789, %s" % [String(standard.text),String(standard.minimum_word)])
		for text: String in texts:
			for index: int in text.length():
				var character := text.unicode_at(index)
				if character in [32,10]: continue
				check(font.has_char(character),"%s: '%s' in %s" % [key,text[index],font.get_font_name()])
