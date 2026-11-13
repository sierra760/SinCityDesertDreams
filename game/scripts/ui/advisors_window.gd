# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Advisors window: the city advisors' current read-only assessment, most
## important first, with urgent problems in the warning color.
class_name AdvisorsWindow
extends Control

signal closed

const Briefing := preload("res://scripts/ui/advisor_briefing.gd")
const Cabinet := preload("res://scripts/content/advisor_cabinet.gd")
const People := preload("res://scripts/content/advisor_cast.gd")

const READINGS_NOTE := "Current city · latest readings"

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _advice_box: VBoxContainer
var _advice_count := 0
var _rows: Array[Dictionary] = []
var _selected := ""
var _buttons: Dictionary = {}
var _button_parts: Dictionary = {}
var _roster: VBoxContainer
var _picker: OptionButton
var _status: Label
var _note: Label
var _rule: HSeparator
var _compact := true
var _bound_city: City


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Advisors")
	_root = chrome["root"]
	_root.set_meta("preferred_size", Vector2(980,660))
	_body = chrome["body"]
	var close_button: Button = chrome["close_button"]
	close_button.pressed.connect(close)
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	WindowDrag.enable(chrome["title_bar"], _root)
	_build()
	_built = true
	_root.resized.connect(_layout)
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or WindowManager.host_owns_escape(self):
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


# ── Contract ─────────────────────────────────────────────────────────────

func bind(sim: Simulation) -> void:
	var city: City = null if sim == null else sim.city
	if city != _bound_city:
		_selected = ""
		_bound_city = city
	if _sim != null and _sim != sim:
		if _sim.month_ended.is_connected(_on_month_ended):
			_sim.month_ended.disconnect(_on_month_ended)
		if _sim.year_ended.is_connected(_on_year_ended):
			_sim.year_ended.disconnect(_on_year_ended)
	_sim = sim
	if sim != null:
		if not sim.month_ended.is_connected(_on_month_ended):
			sim.month_ended.connect(_on_month_ended)
		if not sim.year_ended.is_connected(_on_year_ended):
			sim.year_ended.connect(_on_year_ended)
	refresh()


func open() -> void:
	show()
	refresh()


func close() -> void:
	hide()
	closed.emit()


func refresh() -> void:
	if not _built:
		return
	var paper := _newspaper()
	var advice: Array = []
	if paper != null:
		advice = paper.call("advice")
	_advice_count = advice.size()
	_rows = Cabinet.assess(_sim.city if _has_city() else null,
		_sim.stats if _has_city() else null, advice, _sim.get_system(&"transport") if _has_city() else null)
	if _selected.is_empty(): _selected = String(_rows[0].id)
	var attention := 0
	for row: Dictionary in _rows:
		if row.attention: attention += 1
		_update_button(row)
	_status.text = "%d of 6 departments need attention" % attention if attention > 0 else _empty_status()
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var index := People.ORDER.find(row.id)
		_picker.set_item_text(index,"%s · %s" % [row.speaker.role,row.speaker.status])
		_picker.set_item_metadata(index,row.id)
		_picker.set_item_tooltip(index,"%s — %s" % [row.speaker.name,row.speaker.scope])
	_show_selected(false)


# ── Public helpers ───────────────────────────────────────────────────────

## Total current findings across the cabinet, regardless of selected department.
func advice_count() -> int:
	return _advice_count


## Every advisor line on display (titles, texts or the empty state), joined.
func advice_text() -> String:
	var lines := PackedStringArray()
	lines.append(_status.text)
	for label: Label in _advice_box.find_children("*", "Label", true, false):
		lines.append(label.text)
	return " ".join(lines)


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status = _wrapped("", UITheme.FONT_BODY, UITheme.TEXT_PRIMARY)
	_body.add_child(_status)
	_note = _wrapped(READINGS_NOTE, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(_note)
	_rule = HSeparator.new()
	_body.add_child(_rule)
	_picker = OptionButton.new()
	_picker.name = "AdvisorDepartmentPicker"
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_picker.custom_minimum_size = Vector2(0,44)
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_picker.accessibility_name = "Advisor department"
	for id: String in People.ORDER: _picker.add_item(String(People.CAST[id][1]))
	_picker.item_selected.connect(func(index: int) -> void: select_department(String(_picker.get_item_metadata(index))))
	_body.add_child(_picker)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN * 2)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster = VBoxContainer.new()
	_roster.name = "AdvisorRoster"
	_roster.add_theme_constant_override("separation", UITheme.VSEP)
	columns.add_child(_roster)
	var group := ButtonGroup.new()
	var selected_face := StyleBoxFlat.new()
	selected_face.bg_color = UITheme.ROW_ALT
	selected_face.border_color = UITheme.TITLE_BAR_DARK
	selected_face.set_border_width_all(1)
	selected_face.border_width_left = 4
	selected_face.set_corner_radius_all(UITheme.CORNER)
	for id: String in People.ORDER:
		var button := UIFactory.make_button("")
		button.name = "Advisor_" + id
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(248,80)
		button.add_theme_stylebox_override("pressed",selected_face)
		button.add_theme_stylebox_override("hover_pressed",selected_face)
		button.pressed.connect(select_department.bind(id))
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_" + side,8)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var portrait := Briefing.portrait_for(People.speaker(id,"neutral",0),48)
		row.add_child(portrait)
		var labels := VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.add_theme_constant_override("separation", 0)
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var role := _wrapped(String(People.CAST[id][1]), UITheme.FONT_SMALL, UITheme.HEADER)
		var name_label := _wrapped(String(People.CAST[id][0]), UITheme.FONT_SMALL, UITheme.TEXT_PRIMARY)
		var mood := _wrapped("Neutral", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		for label: Label in [role,name_label,mood]:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			labels.add_child(label)
		row.add_child(labels)
		inset.add_child(row)
		button.add_child(inset)
		_roster.add_child(button)
		_buttons[id] = button
		_button_parts[id] = {"portrait":portrait, "mood":mood}
	_advice_box = VBoxContainer.new()
	_advice_box.add_theme_constant_override("separation", UITheme.MARGIN)
	_advice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_advice_box)
	_body.add_child(columns)
	_roster.hide()
	_status.hide()
	_note.hide()
	_rule.hide()


func select_department(id: String) -> void:
	if not _buttons.has(id): return
	_selected = id
	_show_selected(true)


func _show_selected(reset_scroll: bool) -> void:
	_clear(_advice_box)
	for row: Dictionary in _rows:
		(_buttons[row.id] as Button).set_pressed_no_signal(row.id == _selected)
		if row.id == _selected: _advice_box.add_child(Briefing.make(row,_compact,_root.size.y < 420))
	for i in _picker.item_count:
		if _picker.get_item_metadata(i) == _selected: _picker.select(i)
	if reset_scroll:
		var chrome: Dictionary = _root.get_meta("window_chrome")
		(chrome.body_scroll as ScrollContainer).scroll_vertical = 0


func _update_button(row: Dictionary) -> void:
	var button := _buttons[row.id] as Button
	var parts: Dictionary = _button_parts[row.id]
	(parts.portrait as TextureRect).texture = load(String(row.speaker.portrait)) as Texture2D
	(parts.mood as Label).text = String(row.speaker.status) + (" · %d issue%s" % [row.issues.size(),"" if row.issues.size() == 1 else "s"] if not row.issues.is_empty() else "")
	(parts.mood as Label).add_theme_color_override("font_color",Briefing.mood_color(row.mood))
	button.tooltip_text = "%s — %s. %s" % [row.speaker.role,row.speaker.status,row.speaker.scope]
	button.accessibility_name = "%s, %s, %s" % [row.speaker.role,row.speaker.name,row.speaker.status]


func _layout() -> void:
	var compact := _root.size.x < 800 or _root.size.y < 540
	if compact == _compact: return
	var focus := get_viewport().gui_get_focus_owner()
	var transfer_focus := focus == _picker or (focus != null and _roster.is_ancestor_of(focus))
	_compact = compact
	_roster.visible = not compact
	_picker.visible = compact
	_status.visible = not compact
	_note.visible = not compact
	_rule.visible = not compact
	if transfer_focus:
		if compact: _picker.grab_focus.call_deferred()
		elif _buttons.has(_selected): (_buttons[_selected] as Button).grab_focus.call_deferred()
	if _built: _show_selected.call_deferred(false)


# ── Refreshing ───────────────────────────────────────────────────────────

func _has_city() -> bool:
	return _sim != null and _sim.city != null


func _newspaper() -> SimSystem:
	if not _has_city():
		return null
	return _sim.get_system(&"newspaper")


func _empty_status() -> String:
	if not _has_city():
		return "Load a city to hear from the advisors."
	if _sim.stats.population == 0:
		return "No residents yet. Advice will follow as the town develops."
	if _sim.stats.history.is_empty():
		return "No warnings so far. Monthly reports are still building up."
	return "No pressing problems detected. Keep an eye on Budget and the coverage maps."


static func _wrapped(text: String, font_size: int, color: Color) -> Label:
	var label := UIFactory.make_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(0, 0)
	return label


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
