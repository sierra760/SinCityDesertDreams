# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## After an incremental traffic graph refresh the street lamps replan only the
## cells it can have changed. After every construction edit their placements,
## instance transforms and light-pool table equal a fresh complete plan of the
## same city, byte for byte and in the same order.
extends "res://tests/test_case.gd"

const Edits := preload("res://tests/construction/edit_sequence.gd")

static func _fresh_graph(city: City) -> CityTrafficGraph:
	CityTrafficGraph._completed_state = {}
	CityTrafficGraph._completed_owner = null
	CityTrafficGraph._completed_inputs = []
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	CityTrafficGraph._completed_state = {}
	CityTrafficGraph._completed_owner = null
	CityTrafficGraph._completed_inputs = []
	return graph

static func _batches(lamps: CityStreetLamps3D) -> Array:
	var out: Array = []
	for kind: String in lamps._batches:
		var batch: MultiMesh = lamps._batches[kind].multimesh
		out.append([kind, batch.instance_count, batch.buffer])
	return out

func test_construction_edits_match_a_full_plan() -> void:
	var cities := {"La Presa": 40, "Foothills Ranch": 40, "Valle del Mar": 30}
	for name: String in cities: _edit_city(name, int(cities[name]))

func _edit_city(name: String, steps: int) -> void:
	var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
	if not loaded.ok:
		check(false, "import " + name)
		return
	var city: City = loaded.city
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var lamps := CityStreetLamps3D.new()
	root.add_child(lamps)
	lamps.sync(graph)
	check(not lamps.last_sync_incremental, name + ": the first sync plans the whole city")
	var reference := CityStreetLamps3D.new()
	root.add_child(reference)
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + 7
	var applied := 0
	var incremental := 0
	var lamp_changes := 0
	var step := -1
	while applied < steps and step < steps * 6:
		step += 1
		var kind := Edits.apply(city, builder, rng)
		if kind.is_empty(): continue
		applied += 1
		var before := var_to_bytes(lamps.placements)
		graph.refresh()
		lamps.sync(graph)
		if lamps.last_sync_incremental: incremental += 1
		if var_to_bytes(lamps.placements) != before: lamp_changes += 1
		var fresh := _fresh_graph(city)
		var planned := reference.plan(fresh)
		reference._index(planned)
		reference._publish(planned)
		var label := "%s step %d (%s)" % [name, step, kind]
		check(var_to_bytes(lamps.placements) == var_to_bytes(planned), label + ": placements equal a fresh full plan")
		check(_batches(lamps) == _batches(reference), label + ": lamp instances equal a fresh full plan")
		check(lamps._image.get_data() == reference._image.get_data(), label + ": light pools equal a fresh full plan")
	print(name, ": ", applied, " edits, ", incremental, " incremental lamp syncs, ", lamp_changes, " changed the lamps")
	check(applied == steps, name + ": every planned edit applied")
	check(incremental >= applied / 3, name + ": the incremental path carried the edits")
	check(lamp_changes > 0, name + ": some edits changed the lamps")
	lamps.free()
	reference.free()

func test_unchanged_and_replaced_graphs() -> void:
	var city: City = Sc2Import.load("res://assets/cities/La Presa.sc2").city
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var lamps := CityStreetLamps3D.new()
	root.add_child(lamps)
	lamps.sync(graph)
	var placed := var_to_bytes(lamps.placements)
	check_gt(lamps.placements.size(), 100, "La Presa has street lamps")
	lamps.sync(graph)
	check_eq(var_to_bytes(lamps.placements), placed, "an unchanged graph keeps its lamps")
	# Two refreshes between syncs: the lamps cannot know the first one's cells.
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var refreshes := 0
	for attempt: int in 60:
		if refreshes >= 2: break
		var revision := graph.revision
		if Edits.apply(city, builder, rng).is_empty(): continue
		graph.refresh()
		if graph.revision != revision: refreshes += 1
	check_eq(refreshes, 2, "two graph refreshes")
	lamps.sync(graph)
	check(not lamps.last_sync_incremental, "skipped revisions replan the whole city")
	check_eq(var_to_bytes(lamps.placements), var_to_bytes(lamps.plan(_fresh_graph(city))), "and equal a fresh plan")
	# A different graph instance replans completely.
	var other := _fresh_graph(city)
	lamps.sync(other)
	check(not lamps.last_sync_incremental, "a new graph replans the whole city")
	lamps.sync(null)
	check_eq(lamps.placements.size(), 0, "no graph, no lamps")
	lamps.sync(other)
	check_eq(var_to_bytes(lamps.placements), var_to_bytes(lamps.plan(other)), "lamps return with the graph")
	lamps.free()
