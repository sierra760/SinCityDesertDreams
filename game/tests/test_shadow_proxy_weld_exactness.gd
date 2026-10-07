# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Welded runtime shadow proxies draw exactly the triangles of the unwelded
## proxy: for every catalog model, every proxy and every LOD level (base
## included) the ordered list of triangle corner positions is bit-identical,
## LOD thresholds are identical and only duplicate positions are removed.
extends "res://tests/test_case.gd"

const Compiler := preload("res://scripts/view/city_runtime_mesh_compiler.gd")


## Index list of one surface level (0 = base), decoded with the buffer's width.
static func _indices(mesh: ArrayMesh, level: int) -> PackedInt32Array:
	var data: Dictionary = mesh.get("_surfaces")[0]
	var count: int = int(data.index_count)
	var width: int = (data.index_data as PackedByteArray).size() / count
	var bytes: PackedByteArray = data.index_data if level == 0 else data.lods[level * 2 - 1]
	var result := PackedInt32Array()
	for j: int in range(0, bytes.size(), width):
		result.append(bytes.decode_u16(j) if width == 2 else bytes.decode_u32(j))
	return result


static func _thresholds(mesh: ArrayMesh) -> Array:
	var lods: Array = mesh.get("_surfaces")[0].get("lods", [])
	var result: Array = []
	for i: int in range(0, lods.size(), 2): result.append(lods[i])
	return result


## Bit-exact corner positions of every triangle at one level, in draw order.
static func _corners(mesh: ArrayMesh, level: int) -> PackedByteArray:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var corners := PackedVector3Array()
	for index: int in _indices(mesh, level): corners.append(vertices[index])
	return corners.to_byte_array()


static func _distinct_positions(mesh: ArrayMesh) -> int:
	var seen := {}
	for position: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		seen[var_to_bytes(position)] = true
	return seen.size()


## Every reference vertex mapped to the welded vertex with the bit-identical
## position (-1 when there is none). Equal mapped index lists then mean the
## same ordered triangle corners at the same exact positions.
static func _position_map(reference: ArrayMesh, welded: ArrayMesh) -> PackedInt32Array:
	var lookup := {}
	var welded_vertices: PackedVector3Array = welded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i: int in welded_vertices.size(): lookup[var_to_bytes(welded_vertices[i])] = i
	var result := PackedInt32Array()
	for position: Vector3 in reference.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var target: int = lookup.get(var_to_bytes(position), -1)
		result.append(target)
	return result


## Proxies follow their RuntimeSurfaces sibling; rebuild the unwelded proxy of
## each cull group from that mesh's surfaces (byte copies of the sources, in
## the same source/surface order the compiler grouped them).
func _check_scene(code: int, root: Node, totals: Dictionary) -> void:
	for parent: Node in [root] + root.find_children("*", "Node", true, false):
		var children := parent.get_children()
		for i: int in children.size():
			var visual := children[i] as MeshInstance3D
			if visual == null or visual.name != &"RuntimeSurfaces": continue
			var j := i + 1
			while j < children.size() and children[j] is MeshInstance3D and children[j].has_meta("runtime_shadow_proxy"):
				var proxy := children[j] as MeshInstance3D
				j += 1
				var cull: int = (proxy.mesh.surface_get_material(0) as BaseMaterial3D).cull_mode
				var parts: Array = []
				for surface: int in visual.mesh.get_surface_count():
					if (visual.get_active_material(surface) as BaseMaterial3D).cull_mode == cull:
						parts.append({"mesh": visual.mesh, "surface": surface})
				var reference := Compiler._shadow_mesh(parts, false)
				var welded := proxy.mesh as ArrayMesh
				totals.proxies += 1
				check(proxy.transform == visual.transform and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
					"model %d proxy keeps transform and shadow-only casting" % code)
				var thresholds := _thresholds(reference)
				check(_thresholds(welded) == thresholds, "model %d proxy keeps every LOD threshold" % code)
				var mapping := _position_map(reference, welded)
				check(not mapping.has(-1), "model %d every reference position exists bit-exactly in the welded proxy" % code)
				for level: int in thresholds.size() + 1:
					totals.levels += 1
					var expected := PackedInt32Array()
					for index: int in _indices(reference, level): expected.append(mapping[index])
					if _indices(welded, level) != expected:
						check(false, "model %d proxy level %d draws bit-identical triangles in order" % [code, level])
				var reference_vertices: int = reference.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
				var welded_vertices: int = welded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
				check_eq(welded_vertices, _distinct_positions(reference), "model %d proxy keeps exactly one vertex per distinct position" % code)
				check_eq(_distinct_positions(welded), welded_vertices, "model %d welded proxy has no duplicate position" % code)
				totals.vertices_before += reference_vertices
				totals.vertices_after += welded_vertices
				totals.index_bytes_before += _index_bytes(reference)
				totals.index_bytes_after += _index_bytes(welded)


static func _index_bytes(mesh: ArrayMesh) -> int:
	var data: Dictionary = mesh.get("_surfaces")[0]
	var total: int = (data.index_data as PackedByteArray).size()
	var lods: Array = data.get("lods", [])
	for i: int in range(1, lods.size(), 2): total += (lods[i] as PackedByteArray).size()
	return total


func test_every_catalog_proxy_draws_identical_triangles() -> void:
	var catalog := CityModelCatalog.new()
	catalog.compiled_cache_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK, "catalog loads")
	var totals := {"models": 0, "proxies": 0, "levels": 0, "vertices_before": 0, "vertices_after": 0, "index_bytes_before": 0, "index_bytes_after": 0}
	var codes: Array = catalog.entries.keys()
	codes.sort()
	for code: int in codes:
		var wrapper := catalog.instantiate_model(code)
		check(wrapper != null, "model %d instantiates" % code)
		if wrapper == null: continue
		totals.models += 1
		_check_scene(code, wrapper, totals)
		wrapper.free()
	print("Weld totals: ", totals)
	check_eq(totals.models, codes.size(), "every catalog model compared")
	check(totals.proxies >= codes.size(), "every catalog model has a runtime shadow proxy")
	check(totals.vertices_after < totals.vertices_before, "welding removes duplicate shadow vertices")
	check(totals.index_bytes_after <= totals.index_bytes_before, "welding never widens index buffers")


func test_weld_keeps_signed_zero_positions_distinct() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	# A literal -0.0 folds to +0.0; decode the IEEE negative-zero bit pattern.
	var nz := PackedByteArray([0, 0, 0, 0x80]).decode_float(0)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0.0, 1, 1), Vector3(nz, 1, 1), Vector3(1, 2, 3),
		Vector3(0.0, 1, 1), Vector3(1, 2, 3), Vector3(1, 0.0, 2), Vector3(1, nz, 2), Vector3(nz, 1, 1), Vector3(1, 2, 4)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 8, 5, 6, 8, 7, 2, 8])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.5: PackedInt32Array([3, 1, 4])})
	var reference := Compiler._shadow_mesh([{"mesh": mesh, "surface": 0}], false)
	var welded := Compiler._shadow_mesh([{"mesh": mesh, "surface": 0}], true)
	check_eq(_corners(welded, 0), _corners(reference, 0), "base triangles bit-identical")
	check_eq(_corners(welded, 1), _corners(reference, 1), "LOD triangles bit-identical")
	# (+0,1,1) (-0,1,1) (1,2,3) (1,+0,2) (1,-0,2) (1,2,4): six positions of nine.
	check_eq(welded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 6, "signed zeros stay distinct; bit-equal duplicates merge")
	check_eq(_distinct_positions(reference), 6, "reference has six distinct bit patterns")


func test_multi_part_offsets_remap_across_parts() -> void:
	var box := BoxMesh.new()
	var arrays := box.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := ArrayMesh.new()
	var b := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {1.0: indices.slice(0, 18)})
	var moved := arrays.duplicate()
	var shifted := PackedVector3Array()
	for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]: shifted.append(p + Vector3(1.0, 0, 0))
	moved[Mesh.ARRAY_VERTEX] = shifted
	b.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, moved, [], {2.0: indices.slice(0, 6)})
	var parts := [{"mesh": a, "surface": 0}, {"mesh": b, "surface": 0}]
	var reference := Compiler._shadow_mesh(parts, false)
	var welded := Compiler._shadow_mesh(parts, true)
	check_eq(_thresholds(welded), _thresholds(reference), "same LOD thresholds")
	for level: int in 3:
		check_eq(_corners(welded, level), _corners(reference, level), "level %d bit-identical" % level)
	# Two unit boxes one unit apart share their four x=0.5 corners: 8 + 8 - 4.
	check_eq(welded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 12, "one vertex per distinct position across parts")
	check_eq(_distinct_positions(reference), 12, "reference box pair has twelve distinct corners")
