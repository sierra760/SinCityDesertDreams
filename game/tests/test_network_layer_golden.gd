# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Complete chunked network-layer output of three bundled cities, as actual
## Main projects it. Performance work must not move a vertex: regenerate these
## hashes with tools/golden_networks.gd only for a deliberate geometry change.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")

const GOLDEN := {
	"La Presa": ["ab8ccf38be3c605f76cccfa5cf5eb331ee46b1722fc6f2cc1b30b206a4708199", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "f299bc98c8824e1ed2e68754685c60501bd9559d8a4a8ba1ca6a8e276099aeea", "9464c68b32a9fb86ff6bad13e26026b58ec0b5aa58bd54033f89ee4670b2d53b", "5ed79b90bd16e51af786918dcc0f3a21c0e7e67365e5256dbb979b2583f1ba05"],
	"Valle del Mar": ["27895036ea219e664320e92e2491c44a9632f3f191848757fab0e2aa76386cf3", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "a49284b7f33146dc139d433c80dc22fcd9df12c03af9d22155365eb83f9500e9", "983a8915a137abd62fe7acbac47cb25e78627e0a8e6558f7e346f006d9a18f83", "065ea41ed4d56ddf5a54ac3ee67e225fa1e81dbbbc8bd7477fafc36ce3eeaafa"],
	"Salton Shores": ["0b17a7b4e155befdca38aee1da7fb2c5d4e2709b176aa81a2482f8c7ab2e66cb", "1afd3474220fb5191a1a1a209ad2ec3b52d4529af740756c49e88307fe708956", "a3a8a01a3e0e6d028b107248ce93bc37f009c594df5b860e6a08f73ec09aa6c3", "211e9ec6b3881a2a513f888bfb7695136c34ee08d33243a225f1c35e6f6d74ed", "02f934e946da78e65b171f52adc79c12feb548d211a95ebfcbb008104b09c331"],
}
# Cities whose projection differs on Windows, which rounds some engine math
# differently.
const PLATFORM_GOLDEN := {
	"Windows": {
		"La Presa": ["23cfa3d5a52429f0eed029f9cd492c5b52514aa4a6928baabf7061b05e367a61", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "f299bc98c8824e1ed2e68754685c60501bd9559d8a4a8ba1ca6a8e276099aeea", "9464c68b32a9fb86ff6bad13e26026b58ec0b5aa58bd54033f89ee4670b2d53b", "5ed79b90bd16e51af786918dcc0f3a21c0e7e67365e5256dbb979b2583f1ba05"],
		"Valle del Mar": ["29d77d89e0911890e1b1caf38a969793928ce6aa826c4741c9778b5cb20b0643", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "a49284b7f33146dc139d433c80dc22fcd9df12c03af9d22155365eb83f9500e9", "983a8915a137abd62fe7acbac47cb25e78627e0a8e6558f7e346f006d9a18f83", "065ea41ed4d56ddf5a54ac3ee67e225fa1e81dbbbc8bd7477fafc36ce3eeaafa"],
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
