# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
class ChromeHost extends GameHost:
	func save_preferences() -> void: pass

func settle() -> void:
	for i in 5: await process_frame

func test_shared_control_states_have_readable_colors() -> void:
	var theme := UITheme.control_theme()
	for kind: String in ["Button","OptionButton","CheckBox"]:
		check_eq(theme.get_color("font_hover_color",kind),UITheme.TEXT_PRIMARY,"hover keeps dark text on light stone")
		check_eq(theme.get_color("font_hover_pressed_color",kind),UITheme.TITLE_TEXT)
	for kind: String in ["LineEdit","ItemList","PopupMenu","TooltipPanel"]:
		check(theme.has_stylebox("normal" if kind == "LineEdit" else "panel",kind),"shared field style exists")
		var sb := theme.get_stylebox("normal" if kind == "LineEdit" else "panel",kind)
		check(sb is StyleBoxFlat and sb.bg_color.a == 1.0 and sb.bg_color.get_luminance() > 0.5,"opaque light field/list/menu: " + kind)
	var chrome := UIFactory.make_window_chrome("Budget")
	check(chrome.close_button.tooltip_text.contains("Close") and chrome.close_button.tooltip_text.contains("Esc"))
	chrome.root.free()

func test_long_notice_actions_fit_and_wrap() -> void:
	root.size = Vector2i(640,400)
	var notice := NoticeDialog.new()
	root.add_child(notice)
	notice.show_notice("Unsaved city","Body ".repeat(500),[["Cancel and keep editing",&"cancel"],["Discard the current city",&"discard"],["Save changes and continue",&"save"]])
	await settle()
	check(notice.button_row is HBoxContainer,"existing typed callers remain compatible")
	check(root.get_visible_rect().encloses(notice.panel.get_global_rect()),"compact panel fits")
	for button: Button in notice.choice_buttons:
		check(root.get_visible_rect().encloses(button.get_global_rect()),"every action reachable")
		check(button.size.y >= 44.0)
	check(notice.choice_buttons[0].position.y != notice.choice_buttons[-1].position.y,"long actions wrap")
	root.size = Vector2i(1280,800)
	await settle()
	check(root.get_visible_rect().encloses(notice.panel.get_global_rect()))
	notice.free()

func test_modal_focus_and_safe_dismissal() -> void:
	var background := UIFactory.make_button("Background")
	root.add_child(background)
	var notice := NoticeDialog.new()
	root.add_child(notice)
	var result: Array[StringName] = []
	notice.closed.connect(func(choice: StringName): result.append(choice))
	notice.show_notice("Unsaved city","Body",[["Save",&"save"],["Discard",&"discard"],["Cancel",&"cancel"]])
	await settle()
	check(notice.is_ancestor_of(notice.choice_buttons[-1].find_next_valid_focus()),"Tab cannot leave modal")
	check(notice.is_ancestor_of((notice.panel.get_meta("window_chrome").close_button as Control).find_prev_valid_focus()),"Shift-Tab cannot leave modal")
	notice.dismiss()
	check_eq(result,[&"cancel"] as Array[StringName],"closing never submits destructive first choice")
	notice.show_notice("Ordinary notice","Text")
	notice.dismiss()
	check_eq(result[-1],&"ok","ordinary notices retain acknowledgement")
	notice.free()
	background.free()

func test_focused_choice_scrolls_into_view() -> void:
	root.size = Vector2i(640,400)
	var dialog := ConstructionChoiceDialog.new()
	root.add_child(dialog)
	var options: Array = []
	for i in 20: options.append({"key":StringName("option%d" % i),"label":"Bridge option %d" % i,"cost":10})
	dialog.open("Choose bridge","Select an option",options,100)
	await settle()
	dialog.option_buttons[-1].grab_focus()
	await settle()
	var scroll: ScrollContainer = dialog.panel.get_meta("window_chrome").body_scroll
	check(scroll.scroll_vertical > 0,"focused last option scrolls")
	check(scroll.get_global_rect().intersects(dialog.option_buttons[-1].get_global_rect()))
	check(dialog.is_ancestor_of(dialog.build_button.find_next_valid_focus()),"construction focus wraps")
	dialog.free()

func test_stacked_modal_does_not_steal_tab_and_restores_focus() -> void:
	var first := NoticeDialog.new()
	var second := NoticeDialog.new()
	root.add_child(first)
	root.add_child(second)
	first.show_notice("First","Text")
	await settle()
	var previous := first.choice_buttons[0]
	second.show_notice("Second","Text",[["Cancel",&"cancel"],["Replace",&"replace"]])
	await settle()
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	root.push_input(tab)
	await settle()
	check(second.is_ancestor_of(root.gui_get_focus_owner()),"underlying modal cannot steal Tab")
	second.dismiss()
	check_eq(root.gui_get_focus_owner(),previous,"nested modal returns focus to prior choice")
	first.free()
	second.free()

func test_main_hidden_modals_refit_after_becoming_visible() -> void:
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(ChromeHost)
	root.add_child(host)
	root.size = Vector2i(640,400)
	await settle()
	host.display_layout.refresh_with_metrics(Vector2i(640,400),1.0)
	host.set_option(&"ui_scale",100)
	await settle()
	host.save_dialog.open("Desert Springs")
	await settle()
	check(root.get_visible_rect().encloses(host.save_dialog.panel.get_global_rect()),"Main Save panel fits after hidden registration")
	check(root.get_visible_rect().encloses(host.save_dialog.cancel_button.get_global_rect()),"Main Save Cancel reachable")
	host.save_dialog.close()
	host.notice_dialog.show_notice("Save your city?","Save changes before continuing?",[["Cancel",&"cancel"],["Discard",&"discard"],["Save",&"save"]])
	await settle()
	check(root.get_visible_rect().encloses(host.notice_dialog.panel.get_global_rect()),"Main Notice panel fits after hidden registration")
	for button: Button in host.notice_dialog.choice_buttons:
		check(root.get_visible_rect().encloses(button.get_global_rect()),"Main Notice action reachable")
	host.notice_dialog.dismiss()
	host.load_dialog.open([] as Array[Dictionary])
	await settle()
	check(root.get_visible_rect().encloses(host.load_dialog.panel.get_global_rect()),"Main Load fits")
	host.load_dialog.close()
	host.new_city_dialog.open()
	await settle()
	check(root.get_visible_rect().encloses(host.new_city_dialog.panel.get_global_rect()),"Main New City fits")
	check(root.get_visible_rect().encloses(host.new_city_dialog.start_button.get_global_rect()),"Main Start reachable")
	host.free()
	await process_frame
