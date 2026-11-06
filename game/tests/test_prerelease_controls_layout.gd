# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 10: await process_frame

func test_binding_groups_fit_small_phone_and_restore_desktop_rows() -> void:
	var options := OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.set_process(false)
	options.set_keyboard_available(true)
	options.tabs.current_tab = 1
	var scroll: ScrollContainer = options.panel.get_meta("window_chrome").body_scroll
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(1280,800),Vector2i(320,568)]:
		root.size = dimensions
		await settle()
		for group: String in options._groups:
			for other: String in options._groups: options._groups[other].visible = other == group
			await settle()
			check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page+1,"%s at %s needs no sideways reading" % [group,dimensions])
			for action: String in ControlBindings.GROUPS[group]:
				var primary: Button = options.binding_buttons[action][0]
				var alternate: Button = options.binding_buttons[action][1]
				for button: Button in [primary,alternate]:
					check_ge(button.size.x,44)
					check_ge(button.size.y,44)
					check(button.get_global_rect().position.x >= scroll.global_position.x,"key starts inside viewport")
					check(button.get_global_rect().end.x <= scroll.get_global_rect().end.x,"whole key fits viewport")
				check_eq(primary.global_position.y,alternate.global_position.y,"key choices stay paired")
				for label: Label in options._groups[group].find_children("*","Label",true,false):
					if label.text != ControlBindings.LABELS[action]: continue
					if dimensions.x == 320:
						check(label.get_global_rect().end.y <= primary.global_position.y,"phone labels sit above paired keys")
					elif dimensions.x == 1280:
						check(label.get_global_rect().end.x <= primary.global_position.x,"desktop restores labels beside keys")
	options.free()

func test_reflow_retains_key_capture_and_uses_the_original_buttons() -> void:
	root.size = Vector2i(1280,800)
	var options := OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.set_process(false)
	options.set_keyboard_available(true)
	options.tabs.current_tab = 1
	await settle()
	var button: Button = options.binding_buttons["rotate"][0]
	button.grab_focus()
	button.pressed.emit()
	root.size = Vector2i(320,568)
	await settle()
	check_eq(root.gui_get_focus_owner(),button,"resizing keeps the key being edited")
	check_eq(button.text,"Press key…")
	var scroll: ScrollContainer = options.panel.get_meta("window_chrome").body_scroll
	check(scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()),"the focused key remains visible after wrapping")
	var event := InputEventKey.new()
	event.keycode = KEY_Y
	event.pressed = true
	check(options.capture_event(event))
	check_eq(options.controls.caption(&"rotate"),"Y","narrow control changes the real binding")
	check_eq(options.binding_buttons["rotate"][0],button)
	options.free()

func test_resize_does_not_return_focus_to_a_closed_controls_page() -> void:
	root.size = Vector2i(1280,800)
	var options := OptionsWindow.new()
	root.add_child(options)
	options.open()
	options.set_process(false)
	options.set_keyboard_available(true)
	options.tabs.current_tab = 1
	await settle()
	(options.binding_buttons["rotate"][0] as Button).grab_focus()
	root.size = Vector2i(320,568)
	await process_frame
	options.close()
	var next := UIFactory.make_button("Next action")
	root.add_child(next)
	next.grab_focus()
	await settle()
	check_eq(root.gui_get_focus_owner(),next,"a pending reveal yields to the new screen")
	options.free()
	next.free()
