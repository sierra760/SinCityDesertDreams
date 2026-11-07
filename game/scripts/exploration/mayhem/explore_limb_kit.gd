# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The six loose pieces a struck pedestrian pops into: head, torso, two arms
## and two legs. Each crowd variant's authored detail model is split once by
## the bone that most influences each triangle, in its standing rest pose, and
## the result is shared by every pedestrian of that variant. Pieces are in tile
## units (one tile is sixteen metres) about their own centre; `rest` places a
## piece relative to the pedestrian's feet. Variants without a detail model
## split the catalog crowd mesh by height and width instead.
class_name ExploreLimbKit
extends RefCounted

const PARTS: Array[StringName] = [&"head",&"torso",&"left_arm",&"right_arm",&"left_leg",&"right_leg"]
const _BONE_PARTS := {"Neck":0,"Head":0,"Root":1,"Hips":1,"Spine":1,"Chest":1,
	"LeftUpperArm":2,"LeftForearm":2,"LeftHand":2,"RightUpperArm":3,"RightForearm":3,"RightHand":3,
	"LeftThigh":4,"LeftShin":4,"LeftFoot":4,"RightThigh":5,"RightShin":5,"RightFoot":5}
static var _kits: Dictionary = {}

## The variant's pieces: {"part","mesh","rest","half"} per non-empty part, where
## `half` is the piece's half extent. The same arrays are returned every call.
static func pieces(variant: int) -> Array[Dictionary]:
	var key := posmod(variant,CityTrafficCatalog.pedestrian_variants())
	if _kits.has(key): return _kits[key]
	var kit := _from_detail(key)
	if kit.is_empty(): kit = _from_crowd(key)
	_kits[key] = kit
	return kit

static func _from_detail(variant: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var path := CityTrafficCatalog.ASSET_ROOT+"pedestrian_%02d_detail.glb" % variant
	if not ResourceLoader.exists(path,"PackedScene"): return result
	var scene := load(path) as PackedScene
	if scene == null: return result
	var instance := scene.instantiate()
	var skeletons := instance.find_children("*","Skeleton3D",true,false)
	var meshes := instance.find_children("*","MeshInstance3D",true,false)
	if skeletons.is_empty() or meshes.is_empty() or not instance is Node3D:
		instance.free()
		return result
	var skeleton := skeletons[0] as Skeleton3D
	var model := meshes[0] as MeshInstance3D
	if model.mesh == null or model.skin == null:
		instance.free()
		return result
	# Feet-relative tile space: the authored metres scale down once, exactly as
	# the nearby crowd visual does, through any armature scale on the way.
	var to_tile := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE/CityTrafficCatalog.METRES_PER_TILE),Vector3.ZERO)*_relative(instance as Node3D,skeleton)
	var skin := model.skin
	var binds: Array[Transform3D] = []
	var bind_parts := PackedInt32Array()
	for bind: int in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
		var rest := skeleton.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		binds.append(to_tile*rest*skin.get_bind_pose(bind))
		bind_parts.append(int(_BONE_PARTS.get(String(skeleton.get_bone_name(bone)) if bone >= 0 else "",1)))
	var builders: Array[Dictionary] = []
	for part in PARTS.size(): builders.append({})
	for surface: int in model.mesh.get_surface_count():
		var arrays := model.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var count := vertices.size()
		var influences := bones.size()/count if count > 0 else 0
		if influences <= 0 or weights.size() != bones.size(): continue
		var posed := PackedVector3Array()
		posed.resize(count)
		var posed_normals := PackedVector3Array()
		posed_normals.resize(count)
		var vertex_parts := PackedInt32Array()
		vertex_parts.resize(count)
		for index: int in count:
			var at := Vector3.ZERO
			var normal := Vector3.ZERO
			var best := -1.0
			var part := 1
			var total := 0.0
			for slot: int in influences:
				var weight := weights[index*influences+slot]
				var bind := bones[index*influences+slot]
				if weight <= 0.0 or bind < 0 or bind >= binds.size(): continue
				at += binds[bind]*vertices[index]*weight
				if not normals.is_empty(): normal += (binds[bind].basis*normals[index])*weight
				total += weight
				if weight > best:
					best = weight
					part = bind_parts[bind]
			posed[index] = at/total if total > 0.0 else to_tile*vertices[index]
			posed_normals[index] = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
			vertex_parts[index] = part
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(count))
		_split_surface(builders,indices,posed,posed_normals,uvs,vertex_parts,model.get_active_material(surface))
	instance.free()
	return _commit(builders)

## Without a rig, the low crowd mesh splits at the same heights and widths its
## gait shader animates: legs below the hip, arms outside the shoulders.
static func _from_crowd(variant: int) -> Array[Dictionary]:
	var mesh := CityTrafficCatalog.mesh_for(&"pedestrian",variant)
	if mesh == null: return [] as Array[Dictionary]
	var bounds := mesh.get_aabb()
	var height := maxf(bounds.size.y,.000001)
	var half_width := maxf(maxf(absf(bounds.position.x),absf(bounds.end.x)),.000001)
	var builders: Array[Dictionary] = []
	for part in PARTS.size(): builders.append({})
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var vertex_parts := PackedInt32Array()
		vertex_parts.resize(vertices.size())
		for index: int in vertices.size():
			var at := vertices[index]
			var relative := (at.y-bounds.position.y)/height
			var part := 1
			if relative > .86: part = 0
			elif relative < .45: part = 4 if at.x < 0.0 else 5
			elif absf(at.x) > half_width*.58: part = 2 if at.x < 0.0 else 3
			vertex_parts[index] = part
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
		var material := mesh.surface_get_material(surface)
		var flat := StandardMaterial3D.new()
		if material is ShaderMaterial: flat.albedo_color = (material as ShaderMaterial).get_shader_parameter("tint")
		elif material is BaseMaterial3D: flat = material as StandardMaterial3D
		flat.roughness = .72
		_split_surface(builders,indices,vertices,normals,uvs,vertex_parts,flat)
	return _commit(builders)

## Assign each triangle to the part most of its corners belong to, and append
## it to that part's copy of this surface.
static func _split_surface(builders: Array[Dictionary], indices: PackedInt32Array, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, vertex_parts: PackedInt32Array, material: Material) -> void:
	var key := material.get_instance_id() if material != null else 0
	# Packed arrays are values: fill locals, then store each part once.
	var out_vertices: Array[PackedVector3Array] = []
	var out_normals: Array[PackedVector3Array] = []
	var out_uvs: Array[PackedVector2Array] = []
	for part in builders.size():
		out_vertices.append(PackedVector3Array())
		out_normals.append(PackedVector3Array())
		out_uvs.append(PackedVector2Array())
	for corner: int in range(0,indices.size()-2,3):
		var a := vertex_parts[indices[corner]]
		var b := vertex_parts[indices[corner+1]]
		var c := vertex_parts[indices[corner+2]]
		var part := b if b == c else a
		for offset: int in 3:
			var source := indices[corner+offset]
			out_vertices[part].append(vertices[source])
			out_normals[part].append(normals[source] if source < normals.size() else Vector3.UP)
			out_uvs[part].append(uvs[source] if source < uvs.size() else Vector2.ZERO)
	for part: int in builders.size():
		if out_vertices[part].is_empty(): continue
		var surfaces: Dictionary = builders[part]
		if not surfaces.has(key):
			surfaces[key] = {"material":material,"vertices":out_vertices[part],"normals":out_normals[part],"uvs":out_uvs[part]}
			continue
		var target: Dictionary = surfaces[key]
		var merged_vertices: PackedVector3Array = target.vertices
		merged_vertices.append_array(out_vertices[part])
		var merged_normals: PackedVector3Array = target.normals
		merged_normals.append_array(out_normals[part])
		var merged_uvs: PackedVector2Array = target.uvs
		merged_uvs.append_array(out_uvs[part])
		target.vertices = merged_vertices
		target.normals = merged_normals
		target.uvs = merged_uvs

static func _commit(builders: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: int in builders.size():
		var surfaces: Dictionary = builders[part]
		if surfaces.is_empty(): continue
		var bounds := AABB()
		var first := true
		for entry: Dictionary in surfaces.values():
			for vertex: Vector3 in entry.vertices:
				if first:
					bounds = AABB(vertex,Vector3.ZERO)
					first = false
				else: bounds = bounds.expand(vertex)
		var center := bounds.get_center()
		var mesh := ArrayMesh.new()
		for entry: Dictionary in surfaces.values():
			var vertices: PackedVector3Array = entry.vertices
			for index: int in vertices.size(): vertices[index] -= center
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = entry.normals
			arrays[Mesh.ARRAY_TEX_UV] = entry.uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(mesh.get_surface_count()-1,entry.material)
		result.append({"part":PARTS[part],"mesh":mesh,"rest":Transform3D(Basis.IDENTITY,center),"half":bounds.size*.5})
	return result

static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D: chain = (current as Node3D).transform*chain
		current = current.get_parent()
	return chain
