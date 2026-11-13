# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Newspaper stories read correctly for a count of one, for disasters with
## plural names, for a military base and for each kind of neighbor link.
extends "res://tests/test_case.gd"

const CITY := "Dry Gulch"


## Every headline variant and the body of a report, filled.
func _texts(kind: StringName, args: Dictionary) -> Array[String]:
	var values := NewsStories.values_for(kind, args, CITY, "Ada", 1999)
	var out: Array[String] = []
	for h: String in NewsStories.headline_variants(kind, args):
		out.append(NewsStories.fill(h, values, true))
	out.append(NewsStories.body(kind, args, values))
	return out


func _joined(kind: StringName, args: Dictionary) -> String:
	return "\n".join(_texts(kind, args))


func test_a_count_of_one_reads_in_the_singular() -> void:
	var road := _joined(&"road_decay", {"count": 1, "x": 10, "y": 10})
	check(road.contains("1 Stretch Of Road Crumbles Near"), road)
	check(road.contains("1 stretch of road around the northwest corner has crumbled"), road)
	var escape := _joined(&"prison_escape", {"count": 1, "x": 10, "y": 10})
	check(escape.contains("1 Inmate Walks Away From Overcrowded Prison"), escape)
	check(escape.contains("1 inmate escaped the prison"), escape)
	var rail := _joined(&"rail_decay", {"count": 1, "x": 10, "y": 10})
	check(rail.contains("1 Section Of Track Pulled From Service"), rail)
	check(rail.contains("condemned 1 section of track"), rail)
	var empty := _joined(&"abandonment_wave", {"count": 1, "x": 10, "y": 10})
	check(empty.contains("1 Building Stands Empty As Tenants Move On"), empty)
	check(empty.contains("One more building around the northwest corner was left empty"), empty)
	var dark := _joined(&"power_shortage", {"unpowered": 1})
	check(dark.contains("Brownout Leaves 1 Building In The Dark"), dark)
	check(dark.contains("and 1 building went dark"), dark)
	var dry := _joined(&"water_shortage", {"unwatered": 1})
	check(dry.contains("Taps Run Dry In 1 Building\n"), dry)
	check(dry.contains("and 1 building went without water"), dry)


func test_no_story_pairs_one_with_a_plural() -> void:
	var plural := RegEx.new()
	plural.compile("(?i)\\b1 (new )?(buildings|lots|stretches|sections|inmates|families|tourists|residents|births|years)\\b")
	for kind: StringName in NewsStories.kinds():
		for key: String in ["count", "unpowered", "unwatered", "age_years", "births"]:
			var text := _joined(kind, {key: 1, "x": 10, "y": 10})
			var found := plural.search(text)
			check(found == null, "%s: %s" % [kind, found.get_string() if found != null else ""])


func test_larger_counts_keep_the_plural() -> void:
	var road := _joined(&"road_decay", {"count": 12, "x": 10, "y": 10})
	check(road.contains("12 Stretches Of Road Crumble Near"), road)
	check(road.contains("12 stretches of road around the northwest corner have crumbled"), road)
	var escape := _joined(&"prison_escape", {"count": 21})
	check(escape.contains("21 Inmates Walk Away"), escape)
	var empty := _joined(&"abandonment_wave", {"count": 11, "x": 10, "y": 10})
	check(empty.contains("Another 11 buildings around"), empty)


func test_the_end_of_a_disaster_reads_for_every_name() -> void:
	for kind: StringName in DisasterParams.KINDS:
		var name := DisasterParams.display_name(kind)
		var text := _joined(&"disaster_ended", {"kind": kind})
		check(text.contains(name), "%s is named" % name)
		check(not text.contains("%s Ends" % name), "%s: no verb agreeing with the name in a headline" % name)
		check(not text.contains("%s that struck %s is over" % [name, CITY]), "%s: no verb agreeing with the name in the body" % name)
	var riots := _joined(&"disaster_ended", {"kind": &"mass_riots"})
	check(riots.contains("Dry Gulch has come through the Mass Riots."), riots)


func test_a_military_base_is_not_reported_as_a_port() -> void:
	var opened := _joined(&"port_opened", {"kind": Zones.MILITARY, "x": 100, "y": 20})
	check(opened.contains("Military Base"), opened)
	for wrong: String in ["Its Military;", "New Military Draws", "Through New Military", "Cargo", "Freight", "tourist", "For Business"]:
		check(not opened.contains(wrong), "opened: %s in %s" % [wrong, opened])
	check(opened.contains("the northeast corner"), opened)
	var closed := _joined(&"port_closed", {"kind": Zones.MILITARY, "x": 100, "y": 20})
	check(closed.contains("Military Base"), closed)
	for wrong: String in ["customers", "chamber of commerce", "Dry Gulch Military;"]:
		check(not closed.contains(wrong), "closed: %s in %s" % [wrong, closed])
	check_eq(NewsStories.headline_variants(&"port_opened", {"kind": Zones.MILITARY}).size(),
		NewsStories.headline_variants(&"port_opened", {"kind": Zones.AIRPORT}).size(), "the same number of headlines to choose from")
	check_eq(NewsStories.headline_variants(&"port_closed", {"kind": Zones.MILITARY}).size(),
		NewsStories.headline_variants(&"port_closed", {"kind": Zones.SEAPORT}).size())
	var airport := _joined(&"port_opened", {"kind": Zones.AIRPORT, "x": 100, "y": 20})
	check(airport.contains("First Cargo Moves Through New Airport"), "a civil port keeps its story")


func test_each_kind_of_neighbor_link_has_its_own_story() -> void:
	var road := _joined(&"neighbor_connection", {"name": "Rimrock", "edge": 1, "kind": "road"})
	check(road.contains("Road Now Runs Through To Rimrock"), road)
	var rail := _joined(&"neighbor_connection", {"name": "Rimrock", "edge": 1, "kind": "rail"})
	check(rail.contains("Rimrock") and rail.contains("Rail"), rail)
	check(not rail.contains("Road Now Runs"), rail)
	var power := _joined(&"neighbor_connection", {"name": "Rimrock", "edge": 1, "kind": "power"})
	check(power.contains("Rimrock") and power.contains("Power Line"), power)
	var water := _joined(&"neighbor_connection", {"name": "Rimrock", "edge": 1, "kind": "water"})
	check(water.contains("Rimrock") and water.contains("Pipe"), water)
	for utility: String in [power, water]:
		for wrong: String in ["Road", "Border Crossing", "traffic", "workers"]:
			check(not utility.contains(wrong), "%s in %s" % [wrong, utility])
	for kind: String in ["rail", "power", "water"]:
		check_eq(NewsStories.headline_variants(&"neighbor_connection", {"kind": kind}).size(),
			NewsStories.headline_variants(&"neighbor_connection", {"kind": "road"}).size(), "the same number of headlines to choose from")
		check_eq(NewsStories.priority_of(&"neighbor_connection", {"kind": kind}), NewsStories.priority_of(&"neighbor_connection", {"kind": "road"}))
