# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Static-mesh instancing for city visuals, with spatially bounded culling.
## Physical bodies and query proxies stay in their own hierarchy. Shader-driven,
## animated and manually distance-faded visuals are left as they are.
extends Node3D

const DEFAULT_CHUNK_SIZE := 32
const RegionIndex := preload("res://scripts/view/city_region_index_2d.gd")
const Palm := preload("res://scripts/view/city_palm_3d.gd")
const COPY_PROPERTIES: Array[StringName] = [
	&"layers", &"cast_shadow", &"extra_cull_margin", &"gi_mode",
	&"gi_lightmap_scale", &"gi_lightmap_texel_scale", &"lod_bias",
	&"ignore_occlusion_culling", &"transparency",
]

var statistics: Dictionary = {}
## Per-collection memo of whether a shared mesh resource's own surface materials
## are all supported; instance overrides are still examined per source.
var _mesh_material_support: Dictionary = {}
var _domain_visibility: Dictionary = {}
var _chunk_size := DEFAULT_CHUNK_SIZE
## Source roots of the completed batching, in their given order.
var _roots: Array[Node3D] = []
## One weakly owned inventory per direct child of a root (a "branch"): its root
## index, ownership region, actual descendant mesh chunks/cells, mesh count and
## eligible member records in depth-first order.
var _branches: Dictionary = {}
## Group key -> {source id: member record} in join order. A group's batch is
## remade only when a member leaves or joins; untouched groups keep their
## uploaded instances.
var _groups: Dictionary = {}
## Group key -> attached batch node.
var _batches: Dictionary = {}
## Hidden source id -> WeakRef. Every hidden source belongs to exactly one batch.
var _hidden: Dictionary = {}
## Branches that are not declared immutable with an explicit region: every
## update re-examines them. A live immutable branch that has not left the tree
## since it was indexed needs nothing, so updates visit only these plus the
## branches the roots reported leaving, in the same inventory order.
var _dynamic: Dictionary = {}
## Branch id -> true for children the roots reported leaving the tree, and
## id -> WeakRef for children that entered, since the last completed update.
## They are complete only while `_tracked`: every root was inside the tree when
## the inventory was last made whole, so no child could leave or join unseen.
var _exited: Dictionary = {}
var _entered: Dictionary = {}
var _tracked := false
var _watched: Array[Node] = []
var _serial := 0
## Chunk -> {branch id: true} for every chunk a branch's meshes occupy, and
## chunk -> {group key: true}; statistics sum over the changed chunks only.
var _chunk_branches: Dictionary = {}
var _chunk_groups: Dictionary = {}


## Restore any still-live source meshes before removing their replacements.
func clear() -> void:
	_restore_sources()
	_branches.clear()
	_groups.clear()
	_batches.clear()
	_reset_indices()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	statistics = {"source_meshes": 0, "eligible_meshes": 0, "batched_instances": 0, "batches": 0}


func _exit_tree() -> void:
	_restore_sources()
	_branches.clear()
	_groups.clear()
	_batches.clear()
	_reset_indices()


func _reset_indices() -> void:
	_dynamic.clear()
	_exited.clear()
	_entered.clear()
	_chunk_branches.clear()
	_chunk_groups.clear()
	_tracked = false


func _restore_sources() -> void:
	for reference: WeakRef in _hidden.values():
		var source: Variant = reference.get_ref()
		if is_instance_valid(source):
			source.visible = true
	_hidden.clear()


## Call after all lot/world transforms are final. These roots must be static
## city geometry; a later geometry rebuild clears and rebuilds the batches.
func rebuild(roots: Array[Node3D], chunk_size: int = DEFAULT_CHUNK_SIZE) -> Dictionary:
	clear()
	if not is_inside_tree() or chunk_size <= 0:
		return statistics.duplicate()
	_chunk_size = chunk_size
	_roots = roots.duplicate()
	_watch_roots()
	_mesh_material_support.clear()
	var dirty: Dictionary = {}
	for root_index: int in _roots.size():
		var source_root: Node3D = _roots[root_index]
		if source_root == null: continue
		for branch: Node in source_root.get_children():
			var inventory := _index_branch(branch, root_index, {}, {})
			_set_branch(branch.get_instance_id(), inventory)
			_join_members(inventory, dirty)
			statistics.source_meshes += int(inventory.meshes)
			statistics.eligible_meshes += inventory.members.size()
	_mesh_material_support.clear()
	_remake_groups(dirty)
	_finish_tracking()
	return statistics.duplicate()


## Observe the roots' direct children leaving and entering the tree.
func _watch_roots() -> void:
	for watched: Node in _watched:
		if is_instance_valid(watched):
			if watched.child_exiting_tree.is_connected(_on_root_child_exiting): watched.child_exiting_tree.disconnect(_on_root_child_exiting)
			if watched.child_entered_tree.is_connected(_on_root_child_entered): watched.child_entered_tree.disconnect(_on_root_child_entered)
	_watched.clear()
	for source_root: Variant in _roots:
		if not is_instance_valid(source_root) or source_root.child_exiting_tree.is_connected(_on_root_child_exiting): continue
		source_root.child_exiting_tree.connect(_on_root_child_exiting)
		source_root.child_entered_tree.connect(_on_root_child_entered)
		_watched.append(source_root)


func _on_root_child_exiting(node: Node) -> void:
	_exited[node.get_instance_id()] = true


func _on_root_child_entered(node: Node) -> void:
	_entered[node.get_instance_id()] = weakref(node)


func _roots_in_tree() -> bool:
	for source_root: Variant in _roots:
		if source_root == null: continue
		if not is_instance_valid(source_root) or not source_root.is_inside_tree(): return false
	return true


## The inventory now describes every child of every root.
func _finish_tracking() -> void:
	_exited.clear()
	_entered.clear()
	_tracked = _roots_in_tree()


func _set_branch(id: int, inventory: Dictionary) -> void:
	if _branches.has(id):
		inventory.serial = _branches[id].serial
		_unlist_branch_chunks(id, _branches[id])
	else:
		_serial += 1
		inventory.serial = _serial
	_branches[id] = inventory
	for chunk: Vector2i in inventory.chunks:
		if not _chunk_branches.has(chunk): _chunk_branches[chunk] = {}
		_chunk_branches[chunk][id] = true
	var owner: Variant = inventory.owner.get_ref()
	if inventory.explicit and is_instance_valid(owner) and owner.get_meta("batch_immutable", false): _dynamic.erase(id)
	else: _dynamic[id] = true


func _erase_branch(id: int) -> void:
	_unlist_branch_chunks(id, _branches[id])
	_branches.erase(id)
	_dynamic.erase(id)


func _unlist_branch_chunks(id: int, inventory: Dictionary) -> void:
	for chunk: Vector2i in inventory.chunks:
		var listed: Dictionary = _chunk_branches.get(chunk, {})
		listed.erase(id)
		if listed.is_empty(): _chunk_branches.erase(chunk)


## Branch ids an update must examine, in inventory order. Untracked, all.
func _update_candidates(tracked: bool) -> Array:
	if not tracked: return _branches.keys()
	var by_serial: Dictionary = {}
	for collection: Dictionary in [_dynamic, _exited]:
		for id: int in collection:
			if _branches.has(id): by_serial[int(_branches[id].serial)] = id
	var serials := PackedInt64Array(by_serial.keys())
	serials.sort()
	var ids: Array = []
	for serial: int in serials: ids.append(by_serial[serial])
	return ids


## New direct children of the roots in root order, then child order.
func _new_branches(tracked: bool) -> Array:
	var found: Array = []
	if not tracked:
		for root_index: int in _roots.size():
			var source_root: Node3D = _roots[root_index]
			if source_root == null: continue
			for branch: Node in source_root.get_children():
				if not _branches.has(branch.get_instance_id()): found.append([root_index, branch])
		return found
	var keyed: Dictionary = {}
	for id: int in _entered:
		if _branches.has(id): continue
		var branch: Variant = _entered[id].get_ref()
		if not is_instance_valid(branch): continue
		var parent: Node = branch.get_parent()
		var root_index := _roots.find(parent) if parent != null else -1
		if root_index < 0: continue
		var child_index: int = branch.get_index()
		keyed[(root_index << 32) | child_index] = [root_index, branch]
	var order := PackedInt64Array(keyed.keys())
	order.sort()
	for key: int in order: found.append(keyed[key])
	return found


## Replace only the groups whose membership changed. Branches whose ownership
## region or actual mesh cells meet `regions` are visited again; freed branches
## leave their groups; new direct children of the roots join. Members of other
## branches keep their uploaded instances. The result matches a full rebuild.
func update_regions(roots: Array[Node3D], regions: Array[Rect2i]) -> Dictionary:
	if not is_inside_tree() or regions.is_empty(): return statistics.duplicate()
	if roots != _roots: return rebuild(roots, _chunk_size)
	var index := RegionIndex.new(regions)
	# 1. Which branches are gone or touched, and which chunks their meshes occupy
	# now. A branch with a declared region admits every descendant chunk;
	# world-space sources without one admit only the chunks of their cells.
	var changed_chunks: Dictionary = {}
	var gone: Array = []
	var touched: Dictionary = {}
	var tracked := _tracked and _roots_in_tree()
	for id: int in _update_candidates(tracked):
		var inventory: Dictionary = _branches[id]
		var owner: Variant = inventory.owner.get_ref()
		var alive: bool = is_instance_valid(owner) and owner.get_parent() == _roots[inventory.root]
		var intersects := false
		# Both the chunks its batched members occupied and the chunks its meshes
		# occupy now are affected.
		# A live branch declared immutable cannot have moved, added or removed a
		# mesh since it was indexed; its members stay as they are.
		if inventory.explicit:
			intersects = index.intersects(inventory.region)
			if intersects and (not alive or not owner.get_meta("batch_immutable", false)):
				for chunk: Vector2i in inventory.chunks: changed_chunks[chunk] = true
				if alive:
					var visited: Array = []
					_visit(owner, visited)
					for entry: Array in visited: changed_chunks[entry[1]] = true
					touched[id] = visited
		else:
			for cell: Vector2i in inventory.cells:
				if index.intersects(Rect2i(cell, Vector2i.ONE)):
					intersects = true
					changed_chunks[inventory.cells[cell]] = true
			if alive:
				var visited: Array = []
				_visit(owner, visited)
				for entry: Array in visited:
					if index.intersects(Rect2i(entry[2], Vector2i.ONE)):
						intersects = true
						changed_chunks[entry[1]] = true
				if intersects: touched[id] = visited
		if not alive: gone.append(id)
	# 2. Leave groups: every member of a gone branch; members of touched branches
	# inside the changed chunks (restored to their authored visibility first).
	var dirty: Dictionary = {}
	for id: int in gone:
		for record: Dictionary in _branches[id].members: _leave_member(record, dirty, false)
		_erase_branch(id)
	_mesh_material_support.clear()
	for id: int in touched:
		var inventory: Dictionary = _branches[id]
		var kept: Dictionary = {}
		for record: Dictionary in inventory.members:
			if changed_chunks.has(record.chunk): _leave_member(record, dirty, true)
			else: kept[record.id] = record
		var replacement := _index_branch(inventory.owner.get_ref(), inventory.root, changed_chunks, kept, touched[id])
		_set_branch(id, replacement)
		_join_members(replacement, dirty)
	# 3. New direct children of the roots.
	var scanned := 0
	for entry: Array in _new_branches(tracked):
		var root_index: int = entry[0]
		var branch: Node = entry[1]
		var id := branch.get_instance_id()
		if _branches.has(id): continue
		var inventory := _index_branch(branch, root_index, {}, {})
		_set_branch(id, inventory)
		_join_members(inventory, dirty)
		for chunk: Vector2i in inventory.chunks: changed_chunks[chunk] = true
		scanned += int(inventory.meshes)
	_mesh_material_support.clear()
	# 4. Remake only the groups whose membership changed.
	statistics = {"source_meshes": 0, "eligible_meshes": 0, "batched_instances": 0, "batches": 0}
	_remake_groups(dirty)
	# Statistics count the affected set: every mesh of a branch meeting a
	# changed chunk, plus those visited for new branches.
	var counted: Dictionary = {}
	for chunk: Vector2i in changed_chunks:
		for id: int in _chunk_branches.get(chunk, {}):
			if counted.has(id): continue
			counted[id] = true
			statistics.source_meshes += int(_branches[id].meshes)
	# Eligible sources are the still-hidden ones plus singletons left visible
	# in the changed chunks; batched members there are already hidden.
	var singles := 0
	for chunk: Vector2i in changed_chunks:
		for key: Array in _chunk_groups.get(chunk, {}):
			if _groups[key].size() < 2: singles += _groups[key].size()
	for id: int in touched: scanned += touched[id].size()
	statistics.scanned_meshes = scanned
	statistics.eligible_meshes = _hidden.size() + singles
	statistics.batched_instances = _hidden.size()
	statistics.batches = get_child_count()
	_finish_tracking()
	return statistics.duplicate()


## Every MeshInstance3D below `node` with its current chunk and cell, depth first.
func _visit(node: Node, visited: Array) -> void:
	if node is MeshInstance3D:
		var position := to_local((node as MeshInstance3D).global_position)
		visited.append([node, Vector2i(floori(position.x / _chunk_size), floori(position.z / _chunk_size)), Vector2i(floori(position.x), floori(position.z))])
	for child: Node in node.get_children(): _visit(child, visited)


## Inventory one branch. Members in `inspect` (every chunk when empty) are
## evaluated for eligibility and grouping; other meshes keep their `kept` record.
func _index_branch(branch: Node, root_index: int, inspect: Dictionary, kept: Dictionary, visited: Array = []) -> Dictionary:
	if visited.is_empty(): _visit(branch, visited)
	var explicit := branch.has_meta("batch_region")
	var inventory := {"owner": weakref(branch), "root": root_index, "explicit": explicit,
		"region": branch.get_meta("batch_region") if explicit else Rect2i(), "chunks": {}, "cells": {},
		"meshes": visited.size(), "members": []}
	var domain: StringName = _roots[root_index].get_meta("batch_domain", &"")
	for entry: Array in visited:
		var source := entry[0] as MeshInstance3D
		var chunk: Vector2i = entry[1]
		inventory.chunks[chunk] = true
		if not explicit: inventory.cells[entry[2]] = chunk
		var id := source.get_instance_id()
		if inspect.is_empty() or inspect.has(chunk):
			if not _eligible(source): continue
			var key := _group_key(source, chunk)
			key.insert(1, domain)
			inventory.members.append({"ref": weakref(source), "id": id, "key": key, "chunk": chunk,
				"branch": branch.get_instance_id(), "ordinal": inventory.members.size(),
				"region": inventory.region if explicit else Rect2i(entry[2], Vector2i.ONE)})
		elif kept.has(id):
			var record: Dictionary = kept[id]
			record.ordinal = inventory.members.size()
			inventory.members.append(record)
	return inventory


func _join_members(inventory: Dictionary, dirty: Dictionary) -> void:
	for record: Dictionary in inventory.members:
		if not _groups.has(record.key):
			_groups[record.key] = {}
			var chunk: Vector2i = record.key[0]
			if not _chunk_groups.has(chunk): _chunk_groups[chunk] = {}
			_chunk_groups[chunk][record.key] = true
		_groups[record.key][record.id] = record
		dirty[record.key] = true


## A member leaves its group. Sources of touched branches regain their authored
## visibility before inspection; freed sources need nothing restored.
func _leave_member(record: Dictionary, dirty: Dictionary, restore: bool) -> void:
	var members: Dictionary = _groups.get(record.key, {})
	members.erase(record.id)
	if members.is_empty() and _groups.has(record.key):
		_groups.erase(record.key)
		var listed: Dictionary = _chunk_groups.get(record.key[0], {})
		listed.erase(record.key)
		if listed.is_empty(): _chunk_groups.erase(record.key[0])
	dirty[record.key] = true
	if _hidden.has(record.id):
		_hidden.erase(record.id)
		if restore:
			var source: Variant = record.ref.get_ref()
			if is_instance_valid(source): source.visible = true


## Members compare as the full depth-first collection orders them: root order,
## then the branch's current child index, then the member's ordinal.
static func _member_before(a: Dictionary, b: Dictionary) -> bool:
	if a.root != b.root: return a.root < b.root
	if a.branch_index != b.branch_index: return a.branch_index < b.branch_index
	return a.ordinal < b.ordinal


## The `_member_before` order. Root, child index and ordinal are distinct per
## member, so packing them into one integer and sorting natively gives the same
## total order; out-of-range values use the comparator.
static func _sort_members(live: Array) -> void:
	var keyed: Dictionary = {}
	for record: Dictionary in live:
		var root: int = record.root
		var branch_index: int = record.branch_index
		var ordinal: int = record.ordinal
		if root < 0 or root >= 1 << 20 or branch_index < 0 or branch_index >= 1 << 21 or ordinal < 0 or ordinal >= 1 << 21:
			live.sort_custom(_member_before)
			return
		keyed[(root << 42) | (branch_index << 21) | ordinal] = record
	if keyed.size() != live.size():
		live.sort_custom(_member_before)
		return
	var order := PackedInt64Array(keyed.keys())
	order.sort()
	for i: int in order.size(): live[i] = keyed[order[i]]


func _remake_groups(dirty: Dictionary) -> void:
	var branch_indices: Dictionary = {}
	for key: Array in dirty:
		var previous: MultiMeshInstance3D = _batches.get(key)
		var members: Dictionary = _groups.get(key, {})
		var live: Array = []
		for record: Dictionary in members.values():
			var source: Variant = record.ref.get_ref()
			if not is_instance_valid(source) or not _branches.has(record.branch): continue
			live.append(record)
		if live.size() < 2:
			if previous != null:
				_batches.erase(key)
				remove_child(previous)
				previous.queue_free()
			for record: Dictionary in live:
				if _hidden.has(record.id):
					_hidden.erase(record.id)
					record.ref.get_ref().visible = true
			continue
		# Members usually join in collection order; an already strictly ascending
		# packed order is the sorted order, so the sort is skipped only then.
		var ascending := true
		var last := -1
		for record: Dictionary in live:
			var inventory: Dictionary = _branches[record.branch]
			if not branch_indices.has(record.branch):
				var owner: Variant = inventory.owner.get_ref()
				branch_indices[record.branch] = owner.get_index() if is_instance_valid(owner) else -1
			var root: int = inventory.root
			var branch_index: int = branch_indices[record.branch]
			var ordinal: int = record.ordinal
			record.root = root
			record.branch_index = branch_index
			if ascending:
				if root < 0 or root >= 1 << 20 or branch_index < 0 or branch_index >= 1 << 21 or ordinal < 0 or ordinal >= 1 << 21:
					ascending = false
				else:
					var packed := (root << 42) | (branch_index << 21) | ordinal
					if packed <= last: ascending = false
					last = packed
		if not ascending: _sort_members(live)
		# The same key means the same mesh, materials and render state: the
		# batch node is reused and only its instances are replaced.
		_make_member_batch(live, key, previous)


func _source_region(source: MeshInstance3D) -> Rect2i:
	var node: Node = source
	while node != null:
		if node.has_meta("batch_region"): return node.get_meta("batch_region")
		node = node.get_parent()
	var position := to_local(source.global_position)
	return Rect2i(floori(position.x), floori(position.z), 1, 1)


func _eligible(source: MeshInstance3D) -> bool:
	if source.get_meta("mutable_station_name",false): return false
	if source.mesh == null or not source.is_visible_in_tree():
		return false
	if source.skin != null or not source.skeleton.is_empty() or source.get_blend_shape_count() > 0:
		return false
	# Hiding a mesh node also hides visual descendants. Keep such parent meshes
	# intact so unsupported/singleton child visuals cannot disappear with them.
	if _has_visual_descendant(source):
		return false
	# Negative determinants need per-object cull reversal, not a shared draw.
	if source.global_basis.determinant() <= 0.0 or source.custom_aabb != AABB():
		return false
	if not source.visibility_parent.is_empty() or source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0:
		return false
	if source.transparency != 0.0 or not _material_supported(source.material_overlay):
		return false
	# Active materials are the instance's override, else its surface override,
	# else the mesh's own surface material. Only the last is shared per mesh.
	if source.material_override != null:
		return _material_supported(source.material_override)
	var mesh := source.mesh
	var has_surface_override := false
	for surface: int in mesh.get_surface_count():
		var override := source.get_surface_override_material(surface)
		if override != null:
			has_surface_override = true
			if not _material_supported(override): return false
	if not has_surface_override:
		var mesh_id := mesh.get_instance_id()
		if not _mesh_material_support.has(mesh_id):
			var supported := true
			for surface: int in mesh.get_surface_count():
				if not _material_supported(mesh.surface_get_material(surface)):
					supported = false
					break
			_mesh_material_support[mesh_id] = supported
		return _mesh_material_support[mesh_id]
	for surface: int in mesh.get_surface_count():
		if source.get_surface_override_material(surface) == null and not _material_supported(mesh.surface_get_material(surface)):
			return false
	return true


static func _has_visual_descendant(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is VisualInstance3D or _has_visual_descendant(child):
			return true
	return false


static func _material_supported(material: Material) -> bool:
	if material == null:
		return true
	if material is ShaderMaterial:
		# Only unmodified static palm crown materials qualify; terrain and
		# network shaders stay unbatched.
		return Palm.is_static_crown_material(material)
	if not material is BaseMaterial3D:
		return false
	var base := material as BaseMaterial3D
	# Transparent sorting and billboards need their own draws.
	if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	return _material_supported(base.next_pass)


func _group_key(source: MeshInstance3D, chunk: Vector2i) -> Array:
	# Use resource identities and full property values, not a lossy hash or a
	# material color/filename approximation. UVs, normals, LODs and shadow meshes
	# still come from the source mesh resource.
	var key: Array = [chunk, source.mesh.get_instance_id(),
		_resource_id(source.material_override), _resource_id(source.material_overlay)]
	for surface: int in source.mesh.get_surface_count():
		key.append(_resource_id(source.get_surface_override_material(surface)))
	# The same values COPY_PROPERTIES names, read directly in that order.
	key.append(source.layers)
	key.append(source.cast_shadow)
	key.append(source.extra_cull_margin)
	key.append(source.gi_mode)
	key.append(source.gi_lightmap_scale)
	key.append(source.gi_lightmap_texel_scale)
	key.append(source.lod_bias)
	key.append(source.ignore_occlusion_culling)
	key.append(source.transparency)
	return key


static func _resource_id(resource: Resource) -> int:
	return resource.get_instance_id() if resource != null else 0


## `_make_batch` for sorted live member records: the same instances, bounds,
## metadata and hidden sources, reading each member's id, region and weak
## reference from its record instead of deriving them from the source again.
func _make_member_batch(live: Array, key: Array, existing: MultiMeshInstance3D) -> void:
	var first: MeshInstance3D = live[0].ref.get_ref()
	var mesh := existing.multimesh.mesh if existing != null else _effective_mesh(first)
	if mesh == null:
		return
	var count := live.size()
	var batch: MultiMesh
	if existing != null:
		batch = existing.multimesh
		batch.instance_count = count
	else:
		batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = count
	var relative := global_transform.affine_inverse()
	var bounds := AABB()
	var ids := PackedInt64Array()
	ids.resize(count)
	var uploaded_transforms: Array[Transform3D] = []
	uploaded_transforms.resize(count)
	var source_regions: Array[Rect2i] = []
	var seen_regions: Dictionary = {}
	var source_refs: Array[WeakRef] = []
	source_refs.resize(count)
	var mesh_bounds := mesh.get_aabb()
	for i: int in count:
		var record: Dictionary = live[i]
		var reference: WeakRef = record.ref
		var source: MeshInstance3D = reference.get_ref()
		var transform := relative * source.global_transform
		batch.set_instance_transform(i, transform)
		uploaded_transforms[i] = transform
		var instance_bounds: AABB = transform * mesh_bounds
		bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
		ids[i] = record.id
		source_refs[i] = reference
		var region: Rect2i = record.region
		if not seen_regions.has(region):
			seen_regions[region] = true
			source_regions.append(region)
	batch.custom_aabb = bounds
	var replacement := existing if existing != null else MultiMeshInstance3D.new()
	if existing == null:
		var domain: StringName = key[1]
		replacement.name = "MeshBatch"
		replacement.multimesh = batch
		replacement.material_override = first.material_override
		replacement.material_overlay = first.material_overlay
		for property: StringName in COPY_PROPERTIES:
			replacement.set(property, first.get(property))
		replacement.set_meta("chunk", key[0])
		replacement.set_meta("domain", domain)
		replacement.visible = bool(_domain_visibility.get(domain, true))
	replacement.set_meta("source_ids", ids)
	replacement.set_meta("source_refs", source_refs)
	replacement.set_meta("source_regions", source_regions)
	replacement.set_meta("uploaded_transforms", uploaded_transforms)
	if existing == null: add_child(replacement)
	_batches[key] = replacement
	for record: Dictionary in live:
		_hidden[record.id] = record.ref
		record.ref.get_ref().visible = false
	statistics.batched_instances += count
	statistics.batches += 1


func _make_batch(sources: Array, chunk: Vector2i, domain: StringName, key: Array = [], regions: Array = [], existing: MultiMeshInstance3D = null) -> void:
	var first := sources[0] as MeshInstance3D
	var mesh := existing.multimesh.mesh if existing != null else _effective_mesh(first)
	if mesh == null:
		return
	var batch: MultiMesh
	if existing != null:
		# Same key, same mesh and format: only the instance storage is resized.
		batch = existing.multimesh
		batch.instance_count = sources.size()
	else:
		batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = sources.size()
	var relative := global_transform.affine_inverse()
	var bounds := AABB()
	var ids := PackedInt64Array()
	var uploaded_transforms: Array[Transform3D] = []
	var source_regions: Array[Rect2i] = []
	var seen_regions: Dictionary = {}
	var source_refs: Array[WeakRef] = []
	var mesh_bounds := mesh.get_aabb()
	for i: int in sources.size():
		var source := sources[i] as MeshInstance3D
		var transform := relative * source.global_transform
		batch.set_instance_transform(i, transform)
		uploaded_transforms.append(transform)
		var instance_bounds: AABB = transform * mesh_bounds
		bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
		ids.append(source.get_instance_id())
		source_refs.append(weakref(source))
		var region: Rect2i = regions[i] if i < regions.size() else _source_region(source)
		if not seen_regions.has(region):
			seen_regions[region] = true
			source_regions.append(region)
	batch.custom_aabb = bounds
	var replacement := existing if existing != null else MultiMeshInstance3D.new()
	if existing == null:
		replacement.name = "MeshBatch"
		replacement.multimesh = batch
		replacement.material_override = first.material_override
		replacement.material_overlay = first.material_overlay
		for property: StringName in COPY_PROPERTIES:
			replacement.set(property, first.get(property))
		replacement.set_meta("chunk", chunk)
		replacement.set_meta("domain", domain)
		replacement.visible = bool(_domain_visibility.get(domain, true))
	replacement.set_meta("source_ids", ids)
	replacement.set_meta("source_refs", source_refs)
	replacement.set_meta("source_regions", source_regions)
	replacement.set_meta("uploaded_transforms", uploaded_transforms)
	if existing == null: add_child(replacement)
	if not key.is_empty(): _batches[key] = replacement
	# Only hide visuals once their complete replacement is attached. Source
	# transforms, materials, children and all physics RIDs are left untouched.
	for source: MeshInstance3D in sources:
		_hidden[source.get_instance_id()] = weakref(source)
		source.visible = false
	statistics.batched_instances += sources.size()
	statistics.batches += 1


static func _effective_mesh(source: MeshInstance3D) -> Mesh:
	if source.material_override != null:
		return source.mesh
	var has_override := false
	for surface: int in source.mesh.get_surface_count():
		has_override = has_override or source.get_surface_override_material(surface) != null
	if not has_override:
		return source.mesh
	# Copy the mesh resource only for a surface override; shallow duplication
	# preserves vertex/UV/LOD/shadow data and leaves the source mesh untouched.
	var mesh := source.mesh.duplicate(false) as Mesh
	if mesh == null:
		return null
	for surface: int in mesh.get_surface_count():
		mesh.surface_set_material(surface, source.get_active_material(surface))
	return mesh


## Visibility changes keep all uploaded geometry and physics bodies.
func set_domain_visible(domain: StringName, on: bool) -> void:
	_domain_visibility[domain] = on
	for batch: Node in get_children():
		if batch.get_meta("domain", &"") == domain:
			batch.visible = on
