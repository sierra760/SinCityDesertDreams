# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

@tool
extends EditorExportPlugin

func _get_name() -> String: return "SCDDGeometry"

## Delivery must match the explicitly loaded config; no debug/release split is
## needed because every target uses the same release kernel for both templates.
static func export_plan(features: PackedStringArray) -> Dictionary:
	if "ios" in features:
		return {"library": "res://addons/scdd_geometry/bin/SCDDGeometry.framework", "tags": PackedStringArray(["ios"]), "embedded_framework": true}
	if "windows" in features and "x86_64" in features:
		return {"library": "res://addons/scdd_geometry/bin/SCDDGeometry.windows.x86_64.dll", "tags": PackedStringArray(["windows", "x86_64"]), "embedded_framework": false}
	if "macos" in features:
		return {"library": "res://addons/scdd_geometry/bin/libSCDDGeometry.dylib", "tags": PackedStringArray(["macos"]), "embedded_framework": false}
	if "web" in features and "web_extensions" in features and "nothreads" in features \
			and "wasm32" in features and "threads" not in features and "web_noextensions" not in features:
		return {"library": "res://addons/scdd_geometry/bin/SCDDGeometry.web.nothreads.wasm", "tags": PackedStringArray(["web", "nothreads", "wasm32"]), "embedded_framework": false}
	return {}

func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var plan := export_plan(features)
	if plan.is_empty(): return
	var config := "res://addons/scdd_geometry/scdd_geometry.cfg"
	add_file(config,FileAccess.get_file_as_bytes(config),false)
	var notice := "res://addons/scdd_geometry/GODOT-CPP-LICENSE.md"
	add_file(notice,FileAccess.get_file_as_bytes(notice),false)
	if plan.embedded_framework:
		add_ios_embedded_framework(plan.library)
	else:
		add_shared_object(plan.library,plan.tags,"")

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Kernel libraries are delivered as shared objects/frameworks, never inside the PCK.
	if path.begins_with("res://addons/scdd_geometry/bin/"): skip()
