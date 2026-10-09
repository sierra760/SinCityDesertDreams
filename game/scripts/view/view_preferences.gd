# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Player display preferences that outlive a city: the camera framing, water
## animation, label and vehicle visibility, and the last data overlay.
## Stored in the user directory; every value is validated on read.
class_name ViewPreferences
extends RefCounted

const PATH := "user://display.cfg"
const SECTION := "view"
const EXPLORE_CHARACTERS := ExploreCharacterCatalog.IDS

const MAYOR_NAME_LIMIT := 32
const CONTROL_BINDINGS_VERSION := 2

const DEFAULTS := {
	"mayor_name": "",
	"water_animation": true,
	"tile_grid": true,
	"labels": true,
	"button_labels": true,
	"vehicles": true,
	"overlay": "",
	"minimap": true,
	"ui_scale": 0,
	"fullscreen": false,
	"maximized": false,
	"windowed_size": Vector2(1280, 800),
	"size_3d": 72.0,
	"rotation_3d": 0,
	"center_3d": Vector3(64, 0, 64),
	"explore_sensitivity": 1.0,
	"explore_invert_y": false,
	"pause_in_background": true,
	## Ask about highway ramps after a road or highway build.
	"offer_ramps": true,
	"explore_character": "woman",
	"control_bindings": {},
	## 2 adds the arrow keys as Explore movement alternates.
	"control_bindings_version": CONTROL_BINDINGS_VERSION,
	"render_quality": "high",
	"render_scale": 100,
	"music_enabled": true,
	"effects_enabled": true,
	"music_volume": 0.8,
	"effects_volume": 0.9,
}


static func sanitize(settings: Dictionary) -> Dictionary:
	var clean := DEFAULTS.duplicate()
	clean["mayor_name"] = clean_mayor_name(settings.get("mayor_name", ""))
	var bindings: Variant = settings.get("control_bindings",{})
	var version: Variant = settings.get("control_bindings_version",1)
	# Profiles saved before version 2 get the arrow-key alternates once; a
	# player who later clears an alternate keeps it cleared.
	if typeof(version) not in [TYPE_INT,TYPE_FLOAT] or int(version) < CONTROL_BINDINGS_VERSION:
		bindings = ControlBindings.add_movement_alternates(bindings)
	clean["control_bindings"] = ControlBindings.sanitize(bindings)
	clean["explore_character"] = ExploreCharacterCatalog.sanitize(settings.get("explore_character", "woman"))
	var quality: Variant = settings.get("render_quality", "high")
	if typeof(quality) == TYPE_STRING and quality in ["high", "balanced", "performance"]:
		clean["render_quality"] = quality
	var resolution: Variant = settings.get("render_scale", 100)
	if typeof(resolution) == TYPE_INT and resolution in [50, 75, 100]:
		clean["render_scale"] = resolution
	for flag: String in ["water_animation", "tile_grid", "labels", "button_labels", "vehicles", "minimap", "fullscreen", "maximized", "explore_invert_y", "pause_in_background", "offer_ramps", "music_enabled", "effects_enabled"]:
		var value: Variant = settings.get(flag, clean[flag])
		if typeof(value) == TYPE_BOOL:
			clean[flag] = value
	var scale: Variant = settings.get("ui_scale", 0)
	if typeof(scale) == TYPE_INT and scale in [0,100,125,150,175,200]:
		clean["ui_scale"] = scale
	var window_size: Variant = settings.get("windowed_size", clean["windowed_size"])
	if window_size is Vector2 and (window_size as Vector2).is_finite() and window_size.x > 0 and window_size.y > 0:
		clean["windowed_size"] = window_size
	var overlay: Variant = settings.get("overlay", "")
	if typeof(overlay) == TYPE_STRING or typeof(overlay) == TYPE_STRING_NAME:
		clean["overlay"] = String(overlay)
	var size_3d: Variant = settings.get("size_3d", clean["size_3d"])
	var sensitivity: Variant = settings.get("explore_sensitivity", clean["explore_sensitivity"])
	if (typeof(sensitivity) == TYPE_INT or typeof(sensitivity) == TYPE_FLOAT) and is_finite(float(sensitivity)):
		clean["explore_sensitivity"] = clampf(float(sensitivity), 0.25, 3.0)
	for level: String in ["music_volume", "effects_volume"]:
		var amount: Variant = settings.get(level, clean[level])
		if (typeof(amount) == TYPE_INT or typeof(amount) == TYPE_FLOAT) and is_finite(float(amount)):
			clean[level] = clampf(float(amount), 0.0, 1.0)
	if (typeof(size_3d) == TYPE_INT or typeof(size_3d) == TYPE_FLOAT) and is_finite(float(size_3d)):
		clean["size_3d"] = clampf(float(size_3d), 0.5, 2048.0)
	var rotation_3d: Variant = settings.get("rotation_3d", clean["rotation_3d"])
	if (typeof(rotation_3d) == TYPE_INT or typeof(rotation_3d) == TYPE_FLOAT) and is_finite(float(rotation_3d)):
		clean["rotation_3d"] = posmod(int(rotation_3d), 4)
	var center_3d: Variant = settings.get("center_3d", clean["center_3d"])
	if center_3d is Vector3 and (center_3d as Vector3).is_finite():
		var point: Vector3 = center_3d
		clean["center_3d"] = Vector3(clampf(point.x, 0.0, City.WIDTH), 0.0, clampf(point.z, 0.0, City.HEIGHT))
	return clean


## Keep international names; collapse whitespace and discard nonprinting controls.
static func clean_mayor_name(value: Variant) -> String:
	if typeof(value) != TYPE_STRING: return ""
	var words := ""
	for character: String in String(value):
		var code := character.unicode_at(0)
		if character in ["\n", "\r", "\t"] or code == 0xA0:
			words += " "
		elif code >= 32 and not (code >= 127 and code <= 159) and code not in [0x200B,0x200E,0x200F] and not (code >= 0x202A and code <= 0x202E) and not (code >= 0x2066 and code <= 0x2069):
			words += character
	return " ".join(words.split(" ", false)).left(MAYOR_NAME_LIMIT).strip_edges()

static func mayor_credit(value: Variant) -> String:
	var name := clean_mayor_name(value)
	return "Mayor" if name.is_empty() else name


static func read(path: String = PATH) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return sanitize({})
	var settings: Dictionary = {}
	for key: String in DEFAULTS:
		if config.has_section_key(SECTION, key):
			settings[key] = config.get_value(SECTION, key)
	return sanitize(settings)


static func write(settings: Dictionary, path: String = PATH) -> Error:
	var config := ConfigFile.new()
	if FileAccess.file_exists(path):
		var err := config.load(path)
		if err != OK:
			config = ConfigFile.new()
	var clean := sanitize(settings)
	# Drop keys that are not settings, so the file holds only what is read back.
	if config.has_section(SECTION):
		for key: String in config.get_section_keys(SECTION):
			if not DEFAULTS.has(key):
				config.erase_section_key(SECTION, key)
	for key: String in clean:
		config.set_value(SECTION, key, clean[key])
	return config.save(path)
