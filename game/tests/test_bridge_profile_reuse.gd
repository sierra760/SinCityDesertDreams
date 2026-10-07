# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared bridge/approach/highway-grade profiles reused after an edit must equal
## a fresh whole-city computation byte for byte, and the incrementally masked
## profile inputs must equal the complete masking, over many varied edits on
## real bundled cities: distant and nearby roads, rubble, parks, lots, power
## flags, terrain heights, floods, bridges and highway pieces.
extends "res://tests/test_case.gd"


func after_all() -> void:
	CityNetworks3D.profile_reuse = true


static func _fresh(city: City) -> Array:
	var decks: Dictionary = {}
	var approaches := CityNetworks3D._build_bridge_profiles(city, decks)
	return [decks, approaches]


func _compare(city: City, label: String) -> void:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	var inputs := CityNetworks3D._profile_inputs(city)
	check(var_to_bytes(inputs) == var_to_bytes(CityNetworks3D._profile_inputs_full(city)), label + " incremental profile inputs equal the full masking")
	var shared := CityNetworks3D.shared_bridge_profiles(city)
	var fresh := _fresh(city)
	CityGeometry3D.end_ground_sampling(sampling)
	check(var_to_bytes(shared[0]) == var_to_bytes(fresh[0]), label + " decks equal a fresh computation in order")
	check(var_to_bytes(shared[1]) == var_to_bytes(fresh[1]), label + " approaches and grades equal a fresh computation in order")


func _sequence(name: String, edits: int) -> void:
	var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
	check(loaded.ok, name + " imports")
	if not loaded.ok: return
	var city: City = loaded.city
	_compare(city, name + " initial")
	var reuses := CityNetworks3D.shared_profile_reuses
	var recomputes := CityNetworks3D.shared_profile_recomputes
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var bridges: Array[Vector2i] = []
	var highways: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var code := city.building.at(x, y)
			if CityNetworks3D.bridge_family(code) != NetworkShapes.Family.NONE: bridges.append(Vector2i(x, y))
			elif NetworkShapes.is_highway(code): highways.append(Vector2i(x, y))
	var road := NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH)
	for step: int in edits:
		var kind := step % 10
		var cell := Vector2i(rng.randi_range(0, City.WIDTH - 1), rng.randi_range(0, City.HEIGHT - 1))
		if kind == 3 and not bridges.is_empty():
			cell = bridges[rng.randi_range(0, bridges.size() - 1)] + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
		elif kind == 4 and not highways.is_empty():
			cell = highways[rng.randi_range(0, highways.size() - 1)] + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
		cell = cell.clamp(Vector2i.ZERO, Vector2i(City.WIDTH - 1, City.HEIGHT - 1))
		var label := "%s edit %d kind %d at %s" % [name, step, kind, cell]
		match kind:
			0, 3, 4: city.building.putv(cell, road)
			1: city.building.putv(cell, Buildings.RUBBLE_1 + rng.randi_range(0, 3))
			2: city.building.putv(cell, Buildings.TREES_1)
			5: city.building.putv(cell, Buildings.RES_1X1_FIRST + rng.randi_range(0, 3))
			6: city.flags.putv(cell, city.flags.atv(cell) ^ 0x01)
			7: city.altitude.put(cell.x, cell.y, (city.altitude.at(cell.x, cell.y) & ~City.ALT_MASK) | mini((city.altitude.at(cell.x, cell.y) & City.ALT_MASK) + 1, City.ALT_MASK))
			8:
				if city.flood_overlay.has(cell): city.flood_overlay.erase(cell)
				else: city.flood_overlay[cell] = 1
			9:
				var target: Vector2i = bridges[rng.randi_range(0, bridges.size() - 1)] if not bridges.is_empty() and step % 20 == 9 else (highways[rng.randi_range(0, highways.size() - 1)] if not highways.is_empty() else cell)
				city.building.putv(target, Buildings.NONE)
		_compare(city, label)
	print("    %s reuses=%d recomputes=%d" % [name, CityNetworks3D.shared_profile_reuses - reuses, CityNetworks3D.shared_profile_recomputes - recomputes])
	check(CityNetworks3D.shared_profile_reuses > reuses, name + " reuses the profiles after distant edits")


func test_real_city_edit_sequences() -> void:
	for name: String in ["La Presa", "Foothills Ranch", "Valle del Mar", "Oro Canyon"]:
		_sequence(name, 60)


## The renderer keeps its copies when the shared profiles are reused.
func test_network_layer_keeps_reused_profiles() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	var city: City = loaded.city
	var root := CityNetworks3D.new()
	var regions: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, 16):
		for x: int in range(0, City.WIDTH, 16): regions.append(Rect2i(x, y, 16, 16))
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	root.update_regions(city, regions, 16)
	CityGeometry3D.end_ground_sampling(sampling)
	var decks := root._deck_profiles
	var before := var_to_bytes([root._deck_profiles, root._approach_profiles])
	var far := Vector2i(-1, -1)
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if far.x < 0 and city.building.at(x, y) == Buildings.NONE and not city.is_water(x, y):
				var cell := Vector2i(x, y)
				var near := false
				for deck: Vector2i in root._deck_profiles:
					if absi(deck.x - x) <= 24 and absi(deck.y - y) <= 24: near = true
				if not near: far = cell
	check(far.x >= 0, "a cell far from every bridge exists")
	city.building.putv(far, NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH))
	var revision := CityNetworks3D._shared_profile_revision
	sampling = CityGeometry3D.begin_ground_sampling(city)
	root.update_regions(city, regions, 16)
	var fresh := _fresh(city)
	CityGeometry3D.end_ground_sampling(sampling)
	if root._deck_revision == revision:
		check(root._deck_profiles == decks and var_to_bytes([root._deck_profiles, root._approach_profiles]) == before, "reused profiles keep the renderer's copies")
	check(var_to_bytes(root._deck_profiles) == var_to_bytes(fresh[0]) and var_to_bytes(root._approach_profiles) == var_to_bytes(fresh[1]), "renderer profiles equal a fresh computation")
	root.free()
