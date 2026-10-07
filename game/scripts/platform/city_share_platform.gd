# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The system share sheet, through an optional Apple extension. Builds without
## it offer the same playable file in the file manager (Files on iOS).
class_name CitySharePlatform
extends RefCounted

const CONFIG := "res://addons/apple_share/apple_share.cfg"
var native: RefCounted

func _init() -> void:
	if OS.get_name() not in ["macOS","iOS"] or DisplayServer.get_name() == "headless": return
	if not ClassDB.class_exists("SCDDNativeShare"):
		var status := GDExtensionManager.load_extension(CONFIG)
		if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]: return
	if ClassDB.class_exists("SCDDNativeShare"): native = ClassDB.instantiate("SCDDNativeShare")

func available() -> bool:
	return native != null and bool(native.call("is_available"))

func busy() -> bool:
	return native != null and bool(native.call("is_busy"))

func share_file(path: String, title: String, message: String) -> Error:
	if not available(): return ERR_UNAVAILABLE
	return native.call("share_file",ProjectSettings.globalize_path(path),title,message)

func completion() -> int:
	return int(native.call("completion_status")) if native != null else -2

static func reveal_file(path: String) -> Error:
	if MobilePlatform.is_mobile(): return ERR_UNAVAILABLE
	return OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
