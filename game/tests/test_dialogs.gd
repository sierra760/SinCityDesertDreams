# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Dialogs, panels and windows drive by method calls and report through
## signals: notice choices, new-city parameters and preview, save and load
## lists, the tile inspector, options and help.
extends "res://tests/test_case.gd"

var holder: Control


func before_each() -> void:
	holder = Control.new()
	root.add_child(holder)


func after_each() -> void:
	root.remove_child(holder)
	holder.free()


func test_notice_dialog_reports_the_choice() -> void:
	var d := NoticeDialog.new()
	holder.add_child(d)
	check(not d.is_open())
	var choices: Array[StringName] = []
	d.closed.connect(func(c: StringName) -> void: choices.append(c))
	d.show_notice("Title", "Body text", [["Yes", &"accept"], ["No", &"decline"]])
	check(d.is_open())
	check_eq(d.title_label.text, "Title")
	check_eq(d.body_label.text, "Body text")
	check_eq(d.choice_buttons.size(), 2)
	(d.choice_buttons[1] as Button).pressed.emit()
	check(not d.is_open())
	check_eq(choices, [&"decline"] as Array[StringName])
	d.dismiss()
	check_eq(choices.size(), 1, "closing twice emits once")
	d.show_notice("Sign", "Text", [["Place", &"submit"]], true, "Main Street")
	check(d.line_edit.visible)
	check_eq(d.prompt_text(), "Main Street")
	d.dismiss(&"submit")
	check_eq(choices[1], &"submit")


func test_new_city_dialog_params_preview_and_start() -> void:
	var d := NewCityDialog.new()
	d.terrain_transport_factory = preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport
	holder.add_child(d)
	d.open()
	check(d.is_open())
	check(not d.name_edit.text.is_empty(), "a name is rolled on open")
	var first := d.name_edit.text
	var changed := false
	for _i in 8:
		d.reroll_name()
		if d.name_edit.text != first:
			changed = true
	check(changed, "reroll picks other names")
	d.set_params({"name": "Dry Gulch", "difficulty": City.Difficulty.HARD, "founded_year": 2000,
		"hills": 30, "water": 10, "trees": 5, "coast": "west", "river": true, "seed": 99})
	var p := d.params()
	check_eq(p["name"], "Dry Gulch")
	check_eq(p["difficulty"], City.Difficulty.HARD)
	check_eq(p["founded_year"], 2000)
	check_eq(p["coast"], "west")
	check_eq(p["seed"], 99)
	var city := d.generate_preview()
	check(city != null)
	check_eq(city.name, "Dry Gulch")
	check_eq(city.founded_year, 2000)
	check_eq(city.funds, City.STARTING_FUNDS[City.Difficulty.HARD])
	check(d.preview_rect.texture != null, "preview drawn")
	check_eq(d.preview_rect.texture.get_width(), City.WIDTH)
	var got: Array = []
	d.started.connect(func(params: Dictionary, c: City) -> void: got.append([params, c]))
	d.start()
	check_eq(got.size(), 1)
	check_eq(got[0][1], city, "start uses the previewed city when settings are unchanged")
	check(not d.is_open())
	d.seed_edit.text = "desert"
	check_eq(d.seed_value(), "desert".hash(), "words hash to a seed")


## The dialog is narrower than 600 units, so its body labels wrap. Inline
## captions must stay wide enough for their word, or "Coast" stacks one
## letter per line and stretches its dropdown far past its 44-unit height.
func test_new_city_inline_captions_do_not_stretch_their_rows() -> void:
	var d := NewCityDialog.new()
	d.terrain_transport_factory = preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport
	holder.add_child(d)
	d.open()
	check_eq(d.coast_button.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "coast dropdown keeps its own height")
	var widths := {}
	for control: Control in [d.hills_slider, d.water_slider, d.trees_slider, d.coast_button]:
		var caption := control.get_parent().get_child(0) as Label
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var text_width := caption.get_theme_font("font").get_string_size(caption.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		check(caption.custom_minimum_size.x >= text_width, "%s fits on one line" % caption.text)
		check_eq(caption.get_minimum_size().y, caption.get_theme_font("font").get_height(
			caption.get_theme_font_size("font_size")), "%s is a single line" % caption.text)
		widths[caption.custom_minimum_size.x] = true
	check_eq(widths.size(), 1, "captions share one column width")
	d.close()


func test_save_and_load_dialogs() -> void:
	var s := SaveDialog.new()
	holder.add_child(s)
	var names: Array[String] = []
	s.save_requested.connect(func(n: String) -> void: names.append(n))
	s.open("My Town")
	check(s.is_open())
	s.name_edit.text = "  "
	s.confirm()
	check(s.is_open(), "empty names are refused")
	s.name_edit.text = "Round Trip: 2?"
	s.confirm()
	check_eq(names, ["Round Trip 2"] as Array[String])
	check(not s.is_open())
	var city := flat_city()
	city.name = "Listed"
	var dir := SaveFormat.default_dir()
	var path := dir.path_join("dialog-listing.sc2d")
	check_eq(SaveFormat.save(path, city, {"stats": {"population": 1234}}), OK)
	var l := LoadDialog.new()
	holder.add_child(l)
	var chosen: Array[String] = []
	l.load_requested.connect(func(p: String) -> void: chosen.append(p))
	l.open(SaveFormat.list_saves())
	check(l.is_open())
	check(l.item_list.item_count >= 1)
	var index := -1
	for i in l.paths.size():
		if l.paths[i] == path:
			index = i
	check(index >= 0, "the new save is listed")
	check(l.item_list.get_item_text(index).contains("Listed"))
	check(l.item_list.get_item_text(index).contains("1,234"))
	l.select(index)
	l.confirm()
	check_eq(chosen, [path] as Array[String])
	check(not l.is_open())
	l.open([] as Array[Dictionary])
	check(l.empty_label.visible)
	check(l.load_button.disabled)
	l.close()
	DirAccess.remove_absolute(path)


func test_query_panel_describes_a_tile() -> void:
	var city := flat_city()
	var sim := make_simulation(city)
	var b := Builder.new(city, sim.stats, sim)
	check(bool(b.apply(Tools.Kind.COAL_PLANT, Vector2i(20, 20))["ok"]))
	city.signs[Vector2i(30, 30)] = "Old Well"
	var q := QueryPanel.new()
	holder.add_child(q)
	var demolished: Array[Vector2i] = []
	q.demolish_requested.connect(func(t: Vector2i) -> void: demolished.append(t))
	q.show_tile(city, sim, Vector2i(21, 21))
	check(q.is_open())
	check_eq(q.tile, Vector2i(21, 21))
	check_eq(q.info["Building"], "Coal Power Plant")
	check_eq(q.info["Footprint"], "4×4 at 20, 20")
	check(q.info.has("Age"), "facility record shown")
	check(not q.demolish_button.disabled)
	q.demolish_button.pressed.emit()
	check_eq(demolished, [Vector2i(21, 21)] as Array[Vector2i])
	q.show_tile(city, sim, Vector2i(30, 30))
	check_eq(q.info["Building"], "Open ground")
	check_eq(q.info["Sign"], "Old Well")
	check_eq(q.info["Zone"], "Unzoned")
	check(q.demolish_button.disabled, "nothing to demolish on open ground")
	check(q.lines().size() >= 10)
	q.show_tile(city, sim, Vector2i(-1, 0))
	check_eq(q.info["Location"], "outside the city")
	q.close()
	check(not q.is_open())
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func test_options_window_round_trips_values() -> void:
	var o := OptionsWindow.new()
	holder.add_child(o)
	var changes: Array = []
	o.option_changed.connect(func(k: StringName, v: Variant) -> void: changes.append([k, v]))
	o.set_values({"ui_scale": 150, "fullscreen": true, "labels": true, "minimap": false, "vehicles": true,
		"zoom": 3, "disasters_enabled": false, "auto_budget": true})
	check(changes.is_empty(), "set_values does not emit")
	var v := o.values()
	check_eq(v["ui_scale"],150)
	check_eq(v["fullscreen"],true)
	check(not v.has("minimap") and not v.has("zoom") and not v.has("auto_budget"), "city actions live in their menus")
	(o.checks[&"fullscreen"] as CheckBox).button_pressed = false
	check_eq(changes.size(), 1)
	check_eq(changes[0][0], &"fullscreen")
	check_eq(changes[0][1], false)
	var closed := [0]
	o.closed.connect(func() -> void: closed[0] += 1)
	o.open()
	check(o.visible)
	o.close()
	check(not o.visible)
	check_eq(closed[0], 1)


func test_help_window_and_title_screen() -> void:
	var h := HelpWindow.new()
	holder.add_child(h)
	h.open()
	check(h.visible)
	check(h.body.get_child_count() > 0)
	h.close()
	check(not h.visible)
	var t := TitleScreen.new()
	holder.add_child(t)
	var fired: Array[String] = []
	t.new_city_requested.connect(func() -> void: fired.append("new"))
	t.load_requested.connect(func() -> void: fired.append("load"))
	t.import_requested.connect(func() -> void: fired.append("import"))
	t.quit_requested.connect(func() -> void: fired.append("quit"))
	t.new_button.pressed.emit()
	t.load_button.pressed.emit()
	t.import_button.pressed.emit()
	t.quit_button.pressed.emit()
	check_eq(fired, ["new", "load", "import", "quit"] as Array[String])


func test_menu_bar_actions_and_checks() -> void:
	var m := GameMenuBar.new()
	holder.add_child(m)
	var got: Array = []
	m.action_requested.connect(func(a: StringName, v: Variant) -> void: got.append([a, v]))
	check(m.has_action(&"city_new"))
	check(m.has_action(&"disaster", &"fire"))
	check(m.has_action(&"window", "budget"))
	m.press(&"city_new")
	check_eq(got[0][0], &"city_new")
	m.press(&"labels")
	check(m.is_checked(&"labels"), "check items toggle on press")
	check_eq(got[1][1], true)
	m.press(&"labels")
	check(not m.is_checked(&"labels"))
	m.set_checked(&"speed", true, GameClock.Speed.FAST)
	check(m.is_checked(&"speed", GameClock.Speed.FAST))
	check(not m.is_checked(&"speed", GameClock.Speed.PAUSED))
	m.press(&"overlay", &"power")
	check(m.is_checked(&"overlay", &"power"))
	check(not m.is_checked(&"overlay", &""))
	check_eq(got[got.size() - 1][1], &"power")
	for kind in DisasterParams.KINDS:
		check(m.has_action(&"disaster", kind), "menu lists %s" % kind)
