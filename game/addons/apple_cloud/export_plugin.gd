# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

@tool
extends EditorExportPlugin

func _get_name() -> String: return "SCDDAppleCloud"

func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	if "macos" not in features and "ios" not in features: return
	var config := "res://addons/apple_cloud/apple_cloud.cfg"
	add_file(config,FileAccess.get_file_as_bytes(config),false)
	var notice := "res://addons/apple_cloud/GODOT-CPP-LICENSE.md"
	add_file(notice,FileAccess.get_file_as_bytes(notice),false)
	if "ios" in features:
		add_apple_embedded_platform_embedded_framework("res://addons/apple_cloud/bin/SCDDAppleCloud.framework")
	else:
		add_shared_object("res://addons/apple_cloud/bin/libSCDDAppleCloud.dylib",PackedStringArray(["macos"]),"")

		# Godot 4.7.2 auto-embeds profiles only for App Store. For Developer ID,
		# copy a private prevalidated profile into Contents BEFORE bundle signing.
		# Never put signing profiles in ProjectSettings or the PCK.
		var profile := OS.get_environment("SCDD_APPLE_CLOUD_PROFILE")
		if not profile.is_empty() and int(get_option("export/distribution_type")) == 1:
			if profile.is_absolute_path() and profile.get_file() == "embedded.provisionprofile" and FileAccess.file_exists(profile):
				add_shared_object(profile, PackedStringArray(["macos"]), "Contents")
			else:
				push_error("Cloud profile must be an existing private absolute path named embedded.provisionprofile")

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Native binaries belong beside the executable, never inside the PCK.
	if path.begins_with("res://addons/apple_cloud/bin/") or path.begins_with("res://platform/apple-cloud/") or path.ends_with(".provisionprofile") or path.ends_with(".mobileprovision") or path.ends_with(".entitlements"): skip()
