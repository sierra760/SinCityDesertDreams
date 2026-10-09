# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

@tool
extends EditorExportPlugin

func _get_name() -> String: return "SCDDGeometry"

func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	var windows := "windows" in features and "x86_64" in features
	if "macos" not in features and "ios" not in features and not windows: return
	var config := "res://addons/scdd_geometry/scdd_geometry.cfg"
	add_file(config,FileAccess.get_file_as_bytes(config),false)
	var notice := "res://addons/scdd_geometry/GODOT-CPP-LICENSE.md"
	add_file(notice,FileAccess.get_file_as_bytes(notice),false)
	if "ios" in features:
		add_ios_embedded_framework("res://addons/scdd_geometry/bin/SCDDGeometry.framework")
	elif windows:
		add_shared_object("res://addons/scdd_geometry/bin/SCDDGeometry.windows.x86_64.dll",PackedStringArray(["windows","x86_64"]),"")
	else:
		add_shared_object("res://addons/scdd_geometry/bin/libSCDDGeometry.dylib",PackedStringArray(["macos"]),"")

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Native binaries belong beside the executable, never inside the PCK.
	if path.begins_with("res://addons/scdd_geometry/bin/"): skip()
