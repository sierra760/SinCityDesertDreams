# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rubble (codes 1-4) and contaminated ground (code 5) from the original
## Blender kit `assets/desert-dreams-rubble/rubble-kit.glb`
## (tools/build_rubble_models.py). Each variant has two kinds of children:
## "Drape" heightfields, whose vertices are laid on the terrain facets and
## emitted with the network surface, and rigid debris pieces, each rested on a
## plane fitted under its footprint so no corner floats on a sloped or creased
## tile. "Solid" pieces also block walking actors like palm trunks do.
## Placement is a pure function of the cell, its code and its ground corners.
extends RefCounted

const KIT := preload("res://assets/desert-dreams-rubble/rubble-kit.glb")
const VARIANTS: Array[String] = ["Rubble1", "Rubble2", "Rubble3", "Rubble4", "Contamination"]
## Source metres per tile unit.
const METRES := 1.0 / 16.0
## Every drape and piece sits this far (tile units) above the terrain facets,
## keeping the low dust layers clear of the terrain depth at aerial distances.
const LIFT := 0.006

## Per variant: {"drapes": [[PackedVector3Array metre triangles, PackedColorArray]],
## "pieces": [{mesh, transform, solid, bounds, footprint}]}. Built once.
static var _kit: Array = []


static func variant_index(code: int) -> int:
	return clampi(code - Buildings.RUBBLE_1, 0, VARIANTS.size() - 1)


## Quarter turns that vary repeated rubble fields; stable per cell.
static func quarter_turns(cell: Vector2i) -> int:
	return ((cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.x * cell.y * 83492791)) & 3


static func spin(cell: Vector2i) -> Basis:
	return Basis(Vector3.UP, quarter_turns(cell) * PI * .5)


static func variant(code: int) -> Dictionary:
	if _kit.is_empty(): _load()
	return _kit[variant_index(code)]


static func _load() -> void:
	var scene: Node = KIT.instantiate()
	for name: String in VARIANTS:
		var root: Node = scene.find_child(name, true, false)
		assert(root != null, "rubble kit variant " + name)
		var drapes: Array = []
		var pieces: Array = []
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			var local := mesh_node.transform
			var parent := mesh_node.get_parent()
			while parent != root:
				local = (parent as Node3D).transform * local
				parent = parent.get_parent()
			var label := String(mesh_node.name)
			if label.begins_with("Drape"):
				drapes.append(_drape_triangles(mesh_node.mesh, local))
				continue
			# Every kit material is coloured only by its Mottle vertex colours. The
			# importer leaves that flag off for some single-user materials.
			for surface: int in mesh_node.mesh.get_surface_count():
				var material := mesh_node.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null: material.vertex_color_use_as_albedo = true
			var bounds := mesh_node.mesh.get_aabb()
			var footprint := PackedVector3Array()
			for corner: Vector3 in [bounds.position, Vector3(bounds.end.x, bounds.position.y, bounds.position.z),
					Vector3(bounds.position.x, bounds.position.y, bounds.end.z), Vector3(bounds.end.x, bounds.position.y, bounds.end.z)]:
				footprint.append(local * corner)
			pieces.append({"name": label, "mesh": mesh_node.mesh, "transform": local, "solid": label.begins_with("Solid"),
				"bounds": bounds, "footprint": footprint})
		pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
		_kit.append({"drapes": drapes, "pieces": pieces})
	scene.free()


static func _drape_triangles(mesh: Mesh, local: Transform3D) -> Array:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i: int in vertices.size(): indices.append(i)
		for t: int in range(0, indices.size() - 2, 3):
			var color := Color(0, 0, 0, 0)
			for k: int in 3:
				var index := indices[t + k]
				points.append(local * vertices[index])
				color += vertex_colors[index] if not vertex_colors.is_empty() else Color.WHITE
			# glTF vertex colours are linear; the network surface takes sRGB colours.
			color = (color / 3.0).linear_to_srgb()
			color.a = 1.0
			colors.append(color)
	return [points, colors]


## All of a variant's draped ground for one quarter turn: per-vertex tile
## offsets and heights above the facets (LIFT included), one colour per
## triangle. Cached per variant and turn; callers only read.
static func drape_ground(code: int, cell: Vector2i) -> Array:
	var kit := variant(code)
	var turn := quarter_turns(cell)
	var turns: Array = kit.get("drape_turns", [])
	if turns.is_empty():
		turns = [[], [], [], []]
		kit["drape_turns"] = turns
	if turns[turn].is_empty():
		var basis := Basis(Vector3.UP, turn * PI * .5)
		var offsets := PackedVector2Array()
		var heights := PackedFloat32Array()
		var colors := PackedColorArray()
		for drape: Array in kit.drapes:
			for point: Vector3 in drape[0]:
				var turned := basis * point
				offsets.append(Vector2(turned.x * METRES + .5, turned.z * METRES + .5))
				heights.append(LIFT + point.y * METRES)
			colors.append_array(drape[1])
		turns[turn] = [offsets, heights, colors]
	return turns[turn]


## Tile offset (0..1 across the cell) of a metre-space kit point after the cell spin.
static func offset_of(cell: Vector2i, point: Vector3) -> Vector2:
	var turned := spin(cell) * point
	return Vector2(turned.x * METRES + .5, turned.z * METRES + .5)


## Rigid debris for one cell, placed under `parent` (city coordinates).
## `facet` is [ground corners, NW-SE diagonal] as CityNetworks3D caches it.
static func add_pieces(parent: Node3D, cell: Vector2i, code: int, facet: Array) -> void:
	var turn := spin(cell)
	var pieces: Array = variant(code).pieces
	for index: int in pieces.size():
		var piece: Dictionary = pieces[index]
		var local: Transform3D = piece.transform
		var origin := offset_of(cell, local.origin)
		var rest := _rest_plane(cell, facet, piece.footprint, origin)
		var normal: Vector3 = rest[0]
		var tilt := Basis(Quaternion(Vector3.UP, normal))
		# Authored heights above ground (debris on a heap) are vertical, like the drapes.
		var at := Vector3(cell.x + origin.x, rest[1] + LIFT + local.origin.y * METRES, cell.y + origin.y)
		var basis := tilt * turn * local.basis
		var model := MeshInstance3D.new()
		model.name = piece.name
		model.mesh = piece.mesh
		model.set_meta(&"rubble_piece", index)
		model.transform = Transform3D(basis * METRES, at)
		parent.add_child(model)
		if piece.solid: _add_body(parent, model.transform, piece.bounds, basis.get_scale().x * METRES)


## Least-squares plane under a piece's footprint corners and pivot, lowered so
## no sample lies above the ground: [unit normal, height at the pivot].
static func _rest_plane(cell: Vector2i, facet: Array, footprint: PackedVector3Array, origin: Vector2) -> Array:
	var samples: Array[Vector3] = [_ground(cell, facet, origin)]
	for corner: Vector3 in footprint:
		var offset := offset_of(cell, corner).clamp(Vector2.ZERO, Vector2.ONE)
		samples.append(_ground(cell, facet, offset))
	# Normal equations for y = a*x + b*z + c over samples centred on the pivot.
	var sxx := 0.0; var sxz := 0.0; var szz := 0.0; var sx := 0.0; var sz := 0.0
	var sxy := 0.0; var szy := 0.0; var sy := 0.0
	for p: Vector3 in samples:
		var x := p.x - origin.x
		var z := p.z - origin.y
		sxx += x * x; sxz += x * z; szz += z * z; sx += x; sz += z
		sxy += x * p.y; szy += z * p.y; sy += p.y
	var n := float(samples.size())
	var system := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, n))
	var coefficients := Vector3(0, 0, sy / n)
	if absf(system.determinant()) > 1e-9:
		coefficients = system.inverse() * Vector3(sxy, szy, sy)
	var lowest := INF
	for p: Vector3 in samples:
		lowest = minf(lowest, p.y - (coefficients.x * (p.x - origin.x) + coefficients.y * (p.z - origin.y) + coefficients.z))
	var normal := Vector3(-coefficients.x, 1.0, -coefficients.y).normalized()
	return [normal, coefficients.z + minf(lowest, 0.0)]


## Ground sample in cell-offset x/z and world height y.
static func _ground(cell: Vector2i, facet: Array, offset: Vector2) -> Vector3:
	var point := CityGeometry3D.point_over_facet(facet[0], facet[1], cell, offset)
	return Vector3(offset.x, point.y, offset.y)


static func _add_body(parent: Node3D, model: Transform3D, bounds: AABB, scale: float) -> void:
	var body := StaticBody3D.new()
	body.name = "RubbleSolid"
	body.set_meta(&"rubble_solid", true)
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size * scale
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(model.basis.orthonormalized(), model * bounds.get_center())
	parent.add_child(body)
