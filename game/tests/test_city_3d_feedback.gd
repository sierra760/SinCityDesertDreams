# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only utility feedback, independent of vehicle and incident visibility.
## Async teardown lets removed marker resources leave the tree before exit.
extends "res://tests/exploration/async_test_case.gd"


func test_power_feedback_is_read_only_and_independent() -> void:
	var city := City.new()
	TerrainSurface.new(4).project(city)
	city.stamp_building(30, 30, Buildings.RES_2X2_FIRST)
	city.stamp_building(32, 30, Buildings.RES_2X2_FIRST)
	city.stamp_building(40, 40, Buildings.ARCOLOGY_BOULDER)
	for anchor: Vector2i in [Vector2i(30, 30), Vector2i(32, 30), Vector2i(40, 40)]:
		_set_power(city, anchor, false)
	# A lone powered neighbor and a non-conductive building need no warning.
	city.stamp_building(50, 50, Buildings.RES_1X1_FIRST)
	_set_power(city, Vector2i(50, 50), true)
	city.stamp_building(51, 50, Buildings.RES_1X1_FIRST)
	city.set_flag(10, 10, TileFlags.CONDUCTS_POWER, true)
	var before := SaveFormat.encode_city(city)
	var catalog := CityModelCatalog.new()
	check(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json") == OK, "authored roof catalog loads")
	var feedback := CityFeedback3D.new()
	feedback.catalog = catalog
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([])
	check(feedback.power_warning_count() == 3, "one warning per unpowered canonical footprint")
	check(feedback.marker_count() == 0, "power warnings use a separate root from incidents and crews")
	var anchors: Dictionary = {}
	for warning: Sprite3D in feedback.power_markers.get_children():
		var anchor: Vector2i = warning.get_meta("cell")
		anchors[anchor] = true
		var code := city.building_at(anchor.x, anchor.y)
		var roof := CityGeometry3D.ground_height(city, anchor) + float(catalog.entries[code].height)
		check(warning.position.y - warning.texture.get_height() * warning.pixel_size * 0.5 > roof,
			"entire warning is above authored roof for %s" % anchor)
		check(warning.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not warning.shaded,
			"warning remains a readable camera-facing icon")
	check(anchors.has(Vector2i(30, 30)) and anchors.has(Vector2i(32, 30)), "touching equal-code lots remain distinct warnings")
	check(not anchors.has(Vector2i(50, 50)) and not anchors.has(Vector2i(51, 50)) and not anchors.has(Vector2i(10, 10)),
		"powered, non-conductive and empty cells do not warn")
	check(SaveFormat.encode_city(city) == before, "feedback leaves the full city payload unchanged")
	feedback.sync_records([{"kind": &"fire", "tile": Vector2i(20, 20)},
		{"kind": &"fire_crew", "tile": Vector2i(21, 20)}, {"kind": &"car", "pos": Vector2(22, 20)}])
	check(feedback.marker_count() == 2 and feedback.power_warning_count() == 3, "fire, crew and utility feedback coexist")
	check(feedback.traffic.multimesh != null, "vehicle feedback still works")
	feedback.sync_records([])
	check(feedback.power_warning_count() == 3 and feedback.traffic.multimesh == null,
		"vehicles-off empty records preserve power warnings")
	_set_power(city, Vector2i(30, 30), true)
	var powered_before := SaveFormat.encode_city(city)
	feedback.sync_records([])
	check(feedback.power_warning_count() == 2, "power restoration removes the affected warning")
	check(SaveFormat.encode_city(city) == powered_before, "power refresh is read-only")
	# A changed non-anchor flag must still invalidate the canonical lot warning.
	city.set_flag(31, 31, TileFlags.POWERED, false)
	feedback.sync_power()
	check(feedback.power_warning_count() == 3, "an unpowered far corner warns for its canonical lot")
	city.clear_footprint(40, 40)
	feedback.sync_power()
	check(feedback.power_warning_count() == 2, "demolition removes the old building warning")
	feedback.clear()
	check(feedback.power_warning_count() == 0 and feedback.marker_count() == 0, "clear removes every independent marker root")
	feedback.sync_power()
	check(feedback.power_warning_count() == 2, "clear invalidates cached power state")
	var replacement := City.new()
	TerrainSurface.new(7).project(replacement)
	replacement.stamp_building(60, 60, Buildings.RES_1X1_FIRST)
	_set_power(replacement, Vector2i(60, 60), false)
	var replacement_before := SaveFormat.encode_city(replacement)
	feedback.bind_city(replacement)
	check(feedback.power_warning_count() == 1, "rebind discards old city markers")
	var rebound := feedback.power_markers.get_child(0) as Sprite3D
	check(rebound.get_meta("cell") == Vector2i(60, 60), "rebound warning belongs to the new city")
	check(SaveFormat.encode_city(replacement) == replacement_before, "rebind does not mutate the new city")
	replacement.terrain.put(60, 60, Terrain.SURFACE)
	replacement.set_heights(60, 60, 7, 12)
	feedback.sync_power()
	var afloat := feedback.power_markers.get_child(0) as Sprite3D
	var water_roof := CityGeometry3D.surface_height(replacement, Vector2i(60, 60)) + float(catalog.entries[Buildings.RES_1X1_FIRST].height)
	check(afloat.position.y - afloat.texture.get_height() * afloat.pixel_size * 0.5 > water_roof,
		"warning follows the actual model surface height above water")
	feedback.bind_city(null)
	feedback.sync_records([])
	check(feedback.power_warning_count() == 0 and feedback.marker_count() == 0, "null rebind clears all feedback safely")
	feedback.queue_free()
	await process_frame
	await process_frame


func _set_power(city: City, anchor: Vector2i, powered: bool) -> void:
	var size := Buildings.size(city.building_at(anchor.x, anchor.y))
	for y: int in size.y:
		for x: int in size.x:
			city.set_flag(anchor.x + x, anchor.y + y, TileFlags.CONDUCTS_POWER, true)
			city.set_flag(anchor.x + x, anchor.y + y, TileFlags.POWERED, powered)
