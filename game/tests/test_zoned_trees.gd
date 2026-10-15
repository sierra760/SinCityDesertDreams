# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Natural trees leave undeveloped zoning visible without requiring electricity.
extends "res://tests/exploration/async_test_case.gd"

const CELL := Vector2i(10, 10)


func test_tree_ground_keeps_every_zone_on_flat_and_sloping_land() -> void:
	var city := flat_city()
	for sloped: bool in [false, true]:
		city.terrain_surface = TerrainSurface.new(4)
		if sloped:
			city.terrain_surface.set_vertex(11, 10, 5)
			city.terrain_surface.set_vertex(11, 11, 5)
		for zone: int in Zones.COLORS:
			city.building.putv(CELL, Buildings.NONE)
			city.zone.putv(CELL, Zones.make(zone))
			var empty := CityGeometry3D.build_chunk(city, Rect2i(CELL, Vector2i.ONE))
			var expected: PackedColorArray = empty.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			for code: int in range(Buildings.TREES_1, Buildings.TREES_7 + 1):
				city.building.putv(CELL, code)
				var before := var_to_bytes(SaveFormat.encode_city(city))
				var wooded := CityGeometry3D.build_chunk(city, Rect2i(CELL, Vector2i.ONE))
				check_eq(wooded.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR], expected,
					"tree %d retains zone %d ground (slope %s)" % [code, zone, sloped])
				check_eq(wooded.faces, empty.faces, "tree tint preserves visible terrain")
				check_eq(wooded.physical_floor_faces, empty.physical_floor_faces, "tree tint preserves walking ground")
				check_eq(var_to_bytes(SaveFormat.encode_city(city)), before, "rendering preserves saved city")
	city.zone.putv(CELL, Zones.NONE)
	check_eq(CityGeometry3D.cell_sand_color(city, 10, 10), Color(0.75, 0.633, 0.49), "unzoned trees retain sand")
	city.zone.putv(CELL, Zones.make(Zones.RES_LOW))
	for code: int in [Buildings.SMALL_PARK, Buildings.RES_1X1_FIRST, Buildings.ROAD_FIRST]:
		city.building.putv(CELL, code)
		check_eq(CityGeometry3D.cell_sand_color(city, 10, 10), Color(0.75, 0.633, 0.49), "built lots and roads retain ground")


func test_maps_show_zoning_over_natural_trees_but_keep_unzoned_groves() -> void:
	var city := flat_city()
	for zone: int in Zones.COLORS:
		city.zone.putv(CELL, Zones.make(zone))
		city.building.putv(CELL, Buildings.NONE)
		var expected := MiniMap.tile_color(city, 10, 10)
		check_ne(expected, MiniMap.COLOR_TREES, "zone is distinct from unzoned vegetation")
		for code: int in range(Buildings.TREES_1, Buildings.TREES_7 + 1):
			city.building.putv(CELL, code)
			check_eq(MiniMap.tile_color(city, 10, 10), expected, "map preserves zone beneath tree %d" % code)
	city.zone.putv(CELL, Zones.NONE)
	check_eq(MiniMap.tile_color(city, 10, 10), MiniMap.COLOR_TREES, "unzoned woodland retains its symbol")
	city.zone.putv(CELL, Zones.make(Zones.COM_LOW))
	city.building.putv(CELL, Buildings.SMALL_PARK)
	check_eq(MiniMap.tile_color(city, 10, 10), MiniMap.COLOR_TREES, "built pocket park retains its symbol")
	city.building.putv(CELL, Buildings.ROAD_FIRST)
	check_eq(MiniMap.tile_color(city, 10, 10), MiniMap.COLOR_ROAD, "road retains map precedence")


func test_actual_power_setup_excludes_trees_and_retires_cached_warnings() -> void:
	var city := flat_city()
	for zone: int in Zones.COLORS:
		for code: int in range(Buildings.TREES_1, Buildings.TREES_7 + 1):
			var cell := Vector2i(10 + code, 10 + zone)
			city.stamp_building(cell.x, cell.y, code)
			city.zone.putv(cell, Zones.make(zone))
	city.stamp_building(60, 60, Buildings.RES_1X1_FIRST)
	city.stamp_building(62, 60, Buildings.POWER_LINE_FIRST)
	var power := PowerSystem.new()
	power.setup(make_context(city))
	check(city.conducts_power(16, 11) and not city.is_powered(16, 11), "real setup makes disconnected zoned trees conductive")
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	check_eq(feedback.power_warning_count(), 2, "only the house and ordinary power line need warnings")
	for warning: Node in feedback.power_markers.get_children():
		check(warning.get_meta("cell") in [Vector2i(60, 60), Vector2i(62, 60)], "no tree receives an outage icon")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)), before, "warning refresh preserves city state")
	city.stamp_building(60, 60, Buildings.TREES_7)
	city.zone.put(60, 60, Zones.make(Zones.RES_LOW))
	power.setup(make_context(city))
	feedback.sync_power()
	check_eq(feedback.power_warning_count(), 1, "tree replacement removes cached house warning")
	city.stamp_building(60, 60, Buildings.RES_1X1_FIRST)
	power.setup(make_context(city))
	feedback.sync_power()
	check_eq(feedback.power_warning_count(), 2, "redeveloped house regains its outage warning")
	feedback.queue_free()
	await process_frame
	await process_frame


func test_zoning_and_development_recolor_retained_tree_ground_and_maps() -> void:
	var city := flat_city()
	city.stamp_building(10, 10, (Buildings.TREES_1 + 3))
	var bounds := Rect2i(CELL, Vector2i.ONE)
	var retained := CityGeometry3D.build_chunk(city, bounds)
	var overview := MiniMap.new()
	overview.city = city
	overview.generate_image()
	for step: Dictionary in [
		{"zone": Zones.COM_LOW, "building": (Buildings.TREES_1 + 3)},
		{"zone": Zones.RES_HIGH, "building": (Buildings.TREES_1 + 3)},
		{"zone": Zones.NONE, "building": (Buildings.TREES_1 + 3)},
		{"zone": Zones.RES_LOW, "building": (Buildings.TREES_1 + 3)},
		{"zone": Zones.RES_LOW, "building": Buildings.RES_1X1_FIRST},
		{"zone": Zones.RES_LOW, "building": Buildings.TREES_1}]:
		city.zone.putv(CELL, Zones.make(step.zone))
		city.building.putv(CELL, step.building)
		retained = CityGeometry3D.recolor_chunk(city, retained, [CELL])
		var expected := Color(0.75, 0.633, 0.49)
		if step.zone != Zones.NONE and step.building != Buildings.RES_1X1_FIRST:
			expected = expected.lerp(Zones.COLORS[step.zone], 0.65)
		# Mesh upload quantizes colors to bytes; check the authored tint exactly,
		# then compare the complete uploaded arrays with a fresh mesh below.
		var colors: PackedColorArray = retained.colors
		check_eq(colors[0], expected, "retained ground follows zoning and development")
		var fresh := CityGeometry3D.build_chunk(city, bounds)
		check_eq(retained.mesh.surface_get_arrays(0), fresh.mesh.surface_get_arrays(0), "retained terrain equals full rebuild")
		overview.generate_image()
		var rebuilt := MiniMap.new()
		rebuilt.city = city
		rebuilt.generate_image()
		check_eq(overview.get_image().get_data(), rebuilt.get_image().get_data(), "incremental map follows zoning/development")
		rebuilt.free()
	overview.free()
