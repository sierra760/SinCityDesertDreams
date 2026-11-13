# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A change of flooded tiles refreshes the traffic graph and the street lamps
## incrementally. After every change the graph, every sampled point and the
## lamps equal a fresh complete projection of the same flooded city, byte for
## byte and in the same order, on imported per-tile terrain and on native
## shared-vertex terrain, with construction edits in between.
extends "res://tests/test_case.gd"

const Edits := preload("res://tests/construction/edit_sequence.gd")
const DOMAINS: Array[StringName] = [&"road", &"highway", &"rail", &"water"]
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


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


static func _graph_bytes(graph: CityTrafficGraph) -> PackedByteArray:
	return var_to_bytes([graph._nodes, graph._lists, graph._demand, graph.facilities, graph.developed, graph._axis_cells,
		graph._decks, graph._approaches, graph.highways.routes, graph.highways.shape_cells])


## Fill every point cache so a stale entry would show after the next change.
static func _prime(graph: CityTrafficGraph) -> void:
	for domain: StringName in DOMAINS:
		for cell: Vector2i in graph._nodes[domain]: graph.center(cell, domain)


static func _points_match(graph: CityTrafficGraph, fresh: CityTrafficGraph) -> bool:
	for domain: StringName in DOMAINS:
		for cell: Vector2i in fresh._nodes[domain]:
			if graph.center(cell, domain) != fresh.point(cell, domain): return false
			if graph.point(cell, domain, Vector2(.1, .9)) != fresh.point(cell, domain, Vector2(.1, .9)): return false
	return true


static func _batches(lamps: CityStreetLamps3D) -> Array:
	var out: Array = []
	for kind: String in lamps._batches:
		var batch: MultiMesh = lamps._batches[kind].multimesh
		out.append([kind, batch.instance_count, batch.buffer])
	return out


static func _cells_beside(city: City, wanted: Callable) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if city.is_water(x, y): continue
			for step: Vector2i in DIRS:
				var near := Vector2i(x, y) + step
				if city.in_bounds(near.x, near.y) and wanted.call(near):
					found.append(Vector2i(x, y))
					break
	return found


func _sequence(label: String, city: City, steps: int) -> void:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var lamps := CityStreetLamps3D.new()
	root.add_child(lamps)
	lamps.sync(graph)
	var reference := CityStreetLamps3D.new()
	root.add_child(reference)
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label) + 3
	var kinds := CityTrafficGraph.network_kinds()
	var shore := _cells_beside(city, func(cell: Vector2i) -> bool: return city.is_water(cell.x, cell.y))
	var roadside := _cells_beside(city, func(cell: Vector2i) -> bool: return kinds[city.building.atv(cell)] != 0)
	check(not roadside.is_empty(), label + ": the city has ground beside its networks")
	var incremental := 0
	var lamp_syncs := 0
	var flood_steps := 0
	for step: int in steps:
		_prime(graph)
		var kind := step % 10
		var what := "flood"
		match kind:
			0, 1, 2:
				# A flood spreading from the shore.
				var at: Vector2i = shore[rng.randi_range(0, shore.size() - 1)] if not shore.is_empty() else roadside[rng.randi_range(0, roadside.size() - 1)]
				for i: int in rng.randi_range(1, 8):
					if city.in_bounds(at.x, at.y): city.flood_overlay[at] = rng.randi_range(1, 3)
					at += DIRS[rng.randi_range(0, 3)]
			3, 4, 5:
				# Onto and beside roads, rails, highways, ramps and bridges.
				var at: Vector2i = roadside[rng.randi_range(0, roadside.size() - 1)]
				for i: int in rng.randi_range(1, 6):
					if city.in_bounds(at.x, at.y): city.flood_overlay[at] = 1
					at += DIRS[rng.randi_range(0, 3)]
			6:
				var wet: Array = city.flood_overlay.keys()
				for i: int in mini(wet.size(), rng.randi_range(1, 8)): city.flood_overlay.erase(wet[rng.randi_range(0, wet.size() - 1)])
			7:
				# Deeper water on the same tiles.
				for cell: Vector2i in city.flood_overlay: city.flood_overlay[cell] = int(city.flood_overlay[cell]) + 1
			8:
				what = "edit " + Edits.apply(city, builder, rng)
				if step % 20 == 8:
					var at: Vector2i = roadside[rng.randi_range(0, roadside.size() - 1)]
					city.flood_overlay[at] = 1
					what += " and flood"
			9:
				if step % 30 == 29:
					city.flood_overlay.clear()
					what = "flood ends"
				else:
					var wet: Array = city.flood_overlay.keys()
					for i: int in mini(wet.size(), 3): city.flood_overlay.erase(wet[i])
		graph.refresh()
		lamps.sync(graph)
		if kind != 8: flood_steps += 1
		if kind != 8 and graph.last_change != CityTrafficGraph.CHANGE_FULL: incremental += 1
		if lamps.last_sync_incremental: lamp_syncs += 1
		var fresh := _fresh_graph(city)
		var planned := reference.plan(fresh)
		reference._index(planned)
		reference._publish(planned)
		var name := "%s step %d (%s, %d flooded)" % [label, step, what, city.flood_overlay.size()]
		check(_graph_bytes(graph) == _graph_bytes(fresh), name + ": the graph equals a fresh projection")
		check(_points_match(graph, fresh), name + ": every sampled point equals a fresh projection's")
		check(var_to_bytes(lamps.placements) == var_to_bytes(planned), name + ": lamp placements equal a fresh plan")
		check(_batches(lamps) == _batches(reference), name + ": lamp instances equal a fresh plan")
		check(lamps._image.get_data() == reference._image.get_data(), name + ": light pools equal a fresh plan")
	print("    %s: %d of %d flood changes refreshed incrementally, %d incremental lamp syncs" % [label, incremental, flood_steps, lamp_syncs])
	check(incremental * 10 >= flood_steps * 8, label + ": flood changes refresh the graph incrementally (%d of %d)" % [incremental, flood_steps])
	check(lamp_syncs * 2 >= steps, label + ": the lamps follow incrementally (%d of %d)" % [lamp_syncs, steps])
	lamps.free()
	reference.free()


func test_imported_terrain() -> void:
	_sequence("Harbor Palms", SaveFormat.load("res://assets/cities/Harbor Palms.sc2d").city, 60)
	_sequence("Valle del Mar", Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city, 40)
	_sequence("La Presa", Sc2Import.load("res://assets/cities/La Presa.sc2").city, 40)


func test_native_terrain() -> void:
	_sequence("Adaven", SaveFormat.load("res://assets/cities/Adaven.sc2d").city, 50)
	_sequence("Juniper Basin", SaveFormat.load("res://assets/cities/Juniper Basin.sc2d").city, 40)
	_sequence("Bonanza Gap", SaveFormat.load("res://assets/cities/Bonanza Gap.sc2d").city, 40)
