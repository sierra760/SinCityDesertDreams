# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Upland trees for the higher vegetation zones: rounded junipers and piñons
## for the piñon-juniper woodland, tiered ponderosa pines and white firs for
## the pine forest. Each natural tree tile plants a grove whose size follows
## its density code, like the palm groves below them.
extends RefCounted

enum Species { JUNIPER, PINYON, PINE, FIR }

## Per species and variant: [height, crown radius] in tile units (16 m).
const SIZES := [
	[[0.30, 0.13], [0.36, 0.15], [0.26, 0.12]],
	[[0.42, 0.14], [0.50, 0.16], [0.38, 0.13]],
	[[1.15, 0.16], [1.30, 0.17], [0.95, 0.14]],
	[[1.05, 0.13], [1.20, 0.14], [0.90, 0.12]],
]
const CROWN_COLORS := [Color(0.37, 0.46, 0.37), Color(0.33, 0.42, 0.24), Color(0.20, 0.34, 0.19), Color(0.22, 0.36, 0.31)]
const BARK_COLORS := [Color(0.47, 0.39, 0.33), Color(0.42, 0.34, 0.27), Color(0.55, 0.35, 0.22), Color(0.40, 0.33, 0.29)]

const J := Species.JUNIPER
const P := Species.PINYON
const PINE := Species.PINE
const FIR := Species.FIR
## Groves per density (TREES_1..TREES_7): [x, y, species, variant] per tree.
## Woodland is open and scattered; forest closes its canopy.
const WOODLAND := [
	[[0.52, 0.47, J, 0]],
	[[0.33, 0.36, P, 0], [0.68, 0.62, J, 1]],
	[[0.28, 0.30, J, 0], [0.70, 0.38, P, 1], [0.45, 0.72, J, 2]],
	[[0.26, 0.28, P, 0], [0.72, 0.30, J, 1], [0.30, 0.72, J, 2], [0.70, 0.70, P, 2]],
	[[0.22, 0.24, P, 0], [0.58, 0.20, J, 1], [0.84, 0.42, P, 2], [0.20, 0.62, J, 0], [0.52, 0.54, P, 1], [0.74, 0.80, J, 2]],
	[[0.18, 0.20, J, 0], [0.48, 0.16, P, 2], [0.80, 0.24, J, 1], [0.30, 0.46, P, 0], [0.66, 0.50, P, 1],
		[0.16, 0.78, J, 2], [0.50, 0.82, P, 0], [0.84, 0.74, J, 0]],
	[[0.16, 0.16, P, 1], [0.44, 0.14, J, 0], [0.76, 0.18, P, 0], [0.28, 0.40, J, 2], [0.58, 0.38, P, 2],
		[0.86, 0.48, J, 1], [0.16, 0.66, P, 0], [0.44, 0.62, P, 1], [0.72, 0.72, J, 0], [0.34, 0.88, J, 1]],
]
const FOREST := [
	[[0.50, 0.50, PINE, 0]],
	[[0.32, 0.34, PINE, 1], [0.68, 0.66, PINE, 0]],
	[[0.30, 0.28, PINE, 0], [0.72, 0.40, FIR, 0], [0.42, 0.74, PINE, 2]],
	[[0.27, 0.27, PINE, 0], [0.73, 0.27, PINE, 2], [0.27, 0.73, FIR, 1], [0.73, 0.73, PINE, 1]],
	[[0.24, 0.24, PINE, 1], [0.74, 0.22, FIR, 0], [0.50, 0.52, PINE, 0], [0.24, 0.78, PINE, 2], [0.78, 0.76, FIR, 1]],
	[[0.20, 0.20, PINE, 0], [0.55, 0.17, FIR, 1], [0.84, 0.36, PINE, 2], [0.34, 0.50, PINE, 1],
		[0.70, 0.62, FIR, 0], [0.18, 0.80, FIR, 2], [0.52, 0.85, PINE, 0]],
	[[0.18, 0.18, PINE, 0], [0.50, 0.15, FIR, 1], [0.82, 0.20, PINE, 2], [0.16, 0.50, FIR, 0], [0.50, 0.48, PINE, 1],
		[0.84, 0.52, PINE, 0], [0.20, 0.84, PINE, 2], [0.52, 0.82, FIR, 2], [0.84, 0.84, PINE, 1]],
]

## Identical species/variant pairs share immutable rendering resources; each
## placement keeps its own transform, nodes and physical body.
static var _crowns: Dictionary = {}
static var _trunks: Dictionary = {}
static var _bark: Dictionary = {}
static var _crown_material_contracts: Dictionary = {}


## Plant the grove for a tree tile of `code` in the woodland or forest zone.
## The layout turns and mirrors per tile, and each tree faces its own way, so
## neighboring tiles of one density do not repeat.
static func add_grove(parent: Node3D, city: City, cell: Vector2i, code: int, zone: int) -> void:
	for placement: Array in grove(cell, code, zone):
		var tree := create(placement[1], placement[2])
		tree.position = CityGeometry3D.point_on_ground(city, cell, placement[0])
		tree.rotation.y = placement[3]
		parent.add_child(tree)


## [root offset, species, variant, yaw] per tree of a tile's grove.
static func grove(cell: Vector2i, code: int, zone: int) -> Array:
	var layouts: Array = FOREST if zone == VegetationZones.Zone.PINE else WOODLAND
	var trees: Array = layouts[clampi(code - Buildings.TREES_1, 0, layouts.size() - 1)]
	var seed := _hash(cell)
	var turn := seed & 3
	var mirror := (seed >> 2) & 1 == 1
	var out: Array = []
	for i: int in trees.size():
		var entry: Array = trees[i]
		var offset := Vector2(entry[0], entry[1]) - Vector2(0.5, 0.5)
		if mirror: offset.x = -offset.x
		for q: int in turn: offset = Vector2(-offset.y, offset.x)
		var yaw := float((seed >> (3 + i * 3)) & 7) * TAU / 8.0 + float(i) * 0.37
		out.append([offset + Vector2(0.5, 0.5), int(entry[2]), int(entry[3]), fmod(yaw, TAU)])
	return out


static func _hash(cell: Vector2i) -> int:
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


## One tree with its root at local ground level.
static func create(species: int, variant: int) -> Node3D:
	var size: Array = SIZES[species][variant]
	var height: float = size[0]
	var crown: float = size[1]
	var tree := Node3D.new()
	tree.name = "Tree"
	var upland := species >= Species.PINE
	var trunk_height := height * (0.92 if upland else 0.42)
	var trunk_radius := clampf(height * 0.022, 0.011, 0.026) if upland else crown * 0.13
	var key := [species, variant]
	var trunk := MeshInstance3D.new()
	if not _trunks.has(key):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = trunk_radius * (0.35 if upland else 0.7)
		cylinder.bottom_radius = trunk_radius
		cylinder.height = trunk_height
		cylinder.radial_segments = 6
		cylinder.rings = 1
		_trunks[key] = cylinder
	trunk.mesh = _trunks[key]
	trunk.position.y = trunk_height * 0.5
	if not _bark.has(species):
		_bark[species] = CityGeometry3D.material(BARK_COLORS[species])
	trunk.material_override = _bark[species]
	tree.add_child(trunk)
	# Walkers meet the trunk of a tall tree and the low bulk of a shrubby one.
	var body := StaticBody3D.new()
	body.name = "TreeTrunk"
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var volume := CylinderShape3D.new()
	volume.height = trunk_height if upland else height * 0.7
	volume.radius = trunk_radius if upland else crown * 0.45
	shape.shape = volume
	shape.position.y = volume.height * 0.5
	body.add_child(shape)
	tree.add_child(body)
	var crown_node := MeshInstance3D.new()
	if not _crowns.has(key):
		var mesh := _make_crown(species, variant, height, crown)
		_crowns[key] = mesh
		var material := mesh.surface_get_material(0) as ShaderMaterial
		_crown_material_contracts[material] = {"shader": material.shader, "code": material.shader.code}
	crown_node.mesh = _crowns[key]
	tree.add_child(crown_node)
	return tree


## Only our own cached crown materials qualify for static batching, under the
## same plain vertex-color contract as the palm crowns.
static func is_static_crown_material(material: Material) -> bool:
	if not material is ShaderMaterial or not _crown_material_contracts.has(material):
		return false
	var crown := material as ShaderMaterial
	var contract: Dictionary = _crown_material_contracts[material]
	return crown.shader == contract.shader and crown.shader.code == contract.code \
		and crown.next_pass == null \
		and crown.get_shader_parameter("surface_kind") == CityGeometry3D.SurfaceKind.DETAIL \
		and crown.get_shader_parameter("grain_strength") == 0.0


## Crown faces split into parts; the medium and far LODs keep fewer parts.
static func _make_crown(species: int, variant: int, height: float, radius: float) -> ArrayMesh:
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var parts: Array[Vector2i] = []
	var base: Color = CROWN_COLORS[species]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (species + 1) + 104729 * (variant + 1)
	var medium: Array = []
	var far: Array = []
	match species:
		Species.JUNIPER:
			# Three lumpy, overlapping masses on a short trunk.
			for blob: Array in [[Vector3(0, 0.56, 0), 0.78, 0.0], [Vector3(0.36, 0.48, 0.18), 0.6, -0.05], [Vector3(-0.28, 0.72, -0.24), 0.56, 0.05]]:
				var start := faces.size()
				var at: Vector3 = blob[0]
				var tone: float = blob[2]
				_blob(faces, colors, rng, Vector3(at.x * radius, at.y * height, at.z * radius), radius * float(blob[1]),
					height * 0.32 * float(blob[1]) / 0.78, base.lightened(tone) if tone >= 0.0 else base.darkened(-tone))
				parts.append(Vector2i(start, faces.size()))
			medium = [0, 1]
			far = [0]
		Species.PINYON:
			# A dense, rounded cone: a broad lower mass under a smaller top.
			for blob: Array in [[0.48, 1.0, 0.36], [0.74, 0.7, 0.26], [0.9, 0.38, 0.14]]:
				var start := faces.size()
				_blob(faces, colors, rng, Vector3(0, height * float(blob[0]), 0), radius * float(blob[1]), height * float(blob[2]), base.lightened(0.03 * parts.size()))
				parts.append(Vector2i(start, faces.size()))
			medium = [0, 1]
			far = [0, 1]
		_:
			# Stacked, slightly ragged tiers narrowing to a spire.
			var tiers := 5 if species == Species.PINE else 6
			var bottom := height * (0.36 if species == Species.PINE else 0.2)
			var step := (height - bottom) / float(tiers)
			for tier: int in tiers:
				var t := float(tier) / float(tiers - 1)
				var tier_radius := radius * lerpf(1.0, 0.32 if species == Species.PINE else 0.22, t)
				var y := bottom + step * tier
				var top := minf(height, y + step * 1.8)
				var start := faces.size()
				_tier(faces, colors, rng, y, top, tier_radius, base.lightened(0.025 * tier).darkened(0.06 if tier % 2 == 0 else 0.0))
				parts.append(Vector2i(start, faces.size()))
			medium = range(tiers).filter(func(i: int) -> bool: return i != 1 and i != tiers - 2)
			far = [0, 2, tiers - 1]
	var original := CityGeometry3D.mesh_from_faces(faces, colors)
	var mesh := ArrayMesh.new()
	var surface: Dictionary = original.get("_surfaces")[0].duplicate()
	surface["material"] = CityGeometry3D.surface_material()
	var identity := PackedInt32Array()
	for index: int in faces.size(): identity.append(index)
	surface.format = int(surface.format) | Mesh.ARRAY_FORMAT_INDEX
	surface.index_data = _indices_u16(identity)
	surface.index_count = identity.size()
	surface.lods = [radius * 0.12, _indices_u16(_part_indices(parts, medium)), radius * 0.3, _indices_u16(_part_indices(parts, far))]
	mesh.set("_surfaces", [surface])
	return mesh


## A low-poly, gently irregular ellipsoid: a jittered icosahedron.
static func _blob(faces: PackedVector3Array, colors: PackedColorArray, rng: RandomNumberGenerator, center: Vector3, radius: float, half_height: float, color: Color) -> void:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var points: Array[Vector3] = [Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1)]
	# The twenty faces: five around the top vertex, the band, five around the bottom.
	const TRIANGLES := [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	var scaled: Array[Vector3] = []
	for p: Vector3 in points:
		var n := p.normalized() * rng.randf_range(0.86, 1.1)
		# Flatten the underside a little so the mass sits on its branches.
		if n.y < 0.0: n.y *= 0.75
		scaled.append(center + Vector3(n.x * radius, n.y * half_height, n.z * radius))
	for face: Vector3i in TRIANGLES:
		var a := scaled[face.x]
		var b := scaled[face.z]
		var c := scaled[face.y]
		faces.append_array(PackedVector3Array([a, b, c]))
		var shade := color.darkened(0.12) if (a.y + b.y + c.y) / 3.0 < center.y else color.lightened(rng.randf_range(0.0, 0.06))
		colors.append_array(PackedColorArray([shade, shade, shade]))


## One conifer tier: a ragged eight-sided cone with a closed underside.
static func _tier(faces: PackedVector3Array, colors: PackedColorArray, rng: RandomNumberGenerator, y: float, top: float, radius: float, color: Color) -> void:
	const SIDES := 8
	var ring: Array[Vector3] = []
	var spin := rng.randf() * TAU
	for side: int in SIDES:
		var angle := spin + side * TAU / SIDES
		var r := radius * rng.randf_range(0.82, 1.08)
		ring.append(Vector3(cos(angle) * r, y - radius * rng.randf_range(0.08, 0.22), sin(angle) * r))
	var apex := Vector3(0, top, 0)
	var hub := Vector3(0, y + (top - y) * 0.18, 0)
	for side: int in SIDES:
		var a := ring[side]
		var b := ring[(side + 1) % SIDES]
		# Outward normals: mesh_from_faces takes (c - a) × (b - a).
		faces.append_array(PackedVector3Array([a, b, apex]))
		var lit := color.lightened(0.05) if side % 2 == 0 else color
		colors.append_array(PackedColorArray([lit.darkened(0.1), lit.darkened(0.1), lit.lightened(0.04)]))
		faces.append_array(PackedVector3Array([a, hub, b]))
		var under := color.darkened(0.3)
		colors.append_array(PackedColorArray([under, under, under]))


static func _part_indices(parts: Array[Vector2i], keep: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part: int in keep:
		for index: int in range(parts[part].x, parts[part].y): out.append(index)
	return out


static func _indices_u16(indices: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(indices.size() * 2)
	for i: int in indices.size(): bytes.encode_u16(i * 2, indices[i])
	return bytes
