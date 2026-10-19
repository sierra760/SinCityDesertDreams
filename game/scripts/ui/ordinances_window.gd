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
	[OrdinanceParams.GROUP_SAFETY, "Safety"],
	[OrdinanceParams.GROUP_CITY, "City"],
]

var _pages: ReportPages
var _enacted_only: CheckBox
var _empty: Label
var _expanded: StringName = &""
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
	_root.size = Vector2(600, 510)
	_root.set_meta("preferred_size", Vector2(600, 510))
	_pages = ReportPages.new(chrome, ["Finance", "Safety", "City"])
	_pages.tabs.tab_changed.connect(func(_index: int) -> void: _filter_rows())
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
	_status_label.text = _sim.date_text() if has_city else "No city loaded"
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
	var enabled := 0
	for row: Dictionary in _rows.values():
		if (row.box as CheckBox).button_pressed: enabled += 1
	var net := stats.ordinance_income - stats.ordinance_cost
	_totals_label.text = "All enacted (%d): %s / year" % [enabled, UIFactory.format_money(net)]
	_totals_label.tooltip_text = "Income %s · cost %s / year" % [UIFactory.format_amount(stats.ordinance_income), UIFactory.format_amount(stats.ordinance_cost)]
	_syncing = false
	_filter_rows()


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

func select_group(group: String) -> void:
	for entry in GROUPS:
		if group == String(entry[0]) or group == String(entry[1]): _pages.select(String(entry[1]))
	_filter_rows()

func selected_group() -> String:
	return _pages.selected()

func set_enacted_only(on: bool) -> void:
	_enacted_only.set_pressed_no_signal(on)
	_filter_rows()

func visible_policy_count() -> int:
	var count := 0
	for row: Dictionary in _rows.values():
		if (row.card as Control).is_visible_in_tree(): count += 1
	return count

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages.header.add_child(_status_label)
	_enacted_only = CheckBox.new()
	_enacted_only.text = "Enacted only"
	_enacted_only.custom_minimum_size.y = 44
	_enacted_only.toggled.connect(func(_on: bool) -> void: _filter_rows())
	_pages.header.add_child(_enacted_only)
	for i in GROUPS.size(): _group_boxes[GROUPS[i][0]] = _pages.page(i)
	_empty = UIFactory.make_label("No enacted policies in this category.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_empty)
	var clear_filter := UIFactory.make_button("Show all policies", "Clear the enacted-only filter")
	clear_filter.name = "ClearPolicyFilter"
	clear_filter.pressed.connect(func() -> void: set_enacted_only(false))
	_body.add_child(clear_filter)
	_totals_label = UIFactory.make_label("", UITheme.FONT_SMALL)
	_totals_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_totals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_totals_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chrome: Dictionary = _root.get_meta("window_chrome")
	chrome.actions.add_child(_totals_label)

func _filter_rows() -> void:
	if _enacted_only == null or _empty == null: return
	var focused := get_viewport().gui_get_focus_owner()
	for row: Dictionary in _rows.values():
		var show_row := not _enacted_only.button_pressed or (row.box as CheckBox).button_pressed
		if not show_row and focused != null and (row.card as Node).is_ancestor_of(focused): _enacted_only.grab_focus()
		(row.card as Control).visible = show_row
	var empty := _enacted_only.button_pressed and visible_policy_count() == 0
	_empty.visible = empty
	var clear_filter := _body.get_node("ClearPolicyFilter") as Control
	if not empty and clear_filter.has_focus(): _enacted_only.grab_focus()
	clear_filter.visible = empty

func _show_description(on: bool, key: StringName) -> void:
	_expanded = key if on else &""
	for k: StringName in _rows:
		var row: Dictionary = _rows[k]
		(row.description as Control).visible = k == _expanded
		(row.details as Button).set_pressed_no_signal(k == _expanded)
		(row.details as Button).text = "▾" if k == _expanded else "▸"


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
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		column.add_child(card)
		var head := HBoxContainer.new()
		card.add_child(head)
		var policy_name := String(rec.get("name", String(k)))
		var box := CheckBox.new()
		box.custom_minimum_size = Vector2(44, 44)
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.accessibility_name = policy_name
		box.tooltip_text = "Enact " + policy_name
		box.toggled.connect(_on_toggled.bind(k))
		head.add_child(box)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(text)
		var title := UIFactory.make_label(policy_name, UITheme.FONT_BODY)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(title)
		var amount := UIFactory.make_label("$0", UITheme.FONT_SMALL, UITheme.MONEY_NEUTRAL)
		text.add_child(amount)
		var brief := UIFactory.make_label(_effect(k), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(brief)
		var details := UIFactory.make_button("▸", "Details for " + policy_name)
		details.accessibility_name = "Details for " + policy_name
		details.custom_minimum_size = Vector2(44, 44)
		details.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		details.toggle_mode = true
		details.toggled.connect(_show_description.bind(k))
		head.add_child(details)
		var description := UIFactory.make_label(String(rec.get("description", "")), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.hide()
		card.add_child(description)
		card.add_child(HSeparator.new())
		_rows[k] = {"box": box, "amount": amount, "description": description, "details": details, "card": card, "title": title}

static func _effect(key: StringName) -> String:
	return String({
		&"sales_tax": "Raises income; reduces commercial demand.",
		&"income_tax": "Raises income; reduces residential demand.",
		&"parking_fines": "Raises income from parking enforcement.",
		&"legalized_gambling": "Raises income and local crime.",
		&"tourist_advertising": "Attracts tourists and supports shops.",
		&"business_advertising": "Encourages industrial demand.",
		&"volunteer_fire": "Extends fire coverage.",
		&"public_smoking_ban": "Improves public health.",
		&"free_clinics": "Improves life expectancy.",
		&"junior_sports": "Supports health and education.",
		&"anti_drug_campaign": "Improves health and reduces crime.",
		&"casino_safety": "Reduces casino crime; applies next visitor period.",
		&"neighborhood_watch": "Reduces neighborhood crime.",
		&"cpr_training": "Improves emergency survival.",
		&"pollution_controls": "Reduces pollution; slows industrial demand.",
		&"energy_conservation": "Reduces power consumption.",
		&"nuclear_free_zone": "Prevents new nuclear plants.",
		&"homeless_shelters": "Supports households and shops.",
		&"pro_reading_campaign": "Improves education.",
		&"tree_planting": "Reduces pollution and supports housing demand.",
		&"annual_carnival": "Boosts April visitors when announced in March.",
	}.get(key, ""))



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
	# An open Budget shows the ordinance income and costs.
	BudgetWindow.refresh_other_windows(self)


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
