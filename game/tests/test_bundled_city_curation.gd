# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const Catalog := preload("res://scripts/io/bundled_cities.gd")
const AUTHORED := ["Adaven", "Bonanza Gap", "Juniper Basin"]

func test_every_nameable_connection_has_a_name_and_classic_signs_are_gone() -> void:
	for entry: Dictionary in Catalog.entries():
		var loaded := SaveFormat.load(entry.path)
		check(loaded.ok, entry.name + " loads")
		if not loaded.ok: continue
		var city: City = loaded.city
		check(city.signs.is_empty(), entry.name + " has no classic signs")
		var topology: StreetTopology = loaded.topology
		for segment: Dictionary in topology.segments({}):
			for link: String in segment.links:
				check(city.street_naming.links.has(link), entry.name + ": " + link)
		var before: Dictionary = city.street_naming.duplicate(true)
		var naming := StreetNamingService.new()
		naming.set_station_allocator(StationNameResolver.reconcile)
		check(naming.bind_city(city, topology).ok, "host naming bind succeeds")
		check_eq(city.street_naming, before, entry.name + " station names already reconciled")

func test_new_streets_continue_straight_through_junctions_and_follow_bends() -> void:
	for entry: Dictionary in Catalog.entries():
		if entry.name in AUTHORED: continue # Preserve the owner's existing name boundaries.
		var loaded := SaveFormat.load(entry.path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var topology: StreetTopology = loaded.topology
		for junction: Dictionary in topology.junctions(city.street_naming.links):
			if entry.name == "Grant Pass - Soledad" and junction.cell.x == 67: continue
			for a: Dictionary in junction.approaches:
				for b: Dictionary in junction.approaches:
					if a.direction == -b.direction:
						check_eq(a.street_id, b.street_id, entry.name + " straight junction at " + str(junction.cell))
		for segment: Dictionary in topology.segments({}):
			var ids := {}
			for link: String in segment.links:
				ids[int(city.street_naming.links.get(link, 0))] = true
			if entry.name != "Grant Pass - Soledad":
				check_eq(ids.size(), 1, entry.name + " continuous bend/bridge/tunnel")

func test_resort_lots_use_every_available_design_before_repeating() -> void:
	for entry: Dictionary in Catalog.entries():
		var loaded := SaveFormat.load(entry.path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var counts := {}
		var total := 0
		for anchor: Vector2i in city.facilities:
			var code := city.building.atv(anchor)
			if not Buildings.is_arcology(code): continue
			check_eq(StringName(city.facilities[anchor].key), Buildings.key(code), entry.name + " facility agrees with model")
			if Buildings.size(code) != Vector2i(4,4): continue
			total += 1
			counts[code] = int(counts.get(code,0)) + 1
			for y: int in range(anchor.y, anchor.y+4):
				for x: int in range(anchor.x, anchor.x+4):
					check_eq(city.building.at(x,y), code, "complete original 4x4 lot")
		check_eq(counts.size(), mini(total, 10), entry.name + " maximum design variety")
		for count: int in counts.values():
			check(count <= 2, entry.name + " surplus repeats spread between designs")

func test_border_street_names_follow_sonora_and_arizona_sides() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Grant Pass - Soledad.sc2d")
	check(loaded.ok)
	if not loaded.ok: return
	var city: City = loaded.city
	var sides := {}
	for link: String in city.street_naming.links:
		var ends := link.split(">")
		var west := int(ends[0].get_slice(",",0)) + int(ends[1].get_slice(",",0)) < 134
		var id: int = city.street_naming.links[link]
		var name: String = city.street_naming.streets[id]
		if sides.has(id): check_eq(sides[id], west, "name changes at the international border")
		sides[id] = west
		if west:
			check(name.begins_with("Calle ") or name.begins_with("Avenida ") or name.begins_with("Calzada ") or name.begins_with("Boulevard ") or name.begins_with("Paseo "), "Sonoran street: " + name)

func test_classic_terrain_dates_and_funds_are_preserved() -> void:
	var sources := {"Aliso Niguel":"Aliso Niguel", "Foothills Ranch":"Foothills Ranch", "Grant Pass - Soledad":"Grant Pass - Soledad", "Harbor Palms":"Lawndale", "La Presa":"La Presa", "Oro Canyon":"Oro Canyon", "Salton Shores":"Salton Shores", "Silver Ridge":"Magnolia Township", "Valle del Mar":"Valle del Mar"}
	for name: String in sources:
		var imported := Sc2Import.load("res://assets/cities/%s.sc2" % sources[name])
		var loaded := SaveFormat.load("res://assets/cities/%s.sc2d" % name)
		check(imported.ok and loaded.ok, name + " source and curated city load")
		if not imported.ok or not loaded.ok: continue
		var original: City = imported.city
		var city: City = loaded.city
		check_eq(city.terrain.data, original.terrain.data, name + " terrain")
		check_eq(city.altitude.data, original.altitude.data, name + " altitude")
		check_eq(city.zone.data, original.zone.data, name + " original lot corners")
		check_eq(city.day, original.day, name + " date")
		check_eq(city.funds, original.funds, name + " treasury")

func test_streets_do_not_repeat_base_names_with_different_types() -> void:
	var suffix := RegEx.new()
	check_eq(suffix.compile(" (street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|court|ct|circle|cir|way|parkway|pkwy|highway|hwy|place|pl|trail|terrace|loop|bend|walk|path)\\.?$"), OK)
	var prefix := RegEx.new()
	check_eq(prefix.compile("^(calle|avenida|calzada|paseo|camino|boulevard) ((de la|de los|de las|del|de) )?"), OK)
	for entry: Dictionary in Catalog.entries():
		var loaded := SaveFormat.load(entry.path)
		check(loaded.ok, entry.name + " loads for name-variety check")
		if not loaded.ok: continue
		var city: City = loaded.city
		var roots := {}
		for name: String in city.street_naming.streets.values():
			var folded := name.to_lower()
			for pair: Array in [["á","a"],["é","e"],["í","i"],["ó","o"],["ú","u"],["ü","u"],["ñ","n"]]:
				folded = folded.replace(pair[0],pair[1])
			var base := prefix.sub(suffix.sub(folded,""),"")
			check(not roots.has(base), entry.name + ": repeated base name " + name + " / " + String(roots.get(base,"")))
			roots[base] = name
