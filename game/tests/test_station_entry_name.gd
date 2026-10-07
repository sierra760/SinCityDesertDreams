# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")

class StationWorld extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

func _named_signs(node: Node, found: Array[Node3D]) -> void:
	if node.has_meta("station_entry_name"): found.append(node)
	for child: Node in node.get_children(): _named_signs(child,found)

func _check_sign(sign: Node3D, title: String) -> void:
	check_eq(sign.get_meta("station_entry_name"),title,"entry uses the route picker station name")
	var letters: MeshInstance3D=sign.get_node("StationName")
	var board: MeshInstance3D=sign.get_node("NameplateFace")
	check_eq(letters.mesh.text,title.to_upper())
	check(letters.mesh.font.get_font_name().begins_with("BioRhyme"))
	var bounds: AABB=letters.transform*letters.mesh.get_aabb()
	var face: AABB=board.transform*board.mesh.get_aabb()
	check(bounds.position.x>face.position.x+.005 and bounds.end.x<face.end.x-.005,"name fits inside the cabinet horizontally")
	check(bounds.position.y>face.position.y and bounds.end.y<face.end.y-.002,"name stays below the canopy and inside its sign")
	check(bounds.position.z<face.position.z,"lettering faces out from the opaque sign face")
	check(face.position.z<-.495,"sign face covers generic baked lettering")
	check(bounds.position.y>.205,"name is above the entry door")

func test_build_and_explore_entries_match_their_station_names() -> void:
	var city := Fixtures.subway_city()
	var before := SaveFormat.encode_city(city)
	var graph := CityTrafficGraph.new(); graph.bind_city(city)
	var network := ExploreTransitNetwork.new(); network.rebuild(city,graph,1)
	var catalog := CityModelCatalog.new(); check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var buildings := CityBuildings3D.new();root.add_child(buildings);buildings.rebuild(city,catalog)
	var world := StationWorld.new();root.add_child(world);world.network=network;world.build(network.route(0,1))
	for layer: Node in [buildings,world]:
		var signs: Array[Node3D]=[];_named_signs(layer,signs)
		check_eq(signs.size(),2,"each exterior entry has an individual station name")
		for i: int in signs.size(): _check_sign(signs[i],network.stations[i].name)
	check_eq(SaveFormat.encode_city(city),before,"naming is presentation only")
	world.free();buildings.free();await physics_frame

func test_long_station_names_fit_the_same_mounted_cabinet() -> void:
	var world := StationWorld.new();root.add_child(world)
	var title := "Desert Transit Convention Center"
	world._elevator_access({"name":title,"position":Vector3(20,2,20),"surface":3.0,"yaw":PI*.5,"side":1,"platform":Vector3(20.24,2.025,20),"normal":Vector3.RIGHT})
	var signs: Array[Node3D]=[];_named_signs(world,signs)
	check_eq(signs.size(),1)
	if not signs.is_empty(): _check_sign(signs[0],title)
	world.free();await physics_frame
