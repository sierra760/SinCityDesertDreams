# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

class CountedStore extends AgriculturalParcels:
	var record_copies := 0
	var canonical_copies := 0
	func _capture_canonical_proof() -> void:
		canonical_copies += 1
		super._capture_canonical_proof()
	func records() -> Array[Dictionary]:
		record_copies += 1
		return super.records()

class FullStore extends CountedStore:
	func _canonical_matches() -> bool:
		return false

func populated(count: int = 2) -> City:
	var city := flat_city()
	city.agricultural_parcels = CountedStore.new()
	for n in count:
		var members := F.square(4,Vector2i(8+(n%10)*5,8+(n/10)*5))
		F.zone(city,members)
		check_eq(city.agricultural_parcels.put(city,F.record(n+1,members)),OK)
	return city

func update(city: City, id: int, month: int) -> Error:
	var value := city.agricultural_parcels.record(id)
	value.last_month = month
	return city.agricultural_parcels.put(city,value)

func snapshot(city: City) -> PackedByteArray:
	return var_to_bytes([city.agricultural_parcels.to_dict(),city.building.data,city.zone.data,
		city.terrain.data,city.altitude.data,city.flags.data,city.flood_overlay,city.agricultural_parcels.get("_owners")])

func test_counter_updates_revalidate_changed_records_with_bounded_work() -> void:
	var city := populated(80)
	var has_counter := false
	for property in city.agricultural_parcels.get_property_list():
		if property.name == "_data_validations": has_counter = true
	check(has_counter,"record validation work is measured independently of machine speed")
	if not has_counter: return
	var initial: int = city.agricultural_parcels.get("_data_validations")
	var before := city.agricultural_parcels.to_dict()
	city.agricultural_parcels.set("record_copies",0)
	city.agricultural_parcels.set("canonical_copies",0)
	for id in range(1,81): check_eq(update(city,id,1),OK)
	check_eq(city.agricultural_parcels.get("record_copies"),0,"counter changes must avoid whole-store copies")
	check_eq(city.agricultural_parcels.get("canonical_copies"),0,"counter changes must not encode or copy the whole canonical proof")
	var work: int = city.agricultural_parcels.get("_data_validations")-initial
	check(work <= 160,"80 lifecycle changes must not repeat 80 whole-store land validations: %d" % work)
	var after := city.agricultural_parcels.to_dict()
	for id in range(1,81):
		var record := city.agricultural_parcels.record(id)
		var old: Dictionary = before.records[id-1]
		check_eq(record.last_month,1)
		check_eq(record.revision,old.revision+1)
		for field in ["members","modules","archetype","state","layout_seed","stock_units"]:
			var saved: Dictionary = after.records[id-1]
			check_eq(saved[field],old[field],field)
	check(AgriculturalParcels.decode(city.agricultural_parcels.to_dict(),city).ok)

func test_every_relevant_raw_land_edit_invalidates_other_record_proofs() -> void:
	for layer in ["building","zone","terrain","altitude","flags","flood"]:
		var city := populated()
		check_eq(update(city,1,0),OK)
		var index: int = city.agricultural_parcels.record(2).members[0]
		var point := AgriculturalParcels.tile(index)
		match layer:
			"building": city.building.data[index] = Buildings.NONE
			"zone": city.zone.data[index] = Zones.RES_LOW
			"terrain": city.terrain.data[index] = Terrain.SLOPE_W
			"altitude": city.altitude.data[index] = 5
			"flags": city.flags.data[index] |= TileFlags.LANDMARK
			"flood": city.flood_overlay[point] = true
		var before := snapshot(city)
		check_eq(update(city,1,1),ERR_INVALID_DATA,layer)
		check(snapshot(city)==before,"refusal must preserve raw edit and store: "+layer)
		# A second attempt must not adopt an invalid snapshot after refusal.
		check_eq(update(city,1,1),ERR_INVALID_DATA,layer)
		check(snapshot(city)==before,layer)

func test_exact_types_remain_required_after_warm_proof() -> void:
	var city := populated()
	check_eq(update(city,1,1),OK)
	var before := snapshot(city)
	for field in AgriculturalParcels.INTEGER_FIELDS:
		var record := city.agricultural_parcels.record(1)
		record[field] = float(record[field])
		check_eq(city.agricultural_parcels.put(city,record),ERR_INVALID_DATA,field)
		check(snapshot(city)==before,field)
	var record := city.agricultural_parcels.record(1)
	record.members = Array(record.members)
	check_eq(city.agricultural_parcels.put(city,record),ERR_INVALID_DATA)
	check(snapshot(city)==before)

func test_detached_copy_proofs_follow_its_own_layers() -> void:
	var city := populated()
	check_eq(update(city,1,0),OK)
	var copy := city.duplicate_city()
	var before := snapshot(city)
	var index: int = copy.agricultural_parcels.record(2).members[0]
	copy.zone.data[index] = Zones.RES_LOW
	check_eq(update(copy,1,1),ERR_INVALID_DATA)
	check(snapshot(city)==before,"detached validation cannot invalidate or change original")
	check_eq(update(city,1,1),OK)
	check_eq(copy.agricultural_parcels.record(1).last_month,0)

func test_benign_raw_write_refreshes_proofs_without_rejecting_legal_updates() -> void:
	var city := populated()
	check_eq(update(city,1,0),OK)
	city.flags.data[120*128+120] |= TileFlags.POWERED
	city.terrain.data[121*128+121] = Terrain.SLOPE_W
	check_eq(update(city,1,1),OK)
	check(AgriculturalParcels.decode(city.agricultural_parcels.to_dict(),city).ok)

func exhausted_store(city: City) -> void:
	var data := city.agricultural_parcels.to_dict()
	data.revision = AgriculturalParcels.MAX_ID
	var loaded := AgriculturalParcels.decode(data,city)
	check(loaded.ok)
	city.agricultural_parcels = loaded.store

func test_global_revision_exhaustion_refuses_put_without_writes_or_signals() -> void:
	var city := populated()
	exhausted_store(city)
	var signals := []
	city.agricultural_parcels.changed.connect(func(change: Dictionary) -> void: signals.append(change))
	var before := snapshot(city)
	check_eq(update(city,1,1),ERR_OUT_OF_MEMORY)
	check(snapshot(city)==before)
	check(signals.is_empty())
	check(AgriculturalParcels.decode(city.agricultural_parcels.to_dict(),city).ok)

func test_global_revision_exhaustion_refuses_legacy_adoption_atomically() -> void:
	var city := flat_city()
	var code := AgricultureParams.building_id(&"grain")
	city.stamp_building(20,20,code,Zones.AGR_LOW)
	exhausted_store(city)
	var lots: Array[Dictionary] = [{"zone_kind":Zones.AGR_LOW,"anchor":Vector2i(20,20),
		"rect":Rect2i(20,20,2,2),"archetype":&"grain","state":&"active","building_id":code,
		"failed_months":0,"last_month":-1}]
	var before := snapshot(city)
	check_eq(city.agricultural_parcels.adopt_legacy(city,lots),ERR_OUT_OF_MEMORY)
	check(snapshot(city)==before)
	check(AgriculturalParcels.decode(city.agricultural_parcels.to_dict(),city).ok)

func test_global_revision_exhaustion_refuses_discard_without_more_mutations() -> void:
	var city := flat_city()
	city.stamp_building(20,20,AgricultureParams.building_id(&"grain"),Zones.AGR_LOW)
	var source := F.source(city)
	exhausted_store(city)
	city.building.put(20,20,Buildings.NONE)
	var before := snapshot(city)
	city.agricultural_parcels.discard_invalid_legacy(city)
	check(snapshot(city)==before,"raw damaged square is not further mutated after exhausted refusal")
	check_eq(city.agricultural_parcels.revision,AgriculturalParcels.MAX_ID)
	source.ctx.systems.clear()

func test_exhausted_id_refuses_new_record_and_preserves_last_existing_identity() -> void:
	var city := populated()
	var data := city.agricultural_parcels.to_dict()
	data.next_id = AgriculturalParcels.MAX_ID
	var decoded := AgriculturalParcels.decode(data,city)
	check(decoded.ok)
	city.agricultural_parcels = decoded.store
	var members := F.square(2,Vector2i(90,90));F.zone(city,members)
	var before := snapshot(city)
	check_eq(city.agricultural_parcels.put(city,F.record(AgriculturalParcels.MAX_ID,members)),ERR_OUT_OF_MEMORY)
	check(snapshot(city)==before)
	check_eq(update(city,1,1),OK,"ID exhaustion does not prevent an existing identity changing")

func test_legacy_noops_do_not_require_a_new_revision() -> void:
	var city := populated()
	exhausted_store(city)
	var before := snapshot(city)
	check_eq(city.agricultural_parcels.adopt_legacy(city,[]),OK)
	city.agricultural_parcels.discard_invalid_legacy(city)
	check(snapshot(city)==before)

func test_raw_owner_removal_and_orphan_ownership_refuse_atomically() -> void:
	for orphan in [false,true]:
		var city := populated()
		check_eq(update(city,1,0),OK)
		var owners: PackedInt32Array = city.agricultural_parcels.get("_owners")
		var index: int = 120*128+120 if orphan else city.agricultural_parcels.record(2).members[0]
		owners[index] = 7 if orphan else 0
		var before := snapshot(city)
		check_eq(update(city,1,1),ERR_INVALID_DATA,"corrupt owner map must not be legitimized")
		check(snapshot(city)==before,"owner-map refusal must not change any source state")

func test_internal_record_changes_cannot_reuse_whole_store_proof() -> void:
	for field in ["last_month","id","modules","stock_units","mapping"]:
		var city := populated()
		check_eq(update(city,1,0),OK)
		var records: Dictionary = city.agricultural_parcels.get("_records")
		match field:
			"last_month": records[2].last_month = float(records[2].last_month)
			"id": records[2].id = 2.0
			"modules": records[2].modules = [{"key":&"farm_shed","at":Vector3(1000,.14,1000),"yaw":0}]
			"stock_units": records[2].stock_units[records[2].members[0]] = 0.0
			"mapping":
				var retained: Dictionary = records[2]
				records.erase(2)
				records[3] = retained
		var before := snapshot(city)
		check_eq(update(city,1,1),ERR_INVALID_DATA,field)
		check(snapshot(city)==before,"malformed canonical record must not be legitimized: "+field)

func test_state_changes_take_full_validation_and_publish_the_same_neighbor_contract() -> void:
	var city := flat_city()
	city.agricultural_parcels = CountedStore.new()
	for n in 2:
		var members := F.square(4,Vector2i(8+n*4,8))
		F.zone(city,members)
		check_eq(city.agricultural_parcels.put(city,F.record(n+1,members)),OK)
	check_eq(update(city,1,0),OK)
	city.agricultural_parcels.set("record_copies",0)
	var signals := []
	city.agricultural_parcels.changed.connect(func(change: Dictionary) -> void: signals.append(change))
	var record := city.agricultural_parcels.record(1)
	record.state = &"dormant"
	check_eq(city.agricultural_parcels.put(city,record),OK)
	check_gt(city.agricultural_parcels.get("record_copies"),0,"state is not a lifecycle counter")
	var first: Dictionary = signals[-1]
	check_eq(first.neighbor_ids,[2],"adjacent parcel remains in the update notification")
	check_eq(update(city,1,1),OK)
	var second: Dictionary = signals[-1]
	check_eq(first.ids,second.ids)
	check_eq(first.old_bounds,second.old_bounds)
	check_eq(first.new_bounds,second.new_bounds)
	check_eq(first.neighbor_ids,second.neighbor_ids)
	check_eq(second.revision,first.revision+1)
	check(AgriculturalParcels.decode(city.agricultural_parcels.to_dict(),city).ok)

func domain_record(value: Dictionary, kind: String) -> Dictionary:
	var r := value.duplicate(true)
	match kind:
		"field_keys":
			var d := {}
			for key in r: d[StringName(key)] = r[key]
			r = d
		"field_order":
			var d := {};var keys := r.keys();keys.reverse()
			for key in keys: d[key] = r[key]
			r = d
		"module_keys":
			var d := {}
			for key in r.modules[0]: d[StringName(key)] = r.modules[0][key]
			r.modules[0] = d
		"module_order":
			var d := {};var keys: Array = r.modules[0].keys();keys.reverse()
			for key in keys: d[key] = r.modules[0][key]
			r.modules[0] = d
		"stock_order":
			var d := {};var keys: Array = r.stock_units.keys();keys.reverse()
			for key in keys: d[key] = r.stock_units[key]
			r.stock_units = d
		"typed_modules":
			var modules: Array[Dictionary] = []
			for pose in r.modules: modules.append(pose)
			r.modules = modules
		"signed_zero": r.modules[0].at.x = -0.0
		"numeric": r.last_month = float(r.last_month)
		"members": r.members = Array(r.members)
		"module_type": r.modules[0].yaw = float(r.modules[0].yaw)
		"stock_key":
			var d := {}
			for key in r.stock_units: d[float(key)] = r.stock_units[key]
			r.stock_units = d
	return r

func domain_city(full: bool) -> City:
	var city := flat_city()
	city.agricultural_parcels = FullStore.new() if full else CountedStore.new()
	for n in 2:
		var members := F.square(4,Vector2i(8+n*4,8));F.zone(city,members)
		var r := F.record(n+1,members,&"sheep_pasture")
		r.origin_index += 2*128+2
		r.modules = [{"key":&"farm_shed","at":Vector3(0,.14,0),"yaw":0}]
		check_eq(city.agricultural_parcels.put(city,r),OK)
	return city

func exact_store(city: City) -> PackedByteArray:
	return var_to_bytes([city.agricultural_parcels.get("_records"),city.agricultural_parcels.revision,
		city.agricultural_parcels.get("_next_id"),city.agricultural_parcels.get("_owners"),
		city.building.data,city.zone.data,city.terrain.data,city.altitude.data,city.flags.data,city.flood_overlay])

func test_native_domain_matches_full_validation_for_legal_aliases_and_metadata() -> void:
	for kind in ["field_keys","field_order","module_keys","module_order","stock_order","typed_modules","signed_zero"]:
		for other in [false,true]:
			var fast := domain_city(false);var full := domain_city(true)
			var fast_events := [];var full_events := []
			fast.agricultural_parcels.changed.connect(func(c: Dictionary) -> void: fast_events.append(c))
			full.agricultural_parcels.changed.connect(func(c: Dictionary) -> void: full_events.append(c))
			if other:
				for city in [fast,full]:
					var records: Dictionary = city.agricultural_parcels.get("_records")
					records[2] = domain_record(records[2],kind)
			var incoming := domain_record(fast.agricultural_parcels.record(1),kind)
			incoming.last_month = 1
			check_eq(fast.agricultural_parcels.put(fast,incoming),OK,kind)
			check_eq(full.agricultural_parcels.put(full,incoming),OK,kind)
			check(exact_store(fast)==exact_store(full),"full validation must preserve the same exact canonical values: "+kind)
			check(var_to_bytes(fast_events)==var_to_bytes(full_events),kind)
			check_eq(update(fast,1,2),OK);check_eq(update(full,1,2),OK)
			check(exact_store(fast)==exact_store(full),kind)
			check(var_to_bytes(fast_events)==var_to_bytes(full_events),kind)

func test_native_domain_rejects_invalid_internal_values_like_full_validation() -> void:
	for kind in ["numeric","members","module_type","stock_key","top_float","mapping"]:
		var fast := domain_city(false);var full := domain_city(true)
		for city in [fast,full]:
			var records: Dictionary = city.agricultural_parcels.get("_records")
			if kind == "top_float" or kind == "mapping":
				var retained: Dictionary = records[2];records.erase(2)
				records[2.0 if kind == "top_float" else 3] = retained
			else: records[2] = domain_record(records[2],kind)
		var before := exact_store(fast)
		var fast_events := [];var full_events := []
		fast.agricultural_parcels.changed.connect(func(c: Dictionary) -> void: fast_events.append(c))
		full.agricultural_parcels.changed.connect(func(c: Dictionary) -> void: full_events.append(c))
		check_eq(update(fast,1,1),ERR_INVALID_DATA,kind)
		check_eq(update(full,1,1),ERR_INVALID_DATA,kind)
		check(exact_store(fast)==before,"failure is atomic: "+kind)
		check(exact_store(fast)==exact_store(full),kind)
		check_eq(fast_events,full_events);check(fast_events.is_empty())

func test_canonical_proofs_detach_nested_packed_members_and_city_clones() -> void:
	var city := domain_city(false)
	var clone := city.duplicate_city()
	var before := exact_store(city)
	var clone_records: Dictionary = clone.agricultural_parcels.get("_records")
	clone_records[2].members[0] = 12345
	check_eq(update(clone,1,1),ERR_INVALID_DATA,"a packed member edit cannot mutate its validation certificate")
	check(exact_store(city)==before,"clone records and certificates must be detached")
	check_eq(update(city,1,1),OK)
	var records: Dictionary = city.agricultural_parcels.get("_records")
	records[2].members[0] = 12345
	var damaged := exact_store(city)
	check_eq(update(city,1,2),ERR_INVALID_DATA)
	check(exact_store(city)==damaged)
