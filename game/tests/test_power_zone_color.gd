# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Power lines preserve the existing zone ground color without changing city data.
extends "res://tests/test_case.gd"


func _ground_colors(city: City) -> PackedColorArray:
	var mesh: ArrayMesh = CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1)).mesh
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]


func test_all_standalone_power_shapes_keep_each_zone_color() -> void:
	var city := flat_city()
	var sand := _ground_colors(city)
	for zone: int in range(1, 10):
		city.building.put(10, 10, Buildings.NONE)
		city.zone.put(10, 10, Zones.make(zone))
		var zoned := _ground_colors(city)
		check_ne(zoned, sand, "empty zone %d has visible color" % zone)
		for code: int in range(14, 29):
			city.building.put(10, 10, code)
			var before := var_to_bytes(SaveFormat.encode_city(city))
			check_eq(_ground_colors(city), zoned, "power shape %d keeps zone %d color" % [code, zone])
			check_eq(var_to_bytes(SaveFormat.encode_city(city)), before, "rendering preserves city/save data")


func test_unzoned_power_and_transport_crossings_keep_their_ground() -> void:
	var city := flat_city()
	var sand := _ground_colors(city)
	for code: int in range(14, 29):
		city.building.put(10, 10, code)
		check_eq(_ground_colors(city), sand, "unzoned power stays sand")
	city.zone.put(10, 10, Zones.make(Zones.RES_LOW))
	for code: int in [29, 30, 44, 45, 67, 68, 71, 72, 79, 80, 92, 112]:
		city.building.put(10, 10, code)
		check_eq(_ground_colors(city), sand, "transport/developed tile %d keeps its ground" % code)


func test_power_preserves_zone_color_on_shared_sloping_ground() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	city.terrain_surface.set_vertex(11, 10, 5)
	city.terrain_surface.set_vertex(11, 11, 5)
	city.zone.put(10, 10, Zones.make(Zones.COM_HIGH))
	var empty := CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1))
	var zoned: PackedColorArray = empty.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	city.building.put(10, 10, 18)
	var power := CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1))
	check_eq(power.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR], zoned, "grade retains the zone color beneath power")
	check_eq(power.faces, empty.faces, "the color change preserves terrain geometry")
	check_eq(power.physical_floor_faces, empty.physical_floor_faces, "the color change preserves the physical floor")
