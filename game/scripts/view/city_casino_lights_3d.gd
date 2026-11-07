# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Casinos after dark: neon over each casino's own walls, its colour washed
## onto the ground around it and searchlights sweeping the sky. Presentation
## only, and present only while night mode is on.
class_name CityCasinoLights3D
extends Node3D

const Signatures := preload("res://scripts/view/casino_night_signatures.gd")
const Globals := preload("res://scripts/view/city_night_globals.gd")
const NEON := preload("res://shaders/casino_neon_overlay.gdshader")
const BEAM := preload("res://shaders/casino_searchlight.gdshader")
## Beams rise from the roof and lean this far from vertical while sweeping.
const BEAM_LENGTH := 9.0
const BEAM_TILT := deg_to_rad(16.0)
const BEAM_SWEEP := .35

## Lot records: {"node", "code", "bounds", "material"}.
var lots: Array[Dictionary] = []
var _overlaid: Array[GeometryInstance3D] = []
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
		var material := ShaderMaterial.new()
		material.shader = NEON
		material.set_shader_parameter("neon_a",signature.a)
		material.set_shader_parameter("neon_b",signature.b)
		material.set_shader_parameter("base_y",bounds.position.y)
		material.set_shader_parameter("top_y",bounds.end.y)
		material.set_shader_parameter("style",int(signature.style))
		var cell: Vector2i = node.get_meta("cell",Vector2i.ZERO)
		material.set_shader_parameter("phase",float((cell.x*7+cell.y*13)%17))
		var record := {"node":node,"code":code,"bounds":bounds,"material":material,"signature":signature}
		lots.append(record)
		_overlay(record)
		_add_beams(record)
	_paint_wash()
	set_process(not _beams.is_empty())

func clear() -> void:
	for instance: GeometryInstance3D in _overlaid:
		if is_instance_valid(instance): instance.material_overlay = null
	_overlaid.clear()
	for beam: Dictionary in _beams:
		if is_instance_valid(beam.pivot): beam.pivot.free()
	_beams.clear()
	lots.clear()
	if _texture != null: Globals.set_wash(null)
	set_process(false)

func _exit_tree() -> void:
	clear()

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

## Neon is drawn over the lot's visible meshes. A batched mesh is drawn by
## its batch, so the overlay goes on that batch instead.
func _overlay(record: Dictionary) -> void:
	var batches := _batches_by_mesh()
	for child: Node in record.node.find_children("*","MeshInstance3D",true,false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null: continue
		var target: GeometryInstance3D = mesh
		if not mesh.is_visible_in_tree() and batches.has(mesh.mesh.get_instance_id()):
			target = batches[mesh.mesh.get_instance_id()]
		elif not mesh.is_visible_in_tree():
			continue
		target.material_overlay = record.material
		_overlaid.append(target)

func _batches_by_mesh() -> Dictionary:
	var out := {}
	if _view == null or not ("mesh_batches" in _view) or _view.mesh_batches == null: return out
	for child: Node in _view.mesh_batches.find_children("*","MultiMeshInstance3D",true,false):
		var batch := child as MultiMeshInstance3D
		if batch.multimesh != null and batch.multimesh.mesh != null: out[batch.multimesh.mesh.get_instance_id()] = batch
	return out

func _add_beams(record: Dictionary) -> void:
	var count := int(record.signature.get("beams",0))
	if count <= 0: return
	var bounds: AABB = record.bounds
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
	for i: int in count:
		var pivot := Node3D.new()
		pivot.name = "Searchlight"
		var offset := Vector3((float(i)-(count-1)*.5)*minf(bounds.size.x,1.2)*.5,0,0)
		pivot.position = Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)+offset
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
