# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Overhead exit and distance gantries stand on the highway's own tiles.
extends "res://tests/exploration/street_signs_case.gd"
const Gantries := preload("res://scripts/view/highway_gantry_placement_3d.gd")
const Topology := preload("res://scripts/core/naming/street_topology.gd")
const SIGNS := "res://assets/street-name-signs/"

## A long southbound/northbound highway pair (x=20,21) with three west-side
## exits from the southbound carriageway at the given rows, each before
## (north of) the short named road it feeds, since ramps are one way.
## Optional developed lots line both sides.
static func _highway(exits: Array[int], lined: bool = false) -> Dictionary:
	var city := flat_city()
	for y: int in range(2, 100):
		city.building.put(20, y, NetworkShapes.HIGHWAY_NS)
		city.building.put(21, y, NetworkShapes.HIGHWAY_NS)
	var links: Array[String] = []
	for row: int in exits:
		city.building.put(19, row, 96)
		city.flags.put(19, row, RotationMapper.AXIS_FLAG)
		Fixtures.road(city, Vector2i(19, row+1), Vector2i(19, row+3))
		links.append(Topology.link_key(Vector2i(19, row+1), &"open", Vector2i(19, row+2), &"open"))
	if lined:
		for y: int in range(2, 100):
			for x: int in [18, 19, 22, 23]:
				if city.building.atv(Vector2i(x, y)) == 0: city.building.put(x, y, Buildings.SUBWAY_STATION)
	var f := Fixtures.from_city(city)
	f["links"] = links
	return f

func _gantries(layer: Node, kind: String) -> Array[Node]:
	return _signs(layer, kind)

func test_contract_and_provenance() -> void:
	var contract := Gantries.contract()
	for id: String in ["highway-gantry", "gantry-distance"]:
		check_eq(FileAccess.get_sha256(SIGNS + id + ".glb"), contract.templates[id].sha256, id + " exact authored export")
		check(ResourceLoader.exists(SIGNS + id + ".glb"))
	check(FileAccess.file_exists(SIGNS + "gantry-provenance.json"))
	check_eq(contract.font, "res://assets/fonts/overpass/overpass-bold.tres")
	var truss: Dictionary = contract.templates["highway-gantry"].truss_m
	check_lt(float(truss.half_span) / 16.0, .5, "truss stays inside one carriageway tile")
	var scene := (load(SIGNS + "gantry-distance.glb") as PackedScene).instantiate()
	var face := scene.find_child("BlankFaceFront", true, false) as MeshInstance3D
	check_eq(String(face.mesh.surface_get_material(0).resource_name), "HighwayGreen")
	scene.free()

func test_fraction_of_a_mile_text() -> void:
	check_eq(Gantries.distance_text(1), "¼ MI", "never less than a quarter")
	check_eq(Gantries.distance_text(4), "¼ MI")
	check_eq(Gantries.distance_text(8), "½ MI")
	check_eq(Gantries.distance_text(12), "¾ MI")
	check_eq(Gantries.distance_text(16), "1 MI")
	check_eq(Gantries.distance_text(20), "1¼ MI")
	check_eq(Gantries.distance_text(28), "1¾ MI")
	check_eq(Gantries.distance_text(40), "2½ MI")

func test_exit_gantry_spans_its_own_carriageway_tile() -> void:
	if not _available(): return
	var f := Fixtures.exit_city()
	var s := _layer(f)
	check(s.names.assign(_keys([f.named]), "Canyon Way", f.topology.revision).ok)
	var exits := _gantries(s.layer, "exit")
	check_eq(exits.size(), 1, "one exit gantry for the one named exit")
	for gantry: Node3D in exits:
		check_eq(gantry.get_meta("display_text"), "Canyon Way")
		check_eq(gantry.get_meta("structure"), "gantry")
		check_eq(gantry.get_meta("travel_direction"), Vector2i.DOWN)
		check_eq(gantry.get_meta("arrow"), "→", "ramp is on the travel-right side")
		var support: Dictionary = gantry.get_meta("support")
		var cell: Vector2i = support.highway_cell
		check(cell in [Vector2i(20, 17), Vector2i(20, 18)], "one or two tiles before the exit")
		_check_gantry(gantry, cell, f.topology.traffic_graph())
	_dispose(s)

func _check_gantry(gantry: Node3D, cell: Vector2i, graph: CityTrafficGraph) -> void:
	var support: Dictionary = gantry.get_meta("support")
	var tile := Rect2(Vector2(cell), Vector2.ONE)
	var bounds: AABB = gantry.get_meta("world_bounds")
	check(tile.encloses(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))), "whole gantry inside its highway tile")
	var deck: float = support.deck_height
	var lowest_overhead := INF
	var shoes := 0
	for node: Node in gantry.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var at: Node = mesh_node
		while at != gantry:
			t = (at as Node3D).transform * t
			at = at.get_parent()
		var box: AABB = gantry.transform * t * mesh_node.mesh.get_aabb()
		check(bounds.grow(.000001).encloses(box), String(mesh_node.name) + " inside measured bounds")
		var name := String(mesh_node.name)
		if name.begins_with("GantryShoe"):
			shoes += 1
			var foot := Vector2(box.get_center().x, box.get_center().z) - Vector2(cell)
			var shoulder := graph.point(cell, &"highway", foot).y - Gantries.SHOULDER_DROP
			check_lt(absf(box.position.y - shoulder), .0005, name + " rests on the carriageway shoulder")
			check_gt(absf((foot - Vector2(.5, .5)).length()), .45, name + " is outside the 0.92-tile lanes")
		elif not name.begins_with("GantryPost"):
			lowest_overhead = minf(lowest_overhead, box.position.y)
	check_eq(shoes, 2)
	check_gt((lowest_overhead - deck) * 16.0, 5.0, "truss and boards clear tall traffic by over 5 m")

func test_distance_gantries_after_interchanges_and_on_long_stretches() -> void:
	if not _available(): return
	var f := _highway([20, 40, 75])
	var s := _layer(f)
	var names := ["Flamingo Road", "Tropicana Avenue", "Russell Road"]
	for i: int in 3: check(s.names.assign(_keys([f.links[i]]), names[i], f.topology.revision).ok)
	check_eq(s.layer.diagnostics.size(), 0, "every gantry placed")
	var exit_cells: Array[Vector2i] = []
	for gantry: Node3D in _gantries(s.layer, "exit"): exit_cells.append(gantry.get_meta("support").highway_cell)
	exit_cells.sort()
	check_eq(exit_cells, [Vector2i(20, 18), Vector2i(20, 38), Vector2i(20, 73)])
	var rows_at: Dictionary = {}
	for gantry: Node3D in _gantries(s.layer, "distance"):
		var cell: Vector2i = gantry.get_meta("support").highway_cell
		rows_at[cell] = gantry.get_meta("display_rows")
		check_eq(gantry.get_meta("travel_direction"), Vector2i.DOWN)
		_check_gantry(gantry, cell, f.topology.traffic_graph())
	# Two tiles past each interchange, listing what lies ahead.
	check_eq(rows_at.get(Vector2i(20, 22)), [["Tropicana Avenue", "1¼ MI"], ["Russell Road", "3¼ MI"]])
	check_eq(rows_at.get(Vector2i(20, 42)), [["Russell Road", "2 MI"]])
	# A mile on, the open stretch repeats the next exit.
	check_eq(rows_at.get(Vector2i(20, 58)), [["Russell Road", "1 MI"]])
	check_eq(rows_at.size(), 3, "nothing beyond the last exit, nothing on the opposite carriageway")
	# Every row carries complete lettering in both columns.
	for gantry: Node3D in _gantries(s.layer, "distance"):
		var lettered: Array[String] = []
		for node: Node in gantry.find_children("*", "MeshInstance3D", true, false):
			if node.has_meta("complete_text"): lettered.append(node.get_meta("complete_text"))
		for row: Array in gantry.get_meta("display_rows"):
			check(lettered.has(row[0]) and lettered.has(row[1]), "row lettering " + str(row))
	_dispose(s)

func test_lots_lining_the_highway_never_hide_gantries() -> void:
	if not _available(): return
	var open := _highway([20, 40, 75])
	var lined := _highway([20, 40, 75], true)
	var keys: Array = []
	for f: Dictionary in [open, lined]:
		var s := _layer(f)
		for i: int in 3: check(s.names.assign(_keys([f.links[i]]), "Exit %d" % i, f.topology.revision).ok)
		var found: Array = []
		for kind: String in ["exit", "distance"]:
			for gantry: Node3D in _gantries(s.layer, kind): found.append([kind, gantry.get_meta("support").highway_cell])
		found.sort()
		keys.append(found)
		_dispose(s)
	check_eq(keys[1], keys[0], "identical gantries with buildings on both sides")
	check_gt(keys[0].size(), 4)

func test_gantry_refuses_crossings_ramp_mouths_and_bends() -> void:
	var f := _highway([20])
	var graph: CityTrafficGraph = f.topology.traffic_graph()
	check(Gantries.site(f.city, graph, Vector2i(20, 30), Vector2i.DOWN).ok, "plain straight carriageway")
	check_eq(Gantries.site(f.city, graph, Vector2i(20, 20), Vector2i.DOWN).reason, "Ramp mouth")
	check_eq(Gantries.site(f.city, graph, Vector2i(21, 30), Vector2i.DOWN).reason, "Opposite carriageway")
	check_eq(Gantries.site(f.city, graph, Vector2i(20, 30), Vector2i.RIGHT).reason, "Not straight along travel")
	f.city.building.put(20, 30, NetworkShapes.HIGHWAY_NS_ROAD_EW)
	check_eq(Gantries.site(f.city, graph, Vector2i(20, 30), Vector2i.DOWN).reason, "Crossing")
