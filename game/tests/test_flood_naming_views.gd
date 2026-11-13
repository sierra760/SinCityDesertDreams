# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## While a city is flooded, street and station naming read it without the
## flood. One flood-free view serves a whole reconciliation, the shared bridge
## profiles are not recomputed for it, the street projection keeps refreshing
## incrementally, and every result equals a fresh complete computation.
extends "res://tests/test_case.gd"

const CITY := "res://assets/cities/Harbor Palms.sc2d"


class CountingTopology extends StreetTopology:
	var views := 0
	func flood_free(city: City) -> City:
		views += 1
		return super.flood_free(city)


static func _forget_published() -> void:
	CityTrafficGraph._completed_state = {}
	CityTrafficGraph._completed_owner = null
	CityTrafficGraph._completed_inputs = []


static func _fresh_profiles(city: City) -> PackedByteArray:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	var decks: Dictionary = {}
	var approaches := CityNetworks3D._build_bridge_profiles(city, decks)
	CityGeometry3D.end_ground_sampling(sampling)
	return var_to_bytes([decks, approaches])


static func _shared_profiles(city: City) -> PackedByteArray:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	var shared := CityNetworks3D.shared_bridge_profiles(city)
	CityGeometry3D.end_ground_sampling(sampling)
	return var_to_bytes(shared)


static func _dry(city: City) -> City:
	var copy := city.duplicate_city()
	copy.flood_overlay.clear()
	return copy


## Metadata a fresh binding of the same city commits from the same records.
static func _reference(city: City) -> Dictionary:
	_forget_published()
	var copy := city.duplicate_city()
	var topology := StreetTopology.new()
	topology.rebuild(copy)
	var service := StreetNamingService.new()
	service.set_station_allocator(StationNameResolver.reconcile)
	var bound := service.bind_city(copy, topology)
	_forget_published()
	return {"ok": bound.ok, "metadata": copy.street_naming}


static func _graph_bytes(graph: CityTrafficGraph) -> PackedByteArray:
	return var_to_bytes([graph._nodes, graph._lists, graph._demand, graph.facilities, graph.developed, graph._axis_cells,
		graph._decks, graph._approaches, graph.highways.routes, graph.highways.shape_cells])


static func _topology_bytes(topology: StreetTopology) -> PackedByteArray:
	return var_to_bytes([topology._nodes, topology._links, topology._exits, topology._bores, topology._ramp_keys])


static func _rail_stations(city: City) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for anchor: Vector2i in StationNameResolver._stations(city):
		if city.building.atv(anchor) == Buildings.RAIL_STATION: found.append(anchor)
	return found


## A dry cell beside the station's footprint.
static func _beside(city: City, anchor: Vector2i) -> Vector2i:
	var rect := Rect2i(anchor, Buildings.size(city.building.atv(anchor)))
	var around := rect.grow(2)
	for y: int in range(around.position.y, around.end.y):
		for x: int in range(around.position.x, around.end.x):
			if not rect.has_point(Vector2i(x, y)) and city.in_bounds(x, y) and not city.is_water(x, y): return Vector2i(x, y)
	return Vector2i(-1, -1)


## The first dry cell holding nothing.
static func _empty(city: City) -> Vector2i:
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if city.building.at(x, y) == Buildings.NONE and not city.is_water(x, y): return Vector2i(x, y)
	return Vector2i(-1, -1)


func _bound() -> Dictionary:
	var loaded := SaveFormat.load(CITY)
	check(loaded.get("ok", false), "the city loads")
	var city: City = loaded.city
	var topology := CountingTopology.new()
	topology.rebuild(city)
	var service := StreetNamingService.new()
	service.set_station_allocator(StationNameResolver.reconcile)
	check(service.bind_city(city, topology).ok, "naming binds")
	return {"city": city, "topology": topology, "service": service}


func test_flooded_reconciliation_reads_one_view_without_new_profiles() -> void:
	var bound := _bound()
	var city: City = bound.city
	var topology: CountingTopology = bound.topology
	var service: StreetNamingService = bound.service
	var rail := _rail_stations(city)
	check(rail.size() >= 2, "the city has several rail stations")
	_shared_profiles(city)
	for round: int in 3:
		for anchor: Vector2i in rail:
			var cell := _beside(city, anchor)
			if cell.x >= 0: city.flood_overlay[cell] = 1 + round
		check(not city.flood_overlay.is_empty(), "round %d: ground beside the stations floods" % round)
		var expected := _reference(city)
		var recomputes := CityNetworks3D.shared_profile_recomputes
		topology.views = 0
		var result := service.reconcile(Rect2i())
		check(result.ok and expected.ok, "round %d: the flooded city reconciles" % round)
		check_eq(CityNetworks3D.shared_profile_recomputes - recomputes, 0, "round %d: no bridge profile is recomputed for the flood-free view" % round)
		check(topology.views <= 1, "round %d: the stations share one flood-free view (%d requested)" % [round, topology.views])
		check(var_to_bytes(city.street_naming) == var_to_bytes(expected.metadata), "round %d: reconciled names equal a fresh binding" % round)
		var view := topology.flood_free(city)
		check(view != city and view.flood_overlay.is_empty(), "round %d: the view is a flood-free copy" % round)
		check(view == topology.flood_free(city) and view == topology.traffic_graph().city, "round %d: the view is the copy the projection already holds" % round)
		check(view.building.data == city.building.data and view.terrain.data == city.terrain.data and view.altitude.data == city.altitude.data,
			"round %d: the view holds the city's current layers" % round)
		# The live city's own profiles stay available beside the view's.
		recomputes = CityNetworks3D.shared_profile_recomputes
		for pass_index: int in 3:
			check(_shared_profiles(city) == _fresh_profiles(city), "round %d: live profiles equal a fresh computation" % round)
			var dry := _dry(city)
			check(_shared_profiles(dry) == _fresh_profiles(dry), "round %d: flood-free profiles equal a fresh computation" % round)
		check(CityNetworks3D.shared_profile_recomputes - recomputes <= 1, "round %d: alternating between the city and its view recomputes at most once" % round)
		# An edit while flooded invalidates the held copy.
		var empty := _empty(city)
		check(empty.x >= 0, "round %d: an empty cell exists" % round)
		if empty.x >= 0:
			city.building.putv(empty, Buildings.RUBBLE_1)
			check(topology.flood_free(city) != view, "round %d: an edited city gets a new view" % round)
			check(topology.flood_free(city).building.data == city.building.data, "round %d: the new view holds the edit" % round)


## A flood beside a graded highway is within reach of the live profiles but
## absent from the flood-free ones; both stay cached, and swapping is exact.
func test_profiles_of_city_and_view_alternate_without_recomputing() -> void:
	var city: City = SaveFormat.load(CITY).city
	_shared_profiles(city)
	var graded: Dictionary = CityNetworks3D.shared_bridge_profiles(city)[1]
	check(not graded.is_empty(), "the city has graded highways")
	var flooded := 0
	for at: Vector2i in graded:
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var bank: Vector2i = at + step
			if flooded >= 6 or not city.in_bounds(bank.x, bank.y) or graded.has(bank) or city.is_water(bank.x, bank.y): continue
			city.flood_overlay[bank] = 2
			flooded += 1
	check(flooded > 0, "ground beside the highways floods")
	var dry := _dry(city)
	var live_fresh := _fresh_profiles(city)
	var dry_fresh := _fresh_profiles(dry)
	var recomputes := CityNetworks3D.shared_profile_recomputes
	var live_revision := -1
	var dry_revision := -1
	for round: int in 4:
		check(_shared_profiles(city) == live_fresh, "pass %d: flooded profiles equal a fresh computation" % round)
		if round == 0: live_revision = CityNetworks3D._shared_profile_revision
		check_eq(CityNetworks3D._shared_profile_revision, live_revision, "pass %d: the flooded profiles keep their revision" % round)
		# A new copy each time, as naming takes one per reconciliation.
		check(_shared_profiles(_dry(city)) == dry_fresh, "pass %d: flood-free profiles equal a fresh computation" % round)
		if round == 0: dry_revision = CityNetworks3D._shared_profile_revision
		check_eq(CityNetworks3D._shared_profile_revision, dry_revision, "pass %d: the flood-free profiles keep their revision" % round)
	check(CityNetworks3D.shared_profile_recomputes - recomputes <= 1, "the two sets are computed at most once (%d)" % (CityNetworks3D.shared_profile_recomputes - recomputes))
	if live_fresh != dry_fresh: check(live_revision != dry_revision, "different profiles carry different revisions")


## Road edits while flooded refresh the projection incrementally, exactly.
func test_flooded_street_projection_stays_incremental() -> void:
	var city: City = SaveFormat.load(CITY).city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var roads: Array[Vector2i] = []
	for key: String in topology._nodes:
		var node: Dictionary = topology._nodes[key]
		if node.channel == &"open" and node.links.size() == 2 and city.building.atv(node.cell) < NetworkShapes.HIGHWAY_CORNER_NE: roads.append(node.cell)
	check(roads.size() > 40, "the city has ordinary road cells")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var removed: Dictionary = {}
	var incremental := 0
	for step: int in 16:
		var label := "step %d" % step
		# Floods come and go between edits, on and beside roads.
		if step % 4 != 3:
			for i: int in 3:
				var wet: Vector2i = roads[rng.randi_range(0, roads.size() - 1)] + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				if city.in_bounds(wet.x, wet.y): city.flood_overlay[wet] = 1
		elif step % 8 == 7: city.flood_overlay.clear()
		var flooded := not city.flood_overlay.is_empty()
		check(not topology.rebuild(city), label + ": a flood alone changes no structure")
		var cell: Vector2i = roads[rng.randi_range(0, roads.size() - 1)]
		if removed.has(cell):
			city.building.putv(cell, int(removed[cell]))
			removed.erase(cell)
		else:
			removed[cell] = city.building.atv(cell)
			city.building.putv(cell, Buildings.NONE)
		topology.rebuild(city)
		if topology._graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL and flooded: incremental += 1
		_forget_published()
		var fresh := StreetTopology.new()
		fresh.rebuild(city)
		_forget_published()
		check(_topology_bytes(topology) == _topology_bytes(fresh), label + ": topology equals a fresh projection")
		check(_graph_bytes(topology._graph) == _graph_bytes(fresh._graph), label + ": its graph equals a fresh projection")
		check(topology._graph.city.flood_overlay.is_empty(), label + ": the graph reads a flood-free city")
	check(incremental >= 8, "road edits while flooded refresh incrementally (%d of 16)" % incremental)
