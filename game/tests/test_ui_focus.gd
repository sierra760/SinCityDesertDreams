# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
var layout: DisplayLayout
var holder: Control
func before_each() -> void:
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	holder = Control.new()
	root.add_child(holder)
func after_each() -> void:
	holder.free()
	layout.free()
func test_focused_inputs_block_every_city_key() -> void:
	for control in [LineEdit.new(),HSlider.new(),SpinBox.new(),UIFactory.make_button("Build")]:
		holder.add_child(control)
		if control is SpinBox:
			control.get_line_edit().grab_focus()
		else:
			control.grab_focus()
		for key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_R,KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_P,KEY_PLUS,KEY_MINUS,KEY_B]:
			check(layout.blocks_city_keyboard(),"focused control guards key %d" % key)
		layout.release_city_focus()
		check(not layout.blocks_city_keyboard(),"map input releases old keyboard focus")
		control.free()
func test_popup_and_drag_guard() -> void:
	var popup := PopupPanel.new()
	root.add_child(popup)
	popup.visible = true
	check(layout.blocks_city_keyboard())
	popup.free()
	var chrome := UIFactory.make_window_chrome("Dragging")
	holder.add_child(chrome["root"])
	WindowDrag.enable(chrome["title_bar"],chrome["root"])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	chrome["title_bar"].gui_input.emit(press)
	check(layout.blocks_city_keyboard())
	WindowDrag.cancel_all()
	check(not layout.blocks_city_keyboard())

func test_inactive_window_blocks_city_keys() -> void:
	check(DisplayLayout.keyboard_is_blocked(null,false,false,false))
	check(not DisplayLayout.keyboard_is_blocked(null,false,false,true))
