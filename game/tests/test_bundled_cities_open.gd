# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Opening an included city shows it as it is: its population counted, a real
## settlement class, and no backlog of technology news from before today.
extends "res://tests/test_case.gd"

const NAMES := ["Adaven", "Aliso Niguel", "Foothills Ranch", "Grant Pass - Soledad", "La Presa", "Lawndale", "Oro Canyon", "Salton Shores", "Valle del Mar"]


func _open(city_name: String) -> Simulation:
	var result := SaveFormat.load("res://assets/cities/%s.sc2d" % city_name)
	check(bool(result["ok"]), "loads " + city_name)
	var sim := Simulation.new()
	sim.setup(result["city"], -1, null, result["snapshot"])
	sim.restore(result["snapshot"])
	return sim


func test_every_included_city_opens_with_its_people_and_class() -> void:
	for city_name: String in NAMES:
		var sim := _open(city_name)
		var people := sim.stats.total_population()
		check_gt(people, 0, city_name + " opens with its population")
		check_gt(sim.stats.jobs, 0, city_name + " opens with its jobs")
		check_between(sim.city.status, 0, PopulationParams.STATUS_NAMES.size() - 1, city_name + " class")
		check_eq(sim.city.status, PopulationSystem.derived_status(people),
			"%s (%d people) is no %s" % [city_name, people, PopulationParams.status_name(sim.city.status)])
		var water := (sim.get_system(&"water") as WaterSystem).network_summary()
		check_eq(int(water.get("capacity", -1)), sim.stats.water_capacity, city_name + " water window matches the saved stats")
		sim.free()


func test_opening_an_included_city_prints_no_old_inventions() -> void:
	for city_name: String in ["Oro Canyon", "Aliso Niguel", "Salton Shores"]:
		var sim := _open(city_name)
		var year := sim.clock.year()
		var invented: Array[Dictionary] = []
		sim.news_published.connect(func(story: Dictionary) -> void:
			if story.get("kind", &"") == &"invention":
				invented.append(story))
		var opened := sim.stats.population
		sim.advance_days(75)
		for story in invented:
			check_ge(int(story["args"]["year"]), year, "%s: %s is not news" % [city_name, str(story["args"])])
		check_between(sim.stats.population, opened / 2, opened * 2, city_name + ": no month-one influx")
		sim.free()
