# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The player-facing construction flow: bridge and tunnel quotes, links to
## the neighboring towns, citizen objections, tree protests, facility
## queries with rename, signs, and the text of every notice kind.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")

var host: GameHost


func after_each() -> void:
	if host != null:
		host.sim._ctx.systems.clear()
		host.sim.systems.clear()
		root.remove_child(host)
		host.free()
		host = null


func _builder(funds: int = 20000) -> Builder:
	var c := flat_city(funds)
	c.founded_year = 2000
	return Builder.new(c, CityStats.new())


func _water_row(c: City, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		c.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		c.set_heights(x, y, c.ground_height(x, y), c.ground_height(x, y))


func _hill(c: City, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		c.set_heights(x, y, 6)
	c.terrain.put(x0 - 1, y, Terrain.SLOPE_E)
	c.terrain.put(x1 + 1, y, Terrain.SLOPE_W)


func _keys(choices: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in choices:
		out.append(StringName(String(entry["key"])))
	return out


## A host running a flat city founded in 2000 with the given funds.
func _host_city(funds: int = 20000) -> City:
	host = MainScene.instantiate()
	root.add_child(host)
	var city := flat_city(funds)
	city.founded_year = 2000
	host.start_new_city({"name": "Flowtown", "seed": 9, "founded_year": 2000}, city)
	host.found_city()
	city.funds = funds
	return city


# ── Bridges and tunnels ──────────────────────────────────────────────────

func test_short_water_gap_offers_a_causeway_and_builds_it() -> void:
	var b := _builder()
	var c := b.city
	_water_row(c, 10, 12, 14)
	var p := b.preview(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(16, 10))
	check(p["ok"], p["reason"])
	check(bool(p.get("needs_confirmation", false)), "a water crossing asks first")
	check_eq(p.get("choice_kind"), &"bridge")
	check_eq(p.get("span"), 3)
	var keys := _keys(p["choices"])
	check(keys.has(&"causeway"), "causeway offered for a short gap")
	check(keys.has(&"suspension"), "suspension always offered")
	for entry in p["choices"]:
		if entry["key"] == &"causeway":
			check_eq(entry["cost"], 4 * 10 + 3 * Builder.BRIDGE_COST_CAUSEWAY)
		else:
			check_eq(entry["cost"], 4 * 10 + 3 * Builder.BRIDGE_COST_SUSPENSION)
	check_eq(c.funds, 20000, "a preview charges nothing")
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(16, 10), {"choice": &"causeway"})
	check(r["ok"] and r["applied"])
	check_eq(r["cost"], 4 * 10 + 3 * Builder.BRIDGE_COST_CAUSEWAY)
	for x in range(12, 15):
		check_eq(c.building_at(x, 10), Buildings.id_of(&"bridge_causeway_pylon"), "causeway at %d" % x)
	check_eq(c.funds, 20000 - int(r["cost"]))
	# The same short gap takes a suspension bridge when the player asks for one.
	_water_row(c, 20, 12, 14)
	var s := b.apply(Tools.Kind.ROAD, Vector2i(10, 20), Vector2i(16, 20), {"choice": &"suspension"})
	check(s["ok"], s["reason"])
	check_eq(s["cost"], 4 * 10 + 3 * Builder.BRIDGE_COST_SUSPENSION)
	check_eq(c.building_at(12, 20), Buildings.id_of(&"bridge_suspension_start"))
	check_eq(c.building_at(14, 20), Buildings.id_of(&"bridge_suspension_end"))


func test_long_gap_offers_only_a_suspension_bridge() -> void:
	var b := _builder()
	var c := b.city
	_water_row(c, 30, 12, 19)
	var p := b.preview(Tools.Kind.ROAD, Vector2i(10, 30), Vector2i(21, 30))
	check(p["ok"], p["reason"])
	check_eq(p.get("choice_kind"), &"bridge")
	var keys := _keys(p["choices"])
	check(not keys.has(&"causeway"), "eight tiles is too far for a causeway")
	check_eq(keys, [&"suspension"] as Array[StringName])
	var refused := b.preview(Tools.Kind.ROAD, Vector2i(10, 30), Vector2i(21, 30), {"choice": &"causeway"})
	check(not refused["ok"], "an impossible choice is refused")
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 30), Vector2i(21, 30), {"choice": &"suspension"})
	check(r["ok"] and r["applied"])
	check_eq(c.building_at(15, 30), Buildings.id_of(&"bridge_suspension_span"))
	# Rail gets its own bridge; a power line its elevated span.
	_water_row(c, 40, 12, 14)
	var rail := b.preview(Tools.Kind.RAIL, Vector2i(10, 40), Vector2i(16, 40))
	check_eq(_keys(rail["choices"]), [&"rail"] as Array[StringName])
	var power := b.preview(Tools.Kind.POWER_LINE, Vector2i(10, 40), Vector2i(16, 40))
	check_eq(_keys(power["choices"]), [&"elevated"] as Array[StringName])
	var built := b.apply(Tools.Kind.RAIL, Vector2i(10, 40), Vector2i(16, 40), {"choice": &"rail"})
	check(built["ok"])
	check_eq(c.building_at(13, 40), Buildings.id_of(&"bridge_rail_span"))


func test_tunnel_quotes_its_length_and_cost() -> void:
	var b := _builder()
	var c := b.city
	_hill(c, 40, 40, 42)
	var p := b.preview(Tools.Kind.TUNNEL, Vector2i(39, 40))
	check(p["ok"], p["reason"])
	check(bool(p.get("needs_confirmation", false)))
	check_eq(p.get("choice_kind"), &"tunnel")
	check_eq(p.get("span"), 5, "three hill tiles plus two portals")
	check_eq(p["choices"].size(), 1)
	check_eq(p["choices"][0]["cost"], 5 * Tools.cost(Tools.Kind.TUNNEL))
	var r := b.apply(Tools.Kind.TUNNEL, Vector2i(39, 40), Vector2i(-1, -1), {"choice": &"tunnel"})
	check(r["ok"] and r["applied"])
	check_eq(c.building_at(39, 40), Buildings.id_of(&"tunnel_e"))
	check_eq(c.building_at(43, 40), Buildings.id_of(&"tunnel_w"))


func test_host_shows_the_bridge_dialog_and_builds_the_choice() -> void:
	var city := _host_city()
	_water_row(city, 50, 30, 32)
	host.select_tool(Tools.Kind.ROAD)
	var funds := city.funds
	var quote := host.handle_drag(Vector2i(28, 50), Vector2i(34, 50))
	check(quote["ok"], quote["reason"])
	check(not bool(quote["applied"]), "nothing built before the answer")
	check(host.choice_dialog.is_open(), "the choice dialog opened")
	check(host.is_input_blocked(), "map input waits on the dialog")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the game pauses under the quote")
	check_eq(host.choice_dialog.option_buttons.size(), 2)
	check(host.choice_dialog.title_label.text.contains("Bridge"))
	check(host.choice_dialog.body_label.text.contains("3 tiles"))
	check_eq(city.funds, funds)
	check(host.choice_dialog.select(&"suspension"))
	check_eq(host.choice_dialog.selected_key(), &"suspension")
	host.choice_dialog.build_button.pressed.emit()
	check(not host.choice_dialog.is_open())
	check_eq(city.building_at(30, 50), Buildings.id_of(&"bridge_suspension_start"), "the chosen bridge stands")
	check_eq(city.funds, funds - (4 * 10 + 3 * Builder.BRIDGE_COST_SUSPENSION))
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "speed restored")
	# Cancel builds nothing.
	_water_row(city, 60, 30, 32)
	host.handle_drag(Vector2i(28, 60), Vector2i(34, 60))
	check(host.choice_dialog.is_open())
	host.escape()
	check(not host.choice_dialog.is_open(), "escape cancels the quote")
	check_eq(city.building_at(28, 60), Buildings.NONE, "cancelled drags leave the ground alone")
	check_eq(city.funds, funds - (4 * 10 + 3 * Builder.BRIDGE_COST_SUSPENSION))
	# A quote the treasury cannot pay at all is refused before it is shown;
	# an option dearer than the treasury is listed but cannot be built.
	city.funds = 5
	var poor := host.handle_drag(Vector2i(28, 60), Vector2i(34, 60))
	check(not poor["ok"] and not host.choice_dialog.is_open(), "no quote without the money for the cheapest span")
	check_eq(poor["reason"], Builder.REASON_FUNDS)
	city.funds = 4 * 10 + 3 * Builder.BRIDGE_COST_CAUSEWAY
	host.handle_drag(Vector2i(28, 60), Vector2i(34, 60))
	check(host.choice_dialog.is_open())
	check(not host.choice_dialog.build_button.disabled, "the causeway is affordable")
	host.choice_dialog.select(&"suspension")
	check(host.choice_dialog.build_button.disabled, "unaffordable options cannot be built")
	host.choice_dialog.cancel()


# ── Neighbor links ───────────────────────────────────────────────────────

func test_edge_drag_asks_about_the_neighbor_and_accepting_links() -> void:
	var c := flat_city()
	c.founded_year = 2000
	var sim := make_simulation(c)
	var b := Builder.new(c, sim.stats, sim)
	var neighbors: NeighborSystem = sim.get_system(&"neighbors")
	check(neighbors != null)
	var p := b.preview(Tools.Kind.ROAD, Vector2i(5, 40), Vector2i(0, 40))
	check(p["ok"], p["reason"])
	check(bool(p.get("needs_confirmation", false)), "reaching the limit asks")
	check_eq(p.get("choice_kind"), &"neighbor")
	var ask: Dictionary = p["neighbor"]
	check_eq(int(ask["edge"]), NeighborParams.EDGE_WEST)
	check_eq(ask["tile"], Vector2i(0, 40))
	check_eq(ask["kind"], &"road")
	check_eq(int(ask["cost"]), Builder.NEIGHBOR_LINK_COST[NetworkShapes.Family.ROAD])
	check_eq(String(ask["name"]), neighbors.neighbor_name(NeighborParams.EDGE_WEST))
	check_eq(p["tiles"].size(), 5, "the border tile is not in the plan yet")
	var funds := c.funds
	var r := b.apply(Tools.Kind.ROAD, Vector2i(5, 40), Vector2i(0, 40))
	check(r["ok"] and r["applied"])
	check_eq(c.funds, funds - 5 * Tools.cost(Tools.Kind.ROAD), "the road to the limit is paid")
	check_eq(c.building_at(0, 40), Buildings.NONE, "declining leaves the border tile unbuilt")
	check(not bool(neighbors.connections()[NeighborParams.EDGE_WEST]["road"]), "no link yet")
	var linked := b.apply(Tools.Kind.ROAD, Vector2i(0, 40), Vector2i(0, 40), {"connect": true})
	check(linked["ok"] and linked["applied"], linked["reason"])
	check_eq(linked["cost"], Builder.NEIGHBOR_LINK_COST[NetworkShapes.Family.ROAD])
	check(Buildings.is_road_like(c.building_at(0, 40)), "the border tile carries the road")
	check(bool(neighbors.connections()[NeighborParams.EDGE_WEST]["road"]), "the accepted link is counted")
	check_eq(neighbors.link_count(), 1)
	var news := sim.events.news.filter(func(s: Dictionary) -> bool: return s["kind"] == &"neighbor_connection")
	check_eq(news.size(), 1, "the paper hears about the link")
	# Rail, power and pipes ask too; subways do not.
	check_eq(b.preview(Tools.Kind.RAIL, Vector2i(64, 3), Vector2i(64, 0)).get("choice_kind"), &"neighbor")
	check_eq(b.preview(Tools.Kind.POWER_LINE, Vector2i(124, 64), Vector2i(127, 64)).get("choice_kind"), &"neighbor")
	var pipe := b.preview(Tools.Kind.WATER_PIPE, Vector2i(64, 124), Vector2i(64, 127))
	check_eq(pipe.get("choice_kind"), &"neighbor")
	check_eq(pipe["neighbor"]["kind"], &"water")
	var pipe_link := b.apply(Tools.Kind.WATER_PIPE, Vector2i(64, 124), Vector2i(64, 127), {"connect": true})
	check(pipe_link["ok"], pipe_link["reason"])
	check(bool(neighbors.connections()[NeighborParams.EDGE_SOUTH]["water"]))
	var subway := b.preview(Tools.Kind.SUBWAY, Vector2i(60, 3), Vector2i(60, 0))
	check(not subway.has("neighbor"), "subways stay inside the city")
	# A drag along the border is stopped at the limit.
	var along := b.preview(Tools.Kind.ROAD, Vector2i(10, 0), Vector2i(20, 0))
	check(not along["ok"], "roads cannot run along the limit")
	check_eq(along["reason"], Builder.REASON_LIMIT)
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func test_host_prompts_for_the_link_after_the_drag() -> void:
	var city := _host_city()
	host.select_tool(Tools.Kind.ROAD)
	var funds := city.funds
	var result := host.handle_drag(Vector2i(4, 70), Vector2i(0, 70))
	check(result["applied"], "the road up to the limit is built at once")
	check(host.choice_dialog.is_open(), "then the link is offered")
	check(host.choice_dialog.title_label.text.contains("Connect"))
	check_eq(host.choice_dialog.build_button.text, "Connect")
	host.choice_dialog.build_button.pressed.emit()
	check(Buildings.is_road_like(city.building_at(0, 70)))
	check_eq(city.funds, funds - 4 * Tools.cost(Tools.Kind.ROAD) - Builder.NEIGHBOR_LINK_COST[NetworkShapes.Family.ROAD])
	var neighbors: NeighborSystem = host.sim.get_system(&"neighbors")
	check(bool(neighbors.connections()[NeighborParams.EDGE_WEST]["road"]))
	host.handle_drag(Vector2i(4, 80), Vector2i(0, 80))
	check(host.choice_dialog.is_open())
	host.choice_dialog.cancel_button.pressed.emit()
	check_eq(city.building_at(0, 80), Buildings.NONE, "declined link stays unbuilt")
	check(Buildings.is_road_like(city.building_at(1, 80)), "the rest of the road stays")


# ── Objections and protests ──────────────────────────────────────────────

func test_forced_objection_charges_nothing_until_the_player_proceeds() -> void:
	var b := _builder(100000)
	var c := b.city
	b.forced_opposition = true
	var r := b.apply(Tools.Kind.NUCLEAR_PLANT, Vector2i(30, 30))
	check(r["ok"], r["reason"])
	check(not bool(r["applied"]), "an objection holds the placement")
	check(bool(r.get("needs_confirmation", false)))
	check_eq(r.get("choice_kind"), &"opposition")
	check_eq(c.funds, 100000, "nothing charged")
	check_eq(c.building_at(30, 30), Buildings.NONE, "nothing placed")
	var built := b.apply(Tools.Kind.NUCLEAR_PLANT, Vector2i(30, 30), Vector2i(-1, -1), {"proceed": true})
	check(built["ok"] and built["applied"])
	check_eq(c.building_at(31, 31), Buildings.NUCLEAR_PLANT)
	check_eq(c.funds, 100000 - Tools.cost(Tools.Kind.NUCLEAR_PLANT))
	# A school never draws an objection, forced or not.
	var school := b.apply(Tools.Kind.SCHOOL, Vector2i(50, 50))
	check(school["applied"], "schools are welcome")
	b.forced_opposition = false
	# Without homes nearby the gate always passes; ringed by homes it can fail.
	var quiet := b.preview(Tools.Kind.COAL_PLANT, Vector2i(80, 80))
	check_eq(int(quiet.get("opposition_exposure", -1)), 0)
	var homes := b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(70, 70), Vector2i(95, 95))
	check(homes["ok"], homes["reason"])
	var ringed := b.preview(Tools.Kind.COAL_PLANT, Vector2i(80, 80))
	check_gt(int(ringed.get("opposition_exposure", 0)), Builder.OPPOSITION_THRESHOLD_RANGE, "a plant amid homes always objects")
	var refused := b.apply(Tools.Kind.COAL_PLANT, Vector2i(80, 80))
	check(refused["ok"], refused["reason"])
	check(not bool(refused["applied"]), "the objection holds the plant")
	check_eq(refused.get("choice_kind"), &"opposition")


func test_host_objection_notice_cancels_or_proceeds() -> void:
	var city := _host_city(40000)
	host.builder.forced_opposition = true
	host.select_tool(Tools.Kind.PRISON)
	var funds := city.funds
	var r := host.handle_drag(Vector2i(20, 20), Vector2i(20, 20))
	check(r["ok"] and not bool(r["applied"]))
	check(host.notice_dialog.is_open(), "the objection is a notice")
	check(host.notice_dialog.title_label.text.contains("Object"))
	check(host.notice_dialog.body_label.text.contains("reconsider"))
	check_eq(host.notice_dialog.choice_buttons.size(), 2)
	host.notice_dialog.dismiss(&"cancel")
	check_eq(city.funds, funds, "cancel charges nothing")
	check_eq(city.building_at(20, 20), Buildings.NONE)
	host.handle_drag(Vector2i(20, 20), Vector2i(20, 20))
	check(host.notice_dialog.is_open())
	host.notice_dialog.dismiss(&"proceed")
	check_eq(city.building_at(20, 20), Buildings.PRISON, "proceeding places the prison")
	check_eq(city.funds, funds - Tools.cost(Tools.Kind.PRISON))


func test_felling_many_trees_draws_one_protest_a_year() -> void:
	var city := _host_city()
	for x in range(10, 30):
		city.building.put(x, 15, Buildings.TREES_1)
	host.select_tool(Tools.Kind.BULLDOZE)
	# The protest is flavour: it reads on the status line and never pauses.
	var message := host.status_bar.message_label
	var few := host.handle_drag(Vector2i(10, 15), Vector2i(12, 15))
	check(few["applied"])
	check(not message.text.contains("Trees"), "three trees pass without comment")
	var many := host.handle_drag(Vector2i(13, 15), Vector2i(22, 15))
	check(many["applied"])
	check_eq(city.building_at(20, 15), Buildings.NONE, "the protest changes nothing on the map")
	check(not host.notice_dialog.is_open(), "the protest does not open a dialog")
	check(message.text.contains("Trees"), "ten trees draw a protest: " + message.text)
	check(message.text.contains("10"))
	var again := host.handle_drag(Vector2i(23, 15), Vector2i(29, 15))
	check(again["applied"])
	check(not message.text.contains("Trees"), "only one protest a year")
	host.sim.advance_days(GameClock.DAYS_PER_YEAR)
	if host.notice_dialog.is_open():
		host.notice_dialog.dismiss()
	if host.window_manager.is_open("budget"):
		(host.windows["budget"] as Control).call("close")
	for x in range(10, 30):
		city.building.put(x, 25, Buildings.TREES_1)
	host.handle_drag(Vector2i(10, 25), Vector2i(29, 25))
	check(message.text.contains("Trees"), "a new year allows a new protest")


# ── Facility query, rename, signs ────────────────────────────────────────

func test_query_shows_facility_figures_and_rename_stores_a_name() -> void:
	var city := _host_city(60000)
	host.select_tool(Tools.Kind.COAL_PLANT)
	check(host.handle_drag(Vector2i(20, 20), Vector2i(20, 20))["applied"])
	host.select_tool(Tools.Kind.PRISON)
	check(host.handle_drag(Vector2i(30, 20), Vector2i(30, 20))["applied"])
	host.select_tool(Tools.Kind.BUS_DEPOT)
	check(host.handle_drag(Vector2i(40, 20), Vector2i(40, 20))["applied"])
	host.sim.advance_days(15)
	host.open_query(Vector2i(21, 21))
	var info := host.query_panel.info
	check_eq(info["Building"], "Coal Power Plant")
	check_eq(info["Built"], "2000")
	check(info.has("Age"))
	check(info.has("Output"), "plant output shown")
	check(not host.query_panel.rename_button.disabled, "facilities can be renamed")
	host.open_query(Vector2i(31, 21))
	info = host.query_panel.info
	check(info.has("Inmates") and info.has("Guards") and info.has("Capacity"), "prison figures shown")
	host.open_query(Vector2i(40, 20))
	check(host.query_panel.info.has("Riders this year"), "station riders shown")
	host.open_query(Vector2i(50, 50))
	check(host.query_panel.rename_button.disabled, "open ground has no name to give")
	# Rename through the prompt.
	host.open_query(Vector2i(21, 21))
	host.query_panel.rename_button.pressed.emit()
	check(host.notice_dialog.is_open())
	check(host.notice_dialog.line_edit.visible, "rename asks for text")
	host.notice_dialog.line_edit.text = "Old Smoky"
	host.notice_dialog.dismiss(&"submit")
	check_eq(String(city.facility(Vector2i(20, 20)).get("name", "")), "Old Smoky")
	check_eq(host.query_panel.info.get("Name"), "Old Smoky", "the panel refreshes")
	var r := host.builder.rename_facility(Vector2i(22, 22), "")
	check(r["ok"])
	check(not city.facility(Vector2i(20, 20)).has("name"), "empty text clears the name")
	check(not host.builder.rename_facility(Vector2i(50, 50), "Nothing")["ok"])
	host.escape()


func test_sign_tool_prompts_and_labels_render() -> void:
	var city := _host_city()
	host.set_option(&"labels", true)
	host.select_tool(Tools.Kind.SIGN)
	host.handle_drag(Vector2i(33, 33), Vector2i(33, 33))
	check(host.notice_dialog.is_open(), "the sign tool asks for text")
	check(host.notice_dialog.line_edit.visible)
	host.notice_dialog.line_edit.text = "Dry Gulch"
	host.notice_dialog.dismiss(&"submit")
	check_eq(String(city.signs.get(Vector2i(33, 33), "")), "Dry Gulch")
	check_eq(host.city_view_3d._labels.get_child_count(), 1, "the label layer draws the sign")
	host.handle_drag(Vector2i(33, 33), Vector2i(33, 33))
	check_eq(host.notice_dialog.line_edit.text, "Dry Gulch", "the prompt starts from the current text")
	host.notice_dialog.line_edit.text = ""
	host.notice_dialog.dismiss(&"submit")
	check(not city.signs.has(Vector2i(33, 33)), "empty text removes the sign")
	check_eq(host.city_view_3d._labels.get_child_count(), 0)


# ── Notice text ──────────────────────────────────────────────────────────

func test_every_notice_kind_has_a_title_and_body() -> void:
	_host_city()
	var payloads := {
		&"approval_milestone": {"approval": 72},
		&"plant_retired": {"name": "Coal Power Plant", "anchor": Vector2i(3, 4), "age_years": 51},
		&"fiscal_crisis": {"funds": -1200, "year": 2001},
		&"bankruptcy": {"funds": -40000, "debt": 30000, "year": 2002},
		&"exodus": {"resorts": 2, "residents": 61000, "refund": 20000},
		&"national_guard": {},
		&"disaster": {"kind": "earthquake", "x": 40, "y": 40},
		&"opposition": {"name": "Nuclear Power Plant"},
		&"tree_protest": {"count": 12},
		&"newspaper": {"extra": true, "date": "May 2001", "stories": [{"headline": "Flood!", "body": "Wet."}]},
	}
	for kind in payloads:
		var spec := host.notices.notice_for(kind, payloads[kind])
		check(not String(spec.get("title", "")).is_empty(), "%s has a title" % kind)
		check(not String(spec.get("body", "")).is_empty(), "%s has a body" % kind)
		check(not String(spec.get("body", "")).contains("{"), "%s body fully filled: %s" % [kind, spec.get("body", "")])
		check(not String(spec.get("title", "")).contains("{"), "%s title fully filled" % kind)
	for milestone in RewardParams.MILESTONES:
		var key: StringName = milestone.key
		var payload := {"key": key}
		if key == RewardParams.MILITARY_KEY:
			payload["kind"] = "army"
			payload["site"] = [10, 10, 8, 8]
		var spec := host.notices.notice_for(&"reward_offered", payload)
		check(not String(spec["title"]).is_empty() and not String(spec["body"]).is_empty(), "%s offer has text" % key)
		check(not String(spec["body"]).contains("{"), "%s offer fully filled" % key)
		check_eq(spec["choices"].size(), 2, "%s offer has two answers" % key)
	var retired := host.notices.notice_for(&"plant_retired", payloads[&"plant_retired"])
	check(String(retired["body"]).contains("Coal Power Plant"), "the retired plant is named")
	check(String(retired["body"]).to_lower().contains("rebuild"), "a rebuild hint is given")
	var crisis := host.notices.notice_for(&"fiscal_crisis", payloads[&"fiscal_crisis"])
	check(String(crisis["body"]).contains("-$1,200"))
	var approval := host.notices.notice_for(&"approval_milestone", payloads[&"approval_milestone"])
	check(String(approval["body"]).contains("72"))
	check(host.notices.notice_for(&"newspaper", {"extra": false}).is_empty(), "ordinary issues stay quiet")
	for kind in [&"bridge", &"tunnel", &"neighbor"]:
		var lines := NoticeLines.render(kind, {"count": 4, "neighbor": "Searchlight", "cost": 100, "kind": "road"}, "Flowtown", "Mayor", 2000)
		check(not String(lines["body"]).contains("{"), "%s prompt fully filled" % kind)
