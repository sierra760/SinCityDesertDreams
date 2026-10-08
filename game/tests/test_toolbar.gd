# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The toolbar lists every tool, reports prices and lock reasons, and
## highlights the selection.
extends "res://tests/test_case.gd"

var toolbar: Toolbar


func before_each() -> void:
	toolbar = Toolbar.new()
	root.add_child(toolbar)


func after_each() -> void:
	root.remove_child(toolbar)
	toolbar.free()


func test_every_tool_has_a_button_with_price_tooltip() -> void:
	for tool in Tools.all():
		check(toolbar.buttons.has(tool), "button for %s" % Tools.display_name(tool))
		var b: Button = toolbar.buttons[tool]
		check(b.tooltip_text.begins_with(Tools.display_name(tool)), "tooltip names the tool")
		if Tools.cost(tool) > 0:
			check(b.tooltip_text.contains("$" + UIFactory.commafy(Tools.cost(tool))), "tooltip prices %s" % Tools.display_name(tool))
		else:
			check(b.tooltip_text.contains("free"))
		check(b.icon != null, "%s has an icon" % Tools.display_name(tool))
	check_eq(toolbar.buttons.size(), Tools.all().size())


func test_pressing_a_button_selects_the_tool() -> void:
	var picked: Array[int] = []
	toolbar.tool_selected.connect(func(t: int) -> void: picked.append(t))
	(toolbar.buttons[Tools.Kind.RAIL] as Button).pressed.emit()
	check_eq(picked, [Tools.Kind.RAIL] as Array[int])
	toolbar.set_active(Tools.Kind.RAIL)
	check_eq(toolbar.active_tool, Tools.Kind.RAIL)
	var active: Button = toolbar.buttons[Tools.Kind.RAIL]
	var other: Button = toolbar.buttons[Tools.Kind.ROAD]
	check_ne(active.get_theme_stylebox("normal"), other.get_theme_stylebox("normal"), "active button is highlighted")
	toolbar.set_active(-1)
	check_eq(active.get_theme_stylebox("normal"), other.get_theme_stylebox("normal"), "highlight cleared")


func test_refresh_locks_by_year_reward_and_emergency() -> void:
	var city := flat_city()
	city.founded_year = 1900
	var sim := make_simulation(city)
	toolbar.refresh(city, sim.stats, sim.get_system(&"disasters"))
	check(toolbar.is_locked(Tools.Kind.SUBWAY), "subways are locked in 1900")
	check((toolbar.buttons[Tools.Kind.SUBWAY] as Button).disabled)
	check((toolbar.buttons[Tools.Kind.SUBWAY] as Button).tooltip_text.contains("not available until"))
	check(not toolbar.is_locked(Tools.Kind.ROAD))
	check(toolbar.is_locked(Tools.Kind.REWARD_CITY_HALL), "rewards wait for their offer")
	check(toolbar.is_locked(Tools.Kind.DISPATCH_FIRE), "no crews outside an emergency")
	sim.stats.rewards_offered[&"city_hall"] = true
	city.day = GameClock.DAYS_PER_YEAR * 20
	toolbar.refresh(city, sim.stats, sim.get_system(&"disasters"))
	check(not toolbar.is_locked(Tools.Kind.REWARD_CITY_HALL))
	city.day = GameClock.DAYS_PER_YEAR * 30
	toolbar.refresh(city, sim.stats, sim.get_system(&"disasters"))
	check(not toolbar.is_locked(Tools.Kind.SUBWAY),
		"subways unlock by 1930: the rolled year is 1910 plus under twenty years")
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func test_nuclear_free_zone_locks_the_nuclear_plant() -> void:
	var city := flat_city()
	city.founded_year = 2000
	var stats := CityStats.new()
	toolbar.refresh(city, stats)
	check(not toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "nuclear plants are available in 2000")
	stats.ordinances[&"nuclear_free_zone"] = true
	toolbar.refresh(city, stats)
	check(toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "the ordinance locks the nuclear plant")
	var b: Button = toolbar.buttons[Tools.Kind.NUCLEAR_PLANT]
	check(b.disabled)
	check(b.tooltip_text.contains(Tools.NUCLEAR_FREE_ZONE_REASON), "the tooltip names the ordinance")
	check(not toolbar.is_locked(Tools.Kind.COAL_PLANT))
	stats.ordinances[&"nuclear_free_zone"] = false
	toolbar.refresh(city, stats)
	check(not toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "repealing unlocks it")


func test_groups_appear_in_order() -> void:
	var column: VBoxContainer = toolbar.get_node("Shell/Scroll/Column")
	var headers: Array[String] = []
	for child in column.get_children():
		if child is Label:
			headers.append((child as Label).text)
	check_eq(headers.size(), Toolbar.GROUP_ORDER.size())
	check_eq(headers[0], "Inspect")
	check_eq(headers[headers.size() - 1], "Terrain")
