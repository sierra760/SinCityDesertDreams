# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Applies street-name edits to a city. The host binds a city before use, and
## rebinding clears the selection. Topology revision tokens are unique only for
## the running session, so they must never be saved.
class_name StreetNamingService
extends RefCounted

const Codec := preload("res://scripts/core/naming/street_naming_codec.gd")
signal changed(revision: int, affected: Dictionary)
var revision := 0
var _city: City
var _topology: StreetTopology
var _station_allocator: Callable
var _allocating := false
var _publishing := false
## Complete inputs of the last reconciliation, captured after its commit.
var _reconciled: Array = []

func _affected() -> Dictionary:
	return {"links":[],"street_ids":[],"station_anchors":[]}

func _result(ok: bool, error: String = "", did_change: bool = false, street_id: int = 0, affected: Dictionary = {}) -> Dictionary:
	return {"ok":ok,"error":error,"changed":did_change,"revision":revision,"street_id":street_id,"affected":_affected() if affected.is_empty() else affected.duplicate(true)}

func set_station_allocator(callback: Callable) -> void:
	_station_allocator = callback

func _station_exists(city: City, anchor: Vector2i) -> bool:
	var code := city.building.atv(anchor)
	if code not in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]: return false
	if city.anchor_of(anchor.x,anchor.y)!=anchor: return false
	if city.facilities.has(anchor):
		var record: Variant = city.facilities[anchor]
		if typeof(record)!=TYPE_DICTIONARY or record.get("key",&"")!=Buildings.key(code): return false
	return true

func _station_types(city: City, metadata: Dictionary) -> bool:
	for anchor: Vector2i in metadata.station_auto:
		if not _station_exists(city,anchor): return false
	return true

func bind_city(city: City, topology: StreetTopology) -> Dictionary:
	if _allocating or _publishing: return _result(false,"A naming transaction is already in progress.")
	if city==null or topology==null or not topology.is_bound_to(city): return _result(false,"Street topology does not belong to this city.")
	var valid := Codec.validate(city.street_naming)
	if not valid.ok: return _result(false,valid.error)
	# Well-formed automatic records may outlive infrastructure in a saved
	# snapshot. Allocation below prunes/repairs them before publication.
	topology.rebuild(city)
	var draft: Dictionary = valid.metadata
	_prune_links(draft,topology)
	_retire_unused(draft)
	var allocation := _allocate(city,topology,draft)
	if not allocation.ok: return _result(false,allocation.error)
	_city = city
	_topology = topology
	return _commit(draft,0,allocation.changed_anchors)

## Refresh BEFORE comparing tokens: unnotified demolition must reject the old
## selection as a whole, without reconciling committed naming as a side effect.
func _ready() -> Dictionary:
	if _allocating or _publishing: return _result(false,"A naming transaction is already in progress.")
	if _city==null or _topology==null or not _topology.is_bound_to(_city): return _result(false,"The naming city or topology binding changed. Retry selection.")
	_topology.rebuild(_city)
	var valid := Codec.validate(_city.street_naming)
	return valid

func _selection(keys: Array[String], expected_revision: int) -> Dictionary:
	var ready := _ready()
	if not ready.ok: return _result(false,ready.error)
	if expected_revision!=_topology.revision: return _result(false,"Street layout changed. Retry selection.")
	if keys.is_empty(): return _result(false,"Select at least one street connection.")
	var seen: Dictionary = {}
	for key: String in keys:
		if seen.has(key) or not Codec.valid_link_key(key) or not _topology.has_link(key): return _result(false,"Street selection is invalid or stale. Retry selection.")
		seen[key] = true
	return ready

func assign(keys: Array[String], text: String, expected_topology_revision: int) -> Dictionary:
	var selection := _selection(keys,expected_topology_revision)
	if not selection.ok: return selection
	var name := Codec.normalize_name(text)
	if not name.ok: return _result(false,name.error)
	var draft: Dictionary = selection.metadata
	var existing := 0
	for id: int in draft.streets:
		if String(draft.streets[id]).to_lower()==name.comparison: existing = id; break
	var whole_id := int(draft.links.get(keys[0],0))
	if whole_id>0:
		for key: String in keys:
			if int(draft.links.get(key,0))!=whole_id: whole_id = 0; break
	if whole_id>0:
		var count := 0
		for id: int in draft.links.values():
			if id==whole_id: count += 1
		if count!=keys.size(): whole_id = 0
	var target := existing
	if whole_id>0 and (existing==0 or existing==whole_id):
		target = whole_id
		draft.streets[target] = name.display
	elif target==0:
		if draft.next_street_id==9223372036854775807: return _result(false,"Street ID capacity is exhausted.")
		target = draft.next_street_id
		draft.next_street_id += 1
		draft.streets[target] = name.display
	for key: String in keys: draft.links[key] = target
	_retire_unused(draft)
	var allocation := _allocate(_city,_topology,draft)
	if not allocation.ok: return _result(false,allocation.error)
	return _commit(draft,target,allocation.changed_anchors)

func remove(keys: Array[String], expected_topology_revision: int) -> Dictionary:
	var selection := _selection(keys,expected_topology_revision)
	if not selection.ok: return selection
	var draft: Dictionary = selection.metadata
	for key: String in keys: draft.links.erase(key)
	_retire_unused(draft)
	var allocation := _allocate(_city,_topology,draft)
	if not allocation.ok: return _result(false,allocation.error)
	return _commit(draft,0,allocation.changed_anchors)

func _prune_links(draft: Dictionary, topology: StreetTopology) -> void:
	for key: String in draft.links.keys():
		if not topology.has_link(key): draft.links.erase(key)

func _retire_unused(draft: Dictionary) -> void:
	var used: Dictionary = {}
	for id: int in draft.links.values(): used[id] = true
	for id: int in draft.streets.keys():
		if not used.has(id): draft.streets.erase(id)

func _allocate(city: City, topology: StreetTopology, draft: Dictionary) -> Dictionary:
	var anchors: Array[Vector2i] = []
	if _station_allocator.is_valid():
		# The allocator must not change the city. Only the station records it
		# returns are used; edits to the draft copy it receives are ignored.
		_allocating = true
		var response: Variant = _station_allocator.call(city,topology,draft.duplicate(true))
		_allocating = false
		if typeof(response)!=TYPE_DICTIONARY or typeof(response.get("ok"))!=TYPE_BOOL or not response.ok:
			return {"ok":false,"error":String(response.get("error","Station allocation failed.")) if typeof(response)==TYPE_DICTIONARY else "Invalid station allocator response.","changed_anchors":[]}
		if typeof(response.get("station_auto"))!=TYPE_DICTIONARY or typeof(response.get("changed_anchors"))!=TYPE_ARRAY:
			return {"ok":false,"error":"Invalid station allocator response.","changed_anchors":[]}
		for anchor: Variant in response.changed_anchors:
			if not Codec.valid_anchor(anchor): return {"ok":false,"error":"Invalid affected station anchor.","changed_anchors":[]}
			if not anchors.has(anchor): anchors.append(anchor)
		draft.station_auto = response.station_auto.duplicate(true)
	else:
		# Without an allocator, drop stations that no longer exist or whose
		# streets are gone, and keep the rest unchanged for the next allocation.
		for anchor: Vector2i in draft.station_auto.keys():
			var valid := _station_exists(city,anchor)
			for id: int in draft.station_auto[anchor].source_street_ids:
				if not draft.streets.has(id): valid = false
			if not valid: draft.station_auto.erase(anchor)
	var validated := Codec.validate(draft)
	if not validated.ok: return {"ok":false,"error":validated.error,"changed_anchors":[]}
	if not _station_types(city,draft): return {"ok":false,"error":"Automatic metadata does not reference a current station.","changed_anchors":[]}
	return {"ok":true,"error":"","changed_anchors":anchors}

func reconcile(_changed_rect: Rect2i) -> Dictionary:
	var ready := _ready()
	if not ready.ok: return _result(false,ready.error)
	# Reconciliation is a function of the current structure, station cells,
	# water, custom facility names and committed metadata. Unchanged inputs
	# reproduce the committed state, so the day's growth elsewhere costs nothing.
	var inputs := _reconcile_inputs()
	if inputs == _reconciled: return _result(true,"",false,0,_affected())
	# Topology currently rebuilds citywide; pruning all keys also catches
	# simulation-originated destruction outside a caller's advisory rectangle.
	var draft: Dictionary = ready.metadata
	_prune_links(draft,_topology)
	_retire_unused(draft)
	var allocation := _allocate(_city,_topology,draft)
	if not allocation.ok: return _result(false,allocation.error)
	var result := _commit(draft,0,allocation.changed_anchors)
	_reconciled = _reconcile_inputs()
	return result

## Everything the pruning, station allocation and commit read: the topology's
## complete projected structure and heights, each station's code and the raw
## building/altitude/terrain/flood bytes of its footprint plus the access radius
## and shared-vertex ring, custom facility names and the committed metadata.
## Lot growth away from stations leaves all of these unchanged.
func _reconcile_inputs() -> Array:
	var stations: Array = []
	var codes := _city.building.data
	for station_code: int in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
		var index := codes.find(station_code)
		while index >= 0:
			var cell := Vector2i(index % City.WIDTH,index / City.WIDTH)
			if _city.anchor_of(cell.x,cell.y) == cell:
				var rect := Rect2i(cell,Buildings.size(station_code)).grow(StationStreetAccess.RADIUS+1).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
				var bytes := PackedInt32Array()
				for y: int in range(rect.position.y,rect.end.y):
					for x: int in range(rect.position.x,rect.end.x):
						var i := y*City.WIDTH+x
						bytes.append(codes[i]); bytes.append(_city.altitude.data[i]); bytes.append(_city.terrain.data[i])
						bytes.append(int(_city.flood_overlay.has(Vector2i(x,y))))
				stations.append([cell,station_code,bytes])
			index = codes.find(station_code,index+1)
	return [_topology.revision,_topology._projection_state,stations,
		_city.facilities.duplicate(true),_city.street_naming.duplicate(true)]

func refresh_station_names(changed_manual: Array[Vector2i] = []) -> Dictionary:
	var ready := _ready()
	if not ready.ok: return _result(false,ready.error)
	for anchor: Vector2i in changed_manual:
		if not Codec.valid_anchor(anchor) or not _station_exists(_city,anchor): return _result(false,"Manual title refresh requires a current station anchor.")
	var draft: Dictionary = ready.metadata
	var allocation := _allocate(_city,_topology,draft)
	if not allocation.ok: return _result(false,allocation.error)
	var anchors: Array[Vector2i] = []
	anchors.assign(allocation.changed_anchors)
	for anchor: Vector2i in changed_manual:
		if not anchors.has(anchor): anchors.append(anchor)
	return _commit(draft,0,anchors)

func _diff(before: Dictionary, after: Dictionary, anchors: Array) -> Dictionary:
	var affected := _affected()
	var ids: Dictionary = {}
	var links: Dictionary = {}
	var stations: Dictionary = {}
	for id: int in before.streets:
		if before.streets[id]!=after.streets.get(id): ids[id] = true
	for id: int in after.streets:
		if after.streets[id]!=before.streets.get(id): ids[id] = true
	for key: String in before.links:
		var old: int = before.links[key]
		var current: int = after.links.get(key,0)
		if old!=current or ids.has(old):
			links[key] = true
			ids[old] = true
			if current>0: ids[current] = true
	for key: String in after.links:
		var current: int = after.links[key]
		if current!=int(before.links.get(key,0)) or ids.has(current): links[key] = true; ids[current] = true
	for anchor: Vector2i in before.station_auto:
		if before.station_auto[anchor]!=after.station_auto.get(anchor): stations[anchor] = true
	for anchor: Vector2i in after.station_auto:
		if after.station_auto[anchor]!=before.station_auto.get(anchor): stations[anchor] = true
	for anchor: Vector2i in anchors: stations[anchor] = true
	affected.links = links.keys()
	affected.links.sort()
	affected.street_ids = ids.keys()
	affected.street_ids.sort()
	affected.station_anchors = stations.keys()
	affected.station_anchors.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y<b.y or (a.y==b.y and a.x<b.x))
	return affected

func _commit(draft: Dictionary, street_id: int, station_anchors: Array) -> Dictionary:
	var affected := _diff(_city.street_naming,draft,station_anchors)
	var did_change := _city.street_naming!=draft or not station_anchors.is_empty()
	if did_change:
		_city.street_naming = draft.duplicate(true)
		revision += 1
		# Subscribers cannot mutate committed metadata or the returned result.
		_publishing = true
		changed.emit(revision,affected.duplicate(true))
		_publishing = false
	return _result(true,"",did_change,street_id,affected)
