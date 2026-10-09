# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const PLATFORM_PATH := "res://scripts/platform/mobile_platform.gd"

func _platform() -> Variant:
	check(FileAccess.file_exists(PLATFORM_PATH), "mobile platform adapter exists")
	return load(PLATFORM_PATH).new() if FileAccess.file_exists(PLATFORM_PATH) else null

func test_touch_detection_keeps_mobile_and_desktop_touch_distinct() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	check(platform.is_mobile({"os_name":"iOS"}))
	check(platform.uses_touch({"os_name":"iOS","touchscreen":false}))
	check(not platform.is_mobile({"os_name":"macOS","touchscreen":true}))
	check(not platform.uses_touch({"os_name":"macOS","touchscreen":true,"features":[]}),"a touch-capable desktop keeps its mouse and keyboard presentation")
	check(not platform.uses_touch({"os_name":"Windows","touchscreen":true,"features":[]}))
	check(not platform.uses_touch({"os_name":"macOS","touchscreen":false,"features":[]}))
	check(not platform.uses_touch({"os_name":"Web","features":["web"]}),"a desktop browser is not touch-first")
	check(platform.uses_touch({"os_name":"Web","features":["web","web_android"]}),"a phone or tablet browser is touch-first")
	check(platform.uses_touch({"os_name":"Web","features":["web","web_ios"]}))
	check(not platform.is_mobile({"os_name":"Web","features":["web","web_ios"]}),"browser builds keep the desktop window policy")

func test_desktop_picker_starts_in_downloads_then_documents() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var existing := ProjectSettings.globalize_path("user://")
	check_eq(platform.desktop_picker_start_dir({"os_name":"macOS","system_dirs":["/no/such/downloads",existing]}),existing,"a missing Downloads folder falls back to the next")
	check_eq(platform.desktop_picker_start_dir({"os_name":"Windows","system_dirs":["","/no/such/dir"]}),"","no readable folder leaves the picker's default")
	check_eq(platform.desktop_picker_start_dir({"os_name":"iOS","system_dirs":[existing]}),"","mobile pickers are configured separately")
	var live: String = platform.desktop_picker_start_dir()
	if not downloads.is_empty() and DirAccess.dir_exists_absolute(downloads): check_eq(live,downloads)
	elif not documents.is_empty() and DirAccess.dir_exists_absolute(documents): check_eq(live,documents)

func test_android_native_picker_starts_in_downloads() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	# A real folder stands in for Android's shared Download directory.
	var downloads := ProjectSettings.globalize_path("user://android-downloads-fixture")
	check_eq(DirAccess.make_dir_recursive_absolute(downloads),OK)
	var picker := FileDialog.new()
	root.add_child(picker)
	platform.configure_file_picker(picker,{"os_name":"Android","native_file_dialog":true,"downloads_dir":downloads})
	check_eq(picker.current_dir,downloads,"the system picker opens where shared cities arrive, not app-private storage")
	picker.free()
	DirAccess.remove_absolute(downloads)

func test_ios_picker_is_bounded_to_files_visible_userdata() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	var picker := FileDialog.new()
	root.add_child(picker)
	picker.access = FileDialog.ACCESS_FILESYSTEM
	platform.configure_file_picker(picker,{"os_name":"iOS","native_file_dialog":false})
	check_eq(picker.access,FileDialog.ACCESS_USERDATA)
	check_eq(picker.current_dir,"user://")
	check(not picker.use_native_dialog,"Godot 4.6.1 iOS has no native file dialog backend")
	check(not picker.show_hidden_files)
	picker.free()

func test_desktop_picker_configuration_is_preserved() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	var picker := FileDialog.new()
	root.add_child(picker)
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.current_dir = "/tmp"
	platform.configure_file_picker(picker,{"os_name":"macOS","native_file_dialog":false})
	check_eq(picker.access,FileDialog.ACCESS_FILESYSTEM)
	check_eq(picker.current_dir,"/tmp")
	check(not picker.use_native_dialog,"unsupported display server retains the custom picker")
	picker.free()

func test_available_native_picker_is_used_on_every_platform() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	for os_name: String in ["macOS","Windows","Linux","Android","iOS","Other"]:
		var picker := FileDialog.new()
		root.add_child(picker)
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.current_dir = "/tmp"
		platform.configure_file_picker(picker,{"os_name":os_name,"native_file_dialog":true})
		check(picker.use_native_dialog,"available OS picker is preferred on " + os_name)
		check_eq(picker.access,FileDialog.ACCESS_FILESYSTEM,"native picker can access selected external city files on " + os_name)
		if os_name not in ["Android","iOS"]:
			check_eq(picker.current_dir,"/tmp","desktop starting directory is retained on " + os_name)
		picker.free()

func test_unavailable_native_picker_falls_back_on_every_platform() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	for os_name: String in ["macOS","Windows","Linux","Android","iOS","Other"]:
		var picker := FileDialog.new()
		root.add_child(picker)
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.use_native_dialog = true
		platform.configure_file_picker(picker,{"os_name":os_name,"native_file_dialog":false})
		check(not picker.use_native_dialog,"custom picker is available without native support on " + os_name)
		check_eq(picker.access,FileDialog.ACCESS_USERDATA if os_name in ["Android","iOS"] else FileDialog.ACCESS_FILESYSTEM)
		picker.free()

func test_mobile_presentation_defaults_do_not_override_explicit_preferences() -> void:
	var platform: Variant = _platform()
	if platform == null: return
	check_eq(platform.presentation_defaults({"os_name":"iOS"}), {"render_quality":"balanced","render_scale":75})
	check_eq(platform.presentation_defaults({"os_name":"macOS"}), {"render_quality":"high","render_scale":100})
	var path := "user://ipad_preferences.cfg"
	var stored := ConfigFile.new()
	check_eq(stored.save(path),OK)
	var initial: Dictionary = platform.read_view_preferences(path,{"os_name":"iOS"})
	check_eq(initial.render_quality,"balanced")
	check_eq(initial.render_scale,75)
	check_eq(ViewPreferences.write({"render_quality":"high","render_scale":100},path),OK)
	var explicit: Dictionary = platform.read_view_preferences(path,{"os_name":"iOS"})
	check_eq(explicit.render_quality,"high")
	check_eq(explicit.render_scale,100)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_ipad_export_is_files_visible_and_automatically_signed() -> void:
	var presets := ConfigFile.new()
	check_eq(presets.load("res://export_presets.cfg"),OK)
	var section := ""
	for candidate: String in presets.get_sections():
		if presets.get_value(candidate,"platform","") == "iOS": section = candidate
	check(not section.is_empty(),"iPad export preset is configured")
	if section.is_empty(): return
	var options := section + ".options"
	check_eq(presets.get_value(options,"application/targeted_device_family",-1),2,"iPhone and iPad (the iPhone layout shipped after the iPad-only preset)")
	check_eq(presets.get_value(options,"user_data/accessible_from_files_app",false),true)
	check_eq(presets.get_value(options,"user_data/accessible_from_itunes_sharing",false),true)
	check_eq(presets.get_value(options,"application/app_store_team_id",""),"2LK9LNU9V8")
	# Xcode automatic signing rejects a Release config that names "Apple Distribution";
	# archives sign for development and Xcode re-signs for distribution on export.
	for key: String in ["application/code_sign_identity_debug","application/code_sign_identity_release"]:
		check_eq(presets.get_value(options,key,""),"Apple Development",key)
	for key: String in ["application/provisioning_profile_specifier_debug","application/provisioning_profile_specifier_release"]:
		check_eq(presets.get_value(options,key,""),"","automatic signing selects the provisioning profile")
	check_eq(ProjectSettings.get_setting("display/window/handheld/orientation"),6)
	check_eq(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc"),true)

func test_macos_distribution_export_uses_developer_id() -> void:
	var presets := ConfigFile.new()
	check_eq(presets.load("res://export_presets.cfg"),OK)
	var section := ""
	for candidate: String in presets.get_sections():
		if presets.get_value(candidate,"platform","") == "macOS": section = candidate
	check(not section.is_empty(),"macOS export preset is configured")
	if section.is_empty(): return
	var options := section + ".options"
	check_eq(presets.get_value(options,"export/distribution_type",-1),1)
	check_eq(presets.get_value(options,"codesign/codesign",-1),3)
	check_eq(presets.get_value(options,"codesign/apple_team_id",""),"2LK9LNU9V8")
	var identity: String = presets.get_value(options,"codesign/identity","")
	check(identity.begins_with("Developer ID Application:"),"distribution builds sign with a Developer ID Application identity")
	check(identity.ends_with("(2LK9LNU9V8)"),"signing identity belongs to the configured team")
