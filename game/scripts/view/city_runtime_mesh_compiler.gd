# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Runtime-only compilation of static imported mesh leaves into multi-surface meshes.
## Source GLBs and all collision nodes are never modified.
## Compatible means identical local transform and rendering state, NOT similar color.
## Surface buffers (including compression, LOD indices and shadow meshes) are copied
## byte-for-byte using ArrayMesh's serialized surface representation. No rebaking.
## One combined culling AABB replaces per-part AABBs; automatic LOD distance is
## consequently evaluated against that group. Surface LOD thresholds are kept.
extends RefCounted

const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
## Bump whenever compiled output changes; it keys the on-disk compiled cache.
const VERSION := 2

static func compile(source: Node3D, consolidate_shadows: bool = false) -> PackedScene:
	# Dynamic/animated imported scenes rely on their source node paths.
	if _has_behavior(source):
		return null
	_consolidate(source, consolidate_shadows)
	_own_children(source, source)
	var packed := PackedScene.new()
	return packed if packed.pack(source) == OK else null

static func _has_behavior(node: Node) -> bool:
	if node.get_script() != null or node is AnimationMixer: return true
	for child: Node in node.get_children():
		if _has_behavior(child): return true
	return false

static func _own_children(node: Node, owner_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_root
		_own_children(child, owner_root)

static func _consolidate(parent: Node, consolidate_shadows: bool) -> void:
	var groups := {}
	for child: Node in parent.get_children():
		if child is MeshInstance3D and _supported(child):
			var key: Array = [child.transform, child.mesh.shadow_mesh != null,
				child.material_override, child.material_overlay]
			for property: StringName in Batcher.COPY_PROPERTIES:
				key.append(child.get(property))
			if not groups.has(key): groups[key] = []
			groups[key].append(child)
		else:
			_consolidate(child, consolidate_shadows)
	for sources: Array in groups.values():
		if sources.size() < 2: continue
		var first: MeshInstance3D = sources[0]
		var surfaces: Array = []
		var shadow_surfaces: Array = []
		var source_node_names: Array[String] = []
		for instance: MeshInstance3D in sources:
			# One serialized surface table per mesh; reading it per surface would
			# serialize every buffer of the mesh once per surface.
			var instance_surfaces: Array = instance.mesh.get("_surfaces")
			for index: int in instance.mesh.get_surface_count():
				var surface: Dictionary = instance_surfaces[index].duplicate()
				surface.material = instance.get_active_material(index)
				surfaces.append(surface)
				source_node_names.append(String(instance.name))
			if instance.mesh.shadow_mesh != null:
				shadow_surfaces.append_array(instance.mesh.shadow_mesh.get("_surfaces"))
		# Godot limits ArrayMesh to 256 surfaces. Unusual imports stay unchanged.
		if surfaces.size() > 256 or shadow_surfaces.size() > 256: continue
		var mesh := ArrayMesh.new()
		mesh.set("_surfaces", surfaces)
		if mesh.get_surface_count() != surfaces.size(): continue
		if not shadow_surfaces.is_empty():
			var shadow := ArrayMesh.new()
			shadow.set("_surfaces", shadow_surfaces)
			mesh.shadow_mesh = shadow
		var replacement := MeshInstance3D.new()
		replacement.name = "RuntimeSurfaces"
		replacement.mesh = mesh
		replacement.set_meta("source_node_names", source_node_names)
		replacement.transform = first.transform
		replacement.material_overlay = first.material_overlay
		for property: StringName in Batcher.COPY_PROPERTIES:
			replacement.set(property, first.get(property))
		parent.add_child(replacement)
		if consolidate_shadows:
			var proxies := _shadow_proxies(sources)
			if not proxies.is_empty():
				replacement.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for proxy: MeshInstance3D in proxies: parent.add_child(proxy)
		for instance: MeshInstance3D in sources:
			parent.remove_child(instance)
			instance.free()

static func _supported(instance: MeshInstance3D) -> bool:
	if not instance.mesh is ArrayMesh or instance.get_child_count() != 0 or not instance.visible:
		return false
	if instance.get_script() != null or instance.skin != null or not instance.skeleton.is_empty():
		return false
	if instance.mesh.get_blend_shape_count() != 0 or instance.custom_aabb != AABB():
		return false
	if instance.visibility_range_begin != 0 or instance.visibility_range_end != 0 or not instance.visibility_parent.is_empty():
		return false
	if instance.transparency != 0 or instance.material_overlay != null:
		return false
	for index: int in instance.mesh.get_surface_count():
		var material := instance.get_active_material(index)
		# World/object-dependent custom shaders and sorted transparent geometry
		# must retain independent instance bounds and draw ordering.
		if material is ShaderMaterial or not Batcher._material_supported(material):
			return false
	return true


## Shadow submissions do not need the visible material boundaries. Only opaque
## standard materials with no vertex displacement qualify. Visible triangle
## positions are decoded once because Godot 4.6 compressed position-only import
## shadows do not expose vertices through surface_get_arrays(). Source import
## shadow buffers remain intact on the visual mesh. Close silhouettes use every
## source triangle in its orientation; each distant level combines the source LOD indices.
static func _shadow_proxies(sources: Array) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var first: MeshInstance3D = sources[0]
	if first.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON: return result
	var groups := {}
	for source: MeshInstance3D in sources:
		for surface: int in source.mesh.get_surface_count():
			var material := source.get_active_material(surface) as BaseMaterial3D
			if material == null or material.grow or material.next_pass != null \
				or material.proximity_fade_enabled or material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED \
				or source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return result
			var cull := material.cull_mode
			if not groups.has(cull): groups[cull] = []
			groups[cull].append({"mesh": source.mesh, "surface": surface})
	for cull: int in groups:
		var mesh := _shadow_mesh(groups[cull], true)
		if mesh == null:
			for proxy: MeshInstance3D in result: proxy.free()
			return []
		var material := StandardMaterial3D.new()
		material.cull_mode = cull
		mesh.surface_set_material(0, material)
		var proxy := MeshInstance3D.new()
		proxy.name = "RuntimeShadow"
		proxy.mesh = mesh
		proxy.transform = first.transform
		for property: StringName in Batcher.COPY_PROPERTIES: proxy.set(property, first.get(property))
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		proxy.set_meta("runtime_shadow_proxy", true)
		result.append(proxy)
	return result


## With `weld`, vertices sharing a bit-identical position become one vertex,
## as Godot's own import shadow meshes do; every triangle, its winding and each
## LOD index list keep the same positions in the same order, so depth output is
## unchanged while shadow passes shade and store far fewer vertices.
static func _shadow_mesh(parts: Array, weld: bool = false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var base_indices := PackedInt32Array()
	var levels: Array[Dictionary] = []
	var thresholds := {}
	var welded := {}
	for part: Dictionary in parts:
		var mesh: ArrayMesh = part.mesh
		var surface: int = part.surface
		var arrays := mesh.surface_get_arrays(surface)
		if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return null
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset := vertices.size()
		var remap := PackedInt32Array()
		if weld:
			remap.resize(source_vertices.size())
			for i: int in source_vertices.size():
				var key: Variant = _weld_key(source_vertices[i])
				var target: int = welded.get(key, -1)
				if target < 0:
					target = vertices.size()
					welded[key] = target
					vertices.append(source_vertices[i])
				remap[i] = target
		else:
			vertices.append_array(source_vertices)
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if source_indices.is_empty():
			for index: int in source_vertices.size(): source_indices.append(index)
		if weld:
			for index: int in source_indices: base_indices.append(remap[index])
		else:
			for index: int in source_indices: base_indices.append(index + offset)
		var choices: Dictionary = {0.0: source_indices}
		var data: Dictionary = mesh.get("_surfaces")[surface]
		var lods: Array = data.get("lods", [])
		var width := 2 if source_vertices.size() <= 65536 else 4
		for i: int in range(0, lods.size(), 2):
			var edge: float = lods[i]
			var bytes: PackedByteArray = lods[i+1]
			var indices := PackedInt32Array()
			for j: int in range(0, bytes.size(), width):
				indices.append(bytes.decode_u16(j) if width == 2 else bytes.decode_u32(j))
			choices[edge] = indices
			thresholds[edge] = true
		levels.append({"offset": offset, "remap": remap, "choices": choices})
	var combined_lods := {}
	var ordered := thresholds.keys()
	ordered.sort()
	for edge: float in ordered:
		var indices := PackedInt32Array()
		for level: Dictionary in levels:
			var selected := 0.0
			for threshold: float in level.choices:
				if threshold <= edge and threshold > selected: selected = threshold
			if weld:
				var remap: PackedInt32Array = level.remap
				for index: int in level.choices[selected]: indices.append(remap[index])
			else:
				for index: int in level.choices[selected]: indices.append(index + int(level.offset))
		combined_lods[edge] = indices
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = base_indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], combined_lods)
	return result


## Exact position identity. Dictionary key comparison joins -0.0 with 0.0 and
## any NaN with any NaN, so zero or non-finite components key by encoded bits.
static func _weld_key(position: Vector3) -> Variant:
	if position.x != 0.0 and position.y != 0.0 and position.z != 0.0 and position.is_finite():
		return position
	return var_to_bytes(position)
