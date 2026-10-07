# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ground cover, rubble, parks and utility lines refresh as land use; the graph equals a fresh rebuild.
extends "res://tests/test_case.gd"
const FIELDS: Array[String] = ["_nodes", "_lists", "_demand", "facilities", "developed", "_axis_cells", "_decks", "_approaches"]
func _compare(graph: CityTrafficGraph, city: City, label: String) -> void:
	var fresh := CityTrafficGraph.new()
	fresh.bind_city(city)
	for field: String in FIELDS:
		check(graph.get(field) == fresh.get(field), label + ": " + field + " equals a fresh graph")
	check(graph.highways.routes == fresh.highways.routes, label + ": highway routes equal a fresh graph")
func test_land_use_refreshes_match_fresh_graph() -> void:
	var kinds := CityTrafficGraph.network_kinds()
	for path: String in ["res://assets/cities/La Presa.sc2", "res://assets/cities/Foothills Ranch.sc2"]:
		var loaded := Sc2Import.load(path)
		if not loaded.ok:
			check(false, "import " + path)
			continue
		var city: City = loaded.city
		var name := path.get_file()
		var graph := CityTrafficGraph.new()
		graph.bind_city(city)
		var revision := graph.revision
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		var edits := 0
		var attempts := 0
		while edits < 60 and attempts < 20000:
			attempts += 1
			var x := rng.randi_range(0, City.WIDTH - 1)
			var y := rng.randi_range(0, City.HEIGHT - 1)
			var code := city.building.at(x, y)
			if kinds[code] != 0 or city.is_water(x, y) or code >= Buildings.RES_1X1_FIRST: continue
			match edits % 5:
				0: city.building.put(x, y, Buildings.TREES_1 + rng.randi_range(0, 6))
				1: city.building.put(x, y, Buildings.NONE)
				2: city.building.put(x, y, Buildings.RUBBLE_1 + rng.randi_range(0, 3))
				3: city.building.put(x, y, Buildings.SMALL_PARK)
				4: city.building.put(x, y, Buildings.POWER_LINE_FIRST + rng.randi_range(0, 1))
			edits += 1
		check(edits == 60, name + ": 60 ground-cover edits applied")
		check(graph.refresh(), name + ": the refresh reports a land-use change")
		check(graph.revision == revision, name + ": ground cover keeps the topology revision")
		_compare(graph, city, name + " ground cover")
		# A new lot next to a road is still land use; a new road is structure.
		var lot_done := false
		for sy: int in range(1, City.HEIGHT - 1):
			for sx: int in range(1, City.WIDTH - 1):
				if city.building.at(sx, sy) == Buildings.NONE and not city.is_water(sx, sy):
					city.building.put(sx, sy, Buildings.RES_1X1_FIRST + 3)
					lot_done = true
					break
			if lot_done: break
		check(graph.refresh() and graph.revision == revision, name + ": a new lot is land use")
		_compare(graph, city, name + " new lot")
		var road_done := false
		for sy: int in range(1, City.HEIGHT - 1):
			for sx: int in range(1, City.WIDTH - 1):
				if city.building.at(sx, sy) == Buildings.NONE and not city.is_water(sx, sy):
					city.building.put(sx, sy, Buildings.ROAD_FIRST)
					road_done = true
					break
			if road_done: break
		check(graph.refresh() and graph.revision != revision, name + ": a new road rebuilds the structure")
		_compare(graph, city, name + " new road")
