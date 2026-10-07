# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Network regions rebuilt for visual-only changes keep the resolved physical geometry.
extends "res://tests/exploration/async_test_case.gd"
func _patch_bytes(networks: CityNetworks3D) -> Array:
	return [networks._physical_cells, networks._physical_groups, networks._physical_roles, networks._physical_depths, networks._physical_triangles, networks._physical_boxes, networks._physical_obstacles]
func test_visual_only_rebuilds_keep_resolved_physics() -> void:
	# Synthetic: an isolated road reshaped in place emits identical physical bytes.
	var city := City.new()
	city.altitude.data.fill(4)
	city.building.put(10, 8, 30)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var before := view.traversal_snapshot()
	check(not view.networks._physical_cache.is_empty(), "snapshot resolves the network physics")
	var bytes := _patch_bytes(view.networks).duplicate(true)
	city.building.put(10, 8, 31)
	view.refresh()
	check(view.refresh_statistics.network_chunks == 1, "the reshaped road rebuilds its region")
	var same := _patch_bytes(view.networks) == bytes
	check(same == not view.networks._physical_cache.is_empty(), "the resolution is retained exactly when every physical byte is identical")
	if same: check(view.traversal_snapshot().networks == before.networks, "a retained resolution equals the previous snapshot")
	city.building.put(11, 8, 30)
	view.refresh()
	check(_patch_bytes(view.networks) != bytes and view.networks._physical_cache.is_empty(), "changed physical bytes release the resolution")
	view.queue_free()
	await process_frame
	# Real city: planting and clearing palms rebuilds regions without physical change.
	var loaded := Sc2Import.load("res://assets/cities/Foothills Ranch.sc2")
	check(loaded.ok, "Foothills Ranch imports")
	var real: City = loaded.city
	view = CityView3D.new()
	root.add_child(view)
	view.bind_city(real)
	view.set_active(true)
	var resolved: Dictionary = view.traversal_snapshot().networks.duplicate(true)
	var planted := 0
	for y: int in range(10, 118, 3):
		for x: int in range(10, 118, 3):
			if planted >= 60: break
			if real.building.at(x, y) == Buildings.NONE and not real.is_water(x, y):
				real.building.put(x, y, Buildings.TREES_1)
				planted += 1
	check(planted > 20, "palms were planted on empty ground")
	view.refresh()
	check(view.refresh_statistics.network_chunks > 0, "planting rebuilds network regions")
	check(not view.networks._physical_cache.is_empty(), "palm-only rebuilds keep the resolved physics")
	var after: Dictionary = view.traversal_snapshot().networks
	check(after == resolved, "the retained resolution equals the complete previous one")
	view.networks._physical_cache = {}
	var fresh: Dictionary = view.traversal_snapshot().networks
	check(fresh == resolved, "a forced fresh resolution of the same bytes is identical")
	view.queue_free()
	await process_frame
