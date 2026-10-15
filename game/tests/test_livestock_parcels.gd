# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
var camera: Camera3D
func before_each() -> void:
	root.size = Vector2i(1440,900)
	camera = Camera3D.new();root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 6
	focus(Vector3(22,CityGeometry3D.HEIGHT*4,21))
func after_each() -> void:
	camera.free()
	await process_frame
func focus(at: Vector3, turn: float = 0) -> void:
	camera.position = at+Vector3(0,60,60).rotated(Vector3.UP,turn);camera.look_at(at)

func test_generated_pause_cut_and_rotation_release_old_profile() -> void:
	var city := F.install_pair(flat_city(1000000));var source := F.source(city)
	var view := CityView3D.new();root.add_child(view);view.bind_city(city);view.set_active(true)
	var herds := view.livestock
	herds.sync_source(source.ag);herds.advance(.05,camera,false)
	check_eq(herds.detailed_animal_count(),6,"two active four-cell cattle parcels have three animals each")
	check_eq(F.rigs(herds),6)
	var before := F.herd_snapshot(herds)
	check_eq(before.size(),2)
	for item in before:
		check_gt(item.parcel_id,0)
		if item.parcel_id == 0: continue
		check_eq(item.transform,view.agriculture.record_for_parcel(item.parcel_id).transform)
		check_eq(item.profile,view.agriculture.record_for_parcel(item.parcel_id).layout.profile)
	check(F.all_live_herds_match_store(city,herds))
	for turn in 4:
		focus(Vector3(22,CityGeometry3D.HEIGHT*4,21),turn*PI/2)
		herds.advance(120,camera,true)
		check_eq(F.herd_snapshot(herds),before,"camera rotations do not advance or relocate herds")
	var old_root: int = before[0].root_id if not before.is_empty() else 0
	var change := city.remove_agricultural_cells(F.mask([[20,20],[20,21]]))
	check_eq(change.get("error",""),"","atomic cut succeeds")
	herds.sync_source(source.ag);herds.advance(120,camera,true)
	check(not is_instance_id_valid(old_root),"obsolete skeleton hierarchy freed in the same frame")
	var paused := F.herd_snapshot(herds)
	check_ne(paused,before);check_eq(F.rigs(herds),3)
	check(F.all_live_herds_match_store(city,herds))
	view.agriculture.flush_changes()
	check(F.all_logical_fences_have_one_physical_owner(F.rendered_records(view.agriculture)))
	herds.advance(120,camera,true);check_eq(F.herd_snapshot(herds),paused)
	view.free();source.ctx.systems.clear()

func test_stock_only_revisions_dormancy_and_city_replacement_reconcile_paused() -> void:
	var city := F.install_pair(flat_city());var source := F.source(city)
	var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
	herds.sync_source(source.ag);herds.advance(.05,camera,false)
	check_eq(F.rigs(herds),6)
	var record := city.agricultural_parcels.record(1)
	for i in record.stock_units: record.stock_units[i] = 0
	record.stock_units[record.members[0]] = 8;record.stock_units[record.members[1]] = 1
	check_eq(city.agricultural_parcels.put(city,record),OK)
	herds.sync_source(source.ag);check_eq(F.rigs(herds),3,"old three-stock hierarchy released before replacement allocation")
	herds.advance(120,camera,true);check_eq(F.rigs(herds),4)
	check(F.all_live_herds_match_store(city,herds))
	record = city.agricultural_parcels.record(1);record.state = &"dormant"
	check_eq(city.agricultural_parcels.put(city,record),OK)
	herds.sync_source(source.ag);check_eq(F.rigs(herds),3)
	herds.bind_city(flat_city());check_eq(F.rigs(herds),0);check_eq(herds.get_child_count(),0)
	herds.free();source.ctx.systems.clear()

func test_canonical_and_high_density_producers_share_static_source_keys() -> void:
	var city := F.install_pair(flat_city())
	for index in F.square(3,Vector2i(30,30)): city.zone.put(index%128,index/128,Zones.AGR_HIGH)
	city.stamp_building(30,30,AgricultureParams.building_id(&"feedlot"))
	var source := F.source(city);var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
	var keys := []
	for lot in source.ag.current_lots(): keys.append(String(lot.source_key))
	check(keys.has("parcel:1") and keys.has("parcel:2") and keys.has("legacy:30:30"))
	herds.sync_source(source.ag)
	var herd_keys := []
	for item in F.herd_snapshot(herds): herd_keys.append(item.source_key)
	check_eq(herd_keys.size(),3)
	for key in keys: check(herd_keys.has(key),"producer key survives admission: "+key)
	herds.free();source.ctx.systems.clear()


func test_distant_saved_origin_uses_actual_eight_corners_and_detail_bands() -> void:
	var city := flat_city();var record := F.record(1,F.square(2),&"cattle_range",&"active")
	record.origin_index = 0;record.modules = [];record.modules = AgriculturalParcelGeometry.plan(record).modules
	F.zone(city,record.members);check_eq(city.agricultural_parcels.put(city,record),OK)
	var source := F.source(city);var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
	herds.sync_source(source.ag);herds.advance(.05,camera,true)
	check_eq(F.rigs(herds),3,"visible extension gets detail despite distant saved origin")
	var items := F.herd_snapshot(herds);check_eq(items.size(),1)
	if items.size()==1:
		var corners: PackedVector3Array = herds.call("_herd_bounds",items[0])
		check_eq(corners.size(),8)
		for p in corners:
			check(p.x==20 or p.x==22);check(p.z==20 or p.z==22)
	for entry in [[Vector3(21,CityGeometry3D.HEIGHT*4,21),2],[Vector3(40,CityGeometry3D.HEIGHT*4,21),1],[Vector3(70,CityGeometry3D.HEIGHT*4,21),0]]:
		focus(entry[0]);herds.advance(100,camera,true)
		check_eq(F.herd_snapshot(herds)[0].detail,entry[1])
	focus(Vector3(21,CityGeometry3D.HEIGHT*4,21));camera.size=1000
	herds.advance(100,camera,true);check_eq(F.rigs(herds),0);check_eq(herds.get_child_count(),0)
	herds.free();source.ctx.systems.clear()

func test_generated_visible_extensions_compete_at_cap_without_transient_rigs() -> void:
	var city := flat_city();var id := 1
	# Nine visible fields and two wholly beside the camera compete for eight slots.
	for at: Vector2i in [Vector2i(56,64),Vector2i(60,64),Vector2i(64,64),Vector2i(68,64),Vector2i(56,68),Vector2i(60,68),Vector2i(64,68),Vector2i(68,68),Vector2i(62,72),Vector2i(52,64),Vector2i(72,64)]:
		var r := F.record(id,F.square(4,at),&"sheep_pasture",&"active")
		F.zone(city,r.members);check_eq(city.agricultural_parcels.put(city,r),OK);id+=1
	var source := F.source(city);var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
	herds.sync_source(source.ag)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=75
	camera.position=Vector3(64,CityGeometry3D.HEIGHT*4+.1,64);camera.look_at(Vector3(64,CityGeometry3D.HEIGHT*4+.1,74))
	herds.advance(.05,camera,true)
	check_eq(F.rigs(herds),96);check_eq(herds.detailed_animal_count(),96)
	for key in ["parcel:10","parcel:11"]:
		var item := F.herd_at(herds,key)
		check(not item.is_empty());if item.is_empty(): continue
		check_eq(item.detail,1,"offscreen stock yields scarce detailed slots")
	var before := F.herd_snapshot(herds)
	for z: float in [64.1,65,66,67,64]:
		camera.position.z=z;herds.advance(.05,camera,true)
		check(F.rigs(herds)<=96);check_eq(F.rigs(herds),herds.detailed_animal_count())
		for item in F.herd_snapshot(herds): check(item.count<=12)
	check_ne(F.herd_snapshot(herds),before,"moving visible edge changes whole-herd allocation")
	herds.free();source.ctx.systems.clear()

func test_square_and_legacy_profiles_keep_all_four_authored_enclosures() -> void:
	var catalog := AgricultureAssetCatalog.new();check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
	for key: StringName in [&"cattle_range",&"sheep_pasture",&"dairy",&"feedlot"]:
		var city := flat_city();var code := AgricultureParams.building_id(key)
		var low := key in [&"cattle_range",&"sheep_pasture"]
		for index in F.square(3): city.zone.put(index%128,index/128,Zones.AGR_LOW if low else Zones.AGR_HIGH)
		city.stamp_building(20,20,code)
		var source := F.source(city);var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
		herds.sync_source(source.ag);herds.advance(.05,camera,true)
		var items := F.herd_snapshot(herds);check_eq(items.size(),1)
		if items.size()==1:
			check_eq(items[0].profile,catalog.profile(key))
			check_eq(F.rigs(herds),8 if key in [&"cattle_range",&"dairy"] else (10 if key==&"sheep_pasture" else 12))
		herds.free();source.ctx.systems.clear()


func test_rotated_hole_and_neck_rigs_share_world_and_frozen_poses() -> void:
	for members in [F.expanded(F.ring()),F.expanded(F.dumbbell())]:
		var city := flat_city();F.zone(city,members)
		check_eq(city.agricultural_parcels.put(city,F.record(1,members,&"sheep_pasture",&"active")),OK)
		var source := F.source(city);var view := CityView3D.new();root.add_child(view);view.bind_city(city);view.set_active(true)
		var herds := view.livestock;herds.sync_source(source.ag)
		var bounds := AgriculturalParcels.bounds(members)
		var centre := Vector3(bounds.get_center().x,CityGeometry3D.HEIGHT*4,bounds.get_center().y)
		for rotation in 4:
			focus(centre,rotation*PI/2);herds.advance(.05,camera,false)
			check_eq(F.rigs(herds),12);check_eq(herds.get_parent(),view.world)
			check_eq(F.rigs(view.agriculture),0,"static geometry never duplicates skeletons")
			check(F.all_live_herds_match_store(city,herds))
			var before := F.herd_snapshot(herds)
			check_eq(before[0].poses.size(),12)
			for i in 10: herds.advance(120,camera,true)
			check_eq(F.herd_snapshot(herds),before,"all actual bones freeze at every camera rotation")
		view.free();source.ctx.systems.clear()

class CountingSource extends AgricultureSystem:
	var calls := 0
	func current_lots() -> Array[Dictionary]:
		calls+=1
		return super.current_lots()

func test_generated_revision_reconciles_once_without_per_frame_census() -> void:
	var city := F.install_pair(flat_city());var ctx := make_context(city,7)
	var source := CountingSource.new();ctx.systems[&"agriculture"]=source;source.setup(ctx)
	var herds := CityLivestock3D.new();root.add_child(herds);herds.bind_city(city)
	herds.sync_source(source);herds.advance(.05,camera,false)
	check_eq(F.rigs(herds),6)
	var roots := F.herd_snapshot(herds)
	for i in 120: herds.sync_source(source)
	check_eq(source.calls,1);check_eq(F.herd_snapshot(herds),roots)
	var r := city.agricultural_parcels.record(1);r.failed_months = 1
	check_eq(city.agricultural_parcels.put(city,r),OK)
	herds.sync_source(source)
	for i in 120: herds.sync_source(source)
	check_eq(source.calls,2,"one store revision triggers one producer snapshot")
	herds.free();ctx.systems.clear()

func test_square_cut_releases_centred_template_before_generated_readmission() -> void:
	var city := flat_city();var r := F.record(1,F.square(3),&"cattle_range",&"active")
	r.mode = &"square";r.legacy_code = AgricultureParams.building_id(&"cattle_range");r.modules = []
	F.zone(city,r.members);check_eq(city.agricultural_parcels.put(city,r),OK)
	var source := F.source(city);var view := CityView3D.new();root.add_child(view);view.bind_city(city);view.set_active(true)
	var herds := view.livestock;herds.sync_source(source.ag);herds.advance(.05,camera,true)
	check_eq(F.rigs(herds),8)
	var original := F.herd_snapshot(herds)[0]
	check_eq(original.transform.origin,Vector3(21.5,CityGeometry3D.HEIGHT*4,21.5))
	city.remove_agricultural_cells(F.mask([[22,22]]))
	herds.sync_source(source.ag);herds.advance(120,camera,true)
	check_eq(F.rigs(herds),0);check(not is_instance_id_valid(original.root_id))
	r = city.agricultural_parcels.record(1)
	check_eq(r.mode,&"generated");check_eq(r.state,&"prepared")
	r.state = &"active";check_eq(city.agricultural_parcels.put(city,r),OK)
	herds.sync_source(source.ag);herds.advance(120,camera,true)
	check_eq(F.rigs(herds),7,"remaining eight tiles retain 64/9 stock")
	var current := F.herd_snapshot(herds)[0]
	check_eq(current.source_key,"parcel:1");check_ne(current.root_id,original.root_id)
	check_eq(current.transform.origin,Vector3(20,CityGeometry3D.HEIGHT*4,20))
	check_eq(current.transform,view.agriculture.record_for_parcel(1).transform)
	check(F.all_live_herds_match_store(city,herds))
	view.free();source.ctx.systems.clear()

func test_healthy_month_retains_static_node_live_rigs_and_motion() -> void:
	var service_tests: SceneTree = load("res://tests/test_agricultural_parcel_services.gd").new()
	var f: Dictionary = service_tests.supplied_farm()
	service_tests.free()
	var city: City = f.city
	var old := city.agricultural_parcels.record(1)
	var removed := city.remove_agricultural_cells(old.members)
	check(removed.ok)
	var r := F.record(2,F.square(2),&"cattle_range",&"active")
	r.target_area = 4
	F.zone(city,r.members)
	for y in range(19,22):
		for x in range(20,22): city.underground.put(x,y,UtilityParams.pipe_code(15))
	city.facilities[Vector2i(20,19)].output = 100
	check_eq(city.agricultural_parcels.put(city,r),OK)
	f.water.reallocate_established(f.ctx,Rect2i(0,0,128,128))
	f.ag.networks_changed(f.ctx,Rect2i(19,19,4,4))
	check_eq(f.ag.inspect_tile(Vector2i(20,20)).blocked_reason,"")
	var view := CityView3D.new();root.add_child(view);view.bind_city(city);view.set_active(true)
	var herds := view.livestock
	herds.sync_source(f.ag)
	for tick in 90: herds.advance(.05,camera,false)
	var before := F.herd_at(herds,"parcel:2")
	var static_id: int = view.agriculture.record_for_parcel(2).node.get_instance_id()
	var motion: RefCounted = herds.get("_herds")["parcel:2"].motion
	check_gt(before.root_id,0)
	f.ctx.clock.day = GameClock.DAYS_PER_MONTH
	f.ag.monthly(f.ctx,0)
	check_eq(city.agricultural_parcels.record(2).failed_months,0)
	check_eq(city.agricultural_parcels.record(2).last_month,1)
	herds.sync_source(f.ag)
	var after := F.herd_at(herds,"parcel:2")
	check_eq(view.agriculture.record_for_parcel(2).node.get_instance_id(),static_id,"monthly bookkeeping retains actual static node")
	check_eq(after.root_id,before.root_id,"monthly bookkeeping retains every rig")
	check_eq(herds.get("_herds")["parcel:2"].motion,motion,"retain exact motion controller")
	check_eq(after.states,before.states,"no reset before next advance")
	herds.advance(.05,camera,false)
	check_ne(F.herd_at(herds,"parcel:2").states,before.states,"motion continues")
	check(F.all_live_herds_match_store(city,herds))
	view.free();f.ctx.systems.clear()
