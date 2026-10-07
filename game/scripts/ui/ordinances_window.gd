# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ordinances window: the city's policies in three groups, each with a
## switch, a description and its yearly cost or income, plus the totals.
class_name OrdinancesWindow
extends Control

signal closed
## A policy was switched on or off; tools it governs may change availability.
signal ordinance_changed(key: StringName, on: bool)

const GROUPS: Array[Array] = [
	[OrdinanceParams.GROUP_FINANCE, "Finance"],
	[OrdinanceParams.GROUP_SAFETY, "Safety and Health"],
	[OrdinanceParams.GROUP_CITY, "City"],
]

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _syncing := false
var _status_label: Label
var _totals_label: Label
var _group_boxes: Dictionary = {}    ## group -> VBoxContainer
var _rows: Dictionary = {}           ## key -> {box: CheckBox, amount: Label, description: Label}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Ordinances")
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
	_syncing = true
	var has_city := _sim != null and _sim.city != null
	var stats := _sim.stats if _sim != null else CityStats.new()
	var ordinances: SimSystem = _sim.get_system(&"ordinances") if has_city else null
	_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()] if has_city else "No city loaded"
	_ensure_rows(ordinances)
	var catalog: Array = []
	if ordinances != null:
		catalog = ordinances.call("catalog")
	for entry in catalog:
		var rec: Dictionary = entry
		var k := StringName(String(rec.get("key", "")))
		if not _rows.has(k):
			continue
		var row: Dictionary = _rows[k]
		var box: CheckBox = row["box"]
		var amount: Label = row["amount"]
		box.button_pressed = bool(rec.get("enabled", false))
		box.disabled = false
		_set_amount(amount, int(rec.get("estimated_yearly", 0)))
	if ordinances == null:
		for k: StringName in _rows:
			var row: Dictionary = _rows[k]
			var box: CheckBox = row["box"]
			box.button_pressed = bool(stats.ordinances.get(k, false))
			box.disabled = true
			var amount: Label = row["amount"]
			_set_amount(amount, 0)
	var net := stats.ordinance_income - stats.ordinance_cost
	_totals_label.text = "Estimated yearly income %s, cost %s, net %s, settled each January" % [
		UIFactory.format_amount(stats.ordinance_income), UIFactory.format_amount(stats.ordinance_cost),
		UIFactory.format_money(net)]
	_syncing = false


# ── Public helpers ───────────────────────────────────────────────────────

func set_ordinance(k: StringName, on: bool) -> void:
	if _rows.has(k):
		var row: Dictionary = _rows[k]
		var box: CheckBox = row["box"]
		box.button_pressed = on


func is_checked(k: StringName) -> bool:
	if not _rows.has(k):
		return false
	var row: Dictionary = _rows[k]
	var box: CheckBox = row["box"]
	return box.button_pressed


func amount_text(k: StringName) -> String:
	if not _rows.has(k):
		return ""
	var row: Dictionary = _rows[k]
	var amount: Label = row["amount"]
	return amount.text


func totals_text() -> String:
	return _totals_label.text


func row_count() -> int:
	return _rows.size()


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(_status_label)
	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN)
	_body.add_child(columns)
	for group in GROUPS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", UITheme.MARGIN_COMPACT)
		column.custom_minimum_size = Vector2(250, 0)
		column.add_child(UIFactory.make_section_header(String(group[1])))
		columns.add_child(column)
		_group_boxes[group[0]] = column
	_totals_label = UIFactory.make_label("Estimated yearly income $0, cost $0, net $0, settled each January", UITheme.FONT_HEADER)
	_totals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_totals_label.custom_minimum_size = Vector2(0, 0)
	_body.add_child(_totals_label)


## The rows follow the catalog; without a system the authored catalog order
## is used so the window still lists every policy.
func _ensure_rows(ordinances: SimSystem) -> void:
	if not _rows.is_empty():
		return
	var catalog: Array = []
	if ordinances != null:
		catalog = ordinances.call("catalog")
	else:
		for row in OrdinanceParams.CATALOG:
			catalog.append({"key": row[0], "group": row[1], "name": row[2], "description": row[3]})
	for entry in catalog:
		var rec: Dictionary = entry
		var k := StringName(String(rec.get("key", "")))
		var group := StringName(String(rec.get("group", "")))
		if not _group_boxes.has(group):
			continue
		var column: VBoxContainer = _group_boxes[group]
		var head := UIFactory.ResponsiveColumns.new()
		var box := CheckBox.new()
		box.custom_minimum_size.y = 44
		box.text = String(rec.get("name", String(k)))
		box.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.toggled.connect(_on_toggled.bind(k))
		head.add_child(box)
		var amount := UIFactory.make_label("$0", UITheme.FONT_SMALL, UITheme.MONEY_NEUTRAL)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.custom_minimum_size = Vector2(70, 0)
		head.add_child(amount)
		column.add_child(head)
		var description := UIFactory.make_label(String(rec.get("description", "")), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(240, 0)
		column.add_child(description)
		_rows[k] = {"box": box, "amount": amount, "description": description}


static func _set_amount(label: Label, yearly: int) -> void:
	label.text = UIFactory.format_money(yearly) + "/yr"
	var color := UITheme.MONEY_NEUTRAL
	if yearly > 0:
		color = UITheme.MONEY_POSITIVE
	elif yearly < 0:
		color = UITheme.MONEY_NEGATIVE
	label.add_theme_color_override("font_color", color)


func _on_toggled(on: bool, k: StringName) -> void:
	if _syncing or _sim == null or _sim.city == null:
		return
	var ordinances := _sim.get_system(&"ordinances")
	if ordinances == null:
		return
	ordinances.call("set_enabled", k, on)
	refresh()
	ordinance_changed.emit(k, on)


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
