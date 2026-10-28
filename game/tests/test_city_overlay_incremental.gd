# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Data-map refreshes skip unchanged source bytes, rebuild only the rows of
## changed blocks and must equal a fresh build of the same layer.
func arrays_of(overlay: CityOverlay3D) -> Array:
	var mesh: ArrayMesh = overlay.mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0: return []
	var arrays := mesh.surface_get_arrays(0)
	return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_NORMAL]]


func check_matches_fresh(overlay: CityOverlay3D, city: City, message: String) -> void:
	var fresh := CityOverlay3D.new()
	fresh.bind_city(city)
	fresh.set_layer(overlay.active_layer)
	check(arrays_of(overlay) == arrays_of(fresh), message)
	fresh.free()


func test_incremental_layer_changes_equal_a_fresh_build() -> void:
	var city := flat_city()
	city.terrain.put(20, 20, 5)
	for i in range(0, 40): city.crime.put(i, 10, 90 + i)
	var overlay := CityOverlay3D.new()
	overlay.bind_city(city)
	overlay.set_layer(&"crime")
	var builds := overlay.rebuild_count
	city.crime.put(5, 10, 200)
	city.crime.put(30, 40, 60)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1)
	check_matches_fresh(overlay, city, "changed crime blocks equal a fresh build")
	city.flags.set_bits(3, 3, TileFlags.POWERED, true)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1, "unrelated bytes keep the crime mesh")

	overlay.set_layer(&"water")
	for x in range(10, 30): city.flags.set_bits(x, 12, TileFlags.CONDUCTS_WATER, true)
	overlay.refresh()
	builds = overlay.rebuild_count
	city.flags.set_bits(3, 3, TileFlags.POWERED, false)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds, "flag bits that sample equally keep the water mesh")
	city.flags.set_bits(15, 12, TileFlags.WATERED, true)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1)
	check_matches_fresh(overlay, city, "changed service equals a fresh build")

	overlay.set_layer(&"zones")
	city.zone.put(40, 40, Zones.make(Zones.RES_LOW))
	overlay.refresh()
	check_matches_fresh(overlay, city, "zoning equals a fresh build")
	city.set_heights(41, 40, 3)
	overlay.refresh()
	check_matches_fresh(overlay, city, "terrain edits equal a fresh build")
	overlay.free()
