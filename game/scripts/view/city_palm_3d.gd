# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Full-sized arched palms shared by natural groves and planted lots.
extends RefCounted

## Grove layout: how many trunks each tree family plants, where each trunk
## stands inside the tile, which of the four palm variants it uses, and the
## relative height of each variant.
const GROVE_TRUNKS := [4, 3, 4, 7, 8, 8, 9]
const GROVE_ROOTS := [Vector2(0.25, 0.25), Vector2(0.72, 0.24), Vector2(0.25, 0.73), Vector2(0.73, 0.73),
	Vector2(0.49, 0.45), Vector2(0.13, 0.48), Vector2(0.49, 0.87), Vector2(0.88, 0.49), Vector2(0.5, 0.12)]
const GROVE_VARIANTS := [3, 1, 0, 2, 0, 3, 1, 2, 3]
const VARIANT_HEIGHTS := [6.5, 10.0, 8.0, 5.0]

## Identical authored parameter tuples share immutable rendering resources. Every
## placement still receives its own transform, nodes and physical trunk body.
static var _trunk_meshes: Dictionary = {}
static var _frond_meshes: Dictionary = {}
static var _trunk_material: StandardMaterial3D
static var _crown_material_contracts: Dictionary = {}

## Shared palm generator for street planting and authored lot landscaping.
## Height and crown radius are in tile units; the root is at local ground level.
static func create(height: float = 0.65, crown_radius: float = 0.18, variant: int = 0) -> Node3D:
	var palm := Node3D.new()
	palm.name = "Palm"
	var trunk := MeshInstance3D.new()
	var trunk_radius := clampf(height * 0.025, 0.009, 0.018)
	var cylinder: CylinderMesh = _trunk_meshes.get(height)
	if cylinder == null:
		cylinder = CylinderMesh.new()
		cylinder.top_radius = trunk_radius * 0.65
		cylinder.bottom_radius = trunk_radius
		cylinder.height = height
		cylinder.radial_segments = 8
		_trunk_meshes[height] = cylinder
	trunk.mesh = cylinder
	trunk.position.y = height * 0.5
	if _trunk_material == null:
		_trunk_material = CityGeometry3D.material(Color(0.50, 0.37, 0.23))
	trunk.material_override = _trunk_material
	palm.add_child(trunk)
	var body := StaticBody3D.new()
	body.name = "PalmTrunk"
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var volume := CylinderShape3D.new()
	volume.height = height
	volume.radius = trunk_radius
	shape.shape = volume
	shape.position.y = height * 0.5
	body.add_child(shape)
	palm.add_child(body)
	var fronds := MeshInstance3D.new()
	var key: Array = [height, crown_radius, variant]
	if not _frond_meshes.has(key):
		var mesh := _make_fronds(height, crown_radius, variant)
		_frond_meshes[key] = mesh
		var material := mesh.surface_get_material(0) as ShaderMaterial
		_crown_material_contracts[material] = {"shader": material.shader, "code": material.shader.code}
	fronds.mesh = _frond_meshes[key]
	palm.add_child(fronds)
	return palm


## Only our own cached crown materials qualify. DETAIL with zero grain uses
## the plain vertex colors; its fragment result has no world-coordinate,
## time, camera or per-instance uniforms. Terrain/network modes stay excluded.
static func is_static_crown_material(material: Material) -> bool:
	if not material is ShaderMaterial or not _crown_material_contracts.has(material):
		return false
	var crown := material as ShaderMaterial
	var contract: Dictionary = _crown_material_contracts[material]
	return crown.shader == contract.shader and crown.shader.code == contract.code \
		and crown.next_pass == null \
		and crown.get_shader_parameter("surface_kind") == CityGeometry3D.SurfaceKind.DETAIL \
		and crown.get_shader_parameter("grain_strength") == 0.0


static func _make_fronds(height: float, crown_radius: float, variant: int) -> ArrayMesh:
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var cells: Array[Vector2i] = []
	var medium := PackedInt32Array()
	var distant := PackedInt32Array()
	# Eight arched, tapered fronds carry distinct leaflets along their ribs.
	for leaf: int in 8:
		var angle := leaf * TAU / 8.0 + variant * 0.31
		var direction := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-sin(angle), 0, cos(angle))
		var color := Color(0.31, 0.43, 0.18).lightened(0.035 * float((leaf + variant) % 3))
		var rings: Array[Vector2i] = []
		for segment: int in 6:
			var t0 := float(segment) / 6.0
			var t1 := float(segment + 1) / 6.0
			var a := direction * crown_radius * t0 + Vector3.UP * (height + sin(t0 * PI) * crown_radius * 0.35 - t0 * t0 * crown_radius * 0.45)
			var b := direction * crown_radius * t1 + Vector3.UP * (height + sin(t1 * PI) * crown_radius * 0.35 - t1 * t1 * crown_radius * 0.45)
			var width0 := sin(t0 * PI) * crown_radius * 0.21 + crown_radius * 0.02
			var width1 := sin(t1 * PI) * crown_radius * 0.21 + crown_radius * 0.005
			var start := faces.size()
			if segment == 0: rings.append(Vector2i(start, start+1))
			rings.append(Vector2i(start+2, start+4))
			CityGeometry3D.quad(faces, cells, colors, a + across * width0, a - across * width0,
				b + across * width1, b - across * width1, Vector2i.ZERO, color)
			if segment > 0 and segment < 5:
				for side: int in [-1, 1]:
					var tip := a + across * width0 * 1.65 * side - direction * crown_radius * 0.10 - Vector3.UP * crown_radius * 0.065
					faces.append_array(PackedVector3Array([a, b, tip] if side > 0 else [a, tip, b]))
					colors.append_array(PackedColorArray([color, color.darkened(0.08), color]))
		# Continuous strips span existing rib endpoints; merely dropping alternate
		# near triangles would leave holes. Tiny side leaflets disappear only at
		# automatic overview LOD distances. Near arrays and the physical trunk are not simplified.
		_append_ribbon_lod(medium, rings, [0, 2, 4, 6])
		_append_ribbon_lod(distant, rings, [0, 3, 6])
	var original := CityGeometry3D.mesh_from_faces(faces, colors)
	var mesh := ArrayMesh.new()
	# Godot requires an indexed base surface for automatic LOD. Add an
	# identity index stream to the serialized surface, preserving packed normal,
	# color and position bytes instead of quantizing them a second time.
	var surface: Dictionary = original.get("_surfaces")[0].duplicate()
	# Each crown keeps its own material: the batcher admits exactly these
	# registered crown materials, never the shared generic surface material.
	surface["material"] = CityGeometry3D.surface_material()
	var identity := PackedInt32Array()
	for index: int in faces.size(): identity.append(index)
	surface.format = int(surface.format) | Mesh.ARRAY_FORMAT_INDEX
	surface.index_data = _indices_u16(identity)
	surface.index_count = identity.size()
	surface.lods = [crown_radius * 0.12, _indices_u16(medium), crown_radius * 0.28, _indices_u16(distant)]
	mesh.set("_surfaces", [surface])
	return mesh


static func _append_ribbon_lod(indices: PackedInt32Array, rings: Array[Vector2i], stops: Array[int]) -> void:
	for segment: int in stops.size()-1:
		var a := rings[stops[segment]]
		var b := rings[stops[segment+1]]
		indices.append_array(PackedInt32Array([a.x, a.y, b.x, a.y, b.y, b.x]))


static func _indices_u16(indices: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(indices.size()*2)
	for i: int in indices.size(): bytes.encode_u16(i*2, indices[i])
	return bytes
