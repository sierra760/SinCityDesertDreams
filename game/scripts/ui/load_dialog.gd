# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Load City: personal saves, newest first, followed by included cities.
class_name LoadDialog
extends Control

signal share_requested(path: String)
signal browse_requested
signal load_requested(path: String)
signal bundled_city_requested(path: String)
signal closed

var item_list: ItemList
var load_button: Button
var cancel_button: Button
var browse_button: Button
var share_button: Button
var empty_label: Label
var details_label: Label
var _saves: Array[Dictionary] = []
## The credit a city carries when no mayor name was chosen.
const DEFAULT_MAYOR := "Mayor"
var panel: PanelContainer
## Paths in the order of the list rows.
var paths: PackedStringArray = PackedStringArray()


func _init() -> void:
	name = "LoadDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var chrome := UIFactory.make_window_chrome("Load City")
	panel = chrome["root"]
	panel.name = "Panel"
	panel.set_meta("preferred_size", Vector2(520, 440))
	(chrome["close_button"] as Button).pressed.connect(close)
	var body: VBoxContainer = chrome["body"]
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list = ItemList.new()
	item_list.name = "Saves"
	item_list.add_theme_constant_override("v_separation",20)
	item_list.custom_minimum_size = Vector2(0, 112)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	item_list.item_activated.connect(func(_i: int) -> void: confirm())
	item_list.item_selected.connect(_show_details)
	body.add_child(item_list)
	details_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	details_label.name = "SelectedSaveDetails"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(details_label)
	empty_label = UIFactory.make_label("No saved cities yet. Start a New City, or Browse for a .sc2d file.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(empty_label)
	var row: HBoxContainer = chrome["actions"]
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	browse_button = UIFactory.make_button("Browse…", "Find a saved city in another folder")
	browse_button.pressed.connect(func(): browse_requested.emit())
	row.add_child(browse_button)
	share_button = UIFactory.make_button("Share…", "Share the selected saved city as a playable .sc2d file")
	share_button.name = "ShareSave"
	share_button.disabled = true
	share_button.pressed.connect(func() -> void:
		var path := selected_path()
		if not share_button.disabled and not path.is_empty(): share_requested.emit(path))
	row.add_child(share_button)
	cancel_button = UIFactory.make_button("Cancel")
	cancel_button.pressed.connect(close)
	row.add_child(cancel_button)
	load_button = UIFactory.make_primary_button("Load")
	load_button.pressed.connect(confirm)
	row.add_child(load_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -210
	panel.offset_right = 210
	panel.offset_top = -170
	panel.offset_bottom = 170
	add_child(panel)
	WindowDrag.enable(chrome["title_bar"], panel)


## Fill personal save headers and optionally append included-city entries.
func refresh(saves: Array[Dictionary], included: Array[Dictionary] = []) -> void:
	item_list.clear()
	_saves = saves.duplicate(true)
	for entry: Dictionary in included:
		var header := entry.duplicate(true)
		header["included_city"] = true
		_saves.append(header)
	details_label.text = ""
	details_label.hide()
	paths = PackedStringArray()
	for h: Dictionary in _saves:
		if bool(h.get("included_city", false)):
			item_list.add_item("%s — Included city" % String(h.get("name", "?")))
			item_list.set_item_tooltip(item_list.item_count - 1, "Start with an included city. Save a personal copy to keep your changes.")
			paths.append(String(h.get("path", "")))
			continue
		var year := int(h.get("year", 0))
		var text := "%s — %s — pop %s" % [String(h.get("name", "?")),
			("year %d" % year) if year > 0 else "", UIFactory.commafy(int(h.get("population", 0)))]
		if String(h.get("stage", SaveFormat.STAGE_PLAY)) == SaveFormat.STAGE_EDITING:
			text = "%s — unfounded map" % String(h.get("name", "?"))
		if bool(h.get("suspended_recovery", false)):
			text = "Recovered after the app closed · " + text
		elif bool(h.get("automatic_backup", false)):
			text = "Automatic backup · " + text
		item_list.add_item(text)
		item_list.set_item_tooltip(item_list.item_count - 1, "%s\nsaved %s" % [String(h.get("path", "")).get_file(), saved_text(h)])
		paths.append(String(h.get("path", "")))
	empty_label.visible = _saves.is_empty()
	load_button.disabled = true
	share_button.disabled = true
	if not _saves.is_empty():
		select(0)


func open(saves: Array[Dictionary], included: Array[Dictionary] = []) -> void:
	refresh(saves, included)
	visible = true
	UIFactory.contain_modal_focus(self, browse_button if _saves.is_empty() else item_list)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func select(index: int) -> void:
	if index >= 0 and index < item_list.item_count:
		item_list.select(index)
		_show_details(index)
		# Keep programmatically selected saves reachable in a long list.
		item_list.ensure_current_is_visible()


func selected_path() -> String:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return ""
	return paths[sel[0]]


func confirm() -> void:
	var path := selected_path()
	if path.is_empty():
		return
	var index := item_list.get_selected_items()[0]
	visible = false
	if bool(_saves[index].get("included_city", false)):
		bundled_city_requested.emit(path)
	else:
		load_requested.emit(path)
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		accept_event()


## When a save was written, in local time without seconds. Headers from the
## save list carry `saved_at`; others fall back to their stored date text.
static func saved_text(header: Dictionary) -> String:
	var saved_at: Variant = header.get("saved_at", null)
	if typeof(saved_at) in [TYPE_INT, TYPE_FLOAT] and int(saved_at) > 0:
		var bias := int(Time.get_time_zone_from_system().get("bias", 0))
		var local := Time.get_datetime_dict_from_unix_time(int(saved_at) + bias * 60)
		return "%04d-%02d-%02d %02d:%02d" % [local.year, local.month, local.day, local.hour, local.minute]
	return String(header.get("date_text", ""))


func _show_details(index: int) -> void:
	if index < 0 or index >= _saves.size(): return
	var header := _saves[index]
	share_button.disabled = bool(header.get("included_city",false))
	var filename := String(header.get("path", "")).get_file()
	if bool(header.get("included_city", false)):
		details_label.text = "Included city — make it your own, then save a personal copy.\nFile: %s" % filename
		details_label.show()
		load_button.disabled = false
		return
	var date := saved_text(header)
	var stage := "Unfounded map" if String(header.get("stage", SaveFormat.STAGE_PLAY)) == SaveFormat.STAGE_EDITING else "Founded city"
	var year := int(header.get("year", 0))
	var summary := stage + (" · Year %d" % year if year > 0 else "")
	summary += " · Population %s" % UIFactory.commafy(int(header.get("population", 0)))
	var mayor := String(header.get("mayor", ""))
	# The default credit "Mayor" says nothing; show only a chosen mayor name.
	var mayor_line := "" if mayor.is_empty() or mayor == DEFAULT_MAYOR else "Mayor: %s\n" % mayor
	details_label.text = "%sFile: %s\nSaved: %s\n%s" % [mayor_line, filename, date if not date.is_empty() else "date unavailable", summary]
	if bool(header.get("suspended_recovery", false)):
		details_label.text = "Recovered after the app closed — save under a new name to keep it.\n" + details_label.text
	elif bool(header.get("automatic_backup", false)):
		details_label.text = "Automatic backup — save under a new name to keep it.\n" + details_label.text
	details_label.show()
	load_button.disabled = false
