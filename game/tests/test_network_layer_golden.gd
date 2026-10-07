# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Complete chunked network-layer output of three bundled cities, as actual
## Main projects it. Performance work must not move a vertex: regenerate these
## hashes with tools/golden_networks.gd only for a deliberate geometry change.
extends "res://tests/test_case.gd"

const GOLDEN := {
	"La Presa": ["ccc7ef8ab6ba6d4ea5b1a12f93fcccd342dabbd69b9ad8df0a6cc004ed702bf1", "20585491d0c1cbccc81b63d52df8e1a69f6e705d1e38f08083303f62e68bfd6d", "78e4ef0e25577da28a477786d06957543b474acc43e427af646f6d75ab512107", "201b2f85eaee5cb49721331201dca815e776ee82ae53adb89138c140173e9042", "8fbc189e988db2fe871e5a5f0d532434aa9deef003013a167f55b822f2f370ba"],
	"Valle del Mar": ["8d5369cad7bb698f081357d21e1bfbc0293509d228a1b417a46b59a0d1314248", "a93ce20ec8eaede53e9a36384b1bc43c85e28e9ca07ad387d5d73123c4cd2a62", "31d7cd0cbafd8f968d13b241b706ff56831c851445eaa4df32d9e20dbccecf2c", "c7f7fe7e6227204ef80ddbafb82e3099eee1d135caea12ce6938029e97f90410", "069ebc43c176fb190053c046238bef4fe290372bcf199e03c54f995ec4003fa9"],
	"Salton Shores": ["2ac9c567f8a4dcc35c662f3d09d049f30976cd9e1e7dbe99999d86ae7d6e7f40", "1afd3474220fb5191a1a1a209ad2ec3b52d4529af740756c49e88307fe708956", "f17318f2c3d410fd97219b1aa6635d56abaa96e852e8ac5a9a2ca5821b2c151c", "0061ce116f8c91e4c13c45e029c32ab489e97e07e5033d3534229caed73bb020", "3ac10280a6400d750b54aec95dcbaff1c93f041e0ff57ec34fb5c7db428406d8"],
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
