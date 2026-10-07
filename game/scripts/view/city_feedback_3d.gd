# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only transient feedback; never advances simulation or consumes random state.
class_name CityFeedback3D
extends Node3D

var city: City
var catalog: CityModelCatalog
var markers: Node3D
var power_markers: Node3D
var traffic: MultiMeshInstance3D
var disaster_visuals: Node3D
var _disaster_nodes: Dictionary = {}
var _signature := 0
var _power_signature: Variant = null
var _power_texture: Texture2D
var _power_geometry_signature: Variant = null
var _traffic_batch: MultiMesh
var _traffic_buffer := PackedFloat32Array()
var _catalog_key: Array = []
var _catalog_hash := 0


func _ready() -> void:
	markers = Node3D.new()
	markers.name = "IncidentMarkers"
	add_child(markers)
	power_markers = Node3D.new()
	power_markers.name = "PowerWarnings"
	add_child(power_markers)
	traffic = MultiMeshInstance3D.new()
	add_child(traffic)
	disaster_visuals = Node3D.new()
	disaster_visuals.name = "Disasters"
	add_child(disaster_visuals)
	sync_power()


## Attach the same city used by the other view layers.
func bind_city(value: City) -> void:
	city = value
	_signature = 0
	clear()
	sync_power()


## Remove all transient models immediately from this view.
func clear() -> void:
	_signature = 0
	_power_signature = null
	_power_geometry_signature = null
	if markers != null:
		for child: Node in markers.get_children():
			markers.remove_child(child)
			child.queue_free()
	if power_markers != null:
		for child: Node in power_markers.get_children():
			power_markers.remove_child(child)
			child.queue_free()
	if traffic != null:
		traffic.multimesh = null
	_sync_disasters([])


## Number of visible incident and response-crew markers.
func marker_count() -> int:
	return markers.get_child_count() if markers != null else 0


## Power warnings remain independent of vehicles, fire and response crews.
func power_warning_count() -> int:
	return power_markers.get_child_count() if power_markers != null else 0


## Project the power flags once per building footprint; the city is only read.
func sync_power(layers: Dictionary = {}) -> void:
	if city == null or power_markers == null:
		return
	if layers.is_empty(): layers = _layer_hashes()
	# Raw packed writes are public, so compare content rather than notifications.
	# Geometry and catalog data cannot create a warning: only inspect them when
	# a warning exists. Keep existing nodes when unrelated flags/terrain change.
	# Each layer is hashed once per call and shared with sync_runtime.
	var signature := hash([layers.flags, layers.building, layers.zone])
	if _power_signature == null or signature != _power_signature:
		_power_signature = signature
		var existing: Dictionary = {}
		for child: Node in power_markers.get_children():
			existing[child.get_meta("cell")] = child
		var seen: Dictionary = {}
		var buildings := city.building.data
		var flags := city.flags.data
		for i: int in buildings.size():
			var code := buildings[i]
			if code == Buildings.NONE or (flags[i] & (TileFlags.CONDUCTS_POWER | TileFlags.POWERED)) != TileFlags.CONDUCTS_POWER:
				continue
			# Bridges carry electricity but do not need an outage warning.
			if Buildings.category(code) == Buildings.Category.BRIDGE:
				continue
			var anchor := city.anchor_of(i % City.WIDTH, i / City.WIDTH)
			if seen.has(anchor):
				continue
			seen[anchor] = true
			var warning: Sprite3D = existing.get(anchor)
			if warning == null:
				_power_marker(anchor, code)
			else:
				existing.erase(anchor)
				if int(warning.get_meta("code")) != code:
					_power_marker(anchor, code, warning)
		for child: Node in existing.values():
			power_markers.remove_child(child)
			child.queue_free()
	if power_markers.get_child_count() == 0:
		_power_geometry_signature = null
		return
	var geometry_signature := hash([layers.altitude, layers.terrain, layers.flood,
		layers.vertices, _catalog_signature()])
	if _power_geometry_signature != null and geometry_signature == _power_geometry_signature:
		return
	_power_geometry_signature = geometry_signature
	for warning: Sprite3D in power_markers.get_children():
		_power_marker(warning.get_meta("cell"), int(warning.get_meta("code")), warning)


## One content hash per city layer read by the feedback signatures.
func _layer_hashes() -> Dictionary:
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	return {"flags": hash(city.flags.data), "building": hash(city.building.data), "zone": hash(city.zone.data),
		"altitude": hash(city.altitude.data), "terrain": hash(city.terrain.data), "flood": hash(city.flood_overlay),
		"vertices": hash(vertices)}


## Entry roof heights place warnings. The catalog's entries change only through
## load_manifest, so rehash them only for a new catalog or revision.
func _catalog_signature() -> int:
	if catalog == null: return hash({})
	var key := [catalog.get_instance_id(), catalog.revision, catalog.entries.size()]
	if key != _catalog_key:
		_catalog_key = key
		_catalog_hash = hash(catalog.entries)
	return _catalog_hash


func _power_marker(anchor: Vector2i, code: int, warning: Sprite3D = null) -> void:
	if _power_texture == null:
		_power_texture = _bolt_texture()
	var height := 0.75
	if catalog != null and catalog.entries.has(code):
		height = float(catalog.entries[code].height)
	elif code >= Buildings.RES_1X1_FIRST:
		height = 4.0 if Buildings.category(code) == Buildings.Category.ARCOLOGY else 0.35 + float((code - Buildings.RES_1X1_FIRST) % 16) * 0.12
	var size := Buildings.size(code)
	var roof := CityGeometry3D.surface_height(city, anchor) + height
	var is_new := warning == null
	if is_new:
		warning = Sprite3D.new()
	warning.name = "PowerWarning"
	warning.texture = _power_texture
	warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warning.shaded = false
	warning.no_depth_test = true
	warning.pixel_size = 0.016
	warning.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	warning.position = Vector3(anchor.x + size.x * 0.5, roof + 0.5, anchor.y + size.y * 0.5)
	warning.set_meta("cell", anchor)
	warning.set_meta("code", code)
	warning.set_meta("roof_height", roof)
	if is_new:
		power_markers.add_child(warning)


## A yellow lightning bolt with a dark outline stays readable at every camera
## direction and shares no geometry with the incident markers.
static func _bolt_texture() -> Texture2D:
	var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	var polygon := PackedVector2Array([Vector2(18, 3), Vector2(5, 26), Vector2(15, 26),
		Vector2(11, 45), Vector2(28, 18), Vector2(19, 18), Vector2(24, 3)])
	for y: int in 48:
		for x: int in 32:
			var point := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(point, polygon):
				image.set_pixel(x, y, Color(1.0, 0.82, 0.12))
				continue
			for offset: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				if Geometry2D.is_point_in_polygon(point + offset * 1.5, polygon):
					image.set_pixel(x, y, Color(0.16, 0.11, 0.04))
					break
	return ImageTexture.create_from_image(image)


## Accept the public entity helper's normalized records, including incidents.
func sync_records(records: Array) -> void:
	var vehicles: Array = []
	var incidents: Array[Dictionary] = []
	var fires: Array[Vector2i] = []
	var crews: Dictionary = {}
	for raw: Variant in records:
		var record := CityEntityRecords.normalize(raw, &"car")
		if record.is_empty():
			continue
		var position: Vector2 = record.pos
		if not position.is_finite() or city == null or not city.in_bounds(int(position.x), int(position.y)):
			continue
		if CityDisasterVisual3D.KINDS.has(record.kind) or (record.kind == &"plane" and record.get("source", &"") == &"disasters"):
			incidents.append(record)
		elif record.kind == &"fire":
			fires.append(Vector2i(position))
		elif String(record.kind).ends_with("_crew"):
			crews[Vector2i(position)] = true
		else:
			vehicles.append(record)
	_sync_disasters(incidents)
	sync_runtime(vehicles, {"fires": fires}, crews)


func _sync_disasters(records: Array) -> void:
	if disaster_visuals == null: return
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	for record: Dictionary in records:
		var kind: StringName = record.kind
		var index := int(counts.get(kind, 0))
		counts[kind] = index + 1
		var key := "%s:%d" % [kind, index]
		seen[key] = true
		var visual: CityDisasterVisual3D = _disaster_nodes.get(key)
		if visual == null:
			visual = CityDisasterVisual3D.new()
			visual.build(kind)
			disaster_visuals.add_child(visual)
			var initial_pos: Vector2 = record.pos
			visual.set_animation_phase(float(posmod(int(initial_pos.x) * 73 + int(initial_pos.y) * 157, 997)) / 997.0)
			_disaster_nodes[key] = visual
		var pos: Vector2 = record.pos
		visual.position = Vector3(pos.x + 0.5, CityGeometry3D.surface_height(city, Vector2i(pos)), pos.y + 0.5)
		visual.rotation.y = -float(record.heading) * PI / 4.0
	for key: String in _disaster_nodes.keys():
		if seen.has(key): continue
		var visual: CityDisasterVisual3D = _disaster_nodes[key]
		disaster_visuals.remove_child(visual)
		visual.queue_free()
		_disaster_nodes.erase(key)


## Synchronize external snapshots without retaining mutable simulation records.
func sync_runtime(vehicles: Array, events: Dictionary, utility_cells: Dictionary) -> void:
	if city == null or markers == null:
		return
	var layers := _layer_hashes()
	sync_power(layers)
	var signature := hash([events, utility_cells, layers.altitude, layers.terrain,
		layers.building, layers.zone, layers.vertices, layers.flood])
	if signature != _signature:
		_signature = signature
		var remaining_fires: Dictionary = {}
		for child: Node in markers.get_children():
			if child is CityDisasterVisual3D and child.has_meta("fire_cell"):
				remaining_fires[child.get_meta("fire_cell")] = child
				continue
			markers.remove_child(child)
			child.queue_free()
		for cell: Vector2i in events.get("fires", []):
			_fire_marker(cell, remaining_fires.get(cell))
			remaining_fires.erase(cell)
		for child: Node in remaining_fires.values():
			markers.remove_child(child)
			child.queue_free()
		for cell: Vector2i in utility_cells:
			_marker(cell, Color(1, 0.84, 0.15), 0.3)
	var valid: Array[Dictionary] = []
	for raw: Variant in vehicles:
		var record := CityEntityRecords.normalize(raw, &"car")
		if record.is_empty():
			continue
		var pos: Vector2 = record.pos
		if pos.is_finite() and pos.x >= 0 and pos.y >= 0 and pos.x < City.WIDTH and pos.y < City.HEIGHT:
			valid.append(record)
	if valid.is_empty():
		traffic.multimesh = null
		return
	if _traffic_batch == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 0.12, 0.3)
		mesh.material = CityGeometry3D.material(Color(0.95, 0.8, 0.55))
		_traffic_batch = MultiMesh.new()
		_traffic_batch.transform_format = MultiMesh.TRANSFORM_3D
		_traffic_batch.mesh = mesh
	var batch := _traffic_batch
	if valid.size() > batch.instance_count:
		batch.instance_count = maxi(valid.size(), maxi(16, batch.instance_count * 2))
		_traffic_buffer.resize(batch.instance_count * 12)
	batch.visible_instance_count = valid.size()
	for i: int in valid.size():
		var record: Dictionary = valid[i]
		var pos: Vector2 = record.pos
		var altitude := float(record.altitude) if is_finite(float(record.altitude)) else 0.0
		var ground := CityGeometry3D.ground_height(city, Vector2i(pos))
		var pose := Transform3D(Basis(Vector3.UP, float(record.heading) * PI / 4.0),
			Vector3(pos.x + 0.5, ground + 0.13 + altitude * CityGeometry3D.HEIGHT, pos.y + 0.5))
		var offset := i * 12
		_traffic_buffer[offset] = pose.basis.x.x
		_traffic_buffer[offset + 1] = pose.basis.y.x
		_traffic_buffer[offset + 2] = pose.basis.z.x
		_traffic_buffer[offset + 3] = pose.origin.x
		_traffic_buffer[offset + 4] = pose.basis.x.y
		_traffic_buffer[offset + 5] = pose.basis.y.y
		_traffic_buffer[offset + 6] = pose.basis.z.y
		_traffic_buffer[offset + 7] = pose.origin.y
		_traffic_buffer[offset + 8] = pose.basis.x.z
		_traffic_buffer[offset + 9] = pose.basis.y.z
		_traffic_buffer[offset + 10] = pose.basis.z.z
		_traffic_buffer[offset + 11] = pose.origin.z
	batch.buffer = _traffic_buffer
	traffic.multimesh = batch


func _fire_marker(cell: Vector2i, node: CityDisasterVisual3D = null) -> void:
	if not city.in_bounds(cell.x, cell.y): return
	var is_new := node == null
	if is_new:
		node = CityDisasterVisual3D.new()
		node.build(&"fire")
		node.set_meta("fire_cell", cell)
	var floor := CityGeometry3D.surface_height(city, cell)
	var code := city.building_at(cell.x, cell.y)
	if catalog != null and catalog.entries.has(code):
		var footprint := Rect2i(city.anchor_of(cell.x, cell.y), Buildings.size(code))
		floor = CityBuildings3D.base_height(city, footprint, code) + float(catalog.entries[code].height)
	node.position = Vector3(cell.x + 0.5, floor, cell.y + 0.5)
	if is_new:
		markers.add_child(node)
		node.set_animation_phase(float(posmod(cell.x * 73 + cell.y * 157, 997)) / 997.0)


func _marker(cell: Vector2i, color: Color, height: float) -> void:
	if not city.in_bounds(cell.x, cell.y):
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = 0.18
	mesh.height = height
	mesh.radial_segments = 5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = CityGeometry3D.material(color)
	node.position = Vector3(cell.x + 0.5, CityGeometry3D.ground_height(city, cell) + height / 2.0 + 0.3, cell.y + 0.5)
	markers.add_child(node)
