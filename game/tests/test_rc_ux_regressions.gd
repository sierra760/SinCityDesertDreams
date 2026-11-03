# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://rc-ux-regressions.cfg"
const SAVE := "user://rc-ux-regressions.sc2d"
var host: GameHost

func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.new_city_dialog.terrain_transport_factory = preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport
	await settle()

func after_each() -> void:
	host.free()
	for filename in [PREFS, SAVE]: DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	await process_frame

func settle() -> void:
	for frame in 6: await process_frame

func press(code: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func owns_focus(control: Control) -> bool:
	var focused := root.gui_get_focus_owner()
	return focused != null and control.is_ancestor_of(focused)

func play() -> void:
	host.begin_city(flat_city(), {}, 42, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)

func test_keyboard_opened_help_keeps_tab_away_from_title_quit() -> void:
	host.title_screen.help_button.grab_focus()
	press(KEY_ENTER)
	await settle()
	var help := host.windows.help as Control
	check(help.visible)
	check(owns_focus(help), "Help receives keyboard focus")
	for i in 12:
		press(KEY_TAB, i % 2 == 0)
		check(owns_focus(help), "Tab and Shift+Tab stay in Help")
	host.escape()
	check(not help.visible)
	check_eq(root.gui_get_focus_owner(), host.title_screen.help_button, "closing restores the initiating action")

func test_help_cannot_change_a_background_tax_and_restores_its_focus() -> void:
	play()
	var budget := host.open_window("budget") as BudgetWindow
	budget.select_page("Taxes")
	await settle()
	var plus: Button = budget._tax_spinners[&"residential"]._plus
	plus.grab_focus()
	host.menu_bar.action_requested.emit(&"help", null)
	await settle()
	var before := host.sim.snapshot().duplicate(true)
	press(KEY_SPACE)
	await settle()
	check_eq(host.sim.stats.tax_residential, 7, "Space does not activate the background tax button")
	check_eq(host.sim.snapshot(), before, "reading Help changes no simulation state")
	if host.window_manager.is_open("help"): host.escape()
	check_eq(root.gui_get_focus_owner(), plus, "closing Help restores the previous report control")
	check_eq(host.modal_depth, 0, "reports retain their nonmodal contract")

func test_raising_and_closing_windows_keeps_focus_with_the_front_window() -> void:
	play()
	var budget := host.open_window("budget")
	var help := host.open_window("help")
	host.open_window("budget")
	await settle()
	check(owns_focus(budget), "raising an open report also raises its keyboard owner")
	help.close()
	check(owns_focus(budget), "closing a background window cannot steal focus")
	var population := host.open_window("population")
	await settle()
	press(KEY_ESCAPE)
	check(not population.visible and budget.visible, "Escape closes only the front report")
	check(owns_focus(budget), "the exposed report regains focus")

func test_report_focus_yields_to_a_notice_without_resizing_the_report() -> void:
	play()
	var budget := host.open_window("budget") as BudgetWindow
	await settle()
	var before := budget._root.size
	host.notices.show("Notice", "A modal owns the next keyboard action.")
	host.open_window("help")
	press(KEY_TAB)
	check(owns_focus(host.notice_dialog), "report navigation cannot take a modal's focus")
	host.notice_dialog.dismiss()
	host.open_window("budget")
	await settle()
	check_eq(budget._root.size, before, "keyboard containment does not grow reports into modal forms")
	check_eq(host.modal_depth, 0)

func test_loading_card_fits_phone_safe_bounds_and_reflows_on_rotation() -> void:
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1280, 800)]:
		root.size = dimensions
		var safe := Rect2i(8, 20, dimensions.x - 16, dimensions.y - 40)
		host.display_layout.refresh_with_mobile_metrics(dimensions, 1, safe)
		host.loading_screen.open("Preparing Explore…", "Preparing walking paths, vehicles and station interiors. " + "M".repeat(40) + ".sc2d")
		await settle()
		var panel := host.loading_screen.get_node("Center/Panel") as Control
		check(host.display_layout.logical_rect().grow(0.5).encloses(panel.get_global_rect()), "loading fits safe bounds at %s" % dimensions)
		check(panel.get_global_rect().encloses(host.loading_screen.detail.get_global_rect()), "loading detail stays inside its card")
	host.loading_screen.close()

func rows() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in 100:
		entries.append({"name": "City %03d" % i, "slot_id": "slot-%d" % i,
			"cloud_owned": true, "path": "user://saves/city%d.sc2d" % i, "population": i * 100})
	return entries

func test_changed_save_rows_preserve_scroll_and_selected_identity() -> void:
	var entries := rows()
	host.files.open_load_dialog()
	var dialog := host.load_dialog
	dialog.refresh(entries)
	await settle()
	dialog.item_list.get_v_scroll_bar().value = 700
	await settle()
	entries[99].population = 12345
	dialog.refresh(entries)
	await settle()
	check_eq(dialog.item_list.get_v_scroll_bar().value, 700.0, "a changed row does not jump back to selection")
	check_eq(dialog.selected_entry().slot_id, "slot-0")
	entries.push_front({"name": "New city", "slot_id": "new", "path": "user://new.sc2d"})
	dialog.refresh(entries)
	await settle()
	check_eq(dialog.item_list.get_v_scroll_bar().value, 700.0, "inserting a row preserves browsing position")
	check_eq(dialog.selected_entry().slot_id, "slot-0", "selection follows identity when its index changes")
	dialog.select(90)
	await settle()
	check_gt(dialog.item_list.get_v_scroll_bar().value, 700.0, "explicit selection still reveals its row")

func test_save_list_scroll_clamps_when_rows_disappear() -> void:
	host.files.open_load_dialog()
	var dialog := host.load_dialog
	var entries := rows()
	dialog.refresh(entries)
	await settle()
	dialog.item_list.get_v_scroll_bar().value = 700
	dialog.refresh(entries.slice(0, 2))
	await settle()
	check_eq(dialog.item_list.get_v_scroll_bar().value, 0.0, "shortened lists clamp to their valid range")
	dialog.refresh([])
	await settle()
	check(dialog.selected_entry().is_empty())
	check(dialog.load_button.disabled)

func test_loaded_city_guidance_and_speed_tooltip_follow_rebound_keys() -> void:
	play()
	host.sim.set_speed(GameClock.Speed.FAST)
	check_eq(SaveFormat.save(SAVE, host.sim.city, host.sim.snapshot()), OK)
	check_eq(host.controls.assign(&"pause", 0, KEY_K), "")
	check_eq(host.controls.assign(&"pause", 1, KEY_L), "")
	host.prefs.set_option(&"control_bindings", host.controls.values())
	check(host.load_city(SAVE))
	var message := host.status_bar.message_label.text
	check(message.contains("K / L") and not message.contains("or P"), "load hint names the actual pause bindings")
	check(host.status_bar.speed_label.tooltip_text.contains("K / L"), "speed tooltip names the same bindings")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host.display_layout.release_city_focus()
	press(KEY_K)
	check_eq(host.sim.speed, GameClock.Speed.FAST, "the advertised key resumes the saved speed")

func test_phone_loaded_city_guidance_names_the_phone_speed_menu() -> void:
	play()
	check_eq(SaveFormat.save(SAVE, host.sim.city, host.sim.snapshot()), OK)
	root.size = Vector2i(390, 844)
	host.display_layout.refresh_with_mobile_metrics(root.size, 1, Rect2i(Vector2i.ZERO, root.size))
	check(host.load_city(SAVE))
	check(host.status_bar.message_label.text.contains("Menu → Speed"), "phone guidance points to its visible menu")
	check(not host.status_bar.message_label.text.contains("or P"), "touch guidance does not require a keyboard")

func test_clicking_an_older_report_keeps_subsequent_keyboard_navigation_there() -> void:
	play()
	await _click_older_report()

func test_annual_budget_clock_hold_preserves_report_mouse_switching() -> void:
	play()
	host.sim.budget_review_pending = true
	host.present_budget_review()
	await _click_older_report()
	check_eq(host.modal_depth, 1, "report switching retains the annual review hold")
	check(host.sim.budget_review_pending)

func _click_older_report() -> void:
	var budget := host.open_window("budget") as BudgetWindow
	budget.select_page("Taxes")
	budget._root.position = Vector2(40, 150)
	var help := host.open_window("help") as HelpWindow
	help.panel.position = Vector2(700, 100)
	await settle()
	var plus: Button = budget._tax_spinners[&"residential"]._plus
	var point := plus.get_global_rect().get_center()
	check(not help.panel.get_global_rect().has_point(point), "fixture exposes the older report's control")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	await settle()
	check_eq(host.sim.stats.tax_residential, 8, "the intentional pointer action reaches the exposed control")
	press(KEY_TAB)
	check(owns_focus(budget), "Tab follows the report selected with the pointer")
	check_eq(host.window_manager.front(), budget, "the clicked report becomes the front window")

func test_loading_card_bounds_long_filenames_and_keyboard_reduced_space() -> void:
	for spec: Array in [[Vector2i(320, 568), 0], [Vector2i(568, 320), 0], [Vector2i(390, 844), 604]]:
		root.size = spec[0]
		host.display_layout.refresh_with_mobile_metrics(root.size, 1, Rect2i(Vector2i.ZERO, root.size), spec[1])
		host.loading_screen.open("Loading city…", "W".repeat(250) + ".sc2d")
		await settle()
		var panel := host.loading_screen.get_node("Center/Panel") as Control
		check(host.display_layout.logical_rect().grow(0.5).encloses(panel.get_global_rect()), "long filename card fits the usable height at %s, keyboard %s" % spec)
	host.loading_screen.close()
