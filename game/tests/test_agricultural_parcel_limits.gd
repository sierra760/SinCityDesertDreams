# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func fixture(store_remaining: int, record_remaining: int = 100) -> Dictionary:
	var c := flat_city()
	var m := F.square(2)
	F.zone(c,m)
	check_eq(c.agricultural_parcels.put(c,F.record(1,m)),OK)
	var source := F.source(c)
	var doc := c.agricultural_parcels.to_dict()
	doc.revision = AgriculturalParcels.MAX_ID-store_remaining
	doc.records[0].revision = AgriculturalParcels.MAX_ID-record_remaining
	var decoded := AgriculturalParcels.decode(doc,c)
	check(decoded.ok)
	c.agricultural_parcels = decoded.store
	return source

func source_bytes(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([SaveFormat.encode_city(f.ctx.city),f.ctx.stats.to_dict(),f.ctx.rng.state(),f.ctx.events.map_dirty,f.ctx.events.news,f.ctx.events.notices])

func refuses_atomically(f: Dictionary) -> void:
	var before: Dictionary = f.ag.save()
	var source := source_bytes(f)
	f.ag.monthly(f.ctx,0)
	check_eq(f.ag.migration_error(),ERR_OUT_OF_MEMORY,"counter exhaustion is an explicit failed recovery")
	check(not f.ag.repair_error().is_empty(),"counter refusal explains the exhausted resource")
	var after: Dictionary = f.ag.save()
	check_eq(after.get("migration_error",OK),ERR_OUT_OF_MEMORY)
	after.erase("migration_error")
	check_eq(after,before,"private RNG, demand and phase guards do not advance")
	check(source_bytes(f)==source,"no layers, ownership, facilities, stats, shared RNG or events change")
	check(AgriculturalParcels.decode(f.ctx.city.agricultural_parcels.to_dict(),f.ctx.city).ok,"the city remains decodable")
	f.ag.monthly(f.ctx,1)
	f.ag.networks_changed(f.ctx,Rect2i(20,20,2,2))
	after=f.ag.save();after.erase("migration_error")
	check_eq(after,before,"refusal remains latched across later calls")
	check(source_bytes(f)==source)
	f.ctx.systems.clear()

func test_zero_one_two_global_writes_remaining_refuse_before_phase_mutation() -> void:
	for remaining in [0,1,2]: refuses_atomically(fixture(remaining))

func test_zero_one_two_record_writes_remaining_refuse_before_phase_mutation() -> void:
	for remaining in [0,1,2]: refuses_atomically(fixture(100000,remaining))

func test_near_limit_refusal_never_replaces_an_existing_save() -> void:
	var f := fixture(1)
	var path := "user://agriculture-limits-existing.sc2d"
	check_eq(SaveFormat.save(path,f.ctx.city,{"systems":{"agriculture":f.ag.save()}}),OK)
	var previous := FileAccess.get_file_as_bytes(path)
	f.ag.monthly(f.ctx,0)
	check_eq(SaveFormat.save(path,f.ctx.city,{"systems":{"agriculture":f.ag.save()}}),ERR_INVALID_DATA)
	check(FileAccess.get_file_as_bytes(path)==previous)
	check(SaveFormat.load(path).ok,"the retained original save remains loadable")
	DirAccess.remove_absolute(path)
	f.ctx.systems.clear()

func test_ordinary_month_below_boundary_retains_existing_lifecycle_rules() -> void:
	var f := fixture(100000,100)
	var before: int = f.ctx.city.agricultural_parcels.revision
	f.ag.monthly(f.ctx,0)
	check_eq(f.ag.migration_error(),OK)
	check_eq(f.ag.save().phase_months,[0,-1])
	check_eq(f.ctx.city.agricultural_parcels.revision,before+1)
	check_eq(f.ctx.city.agricultural_parcels.record(1).last_month,0)
	check_eq(f.ctx.city.agricultural_parcels.record(1).state,&"prepared")
	check(AgriculturalParcels.decode(f.ctx.city.agricultural_parcels.to_dict(),f.ctx.city).ok)
	f.ctx.systems.clear()

func test_empty_city_does_not_need_parcel_revision_headroom() -> void:
	var c := flat_city()
	var doc := c.agricultural_parcels.to_dict()
	doc.revision = AgriculturalParcels.MAX_ID
	var decoded := AgriculturalParcels.decode(doc,c)
	check(decoded.ok)
	c.agricultural_parcels=decoded.store
	var f := F.source(c)
	f.ag.monthly(f.ctx,0)
	check_eq(f.ag.migration_error(),OK)
	check_eq(c.agricultural_parcels.revision,AgriculturalParcels.MAX_ID)
	f.ctx.systems.clear()

func test_exact_reserved_headroom_still_allows_an_ordinary_phase() -> void:
	var f := fixture(2 * 16384 + 2 * 16 + 2,4)
	f.ag.monthly(f.ctx,0)
	check_eq(f.ag.migration_error(),OK)
	check_eq(f.ag.save().phase_months,[0,-1])
	check(AgriculturalParcels.decode(f.ctx.city.agricultural_parcels.to_dict(),f.ctx.city).ok)
	f.ctx.systems.clear()

func test_direct_lifecycle_failure_is_returned_and_latched_without_assertion() -> void:
	var f := fixture(100000,0)
	var lot: Dictionary = f.ag.current_lots()[0]
	lot.last_month=1
	var before := source_bytes(f)
	var result: Variant = f.ag._persist_lot(lot)
	check_eq(result,ERR_OUT_OF_MEMORY)
	check_eq(f.ag.migration_error(),ERR_OUT_OF_MEMORY)
	check(not f.ag.repair_error().is_empty())
	check(source_bytes(f)==before)
	f.ctx.systems.clear()

func test_decline_ceiling_refuses_the_previously_underreserved_global_headroom() -> void:
	# A monthly phase can contain every saved owner, regardless of its location.
	# Reserving just one write per member leaves room for a partial mass decline.
	refuses_atomically(fixture(16384 + 2 * 16 + 2))

func test_declining_east_member_obeys_saved_phase_and_consumes_two_revisions() -> void:
	var c := flat_city()
	var members := F.square(1,Vector2i(80,20))
	F.zone(c,members)
	var r := F.record(1,members,&"grain",&"active")
	r.phase=0
	r.failed_months=AgricultureParams.FAILURE_MONTHS-1
	check_eq(c.agricultural_parcels.put(c,r),OK,"saved phase need not match current geographic half")
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	var f := F.source(c)
	var store_before := c.agricultural_parcels.revision
	var record_before: int = c.agricultural_parcels.record(1).revision
	f.ag.monthly(f.ctx,0)
	check_eq(c.agricultural_parcels.record(1).state,&"dormant")
	check_eq(c.agricultural_parcels.record(1).phase,0)
	check_eq(c.agricultural_parcels.revision-store_before,2,"aging and dormancy are separate store writes")
	check_eq(c.agricultural_parcels.record(1).revision-record_before,2)
	check_ge(AgricultureSystem.MONTHLY_STORE_REVISION_HEADROOM,(c.agricultural_parcels.revision-store_before)*AgriculturalParcels.CELL_COUNT+2*AgricultureSystem.DEVELOPMENT_BUDGET+2,"all legally same-phase owners require the observed per-owner write ceiling")
	f.ctx.systems.clear()
