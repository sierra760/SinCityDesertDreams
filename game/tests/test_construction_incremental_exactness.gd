# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Construction edits refresh the traffic graph and the street topology
## incrementally; after every edit both equal a fresh complete projection of
## the same city byte for byte (contents and order), and selection tokens
## advance exactly when a fresh projection's structure changes.
extends "res://tests/test_case.gd"

const Edits := preload("res://tests/construction/edit_sequence.gd")
const DOMAINS: Array[StringName] = [&"road", &"highway", &"rail", &"water"]

## Forget every published projection so a reference is computed from scratch.
static func _forget_published() -> void:
	CityTrafficGraph._completed_state = {}
	CityTrafficGraph._completed_owner = null
	CityTrafficGraph._completed_inputs = []

static func _fresh_graph(city: City) -> CityTrafficGraph:
	_forget_published()
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	_forget_published()
	return graph

static func _fresh_topology(city: City) -> StreetTopology:
	_forget_published()
	var topology := StreetTopology.new()
	topology.rebuild(city)
	_forget_published()
	return topology

static func _graph_bytes(graph: CityTrafficGraph) -> PackedByteArray:
	return var_to_bytes([graph._nodes, graph._lists, graph._demand, graph.facilities, graph.developed, graph._axis_cells,
		graph._decks, graph._approaches, graph.highways.routes, graph.highways.shape_cells])

static func _explain(topology: StreetTopology, fresh: StreetTopology) -> void:
	for field: String in ["_nodes", "_links", "_exits", "_bores", "_link_ranks", "_ramp_keys"]:
		var a: Variant = topology.get(field)
		var b: Variant = fresh.get(field)
		if var_to_bytes(a) != var_to_bytes(b):
			print("  differs: ", field, " equal-as-values=", a == b)
			if a is Dictionary and a != b:
				for key: Variant in b:
					if not a.has(key): print("    missing ", key, " ", b[key])
					elif a[key] != b[key]: print("    value ", key, "\n      got ", a[key], "\n      want ", b[key])
				for key: Variant in a:
					if not b.has(key): print("    extra ", key, " ", a[key])

static func _topology_bytes(topology: StreetTopology) -> PackedByteArray:
	return var_to_bytes([topology._nodes, topology._links, topology._exits, topology._bores, topology._ramp_keys])

## Point caches filled before an edit must not survive where points change.
static func _prime_centers(graph: CityTrafficGraph) -> void:
	for domain: StringName in [&"road", &"highway", &"rail"]:
		for cell: Vector2i in graph.cells(domain): graph.center(cell, domain)

static func _centers_match(graph: CityTrafficGraph, fresh: CityTrafficGraph) -> bool:
	for domain: StringName in [&"road", &"highway", &"rail"]:
		for cell: Vector2i in fresh.cells(domain):
			if graph.center(cell, domain) != fresh.point(cell, domain): return false
	return true

func test_construction_edits_match_fresh_projection() -> void:
	var cities := {"La Presa": 45, "Foothills Ranch": 45, "Oro Canyon": 30, "Valle del Mar": 30, "Salton Shores": 30}
	for name: String in cities: _edit_city(name, int(cities[name]))
	_growth_then_construction("Foothills Ranch")
	_lazy_adoption("La Presa")
	_adopted_source("Foothills Ranch")
	_floods("La Presa")
	_naming("La Presa")

func _edit_city(name: String, steps: int) -> void:
	var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
	if not loaded.ok:
		check(false, "import " + name)
		return
	var city: City = loaded.city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	_prime_centers(graph)
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var structure := topology._structure_keys()
	var revision := topology.revision
	var applied := 0
	var incremental_topology := 0
	var incremental_graph := 0
	var structural_changes := 0
	var kinds: Dictionary = {}
	var step := -1
	while applied < steps and step < steps * 6:
		step += 1
		var kind := Edits.apply(city, builder, rng)
		if kind.is_empty(): continue
		applied += 1
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var graph_revision := topology._graph.revision
		var changed := topology.rebuild(city)
		var refreshed := topology._graph.revision != graph_revision
		graph.refresh()
		if topology._graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL: incremental_topology += 1
		if graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL: incremental_graph += 1
		var fresh_topology := _fresh_topology(city)
		var fresh := _fresh_graph(city)
		var label := "%s step %d (%s)" % [name, step, kind]
		var reference := _graph_bytes(fresh)
		check(_topology_bytes(topology) == _topology_bytes(fresh_topology), label + ": topology equals a fresh projection")
		check(topology._link_ranks == fresh_topology._link_ranks, label + ": link creation ranks equal a fresh projection")
		if _topology_bytes(topology) != _topology_bytes(fresh_topology): _explain(topology, fresh_topology)
		# Between network edits the topology does not refresh its graph (lots,
		# ground cover, power lines and congestion do not shape streets); when
		# it does refresh, its whole graph equals a fresh projection.
		if refreshed: check(_graph_bytes(topology._graph) == reference, label + ": refreshed topology graph equals a fresh projection")
		check(_graph_bytes(graph) == reference, label + ": second graph equals a fresh projection")
		check(_centers_match(graph, fresh), label + ": cached centers equal fresh points")
		var keys := fresh_topology._structure_keys()
		check(changed == (keys != structure), label + ": rebuild reports a change exactly when the fresh structure changed")
		check((topology.revision != revision) == changed, label + ": the selection token advances only with a change")
		check(topology.segments({}) == fresh_topology.segments({}) and topology.junctions({}) == fresh_topology.junctions({}), label + ": derived segments and junctions agree")
		if changed: structural_changes += 1
		structure = keys
		revision = topology.revision
	print(name, ": ", applied, " edits ", kinds, "; incremental topology graph ", incremental_topology, ", second graph ", incremental_graph, ", structural changes ", structural_changes)
	check(applied == steps, name + ": every planned edit applied")
	check(incremental_graph >= applied / 3, name + ": the incremental path carried the edits")
	check(structural_changes > 0, name + ": some edits changed the street structure")

## Long growth leaves the topology's graph many lot changes behind; the next
## road edit still refreshes it incrementally and exactly.
func _growth_then_construction(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var kinds := CityTrafficGraph.network_kinds()
	var grown := 0
	for attempt: int in 20000:
		if grown >= 1500: break
		var x := rng.randi_range(0, City.WIDTH - 1)
		var y := rng.randi_range(0, City.HEIGHT - 1)
		if kinds[city.building.at(x, y)] != 0 or city.is_water(x, y): continue
		city.building.put(x, y, Buildings.RES_1X1_FIRST + rng.randi_range(0, 60) if grown % 3 != 0 else Buildings.NONE)
		grown += 1
	check(not topology.rebuild(city), name + ": growth alone leaves the topology unchanged")
	var builder := Builder.new(city, CityStats.new())
	var applied := 0
	for step: int in 40:
		if applied >= 3: break
		if Edits.apply(city, builder, rng) in ["road", "rail", "bulldoze"]:
			applied += 1
			topology.rebuild(city)
			check(topology._graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL, name + " growth edit %d: incremental" % applied)
			check(_topology_bytes(topology) == _topology_bytes(_fresh_topology(city)), name + " growth edit %d: topology equals a fresh projection" % applied)
			check(_graph_bytes(topology._graph) == _graph_bytes(_fresh_graph(city)), name + " growth edit %d: graph equals a fresh projection" % applied)
	check(applied == 3, name + ": construction after growth applied")

## A new owner adopts an incrementally refreshed graph's live projection.
func _lazy_adoption(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var done := 0
	while done < 4:
		if Edits.apply(city, builder, rng) in ["road", "rail", "bulldoze"]: done += 1
	graph.refresh()
	check(graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL, name + ": construction refreshes incrementally")
	var before := CityTrafficGraph.completed_adoptions
	var adopter := CityTrafficGraph.new()
	adopter.bind_city(city)
	check(CityTrafficGraph.completed_adoptions == before + 1, name + ": a new owner adopts the live incremental projection")
	var fresh := _fresh_graph(city)
	check(_graph_bytes(adopter) == _graph_bytes(fresh), name + ": the adopted projection equals a fresh one")
	var road_cell: Vector2i = adopter._nodes[&"road"].keys()[0]
	adopter._nodes[&"road"][road_cell]["mask"] = 255
	check(int(graph._nodes[&"road"][road_cell]["mask"]) != 255, name + ": adoption detaches the copy")
	# A stale owner (changed since) is never adopted.
	city.traffic.put(3, 3, city.traffic.at(3, 3) ^ 0x55)
	_forget_published()
	graph._publish_owner(graph._state_inputs)
	var stale := CityTrafficGraph.new()
	before = CityTrafficGraph.completed_adoptions
	stale.bind_city(city)
	check(CityTrafficGraph.completed_adoptions == before, name + ": an owner whose inputs differ is not adopted")
	check(_graph_bytes(stale) == _graph_bytes(_fresh_graph(city)), name + ": the fallback projection is exact")

## Topology adopted from a validation projection keeps that source intact.
func _adopted_source(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var source := StreetTopology.new()
	source.rebuild(city)
	var source_bytes := _topology_bytes(source)
	var source_graph := _graph_bytes(source._graph)
	var topology := StreetTopology.new()
	check(topology.adopt(source, city), name + ": adoption reports the new binding")
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for step: int in 12:
		if Edits.apply(city, builder, rng).is_empty(): continue
		topology.rebuild(city)
		check(_topology_bytes(topology) == _topology_bytes(_fresh_topology(city)), "%s adopted step %d: topology equals a fresh projection" % [name, step])
		check(_graph_bytes(topology._graph) == _graph_bytes(_fresh_graph(city)), "%s adopted step %d: graph equals a fresh projection" % [name, step])
	check(_topology_bytes(source) == source_bytes and _graph_bytes(source._graph) == source_graph, name + ": the adopted source is unchanged")

## Floods use the detached structural copy; returning to dry ground is exact.
func _floods(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var roads := topology._nodes.values()
	for step: int in 8:
		if step == 2: city.flood_overlay[Vector2i(roads[10].cell)] = 1
		if step == 5: city.flood_overlay.clear()
		Edits.apply(city, builder, rng)
		topology.rebuild(city)
		check(_topology_bytes(topology) == _topology_bytes(_fresh_topology(city)), "%s flood step %d: topology equals a fresh projection" % [name, step])

## Named streets reconcile after construction exactly as a fresh binding does.
func _naming(name: String) -> void:
	var city: City = Sc2Import.load("res://assets/cities/%s.sc2" % name).city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var service := StreetNamingService.new()
	service.set_station_allocator(StationNameResolver.reconcile)
	check(service.bind_city(city, topology).ok, name + ": naming binds")
	var segments := topology.segments(city.street_naming.links)
	var named := 0
	for i: int in range(0, segments.size(), 3):
		var keys: Array[String] = []
		keys.assign(segments[i].links)
		if service.assign(keys, "Street %d" % i, topology.revision).ok: named += 1
	check(named > 10, name + ": many streets named")
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for step: int in 20:
		var kind := Edits.apply(city, builder, rng)
		if kind.is_empty(): continue
		var copy := city.duplicate_city()
		var result := service.reconcile(Rect2i())
		_forget_published()
		var reference := StreetTopology.new()
		reference.rebuild(copy)
		var fresh_service := StreetNamingService.new()
		fresh_service.set_station_allocator(StationNameResolver.reconcile)
		var bound := fresh_service.bind_city(copy, reference)
		_forget_published()
		check(result.ok and bound.ok and city.street_naming == copy.street_naming and var_to_bytes(city.street_naming) == var_to_bytes(copy.street_naming),
			"%s naming step %d (%s): reconciled metadata equals a fresh binding" % [name, step, kind])
