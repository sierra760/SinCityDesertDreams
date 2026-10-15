# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CityLivestock3D
extends Node3D
## Cosmetic actors live beside the compiled city, never inside its static batches.
## Distances are tile-space; profiles and animal instances stay in authored metres.
const DETAIL_LIMIT := 96
const NEAR_TILES := 8.0
const FAR_TILES := 32.0
var buildings: CityBuildings3D
var agriculture: CityAgriculture3D
var _city: City
var _catalog := AgricultureAssetCatalog.new()
var _herds: Dictionary = {}
var _static_geometry: Dictionary = {}
var _source: AgricultureSystem
var _source_dirty := true
var _source_revision := -1
var _source_buildings := PackedInt32Array()
var _source_zones := PackedByteArray()
var _source_lots: Array[Dictionary] = []

func _init() -> void:
	_catalog.load_manifest("res://assets/agriculture/enclosures.json")
	# Cache and release the three temporary neutral sources before any live rigs.
	for species: StringName in AgricultureAssetCatalog.MODELS: _neutral_geometry(species)

func bind_city(city: City) -> void:
	if city == _city: return
	clear()
	_city = city

func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_herds.clear()
	_source = null
	_source_dirty = true
	_source_revision = -1
	_source_buildings = PackedInt32Array()
	_source_zones = PackedByteArray()
	_source_lots.clear()

## Notifications cover producer changes and rebuilt authored transforms. Exact
## native packed-array comparisons also detect raw writes and late additions;
## no GDScript whole-city walk or lossy fingerprint is needed on steady frames.
func invalidate_source() -> void:
	_source_dirty = true

func sync_source(source: AgricultureSystem) -> void:
	if source == null or _city == null:
		if _source != null or not _herds.is_empty(): clear()
		return
	if source != _source or _source_dirty or _source_revision != _city.agricultural_parcels.revision or _source_buildings != _city.building.data or _source_zones != _city.zone.data:
		_source = source
		if is_instance_valid(agriculture): agriculture.flush_changes()
		_source_lots = source.current_lots()
		_source_revision = _city.agricultural_parcels.revision
		_source_buildings = _city.building.data.duplicate()
		_source_zones = _city.zone.data.duplicate()
		_source_dirty = false
		sync_lots(_source_lots)
	else:
		# Keep immediate removal independent of motion, visibility and pause.
		# This visits only known stock footprints, never all 16,384 city cells.
		for key: String in _herds.keys():
			var herd: Dictionary = _herds[key]
			if herd.parcel_id == 0 and not _valid_footprint(herd.rect,herd.code): _remove(key)

func detailed_animal_count() -> int:
	var total := 0
	for herd: Dictionary in _herds.values():
		if herd.detail == 2: total += herd.count
	return total

func sync_lots(lots: Array[Dictionary]) -> void:
	var retained: Dictionary = {}
	if _city != null:
		for lot: Dictionary in lots:
			if lot.get("state") != &"active": continue
			var anchor: Vector2i = lot.anchor
			var code: int = lot.building_id
			var rect: Rect2i = lot.rect
			var parcel_id: int = lot.get("parcel_id",0)
			var key := String(lot.get("source_key","legacy:%d:%d" % [anchor.x,anchor.y]))
			var record := _city.agricultural_parcels.record(parcel_id) if parcel_id != 0 else {}
			var profile: Dictionary
			var at: Transform3D
			var signature: String
			var seed_value: int
			if parcel_id != 0:
				if record.is_empty() or record.state != &"active" or record.revision != lot.revision: continue
				# The retained static consumer owns the exact profile and transform.
				# Only standalone consumers plan without that retained presentation.
				var actual := agriculture.record_for_parcel(parcel_id) if is_instance_valid(agriculture) else {}
				if is_instance_valid(agriculture):
					if actual.is_empty() or actual.revision != record.revision: continue
					profile = actual.layout.profile
					at = actual.transform
				else:
					profile = AgriculturalParcelGeometry.plan(record).profile
					at = CityAgriculture3D.parcel_transform(_city,record)
				signature = str([AgriculturalParcelGeometry.presentation_inputs(record),at,code])
				seed_value = record.layout_seed ^ int(record.id)
			else:
				if not _valid_footprint(rect,code): continue
				profile = _catalog.profile(lot.archetype)
				at = _lot_transform(anchor,rect,code)
				signature = str([code,rect,lot.archetype])
				seed_value = anchor.y*City.WIDTH+anchor.x+code*65536
			if profile.is_empty(): continue
			var count := 0
			for pen: Dictionary in profile.pens: count += pen.spawns.size()
			if count <= 0 or count > 12: continue
			if _herds.has(key) and _herds[key].signature != signature: _remove(key)
			if not _herds.has(key):
				_herds[key] = {"signature":signature,"profile":profile,"count":count,
					"seed":seed_value,"root":null,"motion":null,"detail":0,"rect":rect,"code":code,
					"source_key":key,"parcel_id":parcel_id,"revision":record.get("revision",0),
					"generated":record.get("mode") == &"generated","origin":record.get("origin_index",0),
					"transform":at}
			var herd: Dictionary = _herds[key]
			herd.revision = record.get("revision",0)
			herd.transform = at
			if is_instance_valid(herd.root): herd.root.transform = at
			retained[key] = true
	for key: String in _herds.keys():
		if not retained.has(key): _remove(key)

func _valid_footprint(rect: Rect2i, code: int) -> bool:
	if not Buildings.is_agricultural(code): return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not _city.in_bounds(x,y) or _city.building.at(x,y) != code: return false
	return true

func _lot_transform(anchor: Vector2i, rect: Rect2i, code: int) -> Transform3D:
	if is_instance_valid(buildings):
		var actual: Variant = buildings.authored_lot_transform(anchor,code)
		if actual is Transform3D: return actual
	# Before a first geometry rebuild, the canonical agriculture models have
	# zero yaw/pivot and the same 1/16 metre scale as the catalog.
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / 16.0),
		Vector3(rect.position.x+rect.size.x*.5,CityBuildings3D.base_height(_city,rect,code),rect.position.y+rect.size.y*.5))

func advance(delta: float, camera: Camera3D, paused: bool, player_world: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return
	var ordered: Array[Dictionary] = []
	var frustum: Array[Plane] = []
	var viewport := camera.get_viewport()
	# A detached/zero-sized viewport has no usable projection. Keep stable
	# distance ordering in that case, without asking the engine for planes.
	if viewport != null and viewport.get_visible_rect().size.x > 0 and viewport.get_visible_rect().size.y > 0 and camera.get_world_3d() != null:
		frustum = camera.get_frustum()
	for key: String in _herds:
		var herd: Dictionary = _herds[key]
		var origin: Vector3 = global_transform * herd.transform.origin
		var focus := camera.global_position
		if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			var direction := -camera.global_basis.z
			if absf(direction.y) > .00001:
				focus += direction * ((origin.y-focus.y)/direction.y)
		var bounds := _herd_bounds(herd)
		var distance := Vector2(focus.x-origin.x,focus.z-origin.z).length()
		if herd.generated:
			# A saved lattice origin can lie far outside surviving members.
			# Bands use the nearest extent of the actual transformed footprint.
			var box := AABB(bounds[0],Vector3.ZERO)
			for corner in bounds: box = box.expand(corner)
			var closest := Vector2(clampf(focus.x,box.position.x,box.end.x),clampf(focus.z,box.position.z,box.end.z))
			distance = Vector2(focus.x,focus.z).distance_to(closest)
		var pixels := _projected_pixels(camera,origin,bounds)
		var detail := 0 if distance > FAR_TILES or pixels < 2.0 else (2 if distance <= NEAR_TILES else 1)
		ordered.append({"key":key,"anchor":herd.rect.position,"distance":distance,"detail":detail,"visible":_intersects_frustum(bounds,frustum)})
	ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.visible != b.visible: return a.visible
		if not is_equal_approx(a.distance,b.distance): return a.distance < b.distance
		return a.anchor.y < b.anchor.y if a.anchor.y != b.anchor.y else a.anchor.x < b.anchor.x)
	var remaining := DETAIL_LIMIT
	for item: Dictionary in ordered:
		var herd: Dictionary = _herds[item.key]
		if item.detail == 2:
			if herd.count <= remaining: remaining -= herd.count
			else: item.detail = 1
	# Release every downgraded rig first: even during camera moves, allocation
	# never temporarily exceeds the budget while a new near herd is promoted.
	for item: Dictionary in ordered:
		var herd: Dictionary = _herds[item.key]
		if herd.detail != item.detail: _release_representation(herd)
	for item: Dictionary in ordered:
		var herd: Dictionary = _herds[item.key]
		if item.detail != herd.detail: _represent(herd,item.detail)
		if herd.detail != 2 or paused or not is_visible_in_tree(): continue
		var local_player: Vector3 = herd.transform.affine_inverse()*player_world if player_world.is_finite() else Vector3.INF
		herd.motion.advance(delta,local_player)
		var states: Array = herd.motion.states()
		for i: int in states.size(): herd.root.get_child(i).apply_state(states[i],0.0)

func _herd_bounds(herd: Dictionary) -> PackedVector3Array:
	# The entire canonical footprint conservatively encloses every assigned pen.
	# The articulated body reach also pads the vertical extent for every pose.
	var half: Vector2 = Vector2(herd.rect.size) * 8.0
	var minimum := -half
	var maximum := half
	if herd.generated:
		var origin := AgriculturalParcels.tile(herd.origin)
		minimum = Vector2(herd.rect.position-origin)*16.0
		maximum = Vector2(herd.rect.end-origin)*16.0
	var reach: float = herd.profile.body_radius
	var low := 0.0
	var high := reach * 2.0
	for pen: Dictionary in herd.profile.pens:
		low = minf(low,pen.ground_y-reach)
		high = maxf(high,pen.ground_y+reach*2.0)
	var points := PackedVector3Array()
	var at: Transform3D = global_transform * herd.transform
	for x: float in [minimum.x,maximum.x]:
		for y: float in [low,high]:
			for z: float in [minimum.y,maximum.y]: points.append(at*Vector3(x,y,z))
	return points

func _intersects_frustum(points: PackedVector3Array, planes: Array[Plane]) -> bool:
	# Reject only when every corner lies outside one plane. Unlike an anchor
	# test, this retains edge, near-plane and camera-inside intersections.
	for plane: Plane in planes:
		var outside := true
		for point: Vector3 in points:
			if plane.distance_to(point) <= .00001:
				outside = false
				break
		if outside: return false
	return true

func _projected_pixels(camera: Camera3D, point: Vector3, bounds: PackedVector3Array) -> float:
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0: return 0.0
	# A conservative one-metre animal height in tile units. Orthographic height
	# uses KEEP_WIDTH when selected; perspective uses camera-space depth.
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var extent := camera.size
		if camera.keep_aspect == Camera3D.KEEP_WIDTH: extent *= viewport_size.y / maxf(viewport_size.x,1.0)
		return viewport_size.y / maxf(extent,0.001) / 16.0
	var depth := -camera.to_local(point).z
	# Use the nearest visible depth, including extensions away from the origin.
	for corner: Vector3 in bounds: depth = minf(depth,-camera.to_local(corner).z)
	if depth <= camera.near:
		# Centre depth alone cannot reject a lot straddling the near plane.
		var farthest := depth
		for corner: Vector3 in bounds: farthest = maxf(farthest,-camera.to_local(corner).z)
		if farthest <= camera.near: return 0.0
		depth = camera.near
	var vertical_fov := deg_to_rad(camera.fov)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		vertical_fov = 2.0*atan(tan(vertical_fov*.5)*viewport_size.y/maxf(viewport_size.x,1.0))
	return viewport_size.y / (2.0*tan(vertical_fov*.5)*depth) / 16.0

func _represent(herd: Dictionary, detail: int) -> void:
	herd.detail = detail
	if detail == 0: return
	var holder := Node3D.new()
	herd.root = holder
	add_child(holder)
	holder.transform = herd.transform
	if detail == 2:
		# Re-entry deliberately reconstructs private cosmetic state from the
		# saved private seed. Far herds retain neither rigs nor path graphs.
		var motion := LivestockMotion.new()
		motion.configure(herd.profile,herd.seed)
		herd.motion = motion
		var states := motion.states()
		for i: int in states.size():
			var animal := LivestockVisual.new()
			animal.configure(herd.profile.species,herd.seed+i,_catalog)
			holder.add_child(animal)
			animal.apply_state(states[i],0.0)
	else:
		var parts := _neutral_geometry(herd.profile.species)
		for part: Dictionary in parts:
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = part.mesh
			instances.instance_count = herd.count
			var index := 0
			for pen: Dictionary in herd.profile.pens:
				for spawn: Array in pen.spawns:
					instances.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(spawn[0],pen.ground_y,spawn[1]))*part.transform)
					index += 1
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = instances
			instance.material_override = part.material
			holder.add_child(instance)

func _neutral_geometry(species: StringName) -> Array[Dictionary]:
	if not _static_geometry.has(species):
		var source := _catalog.make_animal(species)
		var parts: Array[Dictionary] = []
		if source != null:
			_collect_geometry(source,Transform3D.IDENTITY,parts)
			source.free()
		_static_geometry[species] = parts
	return _static_geometry[species]

func _collect_geometry(node: Node, parent: Transform3D, parts: Array[Dictionary]) -> void:
	var at: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		parts.append({"mesh":node.mesh,"transform":at,"material":node.material_override})
	for child: Node in node.get_children(): _collect_geometry(child,at,parts)

func _release_representation(herd: Dictionary) -> void:
	if is_instance_valid(herd.root):
		remove_child(herd.root)
		herd.root.free()
	herd.root = null
	herd.motion = null
	herd.detail = 0

func _remove(key: String) -> void:
	_release_representation(_herds[key])
	_herds.erase(key)


func _exit_tree() -> void:
	clear()
