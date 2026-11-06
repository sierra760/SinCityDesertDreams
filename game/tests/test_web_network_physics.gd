# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Web dispatch must never load the single-threaded library into an incompatible
## template. Literal feature sets model the engine's platform capability query.
extends "res://tests/test_case.gd"
const Native := preload("res://scripts/view/city_network_physics_native.gd")

func after_each() -> void:
	Native.force_fallback = false

func _supported(platform_name: String, features: PackedStringArray) -> bool:
	var kernel_script: Script = Native
	for method: Dictionary in kernel_script.get_script_method_list():
		if method.name == "supported_platform" and method.args.size() == 2:
			return kernel_script.call("supported_platform", platform_name, func(feature: String) -> bool: return feature in features)
	return false

func test_web_uses_only_single_threaded_extension_template() -> void:
	check(_supported("Web", ["web", "web_extensions", "nothreads", "wasm32"]), "single-threaded wasm32 extension template can load the kernel")
	for features: PackedStringArray in [
		PackedStringArray(["web", "web_noextensions", "nothreads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "threads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "nothreads", "wasm64"]),
		PackedStringArray(["web", "web_extensions", "nothreads", "threads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "web_noextensions", "nothreads", "wasm32"])]:
		check(not _supported("Web", features), "incompatible Web template remains on GDScript: %s" % str(features))

func test_existing_platform_selection_is_preserved() -> void:
	check(_supported("macOS", []), "macOS kernel remains enabled")
	check(_supported("iOS", []), "iOS kernel remains enabled")
	check(_supported("Windows", ["x86_64"]), "Windows x86_64 kernel remains enabled")
	check(not _supported("Windows", ["arm64"]), "Windows ARM remains on GDScript")
	check(not _supported("Linux", ["x86_64"]), "Linux remains on GDScript")
	check(not _supported("Android", ["arm64"]), "Android remains on GDScript")

func test_forced_fallback_does_not_attempt_to_load() -> void:
	var attempted: bool = Native._load_attempted
	Native.force_fallback = true
	check(not Native.available(), "forced fallback reports unavailable")
	check_eq(Native._load_attempted, attempted, "forced fallback cannot attempt extension loading")
	var expected := {"physical_floor_faces":PackedVector3Array(), "physical_obstacle_faces":PackedVector3Array(), "physical_boxes":[]}
	check_eq(Native.resolve([], [], PackedVector3Array()), expected, "forced fallback still resolves geometry")
