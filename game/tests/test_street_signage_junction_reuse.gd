# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Signage reuses its junction list only while the topology projection, graph,
## revision and link assignments are unchanged. After every edit (palms,
## rubble, road placement/removal, terrain, naming assignments) the list the
## signage uses must equal a fresh StreetTopology.junctions() byte for byte.
extends "res://tests/test_case.gd"


func _compare(signage: StreetSignage3D, topology: StreetTopology, links: Dictionary, label: String) -> void:
	var used := signage._junctions(links)
	var fresh := topology.junctions(links)
	check(var_to_bytes(used) == var_to_bytes(fresh), label + " junction list equals a fresh computation")


func test_real_city_junction_reuse() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	check(loaded.ok, "La Presa imports")
	var city: City = loaded.city
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var signage := StreetSignage3D.new()
	signage._topology = topology
	var links: Dictionary = {}
	_compare(signage, topology, links, "initial")
	var first_list := signage._junction_list
	_compare(signage, topology, links, "repeat")
	check(is_same(first_list, signage._junction_list), "an unchanged topology reuses the list")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var road := NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH)
	var roads: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if NetworkShapes.is_plain_road(city.building.at(x, y)): roads.append(Vector2i(x, y))
	var keys: Array = topology._links.keys()
	for step: int in 12:
		var cell := Vector2i(rng.randi_range(2, City.WIDTH - 3), rng.randi_range(2, City.HEIGHT - 3))
		match step % 6:
			0: if city.building.atv(cell) == Buildings.NONE: city.building.putv(cell, Buildings.TREES_1)
			1: city.building.putv(roads[rng.randi_range(0, roads.size() - 1)], Buildings.RUBBLE_1)
			2: if city.building.atv(cell) == Buildings.NONE and not city.is_water(cell.x, cell.y): city.building.putv(cell, road)
			3: city.altitude.put(cell.x, cell.y, (city.altitude.at(cell.x, cell.y) & ~City.ALT_MASK) | mini((city.altitude.at(cell.x, cell.y) & City.ALT_MASK) + 1, City.ALT_MASK))
			4: links[keys[rng.randi_range(0, keys.size() - 1)]] = rng.randi_range(1, 9)
			5: links.erase(links.keys()[0] if not links.is_empty() else "")
		topology.rebuild(city)
		_compare(signage, topology, links, "edit %d" % step)
	signage.free()
