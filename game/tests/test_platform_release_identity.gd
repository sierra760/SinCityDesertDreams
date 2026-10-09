# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Release identity and platform settings that the Godot editor may silently
## rewrite: one version everywhere, supported minimum systems, Android Back,
## the boot splash and iOS audio mixing.
extends "res://tests/test_case.gd"

const VERSION_KEYS := {
	"macOS": ["application/short_version", "application/version"],
	"iOS": ["application/short_version", "application/version"],
	"Windows Desktop": ["application/file_version", "application/product_version"],
	"Android": ["version/name"],
}


func _presets() -> ConfigFile:
	var presets := ConfigFile.new()
	check_eq(presets.load("res://export_presets.cfg"), OK)
	return presets


func test_every_preset_reports_the_project_version() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	check(not version.is_empty(), "project.godot names the version")
	var presets := _presets()
	var seen := {}
	for section: String in presets.get_sections():
		var platform := String(presets.get_value(section, "platform", ""))
		if not VERSION_KEYS.has(platform): continue
		seen[platform] = true
		for key: String in VERSION_KEYS[platform]:
			var value := String(presets.get_value(section + ".options", key, ""))
			# Blank fields fall back to application/config/version at export.
			check(value.is_empty() or value == version, "%s %s is %s, not %s" % [platform, key, value, version])
		var path := String(presets.get_value(section, "export_path", ""))
		if path.contains("-v"): check(path.contains("-v" + version), "%s export name carries %s" % [platform, version])
	check_eq(seen.size(), VERSION_KEYS.size(), "every versioned preset was checked")


func test_minimum_systems_can_start_the_renderer() -> void:
	var presets := _presets()
	for section: String in presets.get_sections():
		if presets.get_value(section, "platform", "") != "macOS": continue
		var intel := String(presets.get_value(section + ".options", "application/min_macos_version_x86_64", ""))
		# The Mobile renderer runs through Vulkan/MoltenVK on Intel Macs.
		check(intel.naturalnocasecmp_to("10.15") >= 0, "Intel macOS minimum is at least 10.15, not " + intel)


func test_platform_project_settings() -> void:
	check_eq(ProjectSettings.get_setting("application/config/quit_on_go_back", true), false, "Android Back reaches the game")
	check_eq(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on", true), false, "the game decides when to keep the display awake")
	check_eq(ProjectSettings.get_setting("audio/general/ios/mix_with_others", false), true, "iOS mixes with the player's own audio")
	check_eq(ProjectSettings.get_setting("application/boot_splash/stretch_mode", -1), 1, "the splash keeps its whole picture on portrait phones")
	var splash: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	var presets := _presets()
	for section: String in presets.get_sections():
		if presets.get_value(section, "platform", "") == "Android":
			check_eq(presets.get_value(section + ".options", "screen/background_color", Color.BLACK), splash, "Android starts on the splash teal, not black")
