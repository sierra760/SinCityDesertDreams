# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
var host: GameHost
var paths: Array[String] = []

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://test-mayor.cfg"
	root.add_child(host)

func after_each() -> void:
	host.free()
	for path: String in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-mayor.cfg"))
	await process_frame

func test_profile_validation_and_persistence() -> void:
	var clean := ViewPreferences.sanitize({"mayor_name":"  María\n del\tMar  "})
	check(clean.has("mayor_name"),"persistent mayor name exists")
	if not clean.has("mayor_name"): return
	check_eq(clean.mayor_name,"María del Mar")
	check_eq(ViewPreferences.sanitize({"mayor_name":123}).mayor_name,"")
	check_eq(ViewPreferences.sanitize({"mayor_name":"   "}).mayor_name,"")
	check_eq(String(ViewPreferences.sanitize({"mayor_name":"a".repeat(80)}).mayor_name).length(),32)
	check_eq(ViewPreferences.write(clean,host.preferences_path),OK)
	check_eq(ViewPreferences.read(host.preferences_path).mayor_name,"María del Mar")

func test_settings_greeting_and_city_attribution() -> void:
	host.set_option(&"mayor_name","  Avery  ")
	check_eq(host.preferences.get("mayor_name"),"Avery")
	check_eq(host.title_screen.get_node("Panel").find_child("MayorGreeting",true,false).text if host.title_screen.find_child("MayorGreeting",true,false) != null else "", "WELCOME, MAYOR AVERY")
	var options := host.open_window("options") as OptionsWindow
	check(options.find_child("MayorName",true,false) is LineEdit,"Settings exposes the mayor name")
	options.close()
	var city := host.start_new_city({"seed":7},flat_city())
	check_eq(city.mayor,"Avery")
	host.set_option(&"mayor_name","Joan")
	check_eq(city.mayor,"Joan")
	host.prefs.flush()
	check_eq(ViewPreferences.read(host.preferences_path).get("mayor_name"),"Joan")

func test_typing_a_mayor_name_writes_preferences_once_typing_pauses() -> void:
	var options := host.open_window("options") as OptionsWindow
	var edit := options.find_child("MayorName",true,false) as LineEdit
	for typed: String in ["P","Pa","Pat"]:
		edit.text = typed
		edit.text_changed.emit(typed)
	check_eq(host.preferences.get("mayor_name"),"Pat","the profile follows each keystroke")
	check_eq(ViewPreferences.read(host.preferences_path).get("mayor_name",""),"","keystrokes are not written one by one")
	options.close()
	check_eq(ViewPreferences.read(host.preferences_path).get("mayor_name"),"Pat","closing Settings writes the name")
	options = host.open_window("options") as OptionsWindow
	edit.text = "Quinn"
	edit.text_changed.emit("Quinn")
	host._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check_eq(ViewPreferences.read(host.preferences_path).get("mayor_name"),"Quinn","suspension writes a pending name")
	edit.text = "Rae"
	edit.text_changed.emit("Rae")
	host._process(0.5)
	check_eq(ViewPreferences.read(host.preferences_path).get("mayor_name"),"Rae","a pause in typing writes the name")
	options.close()
	options = host.open_window("options") as OptionsWindow
	options.sensitivity_slider.value = 2.0
	check_eq(host.explore_hud.sensitivity,2.0,"the camera follows the slider at once")
	check_eq(ViewPreferences.read(host.preferences_path).explore_sensitivity,1.0,"slider steps are not written one by one")
	options.close()
	check_eq(ViewPreferences.read(host.preferences_path).explore_sensitivity,2.0,"closing Settings writes the sensitivity")

func test_loading_retains_saved_mayor_without_changing_profile() -> void:
	host.set_option(&"mayor_name","Local Mayor")
	var city := flat_city()
	city.mayor = "Guest Mayor"
	var path := "user://guest-mayor.sc2d"
	paths.append(path)
	check_eq(SaveFormat.save(path,city),OK)
	check(host.load_city(path))
	check_eq(host.sim.city.mayor,"Guest Mayor")
	check_eq(host.preferences.get("mayor_name"),"Local Mayor")
	check(not host.files.has_unsaved_changes(),"opening a shared city retains its checkpoint")
	host.set_option(&"mayor_name","New Mayor")
	check_eq(host.sim.city.mayor,"New Mayor")
	check(host.files.has_unsaved_changes(),"deliberate attribution change is saved as city work")

func test_save_header_credits_the_mayor() -> void:
	var city := flat_city()
	city.mayor = "Morgan"
	var path := "user://credited.sc2d"
	paths.append(path)
	check_eq(SaveFormat.save(path,city),OK)
	check_eq(SaveFormat.read_header(path).get("mayor"),"Morgan")
