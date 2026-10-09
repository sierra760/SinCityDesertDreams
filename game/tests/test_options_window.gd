# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Settings window behaviour: key capture, sound rows, size readout, the
## fullscreen caption and the tab bar.
extends "res://tests/exploration/async_test_case.gd"

var options: OptionsWindow

func before_each() -> void:
	options = OptionsWindow.new()
	root.add_child(options)
	options.open()

func after_each() -> void:
	options.free()
	await process_frame

# Guards against: another setting changing during a key capture leaving the
# capture active but hidden, so the next key is bound without warning.
func test_other_changes_end_a_key_capture() -> void:
	options.set_keyboard_available(true)
	options.begin_capture(&"rotate", 0)
	check(options.is_capturing())
	check_eq((options.binding_buttons["rotate"][0] as Button).text, "Press key…")
	options.set_values({"control_bindings": options.controls.values(), "tile_grid": true})
	check(options.is_capturing(), "a refresh from elsewhere keeps the capture")
	check_eq((options.binding_buttons["rotate"][0] as Button).text, "Press key…", "and its prompt stays visible")
	var changes: Array = []
	options.option_changed.connect(func(key: StringName, _value: Variant) -> void: changes.append(key))
	options.checks[&"tile_grid"].button_pressed = not options.checks[&"tile_grid"].button_pressed
	check(not options.is_capturing(), "toggling a setting ends the capture")
	check_eq(changes, [&"tile_grid"])
	check_ne((options.binding_buttons["rotate"][0] as Button).text, "Press key…")

# Guards against: a silent, still-active slider for a switched-off sound group,
# and sliders with no visible level.
func test_volume_rows_follow_their_switches_and_show_a_level() -> void:
	options.set_values({"music_enabled": false, "effects_enabled": true, "music_volume": 0.4, "effects_volume": 0.85})
	check(not options.music_slider.editable, "Music off greys its slider")
	check(options.effects_slider.editable)
	check_eq((options.volume_labels[&"music_volume"] as Label).text, "40%")
	check_eq((options.volume_labels[&"effects_volume"] as Label).text, "85%")
	options.checks[&"music_enabled"].button_pressed = true
	check(options.music_slider.editable, "switching Music on enables its slider")
	options.effects_slider.value = 0.5
	check_eq((options.volume_labels[&"effects_volume"] as Label).text, "50%")

# Guards against: "Effective size: 87.50%".
func test_effective_size_reads_as_a_whole_percent() -> void:
	options.set_display_metrics({"requested_percent": 150, "effective_percent": 87.5})
	check(options.effective_label.text.begins_with("Effective size: 88%"), options.effective_label.text)

# Guards against: Settings advertising F11, which macOS keeps for Show Desktop.
func test_fullscreen_caption_names_a_working_shortcut() -> void:
	var caption := (options.checks[&"fullscreen"] as CheckBox).text
	if OS.get_name() == "macOS":
		check_eq(caption, "Fullscreen [Ctrl+Cmd+F]")
		check_eq(OptionsWindow.fullscreen_caption("F12"), "Fullscreen [Ctrl+Cmd+F or F12]", "a rebound key is listed too")
	else:
		check_eq(caption, "Fullscreen [%s]" % options.controls.caption(&"fullscreen"))

# Guards against: General and Controls tabs touching with no gap.
func test_tabs_are_separated() -> void:
	check(options.tabs.get_theme_constant("tab_separation") >= 8)
	check(options.tabs.get_theme_stylebox("tab_selected").content_margin_left >= 24.0)
