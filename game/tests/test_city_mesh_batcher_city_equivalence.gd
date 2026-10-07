# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Incremental batching of a real city equals a fresh full rebuild after growth-like edits.
extends "res://tests/exploration/async_test_case.gd"
func _signature(batcher: Node3D) -> Array:
	var result: Array = []
	for batch: MultiMeshInstance3D in batcher.get_children():
		result.append([str(batch.get_meta("chunk")), String(batch.get_meta("domain")), batch.get_meta("source_ids"),
			batch.get_meta("uploaded_transforms"), batch.multimesh.mesh.get_instance_id(), batch.multimesh.custom_aabb,
			batch.cast_shadow, batch.layers, batch.visible, batch.multimesh.instance_count])
	result.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return result
func _hidden(view: CityView3D) -> Array:
	var ids: Array = []
	for source_root: Node3D in [view.buildings, view.networks]:
		for mesh: MeshInstance3D in source_root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.visible: ids.append(mesh.get_instance_id())
	ids.sort()
	return ids
func test_incremental_city_batches_match_fresh_rebuild() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	check(loaded.ok, "La Presa imports")
	var city: City = loaded.city
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lots: Array[Vector2i] = []
	var empty: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var code := city.building.at(x, y)
			if Buildings.is_zone_building(code) and city.anchor_of(x, y) == Vector2i(x, y): lots.append(Vector2i(x, y))
			elif code == Buildings.NONE and not city.is_water(x, y): empty.append(Vector2i(x, y))
	check(lots.size() > 100 and empty.size() > 100, "fixture has lots and empty ground")
	var distant_ids := _signature(view.mesh_batches).size()
	check(distant_ids > 50, "the full city produces many batches")
	for round: int in 3:
		for step: int in 5:
			match step % 4:
				0:
					var cell: Vector2i = lots[rng.randi_range(0, lots.size() - 1)]
					city.clear_footprint(cell.x, cell.y)
				1:
					var cell: Vector2i = empty[rng.randi_range(0, empty.size() - 1)]
					city.stamp_building(cell.x, cell.y, Buildings.RES_1X1_FIRST + rng.randi_range(0, 7))
				2:
					var cell: Vector2i = lots[rng.randi_range(0, lots.size() - 1)]
					var code := city.building.at(cell.x, cell.y)
					if Buildings.size(code) == Vector2i.ONE: city.building.put(cell.x, cell.y, Buildings.RES_1X1_FIRST + (code - Buildings.RES_1X1_FIRST + 1) % 8)
				3:
					var cell: Vector2i = empty[rng.randi_range(0, empty.size() - 1)]
					city.zone.put(cell.x, cell.y, Zones.make(Zones.IND_LOW))
			view.refresh()
		var incremental := _signature(view.mesh_batches)
		var hidden := _hidden(view)
		var statistics: Dictionary = view.mesh_batches.statistics.duplicate()
		view.mesh_batches.rebuild([view.buildings, view.networks])
		check(_signature(view.mesh_batches) == incremental, "round %d: incremental batches equal a fresh full rebuild" % round)
		check(_hidden(view) == hidden, "round %d: the same source meshes are hidden behind batches" % round)
		check(int(statistics.batched_instances) == int(view.mesh_batches.statistics.batched_instances) and int(statistics.batches) == int(view.mesh_batches.statistics.batches), "round %d: incremental statistics equal the full rebuild" % round)
	view.queue_free()
	await process_frame
