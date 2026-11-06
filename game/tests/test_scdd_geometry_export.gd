# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Export delivery records are consumed by the actual EditorExportPlugin callback.
extends "res://tests/test_case.gd"
const Exporter := preload("res://addons/scdd_geometry/export_plugin.gd")
const WASM := "res://addons/scdd_geometry/bin/SCDDGeometry.web.nothreads.wasm"

func _plan(features: PackedStringArray) -> Dictionary:
	var exporter_script: Script = Exporter
	if not exporter_script.has_method("export_plan"): return {}
	return exporter_script.call("export_plan", features)

func test_web_exports_matching_shared_object_in_both_build_modes() -> void:
	for mode: String in ["debug", "release"]:
		var plan := _plan(["web", "web_extensions", "nothreads", "wasm32", mode])
		check_eq(plan, {"library": WASM, "tags": PackedStringArray(["web", "nothreads", "wasm32"]), "embedded_framework": false}, mode + " exports the standalone wasm shared object")

func test_incompatible_web_exports_do_not_ship_kernel() -> void:
	for features: PackedStringArray in [
		PackedStringArray(["web", "web_noextensions", "nothreads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "threads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "nothreads", "wasm64"]),
		PackedStringArray(["web", "web_extensions", "nothreads", "threads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "web_noextensions", "nothreads", "wasm32"]),
		PackedStringArray(["web", "web_extensions", "wasm32"]),
		PackedStringArray(["linux", "x86_64"]), PackedStringArray(["android", "arm64"])]:
		check_eq(_plan(features), {}, "unsupported export has no native delivery: %s" % str(features))

func test_existing_native_export_delivery_is_preserved() -> void:
	check_eq(_plan(["macos", "arm64"]), {"library": "res://addons/scdd_geometry/bin/libSCDDGeometry.dylib", "tags": PackedStringArray(["macos"]), "embedded_framework": false}, "macOS ships dylib")
	check_eq(_plan(["windows", "x86_64"]), {"library": "res://addons/scdd_geometry/bin/SCDDGeometry.windows.x86_64.dll", "tags": PackedStringArray(["windows", "x86_64"]), "embedded_framework": false}, "Windows ships x86_64 DLL")
	check_eq(_plan(["ios", "arm64"]), {"library": "res://addons/scdd_geometry/bin/SCDDGeometry.framework", "tags": PackedStringArray(["ios"]), "embedded_framework": true}, "iOS embeds its framework")
	check_eq(_plan(["windows", "arm64"]), {}, "Windows ARM has no x86_64 kernel")

func test_web_config_and_preset_can_deliver_the_planned_library() -> void:
	var config := ConfigFile.new()
	check_eq(config.load("res://addons/scdd_geometry/scdd_geometry.cfg"), OK, "explicit extension config loads")
	check_eq(config.get_value("libraries", "web.nothreads.wasm32", ""), WASM, "both build modes select the same single-threaded wasm library")
	var presets := ConfigFile.new()
	check_eq(presets.load("res://export_presets.cfg"), OK, "export presets load")
	var found := false
	for section: String in presets.get_sections():
		if presets.get_value(section, "platform", "") != "Web": continue
		found = true
		check(presets.get_value(section + ".options", "variant/extensions_support", false), "Web template enables dynamic extension support")
		check(not presets.get_value(section + ".options", "variant/thread_support", true), "Web template remains single-threaded")
	check(found, "Web export preset exists")
