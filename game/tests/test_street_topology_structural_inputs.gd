# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Non-network bytes never change the street topology; network bytes still rebuild it exactly.
extends "res://tests/test_case.gd"
## Complete observable structure and geometry of a topology.
func _state(topology: StreetTopology) -> Array:
	var points: Dictionary = {}
	for key: String in topology._nodes:
		points[key] = [topology.node_point(topology._nodes[key]), topology.node_point(topology._nodes[key], Vector2(0.5, 0.0)), topology.node_point(topology._nodes[key], Vector2(1.0, 0.5))]
	var links: Dictionary = {}
	for key: String in topology._links: links[key] = topology.connection_points(key)
	return [topology._nodes.duplicate(true), topology._links.duplicate(true), topology._exits.duplicate(true), topology._bores.duplicate(true), points, links,
		topology.exit_approaches().duplicate(true), topology._structure_keys()]
func test_only_network_bytes_rebuild_topology() -> void:
	var kinds := CityTrafficGraph.network_kinds()
	for path: String in ["res://assets/cities/La Presa.sc2", "res://assets/cities/Oro Canyon.sc2", "res://assets/cities/Valle del Mar.sc2", "res://assets/cities/Foothills Ranch.sc2"]:
		var loaded := Sc2Import.load(path)
		if not loaded.ok:
			check(false, "import " + path)
			continue
		var city: City = loaded.city
		var name := path.get_file()
		var topology := StreetTopology.new()
		topology.rebuild(city)
		var before := _state(topology)
		var revision := topology.revision
		var rng := RandomNumberGenerator.new()
		rng.seed = 13
		var edits := 0
		var attempts := 0
		while edits < 80 and attempts < 20000:
			attempts += 1
			var x := rng.randi_range(0, City.WIDTH - 1)
			var y := rng.randi_range(0, City.HEIGHT - 1)
			var code := city.building.at(x, y)
			if kinds[code] != 0 or city.is_water(x, y): continue
			match edits % 6:
				0: city.building.put(x, y, Buildings.TREES_1 + rng.randi_range(0, 6))
				1: city.building.put(x, y, Buildings.NONE)
				2: city.building.put(x, y, Buildings.RUBBLE_1 + rng.randi_range(0, 3))
				3: city.building.put(x, y, Buildings.SMALL_PARK)
				4: city.building.put(x, y, Buildings.RES_1X1_FIRST + rng.randi_range(0, 15))
				5:
					city.building.put(x, y, Buildings.POWER_LINE_FIRST)
					city.flags.put(x, y, city.flags.at(x, y) ^ RotationMapper.AXIS_FLAG)
			city.zone.put(x, y, Zones.make(rng.randi_range(0, 6)))
			edits += 1
		check(edits == 80, name + ": 80 non-network edits applied")
		var state_before: Array = topology._projection_state
		check(not topology.rebuild(city) and topology.revision == revision, name + ": non-network edits do not rebuild or revise the topology")
		check(topology._projection_state == state_before, name + ": projected structural inputs are unchanged by non-network edits")
		var fresh := StreetTopology.new()
		fresh.rebuild(city)
		check(_state(fresh) == before and _state(topology) == before, name + ": a fresh topology after non-network edits equals the retained one")
		# A network edit still projects exactly.
		var placed := false
		for sy: int in range(2, City.HEIGHT - 2):
			for sx: int in range(2, City.WIDTH - 6):
				var clear := true
				for dx: int in 5:
					if city.building.at(sx + dx, sy) != Buildings.NONE and not Buildings.is_zone_building(city.building.at(sx + dx, sy)): clear = false
					if city.is_water(sx + dx, sy): clear = false
				if not clear: continue
				for dx: int in 5: city.building.put(sx + dx, sy, Buildings.ROAD_FIRST + 1)
				placed = true
				break
			if placed: break
		check(placed, name + ": a road run was placed")
		var changed := topology.rebuild(city)
		var reference := StreetTopology.new()
		reference.rebuild(city)
		check(_state(topology) == _state(reference), name + ": a network edit rebuilds to the fresh projection")
		check(changed == (reference._structure_keys() != before[7]), name + ": the revision changes exactly when the structure changes")
