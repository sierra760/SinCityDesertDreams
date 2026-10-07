# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_subway_edits_invalidate_projection_but_pipe_edits_do_not() -> void:
	var city := flat_city()
	var view := CityView3D.new()
	view.city = city
	view._changed_regions(true)
	city.underground.put(20,20,Underground.subway_code(10))
	var changes := view._changed_regions(false)
	check(not changes.is_empty(),"new underground route raises geometry revision on refresh")
	check(not view._lot_regions.is_empty(),"neighbor stations reorient with new subway")
	city.underground.put(20,20,Underground.subway_code(5))
	check(not view._changed_regions(false).is_empty(),"in-place subway axis change invalidates")
	city.underground.put(20,20,0)
	check(not view._changed_regions(false).is_empty(),"removed subway invalidates existing train route")
	city.underground.put(20,20,Underground.pipe_code(10))
	check(view._changed_regions(false).is_empty(),"pipes do not change passenger or visible surface geometry")
	view.free()

func test_portal_region_signature_tracks_underground_neighbor_connections() -> void:
	var city := flat_city()
	city.building.put(20,20,Buildings.SUBWAY_PORTAL_FIRST)
	var region := Rect2i(16,16,16,16)
	var before := CityNetworks3D._network_inputs(city,region)
	city.underground.put(20,21,Underground.subway_code(5))
	var after := CityNetworks3D._network_inputs(city,region)
	check_ne(before,after,"portal orientation/connectors see added reciprocal underground track")
	city.underground.put(20,21,Underground.pipe_code(5))
	check_eq(before,CityNetworks3D._network_inputs(city,region),"water-only inputs keep same visible network signature")

func test_underground_snapshot_size_change_requires_full_refresh() -> void:
	var view := CityView3D.new()
	view.city = flat_city()
	view._changed_regions(true)
	view._geometry_state[7].resize(3)
	check_eq(view._changed_regions(false).size(),64,"short previous snapshot safely refreshes the whole city")
	view._geometry_state[7].resize(City.WIDTH*City.HEIGHT+1)
	check_eq(view._changed_regions(false).size(),64,"long previous snapshot safely refreshes the whole city")
	view.free()
