# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Physical extraction for every network kind matches its golden output hash.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")
func _compare(city: City, key: String) -> void:
	var before := SaveFormat.encode_city(city)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var patches := layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	var inputs := var_to_bytes([patches,layer._physical_boxes,layer._physical_obstacles])
	var actual: Dictionary = Resolver.resolve(patches, layer._physical_boxes, layer._physical_obstacles)
	check(Hashes.matches(key, Hashes.sha(actual)), "%s every floor/obstacle vertex, physical box and their order match the golden hash" % key)
	check(var_to_bytes([patches,layer._physical_boxes,layer._physical_obstacles]) == inputs, "%s caller-owned physical inputs unchanged" % key)
	check(SaveFormat.encode_city(city) == before, "%s city bytes unchanged" % key)
	check(actual.physical_floor_faces.size() > 0, "%s fixture emits floors" % key)
	layer.free()
func test_every_network_kind_matches_golden_physics() -> void:
	var city := City.new()
	city.altitude.data.fill(4)
	for code: int in range(29,109):
		var index := code-29
		var cell := Vector2i(3+(index%10)*3,80+(index/10)*3)
		city.building.putv(cell,code)
		city.flags.putv(cell,2 if code%2 == 0 else 0)
		if code in range(63,67): city.terrain.putv(cell,code-62)
	for x: int in range(60,65):
		city.building.put(x,20,87)
		city.flags.put(x,20,2)
	_compare(city,"network_physics/mixed_far_city")
