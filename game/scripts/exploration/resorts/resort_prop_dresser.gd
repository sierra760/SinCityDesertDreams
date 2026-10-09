# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Assembles a resort hall from the authored hall and prop kit: every placed
## surface is merged into one mesh per finish, slot cabinets and their stools
## become multimeshes, lettering is set in the resort font, and the authored
## collision shells become one static body. Each finish maps the authored
## `resort_<finish>` material onto the procedural resort finish shader with
## the resort's palette.
class_name ResortPropDresser
extends RefCounted

const ROOT := "res://assets/desert-dreams-resorts/"
const LAYER := 1 << 20
const FINISHES := {"resort_floor": 0, "resort_carpet": 1, "resort_wall": 2, "resort_ceiling": 3,
	"resort_stone": 4, "resort_wood": 5, "resort_metal": 6, "resort_glass": 7, "resort_felt": 8,
	"resort_lamp": 9, "resort_sign": 10, "resort_screen": 11, "resort_rubber": 12, "resort_cove": 13,
	"resort_foliage": 14}
const VARIANTS := {&"arcology_comstock": 0, &"arcology_junction": 1, &"arcology_boulder": 2, &"arcology_orbit": 3}
const METRES := 16.0
const SHADER := preload("res://scripts/exploration/resorts/resort_finish.gdshader")
## Authored props that are visual only, never blocking.
const OPEN_PROPS := ["bar_stool","slot_stool","standard_sign","chandelier_gaslamp","chandelier_lantern",
	"chandelier_turbine","chandelier_starburst"]
## Plate face of the standard_sign prop (metres, prop space) and its size.
const STANDARD_FACE := Vector3(0,1.42,.035)
const STANDARD_ROOM := Vector2(.78,.42)

static var _parts_cache: Dictionary = {}

## Parts of an authored scene: surfaces with their prop-space transforms and
## the prop-space collision triangles. {} when the asset is absent.
static func parts(name: String) -> Dictionary:
	if _parts_cache.has(name): return _parts_cache[name]
	var path := ROOT+name+".glb"
	if not ResourceLoader.exists(path): return {}
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	var result := {"surfaces": [], "collision": PackedVector3Array(), "triangles": 0}
	for child: Node in root.get_children(): _walk(child,Transform3D.IDENTITY,result)
	root.free()
	_parts_cache[name] = result
	return result

static func _walk(node: Node, parent: Transform3D, result: Dictionary) -> void:
	var at := parent
	if node is Node3D: at = parent*(node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var key := material.resource_name if material != null else "resort_stone"
			result.surfaces.append({"mesh": mesh, "surface": surface, "transform": at, "material": key})
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			result.triangles += (indices.size() if not indices.is_empty() else vertices.size())/3
	elif node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		var shape: Shape3D = (node as CollisionShape3D).shape
		var faces := PackedVector3Array()
		if shape is ConcavePolygonShape3D: faces = (shape as ConcavePolygonShape3D).get_faces()
		else:
			var debug := shape.get_debug_mesh()
			if debug != null: faces = debug.get_faces()
		for point: Vector3 in faces: result.collision.append(at*point)
	for child: Node in node.get_children(): _walk(child,at,result)

## Palette colours (base, accent, detail) for each finish of a resort.
static func finish_colors(key: StringName) -> Dictionary:
	var palette: Dictionary = ResortInteriorLayouts.theme(key).get("palette",{})
	var stone: Color = palette.get("stone",Color(.8,.7,.55))
	var metal: Color = palette.get("metal",Color(.7,.45,.25))
	var wood: Color = palette.get("wood",Color(.3,.2,.12))
	var glass: Color = palette.get("glass",Color(.1,.4,.4))
	var lamp: Color = palette.get("lamp",Color(1,.85,.6))
	var carpet: Color = palette.get("carpet",Color(.35,.1,.1))
	var felt: Color = palette.get("felt",Color(.15,.35,.3))
	var accent: Color = palette.get("accent",metal)
	var ink: Color = palette.get("ink",Color(.1,.1,.1))
	var paper: Color = palette.get("paper",Color(.95,.9,.8))
	var variant: int = VARIANTS.get(key,0)
	var floor_base: Color = [stone,paper,glass.darkened(.18),paper][variant]
	var ceiling_base: Color = [paper.lerp(metal,.28),glass.lightened(.12),paper.darkened(.04),ink.lightened(.06)][variant]
	var screen: Color = [lamp,lamp,glass.lightened(.35),glass.lightened(.25)][variant]
	return {"resort_floor": [floor_base,metal,paper], "resort_carpet": [carpet,accent if variant!=1 else metal,paper],
		"resort_wall": [stone,metal,paper], "resort_ceiling": [ceiling_base,metal,paper],
		"resort_stone": [stone,metal,paper], "resort_wood": [wood,metal,paper], "resort_metal": [metal,metal,paper],
		"resort_glass": [glass,metal,paper], "resort_felt": [felt,paper,paper], "resort_lamp": [lamp,lamp,lamp],
		"resort_sign": [ink,metal,paper], "resort_screen": [screen,metal,paper],
		"resort_rubber": [Color(.05,.05,.05),ink,ink], "lettering": [lamp,lamp,lamp],
		"resort_cove": [paper.lerp(Color(.78,.93,.96),.55),glass,paper], "resort_foliage": [Color(.20,.38,.17),Color(.32,.5,.22),paper]}

## One ShaderMaterial per finish for the hall at `origin` (world tile units).
static func materials(key: StringName, origin: Vector3) -> Dictionary:
	var colors := finish_colors(key)
	var result := {}
	for finish: String in FINISHES:
		var material := ShaderMaterial.new()
		material.resource_name = finish
		material.shader = SHADER
		var swatch: Array = colors[finish]
		material.set_shader_parameter("finish",int(FINISHES[finish]))
		material.set_shader_parameter("variant",int(VARIANTS.get(key,0)))
		material.set_shader_parameter("base_color",swatch[0])
		material.set_shader_parameter("accent_color",swatch[1])
		material.set_shader_parameter("detail_color",swatch[2])
		material.set_shader_parameter("origin",origin)
		material.set_shader_parameter("pattern_center",ResortInteriorLayouts.PIT)
		result[finish] = material
	var letters := StandardMaterial3D.new()
	letters.resource_name = "resort_lettering"
	letters.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	letters.albedo_color = Color(colors.lettering[0]).lightened(.08)
	result["resort_lettering"] = letters
	return result

## The shared warm fill for resort halls: layer 21 only, no shadows.
static func make_fill() -> DirectionalLight3D:
	var fill := DirectionalLight3D.new()
	fill.name = "ResortFill"
	fill.light_cull_mask = LAYER
	fill.shadow_enabled = false
	fill.light_color = Color(1.0,.90,.76)
	fill.light_energy = .3
	fill.rotation_degrees = Vector3(-62,-24,0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return fill

## Build `world`'s visuals, lettering, lamps and collision. Returns stats.
static func populate(world: Node3D, key: StringName, code: int, plan: Dictionary) -> Dictionary:
	var hall_space := Node3D.new()
	hall_space.name = "HallMetres"
	hall_space.scale = Vector3.ONE/METRES
	world.add_child(hall_space)
	var finish_materials := materials(key,world.position)
	var batches := {}
	var collision := PackedVector3Array()
	var triangles := 0
	var hall := parts("hall_%d" % code)
	var placeholder := hall.is_empty()
	if placeholder: hall = _placeholder_hall(plan)
	triangles += _place(hall,Transform3D.IDENTITY,batches,collision,true)
	var slots: Array[Transform3D] = []
	var stools: Array[Transform3D] = []
	for table: Dictionary in plan.tables:
		var pose := _metres(table.pose)
		var count := int(table.count)
		var prop := String(table.prop)
		var piece := parts(prop)
		if piece.is_empty(): piece = _placeholder_prop(Vector2(table.half)*METRES/Vector2(maxf(1,count),1),1.2)
		for index: int in count:
			var offset := (float(index)-(count-1)*.5)*(float(table.half.x)*2.0*METRES/float(count))
			var at := pose*Transform3D(Basis.IDENTITY,Vector3(offset,0,0))
			if table.game == &"slots" and not placeholder:
				slots.append(at)
				stools.append(at*Transform3D(Basis.IDENTITY,Vector3(0,0,.95)))
				_add_collision(piece.collision,at,collision)
			else:
				triangles += _place(piece,at,batches,collision,true)
	for row: Dictionary in plan.decor:
		var piece := parts(String(row.prop))
		if piece.is_empty() and bool(row.solid): piece = _placeholder_prop(Vector2(3.5,.55),1.0)
		triangles += _place(piece,_metres(row.pose),batches,collision,bool(row.solid) and String(row.prop) not in OPEN_PROPS)
	for row: Dictionary in plan.chandeliers:
		triangles += _place(parts(String(row.prop)),_metres(row.pose),batches,collision,false)
	var font: Font = load(ResortInteriorLayouts.font_path(key))
	var signs := 0
	for row: Dictionary in plan.signs:
		var at := _metres(row.at)
		if placeholder: _place(_box_parts(Vector3(0,0,-.06),Vector3(row.size.x*METRES,row.size.y*METRES,.1),"resort_sign"),at,batches,collision,false)
		_letter(batches,font,String(row.text),at*Transform3D(Basis.IDENTITY,Vector3(0,0,.012)),Vector2(row.size)*METRES*Vector2(.92,.78))
		signs += 1
	var standard := parts("standard_sign")
	for row: Dictionary in plan.standards:
		var at := _metres(row.pose)
		if standard.is_empty(): _place(_box_parts(Vector3(0,STANDARD_FACE.y,0),Vector3(STANDARD_ROOM.x+.08,STANDARD_ROOM.y+.08,.06),"resort_sign"),at,batches,collision,false)
		else: triangles += _place(standard,at,batches,collision,false)
		var text := "%s\n$%s %s" % [String(row.text),_grouped(int(row.minimum)),String(row.minimum_word)]
		_letter(batches,font,text,at*Transform3D(Basis.IDENTITY,STANDARD_FACE+Vector3(0,0,.004)),STANDARD_ROOM)
		signs += 1
	var mesh := ArrayMesh.new()
	var draws := 0
	var names: Array = batches.keys()
	names.sort()
	for name: String in names:
		var tool: SurfaceTool = batches[name]
		tool.set_material(finish_materials.get(name,finish_materials.resort_stone))
		tool.commit(mesh)
		draws += 1
	var batch := MeshInstance3D.new()
	batch.name = "ResortHallBatch"
	batch.mesh = mesh
	_present(batch)
	hall_space.add_child(batch)
	draws += _multimesh(hall_space,"SlotCabinets",parts("slot_cabinet"),slots,finish_materials)
	draws += _multimesh(hall_space,"SlotStools",parts("slot_stool"),stools,finish_materials)
	var cabinet_triangles := int(parts("slot_cabinet").get("triangles",0))*slots.size()+int(parts("slot_stool").get("triangles",0))*stools.size()
	triangles += cabinet_triangles
	var art_surfaces := _artwork(hall_space,key,slots,plan)
	draws += art_surfaces
	if art_surfaces > 0: triangles += (3+slots.size()*2)*2
	var body := StaticBody3D.new()
	body.name = "ResortHallCollision"
	body.collision_layer = ExploreActorProfile.FLOOR | ExploreActorProfile.OBSTACLE
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	var scaled := PackedVector3Array()
	scaled.resize(collision.size())
	for index: int in collision.size(): scaled[index] = collision[index]/METRES
	shape.set_faces(scaled)
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	world.add_child(body)
	var lights := _light(world,plan)
	return {"triangles": triangles, "draw_surfaces": draws, "lights": lights, "signs": signs,
		"slots": slots.size(), "art_surfaces": art_surfaces,
		"collision_triangles": collision.size()/3, "placeholder": placeholder}

## All illustrated cabinet inserts and three framed wall paintings, grouped by
## texture into one mesh. Raised above the walking lanes; no collision changes.
static func _artwork(parent: Node3D, key: StringName, slots: Array[Transform3D], plan: Dictionary) -> int:
	var batches := {}
	if plan.has("art"):
		for row: Dictionary in plan.art:
			_art_quad(batches,key,String(row.asset),row.pose,row.size)
	else:
		for index: int in 2:
			var asset := "mural-history" if index == 0 else "mural-industry"
			_art_quad(batches,key,asset,Transform3D(Basis(Vector3.UP,PI),Vector3(-15 if index == 0 else 15,6.6,21.18)),Vector2(4.0,4.0))
		_art_quad(batches,key,"mural-heritage",Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-21.01,6.5,-12)),Vector2(4.45,4.45))
	var badge: Dictionary = plan.get("slot_badge",{"position":Vector3(0,1.68,.148),"size":Vector2(.16,.16)})
	for at: Transform3D in slots:
		_art_quad(batches,key,"cabinet-reels",at*Transform3D(Basis.IDENTITY,Vector3(0,1.29,.204)),Vector2(.56,.327))
		_art_quad(batches,key,"symbol-B",at*Transform3D(Basis.IDENTITY,badge.position),badge.size)
	var mesh := ArrayMesh.new()
	for asset: String in batches:
		var texture := ResortArtwork.texture(key,asset)
		if texture == null: continue
		var material := StandardMaterial3D.new()
		material.resource_name = "resort_art_"+asset
		material.albedo_texture = texture
		# Backlit reel inserts and individually lit gallery prints retain their
		# authored ink colors rather than bleaching under the hall's many lamps.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(batches[asset] as SurfaceTool).set_material(material)
		(batches[asset] as SurfaceTool).commit(mesh)
	if mesh.get_surface_count() == 0: return 0
	var node := MeshInstance3D.new()
	node.name = "ResortArtworkBatch"
	node.mesh = mesh
	_present(node)
	parent.add_child(node)
	return mesh.get_surface_count()

static func _art_quad(batches: Dictionary, key: StringName, asset: String, at: Transform3D, size: Vector2) -> void:
	var texture := ResortArtwork.texture(key,asset)
	if texture == null: return
	if not batches.has(asset):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[asset] = tool
	var quad := QuadMesh.new()
	quad.size = size
	var bounds := ResortArtwork.region(key,asset)
	var arrays := quad.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index: int in uv.size():
		uv[index] = (bounds.position+uv[index]*bounds.size)/texture.get_size()
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var trimmed := ArrayMesh.new()
	trimmed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	(batches[asset] as SurfaceTool).append_from(trimmed,0,at)

static func _metres(pose: Transform3D) -> Transform3D:
	return Transform3D(pose.basis,pose.origin*METRES)

static func _grouped(value: int) -> String:
	var digits := str(value)
	var out := ""
	for index: int in digits.length():
		if index>0 and (digits.length()-index)%3==0: out += ","
		out += digits[index]
	return out

static func _present(node: GeometryInstance3D) -> void:
	node.layers = LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

## Append a part set at `at` to the per-finish batches; returns its triangles.
static func _place(piece: Dictionary, at: Transform3D, batches: Dictionary, collision: PackedVector3Array, solid: bool) -> int:
	if piece.is_empty(): return 0
	for row: Dictionary in piece.surfaces:
		var name := String(row.material)
		if not batches.has(name):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[name] = tool
		(batches[name] as SurfaceTool).append_from(row.mesh,int(row.surface),at*Transform3D(row.transform))
	if solid: _add_collision(piece.collision,at,collision)
	return int(piece.triangles)

static func _add_collision(faces: PackedVector3Array, at: Transform3D, collision: PackedVector3Array) -> void:
	for point: Vector3 in faces: collision.append(at*point)

static func _multimesh(parent: Node3D, name: String, piece: Dictionary, placements: Array[Transform3D], finish_materials: Dictionary) -> int:
	if piece.is_empty() or placements.is_empty(): return 0
	var tools := {}
	for row: Dictionary in piece.surfaces:
		var key := String(row.material)
		if not tools.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = tool
		(tools[key] as SurfaceTool).append_from(row.mesh,int(row.surface),Transform3D(row.transform))
	var mesh := ArrayMesh.new()
	for key: String in tools:
		var tool: SurfaceTool = tools[key]
		tool.set_material(finish_materials.get(key,finish_materials.resort_stone))
		tool.commit(mesh)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()
	for index: int in placements.size(): multimesh.set_instance_transform(index,placements[index])
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multimesh
	_present(node)
	parent.add_child(node)
	return mesh.get_surface_count()

## Lettering in the resort font, centred on `at` and fitted into `room`
## (metres), merged into the lettering batch.
static func _letter(batches: Dictionary, font: Font, text: String, at: Transform3D, room: Vector2) -> void:
	var letters := TextMesh.new()
	letters.font = font
	letters.text = text
	letters.font_size = 64
	letters.pixel_size = .01
	letters.depth = 0.0
	letters.curve_step = 1.5
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var size := letters.get_aabb().size
	if size.x<=0.0 or size.y<=0.0: return
	letters.pixel_size = .01*minf(room.x/size.x,room.y/size.y)
	if not batches.has("resort_lettering"):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches["resort_lettering"] = tool
	(batches["resort_lettering"] as SurfaceTool).append_from(letters,0,at)

## The hall's own lamps: OmniLights on layer 21 without shadows. They show
## only while their hall is visible (occupied). The one directional fill for
## every hall belongs to the Explore resort service: directional lights are
## global, so a fill per hall would light the others and add up.
static func _light(world: Node3D, plan: Dictionary) -> int:
	var count := 0
	var palette: Dictionary = ResortInteriorLayouts.theme(StringName(plan.key)).get("palette",{})
	var warm: Color = palette.get("lamp",Color(1,.88,.7))
	for row: Dictionary in plan.lights:
		var lamp := OmniLight3D.new()
		lamp.name = "ResortLamp_"+String(row.role)
		lamp.light_cull_mask = LAYER
		lamp.shadow_enabled = false
		lamp.light_color = warm
		lamp.light_energy = float(row.energy)*.55
		lamp.omni_range = float(row.range)
		lamp.omni_attenuation = .8
		lamp.position = row.position
		world.add_child(lamp)
		count += 1
	return count

static func _box_parts(center: Vector3, size: Vector3, material: String) -> Dictionary:
	var box := BoxMesh.new()
	box.size = size
	var faces := box.get_faces()
	var collision := PackedVector3Array()
	for point: Vector3 in faces: collision.append(point+center)
	return {"surfaces": [{"mesh": box, "surface": 0, "transform": Transform3D(Basis.IDENTITY,center), "material": material}],
		"collision": collision, "triangles": faces.size()/3}

static func _merge(into: Dictionary, piece: Dictionary) -> void:
	into.surfaces.append_array(piece.surfaces)
	into.collision.append_array(piece.collision)
	into.triangles += int(piece.triangles)

static func _placeholder_prop(half: Vector2, height: float) -> Dictionary:
	return _box_parts(Vector3(0,height*.5,0),Vector3(half.x*2.0,height,half.y*2.0),"resort_felt")

## A plain closed hall from the plan, used only while the authored hall asset
## is absent. Metres, local to the floor centre.
static func _placeholder_hall(plan: Dictionary) -> Dictionary:
	var half := ResortInteriorLayouts.HALF*METRES
	var high := ResortInteriorLayouts.CEILING*METRES
	var front := ResortInteriorLayouts.VESTIBULE_END*METRES
	var door := ResortInteriorLayouts.VESTIBULE_HALF_WIDTH*METRES
	var low := ResortInteriorLayouts.VESTIBULE_CEILING*METRES
	var hall := {"surfaces": [], "collision": PackedVector3Array(), "triangles": 0}
	_merge(hall,_box_parts(Vector3(0,-.3,(front-half)*.5),Vector3(half*2+1.2,.6,front+half+1.2),"resort_carpet"))
	_merge(hall,_box_parts(Vector3(0,high+.3,0),Vector3(half*2+1.2,.6,half*2+1.2),"resort_ceiling"))
	_merge(hall,_box_parts(Vector3(0,low+.3,(half+front)*.5),Vector3(door*2+1.2,.6,front-half),"resort_ceiling"))
	for side: int in [-1,1]:
		_merge(hall,_box_parts(Vector3(side*(half+.3),high*.5,0),Vector3(.6,high,half*2+1.2),"resort_wall"))
		_merge(hall,_box_parts(Vector3(side*(door+half)*.5,high*.5,half+.3),Vector3(half-door,high,.6),"resort_wall"))
		_merge(hall,_box_parts(Vector3(side*(door+.3),low*.5,(half+front)*.5),Vector3(.6,low,front-half),"resort_wall"))
	_merge(hall,_box_parts(Vector3(0,(high+low)*.5,half+.3),Vector3(door*2,high-low,.6),"resort_wall"))
	_merge(hall,_box_parts(Vector3(0,high*.5,-half-.3),Vector3(half*2,high,.6),"resort_wall"))
	_merge(hall,_box_parts(Vector3(0,low*.5,front+.3),Vector3(door*2,low,.6),"resort_wood"))
	for row: Dictionary in ResortInteriorLayouts.ARCHITECTURE:
		_merge(hall,_box_parts(Vector3(row.at.x,float(row.height)*.5,row.at.z),Vector3(row.half.x*2.0,float(row.height),row.half.y*2.0),"resort_stone"))
	var dais: Dictionary = ResortInteriorLayouts.DAIS
	_merge(hall,_box_parts(Vector3(dais.at.x,.15,dais.at.z),Vector3(dais.half.x*2.0,.3,dais.half.y*2.0),"resort_floor"))
	return hall
