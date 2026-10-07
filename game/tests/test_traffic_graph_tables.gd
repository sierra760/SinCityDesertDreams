# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The table-driven traffic graph rebuild gives exactly the per-cell
## predicates, window counts and bridge profiles of the direct computation;
## it only avoids repeating them.
extends "res://tests/test_case.gd"

var _city: City

func before_all() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	check(loaded.ok, "fixture city imports")
	_city = loaded.city

func test_code_kinds_match_network_predicates() -> void:
	var kinds := CityTrafficGraph.network_kinds()
	check_eq(kinds.size(), Buildings.COUNT, "one classification per roster code")
	for code: int in Buildings.COUNT:
		var kind: int = kinds[code]
		check_eq(bool(kind & CityTrafficGraph.KIND_ONRAMP), NetworkShapes.is_onramp(code), "onramp bit for code %d" % code)
		check_eq(bool(kind & CityTrafficGraph.KIND_AXIS), NetworkShapes.is_onramp(code) or CityNetworks3D.bridge_family(code) != NetworkShapes.Family.NONE, "axis bit for code %d" % code)
		check_eq(bool(kind & CityTrafficGraph.KIND_TUNNEL_PORTAL), NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code), "tunnel/portal bit for code %d" % code)
		check_eq(bool(kind & CityTrafficGraph.KIND_ROAD), NetworkShapes.in_family(code, NetworkShapes.Family.ROAD), "road bit for code %d" % code)
		check_eq(bool(kind & CityTrafficGraph.KIND_HIGHWAY), NetworkShapes.in_family(code, NetworkShapes.Family.HIGHWAY), "highway bit for code %d" % code)
		check_eq(bool(kind & CityTrafficGraph.KIND_RAIL), NetworkShapes.in_family(code, NetworkShapes.Family.RAIL), "rail bit for code %d" % code)

func test_summed_area_demand_equals_window_scan() -> void:
	var graph := CityTrafficGraph.new()
	graph.bind_city(_city)
	var tables := graph._demand_tables()
	check_eq(tables.size(), 4, "four category tables")
	var compared := 0
	for cell: Vector2i in graph._demand:
		compared += 1
		check(graph._local_demand(cell, tables) == graph._local_demand(cell), "table demand equals the 7x7 scan at %s" % cell)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(127, 127), Vector2i(0, 127), Vector2i(127, 0), Vector2i(3, 124)]:
		check(graph._local_demand(cell, tables) == graph._local_demand(cell), "edge window at %s" % cell)
	check_gt(compared, 1000, "fixture has many demand cells")
	check(graph._demand.values()[0].keys() == ["cars", "people", "industrial", "commercial", "congestion", "activity"], "demand records keep their key order")

func test_shared_bridge_profiles_equal_fresh_collection() -> void:
	var shared := CityNetworks3D.shared_bridge_profiles(_city)
	var fresh := CityNetworks3D.new()
	var decks: Dictionary = {}
	var sampling := CityGeometry3D.begin_ground_sampling(_city)
	CityNetworks3D._collect_bridge_decks(_city, decks)
	decks.merge(preload("res://scripts/view/city_highway_bridges_3d.gd").profiles(_city))
	var approaches := CityNetworks3D.BridgeApproaches.profiles(_city, decks)
	approaches.merge(CityNetworks3D.HighwayGrades.profiles(_city, decks), true)
	CityGeometry3D.end_ground_sampling(sampling)
	check(var_to_bytes(shared[0]) == var_to_bytes(decks), "shared decks equal a fresh collection, in order")
	check(var_to_bytes(shared[1]) == var_to_bytes(approaches), "shared approaches equal a fresh collection, in order")
	check(not decks.is_empty(), "fixture has bridge decks")
	# Prepared owners receive detached copies of the same profiles.
	fresh._prepare_bridge_decks(_city)
	check(var_to_bytes(fresh._deck_profiles) == var_to_bytes(decks), "prepared renderer decks equal the shared profiles")
	check(var_to_bytes(fresh._approach_profiles) == var_to_bytes(approaches), "prepared renderer approaches equal the shared profiles")
	fresh._deck_profiles.clear()
	check(not CityNetworks3D.shared_bridge_profiles(_city)[0].is_empty(), "owners cannot clear the shared table through their copy")
	fresh.free()

func test_graph_rebuild_ends_its_sampling_scope() -> void:
	var graph := CityTrafficGraph.new()
	graph.bind_city(_city)
	check(CityGeometry3D._ground_sampling_city == null, "no sampling scope survives a graph rebuild")
	var outer := CityGeometry3D.begin_ground_sampling(_city)
	var other := CityTrafficGraph.new()
	other.bind_city(_city)
	check(CityGeometry3D._ground_sampling_city == _city, "a surrounding scope is left in place")
	CityGeometry3D.end_ground_sampling(outer)
	check(var_to_bytes([graph._nodes, graph._lists, graph._demand]) == var_to_bytes([other._nodes, other._lists, other._demand]), "scoped and unscoped rebuilds agree")

func test_second_owner_adopts_the_completed_graph_exactly() -> void:
	var first := CityTrafficGraph.new()
	first.bind_city(_city)
	var before := CityTrafficGraph.completed_adoptions
	var second := CityTrafficGraph.new()
	second.bind_city(_city)
	check_eq(CityTrafficGraph.completed_adoptions, before + 1, "equal raw inputs adopt the completed projection")
	var fields := func(graph: CityTrafficGraph) -> PackedByteArray:
		return var_to_bytes([graph._nodes, graph._lists, graph._demand, graph.facilities, graph.developed, graph._axis_cells, graph._decks, graph._approaches, graph.highways.routes, graph.highways.shape_cells, graph._axis_signature])
	check(fields.call(first) == fields.call(second), "adopted graph equals the computed graph in every field")
	check(first._nodes[&"road"] != second._nodes[&"road"] or first._nodes[&"road"].is_empty() or not first._nodes[&"road"].values()[0] == null, "fixture has road nodes")
	var road_cell: Vector2i = first._nodes[&"road"].keys()[0]
	second._nodes[&"road"][road_cell]["mask"] = 255
	check_ne(first._nodes[&"road"][road_cell]["mask"], 255, "adopted state is a detached copy")
	check(first.point(road_cell, &"road") == second.point(road_cell, &"road"), "sampling after adoption agrees")
	var edited := _city.duplicate_city()
	edited.traffic.put(5, 5, edited.traffic.at(5, 5) ^ 0x7F)
	var third := CityTrafficGraph.new()
	third.bind_city(edited)
	check_eq(CityTrafficGraph.completed_adoptions, before + 1, "changed raw bytes rebuild instead of adopting")
