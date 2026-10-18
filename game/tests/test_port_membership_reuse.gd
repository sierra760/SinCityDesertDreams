# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const PortSystem := preload("res://scripts/sim/port_system.gd")

func _fixture() -> City:
	var city := flat_city()
	for y in range(20, 25):
		for x in range(30, 35):
			city.zone.put(x, y, Zones.make(Zones.AIRPORT))
			city.set_flag(x, y, TileFlags.POWERED, true)
	for x in range(30, 35): city.building.put(x, 20, Buildings.RUNWAY)
	city.building.put(29, 24, Buildings.ROAD_FIRST)
	return city

func _matches_cold(ports: PortSystem, city: City, label: String) -> void:
	var cold := PortSystem.new()
	cold.setup(make_context(city))
	check_eq(ports.port_report(), cold.port_report(), label + " report")
	check_eq(ports._ports, cold._ports, label + " canonical membership and piece order")
	check_eq(ports.demand_bonus(), cold.demand_bonus(), label + " demand")
	check_eq(ports.jobs(), cold.jobs(), label + " jobs")
	check_eq(ports.tourism_gateways(), cold.tourism_gateways(), label + " gateways")

func test_service_and_building_updates_reuse_zone_membership_but_recount_pieces() -> void:
	var city := _fixture()
	var ports := PortSystem.new()
	ports.setup(make_context(city))
	check(ports.port_report()[0].operating, "powered complete runway opens airport")
	var tiles: Array = ports._ports[0].tiles
	var tile_set: Dictionary = ports._ports[0].tile_set
	city.flags.data.fill(0)
	check(not ports.port_report()[0].operating, "raw power loss closes airport")
	check(is_same(ports._ports[0].tiles, tiles), "power refresh retains completed zone grouping")
	check(is_same(ports._ports[0].tile_set, tile_set), "power refresh retains membership lookup")
	_matches_cold(ports, city, "power loss")
	city.building.put(32, 20, Buildings.NONE)
	check_eq(ports.port_report()[0].runways, 0, "raw runway cut is recounted")
	check(is_same(ports._ports[0].tiles, tiles), "building refresh retains completed zone grouping")
	_matches_cold(ports, city, "runway damage")
	ports.networks_changed(make_context(city), Rect2i(1, 1, 1, 1))
	ports._rebuild_ports(city)
	check(is_same(ports._ports[0].tiles, tiles), "explicit invalidation recounts without regrouping unchanged zones")
	_matches_cold(ports, city, "explicit invalidation")

func test_raw_zone_split_and_join_rebuild_in_the_original_traversal_order() -> void:
	var city := _fixture()
	var ports := PortSystem.new()
	ports.setup(make_context(city))
	ports.port_report()
	for y in range(20, 25): city.zone.data[y * City.WIDTH + 32] = Zones.NONE
	check_eq(ports.port_report().size(), 2, "raw cut splits the airport")
	_matches_cold(ports, city, "split")
	for y in range(20, 25): city.zone.data[y * City.WIDTH + 32] = Zones.make(Zones.AIRPORT, Zones.CORNER_SE)
	check_eq(ports.port_report().size(), 1, "raw fill rejoins the airport")
	_matches_cold(ports, city, "join with corner bytes")
	city.zone.data.fill(Zones.NONE)
	check_eq(ports.port_report().size(), 0, "removing all zones drops cached ports")
	_matches_cold(ports, city, "empty")

func test_equal_geometry_rebind_and_saved_state_refresh_recount_live_inputs() -> void:
	var city := _fixture()
	var ports := PortSystem.new()
	ports.setup(make_context(city))
	ports.port_report()
	var next := _fixture()
	next.flags.data.fill(0)
	ports.setup(make_context(next))
	check(not ports.port_report()[0].operating, "rebind reads the new city's services")
	_matches_cold(ports, next, "new owner")
	var snapshot := ports.save()
	for y in range(20, 25):
		for x in range(30, 35): next.set_flag(x, y, TileFlags.POWERED, true)
	ports.load(snapshot)
	check(ports.port_report()[0].operating, "load invalidation reads current power")
	_matches_cold(ports, next, "load")
	check_eq(ports.save(), snapshot, "read-only port refresh leaves vehicles and earned openings unchanged")

func test_crane_growth_regroups_even_when_piers_were_already_zoned() -> void:
	var city := flat_city()
	for y in range(20, 25):
		for x in range(38, 40 + PortParams.PIER_LENGTH):
			city.zone.put(x, y, Zones.make(Zones.SEAPORT))
			city.set_flag(x, y, TileFlags.POWERED, true)
	for y in City.HEIGHT:
		for x in range(40, City.WIDTH):
			city.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			city.set_heights(x, y, 2, 4)
	var ctx := make_context(city)
	var ports := PortSystem.new()
	ports.setup(ctx)
	ports.port_report()
	var zones := city.zone.data.duplicate()
	check(ports._place_crane(ctx, ports._ports[0], Vector2i(39, 22)), "a shore crane extends over already zoned water")
	check_eq(city.zone.data, zones, "pier growth can leave the zone bytes unchanged")
	ports._rebuild_ports(city)
	var report := ports.port_report()[0]
	check_eq(report.tiles, 30, "monthly regroup removes temporary duplicate pier members")
	check_eq(report.developed, 5, "one crane and four piers are counted once")
	check_eq(report.jobs, 60, "duplicate members cannot inflate port jobs")
	_matches_cold(ports, city, "already zoned pier growth")
