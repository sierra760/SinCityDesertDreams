# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const BASE := "res://assets/street-name-signs/"
const IDS := ["street-post", "street-blade", "highway-exit"]

func _contract() -> Dictionary:
	var path := BASE + "templates.json"
	check(FileAccess.file_exists(path), "original sign template contract exists")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(data is Dictionary, "contract parses")
	return data if data is Dictionary else {}

func _scene(id: String) -> Node3D:
	var path := BASE + id + ".glb"
	check(ResourceLoader.exists(path), id + " original GLB exists")
	if not ResourceLoader.exists(path): return null
	var packed := load(path) as PackedScene
	check(packed != null, id + " loads as scene")
	return packed.instantiate() as Node3D if packed != null else null

func test_three_original_exports_have_provenance_and_meter_bounds() -> void:
	var contract := _contract()
	if contract.is_empty(): return
	check_eq(float(contract.meters_per_tile), 16.0)
	check(FileAccess.file_exists(BASE + "provenance.json"), "material and source provenance ships")
	for id: String in IDS:
		var scene := _scene(id)
		if scene == null: continue
		var entry: Dictionary = contract.templates[id]
		check_eq(FileAccess.get_sha256(BASE + id + ".glb"), entry.sha256, "authored exact export")
		var bounds := AABB()
		var started := false
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			var aabb := mesh_node.transform * mesh_node.mesh.get_aabb()
			# Board is identity apart from its children; all authored meshes use metre vertices.
			bounds = bounds.merge(aabb) if started else aabb
			started = true
		var expected := Vector3(entry.bounds_m.size[0], entry.bounds_m.size[1], entry.bounds_m.size[2])
		check(bounds.size.distance_to(expected) < 0.001, id + " metre dimensions match contract")
		scene.free()

func test_imported_bodies_are_closed_outward_opaque_and_uv_textured() -> void:
	for id: String in IDS:
		var scene := _scene(id)
		if scene == null: continue
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			var edges: Dictionary = {}
			var triangles := 0
			for s: int in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(s)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				check_eq(uv.size(), vertices.size(), node.name + " UVs survive export")
				var material := mesh.surface_get_material(s) as StandardMaterial3D
				check(material != null, "PBR material")
				if material != null:
					check_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque enamel")
					check(material.albedo_texture != null, "authored texture")
				for i: int in range(vertices.size()):
					check((vertices[i] - mesh.get_aabb().get_center()).dot(normals[i]) > 0.000001, node.name + " outward normals")
				for i: int in range(0, indices.size(), 3):
					triangles += 1
					for e: int in range(3):
						var a := str(vertices[indices[i + e]].snapped(Vector3.ONE * 0.00001))
						var b := str(vertices[indices[i + (e + 1) % 3]].snapped(Vector3.ONE * 0.00001))
						var key := a + ">" + b if a < b else b + ">" + a
						edges[key] = int(edges.get(key, 0)) + 1
			check(triangles > 0 and not edges.is_empty(), "nonempty closed body")
			for count: int in edges.values(): check_eq(count, 2, node.name + " closed welded edge")
		scene.free()

func test_blank_faces_and_two_text_mounts_point_outside_board() -> void:
	var contract := _contract()
	if contract.is_empty(): return
	for id: String in ["street-blade", "highway-exit"]:
		var scene := _scene(id)
		if scene == null: continue
		var entry: Dictionary = contract.templates[id]
		check_eq(entry.operational_faces, ["front"] if id == "highway-exit" else ["front", "back"], "rear support posts exclude highway rear from lettering")
		for side: String in ["front", "back"]:
			var face := scene.get_node_or_null(NodePath(entry.faces[side])) as MeshInstance3D
			var mount := scene.get_node_or_null(NodePath(entry.mounts[side])) as Node3D
			check(face != null and mount != null, "named blank face and lettering mount")
			if face == null or mount == null: continue
			var sign_z := 1.0 if side == "front" else -1.0
			check(mount.basis.z.dot(Vector3(0, 0, sign_z)) > 0.999, "text local +Z points outward")
			check(mount.position.z * sign_z > absf(face.position.z) + face.mesh.get_aabb().size.z * 0.5, "text clears opaque face")
		check(float(entry.maximum_board_scale[0]) >= 1.0 and float(entry.maximum_board_scale[1]) >= 1.0, "explicit safe expansion")
		scene.free()

func test_complete_longest_names_and_exit_labels_fit_positive_margins() -> void:
	var contract := _contract()
	if contract.is_empty(): return
	var font := load("res://assets/fonts/biorhyme/BioRhyme-Medium.ttf") as Font
	for id: String in ["street-blade", "highway-exit"]:
		var entry: Dictionary = contract.templates[id]
		var count := 48 if id == "street-blade" else 99
		var full := "W".repeat(count)
		var split := ceili(count / 2.0)
		var lines := [full.substr(0, split), full.substr(split)]
		check_eq("".join(lines), full, "all longest-name characters retained")
		var total_height := 0.0
		for line: String in lines:
			var text := TextMesh.new()
			text.font = font
			text.font_size = 64
			text.pixel_size = float(entry.layout.destination_em_m) / 64.0
			text.text = line
			var size := text.get_aabb().size
			check(size.x < float(entry.layout.destination_safe_m[0]), "complete destination line has positive horizontal margin")
			total_height += maxf(size.y, float(entry.layout.destination_em_m))
		check(total_height + float(entry.layout.line_gap_m) < float(entry.layout.destination_safe_m[1]), "two complete lines fit with positive vertical margin")
		if id == "highway-exit":
			for label: String in ["EXIT", "←", "→"]:
				var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 64) * (float(entry.layout.header_em_m) / 64.0)
				check(size.x < float(entry.layout.header_safe_m[0] if label == "EXIT" else entry.layout.arrow_safe_m[0]) and size.y < float(entry.layout.header_safe_m[1] if label == "EXIT" else entry.layout.arrow_safe_m[1]), "complete exit label/arrow fits separate header")

func test_maximum_board_growth_stays_inside_placement_envelope_and_reserved_rectangles() -> void:
	var contract := _contract()
	if contract.is_empty(): return
	for id: String in ["street-blade", "highway-exit"]:
		var scene := _scene(id)
		if scene == null: continue
		var entry: Dictionary = contract.templates[id]
		var scale_m := Vector3(entry.maximum_board_scale[0], entry.maximum_board_scale[1], entry.maximum_board_scale[2])
		var pivot := Vector3(entry.board_pivot_m[0], entry.board_pivot_m[1], entry.board_pivot_m[2])
		var board := scene.get_node_or_null(NodePath(entry.board_node))
		check(board != null, "board-only expansion group exists")
		var low: Array = entry.maximum_assembly_envelope_m.min
		var high: Array = entry.maximum_assembly_envelope_m.max
		var envelope := AABB(Vector3(low[0], low[1], low[2]), Vector3(high[0]-low[0], high[1]-low[1], high[2]-low[2])).grow(0.00001)
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			var transform_m := mesh_node.transform
			if mesh_node.get_parent() == board:
				transform_m = Transform3D(Basis.from_scale(scale_m), pivot - pivot * scale_m) * transform_m
			check(envelope.encloses(transform_m * mesh_node.mesh.get_aabb()), node.name + " maximum board growth fits reserved assembly envelope")
		var safe: Array = entry.maximum_safe_face_m
		var face_rect := Rect2(Vector2(-float(safe[0]), -float(safe[1])) * 0.5, Vector2(safe[0], safe[1]))
		var rectangles: Array[Rect2] = []
		for kind: String in (["destination", "header", "arrow"] if id == "highway-exit" else ["destination"]):
			var center: Array = entry.layout[kind + "_center_m"]
			var size: Array = entry.layout[kind + "_safe_m"]
			var rect := Rect2(Vector2(center[0], center[1]) - Vector2(size[0], size[1]) * 0.5, Vector2(size[0], size[1]))
			check(face_rect.encloses(rect), kind + " stays inside usable face")
			for other: Rect2 in rectangles: check(not rect.intersects(other), "destination never consumes EXIT/arrow reserved space")
			rectangles.append(rect)
		scene.free()
