# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Loading the city presentation must not allocate unused incident art/atlases.
## Run in a fresh process; dynamic loading keeps the pre-use boundary observable.
extends "res://tests/test_case.gd"

const ROOT := "res://assets/desert-dreams-disasters/"

func test_unused_incidents_stay_unloaded_and_fire_instances_share_resources() -> void:
	check(not ResourceLoader.has_cached(ROOT + "fire-motion-positions.exr"), "fresh process starts without fire atlas")
	var script: Variant = load("res://scripts/view/city_disaster_visual_3d.gd")
	for kind: String in ["tornado", "hurricane", "monster", "beam", "riot", "plane", "fire"]:
		check(not ResourceLoader.has_cached(ROOT + kind + ".glb"), "class load leaves unused model unloaded: " + kind)
	check(not ResourceLoader.has_cached(ROOT + "fire-motion-positions.exr"), "class load leaves fire positions unloaded")
	check(not ResourceLoader.has_cached(ROOT + "fire-motion-normals.exr"), "class load leaves fire normals unloaded")
	var weather: Node = script.new()
	weather.call("build", &"tornado")
	check(ResourceLoader.has_cached(ROOT + "tornado.glb"), "requested weather model loads")
	check(not ResourceLoader.has_cached(ROOT + "fire-motion-positions.exr"), "weather does not allocate fire atlas")
	check(not ResourceLoader.has_cached(ROOT + "hurricane.glb"), "weather does not allocate other weather")
	weather.free()
	var first: Node = script.new()
	var second: Node = script.new()
	first.call("build", &"fire")
	second.call("build", &"fire")
	var a: MeshInstance3D = first.find_children("*", "MeshInstance3D", true, false)[0]
	var b: MeshInstance3D = second.find_children("*", "MeshInstance3D", true, false)[0]
	check_eq(a.mesh, b.mesh, "fire mesh is shared after first use")
	check_ne(a.material_override, b.material_override, "fire time belongs to each instance")
	var material: ShaderMaterial = script.fire_material()
	check_eq(a.material_override.shader, material.shader, "public material getter preserves authored shader")
	for parameter: StringName in [&"motion_positions", &"motion_normals"]:
		check_eq(a.material_override.get_shader_parameter(parameter), b.material_override.get_shader_parameter(parameter), "fire atlas remains shared")
		check_eq(a.material_override.get_shader_parameter(parameter), material.get_shader_parameter(parameter), "instance retains authored atlas")
	first.free()
	second.free()
