# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Topology := preload("res://scripts/core/naming/street_topology.gd")
const Fixtures := preload("res://tests/fixtures/street_names_fixtures.gd")
const Bore := preload("res://tests/exploration/road_tunnel_fixture.gd")
const Banks := preload("res://tests/test_bridge_approaches.gd")

func test_bends_follow_one_segment_and_junction_arms_stay_separate() -> void:
	var city := flat_city()
	Fixtures.road(city,Vector2i(8,8),Vector2i(11,8))
	Fixtures.road(city,Vector2i(11,8),Vector2i(11,11))
	var t: StreetTopology = Fixtures.from_city(city).topology
	check_eq(t.segments({}).size(),1,"bend stays one six-link segment")
	if not t.segments({}).is_empty(): check_eq(t.segments({})[0].links.size(),6)
	for segment: Dictionary in t.segments({"10,8,open>11,8,open":1}):
		check_lt(segment.endpoints[0].position.distance_to(segment.points[0]),.00001,"bend boundary endpoint matches projected start")
		check_lt(segment.endpoints[1].position.distance_to(segment.points[-1]),.00001,"bend boundary endpoint matches projected end")
	var f := Fixtures.junction()
	check_eq(f.topology.segments({}).size(),4,"four independent arms")
	check_eq(f.topology.junctions({}).size(),1)
	if not f.topology.junctions({}).is_empty():
		check_eq(f.topology.junctions({})[0].approaches.size(),4)
		for approach: Dictionary in f.topology.junctions({})[0].approaches:
			check_eq(approach.links.size(),2)
			check(approach.points.size()>=3,"approach includes real projection")
	f.city.building.put(8,10,0)
	f.city.building.put(8,9,0)
	f.topology.rebuild(f.city)
	check_eq(f.topology.segments({}).size(),3,"T stops at junction")

func test_canonical_keys_use_numeric_y_x_and_channels() -> void:
	check_eq(Topology.link_key(Vector2i(9,8),&"open",Vector2i(8,8),&"open"),"8,8,open>9,8,open")
	check_eq(Topology.link_key(Vector2i(2,10),&"bore",Vector2i(10,2),&"open"),"10,2,open>2,10,bore")
	check_eq(Topology.link_key(Vector2i(8,8),&"bore",Vector2i(8,8),&"open"),"8,8,open>8,8,bore")

func test_channels_distinguish_bore_from_surface() -> void:
	var city: City = Bore.city()
	# Deliberate independent surface road above existing complete bore.
	for x: int in range(22,25): city.building.put(x,20,30)
	var t: StreetTopology = Fixtures.from_city(city).topology
	check(t.has_link("22,20,bore>23,20,bore"),"complete bore survives surface overlay")
	check(t.has_link("22,20,open>23,20,open"),"independent upper road")
	check(t.has_link("19,20,open>20,20,bore"),"explicit mouth transition")
	check(not t.has_link("22,20,open>23,20,bore"),"no cross-elevation shortcut")
	var lower := t.connection_points("22,20,bore>23,20,bore")
	var upper := t.connection_points("22,20,open>23,20,open")
	if not lower.is_empty() and not upper.is_empty(): check_gt(upper[0].y-lower[0].y,1.0)
	city.set_tunnel_bits(23,20,0)
	t.rebuild(city)
	check(not t.has_link("22,20,bore>23,20,bore"),"incomplete bore excluded")
	check(t.has_link("22,20,open>23,20,open"),"surface unaffected by broken bore")

func test_flood_does_not_delete_structure() -> void:
	var f := Fixtures.straight()
	var t: StreetTopology = f.topology
	var revision := t.revision
	for key: String in f.keys: check(t.has_link(key),"fixture connection exists")
	f.city.flood_overlay[Vector2i(10,8)] = true
	check(not t.rebuild(f.city),"flood does not change structure")
	check_eq(t.revision,revision)
	for key: String in f.keys: check(t.has_link(key),"flood preserves assignment target")

func test_loop_boundaries_dead_end_and_isolated_tile() -> void:
	var city := flat_city()
	Fixtures.road(city,Vector2i(8,8),Vector2i(11,8))
	Fixtures.road(city,Vector2i(11,8),Vector2i(11,11))
	Fixtures.road(city,Vector2i(11,11),Vector2i(8,11))
	Fixtures.road(city,Vector2i(8,11),Vector2i(8,8))
	var t: StreetTopology = Fixtures.from_city(city).topology
	check_eq(t.segments({}).size(),1,"degree two loop is one segment")
	if not t.segments({}).is_empty(): check(t.segments({})[0].closed)
	check_eq(t.segments({"8,8,open>9,8,open":7}).size(),2,"assignment boundary breaks loop")
	city = flat_city()
	# Synthetic imported boundary: Builder reserves the outer map border.
	for x: int in 4: city.building.put(x,0,30)
	Fixtures.road(city,Vector2i(8,8),Vector2i(8,8))
	t.rebuild(city)
	check_eq(t.segments({}).size(),1,"isolated tile cannot become a segment")
	if not t.segments({}).is_empty():
		check_eq(t.segments({})[0].links.size(),3,"boundary to dead end")
		check(not t.segments({})[0].closed)

func test_crossings_and_overpass_keep_only_actual_road_axis() -> void:
	for code: int in [68,70,75]:
		var city := flat_city()
		Fixtures.road(city,Vector2i(8,8),Vector2i(12,8))
		city.building.put(10,8,code) # Declared synthetic crossing/overpass.
		city.building.put(10,7,73 if code==75 else 44)
		city.building.put(10,9,73 if code==75 else 44)
		var t: StreetTopology = Fixtures.from_city(city).topology
		check_eq(t.segments({}).size(),1,"crossing ordinary road stays continuous")
		check(t.has_link("9,8,open>10,8,open"))
		check(not t.has_link("10,7,open>10,8,open"),"other network is not a street")
		check(t.exit_approaches().is_empty(),"overpass proximity is not ramp")

func test_bridge_projection_and_read_only_geometry_revision() -> void:
	var city: City = Banks.bank_city(true,3,87,true)
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var t: StreetTopology = Fixtures.from_city(city).topology
	check(t.has_link("22,22,open>23,22,open"),"bridge stays ordinary open channel")
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var points := t.connection_points("22,22,open>23,22,open")
	check(not points.is_empty())
	if not points.is_empty(): check_lt(points[0].distance_to(graph.point(Vector2i(22,22),&"road")),.00001)
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"topology and projection preserve complete native city")
	var f := Fixtures.straight()
	var old: PackedVector3Array = f.topology.connection_points(f.keys[0])
	var rev: int = f.topology.revision
	for y: int in range(5,12):
		for x: int in range(5,16): f.city.set_heights(x,y,5,0)
	check(not f.topology.rebuild(f.city),"same-city projection changes preserve structural revision")
	check_eq(f.topology.revision,rev)
	check_ne(f.topology.connection_points(f.keys[0]),old,"geometry still refreshes")

func test_assignment_boundaries_and_defensive_records() -> void:
	var f := Fixtures.straight()
	check_eq(f.topology.segments({f.keys[0]:1}).size(),2,"different memberships split selection")
	var segments: Array[Dictionary] = f.topology.segments({})
	if not segments.is_empty(): segments[0].links.clear()
	check_eq(f.topology.segments({}).size(),1,"caller cannot mutate topology")
	check(f.topology.connection_points("missing").is_empty())
	f.city.building.put(10,8,0)
	check(f.topology.rebuild(f.city),"demolition changes structural revision")
	check(not f.topology.has_link(f.keys[1]))

func test_exit_connector_stops_at_first_junction_and_eight_links() -> void:
	for length: int in [3,8,9]:
		var f := Fixtures.exit_city(length)
		var junctions: Array[Dictionary] = f.topology.junctions({})
		check_eq(junctions.size(),1,"fixture has actual ordinary-road T")
		if not junctions.is_empty(): check_eq(junctions[0].approaches.size(),3,"all three paid road arms exist")
		var exits: Array[Dictionary] = f.topology.exit_approaches()
		check_eq(exits.size(),1,"one departure approach, not paired-cell duplicates")
		if exits.is_empty(): continue
		check_eq(f.topology.exit_destination(exits[0],{f.named:9}),[9] if length<=8 else [],"bounded unnamed connector")
		check_eq(exits[0].direction,Vector2i.DOWN,"actual departure carriageway")
		check(exits[0].upstream_points.size()>=3,"two actual highway connections upstream")
		var first := Topology.link_key(f.road,&"open",f.road+Vector2i.UP,&"open")
		check_eq(f.topology.exit_destination(exits[0],{first:4,f.named:9}),[4],"named connector wins")
		var beyond := Topology.link_key(f.junction+Vector2i.LEFT,&"open",f.junction+Vector2i.LEFT*2,&"open")
		check_eq(f.topology.exit_destination(exits[0],{beyond:5}),[],"do not search beyond first unnamed junction")

func test_exit_intersection_names_and_incoming_only_or_disconnected_ramp() -> void:
	var f := Fixtures.exit_city()
	var exits: Array[Dictionary] = f.topology.exit_approaches()
	check_eq(exits.size(),1)
	if not exits.is_empty():
		var east := Topology.link_key(f.junction,&"open",f.junction+Vector2i.RIGHT,&"open")
		check_eq(f.topology.exit_destination(exits[0],{f.named:9,east:3}),[3,9],"canonical directional order east then west")
		check_eq(f.topology.exit_destination(exits[0],{f.named:9,east:9}),[9],"deduplicate one named identity")
	var incoming := Fixtures.exit_city(3,true)
	check(incoming.topology.exit_approaches().is_empty(),"no incoming highway predecessor means entrance-only")
	f.city.building.put(19,19,0)
	f.topology.rebuild(f.city)
	check(f.topology.exit_approaches().is_empty(),"disconnected road mouth cannot make exit")

func test_ramp_boundaries_and_exit_changes_invalidate_revision_without_pruning_links() -> void:
	var city := flat_city()
	Fixtures.road(city,Vector2i(19,17),Vector2i(19,23))
	var t: StreetTopology = Fixtures.from_city(city).topology
	var links: Array = t.segments({})[0].links.duplicate()
	var revision := t.revision
	# Synthetic side ramp; no highway yet. Its paid road approach is a new
	# terminal boundary even though the six ordinary connections all survive.
	city.building.put(20,20,94)
	city.building.put(19,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,7))
	check(t.rebuild(city),"ramp-terminal change invalidates stale selection")
	check_gt(t.revision,revision)
	check_eq(t.segments({}).size(),2,"ramp splits a through-road selection")
	for link: String in links: check(t.has_link(link),"ramp retains named memberships")
	var f := Fixtures.exit_city(3,true)
	var original: Array = []
	for segment: Dictionary in f.topology.segments({}): original.append_array(segment.links)
	revision = f.topology.revision
	for y: int in [18,19]:
		for x: int in [20,21]: f.city.building.put(x,y,NetworkShapes.HIGHWAY_NS)
	check(f.topology.rebuild(f.city),"new usable departure invalidates derived exit topology")
	check_gt(f.topology.revision,revision)
	check_eq(f.topology.exit_approaches().size(),1)
	for link: String in original: check(f.topology.has_link(link),"highway approach leaves street membership intact")


func test_city_binding_identity_survives_detached_flood_projection() -> void:
	var f := Fixtures.straight()
	var t: StreetTopology = f.topology
	var other: City = f.city.duplicate_city()
	check(t.is_bound_to(f.city),"adapter exposes source City identity")
	check(not t.is_bound_to(other),"equal city bytes do not establish identity")
	check(not t.is_bound_to(null),"null is never an active City binding")
	var token := t.revision
	f.city.flood_overlay[Vector2i(10,8)] = true
	check(not t.rebuild(f.city),"detached flood projection retains source binding")
	check(t.is_bound_to(f.city),"binding follows source City, not detached projection")
	check_eq(t.revision,token,"temporary flood keeps same-city token")
	check(t.rebuild(null),"clearing an active binding invalidates its token")
	check(not t.is_bound_to(f.city),"cleared binding rejects previous City")
	check(not t.is_bound_to(null))
	token = t.revision
	check(not t.rebuild(null),"clearing an already unbound adapter is stable")
	check_eq(t.revision,token)

func test_identical_city_rebinding_invalidates_token_without_changing_connections() -> void:
	var f := Fixtures.straight()
	var t: StreetTopology = f.topology
	var other: City = f.city.duplicate_city()
	var token := t.revision
	var segments_before := t.segments({})
	check(t.rebuild(other),"different City binding is a structural selection change")
	check_gt(t.revision,token,"identical roads in another City reject old selections")
	check(t.is_bound_to(other))
	check(not t.is_bound_to(f.city))
	check_eq(t.segments({}),segments_before,"rebinding preserves exact memberships and projection")
	token = t.revision
	check(not t.rebuild(other),"same object and structure retain token")
	check_eq(t.revision,token)
	check(t.rebuild(f.city),"returning to a former City gets a fresh token")
	check_gt(t.revision,token)
	for key: String in f.keys: check(t.has_link(key))

func test_revision_tokens_are_monotonic_across_adapters_and_empty_city_bindings() -> void:
	var f := Fixtures.straight()
	var first: StreetTopology = f.topology
	var old_first := first.revision
	var second := Topology.new()
	check(second.rebuild(f.city))
	check_gt(second.revision,old_first,"new adapter on identical City cannot reuse selection token")
	check_eq(second.segments({}),first.segments({}))
	var second_token := second.revision
	f.city.building.put(10,8,0)
	check(first.rebuild(f.city))
	check_gt(first.revision,second_token,"older adapter changes allocate from global sequence")
	var changed_token := first.revision
	check(second.rebuild(f.city))
	check_gt(second.revision,changed_token,"matching updated topology remains adapter-specific")
	var empty_a := flat_city()
	var empty_b := flat_city()
	var empty := Topology.new()
	check(empty.rebuild(empty_a),"first binding changes identity even without connections")
	check_gt(empty.revision,second.revision)
	var empty_token := empty.revision
	check(empty.rebuild(empty_b),"empty City identities cannot share stale selections")
	check_gt(empty.revision,empty_token)
	check(empty.segments({}).is_empty())
