# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A lot growth must not rebuild unchanged roads sharing its geometry chunk.
extends "res://tests/exploration/async_test_case.gd"
func test_lot_growth_keeps_unchanged_roads() -> void:
	var city := City.new()
	city.altitude.data.fill(4)
	city.stamp_building(8,8,Buildings.RES_1X1_FIRST)
	city.stamp_building(14,14,Buildings.RES_1X1_FIRST)
	city.building.put(10,8,30)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	check(view.networks._physical_cache.is_empty(),"aerial activation does not resolve unused traversal geometry")
	var before := view.traversal_snapshot()
	check(not before.networks.physical_floor_faces.is_empty(),"snapshot materializes complete network floor geometry on demand")
	var untouched_id := 0
	for lot: Node in view.buildings.get_children():
		if lot.get_meta("cell") == Vector2i(14,14): untouched_id = lot.get_instance_id()
	var old_network_id: int = view.networks._regions[Vector2i.ZERO].get_instance_id()
	var retained: Dictionary = before.networks.duplicate(true)
	city.building.data[8*City.WIDTH+8] = Buildings.RES_1X1_FIRST+1
	view.refresh()
	for lot: Node in view.buildings.get_children():
		if lot.get_meta("cell") == Vector2i(14,14): check(lot.get_instance_id() == untouched_id,"a distant lot in the same terrain chunk survives local growth")
	check(view.refresh_statistics.network_chunks == 0,"112-to113 growth does zero network chunk work even beside a road")
	check(view.networks._regions[Vector2i.ZERO].get_instance_id() == old_network_id,"mixed region road nodes survive unrelated building growth")
	check(not view.networks._physical_cache.is_empty(),"unchanged networks retain resolved physical cache")
	check(view.traversal_snapshot().networks == retained,"unchanged network snapshot remains exact")
	# Construction can rewrite zone and axis flags on a developed lot. Neither
	# contributes to the procedural network projection of a >=112 building.
	city.zone.put(8,8,Zones.CORNER_NW)
	city.flags.put(8,8,RotationMapper.AXIS_FLAG)
	view.refresh()
	check(view.refresh_statistics.network_chunks == 0,"lot corner/axis changes remain invisible to network projection")
	# Real network input changes still invalidate the region, but extraction is
	# lazy until requested by exploration; old handed-out snapshots stay valid.
	# A second connected road tile changes the physical lane geometry; an
	# isolated tile reshaped in place can leave every physical byte identical,
	# which retains the resolution (tests/test_network_physics_cache_retention.gd).
	city.building.put(11,8,30)
	view.refresh()
	check(view.refresh_statistics.network_chunks == 1,"actual road change rebuilds its one network region")
	check(view.networks._physical_cache.is_empty(),"aerial network edit defers traversal resolution")
	check(before.networks == retained,"previous returned snapshot survives cache invalidation")
	var after := view.traversal_snapshot()
	check(after.revision == before.revision+3,"lazy snapshot belongs to completed visual revision")
	check(not after.networks.physical_floor_faces.is_empty(),"edited network snapshot resolves fully on demand")
	var full := CityNetworks3D.new()
	full.rebuild(city)
	check(after.networks == full.physical_data(),"lazy regional physical projection equals original full projection")
	full.free()
	view.free()
	await process_frame
	await process_frame
