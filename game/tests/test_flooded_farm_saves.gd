# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

## A flood that reaches farmland must never leave the city unsaveable: a farm
## parcel may not keep a member under water, and saving validates every parcel.

const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost


func before_each() -> void:
	host = Fixture.make_host(self, "flooded-farm-saves")
	# Open water beside the farmland gives the flood a shore to rise from.
	var c := flat_city()
	for y in range(30, 60):
		for x in range(63, 70):
			c.terrain.put(x, y, Terrain.SUBMERGED)
	host.begin_city(c, {}, 5821, null)
	host.sim.set_process(false)
	host.sim.stats.disasters_enabled = false
	host.sim.city.funds = 1000000


func after_each() -> void:
	host.free()
	await process_frame


func paint(tool: int, a: Vector2i, b := Vector2i(-1, -1)) -> void:
	host.select_tool(tool)
	var result := host.handle_drag(a, a if b.x < 0 else b)
	check(result.get("applied", false), "real toolbar tool %d: %s" % [tool, result])


func build_serviced_farmland() -> void:
	paint(Tools.Kind.COAL_PLANT, Vector2i(32, 36))
	paint(Tools.Kind.POWER_LINE, Vector2i(36, 37), Vector2i(62, 37))
	paint(Tools.Kind.WATER_PUMP, Vector2i(38, 38))
	paint(Tools.Kind.WATER_PIPE, Vector2i(38, 39), Vector2i(62, 39))
	for x in [40, 44, 48, 52, 56, 60]:
		paint(Tools.Kind.WATER_PIPE, Vector2i(x, 39), Vector2i(x, 50))
		paint(Tools.Kind.POWER_LINE, Vector2i(x, 38), Vector2i(x, 39))
	paint(Tools.Kind.ROAD, Vector2i(39, 39), Vector2i(62, 39))
	paint(Tools.Kind.ROAD, Vector2i(39, 40), Vector2i(39, 50))
	paint(Tools.Kind.ZONE_AGR_LOW, Vector2i(40, 40), Vector2i(60, 42))
	paint(Tools.Kind.ZONE_AGR_LOW, Vector2i(40, 43), Vector2i(44, 49))


func save_now() -> Error:
	var path := OS.get_user_data_dir().path_join("flooded-farm.sc2d")
	return SaveFormat.save(path, host.sim.city, host.sim.snapshot(), SaveFormat.STAGE_PLAY, {}, {})


func owned_tiles_under_water() -> int:
	var city := host.sim.city
	var wet := 0
	for t: Vector2i in city.flood_overlay:
		if city.agricultural_parcels.id_at(t) != 0: wet += 1
	return wet


func test_city_saves_on_every_day_of_a_flood_over_farmland() -> void:
	build_serviced_farmland()
	var ag := host.sim.get_system(&"agriculture") as AgricultureSystem
	host.sim.advance_days(70)
	var farmed_before := 0
	for r in ag.current_parcels(): farmed_before += r.members.size()
	check_gt(farmed_before, 0, "farms formed beside the water")
	check_eq(save_now(), OK, "the city saves before the flood")
	var disasters := host.sim.get_system(&"disasters") as DisasterSystem
	check(disasters.request(host.sim._ctx, &"major_flood", Vector2i(62, 41)), "the flood starts")
	check_eq(save_now(), OK, "the city saves on the day the flood starts")
	var failed := 0
	var reached_farmland := false
	var farmed_least := farmed_before
	for day in 70:
		host.sim.advance_days(1)
		var farmed_now := 0
		for r in ag.current_parcels(): farmed_now += r.members.size()
		farmed_least = mini(farmed_least, farmed_now)
		for t: Vector2i in host.sim.city.flood_overlay:
			if t.x >= 40 and t.x <= 60 and t.y >= 40 and t.y <= 42: reached_farmland = true
		check_eq(owned_tiles_under_water(), 0, "no parcel keeps a member under water")
		if save_now() != OK: failed += 1
	check(reached_farmland, "the flood reached the farmland")
	check_eq(failed, 0, "the city saves on every day of the flood")
	check_eq(host.sim.city.flood_overlay.size(), 0, "the flood receded")
	# Farming may return to the rubble once the water is gone.
	check_lt(farmed_least, farmed_before, "flooded cells left their parcels")
