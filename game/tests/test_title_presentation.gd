# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 6: await process_frame

func actions(title: TitleScreen) -> Array[Button]:
	return [title.new_button, title.load_button, title.import_button, title.settings_button, title.help_button, title.quit_button]

func test_title_actions_fit_and_keep_focus_across_display_sizes() -> void:
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(640,400),Vector2i(1000,640),Vector2i(640,900)]:
		root.size = dimensions
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		title.apply_layout(bounds)
		await settle()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), "title frame fits " + str(dimensions))
		for button: Button in actions(title):
			button.grab_focus()
			await settle()
			check(button.has_focus(), "original action retains focus")
			check(bounds.encloses(button.get_global_rect()), "action reachable after display reflow: " + button.text)
			check(title._actions_scroll.get_global_rect().encloses(button.get_global_rect()), "focused action clears the scroll clip")
			check(button.size.x >= 44 and button.size.y >= 44, "action target retained")
	title.free()

func test_title_never_scrolls_on_common_desktop_and_tablet_screens() -> void:
	# Every action, the greeting and the credits stay in view without a scroll
	# clip: the panel grows to its content when the screen has room, and
	# tightens its rows before it would ever scroll on a short screen.
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	var screens := {
		"macOS 1440x900": Rect2(0,0,1440,900), "macOS 1280x800": Rect2(0,0,1280,800),
		"Windows 1366x768": Rect2(0,0,1366,768), "Windows 1280x720": Rect2(0,0,1280,720),
		"Windows 1920x1080": Rect2(0,0,1920,1080), "iPad 1180x820": Rect2(0,24,1180,796),
		"iPad 1024x768": Rect2(0,24,1024,744), "iPad portrait 820x1180": Rect2(0,24,820,1156),
		"short 900x620": Rect2(0,0,900,620), "short 1000x660": Rect2(0,0,1000,660),
	}
	for label: String in screens:
		var bounds: Rect2 = screens[label]
		root.size = Vector2i(bounds.end)
		title.apply_layout(bounds)
		await settle()
		var clip := title._actions_scroll.get_global_rect()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), label + ": title frame fits")
		check(title._actions.get_combined_minimum_size().y <= clip.size.y + .5, label + ": the action column needs no scrolling")
		check_eq(title._actions_scroll.scroll_vertical, 0, label + ": nothing is scrolled away")
		for button: Button in actions(title):
			check(clip.encloses(button.get_global_rect()), label + ": " + button.text + " is fully in view")
			check(button.size.y >= 44, label + ": " + button.text + " keeps its touch height")
	title.free()

func test_actions_fill_the_available_column_when_artwork_is_hidden() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(not title._poster.visible,"restricted layout concentrates on actions")
		check(absf(title._actions_scroll.size.x - title._content.size.x) <= 1.0,"actions use the complete restricted column width")
	title.free()

func test_title_respects_narrow_safe_areas_and_keyboard() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), "title frame stays in usable area: " + str(bounds))
		for button: Button in actions(title):
			button.grab_focus()
			await settle()
			check(bounds.encloses(button.get_global_rect()), "focused action reachable above keyboard/in safe area: " + button.text)
			check(title._actions_scroll.get_global_rect().encloses(button.get_global_rect()), "restricted focused action clears the scroll clip")
	title.free()

func test_focused_title_action_follows_live_safe_area_reflow() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	title.apply_layout(Rect2(0,0,640,400))
	await settle()
	title.quit_button.grab_focus()
	await settle()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(title.quit_button.has_focus(), "display reflow preserves focused action")
		check(bounds.encloses(title.quit_button.get_global_rect()), "same focus follows the resized title scroll viewport")
		check(title._actions_scroll.get_global_rect().encloses(title.quit_button.get_global_rect()), "same focus remains within the scroll clip")
	title.free()

func test_brand_and_artwork_follow_a_clear_reading_order_and_grid() -> void:
	root.size = Vector2i(1280,800)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	title.apply_layout(Rect2(0,0,1280,800))
	await settle()
	var headline := title._title.get_global_rect()
	var edition := title._logo.get_global_rect()
	var art := title._poster.get_global_rect()
	check(headline.end.y <= edition.position.y,"main identity precedes the edition line")
	check(edition.end.y < art.position.y,"typography has its own area above the illustration")
	check(absf(headline.position.x - edition.position.x) <= 1.0,"title lockup shares a left edge")
	check(absf(headline.position.x - art.position.x) <= 1.0,"artwork follows the title grid")
	check(art.end.x < title.new_button.get_global_rect().position.x,"artwork and action column remain separate")
	title.free()

func _command(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	if OS.get_name() == "macOS": key.meta_pressed = true
	else: key.ctrl_pressed = true
	return key

# Guards against: the City menu's file shortcuts doing nothing on the title.
func test_title_shortcuts_reach_new_load_and_settings() -> void:
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	var events: Array[String] = []
	title.new_city_requested.connect(func() -> void: events.append("new"))
	title.load_requested.connect(func() -> void: events.append("load"))
	title.settings_requested.connect(func() -> void: events.append("settings"))
	title.help_requested.connect(func() -> void: events.append("help"))
	for code: Key in [KEY_N, KEY_O, KEY_COMMA]:
		root.push_input(_command(code))
	await process_frame
	check_eq(events, ["new", "load", "settings"] as Array[String])
	var blocked := true
	title.shortcuts_blocked = func() -> bool: return blocked
	root.push_input(_command(KEY_N))
	await process_frame
	check_eq(events.size(), 3, "a dialog that owns input keeps the shortcut from opening another")
	title.help_button.pressed.emit()
	check_eq(events.back(), "help", "the title offers Help")
	title.free()

# Guards against: Help unreachable before a city exists.
func test_title_help_opens_above_the_title_in_main() -> void:
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://title-help.cfg"
	root.add_child(host)
	await settle()
	check(host.title_screen.visible)
	host.title_screen.help_button.pressed.emit()
	var help := host.windows.get("help") as Control
	check(help != null and help.is_visible_in_tree(), "Help opens from the title")
	if help != null:
		check(help.get_parent() == host.modal_layer and help.get_index() > host.title_screen.get_index(), "Help sits above the title")
		help.call("close")
	root.push_input(_command(KEY_N))
	await process_frame
	check(host.new_city_dialog.is_open(), "Cmd/Ctrl+N opens New City from the title")
	host.new_city_dialog.close()
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title-help.cfg"))
	await process_frame
