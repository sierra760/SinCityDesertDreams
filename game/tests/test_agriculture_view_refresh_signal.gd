# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

## A farm rebuilt inside a view refresh joins that refresh's batch pass; its
## listeners hear one geometry signal after networks and batches are current.
func test_farm_rebuilt_during_refresh_emits_geometry_once_at_the_end() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	var members := F.square(3)
	F.zone(city,members)
	check_eq(city.agricultural_parcels.put(city,F.record(1,members,&"cattle_range",&"active")),OK)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	await process_frame
	view.refresh()
	await process_frame
	var emissions: Array = []
	var statistics: Array = []
	view.geometry_rebuilt.connect(func(revision: int) -> void:
		emissions.append(revision)
		statistics.append(view.refresh_statistics.duplicate()))
	var previous := view.refresh_statistics.duplicate()
	var node_before: int = view.agriculture.record_for_parcel(1).node.get_instance_id()
	city.terrain_surface.set_vertex(21,21,6)
	view.refresh()
	check(view.agriculture.record_for_parcel(1).node.get_instance_id() != node_before,"the terrain edit rebuilds the farm")
	check_eq(emissions.size(),1,"one refresh emits geometry_rebuilt once")
	if not statistics.is_empty():
		check(statistics[0] != previous,"listeners see the completed refresh")
	view.free()
