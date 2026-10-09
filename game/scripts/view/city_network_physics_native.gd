# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Dispatches physical surface extraction to the native geometry kernel on
## Apple platforms and x86_64 Windows, and to the GDScript resolver everywhere
## else. Both paths
## produce the same results; the kernel only removes the GDScript cost.
extends RefCounted

const CONFIG := "res://addons/scdd_geometry/scdd_geometry.cfg"
const NATIVE_CLASS := &"SCDDNetworkPhysics"
const Fallback := preload("res://scripts/view/city_network_physics.gd")

## Tests force the GDScript path to compare it against the native path.
static var force_fallback := false
static var _load_attempted := false


static func available() -> bool:
	if force_fallback: return false
	if not supported_platform(): return false
	if not ClassDB.class_exists(NATIVE_CLASS) and not _load_attempted:
		_load_attempted = true
		var status := GDExtensionManager.load_extension(CONFIG)
		if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]: return false
	return ClassDB.class_exists(NATIVE_CLASS)


## Platforms that ship a kernel library (see scdd_geometry.cfg).
static func supported_platform() -> bool:
	return OS.get_name() in ["macOS","iOS"] or (OS.get_name()=="Windows" and OS.has_feature("x86_64"))


static func resolve(patch_inputs: Array[Dictionary], box_inputs: Array[Dictionary], obstacle_inputs: PackedVector3Array) -> Dictionary:
	if not available(): return Fallback.resolve(patch_inputs, box_inputs, obstacle_inputs)
	var packed := pack_patches(patch_inputs)
	return _resolve_native(packed[0], packed[1], packed[2], packed[3], packed[4], box_inputs, obstacle_inputs)


## Packed patches: cells hold two ints per patch, triangles three points per patch.
static func resolve_packed(cells: PackedInt32Array, groups: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array, box_inputs: Array[Dictionary], obstacle_inputs: PackedVector3Array) -> Dictionary:
	if available(): return _resolve_native(cells, groups, roles, depths, triangles, box_inputs, obstacle_inputs)
	return Fallback.resolve(unpack_patches(cells, groups, roles, depths, triangles), box_inputs, obstacle_inputs)


## Returns [cells, groups, roles, depths, triangles] for the native entry point.
static func pack_patches(patch_inputs: Array[Dictionary]) -> Array:
	var count := patch_inputs.size()
	var cells := PackedInt32Array(); cells.resize(count*2)
	var groups := PackedInt32Array(); groups.resize(count)
	var roles := PackedInt32Array(); roles.resize(count)
	var depths := PackedFloat64Array(); depths.resize(count)
	var triangles := PackedVector3Array(); triangles.resize(count*3)
	for index: int in count:
		var patch: Dictionary = patch_inputs[index]
		var cell: Vector2i = patch.cell
		cells[index*2] = cell.x; cells[index*2+1] = cell.y
		groups[index] = patch.group; roles[index] = patch.role; depths[index] = patch.depth
		var triangle: PackedVector3Array = patch.triangle
		triangles[index*3] = triangle[0]; triangles[index*3+1] = triangle[1]; triangles[index*3+2] = triangle[2]
	return [cells, groups, roles, depths, triangles]


static func unpack_patches(cells: PackedInt32Array, groups: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	for index: int in depths.size():
		patches.append({"cell": Vector2i(cells[index*2], cells[index*2+1]), "group": groups[index], "role": roles[index],
			"triangle": PackedVector3Array([triangles[index*3], triangles[index*3+1], triangles[index*3+2]]), "depth": depths[index]})
	return patches


static func _resolve_native(cells: PackedInt32Array, groups: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array, box_inputs: Array[Dictionary], obstacle_inputs: PackedVector3Array) -> Dictionary:
	var result: Dictionary = ClassDB.class_call_static(NATIVE_CLASS, &"resolve_packed", cells, groups, roles, depths, triangles, obstacle_inputs)
	result["physical_boxes"] = box_inputs.duplicate(true)
	return result


## Per-group resolution for the incremental resolver (see city_network_physics.gd).
static func resolve_detailed(cells: PackedInt32Array, groups: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array, with_walls: bool) -> Dictionary:
	if available(): return ClassDB.class_call_static(NATIVE_CLASS, &"resolve_detailed", cells, groups, roles, depths, triangles, with_walls)
	return Fallback.resolve_detailed(cells, groups, roles, depths, triangles, with_walls)


## Deck boundary walls of an ordered group subset, attributed per group.
static func resolve_boundaries(deck: PackedVector3Array, deck_depths: PackedFloat64Array, deck_ends: PackedInt32Array) -> Dictionary:
	if available(): return ClassDB.class_call_static(NATIVE_CLASS, &"resolve_boundaries", deck, deck_depths, deck_ends)
	return Fallback.resolve_boundaries(deck, deck_depths, deck_ends)


## Concatenates [source, begin, end) runs; a plain copy, identical on both paths.
static func splice_vector3(sources: Array, runs: PackedInt32Array) -> PackedVector3Array:
	if available(): return ClassDB.class_call_static(NATIVE_CLASS, &"splice_vector3", sources, runs)
	var result := PackedVector3Array()
	for r: int in range(0, runs.size(), 3):
		var source: PackedVector3Array = sources[runs[r]]
		result.append_array(source.slice(runs[r+1], runs[r+2]))
	return result


static func splice_float64(sources: Array, runs: PackedInt32Array) -> PackedFloat64Array:
	if available(): return ClassDB.class_call_static(NATIVE_CLASS, &"splice_float64", sources, runs)
	var result := PackedFloat64Array()
	for r: int in range(0, runs.size(), 3):
		var source: PackedFloat64Array = sources[runs[r]]
		result.append_array(source.slice(runs[r+1], runs[r+2]))
	return result


## Exact group-by-group comparison of two patch sets (bitwise values).
static func diff_groups(old_cells: PackedInt32Array, old_groups: PackedInt32Array, old_roles: PackedInt32Array, old_depths: PackedFloat64Array, old_triangles: PackedVector3Array,
		cells: PackedInt32Array, groups: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array) -> Dictionary:
	if available(): return ClassDB.class_call_static(NATIVE_CLASS, &"diff_groups", old_cells, old_groups, old_roles, old_depths, old_triangles, cells, groups, roles, depths, triangles)
	return Fallback.diff_groups(old_cells, old_groups, old_roles, old_depths, old_triangles, cells, groups, roles, depths, triangles)
