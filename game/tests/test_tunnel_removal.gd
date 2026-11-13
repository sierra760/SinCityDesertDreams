# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## A road tunnel is one structure: whatever removes a portal removes the
## bore and the far portal with it, so the hill can be tunnelled, levelled
## and built on again.

const DIR := "user://test_tunnel_removal"
const ENTRANCE := Vector2i(39, 40)
const EXIT := Vector2i(43, 40)

var _contexts: Array[SimContext] = []


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)


func after_each() -> void:
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


## A flat city with a three-tile ridge on row 40 and straight slopes at
## both ends, ready for a tunnel from ENTRANCE to EXIT.
func _ridge_city() -> City:
	var c := flat_city(100000)
	c.founded_year = 2000
	for x in range(40, 43):
		c.set_heights(x, 40, 6)
	c.terrain.put(ENTRANCE.x, ENTRANCE.y, Terrain.SLOPE_E)
	c.terrain.put(EXIT.x, EXIT.y, Terrain.SLOPE_W)
	return c


func _bored(c: City) -> Builder:
	var b := Builder.new(c, CityStats.new())
	var r := b.apply(Tools.Kind.TUNNEL, ENTRANCE, Vector2i(-1, -1), {"choice": &"tunnel"})
	check(bool(r["applied"]), "the fixture tunnel is built: %s" % r["reason"])
	check(NetworkShapes.is_tunnel(c.building_at(ENTRANCE.x, ENTRANCE.y)))
	check(NetworkShapes.is_tunnel(c.building_at(EXIT.x, EXIT.y)))
	return b


func _marked(c: City) -> int:
	var n := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if c.tunnel_bits(x, y) != 0:
				n += 1
	return n


func _portals(c: City) -> int:
	var n := 0
	for id in c.building.data:
		if NetworkShapes.is_tunnel(id):
			n += 1
	return n


## The hill is usable again: a new tunnel is quoted and the land may move.
func _check_recovered(b: Builder) -> void:
	var c := b.city
	check_eq(_marked(c), 0, "no bore is left behind")
	check_eq(_portals(c), 0, "both portals are gone")
	var again := b.preview(Tools.Kind.TUNNEL, ENTRANCE)
	check(bool(again["ok"]), "the tunnel can be rebuilt: %s" % again["reason"])
	var level := b.preview(Tools.Kind.LOWER_LAND, Vector2i(41, 40))
	check(bool(level["ok"]), "the hill can be reshaped: %s" % level["reason"])


func test_demolition_removes_the_whole_tunnel() -> void:
	var c := _ridge_city()
	var b := _bored(c)
	check_eq(_marked(c), 5)
	var quote := b.preview(Tools.Kind.BULLDOZE, EXIT)
	var funds := c.funds
	var r := b.apply(Tools.Kind.BULLDOZE, EXIT)
	check(bool(r["applied"]), r["reason"])
	check_eq(int(r["cost"]), 5)
	check_eq(int(quote["cost"]), int(r["cost"]), "preview and charge agree")
	check_eq(funds - c.funds, 5)
	_check_recovered(b)


func test_unfunded_wear_takes_the_whole_tunnel() -> void:
	var c := _ridge_city()
	var b := _bored(c)
	var ctx := make_context(c, 12345)
	_contexts.append(ctx)
	ctx.clock.founded_year = c.founded_year
	var wear := WearSystem.new()
	ctx.systems[wear.key] = wear
	wear.setup(ctx)
	ctx.stats.set_funding(&"tunnels", 0)
	var funds := c.funds
	var months := 0
	while int(wear.losses()[&"tunnels"]) == 0 and months < 5000:
		ctx.events.clear()
		wear.monthly(ctx)
		months += 1
	check_eq(int(wear.losses()[&"tunnels"]), 2, "both mouths are lost together")
	check_eq(int(wear.network_counts()[&"tunnels"]), 0)
	check(Buildings.is_rubble(c.building_at(ENTRANCE.x, ENTRANCE.y)), "rubble at one mouth")
	check(Buildings.is_rubble(c.building_at(EXIT.x, EXIT.y)), "rubble at the other")
	check_eq(c.funds, funds, "a collapse charges nothing")
	_check_recovered(b)


func test_disaster_takes_the_whole_tunnel() -> void:
	var c := _ridge_city()
	var b := _bored(c)
	var ctx := make_context(c, 41)
	_contexts.append(ctx)
	ctx.clock.day = c.day
	var disasters := DisasterSystem.new()
	ctx.systems = {&"disasters": disasters}
	disasters.setup(ctx)
	var funds := c.funds
	check(disasters.request(ctx, &"plane_crash", ENTRANCE))
	for _day in 40:
		ctx.events.clear()
		disasters.daily(ctx)
		ctx.clock.advance()
		c.day = ctx.clock.day
	check(not NetworkShapes.is_tunnel(c.building_at(ENTRANCE.x, ENTRANCE.y)), "the struck portal is wrecked")
	check_eq(c.funds, funds, "a collapse charges nothing")
	_check_recovered(b)


func test_loading_unmarks_a_bore_that_lost_a_portal() -> void:
	var c := _ridge_city()
	_bored(c)
	# A second, intact tunnel on another ridge.
	for x in range(40, 43):
		c.set_heights(x, 60, 6)
	c.terrain.put(39, 60, Terrain.SLOPE_E)
	c.terrain.put(43, 60, Terrain.SLOPE_W)
	var b := Builder.new(c, CityStats.new())
	check(bool(b.apply(Tools.Kind.TUNNEL, Vector2i(39, 60), Vector2i(-1, -1), {"choice": &"tunnel"})["applied"]))
	# What an earlier version left after a disaster: rubble at one mouth, the
	# bore still marked.
	c.building.put(ENTRANCE.x, ENTRANCE.y, Buildings.RUBBLE_1)
	check_eq(_marked(c), 10)
	var path := DIR + "/orphan.sc2d"
	check_eq(SaveFormat.save(path, c), OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded["ok"]), String(loaded["error"]))
	var restored: City = loaded["city"]
	check_eq(_marked(restored), 5, "only the intact tunnel stays marked")
	for x in range(39, 44):
		check_eq(restored.tunnel_bits(x, 40), 0, "orphan bore at %d" % x)
		check_ne(restored.tunnel_bits(x, 60), 0, "intact bore at %d" % x)
	check(NetworkShapes.is_tunnel(restored.building_at(EXIT.x, EXIT.y)), "the surviving portal stays for the player to clear")
	var rebuilt := Builder.new(restored, CityStats.new())
	check(bool(rebuilt.apply(Tools.Kind.BULLDOZE, EXIT)["applied"]))
	var again := rebuilt.preview(Tools.Kind.TUNNEL, ENTRANCE)
	check(bool(again["ok"]), "the tunnel can be rebuilt: %s" % again["reason"])
	# Saving and loading the repaired city changes nothing further.
	check_eq(SaveFormat.save(path, restored), OK)
	var second: City = SaveFormat.load(path)["city"]
	check(second.altitude.data == restored.altitude.data)
	check(second.building.data == restored.building.data)


func test_loading_keeps_every_bore_of_an_included_city() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Silver Ridge.sc2d")
	check(bool(loaded["ok"]), String(loaded["error"]))
	var c: City = loaded["city"]
	check_eq(_portals(c), 6)
	check_eq(_marked(c), 112)
	check_eq(c.clear_orphan_tunnels(), 0)


func test_a_long_tunnel_is_removed_whole() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Silver Ridge.sc2d")
	var c: City = loaded["city"]
	c.funds = 100000
	var b := Builder.new(c, CityStats.new())
	check(NetworkShapes.is_tunnel(c.building_at(20, 30)))
	check(NetworkShapes.is_tunnel(c.building_at(79, 30)))
	var quote := b.preview(Tools.Kind.BULLDOZE, Vector2i(20, 30))
	var r := b.apply(Tools.Kind.BULLDOZE, Vector2i(20, 30))
	check(bool(r["applied"]), r["reason"])
	check_eq(int(r["cost"]), 60)
	check_eq(int(quote["cost"]), 60)
	check(not NetworkShapes.is_tunnel(c.building_at(79, 30)), "the far portal goes too")
	for x in range(20, 80):
		check_eq(c.tunnel_bits(x, 30), 0, "bore at %d" % x)
	check_eq(_portals(c), 4, "the other tunnels stand")


func test_an_exit_cannot_open_onto_another_bore() -> void:
	var c := flat_city(1000000)
	c.founded_year = 2000
	for y in range(20, 51):
		for x in range(20, 41):
			c.set_heights(x, y, 5)
	for y in range(30, 46):
		for x in range(25, 36):
			c.set_heights(x, y, 6)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			Builder.refresh_shape(c, x, y)
	var b := Builder.new(c, CityStats.new())
	# One tunnel runs east-west along row 29, at the foot of the inner hill.
	var first := b.apply(Tools.Kind.TUNNEL, Vector2i(19, 29), Vector2i(-1, -1), {"choice": &"tunnel"})
	check(bool(first["applied"]), first["reason"])
	check_ne(c.tunnel_bits(30, 29), 0)
	# A second one through the inner hill would come out on that bore.
	var funds := c.funds
	var second := b.apply(Tools.Kind.TUNNEL, Vector2i(30, 46), Vector2i(-1, -1), {"choice": &"tunnel"})
	check(not bool(second["ok"]))
	check_eq(second["reason"], "another tunnel is in the way")
	check_eq(c.funds, funds, "a refusal charges nothing")
	check_eq(c.building_at(30, 29), Buildings.NONE)
	check_eq(c.tunnel_cells(19, 29).size(), 23, "the first tunnel is whole")


func test_a_pipe_passes_under_a_portal() -> void:
	var c := _ridge_city()
	var b := Builder.new(c, CityStats.new())
	check(bool(b.apply(Tools.Kind.WATER_PIPE, Vector2i(39, 38), Vector2i(39, 42))["applied"]))
	var pipe := c.underground.at(ENTRANCE.x, ENTRANCE.y)
	check_ne(pipe, 0)
	var r := b.apply(Tools.Kind.TUNNEL, ENTRANCE, Vector2i(-1, -1), {"choice": &"tunnel"})
	check(bool(r["applied"]), r["reason"])
	check_eq(c.underground.at(ENTRANCE.x, ENTRANCE.y), pipe, "the pipe is kept")
	check(c.conducts_water(ENTRANCE.x, ENTRANCE.y))
	# Subway track still refuses a portal.
	var d := _ridge_city()
	var e := Builder.new(d, CityStats.new())
	check(bool(e.apply(Tools.Kind.SUBWAY, Vector2i(39, 38), Vector2i(39, 42))["applied"]))
	var refused := e.preview(Tools.Kind.TUNNEL, ENTRANCE)
	check(not bool(refused["ok"]))
	check_eq(refused["reason"], "blocked underground")
