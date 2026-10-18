# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_query_summary_excludes_internal_fields_and_irrelevant_citywide_counters() -> void:
	var query: GDScript = load("res://scripts/ui/query_panel.gd")
	check(query.has_method("presentation_info"))
	if not query.has_method("presentation_info"): return
	var full := {"Building": "Power plant", "Power": "Yes", "Output": "2,000 units", "Age": "45 years", "Internal future counter": 123, "City visitor power": "150 units", "Location": "10, 10", "Footprint": "4×4 at 10,10"}
	var summary: Dictionary = query.call("presentation_info", full, false)
	check(summary.has("Output"))
	check(not summary.has("Internal future counter"))
	check(not summary.has("City visitor power"))
	check(not summary.has("Location"))
	var details: Dictionary = query.call("presentation_info", full, true)
	check(not details.has("Internal future counter"), "details are curated too")
	check(not details.has("City visitor power"))
	var land := QueryPanel.presentation_info({"Building":"Home", "Land Value":100}, true)
	check_eq(land.keys().filter(func(key: String) -> bool: return key.to_lower() == "land value").size(), 1, "details do not repeat summary facts with different capitalization")

func test_query_keeps_failures_prominent_without_the_tourism_dump() -> void:
	var query: GDScript = load("res://scripts/ui/query_panel.gd")
	if not query.has_method("presentation_info"):
		check(false, "curated presentation exists")
		return
	var full := {"Building": "Resort", "Power": "No", "Water": "Yes", "Operating": "No", "Operating reason": "Needs road access", "Guests": 0, "Day visitors": 0, "Lodging capacity": 80, "Staffing": "50%; supports 40 of 80 planned guests", "Tier yields": "raw multipliers", "Casino source": "0.043 units", "Tourism jobs": "10 offered / 5 resident-filled / 5 incoming"}
	var summary: Dictionary = query.call("presentation_info", full, false)
	check_eq(summary.get("Status"), "Needs road access")
	check_eq(summary.get("Power"), "No")
	check(not summary.has("Tier yields"))
	check(not summary.has("Casino source"))
	check(summary.size() <= 9)

func test_query_disclosure_survives_same_tile_refresh_and_resets_on_new_tile() -> void:
	var city := flat_city()
	var panel := QueryPanel.new()
	root.add_child(panel)
	panel.show_tile(city, null, Vector2i(10, 10))
	check(panel.has_method("set_details"))
	if panel.has_method("set_details"):
		panel.call("set_details", true)
		panel.show_tile(city, null, Vector2i(10, 10))
		check(panel.call("details_open"))
		panel.show_tile(city, null, Vector2i(11, 10))
		check(not panel.call("details_open"))
		check(panel.lines().size() <= 8, "ground query is concise")
	panel.free()

func test_roads_and_zoned_trees_do_not_show_building_utility_failures() -> void:
	var city := flat_city()
	city.building.put(10,10,Buildings.ROAD_FIRST)
	city.building.put(11,10,Buildings.TREES_1)
	city.zone.put(11,10,Zones.RES_LOW)
	var query: GDScript = load("res://scripts/ui/query_panel.gd")
	for tile in [Vector2i(10,10), Vector2i(11,10)]:
		var summary: Dictionary = query.call("presentation_info", QueryPanel.describe(city,null,tile), false)
		check(not summary.has("Water"))
		check(not summary.has("Power"))

func test_local_support_shortfall_is_visible_in_resort_summary() -> void:
	var query: GDScript = load("res://scripts/ui/query_panel.gd")
	var summary: Dictionary = query.call("presentation_info", {"Building":"Resort", "Lodging capacity":80, "Operating":"Yes", "Utility support":"0 guests / 0 day visitors; limited by water"}, false)
	check(str(summary.get("Status", "")).contains("water"), "summary names the actual local constraint")
