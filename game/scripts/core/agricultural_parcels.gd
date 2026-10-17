# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Authoritative exact-member parcel records. Bounds and owners are derived.
class_name AgriculturalParcels
extends RefCounted

signal changed(change: Dictionary)

const Params := preload("res://scripts/sim/data/agricultural_parcel_params.gd")
const MAX_ID := 2147483647
const CELL_COUNT := City.WIDTH * City.HEIGHT
const INTEGER_FIELDS := ["id","identity_index","origin_index","phase","legacy_code",
	"layout_seed","target_area","height","failed_months","last_month","revision"]
const RECORD_FIELDS := ["id","members","identity_index","origin_index","phase",
	"archetype","state","mode","legacy_code","layout_seed","target_area","height",
	"modules","stock_units","failed_months","last_month","revision"]
var revision: int = 0
var _next_id: int = 1
var _records: Dictionary = {}
var _owners := PackedInt32Array()
# Exact detached proofs only; the static validate() never consults this cache.
# A cut reuses them only for its untouched records' pure layout replay.
var _layout_proofs: Dictionary = {}
var _layout_validations := 0
# Exact successful record proofs for the current occupancy/land snapshot. Packed
# arrays and the mutable flood map are explicitly detached.
var _record_proofs: Dictionary = {}
var _proof_layers: Array = []
var _data_validations := 0
var _canonical_proof: Dictionary = {}
var _canonical_proven := false


func _init() -> void:
	_owners.resize(CELL_COUNT)
	_owners.fill(0)


static func cell(p: Vector2i) -> int:
	return p.y * City.WIDTH + p.x


static func tile(i: int) -> Vector2i:
	return Vector2i(i % City.WIDTH, i / City.WIDTH)


## Owner parcel id per tile index (id_at for every in-bounds tile).
func owners() -> PackedInt32Array:
	return _owners


func id_at(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= City.WIDTH or p.y >= City.HEIGHT: return 0
	return _owners[cell(p)]


## Non-reserving allocation probe. The validating put remains the allocator.
func available_id() -> int:
	return _next_id if _next_id < MAX_ID else 0


func record(id: int) -> Dictionary:
	return _records.get(id, {}).duplicate(true)


func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := _records.keys()
	ids.sort()
	for id in ids: result.append(record(id))
	return result


func duplicate_store() -> AgriculturalParcels:
	var copy := AgriculturalParcels.new()
	copy._records = _records.duplicate(true)
	copy._owners = _owners.duplicate()
	copy._next_id = _next_id
	copy.revision = revision
	copy._layout_proofs = _layout_proofs.duplicate(true)
	copy._layout_validations = _layout_validations
	copy._record_proofs = _record_proofs.duplicate(true)
	copy._proof_layers = _proof_layers.duplicate(true)
	copy._data_validations = _data_validations
	copy._canonical_proof = bytes_to_var(var_to_bytes(_canonical_proof))
	copy._canonical_proven = _canonical_proven
	return copy


static func bounds(members: PackedInt32Array) -> Rect2i:
	if members.is_empty(): return Rect2i()
	var lo := tile(members[0])
	var hi := lo
	for i in members:
		var p := tile(i)
		lo = Vector2i(mini(lo.x,p.x),mini(lo.y,p.y))
		hi = Vector2i(maxi(hi.x,p.x),maxi(hi.y,p.y))
	return Rect2i(lo,hi-lo+Vector2i.ONE)


## Iterative cardinal flood fill. Coordinate checks precede index arithmetic.
static func components(members: PackedInt32Array) -> Array[PackedInt32Array]:
	var remaining := {}
	for i in members:
		if i >= 0 and i < CELL_COUNT: remaining[i] = true
	var ordered := remaining.keys()
	ordered.sort()
	var result: Array[PackedInt32Array] = []
	for first in ordered:
		if not remaining.has(first): continue
		var queue := PackedInt32Array([first])
		remaining.erase(first)
		var cursor := 0
		while cursor < queue.size():
			var p := tile(queue[cursor])
			cursor += 1
			for step in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var q: Vector2i = p+step
				if q.x < 0 or q.y < 0 or q.x >= City.WIDTH or q.y >= City.HEIGHT: continue
				var index := cell(q)
				if remaining.has(index):
					remaining.erase(index)
					queue.append(index)
		queue.sort()
		result.append(queue)
	return result


static func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}


static func _code(r: Dictionary) -> int:
	return r.legacy_code if r.mode == &"legacy" else Params.cell_id(r.archetype,r.state)


static func _record_data_error(city: City, r: Dictionary) -> String:
	if r.size() != RECORD_FIELDS.size(): return "Invalid record fields."
	for key in r:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or key not in RECORD_FIELDS: return "Invalid record field."
	for key in INTEGER_FIELDS:
		if not r.has(key) or typeof(r[key]) != TYPE_INT: return "Invalid integer: " + key
	if r.id < 1 or r.id > MAX_ID: return "Invalid parcel ID."
	if typeof(r.get("members")) != TYPE_PACKED_INT32_ARRAY: return "Invalid members."
	var members: PackedInt32Array = r.members
	if members.is_empty() or members.size() > Params.MAX_AREA: return "Invalid parcel area."
	if r.identity_index not in members: return "Identity is not a member."
	if r.origin_index < 0 or r.origin_index >= CELL_COUNT: return "Invalid origin."
	if r.phase < 0 or r.phase > 1: return "Invalid phase."
	if r.target_area < 1 or r.target_area > Params.MAX_AREA: return "Invalid target area."
	if r.height < 0 or r.height > City.ALT_MASK: return "Invalid height."
	if r.failed_months < 0 or r.failed_months > MAX_ID or r.last_month < -1 or r.last_month > MAX_ID: return "Invalid lifecycle."
	if r.revision < 1 or r.revision > MAX_ID: return "Invalid revision."
	for key in ["archetype","state","mode"]:
		if typeof(r.get(key)) not in [TYPE_STRING,TYPE_STRING_NAME] or String(r[key]).length() > 64: return "Invalid name: " + key
	if not Params.ACTIVE_CODES.has(StringName(r.archetype)): return "Invalid archetype."
	if r.state not in [&"active",&"prepared",&"dormant"]: return "Invalid state."
	if r.mode not in [&"legacy",&"square",&"generated"]: return "Invalid mode."
	if r.mode == &"generated" and r.legacy_code != 0: return "Generated parcel has a legacy code."
	if r.mode != &"generated":
		var active_id := AgricultureParams.building_id(r.archetype)
		var side := Buildings.size(active_id).x
		var expected := active_id if r.state == &"active" or r.mode == &"square" else AgricultureParams.state_id(r.state,side)
		if r.legacy_code != expected: return "Mismatched template code."
		var box := bounds(members)
		if box.size != Vector2i(side,side) or members.size() != side*side: return "Incomplete template footprint."
	var seen := {}
	for i in members:
		if i < 0 or i >= CELL_COUNT or seen.has(i): return "Duplicate or invalid member."
		seen[i] = true
		var p := tile(i)
		if p.x < AgricultureParams.EDGE_MARGIN or p.y < AgricultureParams.EDGE_MARGIN or p.x >= City.WIDTH-AgricultureParams.EDGE_MARGIN or p.y >= City.HEIGHT-AgricultureParams.EDGE_MARGIN: return "Member too close to city edge."
		if city.zone_kind_at(p.x,p.y) != Zones.AGR_LOW: return "Invalid parcel density."
		if city.is_water(p.x,p.y) or not city.is_flat(p.x,p.y) or city.ground_height(p.x,p.y) != r.height: return "Parcel ground is not dry and level."
		var existing := city.building_at(p.x,p.y)
		# Protection freezes an already occupied old farm; it must not erase its
		# ownership or make its save unloadable. New parcel placement stays barred.
		if city.flags.has_bits(p.x,p.y,TileFlags.LANDMARK) and not (r.mode == &"legacy" and existing == _code(r)):
			return "Protected parcel land."
		var owner := city.agricultural_parcels.id_at(p)
		if owner != 0 and owner != r.id: return "Overlapping parcel owner."
		if existing != Buildings.NONE and existing != _code(r):
			if owner != r.id or existing != _code(city.agricultural_parcels.record(owner)): return "Occupied parcel land."
	var rect := bounds(members)
	if rect.size.x > Params.MAX_SPAN or rect.size.y > Params.MAX_SPAN: return "Parcel span too large."
	if components(members).size() != 1: return "Disconnected members."
	if typeof(r.get("stock_units")) != TYPE_DICTIONARY: return "Invalid stock tokens."
	var stock: Dictionary = r.stock_units
	var rate := Params.stock_rate(r.archetype)
	if rate > 0 and stock.size() != members.size(): return "Missing stock entitlement."
	var total := 0
	for i in stock:
		if typeof(i) != TYPE_INT or not seen.has(i): return "Stock token is outside members."
		if typeof(stock[i]) != TYPE_INT or stock[i] < 0 or stock[i] > rate: return "Invalid stock quantity."
		total += stock[i]
	if total > Params.MAX_STOCK_UNITS: return "Stock entitlement exceeds cap."
	if r.mode == &"legacy" and total != int(AgricultureParams.ROSTER[StringName(r.archetype)][4]) * Params.STOCK_DENOMINATOR:
		return "Legacy stock entitlement must remain canonical."
	if typeof(r.get("modules")) != TYPE_ARRAY or r.modules.size() > Params.MAX_AREA: return "Invalid modules."
	for m in r.modules:
		if typeof(m) != TYPE_DICTIONARY or m.size() != 3: return "Invalid module."
		if typeof(m.get("key")) not in [TYPE_STRING,TYPE_STRING_NAME]: return "Invalid module key."
		if typeof(m.get("at")) != TYPE_VECTOR3 or not m.at.is_finite(): return "Invalid module position."
		var position: Vector3 = m.at
		if maxf(absf(position.x),maxf(absf(position.y),absf(position.z))) > City.WIDTH*16: return "Module position out of bounds."
		if typeof(m.get("yaw")) != TYPE_INT or m.yaw < 0 or m.yaw > 3: return "Invalid module yaw."
	return ""


## A raw layer write invalidates all proofs before any update can use them.
## Owners and the store identity also participate because validation consults
## the city's authoritative ownership map, not just the visible building code.
func _refresh_record_proofs(city: City) -> bool:
	if city.agricultural_parcels != self or _proof_layers.size() != 7 or \
		_proof_layers[0] != city.building.data or _proof_layers[1] != city.zone.data or \
		_proof_layers[2] != city.terrain.data or _proof_layers[3] != city.altitude.data or \
		_proof_layers[4] != city.flags.data or _proof_layers[5] != _owners or \
		_proof_layers[6] != city.flood_overlay:
		_record_proofs.clear()
		_canonical_proof.clear()
		_canonical_proven = false
		return false
	return true


func _remember_proof_layers(city: City) -> void:
	_proof_layers = [city.building.data.duplicate(),city.zone.data.duplicate(),city.terrain.data.duplicate(),
		city.altitude.data.duplicate(),city.flags.data.duplicate(),_owners.duplicate(),city.flood_overlay.duplicate(true)]


## Call only after bounded structural/land/type validation. Keep every canonical
## field except the three counters which geometry never reads. Exact equality,
## not a hash, guards membership, poses, stock, state and all transform inputs.
func _cached_record_error(city: City, r: Dictionary, retained: bool = false) -> String:
	# Only canonical retained records or the already checked update may use a
	# byte proof. Untrusted input still reaches bounded schema checks first.
	if retained and _record_proofs.get(r.get("id",0),PackedByteArray()) == var_to_bytes(r): return ""
	_data_validations += 1
	var error := _record_data_error(city,r)
	if not error.is_empty(): return error
	var signature := r.duplicate(true)
	for field in ["failed_months","last_month","revision"]: signature.erase(field)
	if _layout_proofs.get(r.id,{}) == signature:
		if _records.has(r.id): _record_proofs[r.id] = var_to_bytes(r)
		return ""
	_layout_validations += 1
	error = AgriculturalParcelGeometry.record_error(r)
	if error.is_empty():
		_layout_proofs[r.id] = signature
		if _records.has(r.id): _record_proofs[r.id] = var_to_bytes(r)
	return error


## Existing layer bytes are checked even for counter-only replacements. A raw
## edit cannot be silently healed by replaying a previously validated record.
func _validate_update(city: City, values: Array[Dictionary]) -> bool:
	var expected_owners := PackedInt32Array()
	expected_owners.resize(CELL_COUNT)
	expected_owners.fill(0)
	for key in _records:
		var old: Dictionary = _records[key]
		if typeof(key) != TYPE_INT or key != old.get("id",0): return false
		for i in old.members:
			if city.building.data[i] != _code(old): return false
			expected_owners[i] = old.id
	# This also rejects orphan ownership outside every retained footprint.
	if _owners != expected_owners: return false
	var ids := {}
	var members := {}
	for r in values:
		if not _cached_record_error(city,r,true).is_empty() or ids.has(r.id): return false
		ids[r.id] = true
		for i in r.members:
			if members.has(i): return false
			members[i] = true
	return members.size() <= CELL_COUNT


static func validate(city: City, values: Array[Dictionary]) -> Dictionary:
	return _validate_values(city,values,null)


## The complete static checks in validate()'s order. With a store, a record whose
## exact layout signature that store already proved skips only the pure metre-space
## replay; its land, ownership, occupancy, schema and overlap checks still run.
static func _validate_values(city: City, values: Array[Dictionary], proofs: AgriculturalParcels) -> Dictionary:
	if values.size() > CELL_COUNT: return _error("Too many parcels.")
	var ids := {}
	var members := {}
	for r in values:
		var error := _record_data_error(city,r)
		if error.is_empty() and (proofs == null or not proofs._has_layout_proof(r)):
			error = AgriculturalParcelGeometry.record_error(r)
		if not error.is_empty(): return _error(error)
		if ids.has(r.id): return _error("Duplicate parcel ID.")
		ids[r.id] = true
		for i in r.members:
			if members.has(i): return _error("Overlapping parcel members.")
			members[i] = true
		if members.size() > CELL_COUNT: return _error("Too many members.")
	return {"ok":true,"error":""}


## Call only after _record_data_error accepted r. Geometry never reads the
## counters, and the proof is recorded only after record_error accepted it.
func _has_layout_proof(r: Dictionary) -> bool:
	var proof: Dictionary = _layout_proofs.get(r.id,{})
	if proof.is_empty(): return false
	var signature := r.duplicate(true)
	for field in ["failed_months","last_month","revision"]: signature.erase(field)
	return proof == signature


## A normal update may add land and change lifecycle state, but cannot remove
## cells, change identity, or refill retained stock. Cuts use a topology transaction.
func put(city: City, value: Dictionary) -> Error:
	return _put(city,value,false)


## put() for a known lifecycle transition. When only the state, its template code
## and counters change, the result equals put()'s whole-store transaction while
## revalidating just this record; any other change takes that transaction.
func put_lifecycle(city: City, value: Dictionary) -> Error:
	return _put(city,value,true)


func _put(city: City, value: Dictionary, lifecycle: bool) -> Error:
	if revision >= MAX_ID: return ERR_OUT_OF_MEMORY
	var unchanged_land := _refresh_record_proofs(city)
	var error := _cached_record_error(city,value)
	if not error.is_empty(): return ERR_INVALID_DATA
	var r := value.duplicate(true)
	r.members.sort()
	r.archetype = StringName(r.archetype)
	r.state = StringName(r.state)
	r.mode = StringName(r.mode)
	for module in r.modules: module.key = StringName(module.key)
	var id: int = r.id
	var old: Dictionary = _records.get(id,{})
	# Input has passed the original bounded schema and land validation. Exact
	# equality also guards every retained record, including numeric type changes.
	if not old.is_empty() and unchanged_land and _canonical_matches():
		var signature := r.duplicate()
		for field in ["failed_months","last_month","revision"]: signature[field] = old[field]
		if signature == old:
			if old.revision == MAX_ID: return ERR_OUT_OF_MEMORY
			r.revision = old.revision+1
			_publish_counter_update(r,old)
			return OK
		# A lifecycle state change keeps every member, module, token and identity.
		# It rewrites only this parcel's own codes, which no other record's land
		# checks read, so the retained records stay proven by the unchanged layers.
		for field in ["state","legacy_code"]: signature[field] = old[field]
		if lifecycle and signature == old:
			if old.revision == MAX_ID: return ERR_OUT_OF_MEMORY
			r.revision = old.revision+1
			# The same canonical-record recheck the whole-store transaction applies.
			if not _cached_record_error(city,r,true).is_empty(): return ERR_INVALID_DATA
			_publish_state_update(city,r,old)
			return OK
	if old.is_empty():
		if id < _next_id or id >= MAX_ID: return ERR_OUT_OF_MEMORY
	else:
		for key in ["identity_index","origin_index","phase","layout_seed","archetype"]:
			if r[key] != old[key]: return ERR_INVALID_DATA
		for i in old.members:
			if i not in r.members: return ERR_INVALID_DATA
			if r.stock_units.get(i,0) > old.stock_units.get(i,0): return ERR_INVALID_DATA
		if old.revision == MAX_ID: return ERR_OUT_OF_MEMORY
		r.revision = old.revision + 1
	# records() assumes canonical integer keys when looking up each record.
	for key in _records:
		if typeof(key) != TYPE_INT or key != _records[key].get("id",0): return ERR_INVALID_DATA
	var candidates := records()
	for i in range(candidates.size()-1,-1,-1):
		if candidates[i].id == id: candidates.remove_at(i)
	candidates.append(r)
	if not _validate_update(city,candidates): return ERR_INVALID_DATA
	var neighbors := {}
	for i in r.members:
		var p := tile(i)
		for step in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var neighbor := id_at(p+step)
			if neighbor != 0 and neighbor != id: neighbors[neighbor] = true
	var old_bounds := bounds(old.get("members",PackedInt32Array()))
	_records[id] = r
	_next_id = maxi(_next_id,id+1)
	for i in r.members:
		_owners[i] = id
		var p := tile(i)
		city.building.put(p.x,p.y,_code(r))
		# Legacy corner bytes distinguish adjacent rectangular lots.
		if r.mode != &"legacy": city.zone.put(p.x,p.y,Zones.AGR_LOW)
	revision += 1
	# The transaction just proved every retained record and only changed this
	# parcel's legal occupancy. Refresh after those writes, retaining the proofs.
	_record_proofs[id] = var_to_bytes(r)
	_remember_proof_layers(city)
	_capture_canonical_proof()
	var neighbor_ids := neighbors.keys()
	neighbor_ids.sort()
	changed.emit({"revision":revision,"ids":[id],"old_bounds":old_bounds,
		"new_bounds":bounds(r.members),"neighbor_ids":neighbor_ids})
	return OK


## Only a globally validated store may establish this proof. Variant encoding
## detaches nested packed members as well as ordinary dictionaries and arrays.
func _capture_canonical_proof() -> void:
	_canonical_proof = bytes_to_var(var_to_bytes(_records))
	_canonical_proven = true


## Native equality is type-strict for the validated numeric/member domain.
## Dictionary field-key aliases and ordering are legal under the same schema.
func _canonical_matches() -> bool:
	return _canonical_proven and _canonical_proof == _records


## Counter-only changes keep all proven occupancy bytes and geometry intact.
## Publish the same revision and neighbor notification as an ordinary put.
func _publish_counter_update(r: Dictionary, old: Dictionary) -> void:
	var neighbors := {}
	for i in r.members:
		var p := tile(i)
		for step in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var neighbor := id_at(p+step)
			if neighbor != 0 and neighbor != r.id: neighbors[neighbor] = true
	_records[r.id] = r
	_next_id = maxi(_next_id,r.id+1)
	revision += 1
	_record_proofs[r.id] = var_to_bytes(r)
	_canonical_proof[r.id] = bytes_to_var(var_to_bytes(r))
	var neighbor_ids := neighbors.keys()
	neighbor_ids.sort()
	changed.emit({"revision":revision,"ids":[r.id],"old_bounds":bounds(old.members),
		"new_bounds":bounds(r.members),"neighbor_ids":neighbor_ids})


## Commit a state-only replacement exactly as put's transaction would: the same
## occupancy writes, counters, proofs and notification. Only this record's
## canonical proof entry changes, so it is re-encoded alone.
func _publish_state_update(city: City, r: Dictionary, old: Dictionary) -> void:
	var id: int = r.id
	var neighbors := {}
	for i in r.members:
		var p := tile(i)
		for step in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var neighbor := id_at(p+step)
			if neighbor != 0 and neighbor != id: neighbors[neighbor] = true
	var old_bounds := bounds(old.members)
	_records[id] = r
	_next_id = maxi(_next_id,id+1)
	for i in r.members:
		_owners[i] = id
		var p := tile(i)
		city.building.put(p.x,p.y,_code(r))
		if r.mode != &"legacy": city.zone.put(p.x,p.y,Zones.AGR_LOW)
	revision += 1
	_record_proofs[id] = var_to_bytes(r)
	_remember_proof_layers(city)
	_canonical_proof[id] = bytes_to_var(var_to_bytes(r))
	var neighbor_ids := neighbors.keys()
	neighbor_ids.sort()
	changed.emit({"revision":revision,"ids":[id],"old_bounds":old_bounds,
		"new_bounds":bounds(r.members),"neighbor_ids":neighbor_ids})


## Managed destruction proves ID/revision/ownership feasibility before source
## writes, RNG draws or events. Reuse the exact transaction; reserve nothing.
func preflight_removal(city: City, cells: PackedInt32Array) -> Dictionary:
	var owned := false
	for i in cells:
		if i >= 0 and i < CELL_COUNT and _owners[i] != 0: owned = true;break
	if not owned: return {"ok":true,"error":""}
	var detached := city.duplicate_city()
	return detached.agricultural_parcels.remove_cells(detached,cells)


## The optional adapter sees only a detached candidate and returns IDs whose
## existing core and post-edit services may stay active. Never retained here.
func remove_cells(city: City, cells: PackedInt32Array, service_validator: Callable = Callable()) -> Dictionary:
	return _cut(city,cells,true,service_validator)


## Reconcile only changed owners, comparing all their cells with current layers.
## An empty selection deliberately means a mutation-hook audit of all records.
func repair_changed_cells(city: City, cells: PackedInt32Array, service_validator: Callable = Callable()) -> Dictionary:
	return _cut(city,cells,false,service_validator)


static func change_bounds(change: Dictionary, store: AgriculturalParcels) -> Rect2i:
	var box: Rect2i = change.get("old_bounds",Rect2i())
	var next: Rect2i = change.get("new_bounds",Rect2i())
	if next.has_area(): box = box.merge(next) if box.has_area() else next
	for id: int in change.get("neighbor_ids",[]):
		var r := store.record(id)
		if r.is_empty(): continue
		next = bounds(r.members)
		box = box.merge(next) if box.has_area() else next
	return box


func _member_intact(city: City, r: Dictionary, i: int) -> bool:
	var p := tile(i)
	return city.building.data[i] == _code(r) and city.zone_kind_at(p.x,p.y) == Zones.AGR_LOW \
		and city.is_flat(p.x,p.y) and not city.is_water(p.x,p.y) and city.ground_height(p.x,p.y) == r.height


func _cut(city: City, cells: PackedInt32Array, explicit: bool, service_validator: Callable) -> Dictionary:
	var change := {"revision":revision,"ids":[],"old_bounds":Rect2i(),"new_bounds":Rect2i(),
		"neighbor_ids":[],"removed_cells":PackedInt32Array(),"ok":true,"error":""}
	var selected := {}
	var affected := {}
	for i in cells:
		if i < 0 or i >= CELL_COUNT: continue
		selected[i] = true
		if _owners[i] != 0: affected[_owners[i]] = true
	if not explicit and cells.is_empty():
		for id in _records: affected[id] = true
	var cuts := {}
	var ids := affected.keys()
	ids.sort()
	for id: int in ids:
		var old: Dictionary = _records[id]
		var removed := PackedInt32Array()
		for i in old.members:
			if (explicit and selected.has(i)) or not _member_intact(city,old,i): removed.append(i)
		if removed.is_empty(): continue
		# Old rectangular farms keep whole-footprint demolition semantics.
		if old.mode == &"legacy": removed = old.members.duplicate()
		cuts[id] = removed
	if cuts.is_empty(): return change
	if revision >= MAX_ID: return _error("Parcel revision exhausted.")
	var detached := city.duplicate_city()
	var staged := detached.agricultural_parcels
	var fragments: Array[Dictionary] = []
	var neighbors := {}
	for id: int in ids:
		if not cuts.has(id): continue
		var old: Dictionary = _records[id]
		if old.revision >= MAX_ID: return _error("Parcel revision exhausted.")
		change.ids.append(id)
		var box := bounds(old.members)
		change.old_bounds = change.old_bounds.merge(box) if change.old_bounds.has_area() else box
		var retained := PackedInt32Array()
		for i in old.members:
			staged._owners[i] = 0
			for step in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var neighbor := id_at(tile(i)+step)
				if neighbor != 0 and neighbor != id: neighbors[neighbor] = true
			if i not in cuts[id]: retained.append(i)
			else:
				change.removed_cells.append(i)
				# Post-write reconciliation never erases a replacement network/rubble.
				if detached.building.data[i] == _code(old):
					detached.building.data[i] = Buildings.NONE
					var kind := detached.zone_kind_at(i%128,i/128)
					detached.zone.data[i] = Zones.make(kind,Zones.ALL_CORNERS if kind != Zones.NONE else 0)
					detached.flags.data[i] &= ~(TileFlags.CONDUCTS_POWER | TileFlags.POWERED | TileFlags.WATERED)
					detached.flags.set_bits(i%128,i/128,TileFlags.CONDUCTS_WATER,NetworkShapes.underground_in_family(detached.underground.data[i],NetworkShapes.Family.PIPE))
		staged._records.erase(id)
		staged._layout_proofs.erase(id)
		var parts := components(retained)
		var keeper := -1
		for index in parts.size():
			if old.identity_index in parts[index]: keeper=index;break
		if keeper < 0:
			for index in parts.size():
				if keeper < 0 or parts[index].size() > parts[keeper].size(): keeper=index
		for index in parts.size():
			var r := old.duplicate(true)
			r.id = id if index == keeper else 0
			r.members = parts[index]
			r.identity_index = old.identity_index if old.identity_index in r.members else r.members[0]
			r.mode = &"generated"
			r.legacy_code = 0
			r.revision = old.revision+1
			r.stock_units = {}
			for i in r.members:
				if old.stock_units.has(i): r.stock_units[i] = old.stock_units[i]
			var layout := AgriculturalParcelGeometry.repair_layout(r,old.modules)
			r.modules = layout.modules
			var eligible: bool = old.mode == &"generated" and old.state == &"active" and layout.ok and layout.core_intact
			if old.state == &"active" and not eligible: r.state = &"prepared"
			fragments.append({"record":r,"eligible":eligible})
	# Allocate every new component in global row-major order, independent of IDs.
	fragments.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.record.members[0] < b.record.members[0])
	var eligible_ids: Array[int] = []
	for fragment in fragments:
		var r: Dictionary = fragment.record
		if r.id == 0:
			if staged._next_id >= MAX_ID: return _error("Parcel IDs exhausted.")
			r.id = staged._next_id
			staged._next_id += 1
			change.ids.append(r.id)
		if fragment.eligible: eligible_ids.append(r.id)
		staged._records[r.id] = r
		for i in r.members:
			staged._owners[i] = r.id
			detached.building.data[i] = _code(r)
		var box := bounds(r.members)
		change.new_bounds = change.new_bounds.merge(box) if change.new_bounds.has_area() else box
	var keep: Array = []
	if service_validator.is_valid() and not eligible_ids.is_empty():
		var service_city := detached.duplicate_city()
		service_city.imported_power_links = city.imported_power_links.duplicate()
		keep = service_validator.call(service_city,eligible_ids.duplicate())
	for id: int in eligible_ids:
		if id not in keep: staged._records[id].state = &"prepared"
	for fragment in fragments:
		var r: Dictionary = staged._records[fragment.record.id]
		staged._layout_proofs.erase(r.id)
		for i in r.members: detached.building.data[i] = _code(r)
	# Complete land validation of every record. Untouched records reuse their exact
	# detached layout proofs (cut owners' proofs were erased above), so an edit
	# replays only the changed parcels' layouts. No partial commit on error.
	var valid := _validate_values(detached,staged.records(),staged)
	if not valid.ok: return valid
	if not coverage(detached,staged): return _error("Parcel coverage failed after edit.")
	_records = staged._records
	_owners = staged._owners
	_next_id = staged._next_id
	_layout_proofs = staged._layout_proofs
	_record_proofs.clear()
	_proof_layers.clear()
	_canonical_proof.clear()
	_canonical_proven = false
	city.building.data = detached.building.data
	city.zone.data = detached.zone.data
	city.flags.data = detached.flags.data
	for i in change.removed_cells: city.imported_power_links.erase(i)
	revision += 1
	change.revision = revision
	change.ids.sort()
	change.removed_cells.sort()
	change.neighbor_ids = neighbors.keys()
	change.neighbor_ids.sort()
	changed.emit(change.duplicate(true))
	return change


## JSON-safe snapshot. Runtime vectors, names and signed64 seeds have explicit
## representations; owners and bounds remain derived rather than persisted.
func to_dict() -> Dictionary:
	var values: Array[Dictionary] = []
	for r in records():
		r.members = Array(r.members)
		r.layout_seed = str(r.layout_seed)
		for key in ["archetype","state","mode"]: r[key] = String(r[key])
		var stock := {}
		for i in r.stock_units: stock[str(i)] = r.stock_units[i]
		r.stock_units = stock
		for m in r.modules:
			m.key = String(m.key)
			var p: Vector3 = m.at
			m.at = [p.x,p.y,p.z]
		values.append(r)
	return {"schema":1,"next_id":_next_id,"revision":revision,"records":values}


## JSON numbers are accepted only while exactly integral in a bounded domain.
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value == floorf(float(value)) and value >= minimum and value <= maximum


## Compare decimal magnitudes before conversion: int() alone saturates overflow.
static func _seed(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 20: return _error("Invalid seed.")
	var negative: bool = value.begins_with("-")
	var digits: String = value.substr(1) if negative else value
	if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")) or (negative and digits == "0"): return _error("Invalid decimal.")
	for c in digits:
		if c < "0" or c > "9": return _error("Invalid decimal.")
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit): return _error("Seed overflow.")
	return {"ok":true,"value":int(value)}


## Exact coverage is a save boundary invariant in both directions. Legacy
## ordinary squares may await migration, but flexible codes never may.
static func coverage(city: City, store: AgriculturalParcels) -> bool:
	for r in store.records():
		for i in r.members:
			if city.building.data[i] != _code(r): return false
	for i in CELL_COUNT:
		var code := city.building.data[i]
		if code >= Params.ACTIVE_CODES[&"vegetables"] and code <= Params.DORMANT:
			var id: int = store._owners[i]
			if id == 0 or _code(store._records[id]) != code: return false
	return true


static func decode(data: Variant, city: City) -> Dictionary:
	var store := AgriculturalParcels.new()
	if data == null:
		return {"ok":true,"store":store,"error":""} if coverage(city,store) else _error("Missing parcel ownership.")
	if typeof(data) != TYPE_DICTIONARY or data.size() != 4: return _error("Invalid parcel store.")
	for key in ["schema","next_id","revision","records"]:
		if not data.has(key): return _error("Missing store field.")
	if not _integer(data.schema,1,1) or not _integer(data.next_id,1,MAX_ID) or not _integer(data.revision,0,MAX_ID): return _error("Invalid store counters.")
	if typeof(data.records) != TYPE_ARRAY or data.records.size() > CELL_COUNT: return _error("Invalid record count.")
	var values: Array[Dictionary] = []
	for raw in data.records:
		if typeof(raw) != TYPE_DICTIONARY or raw.size() != RECORD_FIELDS.size(): return _error("Invalid record.")
		for key in RECORD_FIELDS:
			if not raw.has(key): return _error("Missing record field.")
		var r: Dictionary = raw.duplicate()
		for key in INTEGER_FIELDS:
			if key == "layout_seed": continue
			if not _integer(r[key],-1,MAX_ID): return _error("Invalid integer: " + key)
			r[key] = int(r[key])
		var seed := _seed(r.layout_seed)
		if not seed.ok: return seed
		r.layout_seed = seed.value
		if typeof(r.members) != TYPE_ARRAY or r.members.is_empty() or r.members.size() > Params.MAX_AREA: return _error("Invalid member array.")
		for i in r.members:
			if not _integer(i,0,CELL_COUNT-1): return _error("Invalid member index.")
		r.members = PackedInt32Array(r.members)
		if typeof(r.stock_units) != TYPE_DICTIONARY or r.stock_units.size() > Params.MAX_AREA: return _error("Invalid stock map.")
		var stock := {}
		for key in r.stock_units:
			if typeof(key) != TYPE_STRING or key.length() > 5: return _error("Invalid stock key.")
			var parsed := _seed(key)
			if not parsed.ok or parsed.value < 0 or parsed.value >= CELL_COUNT: return _error("Invalid stock key.")
			if not _integer(r.stock_units[key],0,Params.MAX_STOCK_UNITS): return _error("Invalid stock value.")
			stock[parsed.value] = int(r.stock_units[key])
		r.stock_units = stock
		if typeof(r.modules) != TYPE_ARRAY or r.modules.size() > Params.MAX_AREA: return _error("Invalid modules.")
		var modules: Array = []
		for m in r.modules:
			if typeof(m) != TYPE_DICTIONARY or m.size() != 3 or not m.has("key") or not m.has("at") or not m.has("yaw"): return _error("Invalid module.")
			if typeof(m.at) != TYPE_ARRAY or m.at.size() != 3 or not _integer(m.yaw,0,3): return _error("Invalid module transform.")
			for v in m.at:
				if typeof(v) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(v)) or absf(float(v)) > City.WIDTH*16: return _error("Invalid module position.")
			modules.append({"key":m.key,"at":Vector3(m.at[0],m.at[1],m.at[2]),"yaw":int(m.yaw)})
		r.modules = modules
		values.append(r)
	var valid := validate(city,values)
	if not valid.ok: return valid
	for r in values:
		if r.id >= data.next_id: return _error("Invalid next parcel ID.")
		r.members.sort()
		for key in ["archetype","state","mode"]: r[key] = StringName(r[key])
		for m in r.modules: m.key = StringName(m.key)
		store._records[r.id] = r
		for i in r.members: store._owners[i] = r.id
	store._next_id = int(data.next_id)
	store.revision = int(data.revision)
	if not coverage(city,store): return _error("Parcel membership and occupancy disagree.")
	return {"ok":true,"store":store,"error":""}


## Adopt fully recovered legacy lots without writes, random draws or replacing
## already canonical records. Validate the complete candidate transaction first.
func adopt_legacy(city: City, lots: Array[Dictionary]) -> Error:
	var candidates := records()
	var next := _next_id
	var added: Array[Dictionary] = []
	for lot in lots:
		if lot.zone_kind != Zones.AGR_LOW or id_at(lot.anchor) != 0: continue
		var members := PackedInt32Array()
		for y in range(lot.rect.position.y,lot.rect.end.y):
			for x in range(lot.rect.position.x,lot.rect.end.x): members.append(cell(Vector2i(x,y)))
		if next >= MAX_ID: return ERR_OUT_OF_MEMORY
		var identity := cell(lot.anchor)
		var r := {"id":next,"members":members,"identity_index":identity,"origin_index":identity,
			"phase":0 if lot.anchor.x < City.HALF else 1,"archetype":lot.archetype,"state":lot.state,
			"mode":&"legacy","legacy_code":lot.building_id,"layout_seed":(identity+1)*65537+AgricultureParams.building_id(lot.archetype),
			"target_area":members.size(),"height":city.ground_height(lot.anchor.x,lot.anchor.y),"modules":[],
			"stock_units":Params.stock_units(lot.archetype,members),"failed_months":lot.failed_months,
			"last_month":lot.last_month,"revision":1}
		candidates.append(r)
		added.append(r)
		next += 1
	if added.is_empty(): return OK
	if revision >= MAX_ID: return ERR_OUT_OF_MEMORY
	if not validate(city,candidates).ok: return ERR_INVALID_DATA
	for r in added:
		_records[r.id] = r
		for i in r.members: _owners[i] = r.id
	_next_id = next
	revision += 1
	_record_proofs.clear()
	_proof_layers.clear()
	_canonical_proof.clear()
	_canonical_proven = false
	var ids: Array = []
	var box := Rect2i()
	for r in added:
		ids.append(r.id)
		var b := bounds(r.members)
		box = box.merge(b) if box.has_area() else b
	changed.emit({"revision":revision,"ids":ids,"old_bounds":Rect2i(),"new_bounds":box,"neighbor_ids":[]})
	return OK


## Ordinary legacy demolition predates parcel-aware topology. Forget a damaged
## whole legacy square without touching the replacement layers or other records.
func discard_invalid_legacy(city: City) -> Error:
	var removed: Array[int] = []
	var box := Rect2i()
	for r in records():
		if r.mode != &"legacy": continue
		var intact := true
		for i in r.members:
			var p := tile(i)
			if city.building.data[i] != r.legacy_code or city.zone_kind_at(p.x,p.y) != Zones.AGR_LOW: intact = false
		if intact: continue
		if revision >= MAX_ID: return ERR_OUT_OF_MEMORY
		removed.append(r.id)
		var b := bounds(r.members)
		box = box.merge(b) if box.has_area() else b
		for i in r.members: _owners[i] = 0
		_records.erase(r.id)
		_layout_proofs.erase(r.id)
	if not removed.is_empty():
		revision += 1
		changed.emit({"revision":revision,"ids":removed,"old_bounds":box,"new_bounds":Rect2i(),"neighbor_ids":[]})
	_record_proofs.clear()
	_proof_layers.clear()
	_canonical_proof.clear()
	_canonical_proven = false
	return OK
