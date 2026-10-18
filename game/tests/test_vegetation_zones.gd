# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Altitude vegetation zones: validated settings, automatic zones from the
## terrain, zone lookup with any one or two zones switched off, save
## round trips, zone tree names, the upland tree models and the network
## layer redrawing exactly the groves whose zone changed.
extends "res://tests/test_case.gd"

const Conifer := preload("res://scripts/view/city_conifer_3d.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
const Z := VegetationZones.Zone


static func _settings(enabled: Array, cutoffs: Array) -> Dictionary:
	return VegetationZones.make(enabled, cutoffs)


func test_sanitize_accepts_only_complete_records() -> void:
	var good := _settings([true, true, true], [10, 20])
	check_eq(VegetationZones.sanitize(good), good, "a complete record is kept")
	check_eq(VegetationZones.sanitize({"version": 1.0, "enabled": [true, false, true], "cutoffs": [3.0, 9.0]}),
		_settings([true, false, true], [3, 9]), "JSON numbers become integers")
	for bad: Variant in [null, {}, "x", {"version": 2, "enabled": [true, true, true], "cutoffs": [1, 2]},
			{"version": 1, "enabled": [false, false, false], "cutoffs": [1, 2]},
			{"version": 1, "enabled": [true, true], "cutoffs": [1, 2]},
			{"version": 1, "enabled": [true, 1, true], "cutoffs": [1, 2]},
			{"version": 1, "enabled": [true, true, true], "cutoffs": [5, 4]},
			{"version": 1, "enabled": [true, true, true], "cutoffs": [-1, 4]},
			{"version": 1, "enabled": [true, true, true], "cutoffs": [1, 33]},
			{"version": 1, "enabled": [true, true, true], "cutoffs": [1.5, 4]},
			{"version": 1, "enabled": [true, true, true], "cutoffs": [1, 4], "extra": 1}]:
		check_eq(VegetationZones.sanitize(bad), {}, "rejects %s" % str(bad))


func test_zone_for_level_with_zones_switched_off() -> void:
	var cuts := [10, 20]
	var cases := [
		[[true, true, true], [[0, Z.PALM], [9, Z.PALM], [10, Z.PINYON_JUNIPER], [19, Z.PINYON_JUNIPER], [20, Z.PINE], [31, Z.PINE]]],
		[[false, true, true], [[0, Z.PINYON_JUNIPER], [19, Z.PINYON_JUNIPER], [20, Z.PINE]]],
		[[true, false, true], [[9, Z.PALM], [10, Z.PINE], [25, Z.PINE]]],
		[[true, true, false], [[9, Z.PALM], [10, Z.PINYON_JUNIPER], [31, Z.PINYON_JUNIPER]]],
		[[true, false, false], [[0, Z.PALM], [31, Z.PALM]]],
		[[false, true, false], [[0, Z.PINYON_JUNIPER], [31, Z.PINYON_JUNIPER]]],
		[[false, false, true], [[0, Z.PINE], [31, Z.PINE]]],
	]
	for case: Array in cases:
		var settings := _settings(case[0], cuts)
		for probe: Array in case[1]:
			check_eq(VegetationZones.zone_for_level(settings, probe[0]), probe[1], "%s level %d" % [str(case[0]), probe[0]])


func test_editing_keeps_invariants() -> void:
	var s := _settings([true, true, true], [10, 20])
	check_eq(VegetationZones.with_cutoff(s, 0, 25).cutoffs, [25, 25], "raising the palm line pushes the pine line")
	check_eq(VegetationZones.with_cutoff(s, 1, 4).cutoffs, [4, 4], "lowering the pine line pushes the palm line")
	check_eq(VegetationZones.with_cutoff(s, 1, 99).cutoffs, [10, 32], "cutoffs clamp to the level range")
	var one := _settings([false, true, false], [10, 20])
	check_eq(VegetationZones.with_enabled(one, Z.PINYON_JUNIPER, false), one, "the last enabled zone stays on")
	check_eq(VegetationZones.with_enabled(s, Z.PALM, false).enabled, [false, true, true], "a zone switches off")
	check_eq(VegetationZones.boundary_cutoff(Z.PALM), 0, "the boundary after palms moves cutoff 0")
	check_eq(VegetationZones.boundary_cutoff(Z.PINYON_JUNIPER), 1, "the boundary after woodland moves cutoff 1")


static func _hill_city(lo: int, hi: int) -> City:
	var city := City.new()
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			city.set_heights(x, y, lo + int(round(float(hi - lo) * x / float(City.WIDTH - 1))))
	return city


func test_automatic_zones_follow_relief() -> void:
	var flat := _hill_city(4, 4)
	check_eq(VegetationZones.resolve(flat).cutoffs, [32, 32], "flat desert is all palms")
	check(VegetationZones.resolve(flat).automatic, "no saved choice means automatic")
	var moderate := _hill_city(4, 12)
	var relief := VegetationZones.relief_range(VegetationZones.histogram(moderate)[0])
	check_eq(VegetationZones.resolve(moderate).cutoffs, [relief.x + ceili((relief.y - relief.x) * 0.6), 32], "moderate relief adds woodland only")
	var high := _hill_city(2, 26)
	relief = VegetationZones.relief_range(VegetationZones.histogram(high)[0])
	check_eq(relief, Vector2i(2, 26), "a broad slope keeps its whole relief")
	check_eq(VegetationZones.resolve(high).cutoffs, [2 + 12, 2 + ceili(24 * 0.78)], "high relief adds pines")
	# A small edit above the peak or below the floor cannot move the zones.
	var before: Array = VegetationZones.resolve(high).cutoffs
	high.set_heights(64, 64, 31)
	high.set_heights(65, 64, 31)
	high.set_heights(10, 10, 0)
	check_eq(VegetationZones.resolve(high).cutoffs, before, "single-tile edits leave automatic zones in place")
	var spike := _hill_city(4, 4)
	for x: int in 20: spike.set_heights(x, 0, 28)
	check_eq(VegetationZones.resolve(spike).cutoffs, [32, 32], "one narrow spike does not turn a flat city to forest")
	# Editing terrain refreshes the cached automatic zones.
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH: high.set_heights(x, y, 3)
	check_eq(VegetationZones.resolve(high).cutoffs, [32, 32], "levelled terrain returns to palms")
	var real := _hill_city(2, 30)
	real.terrain_origin = {"diagnostics": {"source_min_metres": 900.0, "metres_per_level": 50.0}}
	# 1,500 m is level 2 + 600 / 50 = 14; 2,100 m is level 26.
	check_eq(VegetationZones.resolve(real).cutoffs, [14, 26], "real-world cities use real elevations")
	check(is_equal_approx(VegetationZones.metres_for_level(real, 14), 1500.0), "level 14 stands at 1,500 m")
	check(is_equal_approx(VegetationZones.metres_for_level(flat, 10), 10 * VegetationZones.METRES_PER_LEVEL), "other cities measure from level 0")
	var saved := _settings([true, false, true], [7, 9])
	real.vegetation = saved.duplicate(true)
	var resolved := VegetationZones.resolve(real)
	check(not resolved.automatic and resolved.cutoffs == [7, 9] and resolved.enabled == [true, false, true], "a saved choice wins")


func test_histogram_and_names() -> void:
	var city := _hill_city(2, 26)
	city.terrain.put(0, 0, Terrain.SURFACE)
	var bins := VegetationZones.histogram(city)
	var total := 0
	for n: int in bins[0]: total += n
	check_eq(total, City.WIDTH * City.HEIGHT - 1, "every dry tile counted once, water left out")
	city.building.put(127, 5, Buildings.TREES_7)
	city.building.put(0, 5, Buildings.TREES_1)
	city.vegetation = _settings([true, true, true], [10, 20])
	check_eq(VegetationZones.tree_name(city, Vector2i(0, 5), Buildings.TREES_1), "Lone Palm", "low trees are palms")
	check_eq(VegetationZones.tree_name(city, Vector2i(127, 5), Buildings.TREES_7), "Pine Forest", "high trees are pines")
	city.vegetation = _settings([false, true, false], [10, 20])
	check_eq(VegetationZones.tree_name(city, Vector2i(0, 5), Buildings.TREES_1), "Lone Juniper", "a single zone covers every level")
	check_eq(VegetationZones.zone_tree_counts(city, VegetationZones.resolve(city)), PackedInt32Array([0, 2, 0]), "tree tiles counted per zone")
	check_eq(Buildings.display_name(Buildings.TREES_1), "Lone Palm", "generic building names are unchanged")


func test_save_round_trip() -> void:
	var city := _hill_city(2, 20)
	var doc := SaveFormat.encode_city(city)
	check(not doc.has("vegetation"), "automatic zones are not written")
	check_eq(SaveFormat.decode_city(doc).city.vegetation, {}, "and load as automatic")
	city.vegetation = _settings([true, false, true], [8, 15])
	doc = SaveFormat.encode_city(city)
	check_eq(doc.vegetation, city.vegetation, "a chosen setting is written")
	var json: Variant = JSON.parse_string(JSON.stringify(doc))
	check_eq(SaveFormat.decode_city(json).city.vegetation, city.vegetation, "and survives JSON")
	json.vegetation = {"version": 1, "enabled": [false, false, false], "cutoffs": [1, 2]}
	check_eq(SaveFormat.decode_city(json).city.vegetation, {}, "a damaged choice falls back to automatic")


func test_upland_tree_models() -> void:
	for zone: int in [Z.PINYON_JUNIPER, Z.PINE]:
		var previous := 0
		for density: int in 7:
			var grove := Conifer.grove(Vector2i(17, 40), Buildings.TREES_1 + density, zone)
			check_gt(grove.size(), previous, "zone %d density %d plants more trees" % [zone, density + 1])
			previous = grove.size()
			for placement: Array in grove:
				var root: Vector2 = placement[0]
				check(root.x > 0.08 and root.x < 0.92 and root.y > 0.08 and root.y < 0.92, "roots stay inside the tile")
				check((placement[1] >= Conifer.Species.PINE) == (zone == Z.PINE), "zone species")
		check_eq(Conifer.grove(Vector2i(3, 9), Buildings.TREES_1 + 3, zone), Conifer.grove(Vector2i(3, 9), Buildings.TREES_1 + 3, zone), "layouts are deterministic")
	check_ne(Conifer.grove(Vector2i(3, 9), Buildings.TREES_1 + 3, Z.PINE), Conifer.grove(Vector2i(4, 9), Buildings.TREES_1 + 3, Z.PINE), "neighbors vary")
	for species: int in 4:
		for variant: int in 3:
			var tree := Conifer.create(species, variant)
			var crown: MeshInstance3D = tree.get_child(2)
			var mesh: ArrayMesh = crown.mesh
			check(Conifer.is_static_crown_material(mesh.surface_get_material(0)), "crown joins the static batches")
			check(Batcher._material_supported(mesh.surface_get_material(0)), "batcher admits the crown")
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var top := 0.0
			for v: Vector3 in vertices: top = maxf(top, v.y)
			check_between(top, Conifer.SIZES[species][variant][0] * 0.85, Conifer.SIZES[species][variant][0] * 1.05, "crown reaches the tree height")
			var lods: Array = mesh.get("_surfaces")[0].get("lods", [])
			check_eq(lods.size(), 4, "two crown LODs")
			var count := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			for level: int in 2:
				var bytes: PackedByteArray = lods[level * 2 + 1]
				check(bytes.size() / 2 < count and bytes.size() > 0 and bytes.size() % 6 == 0, "LOD keeps fewer whole triangles")
				for i: int in range(0, bytes.size(), 2): check(bytes.decode_u16(i) < count, "LOD index in range")
			var body: StaticBody3D = tree.get_node("TreeTrunk")
			check(body.collision_layer == 4 and body.collision_mask == 0, "walkers meet the tree")
			var twin := Conifer.create(species, variant)
			check(twin.get_child(2).mesh == mesh, "identical trees share their crown")
			twin.free()
			tree.free()


static func _tree_cells(root: Node) -> Dictionary:
	var out := {}
	for child: Node in root.get_children():
		if child is CityNetworks3D:
			var inner := _tree_cells(child)
			for key: Variant in inner: out[key] = out.get(key, 0) + inner[key]
		elif child.has_node("PalmTrunk"):
			out["palm"] = out.get("palm", 0) + 1
		elif child.has_node("TreeTrunk"):
			out["tree"] = out.get("tree", 0) + 1
	return out


func test_network_layer_follows_zones() -> void:
	var city := _hill_city(2, 26)
	# Lone trees across the slope: level grows with x.
	for x: int in range(4, 124, 8): city.building.put(x, 64, Buildings.TREES_1)
	city.vegetation = _settings([true, false, false], [32, 32])
	var layer := CityNetworks3D.new()
	var regions: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, 16):
		for x: int in range(0, City.WIDTH, 16): regions.append(Rect2i(x, y, 16, 16))
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	layer.update_regions(city, regions, 16)
	CityGeometry3D.end_ground_sampling(sampling)
	var counts := _tree_cells(layer)
	check_eq(int(counts.get("tree", 0)), 0, "palms only")
	check_gt(int(counts.get("palm", 0)), 0, "palms drawn")
	city.vegetation = _settings([true, true, true], [12, 20])
	sampling = CityGeometry3D.begin_ground_sampling(city)
	var changed := layer.update_regions(city, regions, 16)
	CityGeometry3D.end_ground_sampling(sampling)
	var expected := {}
	for x: int in range(4, 124, 8):
		if city.ground_height(x, 64) >= 12: expected[Vector2i(x / 16 * 16, 64)] = true
	var origins := {}
	for region: Rect2i in changed: origins[region.position] = true
	check_eq(origins, expected, "only chunks with a tree changing zone are redrawn")
	var fresh := CityNetworks3D.new()
	fresh.rebuild(city)
	var upland := 0
	for x: int in range(4, 124, 8):
		if city.ground_height(x, 64) >= 12: upland += Conifer.grove(Vector2i(x, 64), Buildings.TREES_1, VegetationZones.zone_at(city, Vector2i(x, 64))).size()
	check_eq(int(_tree_cells(layer).get("tree", 0)), upland, "regional update plants the upland trees")
	check_eq(int(_tree_cells(fresh).get("tree", 0)), upland, "a fresh projection agrees")
	layer.free()
	fresh.free()
