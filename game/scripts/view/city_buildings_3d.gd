# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One model and one query proxy per building lot footprint.
class_name CityBuildings3D
extends Node3D

const QUERY_LAYER := 2
const MIN_MARINA_SCALE := 0.45
const RegionIndex := preload("res://scripts/view/city_region_index_2d.gd")
static var _pier_join_mesh: BoxMesh
static var _marina_sources: Dictionary = {}
static var _lot_scan_margin := 0
var missing: Dictionary = {}
var last_updated_lots := 0
var last_retained_lots := 0
var _names_city: City
## Lots by 16-cell bucket of their dependency reach (footprint grown by two
## cells), so an update visits only lots that can meet its regions. Any lot
## whose reach meets a region shares a bucket with it; the exact predicate is
## still applied. The index is used only while it accounts for every child.
const LOT_BUCKET := 16
var _lot_buckets: Dictionary = {}
var _lot_count := 0
var _missing_lots := 0


## Resolve adjacent and rotated lots through City's shared footprint contract.
## Row-major discovery reads the packed layers directly and deduplicates lots
## by their (anchor, code) key.
static func collect(city: City) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	var bld: PackedInt32Array = city.building.data
	var zn: PackedByteArray = city.zone.data
	var sizes: PackedInt32Array = City._sizes
	for y: int in City.HEIGHT:
		var row := y * City.WIDTH
		for x: int in City.WIDTH:
			var code := bld[row + x]
			if code < Buildings.RES_1X1_FIRST:
				continue
			# A single-cell code is its own anchor, as footprint_anchor answers first.
			var anchor := Vector2i(x, y) if sizes[code] == 0x0101 else City.footprint_anchor(bld, zn, x, y)
			var key := Vector3i(anchor.x, anchor.y, code)
			if seen.has(key):
				continue
			seen[key] = true
			records.append({"code": code, "footprint": Rect2i(anchor, Buildings.size(code)), "anchor": anchor})
	return records


## Discover the lots a full scan would project for an edit. A cell's anchor
## can move back by at most its roster span, including the malformed-corner
## fallback. Scan that reach plus the two-cell dependency halo, with the same
## row-major discovery and (anchor, code) deduplication.
static func collect_regions(city: City, regions: Array[Rect2i], region_index: RegionIndex = null) -> Array[Dictionary]:
	if regions.is_empty(): return []
	var query := region_index if region_index!=null else RegionIndex.new(regions)
	if _lot_scan_margin == 0:
		for code: int in Buildings.COUNT:
			var span := Buildings.size(code)
			_lot_scan_margin = maxi(_lot_scan_margin,maxi(span.x,span.y)+2)
	var bounds := Rect2i(0,0,City.WIDTH,City.HEIGHT)
	var area := 0
	for region: Rect2i in regions:
		var scan := region.grow(_lot_scan_margin).intersection(bounds)
		area += scan.size.x*scan.size.y
		if area >= City.WIDTH*City.HEIGHT/2:
			var all: Array[Dictionary] = []
			for record: Dictionary in collect(city):
				if query.intersects(record.footprint.grow(2)): all.append(record)
			return all
	# The union of the scan rectangles, visited once per cell in ascending
	# row-major order: per row, the sorted and merged column intervals.
	var spans: Dictionary = {}
	for region: Rect2i in regions:
		var scan := region.grow(_lot_scan_margin).intersection(bounds)
		if scan.size.x <= 0 or scan.size.y <= 0: continue
		for y: int in range(scan.position.y,scan.end.y):
			if not spans.has(y): spans[y] = []
			spans[y].append(Vector2i(scan.position.x,scan.end.x))
	var rows: Array = spans.keys()
	rows.sort()
	var bld: PackedInt32Array = city.building.data
	var zn: PackedByteArray = city.zone.data
	var sizes: PackedInt32Array = City._sizes
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for y: int in rows:
		var intervals: Array = spans[y]
		intervals.sort()
		var row := y*City.WIDTH
		var next := 0
		for interval: Vector2i in intervals:
			for x: int in range(maxi(interval.x,next),interval.y):
				var code := bld[row+x]
				if code < Buildings.RES_1X1_FIRST: continue
				var anchor := Vector2i(x,y) if sizes[code] == 0x0101 else City.footprint_anchor(bld,zn,x,y)
				var rect := Rect2i(anchor,Buildings.size(code))
				if not query.intersects(rect.grow(2)): continue
				var key := Vector3i(anchor.x,anchor.y,code)
				if seen.has(key): continue
				seen[key] = true
				records.append({"code":code,"footprint":rect,"anchor":anchor})
			next = maxi(next,interval.y)
	return records


## Remove all projected buildings.
func clear() -> void:
	_names_city = null
	last_updated_lots = 0
	_lot_buckets.clear()
	_lot_count = 0
	_missing_lots = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	missing.clear()


## Rebuild visible models, keeping terrain and building queries separate.
func rebuild(city: City, catalog: CityModelCatalog = null) -> void:
	clear()
	_names_city = city
	for record: Dictionary in collect(city):
		_add_record(city, catalog, record)


## Lot footprints, including removed lots, decide which query/physical bodies
## are replaced.
## A neighboring cell can change pier orientation or its connecting deck.
## `previous`/`current` are the view's complete geometry input layers before and
## after this change. A touched ordinary lot whose own inputs are identical in
## both keeps its model, bodies and batch membership.
func update_regions(city: City, catalog: CityModelCatalog, regions: Array[Rect2i], previous: Array = [], current: Array = []) -> Array[Rect2i]:
	last_updated_lots = 0
	last_retained_lots = 0
	var affected: Array[Rect2i] = []
	var query := RegionIndex.new(regions)
	var desired: Dictionary = {}
	var ordered: Array[Dictionary] = []
	for record: Dictionary in collect_regions(city,regions,query):
		if not query.intersects(record.footprint.grow(2)): continue
		desired[_record_key(record)] = record
		ordered.append(record)
	var comparable := previous.size() == 8 and current.size() == 8
	var kept: Dictionary = {}
	for child: Node in _lots_meeting(regions):
		var rect: Rect2i = child.get_meta("batch_region")
		if not query.intersects(rect.grow(2)): continue
		var key: String = child.get_meta("lot_key", "")
		if comparable and desired.has(key) and not _reads_neighbors(int(child.get_meta("code"))) and lot_inputs_equal(previous, current, desired[key]):
			kept[key] = true
			last_retained_lots += 1
			continue
		affected.append(rect)
		_unregister_lot(child)
		remove_child(child)
		child.queue_free()
	missing.clear()
	# Without a missing-model lot the recount below is empty.
	if _missing_lots != 0 or _lot_count != get_child_count():
		for child: Node in get_children():
			if child.get_meta("missing_model", false):
				var code: int = child.get_meta("code")
				missing[code] = int(missing.get(code, 0)) + 1
	for record: Dictionary in ordered:
		if kept.has(_record_key(record)): continue
		affected.append(record.footprint)
		_add_record(city, catalog, record)
	return affected


## Children whose dependency reach can meet `regions`, in child order. Falls
## back to every child when the bucket index does not account for all of them
## or a region is empty (whose engine predicate is not cell-based).
func _lots_meeting(regions: Array[Rect2i]) -> Array:
	if _lot_count != get_child_count(): return get_children()
	var found: Dictionary = {}
	for region: Rect2i in regions:
		if region.size.x <= 0 or region.size.y <= 0: return get_children()
		for by: int in range(floori(float(region.position.y)/LOT_BUCKET),floori(float(region.end.y-1)/LOT_BUCKET)+1):
			for bx: int in range(floori(float(region.position.x)/LOT_BUCKET),floori(float(region.end.x-1)/LOT_BUCKET)+1):
				var bucket: Dictionary = _lot_buckets.get(Vector2i(bx,by),{})
				for id: int in bucket: found[id] = bucket[id]
	var by_index: Dictionary = {}
	for id: int in found:
		var lot: Node = found[id]
		if not is_instance_valid(lot) or lot.get_parent() != self: return get_children()
		by_index[lot.get_index()] = lot
	var order := PackedInt64Array(by_index.keys())
	order.sort()
	var lots: Array = []
	for index: int in order: lots.append(by_index[index])
	return lots


func _lot_buckets_of(rect: Rect2i) -> Array[Vector2i]:
	var reach := rect.grow(2)
	var buckets: Array[Vector2i] = []
	for by: int in range(floori(float(reach.position.y)/LOT_BUCKET),floori(float(reach.end.y-1)/LOT_BUCKET)+1):
		for bx: int in range(floori(float(reach.position.x)/LOT_BUCKET),floori(float(reach.end.x-1)/LOT_BUCKET)+1):
			buckets.append(Vector2i(bx,by))
	return buckets


func _register_lot(model: Node3D) -> void:
	var id := model.get_instance_id()
	for bucket: Vector2i in _lot_buckets_of(model.get_meta("batch_region")):
		if not _lot_buckets.has(bucket): _lot_buckets[bucket] = {}
		_lot_buckets[bucket][id] = model
	_lot_count += 1
	if model.get_meta("missing_model", false): _missing_lots += 1


func _unregister_lot(model: Node) -> void:
	var id := model.get_instance_id()
	var listed := false
	for bucket: Vector2i in _lot_buckets_of(model.get_meta("batch_region")):
		var members: Dictionary = _lot_buckets.get(bucket,{})
		if members.erase(id): listed = true
		if members.is_empty(): _lot_buckets.erase(bucket)
	if not listed: return
	_lot_count -= 1
	if model.get_meta("missing_model", false): _missing_lots -= 1


static func _record_key(record: Dictionary) -> String:
	return "%d:%d:%d" % [record.anchor.x, record.anchor.y, record.code]


## Codes whose projection reads beyond their footprint and its shared ground
## vertices: runs of adjacent pieces, water fitting, street access, pier joins.
## They are always replaced when touched.
static func _reads_neighbors(code: int) -> bool:
	return code in [Buildings.MARINA, Buildings.PIER, Buildings.RUNWAY, Buildings.RUNWAY_CROSS,
		Buildings.RAIL_STATION, Buildings.SUBWAY_STATION] or Buildings.is_arcology(code)


## Whether every byte an ordinary lot's model placement, base height, support
## scan and query box read is identical in two complete geometry input layer
## sets (altitude, terrain, masked flags, native vertices, floods): the footprint
## plus the one-cell ring whose shared dry vertices it samples.
static func lot_inputs_equal(previous: Array, current: Array, record: Dictionary) -> bool:
	var footprint: Rect2i = record.footprint
	var rect := footprint.grow(1).intersection(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	for layer: int in [0, 1]:
		var before: Variant = previous[layer]
		var after: Variant = current[layer]
		if before.size() != after.size(): return false
		for y: int in range(rect.position.y, rect.end.y):
			var row := y * City.WIDTH
			for x: int in range(rect.position.x, rect.end.x):
				if before[row + x] != after[row + x]: return false
	var flags_before: PackedByteArray = previous[4]
	var flags_after: PackedByteArray = current[4]
	if flags_before.size() != flags_after.size(): return false
	var own := footprint.intersection(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	for y: int in range(own.position.y, own.end.y):
		for x: int in range(own.position.x, own.end.x):
			if flags_before[y * City.WIDTH + x] != flags_after[y * City.WIDTH + x]: return false
	var vertices_before: PackedByteArray = previous[5]
	var vertices_after: PackedByteArray = current[5]
	if vertices_before.size() != vertices_after.size(): return false
	if not vertices_before.is_empty():
		for vy: int in range(rect.position.y, rect.end.y + 1):
			for vx: int in range(rect.position.x, rect.end.x + 1):
				if vertices_before[vy * TerrainSurface.VERTS_X + vx] != vertices_after[vy * TerrainSurface.VERTS_X + vx]: return false
	var flood_before: Dictionary = previous[6]
	var flood_after: Dictionary = current[6]
	if not flood_before.is_empty() or not flood_after.is_empty():
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if flood_before.has(cell) != flood_after.has(cell) or flood_before.get(cell) != flood_after.get(cell): return false
	return true


## Matching geometry can keep every model while the simulated city changes.
func rebind_station_names(city: City) -> void:
	_names_city = city
	refresh_station_names([])


func refresh_station_names(anchors: Array[Vector2i]) -> void:
	if _names_city == null: return
	for model: Node3D in get_children():
		var anchor: Vector2i = model.get_meta("cell")
		if not anchors.is_empty() and anchor not in anchors: continue
		var sign := model.get_node_or_null("StationEntranceName") as Node3D
		if sign != null:
			StationEntrySign3D.set_title(sign,StationNameResolver.display_name(_names_city,anchor,int(model.get_meta("code"))==Buildings.SUBWAY_STATION))

static func _touches(rect: Rect2i, regions: Array[Rect2i]) -> bool:
	for region: Rect2i in regions:
		if rect.grow(2).intersects(region): return true
	return false


func _add_record(city: City, catalog: CityModelCatalog, record: Dictionary) -> void:
	_names_city = city
	last_updated_lots += 1
	var rect: Rect2i = record.footprint
	var code: int = record.code
	var ground := base_height(city, rect, code)
	var model: Node3D = catalog.instantiate_model(code) if catalog != null else null
	var missing_model := model == null
	var height := 0.35 + float((code - Buildings.RES_1X1_FIRST) % 16) * 0.12
	if Buildings.category(code) == Buildings.Category.ARCOLOGY:
		height = 4.0
	if model != null:
		height = float(catalog.entries[code].height)
		preload("res://scripts/view/city_lot_landscaping_3d.gd").add_to(model, code, catalog.entries[code])
	else:
		missing[code] = int(missing.get(code, 0)) + 1
		model = _placeholder(rect.size, height)
	model.position = Vector3(rect.position.x + rect.size.x * 0.5, ground, rect.position.y + rect.size.y * 0.5)
	if code in [Buildings.RUNWAY, Buildings.RUNWAY_CROSS, Buildings.PIER]:
		var east_west := _runs_east_west(city, record.anchor, code)
		# Runway markings are authored along Z; the timber pier runs along X.
		model.rotation.y = (0.0 if east_west else -PI / 2.0) if code == Buildings.PIER else (PI / 2.0 if east_west else 0.0)
	elif code == Buildings.MARINA:
		model.rotation.y = _marina_yaw(city, rect, ground)
		_fit_marina(city, rect, model, str(catalog.entries[code].get("glb_sha256", "")) if catalog != null and catalog.entries.has(code) else "")
	elif code in [Buildings.RAIL_STATION, Buildings.SUBWAY_STATION]:
		model.rotation.y = _station_yaw(city, rect, code)
	elif Buildings.is_arcology(code):
		model.rotation.y = resort_yaw(city, rect)
	if code in [Buildings.SUBWAY_STATION,Buildings.RAIL_STATION] and not missing_model:
		StationEntrySign3D.add_to(model,StationNameResolver.display_name(city,record.anchor,code==Buildings.SUBWAY_STATION),code==Buildings.RAIL_STATION)
	if not missing_model:
		preload("res://scripts/view/city_lot_support_3d.gd").add_to(model,city,code,
			str(code)+":"+str(catalog.entries[code]))
	model.set_meta("batch_region", rect)
	model.set_meta("missing_model", missing_model)
	model.set_meta("code", code)
	model.set_meta("cell", record.anchor)
	model.set_meta("lot_key", _record_key(record))
	# A projected lot never changes after this call; replacement makes a new node.
	model.set_meta("batch_immutable", true)
	add_child(model)
	_register_lot(model)
	var body := StaticBody3D.new()
	body.name = "BuildingQuery"
	body.collision_layer = QUERY_LAYER
	body.collision_mask = 0
	body.set_meta("cell", record.anchor)
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(rect.size.x * 0.85, height, rect.size.y * 0.85)
	shape.shape = volume
	shape.position.y = height / 2.0
	body.add_child(shape)
	model.add_child(body)
	if code == Buildings.PIER:
		_add_pier_join(city, record.anchor, model, body)


## Authored station fronts point along local +Z. Share connection selection with
## passenger access so the visible entrance describes the actual playable stop.
static func _station_yaw(city: City, rect: Rect2i, code: int) -> float:
	return StationStreetAccess.station_yaw(city,rect,code)

## Gaming resort main entrances are authored on local +Z. The front stays there
## while a street touches that side; otherwise it turns to the side with the
## most adjacent street cells (east, west, then north on ties). A lot with no
## adjacent street keeps its authored facing. Explore's door shares this yaw.
static func resort_yaw(city: City, rect: Rect2i) -> float:
	var front := Vector2i.DOWN
	var best := _street_frontage(city, rect, front)
	if best == 0:
		for facing: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
			var count := _street_frontage(city, rect, facing)
			if count > best:
				best = count
				front = facing
	return atan2(float(front.x), float(front.y))

## Street cells edge-adjacent to one side of `rect`. Tunnel and bridge decks
## are not at the lot's grade, so they are not a frontage.
static func _street_frontage(city: City, rect: Rect2i, facing: Vector2i) -> int:
	var start := Vector2i(rect.end.x if facing.x > 0 else rect.position.x - 1 if facing.x < 0 else rect.position.x,
		rect.end.y if facing.y > 0 else rect.position.y - 1 if facing.y < 0 else rect.position.y)
	var along := Vector2i(absi(facing.y), absi(facing.x))
	var count := 0
	for i: int in (rect.size.x if facing.y != 0 else rect.size.y):
		var cell := start + along * i
		if not city.in_bounds(cell.x, cell.y): continue
		var code := city.building.atv(cell)
		if NetworkShapes.in_road_family(code) and not NetworkShapes.is_tunnel(code) and not NetworkShapes.is_road_bridge(code):
			count += 1
	return count

## A connected run is authoritative: imported axis conventions differ, and
## native port development stamps either direction without setting AXIS.
static func _runs_east_west(city: City, cell: Vector2i, code: int) -> bool:
	var east_west := 0
	var north_south := 0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor := cell + step
		if not city.in_bounds(neighbor.x, neighbor.y):
			continue
		var other := city.building.atv(neighbor)
		var compatible := other == Buildings.PIER if code == Buildings.PIER else other in [Buildings.RUNWAY, Buildings.RUNWAY_CROSS]
		if compatible:
			if step.x != 0:
				east_west += 1
			else:
				north_south += 1
	if east_west != north_south:
		return east_west > north_south
	return not city.flags.has_bits(cell.x, cell.y, RotationMapper.AXIS_FLAG)


## Floating structures use water across the footprint, including a dry anchor.
## Ignore stale water words on dry cells; a raised shore is not a floating base.
static func base_height(city: City, rect: Rect2i, code: int) -> float:
	if code == Buildings.MARINA or code == Buildings.PIER:
		var levels: Array[float] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				if city.in_bounds(x, y) and city.is_water(x, y):
					levels.append(CityGeometry3D.water_surface_height(city, Vector2i(x, y)))
		if not levels.is_empty():
			levels.sort()
			return levels[levels.size() / 2]
	# A rigid authored floor must clear the entire grade, not just the anchor
	# center. Support geometry retains contact with the lower side of the lot.
	var height := CityGeometry3D.surface_height(city,rect.position)
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x):
			if not city.in_bounds(x,y): continue
			for corner: Vector3 in CityGeometry3D.visible_cell_corners(city,Vector2i(x,y)):
				height=maxf(height,corner.y)
	return height


## The authored rear landing points toward local -Z. Face the dry/raised bank
## rather than putting the floating fingers lengthwise through its slope.
static func _marina_yaw(city: City, rect: Rect2i, water: float) -> float:
	var shore := Vector2.ZERO
	var center := Vector2(rect.position) + Vector2(rect.size) * 0.5
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not city.in_bounds(x, y):
				continue
			var dry := 0.0 if city.is_water(x, y) else 1.0
			for corner: Vector3 in CityGeometry3D.visible_cell_corners(city, Vector2i(x, y)):
				dry += maxf(0.0, corner.y - water)
			shore += (Vector2(x + 0.5, y + 0.5) - center) * dry
	if shore.is_zero_approx():
		return 0.0
	if absf(shore.x) > absf(shore.y):
		return -PI / 2.0 if shore.x > 0 else PI / 2.0
	return PI if shore.y > 0 else 0.0


## Coastal lots can contain only a narrow water berth. Fit the authored scene
## uniformly, never below 45% size, keeping its boats above visible terrain
## and its complete geometry inside the lot. Queries keep the full lot box.
static func _fit_marina(city: City, rect: Rect2i, model: Node3D, source_key: String) -> void:
	var source: Dictionary = _marina_sources.get(source_key, {})
	if source.is_empty():
		source = {"points": [], "seen": {}, "bounds": AABB(), "has_bounds": false}
		for child: Node in model.get_children():
			_marina_geometry(child, Transform3D.IDENTITY, source)
		if source.points.is_empty():
			return
		_marina_sources[source_key] = source
	var original_yaw := model.rotation.y
	# One search reads each berth cell's water state and visible corners once;
	# every candidate still tests every boat point against the same values.
	var probe := {"cells": {}, "first": 0}
	# Prefer the shore-facing landing. Other quarter-turns are fallback choices
	# only if no proportionate fit at that heading clears the actual berth.
	for turn: int in [0, 1, -1, 2]:
		var yaw := original_yaw + turn * PI / 2.0
		var rotation := Basis(Vector3.UP, yaw)
		var rotated: AABB = Transform3D(rotation, Vector3.ZERO) * (source.bounds as AABB)
		var waterward := rotation * Vector3.BACK
		for size_step: int in 12:
			var factor := maxf(MIN_MARINA_SCALE, 1.0 - size_step * 0.05)
			var low := Vector2(-rect.size.x * 0.5 - rotated.position.x * factor, -rect.size.y * 0.5 - rotated.position.z * factor)
			var high := Vector2(rect.size.x * 0.5 - rotated.end.x * factor, rect.size.y * 0.5 - rotated.end.z * factor)
			if low.x > high.x or low.y > high.y:
				continue
			var offsets: Array[Vector2] = []
			for x: float in _fit_offsets(low.x, high.x):
				for z: float in _fit_offsets(low.y, high.y):
					offsets.append(Vector2(x, z))
			offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool:
				return a.dot(Vector2(waterward.x, waterward.z)) > b.dot(Vector2(waterward.x, waterward.z)))
			for offset: Vector2 in offsets:
				var origin := model.position + Vector3(offset.x, 0, offset.y)
				var transform := Transform3D(rotation.scaled(Vector3.ONE * factor), origin)
				if not _boats_clear_cached(city, source.points, transform, probe):
					continue
				model.rotation.y = yaw
				var fitted := Node3D.new()
				fitted.name = "MarineFit"
				fitted.scale = Vector3.ONE * factor
				fitted.position = rotation.inverse() * Vector3(offset.x, 0, offset.y)
				for child: Node in model.get_children():
					model.remove_child(child)
					fitted.add_child(child)
				model.add_child(fitted)
				return


static func _fit_offsets(low: float, high: float) -> Array[float]:
	var values: Array[float] = [clampf(0.0, low, high), low, high]
	var steps := maxi(1, ceili((high - low) / 0.125))
	for i: int in range(1, steps):
		values.append(lerpf(low, high, float(i) / steps))
	return values


static func _boats_clear(city: City, points: Array, transform: Transform3D) -> bool:
	for point: Vector3 in points:
		var placed := transform * point
		var cell := Vector2i(floori(placed.x), floori(placed.z))
		if not city.is_water(cell.x, cell.y):
			return false
		var offset := Vector2(placed.x - cell.x, placed.z - cell.y)
		if CityGeometry3D.visible_ground_height(city, cell, offset) > placed.y + 0.001:
			return false
	return true


## The same verdict as `_boats_clear`, which is an AND over independent point
## tests and so does not depend on their order: the point that rejected the
## previous candidate is tested first. A fit search reads each cell's water
## state, visible corners and facet diagonal once (the city is unchanged while
## one lot is projected); heights use the same interpolation call.
static func _boats_clear_cached(city: City, points: Array, transform: Transform3D, probe: Dictionary) -> bool:
	var count := points.size()
	var cells: Dictionary = probe.cells
	var first: int = probe.first
	for step: int in count:
		var index := (first + step) % count
		var placed := transform * (points[index] as Vector3)
		var cell := Vector2i(floori(placed.x), floori(placed.z))
		if not cells.has(cell):
			if city.is_water(cell.x, cell.y):
				var corners := CityGeometry3D.visible_cell_corners(city, cell)
				cells[cell] = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
			else:
				cells[cell] = false
		var ground: Variant = cells[cell]
		if not ground is Array:
			probe.first = index
			return false
		var offset := Vector2(placed.x - cell.x, placed.z - cell.y)
		if CityGeometry3D.point_over_facet(ground[0], ground[1], cell, offset).y > placed.y + 0.001:
			probe.first = index
			return false
	return true


## Geometry is gathered once per source hash; repeated lots reuse it. Imported
## physical shells follow the same fitted subtree as their authored meshes.
static func _marina_geometry(node: Node, transform: Transform3D, source: Dictionary) -> void:
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = transform * node.mesh.get_aabb()
		source.bounds = (source.bounds as AABB).merge(bounds) if source.has_bounds else bounds
		source.has_bounds = true
		var source_names: Array = node.get_meta("source_node_names", [])
		for surface: int in node.mesh.get_surface_count():
			var source_name := String(source_names[surface]) if surface < source_names.size() else String(node.name)
			if not source_name.ends_with(" boat"): continue
			var points: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in points:
				var placed := transform * point
				if not source.seen.has(placed):
					source.seen[placed] = true
					source.points.append(placed)
	for child: Node in node.get_children():
		_marina_geometry(child, transform, source)


## Join only matching neighboring pier runs at one water level. Four meters
## separates their authored decks; this support also belongs to the first pier
## for queries, without changing the lot footprint or the city data.
func _add_pier_join(city: City, cell: Vector2i, model: Node3D, query: StaticBody3D) -> void:
	var east_west := _runs_east_west(city, cell, Buildings.PIER)
	var next := cell + (Vector2i.RIGHT if east_west else Vector2i.DOWN)
	if not city.in_bounds(next.x, next.y) or city.building.atv(next) != Buildings.PIER:
		return
	if _runs_east_west(city, next, Buildings.PIER) != east_west:
		return
	if not is_equal_approx(model.position.y, base_height(city, Rect2i(next, Vector2i.ONE), Buildings.PIER)):
		return
	if _pier_join_mesh == null:
		_pier_join_mesh = BoxMesh.new()
		_pier_join_mesh.size = Vector3(4.02, 0.30, 7.7) / 16.0
	var join := MeshInstance3D.new()
	join.name = "PierJoin"
	join.mesh = _pier_join_mesh
	join.material_override = _pier_material(model)
	join.position = Vector3(0.5, 1.47 / 16.0, 0)
	model.add_child(join)
	var volume := BoxShape3D.new()
	volume.size = _pier_join_mesh.size
	var query_shape := CollisionShape3D.new()
	query_shape.name = "PierJoinQuery"
	query_shape.shape = volume
	query_shape.position = join.position
	query.add_child(query_shape)
	var shell := StaticBody3D.new()
	shell.collision_layer = CityModelCatalog.SHELL_LAYER
	shell.collision_mask = 0
	var physical := CollisionShape3D.new()
	physical.shape = volume
	shell.add_child(physical)
	join.add_child(shell)


## Reuse the authored deck material rather than introducing another wood color.
static func _pier_material(node: Node) -> Material:
	if node is MeshInstance3D and node.mesh != null:
		var source_names: Array = node.get_meta("source_node_names", [])
		for surface: int in node.mesh.get_surface_count():
			var source_name := String(source_names[surface]) if surface < source_names.size() else String(node.name)
			if source_name.ends_with(" deck_light"):
				return node.get_active_material(surface)
	for child: Node in node.get_children():
		var found := _pier_material(child)
		if found != null:
			return found
	return null


func _placeholder(size: Vector2i, height: float) -> Node3D:
	var model := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x * 0.82, height, size.y * 0.82)
	box.mesh = mesh
	box.position.y = height / 2.0
	box.material_override = CityGeometry3D.material(Color(0.65, 0.56, 0.45))
	model.add_child(box)
	var roof := MeshInstance3D.new()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(size.x * 0.68, 0.035, 0.08)
	roof.mesh = stripe
	roof.position.y = height + 0.02
	roof.material_override = CityGeometry3D.material(Color(0.98, 0.65, 0.23))
	model.add_child(roof)
	return model
