# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rubble (1-4) and contaminated ground (5) draw the authored Blender kit:
## draped heaps/stains on the terrain facets plus rigid debris that never
## floats above flat, sloped or creased ground, batches, and blocks walkers
## with its solid pieces.
extends "res://tests/test_case.gd"

const Rubble := preload("res://scripts/view/city_rubble_3d.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
const CODES := [1, 2, 3, 4, 5]


static func _hill_city() -> City:
	var city := flat_city(20000, 2)
	# A one-level-per-tile hillside plus an isolated knoll give planar slopes and creases.
	for y: int in City.HEIGHT:
		for x: int in range(20, 26): city.set_heights(x, y, 2 + (x - 19), 0)
		for x: int in range(26, City.WIDTH): city.set_heights(x, y, 8, 0)
	city.set_heights(40, 40, 3, 0)
	return city


static func _pieces(layer: CityNetworks3D, cell: Vector2i) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var bounds := Rect2(Vector2(cell), Vector2.ONE)
	for part: CityNetworks3D in layer._regions.values():
		for node: Node in part.get_children():
			if node is MeshInstance3D and node.get_parent() == part and bounds.grow(.02).has_point(Vector2(node.position.x, node.position.z)) \
					and node.has_meta(&"rubble_piece"):
				found.append(node)
	return found


func _bodies(layer: CityNetworks3D, cell: Vector2i) -> int:
	var count := 0
	for part: CityNetworks3D in layer._regions.values():
		for node: Node in part.get_children():
			if node is StaticBody3D and node.has_meta(&"rubble_solid") and floori(node.position.x) == cell.x and floori(node.position.z) == cell.y:
				check_eq(node.collision_layer, 4, "solid rubble blocks walkers like palm trunks")
				count += 1
	return count


static func _ground(city: City, at: Vector3) -> float:
	var cell := Vector2i(floori(at.x), floori(at.z))
	return CityGeometry3D.point_on_ground(city, cell, Vector2(at.x - cell.x, at.z - cell.y)).y


func _place(city: City, cells: Array[Vector2i]) -> CityNetworks3D:
	for i: int in cells.size(): city.building.putv(cells[i], CODES[i % CODES.size()])
	var layer := CityNetworks3D.new()
	layer.update_regions(city, [])
	return layer


func test_every_code_draws_its_complete_variant() -> void:
	var city := flat_city()
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(7, 5), Vector2i(9, 5), Vector2i(11, 5), Vector2i(13, 5)]
	var layer := _place(city, cells)
	var names: Array = []
	for i: int in cells.size():
		var kit: Dictionary = Rubble.variant(CODES[i])
		var groups: Array = kit.pieces.filter(func(p: Dictionary) -> bool: return String(p.name).begins_with("Debris"))
		var solids: Array = kit.pieces.filter(func(p: Dictionary) -> bool: return p.solid)
		check(groups.size() >= 3 and solids.size() >= 1, "variant %d has grouped debris and solid pieces" % CODES[i])
		check_eq(groups.size() + solids.size(), kit.pieces.size(), "variant %d pieces are debris groups or solids" % CODES[i])
		check(kit.drapes.size() >= 2, "variant %d has a draped heap or stain" % CODES[i])
		check_eq(_pieces(layer, cells[i]).size(), kit.pieces.size(), "every piece of variant %d is placed" % CODES[i])
		check_eq(_bodies(layer, cells[i]), kit.pieces.filter(func(p: Dictionary) -> bool: return p.solid).size(), "solid pieces of variant %d get bodies" % CODES[i])
		var meshes: Array = kit.pieces.map(func(p: Dictionary) -> Mesh: return p.mesh)
		names.append(meshes)
	for a: int in names.size():
		for b: int in range(a + 1, names.size()):
			check(names[a] != names[b], "variants %d and %d differ" % [CODES[a], CODES[b]])
	var triangles: Dictionary = {}
	for part: CityNetworks3D in layer._regions.values():
		for cell: Vector2i in part._cells: triangles[cell] = int(triangles.get(cell, 0)) + 1
	for i: int in cells.size():
		var expected := 0
		for drape: Array in Rubble.variant(CODES[i]).drapes: expected += (drape[1] as PackedColorArray).size()
		check_eq(int(triangles.get(cells[i], 0)), expected, "variant %d drapes all its ground triangles" % CODES[i])
	layer.free()


func test_drapes_and_pieces_stay_on_flat_sloped_and_creased_ground() -> void:
	var city := _hill_city()
	var cells: Array[Vector2i] = [Vector2i(5, 30), Vector2i(21, 10), Vector2i(22, 20), Vector2i(23, 30), Vector2i(24, 40),
		Vector2i(39, 39), Vector2i(40, 39), Vector2i(39, 40), Vector2i(41, 41), Vector2i(19, 12)]
	var layer := _place(city, cells)
	var sloped := 0
	for cell: Vector2i in cells:
		var corners := CityGeometry3D.ground_corners(city, cell)
		var lowest := INF
		var highest := -INF
		for corner: Vector3 in corners:
			lowest = minf(lowest, corner.y)
			highest = maxf(highest, corner.y)
		if highest - lowest > .1: sloped += 1
		var code := city.building.atv(cell)
		var floating := 0.0
		var buried := 0.0
		for model: MeshInstance3D in _pieces(layer, cell):
			var bounds := model.mesh.get_aabb()
			var piece: Dictionary = Rubble.variant(code).pieces[int(model.get_meta(&"rubble_piece"))]
			var gaps: Array[float] = []
			var authored: Array[float] = []
			for x: float in [bounds.position.x, bounds.end.x]:
				for z: float in [bounds.position.z, bounds.end.z]:
					var corner := Vector3(x, bounds.position.y, z)
					var world := model.transform * corner
					gaps.append(world.y - _ground(city, world) - Rubble.LIFT)
					authored.append((piece.transform * corner).y * Rubble.METRES)
			# The lowest support rests as authored; leaning pieces may lift their far edge.
			var support: float = gaps.min() - maxf(authored.min(), 0.0)
			floating = maxf(floating, support)
			buried = minf(buried, gaps.min())
			# Pieces lying flat touch at every corner, including across creases.
			if authored.max() - authored.min() < .015:
				for k: int in gaps.size(): floating = maxf(floating, gaps[k] - maxf(authored[k], 0.0) - .004)
		check(floating <= .004, "no debris corner floats above %s ground (%s): %.4f" % [cell, "sloped" if highest - lowest > .1 else "flat", floating])
		check(buried > -.2, "debris stays visible on %s: %.4f" % [cell, buried])
		for part: CityNetworks3D in layer._regions.values():
			for t: int in part._cells.size():
				if part._cells[t] != cell: continue
				for k: int in 3:
					var vertex: Vector3 = part._faces[t * 3 + k]
					check(vertex.y >= _ground(city, vertex) + Rubble.LIFT - .0005, "drape vertex stays above %s ground" % cell)
	check(sloped >= 6, "fixture exercises sloped and creased tiles, got %d" % sloped)
	layer.free()


func test_debris_shares_meshes_and_batches() -> void:
	var city := flat_city()
	city.building.put(4, 4, 2)
	city.building.put(40, 40, 2)
	var layer := CityNetworks3D.new()
	layer.update_regions(city, [])
	var a := _pieces(layer, Vector2i(4, 4))
	var b := _pieces(layer, Vector2i(40, 40))
	check_eq(a.size(), b.size(), "same variant places the same pieces")
	var shared := 0
	for model: MeshInstance3D in a:
		for other: MeshInstance3D in b:
			if other.mesh == model.mesh: shared += 1; break
		check(model.material_override == null, "kit surfaces keep their shared materials")
		for surface: int in model.mesh.get_surface_count():
			var material := model.mesh.surface_get_material(surface)
			check(material is BaseMaterial3D and Batcher._material_supported(material), "kit material is opaque and batchable")
		check(model.basis.determinant() > 0.0, "placement keeps a positive determinant for instancing")
	check_eq(shared, a.size(), "two cells share every debris mesh resource")
	layer.free()


func test_placement_is_deterministic_and_varied() -> void:
	var city := flat_city()
	var cells: Array[Vector2i] = []
	for x: int in range(10, 18):
		cells.append(Vector2i(x, 20))
		city.building.put(x, 20, 1)
	var first := CityNetworks3D.new()
	first.update_regions(city, [])
	var second := CityNetworks3D.new()
	second.update_regions(city, [])
	var turns: Dictionary = {}
	for cell: Vector2i in cells:
		turns[Rubble.quarter_turns(cell)] = true
		var a := _pieces(first, cell)
		var b := _pieces(second, cell)
		check_eq(a.size(), b.size(), "same pieces on rebuild")
		for i: int in mini(a.size(), b.size()): check(a[i].transform.is_equal_approx(b[i].transform), "same transform on rebuild")
	check(turns.size() >= 3, "neighbouring rubble tiles turn differently")
	first.free()
	second.free()


func test_incremental_rebuild_replays_rubble() -> void:
	var city := flat_city()
	city.building.put(6, 6, 3)
	city.building.put(9, 6, 5)
	var layer := CityNetworks3D.new()
	layer.update_regions(city, [])
	var before := _pieces(layer, Vector2i(6, 6)).map(func(m: MeshInstance3D) -> Transform3D: return m.transform)
	city.building.put(14, 14, Buildings.ROAD_FIRST)
	layer.update_regions(city, [Rect2i(0, 0, 16, 16)])
	var after := _pieces(layer, Vector2i(6, 6)).map(func(m: MeshInstance3D) -> Transform3D: return m.transform)
	check_eq(after.size(), before.size(), "untouched rubble keeps its debris after a nearby edit")
	for i: int in mini(before.size(), after.size()): check(before[i].is_equal_approx(after[i]), "replayed rubble keeps its placement")
	check_eq(_bodies(layer, Vector2i(9, 6)), Rubble.variant(5).pieces.filter(func(p: Dictionary) -> bool: return p.solid).size(), "replayed contamination keeps its bodies")
	city.building.put(6, 6, Buildings.NONE)
	layer.update_regions(city, [Rect2i(0, 0, 16, 16)])
	check_eq(_pieces(layer, Vector2i(6, 6)).size(), 0, "cleared rubble removes its debris")
	layer.free()
