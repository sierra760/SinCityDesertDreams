# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
func test_feedback_reuses_unchanged_markers() -> void:
	var city := City.new()
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([{ "pos": Vector2(10, 10) }])
	var batch := feedback.traffic.multimesh
	var mesh := batch.mesh
	feedback.sync_records([{ "pos": Vector2(11, 10), "heading": 2, "altitude": 3 }])
	check(feedback.traffic.multimesh == batch, "moving vehicles reuse GPU instance storage")
	check(feedback.traffic.multimesh.mesh == mesh, "moving vehicles reuse geometry and material")
	# Dummy headless RenderingServer does not retain get_instance_transform;
	# inspect the actual packed upload rather than renderer readback.
	var buffer := feedback._traffic_buffer
	check(is_equal_approx(buffer[3], 11.5), "reused buffer receives current position")
	check(is_equal_approx(buffer[7], 0.13 + 3 * CityGeometry3D.HEIGHT), "altitude updates")
	check(is_equal_approx(buffer[0], 0.0) and is_equal_approx(buffer[2], 1.0) and is_equal_approx(buffer[8], -1.0), "heading updates")
	feedback.sync_records([{ "pos": Vector2(12, 10) }, { "pos": Vector2(13, 10) }])
	check(feedback.traffic.multimesh == batch and batch.mesh == mesh, "growth retains resources")
	check(batch.visible_instance_count == 2, "growth exposes both live instances")
	feedback.sync_records([{ "pos": Vector2(14, 10) }, { "pos": Vector2(NAN, 1) }])
	check(batch.visible_instance_count == 1, "shrink and invalid records hide old instances")
	feedback.sync_records([])
	check(feedback.traffic.multimesh == null, "empty record contract stays null")
	feedback.sync_records([{ "pos": Vector2(15, 10) }])
	check(feedback.traffic.multimesh == batch, "zero-to-nonzero reuses allocated buffer")
	city.stamp_building(20, 20, Buildings.RES_1X1_FIRST)
	var i := 20 * City.WIDTH + 20
	city.flags.data[i] = TileFlags.CONDUCTS_POWER
	feedback.sync_power()
	check(feedback.power_warning_count() == 1, "raw flag writes create warnings from zero")
	var warning := feedback.power_markers.get_child(0)
	city.altitude.data[0] = 5
	feedback.sync_power()
	check(feedback.power_markers.get_child(0) == warning, "unrelated terrain edits preserve existing warning nodes")
	# Per-frame runtime syncs share one hash per layer and rehash the catalog
	# only after it reloads; reloading still re-places the warning.
	var catalog := CityModelCatalog.new()
	check(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json") == OK, "catalog loads")
	feedback.catalog = catalog
	feedback.sync_records([])
	var placed: Vector3 = feedback.power_markers.get_child(0).position
	var catalog_key: Array = feedback._catalog_key
	feedback.sync_records([])
	check(feedback._catalog_key == catalog_key, "an unchanged catalog keeps its cached signature")
	city.altitude.data[20 * City.WIDTH + 20] = 9
	feedback.sync_records([])
	check(feedback.power_markers.get_child(0).position.y > placed.y, "raw terrain writes still move the warning")
	catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json")
	feedback.sync_records([])
	check(feedback._catalog_key != catalog_key, "a reloaded catalog is signed again")
	city.altitude.data[20 * City.WIDTH + 20] = 0
	city.flags.data[i] |= TileFlags.POWERED
	feedback.sync_power()
	check(feedback.power_warning_count() == 0, "raw power restoration clears warnings")
	feedback.catalog = null
	feedback.clear()
	feedback.sync_records([{ "pos": Vector2(16, 10) }])
	check(feedback.traffic.multimesh == batch, "clear retains reusable resources")
	feedback.queue_free()
	await process_frame
	await process_frame
