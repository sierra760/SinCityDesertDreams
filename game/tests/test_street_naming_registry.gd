# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Fixtures := preload("res://tests/fixtures/street_names_fixtures.gd")
const SERVICE_PATH := "res://scripts/core/naming/street_naming_service.gd"
const CODEC_PATH := "res://scripts/core/naming/street_naming_codec.gd"

func _service():
	check(FileAccess.file_exists(SERVICE_PATH), "atomic street edit service is implemented")
	return load(SERVICE_PATH).new() if FileAccess.file_exists(SERVICE_PATH) else null

func _codec():
	check(FileAccess.file_exists(CODEC_PATH), "strict naming codec is implemented")
	return load(CODEC_PATH) if FileAccess.file_exists(CODEC_PATH) else null

func _keys(values: Array) -> Array[String]:
	var result: Array[String] = []
	result.assign(values)
	return result

func _bound(f: Dictionary):
	var service = _service()
	if service != null: check(service.bind_city(f.city,f.topology).ok)
	return service

func _auto(ids: Array, base: String, suffix: int = 0) -> Dictionary:
	return {"source_street_ids":ids,"base_name":base,"suffix":suffix,"display_name":base if suffix==0 else base+" "+str(suffix)}

func test_assign_only_selected_links_and_full_rename_preserves_id() -> void:
	var f := Fixtures.junction()
	var s = _bound(f)
	if s == null: return
	var result: Dictionary = s.assign(_keys(f.arms.north),"  Palm   Avenue  ",f.topology.revision)
	check(result.ok)
	if not result.ok: return
	check_eq(f.city.street_naming.streets[result.street_id],"Palm Avenue")
	check(not f.city.street_naming.links.has(f.arms.east[0]))
	var renamed: Dictionary = s.assign(_keys(f.arms.north),"PALM AVENUE",f.topology.revision)
	check(renamed.ok and renamed.changed)
	check_eq(renamed.street_id,result.street_id)
	check_eq(f.city.street_naming.streets[result.street_id],"PALM AVENUE")
	check_eq(f.city.street_naming.next_street_id,2)

func test_reuse_normalized_name() -> void:
	var f := Fixtures.junction()
	var s = _bound(f)
	if s == null: return
	var first: Dictionary = s.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision)
	var reused: Dictionary = s.assign(_keys(f.arms.east),"  palm\u00a0 avenue  ",f.topology.revision)
	check(first.ok and reused.ok)
	check_eq(reused.street_id,first.street_id)
	check_eq(f.city.street_naming.streets.size(),1)
	check_eq(f.city.street_naming.streets[first.street_id],"Palm Avenue","reuse keeps saved spelling")

func test_partial_rename_merge_and_monotonic_retirement() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var first: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	var partial: Dictionary = s.assign(_keys([f.keys[0]]),"Fremont",f.topology.revision)
	check(first.ok and partial.ok)
	check_ne(partial.street_id,first.street_id)
	check_eq(f.city.street_naming.links[f.keys[1]],first.street_id)
	check_eq(f.topology.segments(f.city.street_naming.links).size(),2,"mixed memberships are selection boundaries")
	var merged: Dictionary = s.assign(_keys(f.keys.slice(1)),"fremont",f.topology.revision)
	check_eq(merged.street_id,partial.street_id)
	check_eq(f.city.street_naming.streets.size(),1)
	check(not f.city.street_naming.streets.has(first.street_id))
	check(s.remove(_keys(f.keys),f.topology.revision).ok)
	check(f.city.street_naming.streets.is_empty())
	var next: Dictionary = s.assign(_keys(f.keys),"New",f.topology.revision)
	check_gt(next.street_id,partial.street_id,"retired IDs never recycled")

func test_stale_selection_is_atomic() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	check(s.assign(_keys([f.keys[0]]),"Palm",f.topology.revision).ok)
	var before := var_to_bytes(f.city.street_naming)
	var rev: int = s.revision
	for values: Array in [[],[f.keys[0],f.keys[0]],[f.keys[0],"0,0,open>1,0,open"]]:
		var rejected: Dictionary = s.assign(_keys(values),"New",f.topology.revision)
		check(not rejected.ok and not rejected.changed)
		check_eq(var_to_bytes(f.city.street_naming),before)
		check_eq(s.revision,rev)
	check(not s.assign(_keys(f.keys),"New",f.topology.revision-1).ok)
	check(not s.remove(_keys(f.keys),f.topology.revision-1).ok)
	check_eq(var_to_bytes(f.city.street_naming),before)

func test_unnotified_structural_edit_and_city_rebind_reject_stale_selection() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var token: int = f.topology.revision
	var before := var_to_bytes(f.city.street_naming)
	f.city.building.put(10,8,0)
	check(not s.assign(_keys(f.keys),"Old selection",token).ok,"service refreshes current topology")
	check_eq(var_to_bytes(f.city.street_naming),before)
	var other := Fixtures.straight()
	check(s.bind_city(other.city,other.topology).ok)
	check(not s.assign(_keys(other.keys),"Old city",token).ok)
	check(other.city.street_naming.links.is_empty())
	other.topology.rebuild(f.city)
	check(not s.assign(_keys(other.keys),"Wrong binding",other.topology.revision).ok)
	check(not s.bind_city(other.city,other.topology).ok,"bind rejects mismatched City adapter")

func test_structural_loss_clears_membership_but_extensions_are_unnamed() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var first: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	f.city.flood_overlay[Vector2i(10,8)] = true
	check(not s.reconcile(Rect2i(10,8,1,1)).changed)
	check_eq(f.city.street_naming.links.size(),4,"flood preserves names")
	f.city.flood_overlay.clear()
	Fixtures.road(f.city,Vector2i(12,8),Vector2i(14,8))
	check(not s.reconcile(Rect2i(12,8,3,1)).changed)
	check(not f.city.street_naming.links.has("12,8,open>13,8,open"))
	f.city.building.put(10,8,0)
	var removed: Dictionary = s.reconcile(Rect2i(10,8,1,1))
	check(removed.ok and removed.changed)
	check_eq(f.city.street_naming.links.size(),2)
	check(f.city.street_naming.streets.has(first.street_id),"surviving fragments preserve identity")
	Fixtures.road(f.city,Vector2i(9,8),Vector2i(11,8))
	check(not s.reconcile(Rect2i(9,8,3,1)).changed)
	check(not f.city.street_naming.links.has("9,8,open>10,8,open"),"reconstruction stays unnamed")

func test_names_reject_controls_and_overlength_without_truncation() -> void:
	var codec = _codec()
	if codec == null: return
	check(codec.normalize_name("🌴".repeat(48)).ok)
	check(not codec.normalize_name("🌴".repeat(49)).ok)
	check_eq(codec.normalize_name("  Palm\u2003  Avenue  ").display,"Palm Avenue")
	check_eq(codec.normalize_name(" ÉCOLE ").comparison,"école")
	for text: String in ["", "   ", "Palm\nAvenue", "Palm\rAvenue", "Palm\tAvenue", "Palm\u0001Avenue", "Palm\u007fAvenue", "Palm\u0085Avenue", "Palm\u2028Avenue", "Palm\u2029Avenue"]:
		check(not codec.normalize_name(text).ok,"reject empty/control/line break")
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var before := var_to_bytes(f.city.street_naming)
	check(not s.assign(_keys(f.keys),"X".repeat(49),f.topology.revision).ok)
	check_eq(var_to_bytes(f.city.street_naming),before)

func test_codec_rejects_schema_ids_names_references_and_noncanonical_keys() -> void:
	var codec = _codec()
	if codec == null: return
	var good: Dictionary = codec.empty_metadata()
	good.streets = {1:"Palm"}
	good.next_street_id = 2
	good.links = {"8,8,open>9,8,open":1}
	check(codec.validate(good).ok)
	for bad: Variant in [null,{},[],{"schema":2},1]: check(not codec.validate(bad).ok)
	for field: String in ["schema","next_street_id","streets","links","station_auto"]:
		var bad := good.duplicate(true)
		bad.erase(field)
		check(not codec.validate(bad).ok)
	for id: Variant in [0,-1,1.0,"1"]:
		var bad := good.duplicate(true)
		bad.streets = {id:"Palm"}
		check(not codec.validate(bad).ok)
	for name: String in [" Palm ","Palm  Avenue","", "X".repeat(49),"Palm\nAvenue"]:
		var bad := good.duplicate(true)
		bad.streets[1] = name
		check(not codec.validate(bad).ok)
	var duplicate := good.duplicate(true)
	duplicate.streets[2] = "palm"
	duplicate.next_street_id = 3
	check(not codec.validate(duplicate).ok)
	var next := good.duplicate(true)
	next.next_street_id = 1
	check(not codec.validate(next).ok)
	for key: String in ["9,8,open>8,8,open","08,8,open>9,8,open","8,8,rail>9,8,open","-1,8,open>0,8,open","127,8,open>128,8,open","8,8,open>8,8,open","8,8,open>10,8,open","garbage"]:
		var bad := good.duplicate(true)
		bad.links = {key:1}
		check(not codec.validate(bad).ok,key)
	for id: Variant in [0,2,1.0,"1"]:
		var bad := good.duplicate(true)
		bad.links["8,8,open>9,8,open"] = id
		check(not codec.validate(bad).ok)
	var extra := good.duplicate(true)
	extra.unknown = true
	check(not codec.validate(extra).ok)

func test_codec_station_records_and_validation_copy_are_strict() -> void:
	var codec = _codec()
	if codec == null: return
	var block: Dictionary = codec.empty_metadata()
	block.streets = {1:"Palm",2:"Fremont"}
	block.next_street_id = 3
	block.station_auto = {Vector2i(9,9):_auto([1,2],"Palm & Fremont",2)}
	var valid: Dictionary = codec.validate(block)
	check(valid.ok)
	if valid.ok:
		valid.metadata.station_auto[Vector2i(9,9)].source_street_ids.clear()
		check_eq(block.station_auto[Vector2i(9,9)].source_street_ids,[1,2])
	for anchor: Variant in ["9,9",Vector2i(-1,9),Vector2i(128,9),Vector2(9,9)]:
		var bad := block.duplicate(true)
		bad.station_auto = {anchor:_auto([1],"Palm")}
		check(not codec.validate(bad).ok)
	for record: Dictionary in [_auto([3],"Palm"),_auto([1,1],"Palm"),_auto([],"Palm"),_auto([1],"Palm",1),_auto([1],"Palm",-1),_auto([1],"Palm\nStreet"),{"source_street_ids":[1],"base_name":"Palm","suffix":0,"display_name":"wrong"}]:
		var bad := block.duplicate(true)
		bad.station_auto[Vector2i(9,9)] = record
		check(not codec.validate(bad).ok)

func test_deep_copy_isolates_nested_naming_data() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var result: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	f.city.street_naming.station_auto[Vector2i(9,9)] = _auto([result.street_id],"Palm")
	var copy = f.city.duplicate_city()
	copy.street_naming.streets[result.street_id] = "Copy"
	copy.street_naming.links.clear()
	copy.street_naming.station_auto[Vector2i(9,9)].source_street_ids.clear()
	check_eq(f.city.street_naming.streets[result.street_id],"Palm")
	check_eq(f.city.street_naming.links.size(),4)
	check_eq(f.city.street_naming.station_auto[Vector2i(9,9)].source_street_ids,[result.street_id])

func test_naming_only_transactions_preserve_city_and_simulation() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var sim := make_simulation(f.city,98765)
	var before := SaveFormat.encode_city(f.city)
	before.erase("street_naming")
	var bytes := var_to_bytes(before)
	var snapshot := var_to_bytes(sim.snapshot())
	var rng_state := sim.rng.state()
	var layers: Array = []
	for grid in [f.city.terrain,f.city.altitude,f.city.building,f.city.zone,f.city.flags,f.city.underground,f.city.traffic,f.city.pollution,f.city.land_value,f.city.crime,f.city.police,f.city.fire_cover,f.city.density,f.city.growth]: layers.append(grid.data.duplicate())
	check(s.assign(_keys(f.keys),"Palm",f.topology.revision).ok)
	check(s.assign(_keys(f.keys),"Fremont",f.topology.revision).ok)
	check(s.remove(_keys([f.keys[0]]),f.topology.revision).ok)
	var after := SaveFormat.encode_city(f.city)
	after.erase("street_naming")
	check_eq(var_to_bytes(after),bytes)
	check_eq(var_to_bytes(sim.snapshot()),snapshot)
	check_eq(sim.rng.state(),rng_state)
	var index := 0
	for grid in [f.city.terrain,f.city.altitude,f.city.building,f.city.zone,f.city.flags,f.city.underground,f.city.traffic,f.city.pollution,f.city.land_value,f.city.crime,f.city.police,f.city.fire_cover,f.city.density,f.city.growth]:
		check_eq(grid.data,layers[index])
		index += 1
	sim.free()

func test_atomic_signal_noop_and_detached_affected_records() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var events: Array = []
	s.changed.connect(func(rev: int, affected: Dictionary) -> void: events.append({"revision":rev,"affected":affected.duplicate(true)}); affected.links.clear())
	var result: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	check(result.ok and result.changed)
	check_eq(events.size(),1)
	check_eq(result.affected.links.size(),4,"signal arguments cannot corrupt returned result")
	check_eq(events[0].revision,s.revision)
	check_eq(events[0].affected.street_ids,[result.street_id])
	var again: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	check(again.ok and not again.changed)
	check_eq(events.size(),1)
	check_eq(s.revision,result.revision)

func test_allocator_participates_in_atomic_draft_and_manual_refresh() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var anchor := Vector2i(9,9)
	f.city.facilities[anchor] = {"key":&"subway_station","built_day":0}
	f.city.building.put(9,9,Buildings.SUBWAY_STATION)
	var events: Array = []
	s.changed.connect(func(rev: int, affected: Dictionary) -> void: events.append({"revision":rev,"affected":affected}))
	s.set_station_allocator(func(_city: City,_topology: StreetTopology,draft: Dictionary) -> Dictionary:
		var id: int = draft.streets.keys()[0]
		return {"ok":true,"error":"","station_auto":{anchor:_auto([id],draft.streets[id])},"changed_anchors":[anchor]})
	var assigned: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	check(assigned.ok)
	check_eq(events.size(),1,"links and stations publish in one commit")
	check_eq(f.city.street_naming.station_auto[anchor].display_name,"Palm")
	check_eq(assigned.affected.station_anchors,[anchor])
	var manual_anchors: Array[Vector2i] = [anchor]
	var manual: Dictionary = s.refresh_station_names(manual_anchors)
	check(manual.ok and manual.changed,"manual title invalidation publishes even with unchanged automatic records")
	check_eq(events.size(),2)
	var before := var_to_bytes(f.city.street_naming)
	var rev: int = s.revision
	s.set_station_allocator(func(_city: City,_topology: StreetTopology,draft: Dictionary) -> Dictionary:
		draft.links.clear()
		return {"ok":false,"error":"allocation rejected","station_auto":{},"changed_anchors":[]})
	check(not s.assign(_keys(f.keys),"Fremont",f.topology.revision).ok)
	check_eq(var_to_bytes(f.city.street_naming),before)
	check_eq(s.revision,rev)
	check_eq(events.size(),2)

func test_binding_rejects_malformed_metadata_but_prunes_stale_station_records() -> void:
	var f := Fixtures.straight()
	var s = _service()
	if s == null: return
	f.city.street_naming.schema = 2
	var before := var_to_bytes(f.city.street_naming)
	check(not s.bind_city(f.city,f.topology).ok)
	check_eq(var_to_bytes(f.city.street_naming),before)
	f.city.street_naming.schema = 1
	f.city.street_naming.streets = {1:"Palm"}
	f.city.street_naming.next_street_id = 2
	f.city.street_naming.links = {f.keys[0]:1}
	f.city.street_naming.station_auto = {Vector2i(9,9):_auto([1],"Palm")}
	check(s.bind_city(f.city,f.topology).ok,"well-formed missing stations reconcile before use")
	check(f.city.street_naming.station_auto.is_empty())

func test_codec_rejects_empty_and_repeated_key_delimiters() -> void:
	var codec = _codec()
	if codec == null: return
	for key: String in ["8,,8,open>9,8,open","8,8,open>>9,8,open",">8,8,open>9,8,open","8,8,open>9,8,open>",",8,8,open>9,8,open","8,8,open,>9,8,open"]:
		var block: Dictionary = codec.empty_metadata()
		block.streets = {1:"Palm"}
		block.next_street_id = 2
		block.links = {key:1}
		check(not codec.validate(block).ok,key)

func test_allocator_malformed_output_rolls_back_and_draft_mutations_are_ignored() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	check(s.assign(_keys(f.keys),"Palm",f.topology.revision).ok)
	var before := var_to_bytes(f.city.street_naming)
	var rev: int = s.revision
	for response: Variant in [[],{}, {"ok":true,"station_auto":[],"changed_anchors":[]}, {"ok":true,"station_auto":{},"changed_anchors":[Vector2i(128,9)]}, {"ok":true,"station_auto":{Vector2i(9,9):_auto([99],"Unknown")},"changed_anchors":[]}]:
		s.set_station_allocator(func(_city: City,_topology: StreetTopology,_draft: Dictionary): return response)
		var result: Dictionary = s.assign(_keys(f.keys),"New",f.topology.revision)
		check(not result.ok and not result.changed)
		check_eq(var_to_bytes(f.city.street_naming),before)
		check_eq(s.revision,rev)
	s.set_station_allocator(func(_city: City,_topology: StreetTopology,draft: Dictionary) -> Dictionary:
		draft.links.clear()
		draft.streets.clear()
		return {"ok":true,"error":"","station_auto":{},"changed_anchors":[]})
	check(s.assign(_keys(f.keys),"New",f.topology.revision).ok)
	check_eq(f.city.street_naming.links.size(),4)
	check_eq(f.city.street_naming.streets.values(),["New"])
	check(not s.refresh_station_names().changed)

func test_signal_observes_complete_commit_and_reentrant_edits_are_rejected() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var events: Array = []
	var nested: Array = []
	s.changed.connect(func(rev: int,_affected: Dictionary) -> void:
		events.append(rev)
		if events.size()==1:
			check_eq(f.city.street_naming.streets.values(),["Palm"],"signal sees committed state")
			nested.append(s.assign(_keys(f.keys),"Nested",f.topology.revision)))
	var result: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	check(result.ok)
	check_eq(events.size(),1)
	check_eq(result.revision,1)
	check(not nested[0].ok and not nested[0].changed)
	check_eq(f.city.street_naming.streets.values(),["Palm"])

func test_bind_prunes_destroyed_station_and_stale_road_memberships_atomically() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var assigned: Dictionary = s.assign(_keys(f.keys),"Palm",f.topology.revision)
	var anchor := Vector2i(9,9)
	f.city.building.put(9,9,Buildings.SUBWAY_STATION)
	f.city.facilities[anchor] = {"key":&"subway_station","built_day":0,"name":"My custom station"}
	f.city.street_naming.station_auto[anchor] = _auto([assigned.street_id],"Palm",2)
	f.city.building.put(9,9,0)
	f.city.building.put(10,8,0)
	var rebound = _service()
	var events: Array = []
	rebound.changed.connect(func(_rev: int,affected: Dictionary) -> void: events.append(affected))
	var result: Dictionary = rebound.bind_city(f.city,f.topology)
	check(result.ok and result.changed)
	check_eq(events.size(),1)
	check_eq(f.city.street_naming.links.size(),2,"only surviving connections keep membership")
	check_eq(f.city.street_naming.streets,{assigned.street_id:"Palm"})
	check(f.city.street_naming.station_auto.is_empty())
	check_eq(f.city.facilities[anchor].name,"My custom station")
	check_eq(result.affected.station_anchors,[anchor])

func test_reconcile_prunes_destroyed_station_then_bind_retires_lost_source_id() -> void:
	var f := Fixtures.straight()
	var s = _bound(f)
	if s == null: return
	var assigned: Dictionary = s.assign(_keys([f.keys[0]]),"Palm",f.topology.revision)
	var anchor := Vector2i(9,9)
	f.city.building.put(9,9,Buildings.SUBWAY_STATION)
	f.city.facilities[anchor] = {"key":&"subway_station","built_day":0,"name":"Custom"}
	f.city.street_naming.station_auto[anchor] = _auto([assigned.street_id],"Palm")
	f.city.building.put(9,9,0)
	var reconciled: Dictionary = s.reconcile(Rect2i(9,9,1,1))
	check(reconciled.ok and reconciled.changed)
	check_eq(reconciled.affected.station_anchors,[anchor])
	check(f.city.street_naming.station_auto.is_empty())
	# A separately supplied valid derived reservation becomes stale when its
	# only structural membership disappears. Input references remain valid.
	f.city.street_naming.station_auto[anchor] = _auto([assigned.street_id],"Palm")
	f.city.building.put(8,8,0)
	var rebound = _service()
	var bound: Dictionary = rebound.bind_city(f.city,f.topology)
	check(bound.ok and bound.changed)
	check(f.city.street_naming.streets.is_empty())
	check(f.city.street_naming.station_auto.is_empty())
	check_eq(f.city.street_naming.next_street_id,2)
	check_eq(f.city.facilities[anchor].name,"Custom")
	if bound.ok:
		var next: Dictionary = rebound.assign(_keys([f.keys[2]]),"New",f.topology.revision)
		check_eq(next.street_id,2,"bind retirement never recycles IDs")
