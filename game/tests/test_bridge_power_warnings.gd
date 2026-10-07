# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Bridges conduct power but never show an outage warning of their own.
extends "res://tests/exploration/async_test_case.gd"

# Every bridge roster entry, including elevated utility and reinforced spans.
const BRIDGES := [81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 106, 107]
const HOUSE := Vector2i(60, 60)
const LINE := Vector2i(62, 60)


func test_bridges_conduct_power_without_warnings() -> void:
	var city := City.new()
	TerrainSurface.new(4).project(city)
	for index: int in BRIDGES.size():
		var cell := Vector2i(20 + index * 2, 20)
		city.stamp_building(cell.x, cell.y, BRIDGES[index])
		city.terrain.put(cell.x, cell.y, Terrain.SURFACE)
		city.set_heights(cell.x, cell.y, 2, 4)
	city.stamp_building(HOUSE.x, HOUSE.y, Buildings.RES_1X1_FIRST)
	city.stamp_building(LINE.x, LINE.y, Buildings.POWER_LINE_FIRST)
	var ctx := make_context(city)
	PowerSystem.new().setup(ctx)
	for index: int in BRIDGES.size():
		check(city.conducts_power(20 + index * 2, 20) and not city.is_powered(20 + index * 2, 20),
			"actual power setup leaves disconnected bridge %d conductive and unpowered" % BRIDGES[index])
	var before := SaveFormat.encode_city(city)
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	check(feedback.power_warning_count() == 2, "3D warnings remain on the house and ordinary line only")
	for warning: Node in feedback.power_markers.get_children():
		check(warning.get_meta("cell") in [HOUSE, LINE], "3D excludes every bridge warning")
	check(SaveFormat.encode_city(city) == before, "drawing warnings leaves the full city payload unchanged")
	# Replacing a warned building must retire its cached icon immediately.
	city.stamp_building(HOUSE.x, HOUSE.y, Buildings.REINFORCED_BRIDGE)
	before = SaveFormat.encode_city(city)
	feedback.sync_power()
	check(feedback.power_warning_count() == 1, "3D removes a cached building warning when the cell becomes a bridge")
	check(SaveFormat.encode_city(city) == before, "replacement warning refresh leaves the city unchanged")
	city.stamp_building(HOUSE.x, HOUSE.y, Buildings.RES_1X1_FIRST)
	feedback.sync_power()
	check(feedback.power_warning_count() == 2,
		"3D restores the warning when an unpowered house replaces the bridge")
	feedback.queue_free()
	await process_frame
	await process_frame
