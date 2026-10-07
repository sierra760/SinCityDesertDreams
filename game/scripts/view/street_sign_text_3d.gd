# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name StreetSignText3D
extends RefCounted

const FONT := "res://assets/fonts/biorhyme/BioRhyme-Medium.ttf"
const LIMIT := 128
static var _cache: Dictionary = {}
static var _order: Array[String] = []
static var _ivory: StandardMaterial3D

static func cache_size() -> int:
	return _cache.size()

## Retain resources and detached layout values, never mutable scene instances.
## The complete face contract is part of the key (including font and rectangles).
static func layout(text: String, face: Dictionary) -> Dictionary:
	var key := text + "\n" + JSON.stringify(face)
	if _cache.has(key):
		_order.erase(key)
		_order.append(key)
		return _cache[key].duplicate(true)
	var config: Dictionary = face.layout
	var font := load(String(face.get("font",FONT))) as Font
	var safe := Vector2(config.destination_safe_m[0],config.destination_safe_m[1])
	var em := float(config.destination_em_m)
	var candidates: Array = [[text]]
	if text.length()>1:
		# Compare real one/two-line fits, preserving all characters at the split.
		var split := 1
		var best := INF
		var breaks: Array[int]=[]
		for at: int in range(1,text.length()):
			if text[at-1]==" ": breaks.append(at)
		if breaks.is_empty():
			for at: int in range(1,text.length()):breaks.append(at)
		for at: int in breaks:
			var width := maxf(font.get_string_size(text.left(at),HORIZONTAL_ALIGNMENT_LEFT,-1,64).x,font.get_string_size(text.substr(at),HORIZONTAL_ALIGNMENT_LEFT,-1,64).x)
			if width<best: best=width;split=at
		candidates.append([text.left(split),text.substr(split)])
	var gap := float(config.line_gap_m)
	var lines: Array[String] = []
	var meshes: Array[TextMesh] = []
	var factor := -INF
	var total := 0.0
	for candidate: Array in candidates:
		var candidate_meshes: Array[TextMesh] = []
		var width := 0.0
		var height := gap*(candidate.size()-1)
		for line: String in candidate:
			var mesh := _mesh(line,font,em)
			candidate_meshes.append(mesh)
			width=maxf(width,mesh.get_aabb().size.x)
			height+=mesh.get_aabb().size.y
		var fit:=minf(safe.x*.96/maxf(width,.000001),safe.y*.90/maxf(height,.000001))
		if fit>factor:
			factor=fit;total=height;meshes=candidate_meshes;lines.assign(candidate)
	var records: Array[Dictionary] = []
	var bounds := AABB()
	var center := Vector2(config.destination_center_m[0],config.destination_center_m[1])
	var cursor := total*.5
	for i: int in meshes.size():
		var mesh := meshes[i]
		var box := mesh.get_aabb()
		# Grow only the lettering plane. The fixed millimetre extrusion stays
		# within the face mount and its physical reservation at every font fit.
		var scale := Vector3(factor,factor,1.0)
		var position := Vector3(center.x,center.y+(cursor-box.size.y*.5)*factor,0)-box.get_center()*scale
		var transform := Transform3D(Basis.from_scale(scale),position)
		var mounted: AABB = transform*box
		bounds = mounted if records.is_empty() else bounds.merge(mounted)
		records.append({"mesh":mesh,"transform":transform,"text":lines[i]})
		cursor-=box.size.y+gap
	var result := {"lines":lines,"meshes":records,"bounds":bounds}
	_cache[key] = result
	_order.append(key)
	while _order.size()>LIMIT: _cache.erase(_order.pop_front())
	return result.duplicate(true)

static func _mesh(text: String, font: Font, em: float) -> TextMesh:
	if _ivory==null:
		_ivory=StandardMaterial3D.new()
		_ivory.albedo_color=Color("f5eed7")
		_ivory.roughness=.8
	var mesh:=TextMesh.new()
	mesh.font=font
	mesh.font_size=64
	mesh.pixel_size=em/64.0
	mesh.depth=.001
	mesh.text=text
	mesh.material=_ivory
	return mesh
