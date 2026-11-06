# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
const IOS_NO_KEYBOARD := {"os_name":"iOS", "hardware_keyboard":false}

# Guards against: Help naming "Cmd/Ctrl+S" on every platform, including touch
# devices that have no keyboard shortcut at all.
func test_save_shortcut_names_the_platform_key() -> void:
	var bindings := ControlBindings.new()
	var row := ""
	for entry: Array in HelpWindow.ROWS:
		if String(entry[0]) == "Save and recover": row = String(entry[1])
	check(not row.is_empty(),"the guide has a Save row")
	var mac := HelpWindow.fill_keys(row,bindings,false,"macOS")
	var windows := HelpWindow.fill_keys(row,bindings,false,"Windows")
	var touch := HelpWindow.fill_keys(row,bindings,true,"iOS")
	check(mac.contains("City menu (Cmd+S)."),mac)
	check(windows.contains("City menu (Ctrl+S)."),windows)
	check(touch.contains("City menu. Load City"),touch)
	for text: String in [mac,windows,touch]:
		check(not text.contains("Cmd/Ctrl"),text)
		check(not text.contains("{") and not text.contains("}"),"no placeholder left: "+text)

# Guards against: the Windows save-folder hint printing "~/AppData/Roaming/..."
# with Unix shorthand and forward slashes Explorer players cannot paste.
func test_windows_save_folder_uses_explorer_form() -> void:
	var env := {"APPDATA":"C:\\Users\\Ada\\AppData\\Roaming", "USERPROFILE":"C:\\Users\\Ada"}
	check_eq(SaveDialog.display_folder("C:/Users/Ada/AppData/Roaming/SinCityDesertDreams/saves","Windows",env),
		"%APPDATA%\\SinCityDesertDreams\\saves")
	check_eq(SaveDialog.display_folder("c:/users/ada/Documents/Cities","Windows",env),
		"%USERPROFILE%\\Documents\\Cities", "drive letters and names compare without case")
	check_eq(SaveDialog.display_folder("D:/Games/Saves","Windows",env), "D:\\Games\\Saves")
	check_eq(SaveDialog.display_folder("/Users/ada/Library/Application Support/SinCityDesertDreams/saves","macOS",{"HOME":"/Users/ada"}),
		"~/Library/Application Support/SinCityDesertDreams/saves")

# Guards against: shared-axis and current-value labels wider than the fixed
# margins being cut off (a one-month Population axis read "40,22").
func test_graph_margins_fit_their_labels() -> void:
	var canvas := GraphsWindow.GraphCanvas.new()
	root.add_child(canvas)
	canvas.size = Vector2(520, 260)
	var font := canvas.get_theme_default_font()
	for values: PackedInt32Array in [PackedInt32Array([40220]), PackedInt32Array([19860683, 19860912])]:
		var rows: Array[Dictionary] = [{"name": &"money", "label": "Funds", "values": values, "color": Color.RED}]
		canvas.set_series(rows, 120)
		var rect := canvas.plot_rect()
		for label: Array in canvas.axis_labels():
			var width := font.get_string_size(String(label[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			check(width <= rect.position.x - 4.0 - 2.0 + 0.5, "axis label %s fits left of the plot" % label[1])
		for label: Dictionary in canvas.endpoint_labels():
			var width := font.get_string_size(String(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
			check(width <= (label.rect as Rect2).size.x + 0.5, "current value %s fits right of the plot" % label.text)
			check((label.rect as Rect2).end.x <= canvas.size.x + 0.5, "current value stays inside the canvas")
	canvas.free()

# Guards against: an empty history drawing a bare 0-to-1 axis with "-" as if
# the city had been measured at zero.
func test_graph_without_readings_says_so() -> void:
	var canvas := GraphsWindow.GraphCanvas.new()
	canvas.size = Vector2(400, 240)
	var rows: Array[Dictionary] = [{"name": &"population", "label": "Population", "values": PackedInt32Array(), "color": Color.BLUE}]
	canvas.set_series(rows, 120)
	check(not canvas.has_readings())
	check(canvas.axis_labels().is_empty(), "no invented axis numbers")
	check_eq(canvas.plot_rect().position.x, GraphsWindow.GraphCanvas.PAD_LEFT)
	canvas.free()
	var window := GraphsWindow.new()
	root.add_child(window)
	window.refresh()
	check(window.legend_text().contains("no readings yet") or window.legend_text() == "No series selected", window.legend_text())
	check(not window.legend_text().contains(": -"), window.legend_text())
	window.free()
	await process_frame

# Guards against: Industries printing "City value $0" and zero units for a
# populated city that has not reached its first monthly economy update.
func test_industries_without_readings_says_so() -> void:
	check(IndustriesWindow._no_units([{"units": 0}, {"units": 0}]))
	check(IndustriesWindow._no_units([]))
	check(not IndustriesWindow._no_units([{"units": 0}, {"units": 368}]))

# Guards against: Windows AltGr (reported as Ctrl+Alt) + Shift + C opening
# secret codes instead of typing a letter in a name or search field.
func test_secret_code_chord_leaves_text_fields_alone() -> void:
	var edit := LineEdit.new()
	var text := TextEdit.new()
	var button := Button.new()
	check(GameHost._is_text_field(edit))
	check(GameHost._is_text_field(text))
	check(not GameHost._is_text_field(button))
	check(not GameHost._is_text_field(null))
	for node in [edit, text, button]: node.free()

# Guards against: the iOS save-folder hint showing a sandbox container path
# that the Files app never names.
func test_ios_save_folder_names_the_files_location() -> void:
	var docs := "/private/var/mobile/Containers/Data/Application/ABC/Documents"
	check_eq(SaveDialog.display_folder(docs + "/saves","iOS",{"user_dir":docs + "/","model":"iPhone17,1"}),
		"Files → On My iPhone → SC2D → saves")
	check_eq(SaveDialog.display_folder(docs + "/saves","iOS",{"user_dir":docs,"model":"iPad16,3"}),
		"Files → On My iPad → SC2D → saves")

# Guards against: iPad Help pointing at an iPhone-only Menu button and
# listing the iPhone drawer layout.
func test_help_speed_and_layout_rows_follow_phone_or_tablet() -> void:
	var bindings := ControlBindings.new()
	check(HelpWindow.shows_row("phone",true,true) and not HelpWindow.shows_row("phone",true,false))
	check(HelpWindow.shows_row("tablet",true,false) and not HelpWindow.shows_row("tablet",true,true))
	check(not HelpWindow.shows_row("phone",false,true) and not HelpWindow.shows_row("touch",false,false))
	var speed := ""
	for entry: Array in HelpWindow.ROWS:
		if String(entry[0]) == "Choose a speed" and entry.size() > 2 and String(entry[2]) == "touch": speed = String(entry[1])
		if String(entry[0]) == "iPhone layout": check_eq(String(entry[2]),"phone","the iPhone layout row is phone-only")
	check(HelpWindow.fill_keys(speed,bindings,true,"iOS",true).contains("from Menu → Speed."))
	check(HelpWindow.fill_keys(speed,bindings,true,"iOS",false).contains("from the Speed menu."))

# Guards against: casino rules and the big-bet confirmation telling iPhone and
# iPad players to press Enter, R, H or Escape.
func test_casino_text_without_a_keyboard_names_taps() -> void:
	check_eq(CasinoLines.confirm_stake(8000,8000,"Deal",false),"Bet $8,000 of the city's $8,000? Tap Deal again to confirm.")
	check(CasinoLines.confirm_stake(8000,8000,"Deal").contains("Press Enter or Deal again"))
	for kind: StringName in [&"blackjack", &"video_poker", &"trajectory", &"roulette"]:
		var limits := {"minimum": 10}
		var touch := CasinoTableOverlay.rules_text(kind, &"arcology_comstock", limits, false)
		for key_text: String in ["Keys:", "Enter", "Escape", "keys 1 to 5", "(A)"]:
			check(not touch.contains(key_text), "%s touch rules omit %s" % [kind, key_text])
		check(touch.contains("tap the button again"), "%s touch rules still explain confirmation" % kind)
		check(CasinoTableOverlay.rules_text(kind, &"arcology_comstock", limits).contains("Keys:"), "%s keyboard rules keep keys" % kind)

# Guards against: iPhone and iPad menus captioning items with keys ("Rotate
# [R]", Cmd+S) nobody can press without a hardware keyboard.
func test_menus_drop_key_captions_without_a_keyboard() -> void:
	var host := HostFixture.make_host(self, "platform-polish-menus")
	var menu := host.menu_bar
	menu.key_hint_environment = IOS_NO_KEYBOARD
	menu.set_bindings(host.controls)
	check(not menu.show_key_hints)
	var texts := _menu_texts(menu)
	check(texts.has("Rotate") and texts.has("Underground"), str(texts))
	for text: String in texts: check(not text.contains("["), "no key caption: " + text)
	var view: PopupMenu = menu.find_child("View", true, false)
	check_eq(view.get_theme_color("font_accelerator_color"), Color.TRANSPARENT, "Cmd/Ctrl accelerators are not drawn")
	menu.key_hint_environment = {"os_name":"iOS", "hardware_keyboard":true}
	menu.set_bindings(host.controls)
	check(_menu_texts(menu).has("Rotate [R]"), "an attached keyboard restores captions")
	check(not view.has_theme_color_override("font_accelerator_color"))
	host.free()
	await process_frame

func _menu_texts(menu: GameMenuBar) -> Array[String]:
	var out: Array[String] = []
	for popup: PopupMenu in menu.find_children("*","PopupMenu",true,false):
		for i in popup.item_count: out.append(popup.get_item_text(i))
	return out

# Guards against: phone players never seeing the city summary (rain, wind,
# water storage) that lives only in a tooltip, or alerts past the second line.
func test_phone_details_show_city_summary_and_every_alert() -> void:
	var host := HostFixture.make_host(self, "platform-polish-phone")
	host.begin_city(flat_city(),{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	root.size = Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	await HostFixture.settle(self, 10)
	var bar := host.status_bar
	bar.refresh(host.sim)
	check(bar.details_label != null, "phone Details has a city summary")
	if bar.details_label == null:
		host.free()
		return
	check(not bar.details_label.visible, "summary waits for Details")
	bar.set_details_open(true)
	bar.set_alerts(PackedStringArray(["Water shortage","Power shortage","Weak fire coverage","Traffic jams","Crime rising","Pollution high"]))
	await HostFixture.settle(self, 4)
	check(bar.details_label.visible and not bar.details_label.text.is_empty(), bar.details_label.text)
	check_eq(bar.alert_label.max_lines_visible, -1, "every alert line is readable in Details")
	check_eq(bar.message_label.max_lines_visible, -1, "the whole status message is readable in Details")
	bar.set_details_open(false)
	check_eq(bar.alert_label.max_lines_visible, 2)
	check_eq(bar.message_label.max_lines_visible, 1)
	check(not bar.details_label.visible)
	host.free()
	await process_frame
