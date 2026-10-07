# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Bridge structure parts connect: suspension cables meet their own towers,
## towers reach the ground, lift trusses reach their towers, rails stand on posts.
extends "res://tests/test_case.gd"
const Banks := preload("res://tests/test_bridge_approaches.gd")
const Net := preload("res://scripts/view/city_networks_3d.gd")

func _check_cable(codes: Array[int], label: String) -> void:
	var cable := Net.suspension_cable(codes)
	check(not cable.is_empty(), label + ": a suspension unit with towers has a cable")
	for i: int in codes.size():
		var h := Net.cable_height(cable, i + .5)
		if codes[i] in [82, 84]:
			check_lt(absf(h - Net.CABLE_TOP), .00001, label + ": cable meets the tower top at %d" % i)
		elif codes[i] < 81 or codes[i] > 85:
			check_eq(h, -1.0, label + ": no cable hangs over causeway cell %d" % i)
		else:
			check_lt(h, Net.CABLE_TOP, label + ": cable stays below the tower tops at %d" % i)
	# Sampled along the span the cable is continuous and never exceeds a tower.
	var previous := -2.0
	for step: int in codes.size() * 64 + 1:
		var h := Net.cable_height(cable, step / 64.0)
		if h >= 0 and previous >= 0:
			check_lt(absf(h - previous), .05, label + ": cable is continuous at %.3f" % (step / 64.0))
		check_lt(h, Net.CABLE_TOP + .00001, label + ": cable never rises above a tower top")
		previous = h

func test_each_suspension_unit_hangs_from_its_own_towers() -> void:
	_check_cable([87, 85, 84, 83, 82, 81, 85, 84, 83, 82, 81, 87] as Array[int], "imported pair")
	_check_cable([85, 84, 83, 82, 81] as Array[int], "imported single")
	_check_cable([81, 82, 83, 83, 83, 83, 83, 84, 85] as Array[int], "constructed")
	var cable := Net.suspension_cable([87, 85, 84, 83, 82, 81, 85, 84, 83, 82, 81, 87] as Array[int])
	check_lt(absf(Net.cable_height(cable, 1.0) - Net.CABLE_ANCHOR), .00001, "first unit anchors at its outer edge")
	check_lt(absf(Net.cable_height(cable, 6.0) - Net.CABLE_ANCHOR), .00001, "adjoining units anchor at their shared edge")
	check_lt(absf(Net.cable_height(cable, 3.5) - Net.CABLE_SAG), .00001, "cable sags between the two towers")
	check(Net.suspension_cable([87, 87, 87] as Array[int]).is_empty(), "causeways have no cable")

func _tower_legs(networks: CityNetworks3D) -> Array[MeshInstance3D]:
	var legs: Array[MeshInstance3D] = []
	for child: Node in networks.get_children():
		if child is MeshInstance3D and is_equal_approx((child as MeshInstance3D).mesh.size.x, .11):
			legs.append(child)
	return legs

func test_imported_towers_stand_on_the_ground_and_carry_their_cables() -> void:
	var towers := 0
	for path: String in Banks.bridge_cities():
		var loaded := Sc2Import.load(path)
		check(loaded.ok, "read-only import of " + path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var encoded := var_to_bytes(SaveFormat.encode_city(city))
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		for cell: Vector2i in networks._deck_profiles:
			var code := city.building.atv(cell)
			if code < 81 or code > 86: continue
			var profile: Dictionary = networks._deck_profiles[cell]
			networks._bridge_structure(city, cell, code)
			var legs := _tower_legs(networks)
			if code in [82, 84, 86]:
				towers += 1
				check_eq(legs.size(), 2, "%s %s tower has two legs" % [path.get_file(), cell])
				for leg: MeshInstance3D in legs:
					var bottom := leg.transform * Vector3(0, -leg.mesh.size.y * .5, 0)
					var top := leg.transform * Vector3(0, leg.mesh.size.y * .5, 0)
					var ground := CityGeometry3D.point_on_ground(city, cell, Vector2(bottom.x - cell.x, bottom.z - cell.y))
					check_lt(bottom.y - ground.y, .00001, "%s %s tower leg reaches the ground" % [path.get_file(), cell])
					if code != 86:
						check_lt(absf(top.y - (float(profile.deck) + Net.CABLE_TOP + .05)), .00001, "%s %s tower top carries the cable" % [path.get_file(), cell])
						var t: float = .5
						check_lt(absf(Net.cable_height(profile.get("cable", []), int(profile.index) + t) - Net.CABLE_TOP), .00001, "%s %s cable reaches this tower" % [path.get_file(), cell])
			else:
				check_eq(legs.size(), 0, "%s %s has no tower without a tower tile" % [path.get_file(), cell])
			for child: Node in networks.get_children():
				networks.remove_child(child)
				child.free()
			networks._faces.clear()
			networks._colors.clear()
			networks._cells.clear()
		check_eq(var_to_bytes(SaveFormat.encode_city(city)), encoded, "checking towers leaves the city unchanged")
		networks.free()
	check_gt(towers, 0, "the checked cities contain bridge towers")

func test_lift_truss_reaches_its_towers_and_rails_stand_on_posts() -> void:
	for ew: bool in [false, true]:
		var city := Banks.bank_city(ew, 4, 87)
		var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
		for i: int in 4:
			city.building.putv(Vector2i(22, 22) + direction * i, [86, 88, 88, 86][i])
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		var tower := Vector2i(22, 22)
		networks._bridge_structure(city, tower, 86)
		var chords: Array[Vector3] = []
		for child: Node in networks.get_children():
			if child is MeshInstance3D and is_equal_approx((child as MeshInstance3D).mesh.size.x, .055):
				chords.append((child as MeshInstance3D).position)
		check_eq(chords.size(), 4, "a lift tower carries two truss segments per side toward its span")
		for chord: Vector3 in chords:
			var along := chord.x - tower.x if ew else chord.z - tower.y
			check_gt(along, .5, "truss segments lie on the lift-span side of the tower")
		var deck: float = networks._deck_profiles[tower].deck
		var posts := 0
		for i: int in range(0, networks._faces.size(), 3):
			var top := maxf(networks._faces[i].y, maxf(networks._faces[i + 1].y, networks._faces[i + 2].y))
			var bottom := minf(networks._faces[i].y, minf(networks._faces[i + 1].y, networks._faces[i + 2].y))
			if absf(bottom - deck) < .00001 and absf(top - (deck + .13)) < .00001: posts += 1
		# Four posts per side, four faces of two triangles each.
		check_eq(posts, 4 * 2 * 4 * 2, "guard rails stand on posts that reach the deck")
		networks.free()
