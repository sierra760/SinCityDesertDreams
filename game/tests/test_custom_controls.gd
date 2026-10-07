# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const PATH := "res://scripts/input/control_bindings.gd"

func controls() -> Variant:
	check(ResourceLoader.exists(PATH), "customizable input bindings exist")
	return load(PATH).new() if ResourceLoader.exists(PATH) else null

func key(code: Key, down := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	return event

func test_rebinding_replaces_old_key_and_preserves_other_context() -> void:
	var input: Variant = controls()
	if input == null: return
	check_eq(input.assign(&"query", 0, KEY_H), "")
	check(input.matches(key(KEY_H), &"query"))
	check(not input.matches(key(KEY_Q), &"query"), "old shortcut is removed")
	check(input.matches(key(KEY_Q), &"ascend"), "Explore retains its own Q")
	var chord := key(KEY_H)
	chord.ctrl_pressed = true
	check(not input.matches(chord, &"query"), "application chords cannot trigger city input")
	var released := key(KEY_H,false)
	released.ctrl_pressed = true
	check(input.matches(released,&"query"), "held-key cleanup survives a modifier pressed later")
	input.reset()
	check(input.matches(key(KEY_Q), &"query"))
	check(not input.matches(key(KEY_H), &"query"))

func test_conflicts_reject_assignment_without_silently_losing_an_action() -> void:
	var input: Variant = controls()
	if input == null: return
	check(not input.assign(&"query", 0, KEY_B).is_empty())
	check(input.matches(key(KEY_Q), &"query"))
	check(not input.assign(&"pause", 0, KEY_W).is_empty(), "global commands conflict with either mode")
	check(not input.assign(&"query", 0, KEY_ESCAPE).is_empty(), "Escape remains an exit and capture cancel")
	check_eq(input.assign(&"jump", 0, KEY_SPACE), "", "walk jump and vehicle brake intentionally share Space")
	check_eq(input.assign(&"query", 0, KEY_F), "", "Build and Explore may share keys")

func test_preferences_validate_and_persist_custom_bindings() -> void:
	var input: Variant = controls()
	if input == null: return
	input.assign(&"interact", 0, KEY_H)
	var path := "user://custom-controls-test.cfg"
	check_eq(ViewPreferences.write({"control_bindings":input.values()},path), OK)
	var read := ViewPreferences.read(path)
	check(read.has("control_bindings"), "bindings survive a restart")
	if read.has("control_bindings"):
		input.configure(read.control_bindings)
		check(input.matches(key(KEY_H), &"interact"))
		check(not input.matches(key(KEY_F), &"interact"))
	input.configure({"query":[KEY_ESCAPE],"move_forward":[NAN],"unknown":[KEY_H]})
	check(input.matches(key(KEY_Q), &"query"), "invalid saved bindings restore usable defaults")
	check(input.matches(key(KEY_W), &"move_forward"))
	input.configure({"query":[KEY_B]})
	check(input.matches(key(KEY_Q),&"query"),"a colliding saved profile cannot strand Query")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_explore_frame_uses_custom_held_keys_and_press_edges() -> void:
	var input: Variant = controls()
	if input == null: return
	input.assign(&"move_forward", 0, KEY_UP)
	input.assign(&"interact", 0, KEY_H)
	var frame: ExploreInputFrame = ExploreInputFrame.new().call("from_keys",{KEY_UP:true,KEY_H:true},{KEY_H:true},input)
	check_eq(frame.move, Vector2(0,-1))
	check(frame.interact)
	frame = ExploreInputFrame.new().call("from_keys",{KEY_W:true,KEY_H:true},{},input)
	check_eq(frame.move, Vector2.ZERO, "old movement binding is removed")
	check(not frame.interact, "interaction remains a press edge")

func test_keyboard_presence_uses_hardware_and_ignores_virtual_keyboard() -> void:
	var platform: Variant = MobilePlatform.new()
	check(not platform.has_keyboard({"os_name":"iOS","hardware_keyboard":false,"keyboard_height_px":280}))
	check(platform.has_keyboard({"os_name":"iOS","hardware_keyboard":true}))
	check(not platform.has_keyboard({"os_name":"Android","hardware_keyboard":false}))
	check(platform.has_keyboard({"os_name":"macOS"}))

func test_settings_hide_bindings_and_cancel_capture_on_disconnect() -> void:
	var options: Variant = OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.tabs.current_tab = 1
	options.set_keyboard_available(true)
	check(options.keyboard_section.is_visible_in_tree())
	options.begin_capture(&"query",0)
	options.set_keyboard_available(false)
	check(not options.keyboard_section.is_visible_in_tree())
	check(not options.is_capturing(), "disconnect cannot leave an invisible key listener")
	check(options.sensitivity_slider.is_visible_in_tree(), "touch camera settings remain available")
	options.free()

func test_mobile_settings_hide_fullscreen_binding_after_lazy_creation() -> void:
	var options: Variant = OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.tabs.current_tab = 1
	options.set_keyboard_available(true)
	options.set_display_metrics({"mobile":true})
	var button: Button = options.binding_buttons.fullscreen[0]
	check(not button.visible,"mobile cannot expose fullscreen through the keyboard editor")
	options.set_display_metrics({"mobile":false})
	check(button.visible,"desktop keeps its fullscreen binding")
	options.free()

func test_capture_cancels_rejects_conflicts_and_emits_only_valid_change() -> void:
	var options: Variant = OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.set_keyboard_available(true)
	var emitted: Array = []
	options.option_changed.connect(func(k,v): emitted.append([k,v]))
	options.begin_capture(&"query",0)
	check(options.capture_event(key(KEY_ESCAPE)))
	check(not options.is_capturing())
	check(emitted.is_empty())
	options.begin_capture(&"query",0)
	check(options.capture_event(key(KEY_B)))
	check(options.is_capturing(), "conflict leaves old binding intact and can be retried")
	check(emitted.is_empty())
	check(options.capture_event(key(KEY_H)))
	check(not options.is_capturing())
	check_eq(emitted.size(),1)
	check_eq(emitted[0][0],&"control_bindings")
	options.free()

func test_host_routes_custom_shortcuts_and_capture_without_city_mutation() -> void:
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://custom-controls-host.cfg"
	root.add_child(host)
	var city := flat_city()
	host.start_new_city({"name":"Control test","difficulty":0,"year":1900},city)
	await host.run_loading("Founding…","",host.found_city)
	var input: Variant = controls()
	if input == null:
		host.free()
		return
	input.assign(&"query",0,KEY_H)
	input.assign(&"bulldoze",0,KEY_J)
	input.assign(&"rotate",0,KEY_K)
	host.set_option(&"control_bindings",input.values())
	var snapshot := SaveFormat.encode_city(host.sim.city)
	host._unhandled_key_input(key(KEY_H))
	check_eq(host.tool,Tools.Kind.QUERY,"host consumes new Query binding")
	host._unhandled_key_input(key(KEY_J))
	check_eq(host.tool,Tools.Kind.BULLDOZE)
	host._input(key(KEY_J,false))
	check_eq(host.tool,Tools.Kind.QUERY,"custom release restores previous tool")
	var rotation := host.city_view_3d.quarter_turn
	host.city_view_3d._unhandled_input(key(KEY_K))
	check_eq(host.city_view_3d.quarter_turn,posmod(rotation+1,4))
	var options := host.open_window("options") as OptionsWindow
	options.tabs.current_tab = 1
	var speed := host.sim.speed
	options.begin_capture(&"pause",0)
	host._input(key(KEY_P))
	check_eq(host.sim.speed,speed,"capturing the live Pause key cannot also pause the city")
	options.begin_capture(&"pause",0)
	host._input(key(KEY_N))
	check(not options.is_capturing())
	check(host.controls.matches(key(KEY_N),&"pause"))
	check_eq(host.tool,Tools.Kind.QUERY,"capture cannot also select a tool")
	check_eq(SaveFormat.encode_city(host.sim.city),snapshot,"binding edits do not touch city state")
	check(host.toolbar.buttons[Tools.Kind.QUERY].tooltip_text.contains("H"),"toolbar describes current key")
	var persisted := ViewPreferences.read(host.preferences_path)
	var loaded: Variant = controls()
	loaded.configure(persisted.control_bindings)
	check(loaded.matches(key(KEY_N),&"pause"),"host saved the edited binding")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://custom-controls-host.cfg"))
	await process_frame

func test_saved_explore_bindings_gain_arrow_keys_once() -> void:
	var path := "user://legacy-controls-test.cfg"
	var legacy := ControlBindings.DEFAULTS.duplicate(true)
	for action: String in ControlBindings.MOVEMENT_ACTIONS: legacy[action] = [legacy[action][0]]
	legacy["interact"] = [KEY_LEFT]
	var config := ConfigFile.new()
	config.set_value(ViewPreferences.SECTION,"control_bindings",legacy)
	check_eq(config.save(path),OK)
	var read := ViewPreferences.read(path)
	var input := ControlBindings.new()
	input.configure(read.control_bindings)
	check(input.matches(key(KEY_UP),&"move_forward"),"an older profile gains the Up arrow")
	check(input.matches(key(KEY_RIGHT),&"move_right"))
	check(not input.matches(key(KEY_LEFT),&"move_left"),"an arrow the player gave another Explore action stays there")
	check(input.matches(key(KEY_LEFT),&"interact"))
	check_eq(read.control_bindings_version,ViewPreferences.CONTROL_BINDINGS_VERSION)
	input.clear_alternate(&"move_forward")
	read.control_bindings = input.values()
	check_eq(ViewPreferences.write(read,path),OK)
	var again := ControlBindings.new()
	again.configure(ViewPreferences.read(path).control_bindings)
	check(not again.matches(key(KEY_UP),&"move_forward"),"a cleared alternate stays cleared")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
