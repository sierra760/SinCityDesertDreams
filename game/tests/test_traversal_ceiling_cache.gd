# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The cached shell ceiling equals a fresh traversal world's after lot changes.
extends "res://tests/exploration/async_test_case.gd"
func test_cached_ceiling_matches_fresh_world() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Lawndale.sc2")
	check(loaded.ok, "Lawndale imports")
	var city: City = loaded.city
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var world := CityTraversalWorld3D.new()
	view.world.add_child(world)
	var snapshot := view.traversal_snapshot()
	world.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	var first := world.max_flight_y()
	check(first > 8.0, "the ceiling rises above the city shells")
	var fresh := CityTraversalWorld3D.new()
	view.world.add_child(fresh)
	fresh.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	check(is_equal_approx(fresh.max_flight_y(), first), "a fresh world computes the same ceiling")
	fresh.queue_free()
	# Replace the tallest lots with empty ground and add a tall arcology elsewhere.
	var tallest: Node3D = null
	var top := -1.0
	for lot: Node3D in view.buildings.get_children():
		var height := float(view.catalog.entries.get(int(lot.get_meta("code")), {}).get("height", 0.0)) + lot.position.y
		if height > top:
			top = height
			tallest = lot
	var anchor: Vector2i = tallest.get_meta("cell")
	city.clear_footprint(anchor.x, anchor.y)
	view.refresh()
	snapshot = view.traversal_snapshot()
	world.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	fresh = CityTraversalWorld3D.new()
	view.world.add_child(fresh)
	fresh.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	check(is_equal_approx(fresh.max_flight_y(), world.max_flight_y()), "after removing the tallest lot the cached ceiling equals a fresh world's")
	fresh.queue_free()
	var placed := false
	for y: int in range(4, City.HEIGHT - 4):
		for x: int in range(4, City.WIDTH - 4):
			var clear := true
			for dy: int in 4:
				for dx: int in 4:
					if city.building.at(x + dx, y + dy) != Buildings.NONE or city.is_water(x + dx, y + dy): clear = false
			if clear:
				city.stamp_building(x, y, Buildings.id_of(&"arcology_comstock") if Buildings.id_of(&"arcology_comstock") > 0 else Buildings.RES_1X1_FIRST)
				placed = true
				break
		if placed: break
	check(placed, "a tall lot was placed")
	view.refresh()
	snapshot = view.traversal_snapshot()
	world.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	fresh = CityTraversalWorld3D.new()
	view.world.add_child(fresh)
	fresh.rebuild(city, snapshot.chunks, snapshot.networks, snapshot.revision)
	check(is_equal_approx(fresh.max_flight_y(), world.max_flight_y()), "after adding a tall lot the cached ceiling equals a fresh world's")
	fresh.queue_free()
	world.queue_free()
	view.queue_free()
	await process_frame
