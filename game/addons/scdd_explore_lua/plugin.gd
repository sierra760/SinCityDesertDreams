# SPDX-License-Identifier: GPL-3.0-or-later
@tool
extends EditorPlugin
class Exporter extends EditorExportPlugin:
	func _get_name() -> String: return "SCDDExploreLua"
	func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		var base := "res://addons/scdd_explore_lua/"
		add_file(base + "LUA-LICENSE.txt", FileAccess.get_file_as_bytes(base + "LUA-LICENSE.txt"), false)
		var mac := "macos" in features
		var windows := "windows" in features and "x86_64" in features
		if not mac and not windows: return
		var library := base + "bin/" + ("libSCDDExploreLua.dylib" if mac else "SCDDExploreLua.windows.x86_64.dll")
		if not FileAccess.file_exists(library): return
		add_file(base + "scdd_explore_lua.cfg", FileAccess.get_file_as_bytes(base + "scdd_explore_lua.cfg"), false)
		add_shared_object(library, PackedStringArray(["macos"] if mac else ["windows", "x86_64"]), "")
	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if path.begins_with("res://addons/scdd_explore_lua/bin/"): skip()
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	exporter = Exporter.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
