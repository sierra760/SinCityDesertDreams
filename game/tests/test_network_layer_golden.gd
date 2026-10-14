# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Complete chunked network-layer output of three bundled cities, as actual
## Main projects it. Performance work must not move a vertex: regenerate these
## hashes with tools/golden_networks.gd only for a deliberate geometry change.
extends "res://tests/test_case.gd"

const GOLDEN := {
	"La Presa": ["937c1bdffb559eb4b62f025ba7f39a8713a1b039f471dbeb43545398288099df", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "261796cb069db2b083fd44d2283585504b30a90575e20dcbe96c7fd2cf9c75ca", "4c1478e1d48e6bd55c48cfc9260f40caf271c9f1bf53015d75544ee0e830e050", "abac17f420fe294f5635d18ca08a81529c876f4215d9d6e521b2517e578df1bf"],
	"Valle del Mar": ["e2e5da39bdf30f82fd9a1bd3a88b8f1d37f46e3d24b21dddc8d43a6aeac6ac43", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "b2c4487ac7c9405b8f7a18fe5ddcbe562a69fb93df41a73b527fc984036ee520", "eedddcf5444adfe37d5ade1cf4a423f705f16e5bff7287e6646291b09cfa7794", "7371ed6850b5930cc8804d943ebad827227d44c35729b40e5eab9d3bdd741280"],
	"Salton Shores": ["42299189ba9c26a1a1b46a4dd9b3f7c96c52fc0c8d972ed42e0163262d471775", "1afd3474220fb5191a1a1a209ad2ec3b52d4529af740756c49e88307fe708956", "66aa160616d9eff2a598ec080de6638d8d43ce28d24fd431b840688c3978acbc", "211e9ec6b3881a2a513f888bfb7695136c34ee08d33243a225f1c35e6f6d74ed", "37ec2af6ee3229242371154ab3ecac19b2d6054fac49a2f5d6f4559d2af739e1"],
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
	for name: String in GOLDEN:
		var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
		check(loaded.ok, "%s imports" % name)
		if not loaded.ok: continue
		var actual := hashes(loaded.city)
		var expected: Array = GOLDEN[name]
		for i: int in expected.size():
			if String(expected[i]).is_empty(): continue
			check_eq(actual[i], expected[i], "%s %s hash" % [name, ["visible", "tunnels", "physical", "boxes", "obstacles"][i]])
		print("NETWORK_GOLDEN %s %s" % [name, actual])
