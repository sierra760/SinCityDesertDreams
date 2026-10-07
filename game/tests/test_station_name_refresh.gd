# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
class StationWorld extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

static func named_city(subway: bool) -> City:
	var city := Fixtures.subway_city() if subway else Fixtures.rail_city()
	var y := 20 if subway else 21
	for x: int in [20,29]:
		var anchor := Vector2i(x,y)
		city.facilities[anchor]={"key":Buildings.key(city.building.atv(anchor)),"name":"Original Station"}
	return city

func _signs(node: Node, output: Array[Node]) -> void:
	if node.has_meta("station_entry_name") or node.has_meta("station_name_anchor"): output.append(node)
	for child: Node in node.get_children(): _signs(child,output)

func test_every_station_surface_uses_one_resolver() -> void:
	for subway: bool in [false,true]:
		var city := named_city(subway)
		var graph := CityTrafficGraph.new(); graph.bind_city(city)
		var network := ExploreTransitNetwork.new(); network.rebuild(city,graph,17)
		var path := network.route(0,1)
		var destinations := network.destinations(0)
		var posed := network.route_from_pose(0,1,network.station_for_route(path,0))
		var catalog := CityModelCatalog.new(); check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
		var buildings := CityBuildings3D.new(); root.add_child(buildings); buildings.rebuild(city,catalog)
		var batch := Batcher.new(); root.add_child(batch); batch.rebuild([buildings])
		check(int(batch.statistics.batches)>0,"real city static batching runs before name refresh")
		var world := StationWorld.new(); root.add_child(world); world.network=network; world.build(path)
		var title := "A".repeat(48)+" & "+"B".repeat(48)+" (2)"
		var anchors: Array[Vector2i]=[]
		for stop: Dictionary in network.stations:
			anchors.append(stop.anchor)
			city.facilities[stop.anchor].erase("name")
			city.street_naming.station_auto[stop.anchor]={"display_name":title}
		network.refresh_station_names()
		buildings.refresh_station_names(anchors)
		world.refresh_names()
		for stop: Dictionary in network.stations:
			check_eq(stop.name,title)
			var info := QueryPanel.describe(city,null,stop.anchor)
			check_eq(info.get("Name"),title)
			check_eq(info.get("Name mode"),"Automatic")
		check_eq(destinations[0].name,title,"already cached picker updates")
		check_eq(network.station_for_route(path,0).name,title,"cached route pose updates")
		check_eq(network.station_for_route(posed,0).name,title,"departure pose updates")
		check_eq(network.station_for_route(network.route(0,1),0).name,title,"deep route cache updates")
		check_eq(network.station_for_route(network.route_from_pose(0,1,network.station_for_route(path,0)),0).name,title,"deep departure cache updates")
		for layer: Node in [buildings,world]:
			var signs: Array[Node]=[]; _signs(layer,signs)
			check_eq(signs.size(),2 if layer==buildings else 4 if subway else 2,"all mounted station titles remain addressable")
			for sign: Node in signs:
				if sign.has_meta("station_entry_name"):
					check_eq(sign.get_meta("station_entry_name"),title)
					check_eq(sign.get_node("StationName").mesh.text,title.to_upper())
					check(sign.get_node("StationName").is_visible_in_tree(),"mutable title remains visible after static batching")
				else: check_eq(sign.mesh.text,"DESERT TRANSIT\n"+title)
		check_eq(network.revision,17)
		batch.free(); world.free(); buildings.free()
	await physics_frame

func test_unavailable_station_refreshes_resolved_title() -> void:
	var city := named_city(true)
	city.underground.data.fill(0)
	var graph := CityTrafficGraph.new(); graph.bind_city(city)
	var network := ExploreTransitNetwork.new(); network.rebuild(city,graph,2)
	check_eq(network.unavailable[0].name,"Original Station")
	city.facilities[Vector2i(20,20)].name="New Unavailable"
	if network.has_method("refresh_station_names"): network.call("refresh_station_names")
	check_eq(network.unavailable[0].name,"New Unavailable")
	city.facilities.erase(Vector2i(20,20))
	var info := QueryPanel.describe(city,null,Vector2i(20,20))
	check_eq(info.get("Name"),"Subway 20,20","physical station without facility record still has a resolved title")
	check_eq(info.get("Name mode"),"Automatic")

func test_automatic_rename_prompt_does_not_freeze_default() -> void:
	var host: GameHost=preload("res://scenes/main.tscn").instantiate()
	host.preferences_path="user://station-name-refresh.cfg"; root.add_child(host)
	var fixture := preload("res://tests/fixtures/street_names_fixtures.gd").station_city()
	var city: City = fixture.city
	var anchor: Vector2i = fixture.anchors.subway
	var names := StreetNamingService.new(); names.set_station_allocator(StationNameResolver.reconcile)
	check(names.bind_city(city,fixture.topology).ok)
	var keys: Array[String]=[]; keys.assign(fixture.street_keys.palm)
	check(names.assign(keys,"A".repeat(48),fixture.topology.revision).ok)
	keys.assign(fixture.street_keys.fremont)
	check(names.assign(keys,"B".repeat(48),fixture.topology.revision).ok)
	host.begin_city(city,{},42,CityStats.new())
	var automatic := StationNameResolver.display_name(city,anchor,true)
	check(automatic.length()>99,"allocated intersection and suffix exceed both custom limits")
	host.construction.prompt_rename(anchor)
	check_eq(host.notice_dialog.line_edit.text,"")
	check(host.notice_dialog.body_label.text.contains(StationNameResolver.display_name(city,anchor,true)),"automatic title is separate prompt context")
	check_eq(host.notice_dialog.line_edit.max_length,Builder.FACILITY_NAME_MAX)
	host.notice_dialog.dismiss(&"submit")
	check_eq(StationNameResolver.name_mode(city,anchor),&"automatic","blank submit does not freeze default")
	check_eq(StationNameResolver.display_name(city,anchor,true),automatic,"complete generated title and suffix survive blank submit")
	city.facilities[anchor].name="Custom"
	host.construction.prompt_rename(anchor)
	check_eq(host.notice_dialog.line_edit.text,"Custom")
	host.notice_dialog.line_edit.text=""; host.notice_dialog.dismiss(&"submit")
	check_eq(StationNameResolver.name_mode(city,anchor),&"automatic","explicit clear restores automatic")
	host.free(); await process_frame

func test_names_are_literal_in_hud_and_cached_route_options() -> void:
	var title := "[b]F to Plaza & Canyon[/b]"
	var hud := ExploreHUD.new(); root.add_child(hud)
	hud.set_touch_controls_enabled(true)
	var status := {"station_id":0,"selected_destination":1,"message":title+": No track.","message_literal":true,"destinations":[{"id":1,"name":title}]}
	hud.set_transit_status(status)
	check_eq(hud._transit_label.text,status.message,"station text does not undergo key-caption replacement")
	check_eq(hud._destination_picker.get_item_text(0),title,"allowed punctuation remains literal")
	var city := named_city(true)
	city.facilities[Vector2i(20,20)].name=title
	var panel := QueryPanel.new(); root.add_child(panel); panel.show_tile(city,null,Vector2i(20,20))
	check_eq(panel.info.Name,title)
	check_eq(panel.info["Name mode"],"Custom")
	var found := false
	for row: Node in panel.rows.get_children():
		if row is VBoxContainer and row.get_child_count()==2 and row.get_child(0).text=="Name":
			check(row.get_child(1) is Label)
			check_eq(row.get_child(1).text,title); found=true
	check(found,"Query mounted value is plain text")
	hud.free(); panel.free(); await process_frame

func test_main_name_revision_refresh_follows_replacement_city() -> void:
	var host: GameHost=preload("res://scenes/main.tscn").instantiate()
	host.preferences_path="user://station-name-lifecycle.cfg"; root.add_child(host)
	var first := named_city(true)
	host.begin_city(first,{},42,CityStats.new())
	var anchor := Vector2i(20,20)
	host.query_panel.show_tile(first,host.sim,anchor)
	check(host.builder.rename_facility(anchor,"First Renamed").ok)
	check(host.street_naming_service.refresh_station_names([anchor]).ok)
	check_eq(host.query_panel.info.Name,"First Renamed","naming signal refreshes current Query")
	var second := named_city(true)
	host.begin_city(second,{},43,CityStats.new())
	host.query_panel.show_tile(second,host.sim,anchor)
	check(host.builder.rename_facility(anchor,"Second Renamed").ok)
	check(host.street_naming_service.refresh_station_names([anchor]).ok)
	check_eq(host.query_panel.info.Name,"Second Renamed")
	check_eq(first.facilities[anchor].name,"First Renamed","new binding never refreshes old city")
	host.free(); await process_frame

func _retained_ids(node: Node) -> Array:
	var ids: Array=[node.get_instance_id()]
	for child: Node in node.get_children(): ids.append_array(_retained_ids(child))
	return ids

func test_matching_city_replacement_rebinds_retained_exterior_names() -> void:
	var host: GameHost=preload("res://scenes/main.tscn").instantiate()
	host.preferences_path="user://station-name-retained-city.cfg"; root.add_child(host)
	var first := named_city(true)
	host.begin_city(first,{},42,CityStats.new())
	var view: CityView3D=host.city_view_3d
	var anchor := Vector2i(20,20)
	var first_bytes := SaveFormat.encode_city(first)
	var retained := [_retained_ids(view.buildings),_retained_ids(view.mesh_batches),_retained_ids(view.chunks),_retained_ids(view.networks)]
	var revision := view._geometry_revision
	var physical: Dictionary=view.traversal_snapshot().networks
	var second := first.duplicate_city()
	for record: Dictionary in second.facilities.values(): record.name="City B Station"
	host.begin_city(second,{},43,CityStats.new())
	check_eq(view._geometry_revision,revision,"matching City replacement retains physical revision")
	check_eq([_retained_ids(view.buildings),_retained_ids(view.mesh_batches),_retained_ids(view.chunks),_retained_ids(view.networks)],retained,"building, sign, batch, terrain and collision identities retained")
	check_eq(view.traversal_snapshot().networks,physical,"resolved physical geometry retained")
	var signs: Array[Node]=[]; _signs(view.buildings,signs)
	check_eq(signs.size(),2)
	for sign: Node in signs:
		check_eq(sign.get_meta("station_entry_name"),"City B Station","replacement City title appears immediately on retained exterior")
		check_eq(sign.get_node("StationName").mesh.text,"CITY B STATION")
	check(host.builder.rename_facility(anchor,"B Renamed").ok)
	check(host.street_naming_service.refresh_station_names([anchor]).ok)
	for sign: Node in signs:
		var expected := "B Renamed" if sign.get_parent().get_meta("cell")==anchor else "City B Station"
		check_eq(sign.get_meta("station_entry_name"),expected,"subsequent B naming event uses B metadata")
		check_eq(sign.get_node("StationName").mesh.text,expected.to_upper())
	check_eq([_retained_ids(view.buildings),_retained_ids(view.mesh_batches),_retained_ids(view.chunks),_retained_ids(view.networks)],retained)
	check_eq(SaveFormat.encode_city(first),first_bytes,"old City metadata and all saved state remain untouched")
	host.free(); await process_frame
