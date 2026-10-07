# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

@tool
extends EditorExportPlugin

func _get_name() -> String: return "SCDDAppleShare"

func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	if "macos" not in features and "ios" not in features: return
	var config := "res://addons/apple_share/apple_share.cfg"
	add_file(config,FileAccess.get_file_as_bytes(config),false)
	var notice := "res://addons/apple_share/GODOT-CPP-LICENSE.md"
	add_file(notice,FileAccess.get_file_as_bytes(notice),false)
	if "ios" in features:
		add_ios_embedded_framework("res://addons/apple_share/bin/SCDDNativeShare.framework")
	else:
		add_shared_object("res://addons/apple_share/bin/libSCDDNativeShare.dylib",PackedStringArray(["macos"]),"")

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Native binaries belong beside the executable, never inside the PCK.
	if path.begins_with("res://addons/apple_share/bin/"): skip()
