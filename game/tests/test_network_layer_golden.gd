# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Complete chunked network-layer output of three bundled cities, as actual
## Main projects it. Performance work must not move a vertex: regenerate these
## hashes with tools/golden_networks.gd only for a deliberate geometry change.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")

const GOLDEN := {
	"La Presa": ["6440625dd7b2b7ca88e687795729a272c281a9eee6d955b0772d697b41ba37e2", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "391969a38375712d47acb25d2760d9e34536a71aaa94f5286d546148bc7a1f28", "9464c68b32a9fb86ff6bad13e26026b58ec0b5aa58bd54033f89ee4670b2d53b", "347b032a0e67fb6ee44f821dbf923a5e47328544465c055fa365889a1052d065"],
	"Valle del Mar": ["8b6cf5855288b308d1127e80bfb6017a665e8696d03d98e4e0acdf6f7eb2341e", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "cf10cc3f0146890050c1bbebafabb5a072a06b7a0695b3f5cf1c09d3aabe6dae", "983a8915a137abd62fe7acbac47cb25e78627e0a8e6558f7e346f006d9a18f83", "6fbd4096069bb58f510289890942dd9c9ea9f045be80ed2f024a16de14e20235"],
	"Salton Shores": ["ef88daff67f893271aceed9f19a604c68320aee82f79a3ef044fdab90b160853", "1afd3474220fb5191a1a1a209ad2ec3b52d4529af740756c49e88307fe708956", "66aa160616d9eff2a598ec080de6638d8d43ce28d24fd431b840688c3978acbc", "211e9ec6b3881a2a513f888bfb7695136c34ee08d33243a225f1c35e6f6d74ed", "c64eb47752d731fff4a0a3254e137ac2031ba3f67dd777c3c597c2a3a5330b0d"],
}
# Cities whose projection differs on Windows, which rounds some engine math
# differently.
const PLATFORM_GOLDEN := {
	"Windows": {
		"La Presa": ["7eceaf87759067354c8b149a1456683700ef1e6e0151f94cd98d50b1178976d4", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "391969a38375712d47acb25d2760d9e34536a71aaa94f5286d546148bc7a1f28", "9464c68b32a9fb86ff6bad13e26026b58ec0b5aa58bd54033f89ee4670b2d53b", "347b032a0e67fb6ee44f821dbf923a5e47328544465c055fa365889a1052d065"],
		"Valle del Mar": ["232fbcc9cd78123864613a3a4476635deb1febd74bfcb8cf2fcd02af84b3bace", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "cf10cc3f0146890050c1bbebafabb5a072a06b7a0695b3f5cf1c09d3aabe6dae", "983a8915a137abd62fe7acbac47cb25e78627e0a8e6558f7e346f006d9a18f83", "6fbd4096069bb58f510289890942dd9c9ea9f045be80ed2f024a16de14e20235"],
	},
}

static func sha(value: Variant) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value))
	return h.finish().hex_encode()

## [visible, tunnels, physical, boxes, obstacles] hashes of one city's chunked projection.
static func hashes(city: City) -> Array[String]:
	var root := CityNetworks3D.new()
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	root.update_regions(city, [], 16)
	CityGeometry3D.end_ground_sampling(sampling)
	var origins: Array = root._regions.keys()
	origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var cells: Array[Vector2i] = []
	var tunnel := [PackedVector3Array(), PackedColorArray(), [], PackedVector3Array(), PackedColorArray(), []]
	for origin: Vector2i in origins:
		var part: CityNetworks3D = root._regions[origin]
		faces.append_array(part._faces)
		colors.append_array(part._colors)
		cells.append_array(part._cells)
		tunnel[0].append_array(part._tunnel_faces)
		tunnel[1].append_array(part._tunnel_colors)
		tunnel[2].append_array(part._tunnel_cells)
		tunnel[3].append_array(part._tunnel_shell_faces)
		tunnel[4].append_array(part._tunnel_shell_colors)
		tunnel[5].append_array(part._tunnel_shell_cells)
	var result: Array[String] = [sha([faces, colors, cells]), sha(tunnel),
		sha([root._physical_cells, root._physical_groups, root._physical_roles, root._physical_depths, root._physical_triangles]),
		sha(root._physical_boxes), sha(root._physical_obstacles)]
	root.free()
	return result

func test_bundled_cities_project_exactly() -> void:
	var golden: Dictionary = Hashes.for_platform(GOLDEN, PLATFORM_GOLDEN)
	for name: String in golden:
		var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
		check(loaded.ok, "%s imports" % name)
		if not loaded.ok: continue
		var actual := hashes(loaded.city)
		var expected: Array = golden[name]
		for i: int in expected.size():
			if String(expected[i]).is_empty(): continue
			check_eq(actual[i], expected[i], "%s %s hash" % [name, ["visible", "tunnels", "physical", "boxes", "obstacles"][i]])
		print("NETWORK_GOLDEN %s %s" % [name, actual])
