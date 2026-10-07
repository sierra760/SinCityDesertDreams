# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var overlay_script

func before_all() -> void:
	var path := "res://scripts/view/city_overlay_3d.gd"
	if ResourceLoader.exists(path): overlay_script = load(path)

func test_batched_overlay_exists() -> void:
	check(overlay_script != null, "terrain-following 3D overlay must exist")

func test_facets_water_cache_flags_and_read_only_city() -> void:
	if overlay_script == null: return
	var city := flat_city()
	city.zone.put(10, 10, Zones.make(Zones.RES_LOW))
	city.terrain.put(10, 10, 1)
	city.zone.put(11, 10, Zones.make(Zones.COM_HIGH))
	city.terrain.put(11, 10, Terrain.SURFACE)
	city.set_heights(11, 10, 2, 6)
	var before := SaveFormat.encode_city(city)
	var overlay = overlay_script.new()
	root.add_child(overlay)
	overlay.bind_city(city)
	overlay.set_layer(&"zones")
	check_eq(overlay.get_child_count(), 1, "one batched mesh, no cell nodes")
	var mesh: ArrayMesh = overlay.mesh_instance.mesh
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(points.size(), 12)
	for i in [0, 1, 2]:
		var p: Vector3 = points[i]
		var ground := CityGeometry3D.surface_corners(city, Vector2i(10, 10))
		check(ground.has(p - Vector3.UP * overlay.SURFACE_OFFSET), "overlay uses actual slope corner")
	for i in range(6, 12): check(is_equal_approx(points[i].y, CityGeometry3D.water_surface_height(city, Vector2i(11, 10)) + overlay.SURFACE_OFFSET))
	var builds: int = overlay.rebuild_count
	overlay.refresh()
	check_eq(overlay.mesh_instance.mesh, mesh)
	check_eq(overlay.rebuild_count, builds)
	city.rotation = 3
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds, "camera rotation doesn't change canonical geometry")
	city.rotation = 0
	check_eq(SaveFormat.encode_city(city), before)
	city.set_heights(10, 10, 8)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1)
	city.flags.put(10, 10, TileFlags.CONDUCTS_POWER)
	overlay.set_layer(&"power")
	builds = overlay.rebuild_count
	city.flags.set_bits(10, 10, TileFlags.POWERED, true)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1)
	overlay.set_layer(&"bogus")
	check_eq(overlay.active_layer, &"power")
	overlay.set_layer(&"none")
	check(not overlay.visible)
	overlay.clear()
	check_eq(overlay.get_child_count(), 1)
	check_eq(overlay.mesh_instance.mesh, null)
	overlay.free()

func test_shared_terrain_vertices_invalidate_overlay_without_city_changes() -> void:
	if overlay_script == null: return
	var city := flat_city()
	city.zone.put(10, 10, Zones.make(Zones.RES_LOW))
	city.terrain_surface = TerrainSurface.new(4)
	var overlay = overlay_script.new()
	overlay.bind_city(city)
	overlay.set_layer(&"zones")
	var builds: int = overlay.rebuild_count
	city.terrain_surface.set_vertex(11, 10, 7)
	var before := SaveFormat.encode_city(city)
	overlay.refresh()
	check_eq(overlay.rebuild_count, builds + 1)
	check_eq(SaveFormat.encode_city(city), before)
	overlay.free()

func test_quarter_resolution_still_follows_each_tile_and_full_city_is_bounded() -> void:
	if overlay_script == null: return
	var city := flat_city()
	city.police.data.fill(255)
	var overlay = overlay_script.new()
	overlay.bind_city(city)
	overlay.set_layer(&"police")
	check_eq(overlay.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 128 * 128 * 6)
	check_eq(overlay.get_child_count(), 1)
	overlay.free()
