# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Native platform readings and sandbox policy. Physical display readings are
## converted by DisplayLayout, never by individual controls.
class_name MobilePlatform
extends RefCounted

static func is_mobile(environment: Dictionary = {}) -> bool:
	var os_name := String(environment.get("os_name",OS.get_name()))
	return os_name in ["iOS","Android"]

static func is_ios(environment: Dictionary = {}) -> bool:
	return String(environment.get("os_name",OS.get_name())) == "iOS"

static func uses_touch(environment: Dictionary = {}) -> bool:
	return is_mobile(environment) or bool(environment.get("touchscreen",DisplayServer.is_touchscreen_available()))

## Mobile reports actual hardware, independently of the on-screen keyboard.
## Desktop display servers do not implement Godot's mobile hardware query.
static func has_keyboard(environment: Dictionary = {}) -> bool:
	if environment.has("hardware_keyboard"): return bool(environment.hardware_keyboard)
	return DisplayServer.has_hardware_keyboard() if is_mobile(environment) else true

static func display_readings(window: Window) -> Dictionary:
	var safe := Rect2i()
	var keyboard := 0
	if is_mobile():
		# iOS safe-area values already include screen backing scale. Both this
		# rect and keyboard height are physical pixels (Godot 4.6.1).
		safe = DisplayServer.get_display_safe_area()
		if window != null:
			safe.position -= window.position
		if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			keyboard = DisplayServer.virtual_keyboard_get_height()
	return {"safe_area_px":safe,"keyboard_height_px":keyboard,"mobile":is_mobile()}

static func configure_file_picker(picker: FileDialog, environment: Dictionary = {}) -> void:
	if picker == null:
		return
	# Prefer the OS picker on every display server that provides one.
	var native_supported := bool(environment.get("native_file_dialog",DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)))
	picker.use_native_dialog = native_supported
	if not is_mobile(environment):
		return
	# Godot 4.6.1 iOS does not provide FEATURE_NATIVE_DIALOG_FILE. Its user://
	# is Documents, exposed by the Files export options. ACCESS_USERDATA also
	# prevents navigating above the app sandbox in the custom picker.
	picker.access = FileDialog.ACCESS_FILESYSTEM if native_supported else FileDialog.ACCESS_USERDATA
	picker.current_dir = ProjectSettings.globalize_path("user://") if native_supported else "user://"
	picker.show_hidden_files = false
	picker.hidden_files_toggle_enabled = false

## First-run presentation. Desktop renders 3D at 75% on a backing scale of 2 or
## more (Retina/200% displays), and Windows/Linux integrated GPUs start on
## Balanced. Environment keys backing_scale/video_adapter_type inject readings.
static func presentation_defaults(environment: Dictionary = {}) -> Dictionary:
	if is_mobile(environment):
		return {"render_quality":"balanced","render_scale":75}
	var os_name := String(environment.get("os_name",OS.get_name()))
	var backing := float(environment["backing_scale"]) if environment.has("backing_scale") else DisplayLayout.screen_backing(DisplayServer.window_get_current_screen())
	var adapter := int(environment["video_adapter_type"]) if environment.has("video_adapter_type") else int(RenderingServer.get_video_adapter_type())
	var integrated := os_name in ["Windows","Linux","FreeBSD","NetBSD","OpenBSD","BSD"] and adapter == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	return {"render_quality":"balanced" if integrated else "high","render_scale":75 if is_finite(backing) and backing >= 2.0 else 100}

## Only absent presentation preferences receive platform defaults. Explicit
## player quality/resolution choices survive subsequent launches unchanged.
static func read_view_preferences(path: String = ViewPreferences.PATH, environment: Dictionary = {}) -> Dictionary:
	var preferences := ViewPreferences.read(path)
	var stored := ConfigFile.new()
	stored.load(path)
	var defaults := presentation_defaults(environment)
	for key: String in defaults:
		if not stored.has_section_key(ViewPreferences.SECTION,key):
			preferences[key] = defaults[key]
	return preferences
