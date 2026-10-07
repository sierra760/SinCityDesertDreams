# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The growth refresh path (lot discovery, marina fitting, lot replacement,
## road bore profile reuse and tracked static batching) keeps its golden
## output. Real bundled cities run a seeded growth-like edit sequence through
## a view; every refresh contributes its counts, lots, batches and hidden
## sources, in order and independent of node instance ids, to one hash per city.
extends SceneTree

const Hashes := preload("res://tests/fixtures/output_hashes.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
const CITIES: Array[String] = ["La Presa", "Foothills Ranch", "Valle del Mar", "Oro Canyon",
	"Aliso Niguel", "Grant Pass - Soledad", "Lawndale", "Salton Shores"]
const TIMING_KEYS: Array[String] = ["microseconds", "terrain_us", "lots_us", "networks_us", "batches_us"]

var passed := 0
var failed := 0
var verdicts := 0
## Per golden key, the hash of every recorded output in order.
var _digests: Dictionary = {}


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", message)


## Adds one output to a golden key. Dictionary order is ignored, as with ==.
func _record(key: String, value: Variant) -> void:
	if not _digests.has(key): _digests[key] = []
	_digests[key].append(Hashes.unordered_sha(value))


func _check_golden(key: String, label: String) -> void:
	check(Hashes.matches(key, Hashes.sha(_digests.get(key, []))), label)
	_digests.erase(key)


func _run() -> void:
	var started := Time.get_ticks_msec()
	var only: Array = OS.get_cmdline_user_args()
	var catalog := CityModelCatalog.new()
	catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json")
	for name: String in CITIES:
		if not only.is_empty() and name not in only: continue
		var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
		check(loaded.ok, name + " imports")
		if not loaded.ok: continue
		_discovery(name, loaded.city)
		await _marinas(name, loaded.city, catalog)
		_check_golden("growth_lots/" + name, name + ": lot discovery and marina fitting match the golden hash")
	print("discovery and marinas: %d ms" % (Time.get_ticks_msec() - started))
	for name: String in ["La Presa", "Foothills Ranch", "Valle del Mar"]:
		if not only.is_empty() and name not in only: continue
		started = Time.get_ticks_msec()
		await _paired_views(name)
		print("%s paired views: %d ms" % [name, Time.get_ticks_msec() - started])
	await _batcher_tracking()
	print("MARINA_CANDIDATE_VERDICTS ", verdicts)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


# ── Lot discovery ────────────────────────────────────────────────────────

func _region_sets(city: City, rng: RandomNumberGenerator) -> Array:
	var sets: Array = []
	for count: int in [1, 7, 20, 70, 160, 400]:
		var cells: Dictionary = {}
		for i: int in count: cells[Vector2i(rng.randi_range(0, City.WIDTH - 1), rng.randi_range(0, City.HEIGHT - 1))] = true
		var single: Array[Rect2i] = []
		for cell: Vector2i in cells: single.append(Rect2i(cell, Vector2i.ONE))
		sets.append(single)
		sets.append(CityView3D._coalesced_lot_cells(cells))
	var edges: Array[Rect2i] = [Rect2i(0, 0, 1, 1), Rect2i(127, 127, 1, 1), Rect2i(-3, -3, 5, 5),
		Rect2i(120, -2, 20, 4), Rect2i(60, 60, 0, 0), Rect2i(30, 90, 0, 3), Rect2i(10, 10, 40, 40), Rect2i(20, 20, 40, 40)]
	sets.append(edges)
	var whole: Array[Rect2i] = [Rect2i(0, 0, City.WIDTH, City.HEIGHT)]
	sets.append(whole)
	# Lots of every footprint size: their own rectangles and neighbours.
	var lots: Array[Rect2i] = []
	for record: Dictionary in CityBuildings3D.collect(city):
		if Buildings.size(record.code) != Vector2i.ONE and lots.size() < 40: lots.append(record.footprint)
	sets.append(lots)
	return sets


func _discovery(name: String, city: City) -> void:
	_record("growth_lots/" + name, CityBuildings3D.collect(city))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6100 + name.length()
	for regions: Array in _region_sets(city, rng):
		var typed: Array[Rect2i] = []
		typed.assign(regions)
		_record("growth_lots/" + name, CityBuildings3D.collect_regions(city, typed))


# ── Marina fitting ───────────────────────────────────────────────────────

static func _index_path(top: Node, node: Node) -> Array:
	var path: Array = []
	while node != top and node != null:
		path.push_front(node.get_index())
		node = node.get_parent()
	return path


static func _shape(shape: Shape3D) -> Variant:
	if shape == null: return null
	if shape is ConcavePolygonShape3D: return shape.get_faces()
	if shape is BoxShape3D: return shape.size
	if shape is CylinderShape3D or shape is CapsuleShape3D: return [shape.radius, shape.height]
	if shape is SphereShape3D: return shape.radius
	return shape.get_class()


## A lot's whole subtree by structure and content, independent of node names
## the engine generates and of resource instances owned by separate catalogs.
static func _subtree(top: Node) -> Array:
	var out: Array = []
	var stack: Array = [top]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var row: Array = [_index_path(top, node), node.get_class(), node.get_child_count()]
		if not String(node.name).begins_with("@"): row.append(String(node.name))
		if node is Node3D: row.append_array([node.transform, node.visible])
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			row.append_array([mesh.get_class() if mesh != null else "", mesh.get_aabb() if mesh != null else AABB(),
				mesh.get_surface_count() if mesh != null else 0, node.cast_shadow, node.material_override != null])
			# Lot-built meshes are compared by vertices; catalog meshes may come from
			# a fresh compile or the compiled-model cache, so they compare by shape.
			if mesh is ArrayMesh and mesh.get_surface_count() > 0:
				var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				row.append(vertices if String(node.name) == "TerrainSupport" else vertices.size())
		if node is CollisionObject3D: row.append_array([node.collision_layer, node.collision_mask])
		if node is CollisionShape3D: row.append(_shape(node.shape))
		for meta: StringName in node.get_meta_list():
			var value: Variant = node.get_meta(meta)
			if value is WeakRef:
				var target: Variant = value.get_ref()
				value = ["weakref", _index_path(top, target) if target is Node else str(target)]
			elif value is Object: value = ["object", value.get_class()]
			row.append([meta, value])
		out.append(row)
		for i: int in range(node.get_child_count() - 1, -1, -1): stack.append(node.get_child(i))
	return out


func _marinas(name: String, city: City, catalog: CityModelCatalog) -> void:
	var buildings := CityBuildings3D.new()
	root.add_child(buildings)
	var count := 0
	for record: Dictionary in CityBuildings3D.collect(city):
		if record.code != Buildings.MARINA: continue
		count += 1
		buildings._add_record(city, catalog, record)
		var marina: Node = buildings.get_child(buildings.get_child_count() - 1)
		_record("growth_lots/" + name, _subtree(marina))
		_candidate_verdicts(name, city, catalog, record, marina)
	if count > 0: print("%s: %d marinas fitted" % [name, count])
	buildings.free()


## Every candidate placement the search can visit gets the same verdict from
## the cached test (sharing one probe, as one search does) and the direct test.
func _candidate_verdicts(name: String, city: City, catalog: CityModelCatalog, record: Dictionary, model: Node3D) -> void:
	var source: Dictionary = CityBuildings3D._marina_sources.get(str(catalog.entries[Buildings.MARINA].get("glb_sha256", "")), {})
	if source.is_empty(): return
	var rect: Rect2i = record.footprint
	var ground := CityBuildings3D.base_height(city, rect, Buildings.MARINA)
	var origin := Vector3(rect.position.x + rect.size.x * 0.5, ground, rect.position.y + rect.size.y * 0.5)
	var yaw := CityBuildings3D._marina_yaw(city, rect, ground)
	var probe := {"cells": {}, "first": 0}
	var same := true
	var cleared := 0
	for turn: int in [0, 1, -1, 2]:
		var rotation := Basis(Vector3.UP, yaw + turn * PI / 2.0)
		var rotated: AABB = Transform3D(rotation, Vector3.ZERO) * (source.bounds as AABB)
		for size_step: int in range(0, 12, 3):
			var factor := maxf(CityBuildings3D.MIN_MARINA_SCALE, 1.0 - size_step * 0.05)
			var low := Vector2(-rect.size.x * 0.5 - rotated.position.x * factor, -rect.size.y * 0.5 - rotated.position.z * factor)
			var high := Vector2(rect.size.x * 0.5 - rotated.end.x * factor, rect.size.y * 0.5 - rotated.end.z * factor)
			# The search's own window, or nearby offsets where none is admissible.
			var xs: Array[float] = CityBuildings3D._fit_offsets(low.x, high.x) if low.x <= high.x else [-0.25, 0.0, 0.25]
			var zs: Array[float] = CityBuildings3D._fit_offsets(low.y, high.y) if low.y <= high.y else [-0.25, 0.0, 0.25]
			for xi: int in range(0, xs.size(), 2):
				for zi: int in range(0, zs.size(), 2):
					var x := xs[xi]
					var z := zs[zi]
					var transform := Transform3D(rotation.scaled(Vector3.ONE * factor), origin + Vector3(x, 0, z))
					var expected := CityBuildings3D._boats_clear(city, source.points, transform)
					verdicts += 1
					if expected: cleared += 1
					if CityBuildings3D._boats_clear_cached(city, source.points, transform, probe) != expected: same = false
	check(same, "%s: marina %s candidate verdicts equal the direct test (%d clear)" % [name, str(record.anchor), cleared])


# ── Paired views ─────────────────────────────────────────────────────────

static func _branch_key(source_root: Node, branch: Node) -> Array:
	if branch.has_meta("cell"): return [String(source_root.name), branch.get_meta("cell"), branch.get_meta("code")]
	if branch.has_meta("batch_region"): return [String(source_root.name), branch.get_meta("batch_region")]
	return [String(source_root.name), branch.get_index()]


static func _source_key(view: CityView3D, source: Node) -> Array:
	var node := source
	while node != null and node.get_parent() != view.buildings and node.get_parent() != view.networks:
		node = node.get_parent()
	if node == null: return ["detached"]
	return [_branch_key(node.get_parent(), node), _index_path(node, source)]


static func _batches(view: CityView3D) -> Array:
	var out: Array = []
	for batch: MultiMeshInstance3D in view.mesh_batches.get_children():
		var sources: Array = []
		for reference: WeakRef in batch.get_meta("source_refs"):
			var source: Variant = reference.get_ref()
			sources.append(_source_key(view, source) if is_instance_valid(source) else ["freed"])
		out.append([batch.get_meta("chunk"), batch.get_meta("domain"), batch.visible, batch.cast_shadow, batch.layers,
			batch.multimesh.instance_count, batch.multimesh.custom_aabb, batch.get_meta("uploaded_transforms"),
			batch.get_meta("source_regions"), sources, batch.material_override != null])
	return out


static func _hidden(view: CityView3D) -> Array:
	var keys: Array = []
	for source_root: Node3D in [view.buildings, view.networks]:
		for mesh: MeshInstance3D in source_root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.visible: keys.append(str(_source_key(view, mesh)))
	keys.sort()
	return keys


## Every lot in child order; `deep` adds each lot's complete subtree.
static func _lots(view: CityView3D, deep: bool) -> Array:
	var out: Array = []
	for lot: Node3D in view.buildings.get_children():
		if deep: out.append(_subtree(lot))
		else: out.append([lot.get_meta("code"), lot.get_meta("cell"), lot.get_meta("missing_model"), lot.transform, lot.get_child_count()])
	return out


static func _statistics(view: CityView3D) -> Dictionary:
	var out := view.refresh_statistics.duplicate()
	for key: String in TIMING_KEYS: out.erase(key)
	return out


## Everything one refresh produced; `deep` includes each lot's complete subtree.
static func _snapshot(view: CityView3D, deep: bool) -> Array:
	return [_statistics(view), view._lot_regions, view._changed_lot_cells, view._terrain_rebuild_regions,
		view._terrain_recolor_cells, view._road_tunnel_state, view.buildings.last_retained_lots,
		view.buildings.last_updated_lots, view.buildings.missing, _lots(view, deep),
		view.mesh_batches.statistics, _batches(view), _hidden(view)]


## One growth-like edit, applied to every city in `cities`.
func _edit(cities: Array, kind: int, rng: RandomNumberGenerator, cache: Dictionary) -> void:
	var city: City = cities[0]
	match kind:
		0: # growth: a new one-cell building on empty dry ground
			var cell: Vector2i = cache.empty[rng.randi_range(0, cache.empty.size() - 1)]
			var code := Buildings.RES_1X1_FIRST + rng.randi_range(0, 7)
			for c: City in cities: c.stamp_building(cell.x, cell.y, code)
		1: # abandonment: a lot is cleared
			var cell: Vector2i = cache.lots[rng.randi_range(0, cache.lots.size() - 1)]
			for c: City in cities: c.clear_footprint(cell.x, cell.y)
		2: # upgrade in place
			var cell: Vector2i = cache.lots[rng.randi_range(0, cache.lots.size() - 1)]
			var code := city.building.at(cell.x, cell.y)
			if Buildings.size(code) == Vector2i.ONE and Buildings.is_zone_building(code):
				for c: City in cities: c.building.put(cell.x, cell.y, Buildings.RES_1X1_FIRST + (code - Buildings.RES_1X1_FIRST + 1) % 8)
		3: # zoning
			var cell: Vector2i = cache.empty[rng.randi_range(0, cache.empty.size() - 1)]
			for c: City in cities: c.zone.put(cell.x, cell.y, Zones.make(Zones.IND_LOW))
		4: # a multi-cell lot on a clear dry square
			for attempt: int in 40:
				var size := 2 + rng.randi_range(0, 1)
				var cell := Vector2i(rng.randi_range(2, City.WIDTH - 6), rng.randi_range(2, City.HEIGHT - 6))
				var clear := true
				for y: int in range(cell.y, cell.y + size):
					for x: int in range(cell.x, cell.x + size):
						if city.building.at(x, y) != Buildings.NONE or city.is_water(x, y): clear = false
				if not clear: continue
				var code := (Buildings.RES_2X2_FIRST if size == 2 else Buildings.RES_3X3_FIRST) + rng.randi_range(0, 3)
				for c: City in cities: c.stamp_building(cell.x, cell.y, code, Zones.RES_HIGH)
				break
		5: # growth beside a marina: the marina is fitted again
			if cache.marinas.is_empty(): return
			var marina: Vector2i = cache.marinas[rng.randi_range(0, cache.marinas.size() - 1)]
			for attempt: int in 30:
				var cell := marina + Vector2i(rng.randi_range(-2, 4), rng.randi_range(-2, 4))
				if not city.in_bounds(cell.x, cell.y) or city.building.at(cell.x, cell.y) != Buildings.NONE or city.is_water(cell.x, cell.y): continue
				var code := Buildings.COM_1X1_FIRST + rng.randi_range(0, 3)
				for c: City in cities: c.stamp_building(cell.x, cell.y, code)
				break
		6: # a heavy growth day: thirty scattered changes in one refresh
			for i: int in 30: _edit(cities, [0, 1, 2, 0, 4][i % 5], rng, cache)
		7: # a bore input: ground beside a tunnel mouth rises, then a mouth is cleared
			if cache.tunnels.is_empty(): return
			var mouth: Vector2i = cache.tunnels[rng.randi_range(0, cache.tunnels.size() - 1)]
			if rng.randi_range(0, 1) == 0:
				for c: City in cities: c.altitude.data[mouth.y * City.WIDTH + mouth.x] += 1
			else:
				for c: City in cities: c.building.put(mouth.x, mouth.y, Buildings.NONE)
		8: # a flood touches only the flood layer; later growth reads it
			var cell: Vector2i = cache.empty[rng.randi_range(0, cache.empty.size() - 1)]
			for c: City in cities: c.flood_overlay[cell] = 1
		9: # the flood recedes
			for c: City in cities: c.flood_overlay.clear()


func _paired_views(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var cities: Array = [city]
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var key := "growth_view/" + name
	_record(key, _snapshot(view, true))
	var cache := {"lots": [], "empty": [], "marinas": [], "tunnels": []}
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var code := city.building.at(x, y)
			if Buildings.is_zone_building(code) and city.anchor_of(x, y) == Vector2i(x, y): cache.lots.append(Vector2i(x, y))
			elif code == Buildings.NONE and not city.is_water(x, y): cache.empty.append(Vector2i(x, y))
			if code == Buildings.MARINA and city.anchor_of(x, y) == Vector2i(x, y): cache.marinas.append(Vector2i(x, y))
			if NetworkShapes.is_tunnel(code): cache.tunnels.append(Vector2i(x, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006 + name.length()
	var plan: Array[int] = [0, 1, 2, 3, 4, 5, 0, 6, 5, 8, 0, 9, 7, 0, 6, 5, 7, 2, 6, 0]
	var step := 0
	for kind: int in plan:
		_edit(cities, kind, rng, cache)
		view.refresh()
		_record(key, [Hashes.sha(SaveFormat.encode_city(city)), _snapshot(view, step % 5 == 4)])
		step += 1
	# The incremental batches also equal a fresh full rebuild of the same view.
	var incremental := _batches(view)
	var hidden := _hidden(view)
	view.mesh_batches.rebuild([view.buildings, view.networks])
	var rebuilt := _batches(view)
	incremental.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	rebuilt.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	check(incremental == rebuilt and hidden == _hidden(view), name + ": tracked incremental batches equal a fresh full rebuild")
	view.refresh(true)
	_record(key, _snapshot(view, true))
	_check_golden(key, name + ": every refresh of the growth sequence and a forced full refresh match the golden hash")
	view.queue_free()
	await process_frame


# ── Batcher tracking edge cases ──────────────────────────────────────────

static var _box: BoxMesh


## Two identical synthetic source trees with explicit immutable, explicit
## mutable and region-less branches.
func _scene(batcher_script: GDScript) -> Dictionary:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE * 0.3
	var holder := Node3D.new()
	root.add_child(holder)
	var sources := Node3D.new()
	sources.set_meta("batch_domain", &"test")
	holder.add_child(sources)
	for i: int in 40:
		_add_branch(sources, i, i % 3)
	var batcher: Node3D = batcher_script.new()
	holder.add_child(batcher)
	var roots: Array[Node3D] = [sources]
	batcher.rebuild(roots, 8)
	return {"holder": holder, "sources": sources, "batcher": batcher, "roots": roots}


static func _add_branch(sources: Node3D, i: int, kind: int) -> Node3D:
	var branch := Node3D.new()
	var cell := Vector2i((i * 7) % 30, (i * 3) % 30)
	branch.position = Vector3(cell.x, 0, cell.y)
	if kind != 2: branch.set_meta("batch_region", Rect2i(cell, Vector2i.ONE))
	if kind == 0: branch.set_meta("batch_immutable", true)
	for j: int in 2 + i % 3:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _box
		mesh.position = Vector3(0.1 * j, 0.2 * j, 0)
		branch.add_child(mesh)
	sources.add_child(branch)
	return branch


static func _synthetic(scene: Dictionary) -> Array:
	var out: Array = []
	for batch: MultiMeshInstance3D in scene.batcher.get_children():
		var sources: Array = []
		for reference: WeakRef in batch.get_meta("source_refs"):
			var source: Variant = reference.get_ref()
			sources.append(_index_path(scene.sources, source) if is_instance_valid(source) else ["freed"])
		out.append([batch.get_meta("chunk"), batch.multimesh.instance_count, batch.get_meta("uploaded_transforms"),
			batch.get_meta("source_regions"), sources])
	var hidden: Array = []
	for mesh: MeshInstance3D in scene.sources.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible: hidden.append(_index_path(scene.sources, mesh))
	out.append(hidden)
	out.append(scene.batcher.statistics)
	return out


func _batcher_tracking() -> void:
	var scene := _scene(Batcher)
	_record("growth_batcher/synthetic", _synthetic(scene))
	var operations: Array[String] = ["remove", "readd", "free", "add", "mutate", "mutate_distant", "reparent_out",
		"root_out_and_in", "batcher_out_and_in", "move", "free_distant"]
	var serial := 100
	for operation: String in operations:
		var sources: Node3D = scene.sources
		match operation:
			"remove":
				var branch := sources.get_child(3)
				sources.remove_child(branch)
				scene["removed"] = branch
			"readd":
				sources.add_child(scene.removed)
			"free":
				sources.get_child(5).free()
			"add":
				_add_branch(sources, serial, 0)
				_add_branch(sources, serial + 1, 2)
			"mutate":
				var branch := sources.get_child(1)
				var mesh := MeshInstance3D.new()
				mesh.mesh = _box
				branch.add_child(mesh)
			"mutate_distant":
				var branch := sources.get_child(sources.get_child_count() - 1)
				branch.get_child(0).position += Vector3(0.05, 0, 0)
			"reparent_out":
				var branch := sources.get_child(2)
				branch.reparent(scene.holder)
			"root_out_and_in":
				scene.holder.remove_child(sources)
				sources.get_child(6).free()
				_add_branch(sources, serial + 2, 0)
				scene.holder.add_child(sources)
			"batcher_out_and_in":
				scene.holder.remove_child(scene.batcher)
				scene.holder.add_child(scene.batcher)
			"move":
				sources.move_child(sources.get_child(0), sources.get_child_count() - 1)
			"free_distant":
				sources.get_child(sources.get_child_count() - 2).free()
		var regions: Array[Rect2i] = [Rect2i(0, 0, 12, 12)]
		scene.batcher.update_regions(scene.roots, regions)
		_record("growth_batcher/synthetic", [operation, _synthetic(scene)])
		serial += 10
	_check_golden("growth_batcher/synthetic", "synthetic: batches, hidden sources and statistics after every tracked change match the golden hash")
	if scene.has("removed") and is_instance_valid(scene.removed) and scene.removed.get_parent() == null: scene.removed.free()
	scene.holder.queue_free()
	await process_frame
