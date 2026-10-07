# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")

func test_curved_surface_construction_keeps_vertices_colors_and_physics() -> void:
	var city := flat_city()
	city.terrain_surface=TerrainSurface.new(4)
	city.terrain_surface.set_vertex(20,20,6)
	var layer := CityNetworks3D.new()
	var square: Array[Vector2] = [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
	var scope := CityGeometry3D.begin_ground_sampling(city)
	layer._physical_group=NetworkShapes.Family.HIGHWAY
	layer._physical_depth=.095
	for i: int in 24:
		layer._curved_polygon(city,Vector2i(20+i%3,20),square,Color(.3,.4,.5),.65,0)
	var output := [layer._faces,layer._colors,layer._cells,layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT))]
	CityGeometry3D.end_ground_sampling(scope)
	check(Hashes.matches("curved_surface/construction", Hashes.sha(output)),"curved surface positions/order/colors and all collision patches match the golden hash")
	layer.free()
