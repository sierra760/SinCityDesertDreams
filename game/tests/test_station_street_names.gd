# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/fixtures/street_names_fixtures.gd")
const Service := preload("res://scripts/core/naming/street_naming_service.gd")
const RESOLVER := "res://scripts/core/naming/station_name_resolver.gd"
const ACCESS := "res://scripts/core/naming/station_street_access.gd"
func _resolver():
	check(FileAccess.file_exists(RESOLVER),"station allocator exists")
	return load(RESOLVER) if FileAccess.file_exists(RESOLVER) else null
func _keys(values: Array) -> Array[String]:
	var result: Array[String] = []
	result.assign(values)
	return result
func _named(f: Dictionary, resolver, palm: String = "Palm Avenue", fremont: String = "Fremont Street") -> StreetNamingService:
	var service := Service.new()
	service.set_station_allocator(resolver.reconcile)
	check(service.bind_city(f.city,f.topology).ok)
	check(service.assign(_keys(f.street_keys.palm),palm,f.topology.revision).ok)
	check(service.assign(_keys(f.street_keys.fremont),fremont,f.topology.revision).ok)
	return service
func test_intersection_precedes_neighbor_street_and_custom_name_wins() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	check_eq(f.city.facilities.size(),2)
	check_eq(resolver.display_name(f.city,f.anchors.rail,false),"Palm Avenue & Fremont Street")
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
	f.city.facilities[f.anchors.rail]["name"] = "Union Terminal"
	check_eq(resolver.display_name(f.city,f.anchors.rail,false),"Union Terminal")
	check_eq(resolver.name_mode(f.city,f.anchors.rail),&"custom")
	check(service.refresh_station_names([f.anchors.rail]).ok)
	f.city.facilities[f.anchors.rail].erase("name")
	check(service.refresh_station_names([f.anchors.rail]).ok)
	check_eq(resolver.name_mode(f.city,f.anchors.rail),&"automatic")
func test_numbers_are_stable_across_reload_and_demolition() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	Fixtures.station(f.city,f.anchors.second_rail,false)
	check(service.reconcile(Rect2i()).ok)
	check_eq(resolver.display_name(f.city,f.anchors.second_rail,false),"Palm Avenue & Fremont Street 3")
	var copy: City = f.city.duplicate_city()
	var t := StreetTopology.new()
	t.rebuild(copy)
	var rebound := Service.new()
	rebound.set_station_allocator(resolver.reconcile)
	check(rebound.bind_city(copy,t).ok)
	check_eq(copy.street_naming,f.city.street_naming)
	check(Builder.new(f.city,CityStats.new()).apply(Tools.Kind.BULLDOZE,f.anchors.rail).ok)
	check(service.reconcile(Rect2i()).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
	check_eq(resolver.display_name(f.city,f.anchors.second_rail,false),"Palm Avenue & Fremont Street 3")
func test_complete_literal_names_reserve_case_whitespace_and_fallbacks() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	Fixtures.station(f.city,f.anchors.second_rail,false)
	f.city.facilities[f.anchors.rail]["name"] = "  PALM\u00a0 avenue & Fremont Street 2  "
	var service := _named(f,resolver)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 3")
	check_eq(resolver.display_name(f.city,f.anchors.rail,false),"  PALM\u00a0 avenue & Fremont Street 2  ")
	f.city.facilities[f.anchors.second_rail]["name"] = f.city.facilities[f.anchors.rail].name
	check(service.refresh_station_names([f.anchors.second_rail]).ok)
	check_eq(f.city.facilities[f.anchors.second_rail].name,f.city.facilities[f.anchors.rail].name)
	check(service.assign(_keys(f.street_keys.palm),"Palm 2",f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm 2 & Fremont Street 3")
	var fallback := Vector2i(1,2)
	Fixtures.station(f.city,fallback,false)
	check(service.remove(_keys(f.street_keys.fremont),f.topology.revision).ok)
	check(service.assign(_keys(f.street_keys.palm),"Rail 1,2",f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,fallback,false),"Rail 1,2")
	check_eq(resolver.name_mode(f.city,fallback),&"automatic","coordinate fallback keeps automatic ownership")
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Rail 1,2 2")
func test_surface_front_full_footprint_radius_and_no_service() -> void:
	var resolver = _resolver()
	if resolver==null: return
	check(FileAccess.file_exists(ACCESS))
	if not FileAccess.file_exists(ACCESS): return
	var access = load(ACCESS)
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	var network := ExploreTransitNetwork.new()
	network.rebuild(f.city,CityTrafficGraph.new(),1)
	check(network.stations.is_empty(),"physical stations name even without usable service")
	var entrance: Dictionary = access.surface_entrance(f.city,f.anchors.rail)
	check_eq(entrance.footprint,Rect2i(f.anchors.rail,Vector2i(2,2)))
	check_eq(entrance.yaw,CityBuildings3D._station_yaw(f.city,entrance.footprint,Buildings.RAIL_STATION))
	check_gt(Vector2(f.anchors.rail).distance_to(Vector2(9,9)),2.0,"junction is beyond anchor radius but within footprint radius")
	check(not access.neighbors(f.city,f.topology,f.anchors.rail,f.city.street_naming).is_empty())
	for distance: int in [2,3]:
		var city := flat_city()
		var anchor := Vector2i(10,10)
		Fixtures.station(city,anchor,false)
		Fixtures.road(city,Vector2i(9,11+distance),Vector2i(14,11+distance))
		var t := StreetTopology.new()
		t.rebuild(city)
		var s := Service.new()
		s.set_station_allocator(resolver.reconcile)
		check(s.bind_city(city,t).ok)
		var k := StreetTopology.link_key(Vector2i(10,11+distance),&"open",Vector2i(11,11+distance),&"open")
		check(s.assign(_keys([k]),"Edge Road",t.revision).ok)
		check_eq(resolver.display_name(city,anchor,false),"Edge Road" if distance==2 else "Rail 10,10")
	# Track orientation comes from the same canonical physical candidates.
	check(Builder.new(f.city,CityStats.new()).apply(Tools.Kind.RAIL,Vector2i(6,5),Vector2i(10,5)).ok)
	entrance = access.surface_entrance(f.city,f.anchors.rail)
	check_eq(entrance.yaw,CityBuildings3D._station_yaw(f.city,entrance.footprint,Buildings.RAIL_STATION))
	check_gt(absf(entrance.yaw),1.0)
	check(service.reconcile(Rect2i()).ok)
func test_manual_claim_removal_reassignment_and_atomic_pure_allocation() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	var before: City = f.city.duplicate_city()
	var before_rng := Simulation.new()
	before_rng.setup(f.city,912)
	var snapshot := before_rng.snapshot()
	var metadata: Dictionary = f.city.street_naming.duplicate(true)
	var encoded_before := SaveFormat.encode_city(f.city)
	var topology_revision: int = f.topology.revision
	var result: Dictionary = resolver.reconcile(f.city,f.topology,metadata)
	check_eq(SaveFormat.encode_city(f.city),encoded_before,"allocator never writes any city field/layer")
	check_eq(f.topology.revision,topology_revision)
	check(result.ok)
	check_eq(metadata,f.city.street_naming,"allocator draft remains untouched")
	check_eq(f.city.funds,before.funds)
	check_eq(f.city.building.data,before.building.data)
	check_eq(before_rng.snapshot(),snapshot)
	before_rng.free()
	Fixtures.station(f.city,f.anchors.second_rail,false)
	f.city.facilities[f.anchors.second_rail]["name"] = "Palm Avenue & Fremont Street 2"
	check(service.refresh_station_names([f.anchors.second_rail]).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 3")
	check(service.assign(_keys(f.street_keys.palm),"Palm Boulevard",f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Boulevard & Fremont Street 3")
	check(service.remove(_keys(f.street_keys.palm),f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Fremont Street 2")
	check(service.remove(_keys(f.street_keys.fremont),f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Subway 10,8")
	check(f.city.street_naming.station_auto.is_empty())
func test_surface_obstacles_grade_bore_and_temporary_flood() -> void:
	var resolver = _resolver()
	if resolver==null: return
	for obstruction: String in ["water","highway","grade","bore","building"]:
		var city := flat_city()
		var anchor := Vector2i(10,10)
		Fixtures.station(city,anchor,false)
		Fixtures.road(city,Vector2i(9,13),Vector2i(14,13))
		# Synthetic barrier layers deliberately model the inaccessible surface;
		# ordinary roads and physical station still use declared paid Builder.
		for x: int in range(8,14):
			match obstruction:
				"water": city.terrain.put(x,12,Terrain.SURFACE); city.set_heights(x,12,4,6)
				"highway": city.building.put(x,12,NetworkShapes.HIGHWAY_EW)
				"grade": city.set_heights(x,12,12,0)
				"building": city.building.put(x,12,Buildings.POLICE_STATION)
		if obstruction=="bore":
			for x: int in range(9,15): city.building.put(x,13,0)
			city.building.put(9,13,Buildings.TUNNEL_FIRST)
			city.building.put(14,13,Buildings.TUNNEL_FIRST+2)
		var t := StreetTopology.new()
		t.rebuild(city)
		var s := Service.new()
		s.set_station_allocator(resolver.reconcile)
		check(s.bind_city(city,t).ok)
		var selected: Array[String] = []
		for segment: Dictionary in t.segments({}): selected.append_array(segment.links)
		if not selected.is_empty(): check(s.assign(selected,"Inaccessible Road",t.revision).ok)
		check_eq(resolver.display_name(city,anchor,false),"Rail 10,10",obstruction+" cannot grant surface access")
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	var before: Dictionary = f.city.street_naming.duplicate(true)
	f.city.flood_overlay[Vector2i(8,8)] = true
	f.city.flood_overlay[Vector2i(9,9)] = true
	check(service.reconcile(Rect2i()).ok)
	check_eq(f.city.street_naming,before,"temporary flooding retains permanent source/suffix")
func test_three_street_approaches_and_canonical_insertion_order() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	# Rail entrance lies northwest: north/west beat the farther east approach.
	var east: Array[String] = _keys(f.street_keys.fremont.slice(2))
	check(service.assign(east,"Third Street",f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.rail,false),"Palm Avenue & Fremont Street")
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Palm Avenue & Third Street")
	var metadata: Dictionary = f.city.street_naming.duplicate(true)
	metadata.station_auto.clear()
	var first: Dictionary = resolver.reconcile(f.city,f.topology,metadata)
	for field: String in ["streets","links"]:
		var reversed: Dictionary = {}
		var keys: Array = metadata[field].keys()
		keys.reverse()
		for key: Variant in keys: reversed[key] = metadata[field][key]
		metadata[field] = reversed
	for field: String in ["_nodes","_links"]:
		var reversed: Dictionary = {}
		var keys: Array = f.topology.get(field).keys()
		keys.reverse()
		for key: Variant in keys: reversed[key] = f.topology.get(field)[key]
		f.topology.set(field,reversed)
	var facilities: Dictionary = {}
	var facility_keys: Array = f.city.facilities.keys()
	facility_keys.reverse()
	for key: Variant in facility_keys: facilities[key] = f.city.facilities[key]
	f.city.facilities = facilities
	var second: Dictionary = resolver.reconcile(f.city,f.topology,metadata)
	check_eq(first.station_auto,second.station_auto,"dictionary insertion cannot affect ordering")
func test_complete_source_suffix_wire_roundtrip_and_native_binding_repair() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	var record: Dictionary = f.city.street_naming.station_auto[f.anchors.subway]
	check_eq(record.source_street_ids,[1,2])
	check_eq(record.suffix,2)
	var wire := SaveFormat.encode_city(f.city)
	check_eq(wire.street_naming.station_auto["10,8"].source_street_ids,["1","2"])
	check_eq(wire.street_naming.station_auto["10,8"].suffix,"2")
	var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(wire)))
	check(decoded.city!=null,decoded.error)
	if decoded.city==null: return
	var loaded: City = decoded.city
	var t := StreetTopology.new()
	t.rebuild(loaded)
	var rebound := Service.new()
	rebound.set_station_allocator(resolver.reconcile)
	check(rebound.bind_city(loaded,t).ok)
	check_eq(loaded.street_naming,f.city.street_naming)
	# Saved allocation is well formed but refers to an old neighborhood source.
	loaded.street_naming.station_auto[f.anchors.subway].source_street_ids = [1]
	loaded.street_naming.station_auto[f.anchors.subway].base_name = "Palm Avenue"
	loaded.street_naming.station_auto[f.anchors.subway].display_name = "Palm Avenue 2"
	check(rebound.bind_city(loaded,t).ok)
	check_eq(resolver.display_name(loaded,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
	check(Builder.new(loaded,CityStats.new()).apply(Tools.Kind.BULLDOZE,f.anchors.rail).ok)
	check(rebound.bind_city(loaded,t).ok)
	check(not loaded.street_naming.station_auto.has(f.anchors.rail))
	check_eq(resolver.display_name(loaded,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
func test_numeric_literal_unicode_custom_and_name_refresh_without_metadata_change() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	check(service.remove(_keys(f.street_keys.fremont),f.topology.revision).ok)
	check(service.assign(_keys(f.street_keys.palm),"Álamo 2",f.topology.revision).ok)
	check_eq(resolver.display_name(f.city,f.anchors.rail,false),"Álamo 2")
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Álamo 2 2")
	Fixtures.station(f.city,f.anchors.second_rail,false)
	f.city.facilities[f.anchors.second_rail]["name"] = " ÁLAMO\u00a0 2  2 "
	check(service.refresh_station_names([f.anchors.second_rail]).ok)
	check_eq(resolver.display_name(f.city,f.anchors.subway,true),"Álamo 2 3")
	var before: Dictionary = f.city.street_naming.duplicate(true)
	var revision := service.revision
	f.city.facilities[f.anchors.second_rail]["name"] = "Another custom title"
	var notified := service.refresh_station_names([f.anchors.second_rail])
	check(notified.ok and notified.changed)
	check_eq(f.city.street_naming,before,"custom-only change needs notification despite identical auto metadata")
	check_eq(service.revision,revision+1)
	check(notified.affected.station_anchors.has(f.anchors.second_rail))
func test_actual_main_binds_allocator_and_rename_refreshes_manual_ownership() -> void:
	var resolver = _resolver()
	if resolver==null: return
	var f := Fixtures.station_city()
	var service := _named(f,resolver)
	f.city.street_naming.station_auto[f.anchors.subway] = {"source_street_ids":[1],"base_name":"Palm Avenue","suffix":2,"display_name":"Palm Avenue 2"}
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://station-street-names-host.cfg"
	root.add_child(host)
	host.begin_city(f.city,{},53,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	check_eq(resolver.display_name(host.sim.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
	host.construction.prompt_rename(f.anchors.subway)
	check(host.notice_dialog.is_open())
	host.notice_dialog.line_edit.text = "Union Terminal"
	var revision: int = host.street_naming_service.revision
	host.notice_dialog.dismiss(&"submit")
	check_eq(resolver.display_name(host.sim.city,f.anchors.subway,true),"Union Terminal")
	check_gt(host.street_naming_service.revision,revision,"successful actual Rename notifies allocator")
	host.construction.prompt_rename(f.anchors.subway)
	host.notice_dialog.line_edit.text = ""
	host.notice_dialog.dismiss(&"submit")
	check_eq(resolver.display_name(host.sim.city,f.anchors.subway,true),"Palm Avenue & Fremont Street 2")
	host.free()
	await process_frame
func test_real_front_passage_uses_clear_half_and_cannot_walk_through_facade() -> void:
	var resolver = _resolver()
	if resolver==null: return
	for enclosed: bool in [false,true]:
		var city := flat_city()
		var anchor := Vector2i(10,10)
		Fixtures.station(city,anchor,false)
		Fixtures.road(city,Vector2i(9,13),Vector2i(14,13))
		# The two-tile front straddles x=11; one clear side of its central
		# walking passage is sufficient, while enclosing both closes access.
		city.building.put(11,12,Buildings.POLICE_STATION)
		if enclosed: city.building.put(10,12,Buildings.POLICE_STATION)
		var t := StreetTopology.new()
		t.rebuild(city)
		var service := Service.new()
		service.set_station_allocator(resolver.reconcile)
		check(service.bind_city(city,t).ok)
		check(service.assign(_keys([StreetTopology.link_key(Vector2i(10,13),&"open",Vector2i(11,13),&"open")]),"Front Street",t.revision).ok)
		check_eq(resolver.display_name(city,anchor,false),"Rail 10,10" if enclosed else "Front Street")
## Palms, rubble and small parks are open ground in Explore: an entrance
## facing them still reaches the named street beyond. Stations placed after
## naming receive automatic titles through the Main placement transaction.
func test_ground_cover_front_and_main_placement_after_naming() -> void:
	var resolver = _resolver()
	if resolver==null: return
	for cover: int in [Buildings.TREES_1+1,Buildings.TREES_7,Buildings.RUBBLE_1,Buildings.CONTAMINATION,Buildings.SMALL_PARK]:
		var city := flat_city()
		var anchor := Vector2i(10,10)
		Fixtures.station(city,anchor,false)
		Fixtures.road(city,Vector2i(9,13),Vector2i(14,13))
		# Declared ground cover across the entire clear front, as an
		# undeveloped wooded or cleared lot leaves it.
		for x: int in range(8,14): city.building.put(x,12,cover)
		var t := StreetTopology.new()
		t.rebuild(city)
		var s := Service.new()
		s.set_station_allocator(resolver.reconcile)
		check(s.bind_city(city,t).ok)
		check(s.assign(_keys([StreetTopology.link_key(Vector2i(10,13),&"open",Vector2i(11,13),&"open")]),"Grove Road",t.revision).ok)
		check_eq(resolver.display_name(city,anchor,false),"Grove Road","ground cover %d grants surface access" % cover)
	var base := flat_city(100000)
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://station-placement-host.cfg"
	root.add_child(host)
	var stats := CityStats.new()
	stats.inventions[&"subways"] = true
	host.begin_city(base,{},77,stats)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	for item: Array in [[Tools.Kind.ROAD,Vector2i(20,30),Vector2i(40,30)],[Tools.Kind.ROAD,Vector2i(30,20),Vector2i(30,40)]]:
		host.select_tool(item[0])
		check(bool(host.handle_drag(item[1],item[2]).get("applied",false)),"paid road")
	var service: StreetNamingService = host.street_naming_service
	var palm: Array[String] = []
	var fremont: Array[String] = []
	for x: int in range(20,40): palm.append(StreetTopology.link_key(Vector2i(x,30),&"open",Vector2i(x+1,30),&"open"))
	for y: int in range(20,40): fremont.append(StreetTopology.link_key(Vector2i(30,y),&"open",Vector2i(30,y+1),&"open"))
	check(service.assign(palm,"Palm Avenue",host.street_topology.revision).ok)
	check(service.assign(fremont,"Fremont Street",host.street_topology.revision).ok)
	# Like Adaven's subway: the entrance faces a palm lot, with the named
	# streets touching the station's other sides.
	host.sim.city.building.put(31,30+2,Buildings.TREES_1+1)
	host.sim.city.building.put(31,28,Buildings.TREES_1+1)
	host.select_tool(Tools.Kind.SUBWAY_STATION)
	check(bool(host.handle_drag(Vector2i(31,31),Vector2i(31,31)).get("applied",false)),"paid subway station")
	host.select_tool(Tools.Kind.RAIL_STATION)
	check(bool(host.handle_drag(Vector2i(28,28),Vector2i(28,28)).get("applied",false)),"paid rail station")
	var subway := host.sim.city.anchor_of(31,31)
	var rail := host.sim.city.anchor_of(28,28)
	check_eq(resolver.name_mode(host.sim.city,subway),&"automatic")
	var subway_title: String = resolver.display_name(host.sim.city,subway,true)
	var rail_title: String = resolver.display_name(host.sim.city,rail,false)
	check(subway_title.begins_with("Palm Avenue & Fremont Street"),"placed subway named from streets: "+subway_title)
	check(rail_title.begins_with("Palm Avenue & Fremont Street"),"placed rail named from streets: "+rail_title)
	check(subway_title!=rail_title,"shared rail/subway uniqueness")
	for i: int in 3: await process_frame
	var signs: Dictionary = {}
	for model: Node in host.city_view_3d.buildings.get_children():
		var sign := model.get_node_or_null("StationEntranceName")
		if sign!=null: signs[model.get_meta("cell")] = sign.get_meta("station_entry_name")
	check_eq(signs.get(subway,""),subway_title,"mounted subway entrance shows automatic title")
	check_eq(signs.get(rail,""),rail_title,"mounted rail entrance shows automatic title")
	# Renaming the street later updates both automatic titles.
	check(service.assign(palm,"Desert Rose Avenue",host.street_topology.revision).ok)
	check(resolver.display_name(host.sim.city,subway,true).begins_with("Desert Rose Avenue & Fremont Street"))
	check(resolver.display_name(host.sim.city,rail,false).begins_with("Desert Rose Avenue & Fremont Street"))
	host.free()
	await process_frame
