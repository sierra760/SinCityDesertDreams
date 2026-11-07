# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Casinos after dark: neon along each casino's own rooflines and corners,
## chasing bulbs on its entrance canopy, its colour washed onto the ground
## around it and searchlights sweeping the sky. Presentation only, and present
## only while night mode is on.
class_name CityCasinoLights3D
extends Node3D

const Signatures := preload("res://scripts/view/casino_night_signatures.gd")
const Globals := preload("res://scripts/view/city_night_globals.gd")
const NEON := preload("res://shaders/casino_neon_tube.gdshader")
const Edges := preload("res://scripts/view/casino_neon_edges.gd")
## Neon tube and marquee bulb half-thickness, in tile units.
const TUBE := .0055
const BULB := .0075
## Rooflines lower than this above the lot base (planters, plinths, steps)
## carry no neon; up to MARQUEE_TOP near the entrance they carry bulbs.
const NEON_FLOOR := .1
const MARQUEE_TOP := .42
## Nothing is lit across the doorway below this height above the base.
const DOOR_TOP := .29
const BEAM := preload("res://shaders/casino_searchlight.gdshader")
const PANES := preload("res://shaders/casino_window_panes.gdshader")
const FEATURE := preload("res://shaders/casino_feature_glow.gdshader")
## Signature features glow harder than the neon around them.
const FEATURE_STRENGTH := 1.5
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
## Glass below this height above the lot base is the lobby and entrance.
const LOBBY_HEIGHT := .2
## About this share of upper-floor panes is lit, chosen per pane.
const LIT_SHARE := .5
## Lit panes sit this far in front of the glass, in tile units.
const PANE_LIFT := .0012
## Glass this many times longer than tall is a ribbon window, lit in bays this
## wide (tiles; 2 m) with this share of each bay left dark as its mullion.
const RIBBON_RATIO := 3.0
const BAY := .125
const BAY_FRAME := .12
## Mullions: upright parts taller than this and thinner than this (tiles),
## standing within this distance of their glass.
const MULLION_HEIGHT := .08
const MULLION_WIDTH := .02
const MULLION_REACH := .02
## Half the width of the entrance kept clear of neon, by lot size.
const DOOR_HALF_WIDTH := {1: .12, 2: .16, 3: .22, 4: .28}
## Beams rise from the roof and lean this far from vertical while sweeping.
const BEAM_LENGTH := 9.0
const BEAM_TILT := deg_to_rad(16.0)
const BEAM_SWEEP := .35

## Lot records: {"node", "code", "bounds", "signature", "door", "neon",
## "panes", "features"}.
var lots: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _view: Node
var _image: Image
var _texture: ImageTexture
var _time := 0.0

func bind(view: Node) -> void:
	_view = view

## Find every casino lot and light it. Called on entering night and whenever
## the city's buildings change while it is night.
func rebuild() -> void:
	clear()
	if _view == null or not ("buildings" in _view) or _view.buildings == null: return
	for node: Node in _view.buildings.get_children():
		if not node.has_meta("code") or not Signatures.has(int(node.get_meta("code"))): continue
		var bounds := _bounds(node)
		if bounds.size == Vector3.ZERO: continue
		var code := int(node.get_meta("code"))
		var signature: Dictionary = Signatures.of(code)
		var cell: Vector2i = node.get_meta("cell",Vector2i.ZERO)
		var door := _door(code,cell)
		var record := {"node":node,"code":code,"bounds":bounds,"signature":signature,"door":door,"cell":cell}
		lots.append(record)
		_add_neon(record)
		_add_panes(record)
		_add_features(record)
		_add_beams(record)
	_paint_wash()
	set_process(not _beams.is_empty())

func clear() -> void:
	for beam: Dictionary in _beams:
		if is_instance_valid(beam.pivot): beam.pivot.free()
	_beams.clear()
	for record: Dictionary in lots:
		if is_instance_valid(record.get("panes")): record.panes.free()
		if is_instance_valid(record.get("neon")): record.neon.free()
		for feature: Variant in record.get("features",[]):
			if is_instance_valid(feature): feature.free()
	lots.clear()
	if _texture != null: Globals.set_wash(null)
	set_process(false)

func _exit_tree() -> void:
	clear()

## The main entrance of a casino lot: where Explore's front door is.
func _door(code: int, anchor: Vector2i) -> Dictionary:
	var city: City = _view.city if "city" in _view else null
	if city == null: return {}
	var threshold: Transform3D = Access.threshold(city,anchor,code)
	var front := threshold.basis*Vector3.BACK
	var size := Buildings.size(code)
	return {"center":Vector2(threshold.origin.x,threshold.origin.z),"front":Vector2(front.x,front.z).normalized(),
		"half_width":float(DOOR_HALF_WIDTH.get(mini(size.x,size.y),.2))}

## Lit window panes, built from the casino's own glass: each authored pane is
## lit whole or not at all. Upper-floor panes glow in the casino's colour
## about half the time; lobby glass glows warm; skylights, canopy tops and
## large glass shapes stay unlit.
func _add_panes(record: Dictionary) -> void:
	var base: float = record.bounds.position.y
	var colour: Color = record.signature.glass
	var lobby := Color(1.0,.84,.6)
	var faces := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var mullions: Array = []
	for child: Node in record.node.find_children("*","MeshInstance3D",true,false):
		var source := child as MeshInstance3D
		if source.mesh == null: continue
		for surface: int in source.mesh.get_surface_count():
			var material := source.get_active_material(surface)
			if material == null or not CityNightMode.role_for(material.resource_name) in [CityNightMode.Role.WINDOW,CityNightMode.Role.WINDOW_DIM]: continue
			for pane: Dictionary in _panes(source,surface):
				var size: Vector3 = pane.size
				# Window panes stand upright: thin one way, taller than thick.
				if pane.triangles.size() > 16 or size.y < .006 or minf(size.x,size.z) > size.y*.6: continue
				var lift: float = pane.center.y-base
				var light := lobby*.75
				# A long, low ribbon of glass is lit bay by bay between its own
				# mullions, like a row of rooms.
				if lift >= LOBBY_HEIGHT and maxf(size.x,size.z) > maxf(size.y*RIBBON_RATIO,BAY*2.0):
					if mullions.is_empty(): mullions = _mullions(record.node)
					_add_ribbon(pane,mullions,colour,faces,normals,colours)
					continue
				if lift >= LOBBY_HEIGHT:
					var roll := _hash01(pane.center)
					if roll > LIT_SHARE: continue
					light = colour*lerpf(.7,1.0,_hash01(pane.center+Vector3(.37,0,.71)))
				var linear := light.srgb_to_linear()
				for triangle: Array in pane.triangles:
					var normal: Vector3 = triangle[3]
					if absf(normal.y) > .3: continue
					for i: int in 3:
						faces.append(triangle[i]+normal*PANE_LIFT)
						normals.append(normal)
						colours.append(linear)
	if faces.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader = PANES
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name = "LitPanes"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	record["panes"] = instance

## Thin upright parts (mullions, glazing bars) of a lot's model: centre and
## height, in world space.
static func _mullions(lot: Node3D) -> Array:
	var out: Array = [Vector3.INF]
	for child: Node in lot.find_children("*","MeshInstance3D",true,false):
		var source := child as MeshInstance3D
		if source.mesh == null or source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		for surface: int in source.mesh.get_surface_count():
			var material := source.get_active_material(surface)
			if material == null or CityNightMode.role_for(material.resource_name) in [CityNightMode.Role.WINDOW,CityNightMode.Role.WINDOW_DIM]: continue
			for part: Dictionary in _panes(source,surface):
				var size: Vector3 = part.size
				if size.y > MULLION_HEIGHT and maxf(size.x,size.z) < MULLION_WIDTH: out.append([part.center,size.y])
	return out

## Lit bays on a ribbon window, divided at the mullions standing on its face
## (or every BAY when it has none).
func _add_ribbon(pane: Dictionary, mullions: Array, colour: Color,
		faces: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray) -> void:
	var size: Vector3 = pane.size
	var center: Vector3 = pane.center
	for triangle: Array in pane.triangles:
		var normal: Vector3 = triangle[3]
		if absf(normal.y) > .3: continue
		var along := Vector3.UP.cross(normal).normalized()
		var half := (absf(along.x)*size.x+absf(along.z)*size.z)*.5
		var reach := (absf(normal.x)*size.x+absf(normal.z)*size.z)*.5+MULLION_REACH
		var bounds: Array[float] = [center.dot(along)-half,center.dot(along)+half]
		for mullion: Variant in mullions:
			if not mullion is Array: continue
			var at: Vector3 = mullion[0]
			if absf((at-center).dot(normal)) > reach or float(mullion[1]) < size.y*.8 or absf(at.y-center.y) > size.y*.5: continue
			var s := at.dot(along)
			if s > bounds[0]+BAY*.2 and s < bounds[1]-BAY*.2: bounds.append(s)
		if bounds.size() == 2:
			var step := bounds[0]+BAY
			while step < bounds[1]-BAY*.2:
				bounds.append(step)
				step += BAY
		bounds.sort()
		var gap := BAY*BAY_FRAME*.5
		for i: int in bounds.size()-1:
			var low: float = bounds[i]+(gap if i > 0 else 0.0)
			var high: float = bounds[i+1]-(gap if i < bounds.size()-2 else 0.0)
			var key := center+along*((low+high)*.5-center.dot(along))
			if high <= low or _hash01(key) > LIT_SHARE: continue
			var tint: Color = (colour*lerpf(.7,1.0,_hash01(key+Vector3(.37,0,.71)))).srgb_to_linear()
			var piece := _clip_slab([triangle[0],triangle[1],triangle[2]],along,low,high)
			for k: int in range(1,piece.size()-1):
				for corner: Vector3 in [piece[0],piece[k],piece[k+1]]:
					faces.append(corner+normal*PANE_LIFT)
					normals.append(normal)
					colours.append(tint)

## The part of a convex polygon between two planes across `axis`.
static func _clip_slab(polygon: Array, axis: Vector3, low: float, high: float) -> Array:
	for side: int in 2:
		var out: Array = []
		for i: int in polygon.size():
			var a: Vector3 = polygon[i]
			var b: Vector3 = polygon[(i+1)%polygon.size()]
			var da := (a.dot(axis)-low) if side == 0 else (high-a.dot(axis))
			var db := (b.dot(axis)-low) if side == 0 else (high-b.dot(axis))
			if da >= 0.0: out.append(a)
			if (da >= 0.0) != (db >= 0.0): out.append(a.lerp(b,da/(da-db)))
		polygon = out
		if polygon.size() < 3: return []
	return polygon

## Each signature feature (the Afterglow's sun, the Boulder Crown's turbine
## wheel...) is its own authored geometry, picked by material inside a box in
## model space and redrawn just in front of itself with its own glow.
func _add_features(record: Dictionary) -> void:
	record["features"] = []
	var specs: Array = Signatures.features(record.code)
	if specs.is_empty() or record.node.get_child_count() == 0: return
	var model := record.node.get_child(0) as Node3D
	if model == null: return
	var to_model := model.global_transform.affine_inverse()
	var sources: Array[MeshInstance3D] = []
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		if (child as MeshInstance3D).mesh != null: sources.append(child)
	for spec: Dictionary in specs:
		var box := AABB()
		var boxed: Array = spec.box
		if not boxed.is_empty(): box = AABB(Vector3(boxed[0],boxed[1],boxed[2]),Vector3(boxed[3]-boxed[0],boxed[4]-boxed[1],boxed[5]-boxed[2]))
		var faces := PackedVector3Array()
		var colours := PackedColorArray()
		for source: MeshInstance3D in sources:
			for surface: int in source.mesh.get_surface_count():
				var material := source.get_active_material(surface) as BaseMaterial3D
				if material == null or not base_name(material.resource_name) in spec.materials: continue
				var tint: Color = spec.colour if spec.colour != null else material.albedo_color
				var linear := tint.srgb_to_linear()
				_feature_triangles(source,surface,to_model,box,boxed.is_empty(),linear,faces,colours)
		if faces.is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces
		arrays[Mesh.ARRAY_COLOR] = colours
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := ShaderMaterial.new()
		material.shader = FEATURE
		var to_world := model.global_transform
		var center_model := Vector3(spec.center[0],spec.center[1],spec.center[2])
		var axis_model := Vector3(spec.axis[0],spec.axis[1],spec.axis[2])
		material.set_shader_parameter("center",to_world*center_model)
		material.set_shader_parameter("axis",(to_world.basis*axis_model).normalized())
		var extent := box.size.length()*.5 if not boxed.is_empty() else 8.0
		material.set_shader_parameter("radius",(to_world.basis*Vector3(extent,0,0)).length())
		material.set_shader_parameter("effect",int(spec.effect))
		material.set_shader_parameter("strength",FEATURE_STRENGTH*float(spec.get("strength",1.0)))
		material.set_shader_parameter("phase",float(record.code % 7))
		mesh.surface_set_material(0,material)
		var instance := MeshInstance3D.new()
		instance.name = "SignatureFeature"
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		record.features.append(instance)

## Triangles of one surface whose centre (in model space) lies in `box`,
## lifted just off the surface along their face normal, in world space.
static func _feature_triangles(source: MeshInstance3D, surface: int, to_model: Transform3D, box: AABB, everywhere: bool,
		colour: Color, faces: PackedVector3Array, colours: PackedColorArray) -> void:
	var arrays := source.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i: int in vertices.size(): indices[i] = i
	var authored: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var to_world := source.global_transform
	var normal_basis := to_world.basis.inverse().transposed()
	for t: int in range(0,indices.size()-2,3):
		var a := to_world*vertices[indices[t]]
		var b := to_world*vertices[indices[t+1]]
		var c := to_world*vertices[indices[t+2]]
		if not everywhere and not box.has_point(to_model*((a+b+c)/3.0)): continue
		var normal := (c-a).cross(b-a)
		if normal.length_squared() < 1e-14: continue
		if not authored.is_empty():
			normal = normal_basis*(authored[indices[t]]+authored[indices[t+1]]+authored[indices[t+2]])
			if normal.length_squared() < 1e-14: continue
		var lift := normal.normalized()*PANE_LIFT
		faces.append_array(PackedVector3Array([a+lift,b+lift,c+lift]))
		colours.append_array(PackedColorArray([colour,colour,colour]))

## A material's authored name without Blender suffixes or texture notes.
static func base_name(material_name: String) -> String:
	var base := material_name.get_slice(" • ",0).strip_edges()
	var dot := base.rfind(".")
	if dot > 0 and base.substr(dot+1).is_valid_int(): base = base.substr(0,dot)
	return base

## The glass of one surface split into panes (connected pieces), in world
## space: {"triangles": [[a, b, c, normal]], "center", "size"}.
static func _panes(source: MeshInstance3D, surface: int) -> Array[Dictionary]:
	var arrays := source.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i: int in vertices.size(): indices[i] = i
	var authored: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var to_world := source.global_transform
	var normal_basis := to_world.basis.inverse().transposed()
	var world := PackedVector3Array()
	world.resize(vertices.size())
	for i: int in vertices.size(): world[i] = to_world*vertices[i]
	# Join vertices that share a position, then triangles that share a vertex.
	var key_of := {}
	var parent: Array[int] = []
	var welded := PackedInt32Array()
	welded.resize(world.size())
	for i: int in world.size():
		var key := Vector3i((world[i]*2000.0).round())
		if not key_of.has(key):
			key_of[key] = parent.size()
			parent.append(parent.size())
		welded[i] = key_of[key]
	for t: int in range(0,indices.size()-2,3):
		var a := _root(parent,welded[indices[t]])
		for k: int in [1,2]:
			var b := _root(parent,welded[indices[t+k]])
			if a != b: parent[b] = a
	var groups := {}
	for t: int in range(0,indices.size()-2,3):
		var root := _root(parent,welded[indices[t]])
		var a := world[indices[t]]
		var b := world[indices[t+1]]
		var c := world[indices[t+2]]
		if (c-a).cross(b-a).length_squared() < 1e-14: continue
		var normal := (c-a).cross(b-a)
		if not authored.is_empty():
			normal = normal_basis*(authored[indices[t]]+authored[indices[t+1]]+authored[indices[t+2]])
		if not groups.has(root): groups[root] = {"triangles":[],"box":AABB(a,Vector3.ZERO)}
		var group: Dictionary = groups[root]
		group.triangles.append([a,b,c,normal.normalized()])
		group.box = group.box.expand(a).expand(b).expand(c)
	var out: Array[Dictionary] = []
	for group: Dictionary in groups.values():
		out.append({"triangles":group.triangles,"center":group.box.get_center(),"size":group.box.size})
	return out

static func _root(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

## A stable 0..1 value for a position; never touches the game's random streams.
static func _hash01(point: Vector3) -> float:
	return float(posmod(hash(Vector3i((point*512.0).round())),65536))/65535.0

static func _bounds(lot: Node) -> AABB:
	var bounds := AABB()
	var first := true
	for child: Node in lot.find_children("*","MeshInstance3D",true,false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null: continue
		var box: AABB = mesh.global_transform*mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

## Neon along the casino's own rooflines (and, for the fins and grid
## styles, its tall outer corners); chasing bulbs on low canopy and porch
## edges by the entrance. Nothing crosses the doorway below its top.
func _add_neon(record: Dictionary) -> void:
	record["neon"] = null
	if record.node.get_child_count() == 0: return
	var model := record.node.get_child(0) as Node3D
	if model == null: return
	var edges := Edges.of(record.code,model)
	var to_world := model.global_transform
	var base: float = record.bounds.position.y
	var signature: Dictionary = record.signature
	var style := int(signature.style)
	var crown_colour := Color(signature.a).srgb_to_linear()
	var corner_colour := Color(signature.b).srgb_to_linear()
	var bulb_colour := Color(signature.b).lerp(Color(1.0,.92,.75),.55).srgb_to_linear()
	var door: Dictionary = record.door
	var door_point := Vector2(door.center) if not door.is_empty() else Vector2(record.bounds.get_center().x,record.bounds.get_center().z)
	var front := Vector2(door.front) if not door.is_empty() else Vector2(0,1)
	var half_width: float = door.get("half_width",.2)
	var near_entrance := maxf(1.2,maxf(record.bounds.size.x,record.bounds.size.z)*.42)
	var faces := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var runs: Array = []
	for edge: Array in edges.crown: runs.append([edge,"crown"])
	for edge: Array in edges.get("soffit",[]): runs.append([edge,"soffit"])
	if style in [Signatures.Style.FINS,Signatures.Style.GRID]:
		for edge: Array in edges.corner: runs.append([edge,"corner"])
	for run: Array in runs:
		var edge: Array = run[0]
		var a: Vector3 = to_world*Vector3(edge[0])
		var b: Vector3 = to_world*Vector3(edge[1])
		var outward: Vector3 = (to_world.basis*Vector3(edge[2])).normalized()
		var mid := (a+b)*.5
		var lift := mid.y-base
		var low := minf(a.y,b.y)-base
		if run[1] != "corner" and lift < NEON_FLOOR: continue
		var flat := Vector2(mid.x,mid.z)-door_point
		var in_doorway := absf(flat.dot(Vector2(front.y,-front.x))) < half_width+.05 and absf(flat.dot(front)) < .8
		if in_doorway and low < DOOR_TOP: continue
		# Bulbs only on low edges that face the street by the entrance.
		var facing := Vector2(outward.x,outward.z).dot(front)
		var marquee := lift <= MARQUEE_TOP and flat.length() < near_entrance and facing > .5
		# A canopy's underside edge carries the marquee and nothing else.
		if run[1] == "soffit" and not marquee: continue
		var bulbs: bool = run[1] != "corner" and marquee
		var colour := bulb_colour if bulbs else (crown_colour if run[1] == "crown" else corner_colour)
		var size := BULB if bulbs else TUBE
		var offset := outward*size+(Vector3.UP*size if run[1] == "crown" else (Vector3.DOWN*size if run[1] == "soffit" else Vector3.ZERO))
		_tube(a+offset,b+offset,size,colour,1.0 if bulbs else 0.0,faces,colours,uvs)
	if faces.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader = NEON
	material.set_shader_parameter("style",style)
	var cell: Vector2i = record.cell
	material.set_shader_parameter("phase",float((cell.x*7+cell.y*13)%17))
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name = "CasinoNeon"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	record["neon"] = instance

## A square tube from `a` to `b`; UV.x runs along it in tile units.
static func _tube(a: Vector3, b: Vector3, size: float, colour: Color, bulbs: float,
		faces: PackedVector3Array, colours: PackedColorArray, uvs: PackedVector2Array) -> void:
	var axis := b-a
	if axis.length_squared() < 1e-10: return
	var direction := axis.normalized()
	var u := direction.cross(Vector3.UP if absf(direction.y) < .9 else Vector3.RIGHT).normalized()*size
	var v := direction.cross(u).normalized()*size
	var start := a.dot(direction)
	var end := b.dot(direction)
	var ring: Array[Vector3] = [u+v,u-v,-u-v,-u+v]
	for i: int in 4:
		var p := ring[i]
		var q := ring[(i+1)%4]
		faces.append_array(PackedVector3Array([a+p,b+p,b+q,a+p,b+q,a+q]))
		uvs.append_array(PackedVector2Array([Vector2(start,bulbs),Vector2(end,bulbs),Vector2(end,bulbs),Vector2(start,bulbs),Vector2(end,bulbs),Vector2(start,bulbs)]))
		for k: int in 6: colours.append(colour)

func _add_beams(record: Dictionary) -> void:
	var count := int(record.signature.get("beams",0))
	if count <= 0: return
	var mesh := CylinderMesh.new()
	# The narrow end is the lamp; the beam widens into the sky.
	mesh.top_radius = .03
	mesh.bottom_radius = .32
	mesh.height = BEAM_LENGTH
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = BEAM
	material.set_shader_parameter("beam_color",Color(record.signature.b).lerp(Color.WHITE,.55))
	material.set_shader_parameter("beam_length",BEAM_LENGTH)
	var anchors := _beam_anchors(record,count)
	for i: int in count:
		var pivot := Node3D.new()
		pivot.name = "Searchlight"
		pivot.position = anchors[i]
		var beam := MeshInstance3D.new()
		beam.mesh = mesh
		beam.material_override = material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Flip so the narrow top sits at the lamp, then lift the cone above it.
		beam.basis = Basis(Vector3.RIGHT,PI)
		beam.position = Vector3(0,BEAM_LENGTH*.5,0)
		pivot.add_child(beam)
		add_child(pivot)
		_beams.append({"pivot":pivot,"phase":float(i)*TAU/count+float(record.code)})
	_sweep(0.0)

## Where each searchlight stands: on the highest flat roofs of the model
## itself, one per tower when equally tall towers are enough, otherwise
## spread to the ends of the highest roof; with no flat roof, on the top of
## the model's bounds.
func _beam_anchors(record: Dictionary, count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = []
	var model: Node3D = record.node.get_child(0) as Node3D if record.node.get_child_count() > 0 else null
	var roofs: Array = []
	if model != null:
		var to_world := model.global_transform
		for points: PackedVector3Array in Edges.of(record.code,model).get("roof",[]):
			var world := PackedVector3Array()
			for point: Vector3 in points: world.append(to_world*point)
			roofs.append(world)
	if roofs.is_empty():
		var bounds: AABB = record.bounds
		for i: int in count: anchors.append(Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z))
		return anchors
	if count > 1 and roofs.size() >= count:
		# The highest roof first, then each time the roof farthest from those
		# already chosen.
		var middles: Array[Vector3] = []
		for roof: PackedVector3Array in roofs: middles.append(_spread(roof,1)[0])
		anchors.append(middles[0])
		while anchors.size() < count:
			var best := -1
			var best_gap := -1.0
			for i: int in middles.size():
				var gap := INF
				for chosen: Vector3 in anchors: gap = minf(gap,Vector2(middles[i].x-chosen.x,middles[i].z-chosen.z).length())
				if gap > best_gap:
					best_gap = gap
					best = i
			anchors.append(middles[best])
		return anchors
	return _spread(roofs[0],count)

## `count` points on a roof: its middle for one, else evenly from end to end
## of its longer side, keeping to the middle across it.
static func _spread(roof: PackedVector3Array, count: int) -> Array[Vector3]:
	var lo := roof[0]
	var hi := roof[0]
	for point: Vector3 in roof:
		lo = lo.min(point)
		hi = hi.max(point)
	var along := 0 if hi.x-lo.x >= hi.z-lo.z else 2
	var across := 2-along
	var middle := (lo[across]+hi[across])*.5
	var points: Array[Vector3] = []
	for i: int in count:
		var target := lerpf(lo[along],hi[along],.5 if count == 1 else float(i)/(count-1))
		var best := roof[0]
		var best_score := INF
		for point: Vector3 in roof:
			var score := absf(point[along]-target)+.5*absf(point[across]-middle)
			if score < best_score:
				best_score = score
				best = point
		points.append(best)
	return points

func _process(delta: float) -> void:
	_time += delta
	_sweep(_time)

func _sweep(time: float) -> void:
	for beam: Dictionary in _beams:
		var pivot: Node3D = beam.pivot
		if not is_instance_valid(pivot): continue
		var start: float = beam.phase
		var heading := start+time*BEAM_SWEEP
		var lean := BEAM_TILT*(.75+.25*sin(time*.6+start))
		pivot.basis = Basis(Vector3.UP,heading)*Basis(Vector3.RIGHT,lean)

## Each casino tints its own tiles and fades over the two tiles around them.
func _paint_wash() -> void:
	if _image == null: _image = Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBA8)
	_image.fill(Color(0,0,0,0))
	for record: Dictionary in lots:
		var bounds: AABB = record.bounds
		var colour: Color = record.signature.a
		var low := Vector2i(floori(bounds.position.x),floori(bounds.position.z))
		var high := Vector2i(floori(bounds.end.x-.001),floori(bounds.end.z-.001))
		for y: int in range(low.y-2,high.y+3):
			for x: int in range(low.x-2,high.x+3):
				if x < 0 or y < 0 or x >= City.WIDTH or y >= City.HEIGHT: continue
				var ring := maxi(maxi(low.x-x,x-high.x),maxi(low.y-y,y-high.y))
				var strength: float = [.6,.3,.1][clampi(ring,0,2)]
				if _image.get_pixel(x,y).a >= strength: continue
				_image.set_pixel(x,y,Color(colour.r,colour.g,colour.b,strength))
	if _texture == null: _texture = ImageTexture.create_from_image(_image)
	else: _texture.update(_image)
	Globals.set_wash(_texture)
