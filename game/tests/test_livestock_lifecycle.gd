# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
const LAYER := "res://scripts/view/city_livestock_3d.gd"
var herds: Node3D
var camera: Camera3D
var city: City
var lots: Array[Dictionary] = []
var empty_lots: Array[Dictionary] = []
func before_all() -> void:
	root.size=Vector2i(1440,900)
func before_each() -> void:
	city=flat_city();lots=[]
	camera=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6
	point_camera(Vector3(21.5,CityGeometry3D.HEIGHT*4,21.5))
	if ResourceLoader.exists(LAYER):
		herds=load(LAYER).new();root.add_child(herds);herds.bind_city(city)
func after_each() -> void:
	if is_instance_valid(herds):herds.free()
	camera.free();herds=null
	await process_frame
func ready_layer() -> bool:
	check(herds!=null,"missing bounded CityLivestock3D layer")
	return herds!=null
func point_camera(focus:Vector3,turn:float=0.0)->void:
	camera.position=focus+Vector3(0,60,60).rotated(Vector3.UP,turn)
	camera.look_at(focus)
func add_lot(anchor:Vector2i,key:StringName=&"feedlot")->Dictionary:
	var code:=AgricultureParams.building_id(key);city.stamp_building(anchor.x,anchor.y,code)
	var lot:Dictionary={"anchor":anchor,"rect":Rect2i(anchor,Buildings.size(code)),"archetype":key,"building_id":code,"state":&"active"}
	lots.append(lot);return lot
func rigs(node:Node)->int:
	var count:=1 if node is Skeleton3D else 0
	for child:Node in node.get_children():count+=rigs(child)
	return count
func test_close_elevated_orthographic_camera_animates_and_pause_drops_time()->void:
	if not ready_layer():return
	add_lot(Vector2i(20,20));herds.sync_lots(lots);herds.advance(.05,camera,false)
	check_eq(herds.detailed_animal_count(),12,"ground focus, not elevated camera distance")
	var herd:Dictionary=F.herd_at(herds,"legacy:20:20")
	var before:Array=herd.states
	for i:int in 10:herds.advance(3600,camera,true)
	check_eq(F.herd_at(herds,"legacy:20:20").states,before)
	herds.advance(.05,camera,false)
	check_ne(F.herd_at(herds,"legacy:20:20").states,before)
	var reference:=LivestockMotion.new();reference.configure(herd.profile,herd.seed)
	reference.advance(.05);reference.advance(.05)
	check_eq(F.herd_at(herds,"legacy:20:20").states,reference.states(),"paused time never reaches motion")
func test_many_ranches_bound_actual_skeletons_and_whole_herds()->void:
	if not ready_layer():return
	for y:int in range(3,60,3):
		for x:int in range(3,60,3):add_lot(Vector2i(x,y))
	herds.sync_lots(lots);herds.advance(.05,camera,false)
	check_eq(herds.detailed_animal_count(),96)
	check_eq(rigs(herds),96,"actual independent rigs, not only a counter")
	var motions:=0
	for herd:Dictionary in F.herd_snapshot(herds):
		if herd.has_motion:motions+=1
		if herd.detail==2:check_eq(herd.children,12)
	check_eq(motions,8,"distant herds do not retain motion graphs")
	check_eq(lots.size(),361,"rendering never changes census")
	print("RESOURCE EVIDENCE: %d herds; %d skeletons; %d motion controllers" % [lots.size(),rigs(herds),motions] + "")
func test_dormancy_demolition_disaster_and_replacement_remove_while_paused()->void:
	if not ready_layer():return
	var lot:=add_lot(Vector2i(20,20))
	herds.sync_lots(lots);herds.advance(.05,camera,false)
	lot.state=&"dormant";herds.sync_lots(lots)
	check_eq(rigs(herds),0);check_eq(herds.get_child_count(),0)
	lot.state=&"active";herds.sync_lots(lots);herds.advance(.05,camera,true)
	check_eq(rigs(herds),12)
	city.building.put(21,21,Buildings.NONE);herds.sync_lots(lots)
	check_eq(rigs(herds),0,"stale caller records cannot retain disaster-damaged footprints")
	city.stamp_building(20,20,lot.building_id);herds.sync_lots(lots);herds.advance(.05,camera,true)
	herds.sync_lots(empty_lots);check_eq(herds.get_child_count(),0,"demolition removes immediately")
	herds.sync_lots(lots);herds.advance(.05,camera,true)
	herds.bind_city(flat_city());check_eq(herds.detailed_animal_count(),0)
	herds.clear();check_eq(herds.get_child_count(),0)
func test_late_sources_rebuild_and_camera_turns_preserve_identity()->void:
	if not ready_layer():return
	herds.sync_lots(empty_lots);herds.advance(.05,camera,false);check_eq(rigs(herds),0)
	add_lot(Vector2i(20,20));herds.sync_lots(lots);herds.advance(.05,camera,false)
	var herd:Dictionary=F.herd_at(herds,"legacy:20:20")
	var id:int=herd.root_id;var at:Transform3D=herd.root_transform
	for turn:int in 4:
		point_camera(Vector3(21.5,CityGeometry3D.HEIGHT*4,21.5),turn*PI/2)
		herds.sync_lots(lots);herds.advance(.05,camera,true)
		check_eq(F.herd_at(herds,"legacy:20:20").root_id,id);check_eq(F.herd_at(herds,"legacy:20:20").root_transform,at)
		check_eq(lots[0].anchor,Vector2i(20,20))
func test_static_distance_tiny_cull_and_repeat_promotions()->void:
	if not ready_layer():return
	add_lot(Vector2i(20,20));herds.sync_lots(lots)
	for i:int in 3:
		point_camera(Vector3(21.5,CityGeometry3D.HEIGHT*4,21.5));herds.advance(.05,camera,i%2==0);check_eq(rigs(herds),12)
		point_camera(Vector3(33.5,CityGeometry3D.HEIGHT*4,21.5));camera.size=16;herds.advance(.05,camera,false)
		check_eq(rigs(herds),0);check_eq(herds.detailed_animal_count(),0)
		var herd:Dictionary=F.herd_at(herds,"legacy:20:20")
		check_eq(herd.detail,1);check(not herd.has_motion)
		check_gt(herd.children,0,"cheap static instances exist")
		point_camera(Vector3(70,CityGeometry3D.HEIGHT*4,21.5));herds.advance(.05,camera,false)
		check_eq(herds.get_child_count(),0,"over 32 tiles allocates no animals")
		point_camera(Vector3(21.5,CityGeometry3D.HEIGHT*4,21.5));camera.size=1000;herds.advance(.05,camera,false)
		check_eq(herds.get_child_count(),0,"below two pixels culls")
		camera.size=6
func test_view_visibility_and_static_compilation_keep_dynamic_sibling()->void:
	if not ready_layer():return
	var view:=CityView3D.new();root.add_child(view);view.bind_city(city)
	check(view.get("livestock")!=null)
	var layer:Node3D=view.get("livestock")
	if layer!=null:
		check_eq(layer.get_parent(),view.world)
		check(layer.get_parent()!=view.buildings)
		view.set_overlay(&"land_value");check(not layer.visible)
		view.set_overlay(&"");check(layer.visible)
		view.set_underground(true);check(not layer.visible)
		view.set_underground(false);check(layer.visible)
		var presentation:=CityPresentationController.new();presentation.view=view
		presentation.sync_actors(.05,[],null,true,false)
		check(layer.visible,"vehicle preference does not hide animals")
		presentation.free()
	view.free()


class ClockHost extends GameHost:
	var blocked := false
	var table := false
	func is_input_blocked() -> bool: return blocked or table
	func is_explore_input_blocked() -> bool: return blocked or table
	func is_casino_open() -> bool: return table

func test_actual_host_city_explore_pause_modal_and_table_clocks()->void:
	if not ready_layer():return
	var host:=ClockHost.new();host.sim=Simulation.new()
	host.exploration=CityExplorationController.new()
	host.sim.speed=GameClock.Speed.PAUSED
	check(host.livestock_paused())
	host.sim.speed=GameClock.Speed.SLOW
	check(not host.livestock_paused())
	host.sim.speed=GameClock.Speed.PAUSED
	host.exploration.set("_active",true)
	check(not host.livestock_paused(),"active Explore advances while construction paused")
	add_lot(Vector2i(20,20));herds.sync_lots(lots)
	herds.advance(.05,camera,host.livestock_paused())
	var herd:Dictionary=F.herd_at(herds,"legacy:20:20")
	var before:Array=herd.states
	host.exploration.set("_suspended",true)
	check(host.livestock_paused());herds.advance(1000,camera,host.livestock_paused())
	check_eq(F.herd_at(herds,"legacy:20:20").states,before)
	host.exploration.set("_suspended",false)
	host.blocked=true
	check(host.livestock_paused());herds.advance(1000,camera,host.livestock_paused())
	host.blocked=false;host.table=true
	check(host.livestock_paused());herds.advance(1000,camera,host.livestock_paused())
	check_eq(F.herd_at(herds,"legacy:20:20").states,before)
	host.table=false
	herds.advance(.05,camera,host.livestock_paused())
	check_ne(F.herd_at(herds,"legacy:20:20").states,before)
	host.exploration.set("_active",false);check(host.livestock_paused())
	host.exploration.free();host.sim.free();host.free()

func test_actual_imported_compiled_farm_transform_and_rebuild_retention()->void:
	if not ready_layer():return
	add_lot(Vector2i(20,20))
	city.set_heights(22,22,7,0)
	var view:=CityView3D.new();root.add_child(view);view.bind_city(city);view.set_active(true)
	var layer:Node3D=view.get("livestock")
	layer.sync_lots(lots);layer.advance(.05,camera,true)
	var herd:Dictionary=F.herd_at(layer,"legacy:20:20")
	var imported:Transform3D=view.buildings.authored_lot_transform(Vector2i(20,20),lots[0].building_id)
	check_eq(herd.root_transform,imported)
	check(imported.basis.get_scale().is_equal_approx(Vector3.ONE/16.0),"exactly one metre-to-tile scale")
	check_eq(imported.origin.y,CityBuildings3D.base_height(city,lots[0].rect,lots[0].building_id))
	check(view.catalog.runtime_scenes.get([lots[0].building_id,true]) is PackedScene,"farm still uses runtime compilation")
	var id:int=herd.root_id
	for i:int in 3:
		view.refresh();layer.sync_lots(lots);layer.advance(.05,camera,true)
		check_eq(F.herd_at(layer,"legacy:20:20").root_id,id)
		check_eq(rigs(view.buildings),0);check_eq(rigs(view.mesh_batches),0)
		check_eq(rigs(layer),12)
	view.free()


func test_validated_agriculture_census_removes_dormancy_and_late_damage()->void:
	if not ready_layer():return
	var code:=AgricultureParams.building_id(&"feedlot")
	for y:int in range(20,23):
		for x:int in range(20,23):city.zone.put(x,y,Zones.make(Zones.AGR_HIGH))
	city.stamp_building(20,20,code)
	var ctx:=make_context(city,75);var agriculture:=AgricultureSystem.new()
	agriculture.setup(ctx)
	herds.sync_lots(agriculture.current_lots());herds.advance(.05,camera,true)
	check_eq(rigs(herds),12)
	city.stamp_building(20,20,AgricultureParams.state_id(&"dormant",3))
	herds.sync_lots(agriculture.current_lots());check_eq(rigs(herds),0)
	city.stamp_building(20,20,code)
	herds.sync_lots(agriculture.current_lots());herds.advance(.05,camera,true)
	check_eq(rigs(herds),12)
	city.building.put(21,21,Buildings.NONE)
	herds.sync_lots(agriculture.current_lots());check_eq(herds.get_child_count(),0)
	ctx.systems.clear()


class CountingAgriculture extends AgricultureSystem:
	var census_calls := 0
	func current_lots() -> Array[Dictionary]:
		census_calls += 1
		return super.current_lots()

func counted_source(value: City) -> CountingAgriculture:
	var source := CountingAgriculture.new()
	source.setup(make_context(value,81))
	return source

func stamp_stock(value: City, anchor: Vector2i) -> void:
	for y: int in range(anchor.y,anchor.y+3):
		for x: int in range(anchor.x,anchor.x+3): value.zone.put(x,y,Zones.make(Zones.AGR_HIGH))
	value.stamp_building(anchor.x,anchor.y,AgricultureParams.building_id(&"feedlot"))

func test_unchanged_empty_and_many_ranch_frames_do_not_repeat_full_census() -> void:
	if not ready_layer(): return
	check(herds.has_method("sync_source"),"missing cached source synchronization")
	if not herds.has_method("sync_source"): return
	var source := counted_source(city)
	herds.sync_source(source)
	for i: int in 120: herds.sync_source(source)
	check_eq(source.census_calls,1,"unchanged empty frames do not scan the city")
	for y: int in range(3,60,3):
		for x: int in range(3,60,3): stamp_stock(city,Vector2i(x,y))
	herds.sync_source(source)
	check_eq(source.census_calls,2,"raw late additions trigger one complete census")
	check_eq(F.herd_snapshot(herds).size(),361)
	for i: int in 120: herds.sync_source(source)
	check_eq(source.census_calls,2,"unchanged many-ranch frames do not scan/copy the census")

func test_cached_source_detects_raw_layers_paused_removal_and_replacement() -> void:
	if not ready_layer(): return
	check(herds.has_method("sync_source"),"missing cached source synchronization")
	if not herds.has_method("sync_source"): return
	var source := counted_source(city)
	herds.sync_source(source)
	stamp_stock(city,Vector2i(20,20))
	herds.sync_source(source);herds.advance(.05,camera,true)
	check_eq(rigs(herds),12);check_eq(source.census_calls,2)
	city.building.data[21*City.WIDTH+21] = Buildings.NONE
	herds.sync_source(source)
	check_eq(rigs(herds),0,"direct packed building mutation removes while paused")
	stamp_stock(city,Vector2i(20,20))
	herds.sync_source(source);herds.advance(.05,camera,true)
	check_eq(rigs(herds),12)
	city.zone.data[21*City.WIDTH+21] = 0
	herds.sync_source(source)
	check_eq(rigs(herds),0,"direct zone mutation invalidates stock footprint")
	stamp_stock(city,Vector2i(20,20))
	herds.sync_source(source);herds.advance(.05,camera,true)
	var replacement := flat_city()
	herds.bind_city(replacement)
	var replacement_source := counted_source(replacement)
	herds.sync_source(replacement_source)
	check_eq(rigs(herds),0);check_eq(herds.get_child_count(),0)
	check_eq(replacement_source.census_calls,1)
	var later_source := counted_source(replacement)
	herds.sync_source(later_source)
	check_eq(later_source.census_calls,1,"producer replacement invalidates identical packed layers")
	herds.sync_source(null)
	check_eq(F.herd_snapshot(herds).size(),0)

func test_source_events_reconcile_once_and_geometry_rebuild_refreshes_transform() -> void:
	if not ready_layer(): return
	check(herds.has_method("sync_source"),"missing cached source synchronization")
	if not herds.has_method("sync_source"): return
	stamp_stock(city,Vector2i(20,20))
	var source := counted_source(city)
	var view := CityView3D.new();root.add_child(view);view.bind_city(city)
	var layer := view.livestock
	layer.sync_source(source)
	check_eq(source.census_calls,1)
	view.geometry_rebuilt.emit(1)
	layer.sync_source(source)
	check_eq(source.census_calls,2,"geometry event invalidates cached authored transform")
	var presentation := CityPresentationController.new();presentation.view=view
	presentation.invalidate_livestock_source()
	layer.sync_source(source)
	check_eq(source.census_calls,3,"map notification invalidates producer snapshot")
	for i: int in 20: layer.sync_source(source)
	check_eq(source.census_calls,3)
	presentation.free();view.free()

# Visible or edge-intersecting herds win over nearer wholly offscreen herds.
func test_perspective_visible_whole_herd_priority_at_cap() -> void:
	if not ready_layer(): return
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=75
	camera.position=Vector3(64.5,.6,64);camera.look_at(Vector3(64.5,.6,74))
	for y:int in [64,67,70]:
		for x:int in [57,60,63,66,69]:
			if y==70 and x!=63: continue
			add_lot(Vector2i(x,y))
	herds.sync_lots(lots);herds.advance(.05,camera,true)
	check_eq(herds.detailed_animal_count(),96)
	check_eq(rigs(herds),96)

	# Nine lots intersect the frustum: the last of three 7.5-tile ties is
	# legitimately static under the stable distance/anchor order and 96 cap.
	check_eq(F.herd_at(herds,"legacy:63:70").detail,1,"stable anchor order resolves the nine-visible-herd overflow")
	check_eq(F.herd_at(herds,"legacy:57:64").detail,1,"nearer wholly offscreen herd releases its detailed slots")
	check_eq(F.herd_at(herds,"legacy:60:64").detail,2,"partial edge herd competes as visible even with centre offscreen")
	check_eq(F.herd_at(herds,"legacy:66:64").detail,2)
	check_eq(F.herd_at(herds,"legacy:57:67").detail,2);check_eq(F.herd_at(herds,"legacy:69:67").detail,2)
	camera.position.z=64.1
	herds.advance(.05,camera,true)
	check_eq(F.herd_at(herds,"legacy:63:70").detail,2,"visible central herd promoted once nearer than the edge ties")
	check(not camera.is_position_in_frustum(F.herd_at(herds,"legacy:57:64").transform.origin))
	check_eq(F.herd_at(herds,"legacy:69:64").detail,1,"distance/anchor tie order applies after visible priority")
	var at:Transform3D=F.herd_at(herds,"legacy:63:70").transform
	camera.look_at(Vector3(54.5,.6,64));herds.advance(.05,camera,true)
	check(rigs(herds)<=96);check_eq(F.herd_at(herds,"legacy:63:70").transform,at)
	camera.look_at(Vector3(64.5,.6,74));herds.advance(.05,camera,true)
	check_eq(F.herd_at(herds,"legacy:63:70").detail,2)

func test_frustum_edge_intersection_and_camera_inside_lot_keep_detail() -> void:
	if not ready_layer(): return
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=75
	camera.position=Vector3(64.5,.1,64);camera.look_at(Vector3(64.5,.1,74))
	# Centre is outside the side plane; the lot's near right edge is visible.
	add_lot(Vector2i(60,64));herds.sync_lots(lots)
	var herd:Dictionary=F.herd_at(herds,"legacy:60:64")
	check(not camera.is_position_in_frustum(herd.transform.origin))
	check(camera.is_position_in_frustum(Vector3(62.9,.1,66.9)))
	herds.advance(.05,camera,true);check_eq(F.herd_at(herds,"legacy:60:64").detail,2)
	# Centre behind camera, while a broad part of the enclosure remains ahead.
	camera.position=Vector3(61.5,.1,66);camera.look_at(Vector3(61.5,.1,76))
	herds.advance(.05,camera,true);check_eq(F.herd_at(herds,"legacy:60:64").detail,2,"near plane intersection must not cull from centre depth")
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6
	point_camera(Vector3(61.5,herd.transform.origin.y,65.5))
	herds.advance(.05,camera,true);check_eq(F.herd_at(herds,"legacy:60:64").detail,2)
	check_eq(rigs(herds),12)
