# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Network emitters keep their golden ramp and quad output, and the cached
## terrain facets, memoized masks and inline spline weights agree with the
## direct calculations they replace.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")

const CITY := "res://assets/cities/La Presa.sc2"
var _city: City

func before_all() -> void:
	var loaded := Sc2Import.load(CITY)
	check(loaded.ok, "fixture city imports")
	_city = loaded.city

func _layer_bytes(layer: CityNetworks3D) -> PackedByteArray:
	return var_to_bytes([layer._faces, layer._colors, layer._cells, layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT)), layer._physical_boxes, layer._physical_obstacles])

func test_ramp_surfaces_match_golden_output() -> void:
	var ramps: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if NetworkShapes.is_onramp(_city.building.at(x, y)): ramps.append(Vector2i(x, y))
	check_gt(ramps.size(), 8, "fixture city has many onramps")
	var sampling := CityGeometry3D.begin_ground_sampling(_city)
	for cell: Vector2i in ramps.slice(0, 8):
		var layer := CityNetworks3D.new()
		layer._prepare_bridge_decks(_city)
		layer._ramp(_city, cell, _city.building.atv(cell))
		check_gt(layer._faces.size(), 1000, "ramp %s emits its full surface" % cell)
		check(Hashes.matches("ramp/%d_%d" % [cell.x, cell.y], Hashes.sha(_layer_bytes(layer))), "ramp %s faces, colors, cells and physical records match the golden hash" % cell)
		layer.free()
	CityGeometry3D.end_ground_sampling(sampling)

func test_ramp_profile_height_equals_ramp_height() -> void:
	var count := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var code := _city.building.at(x, y)
			if not NetworkShapes.is_onramp(code) or count >= 6: continue
			count += 1
			var cell := Vector2i(x, y)
			var ends := NetworkShapes.onramp_endpoints(code, bool(_city.flags.atv(cell) & RotationMapper.AXIS_FLAG), 0)
			var road := Vector2(ends[0])
			var high := Vector2(ends[1])
			var stencil := CityNetworks3D.HighwayHeight.stencil(_city, cell)
			for radius: float in [0.2, 0.5 - 0.3375, 0.5, 0.5 + 0.0125, 0.8]:
				var profile := CityNetworks3D.HighwayHeight.ramp_profile(_city, cell, road, high, radius, stencil, CityNetworks3D.HIGHWAY_ELEVATION)
				for i: int in [0, 1, 7, 64, 100, 127, 128]:
					var t := i/128.0
					check_eq(CityNetworks3D.HighwayHeight.ramp_profile_height(profile, t), CityNetworks3D.HighwayHeight.ramp_height(_city, cell, road, high, t, radius, stencil, CityNetworks3D.HIGHWAY_ELEVATION), "profile height equals direct ramp height at %s r=%s t=%s" % [cell, radius, t])

func test_inline_spline_height_equals_weight_arrays() -> void:
	var stencils: Array[PackedFloat64Array] = []
	for y: int in range(0, City.HEIGHT, 17):
		for x: int in range(0, City.WIDTH, 13):
			stencils.append(CityNetworks3D.HighwayHeight.stencil(_city, Vector2i(x, y)))
	var offsets: Array[Vector2] = [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.125, 0.875), Vector2(1, 1), Vector2(0.3333, 0.01), Vector2(0.98, 0.49)]
	for heights: PackedFloat64Array in stencils:
		for offset: Vector2 in offsets:
			var wx := CityNetworks3D.HighwayHeight.weights(offset.x)
			var wy := CityNetworks3D.HighwayHeight.weights(offset.y)
			var expected := 0.0
			for yy: int in 4:
				for xx: int in 4: expected += heights[yy*4+xx]*wx[xx]*wy[yy]
			check_eq(CityNetworks3D.HighwayHeight.height(heights, offset), expected, "inline weights reproduce the array formulation")

func test_facet_interpolation_equals_point_on_ground() -> void:
	var offsets: Array[Vector2] = [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.4875, 0.4875), Vector2(1, 0), Vector2(0.2, 0.9), Vector2(0.75, 0.75)]
	var layer := CityNetworks3D.new()
	var sampling := CityGeometry3D.begin_ground_sampling(_city)
	for y: int in range(0, City.HEIGHT, 3):
		for x: int in range(0, City.WIDTH, 5):
			var cell := Vector2i(x, y)
			var corners := CityGeometry3D.ground_corners(_city, cell)
			var facet: Array = layer._facet(_city, cell)
			check(facet[0] == corners, "cached facet corners equal ground corners at %s" % cell)
			check_eq(facet[1], CityGeometry3D.uses_nw_se_diagonal(corners), "cached diagonal equals the facet rule at %s" % cell)
			for offset: Vector2 in offsets:
				check(CityGeometry3D.point_over_facet(corners, facet[1], cell, offset) == CityGeometry3D.point_on_ground(_city, cell, offset), "facet interpolation equals point_on_ground at %s %s" % [cell, offset])
	CityGeometry3D.end_ground_sampling(sampling)
	layer.free()

func test_memoized_tables_match_predicates() -> void:
	for code: int in Buildings.COUNT:
		check_eq(CityNetworks3D.bridge_family(code), CityNetworks3D._bridge_family_uncached(code), "bridge family table code %d" % code)
		for family: int in NetworkShapes.Family.values():
			check_eq(CityNetworks3D.network_mask(code, family), CityNetworks3D._network_mask_uncached(code, family), "network mask table code %d family %d" % [code, family])

func test_packed_physical_records_keep_the_record_contract() -> void:
	var layer := CityNetworks3D.new()
	var sampling := CityGeometry3D.begin_ground_sampling(_city)
	layer.update_regions(_city, [], 16)
	CityGeometry3D.end_ground_sampling(sampling)
	var records := layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	check_eq(records.size(), layer._physical_depths.size(), "whole-map query covers every packed patch")
	check_gt(records.size(), 1000, "fixture emits physical patches")
	var first: Dictionary = records[0]
	check_eq(first.keys(), ["cell", "group", "role", "triangle", "depth"], "records keep the cell, group, role, triangle, depth key order")
	check(first.triangle is PackedVector3Array and first.triangle.size() == 3, "each record owns one packed triangle")
	var region := Rect2i(40, 40, 20, 20)
	var expected: Array[Dictionary] = []
	for record: Dictionary in records:
		if region.has_point(record.cell): expected.append(record)
	check(var_to_bytes(layer.physical_patches_in(region)) == var_to_bytes(expected), "region query equals filtering the complete records in order")
	var part: CityNetworks3D = layer._regions.values()[0]
	part.clear_physical_patches()
	check(part._physical_depths.is_empty() and part._physical_triangles.is_empty(), "clearing empties the packed storage")
	layer.free()

func test_triangle_emitter_keeps_vertex_orders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	var layer := CityNetworks3D.new()
	for role: int in [CityNetworks3D.PhysicalRole.DETAIL, CityNetworks3D.PhysicalRole.FLOOR, CityNetworks3D.PhysicalRole.OBSTACLE]:
		for i: int in 40:
			var a := Vector3(rng.randf_range(0, 128), rng.randf_range(0, 20), rng.randf_range(0, 128))
			var b := a + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1))
			var c := a + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1))
			var d := b + c - a
			if i % 7 == 0: c = b # degenerate first triangle
			layer._physical_group = 4
			layer._world_quad(Vector2i(int(a.x), int(a.z)), a, b, c, d, Color(0.1, 0.2, 0.3), role)
	check(Hashes.matches("world_quad/random_quads", Hashes.sha(_layer_bytes(layer))), "world quads emit the golden faces, colors, cells, records and obstacles")
	check_gt(layer._faces.size(), 100, "fixture emitted triangles")
	layer.free()
