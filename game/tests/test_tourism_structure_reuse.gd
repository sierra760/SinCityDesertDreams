# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

## Reusing a classified surface must still refresh gateways and detect raw
## network writes. Compare warm access with an independent cold discovery.
func _fixture() -> SimContext:
	var city := flat_city()
	for x in range(35): city.building.put(x, 24, Buildings.ROAD_FIRST)
	TourismFixture.venue(city, &"arcology_boddy", Vector2i(20, 25))
	for y in range(19, 24):
		for x in range(30, 35):
			city.zone.put(x, y, Zones.make(Zones.AIRPORT))
			city.set_flag(x, y, TileFlags.POWERED, true)
	for x in range(30, 35): city.building.put(x, 19, Buildings.RUNWAY)
	return make_context(city)

func _matches_cold(access: TourismAccess, ctx: SimContext, label: String) -> void:
	var cold := TourismAccess.new()
	cold.refresh(ctx)
	check_eq(access._graph, cold._graph, label + " graph")
	check_eq(access._graph.keys(), cold._graph.keys(), label + " graph order")
	check_eq(access._reverse, cold._reverse, label + " reverse edges")
	check_eq(access._component, cold._component, label + " components")
	check_eq(access._dag, cold._dag, label + " component edges")
	check_eq(access._resident_states, cold._resident_states, label + " residents")
	check_eq(access._venues, cold._venues, label + " venue access")
	check_eq(access.gateways(), cold.gateways(), label + " gateway service")
	var actual := access.report()
	var expected := cold.report()
	check_eq(actual.keys(), expected.keys(), label + " report schema")
	for key in ["graph_states", "graph_edges", "pending_sources", "gateway_count", "arrival_capacity"]:
		check_eq(actual[key], expected[key], label + " " + key)

func _airport_count(access: TourismAccess) -> int:
	var count := 0
	for gateway in access.gateways():
		if gateway.kind == "airport": count += 1
	return count

func test_service_and_ground_changes_keep_structure_and_refresh_gateways() -> void:
	var ctx := _fixture()
	var access := TourismAccess.new()
	access.refresh(ctx)
	_matches_cold(access, ctx, "initial")
	check_eq(_airport_count(access), 1, "fixture has an operating airport")
	var version := access.version
	for y in range(19, 24):
		for x in range(30, 35): ctx.city.flags.data[y * City.WIDTH + x] &= ~TileFlags.POWERED
	access.refresh(ctx)
	check_eq(_airport_count(access), 0, "raw service loss closes the airport")
	_matches_cold(access, ctx, "flags")
	check_eq(access.version, version + 2, "service refresh retains layer and closure version increments")
	ctx.city.terrain.data[20 * City.WIDTH + 40] = Terrain.make(Terrain.FLAT, Terrain.SURFACE)
	access.refresh(ctx)
	_matches_cold(access, ctx, "terrain")
	check_eq(access.version, version + 4, "terrain refresh retains version increments")
	ctx.city.flood_overlay[Vector2i(31, 20)] = true
	access.refresh(ctx)
	_matches_cold(access, ctx, "flood")
	check_eq(access.version, version + 6, "flood refresh retains version increments")
	# This historical counter counts layer refreshes, including unchanged topology.
	check_eq(access.report().graph_builds, 4, "layer refresh counter retains its meaning")
	access.refresh(ctx)
	check_eq(access.version, version + 6, "unchanged refresh preserves version")

func test_raw_network_edits_and_city_rebind_refuse_stale_structure() -> void:
	var ctx := _fixture()
	var access := TourismAccess.new()
	access.refresh(ctx)
	var builds := int(access.report().graph_builds)
	var version := access.version
	ctx.city.building.data[24 * City.WIDTH + 12] = Buildings.NONE
	access.refresh(ctx)
	_matches_cold(access, ctx, "raw road cut")
	check_eq(access.report().graph_builds, builds + 1, "raw road edit rebuilds")
	check_gt(access.version, version, "raw road edit advances version")
	ctx.city.altitude.data[24 * City.WIDTH + 12] |= 1 << City.TUNNEL_SHIFT
	access.refresh(ctx)
	_matches_cold(access, ctx, "raw tunnel")
	check_eq(access.report().graph_builds, builds + 2, "raw tunnel edit rebuilds")
	ctx.city.underground.data[24 * City.WIDTH + 12] = NetworkShapes.SUBWAY_FIRST
	access.refresh(ctx)
	_matches_cold(access, ctx, "raw subway")
	check_eq(access.report().graph_builds, builds + 3, "raw subway edit rebuilds")
	# Different city, byte-identical layers: the cache still belongs to its city.
	var rebound := _fixture()
	rebound.city.building.data = ctx.city.building.data.duplicate()
	rebound.city.altitude.data = ctx.city.altitude.data.duplicate()
	rebound.city.underground.data = ctx.city.underground.data.duplicate()
	access.refresh(rebound)
	_matches_cold(access, rebound, "city rebind")
	check_eq(access.report().graph_builds, builds + 4, "new city rebuilds")
