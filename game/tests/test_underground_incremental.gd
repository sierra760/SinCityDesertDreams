# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Incremental underground refreshes re-project only tiles near changed
## inputs and must equal a fresh full projection of the same city.
func arrays_of(renderer: CityUnderground3D) -> Array:
	var mesh: ArrayMesh = renderer.mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0: return []
	var arrays := mesh.surface_get_arrays(0)
	return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_NORMAL]]


func check_matches_fresh(renderer: CityUnderground3D, city: City, message: String) -> void:
	var fresh := CityUnderground3D.new()
	fresh.bind_city(city)
	check(arrays_of(renderer) == arrays_of(fresh), message)
	fresh.free()


func test_incremental_edits_equal_a_fresh_projection() -> void:
	var city := flat_city()
	for x in range(20, 40): city.underground.put(x, 30, 25) # east-west subway
	city.underground.put(30, 30, 35)
	for y in range(20, 40): city.underground.put(50, y, 5) # north-south pipe
	city.underground.put(50, 30, 31)
	city.stamp_building(60, 60, Buildings.WATER_TREATMENT)
	city.stamp_building(10, 10, Buildings.WATER_PUMP)
	city.stamp_building(11, 10, Buildings.RES_1X1_FIRST)
	city.terrain.put(25, 31, 5)
	var renderer := CityUnderground3D.new()
	renderer.bind_city(city)
	check_eq(renderer.emitted_cells, City.WIDTH * City.HEIGHT, "the first projection covers the map")
	var builds := renderer.rebuild_count

	city.flags.set_bits(20, 30, TileFlags.POWERED, true)
	city.flags.set_bits(100, 100, TileFlags.CONDUCTS_POWER, true)
	renderer.refresh()
	check_eq(renderer.rebuild_count, builds, "power-only flags keep the projection")

	city.stamp_building(12, 10, Buildings.RES_1X1_FIRST)
	renderer.refresh()
	check_eq(renderer.rebuild_count, builds + 1, "growth refreshes the projection")
	check_lt(renderer.emitted_cells, 50, "growth re-projects only nearby tiles")
	check_matches_fresh(renderer, city, "lot growth equals a fresh projection")

	city.flags.set_bits(50, 25, TileFlags.WATERED, true)
	renderer.refresh()
	check_matches_fresh(renderer, city, "service color change equals a fresh projection")

	city.underground.put(40, 30, 25)
	city.underground.put(30, 31, 20)
	renderer.refresh()
	check_matches_fresh(renderer, city, "subway edits equal a fresh projection")

	city.building.put(61, 61, Buildings.NONE)
	renderer.refresh()
	check_matches_fresh(renderer, city, "a broken facility footprint equals a fresh projection")

	city.flags.set_bits(21, 31, RotationMapper.AXIS_FLAG, true)
	city.building.put(21, 31, Buildings.RAIL_FIRST)
	renderer.refresh()
	check_matches_fresh(renderer, city, "surface rail beside a subway equals a fresh projection")

	city.set_heights(26, 30, 7)
	renderer.refresh()
	check_eq(renderer.emitted_cells, City.WIDTH * City.HEIGHT, "terrain changes re-project the map")
	check_matches_fresh(renderer, city, "terrain edits equal a fresh projection")

	var mesh := renderer.mesh_instance.mesh
	builds = renderer.rebuild_count
	renderer.refresh()
	check_eq(renderer.mesh_instance.mesh, mesh, "unchanged inputs keep the mesh")
	check_eq(renderer.rebuild_count, builds)
	renderer.free()
