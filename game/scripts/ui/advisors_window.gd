# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Advisors window: the city advisors' current read-only assessment, most
## important first, with urgent problems in the warning color.
class_name AdvisorsWindow
extends Control

signal closed

const READINGS_NOTE := "Current city · latest available readings"

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _advice_box: VBoxContainer
var _advice_count := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Advisors")
	_root = chrome["root"]
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
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


# ── Contract ─────────────────────────────────────────────────────────────

func bind(sim: Simulation) -> void:
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
	_clear(_advice_box)
	_advice_count = 0
	var paper := _newspaper()
	var advice: Array = []
	if paper != null:
		advice = paper.call("advice")
	if advice.is_empty():
		_advice_box.add_child(_wrapped(_empty_status(), UITheme.FONT_BODY, UITheme.TEXT_MUTED))
		return
	for entry in advice:
		var rec: Dictionary = entry
		var urgent := bool(rec.get("urgent", false))
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		item.add_child(_wrapped(String(rec.get("title", "")), UITheme.FONT_HEADER,
			UITheme.MONEY_NEGATIVE if urgent else UITheme.HEADER))
		item.add_child(_wrapped(String(rec.get("text", "")), UITheme.FONT_BODY, UITheme.TEXT_PRIMARY))
		_advice_box.add_child(item)
		_advice_count += 1


# ── Public helpers ───────────────────────────────────────────────────────

## Number of advisor entries shown; 0 for an empty state.
func advice_count() -> int:
	return _advice_count


## Every advisor line on display (titles, texts or the empty state), joined.
func advice_text() -> String:
	var lines := PackedStringArray()
	for label: Label in _advice_box.find_children("*", "Label", true, false):
		lines.append(label.text)
	return " ".join(lines)


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	var note := _wrapped(READINGS_NOTE, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(note)
	_body.add_child(HSeparator.new())
	_advice_box = VBoxContainer.new()
	_advice_box.add_theme_constant_override("separation", UITheme.MARGIN)
	_advice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_advice_box)


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
