# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Trees planted on building lots follow the lot's vegetation zone: palms in
## the desert, junipers and piñons in the woodland, pines and firs in the
## forest. Moving the zones re-plants exactly the lots whose zone changed.
extends "res://tests/exploration/async_test_case.gd"

const Landscaping := preload("res://scripts/view/city_lot_landscaping_3d.gd")
const Conifer := preload("res://scripts/view/city_conifer_3d.gd")
const Palm := preload("res://scripts/view/city_palm_3d.gd")
const Z := VegetationZones.Zone
## A 2x2 office whose courtyard palms were split out of the model.
const CODE := 150
const LOTS := [[Vector2i(20, 20), 2], [Vector2i(40, 20), 10], [Vector2i(60, 20), 20]]


static func _city() -> City:
	var city := flat_city(20000, 2)
	for lot: Array in LOTS:
		var at: Vector2i = lot[0]
		for y: int in range(at.y - 2, at.y + 4):
			for x: int in range(at.x - 2, at.x + 4): city.set_heights(x, y, lot[1], 0)
		city.stamp_building(at.x, at.y, CODE)
	city.vegetation = VegetationZones.make([true, true, true], [8, 16])
	return city


static func _rows(code: int) -> int:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Landscaping.PATH))
	for profile: Dictionary in data.entries:
		if int(profile.code) == code: return (profile.palms as Array).size()
	return 0


static func _count(node: Node, name: String) -> int:
	var total := 1 if node.name == name else 0
	for child: Node in node.get_children(): total += _count(child, name)
	return total


static func _lot(buildings: Node3D, anchor: Vector2i) -> Node3D:
	for child: Node in buildings.get_children():
		if child.get_meta("cell", Vector2i(-1, -1)) == anchor: return child
	return null


func test_planting_rows_cover_every_split_model() -> void:
	check_gt(_rows(CODE), 0, "the office plants its palm spots")
	for code: int in [145, 174, 204, 238, 251, 255]:
		check(Landscaping.has_trees(code), "%d plants its former built-in palms" % code)
	check(not Landscaping.has_trees(Buildings.TREES_1), "natural tree tiles are not lots")
	# Every planted model's rows were checked against its current geometry.
	var catalog := CityModelCatalog.new()
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	for code: int in catalog.entries:
		if Landscaping.has_trees(code):
			var model := Node3D.new()
			Landscaping.add_to(model, code, catalog.entries[code])
			check_eq(model.get_child_count(), 1, "%d planting matches its model" % code)
			model.free()


func test_upland_trees_fit_the_palm_spot() -> void:
	for zone: int in [Z.PINYON_JUNIPER, Z.PINE]:
		for index: int in 6:
			for spot: Array in [[0.35, 0.10], [0.6, 0.16], [1.1, 0.21]]:
				var tree := Landscaping.tree_for(zone, spot[0], spot[1], index)
				check(tree.has_node("TreeTrunk") and not tree.has_node("PalmTrunk"), "an upland tree replaces the palm")
				var species := [Conifer.Species.JUNIPER, Conifer.Species.PINYON] if zone == Z.PINYON_JUNIPER else [Conifer.Species.PINE, Conifer.Species.FIR]
				var size: Array = Conifer.SIZES[species[index % 2]][(index / 2) % 3]
				check(tree.scale.x * float(size[1]) <= float(spot[1]) + 0.000001, "the crown stays inside the palm's crown")
				check(tree.scale.x * float(size[0]) <= float(spot[0]) * Landscaping.FOREST_HEIGHT * 1.6, "the tree keeps a palm-like scale")
				tree.free()
	# Desert spots share a few palm meshes, scaled to each spot's height.
	var meshes := {}
	for spot: Array in [[0.27, 0.06], [0.4, 0.12], [0.425, 0.103], [0.6, 0.16], [0.9, 0.2], [1.5, 0.22]]:
		var palm := Landscaping.tree_for(Z.PALM, spot[0], spot[1], 0)
		check(palm.has_node("PalmTrunk"), "the desert keeps the shared grove palm")
		var trunk: CollisionShape3D = palm.get_node("PalmTrunk").get_child(0)
		check(is_equal_approx((trunk.shape as CylinderShape3D).height * palm.scale.x, spot[0]), "the palm stands at the spot's height")
		var fronds: MeshInstance3D = palm.get_child(palm.get_child_count() - 1)
		var exact := Palm.create(spot[0], spot[1])
		var reach: float = (exact.get_child(exact.get_child_count() - 1) as MeshInstance3D).mesh.get_aabb().size.x
		check(fronds.mesh.get_aabb().size.x * palm.scale.x <= reach * 1.001, "the crown is no wider than an exact palm for the spot")
		exact.free()
		meshes[fronds.mesh] = true
		palm.free()
	check(meshes.size() <= Landscaping.PALM_PROPORTIONS.size(), "palms share a handful of meshes")


func test_lots_follow_zones_and_replant_on_change() -> void:
	var city := _city()
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	await process_frame
	view.refresh()
	var rows := _rows(CODE)
	var expected := [Z.PALM, Z.PINYON_JUNIPER, Z.PINE]
	var ids: Array[int] = []
	for i: int in LOTS.size():
		var lot := _lot(view.buildings, LOTS[i][0])
		check(lot != null, "lot %d drawn" % i)
		if lot == null: continue
		ids.append(lot.get_instance_id())
		var palms := _count(lot, "PalmTrunk")
		var trees := _count(lot, "TreeTrunk")
		check_eq(palms, rows if expected[i] == Z.PALM else 0, "lot %d palms" % i)
		check_eq(trees, 0 if expected[i] == Z.PALM else rows, "lot %d upland trees" % i)
	if ids.size() != LOTS.size():
		view.free()
		return
	# Lower the pine line onto the woodland lot; the desert and forest lots keep their trees.
	city.vegetation = VegetationZones.make([true, true, true], [8, 9])
	view.refresh()
	check_eq(view.refresh_statistics.get("terrain_rebuilt_chunks", -1), 0, "no terrain is rebuilt")
	check_eq(view.refresh_statistics.get("lots", -1), 1, "only the lot whose zone changed is replaced")
	check_eq(_lot(view.buildings, LOTS[0][0]).get_instance_id(), ids[0], "the desert lot keeps its model")
	check_eq(_lot(view.buildings, LOTS[2][0]).get_instance_id(), ids[2], "the forest lot keeps its model")
	var moved := _lot(view.buildings, LOTS[1][0])
	check(moved.get_instance_id() != ids[1], "the woodland lot is re-planted")
	check_eq(_count(moved, "TreeTrunk"), rows, "the re-planted lot carries pines")
	# Switching the upland zones off brings every lot back to palms.
	city.vegetation = VegetationZones.make([true, false, false], [8, 9])
	view.refresh()
	for lot: Array in LOTS:
		check_eq(_count(_lot(view.buildings, lot[0]), "PalmTrunk"), rows, "palms return at level %d" % lot[1])
	# A fresh projection agrees with the regional updates.
	var fresh := CityBuildings3D.new()
	fresh.rebuild(city, view.catalog)
	for lot: Array in LOTS:
		check_eq(_count(_lot(fresh, lot[0]), "PalmTrunk"), rows, "fresh projection plants palms")
	fresh.free()
	view.free()
