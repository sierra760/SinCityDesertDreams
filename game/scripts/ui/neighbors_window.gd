# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Neighbors window: the four towns beyond the map edges, arranged around a
## compass with their size, links to this city and this year's trade.
class_name NeighborsWindow
extends Control

signal closed

const EDGE_TITLES: Array[String] = ["North", "East", "South", "West"]
## Grid slot (column, row) of each edge in the three-by-three layout.
const EDGE_SLOTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)]

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _status_label: Label
var _compass_label: Label
var _cards: Array[Dictionary] = []    ## per edge: {name, population, links, trade}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Neighbors")
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
	var has_city := _sim != null and _sim.city != null
	var neighbors: SimSystem = _sim.get_system(&"neighbors") if has_city else null
	if has_city:
		_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()]
		_compass_label.text = "%s\npopulation %s" % [_sim.city.name, UIFactory.commafy(_sim.stats.total_population())]
	else:
		_status_label.text = "No city loaded"
		_compass_label.text = "No city"
	var report: Array = []
	if neighbors != null:
		report = neighbors.call("neighbor_report")
	for edge in _cards.size():
		var card: Dictionary = _cards[edge]
		var name_label: Label = card["name"]
		var population_label: Label = card["population"]
		var links_label: Label = card["links"]
		var trade_label: Label = card["trade"]
		var rec: Dictionary = report[edge] if edge < report.size() else {}
		if rec.is_empty():
			name_label.text = "Unknown"
			population_label.text = "Population -"
			links_label.text = "No links"
			trade_label.text = "Trade this year $0"
			continue
		name_label.text = String(rec.get("name", "Unknown"))
		population_label.text = "Population " + UIFactory.commafy(int(rec.get("population", 0)))
		links_label.text = _links_text(rec.get("connected", {}))
		var trade := int(rec.get("trade", 0))
		trade_label.text = "Trade this year " + UIFactory.format_money(trade)
		trade_label.add_theme_color_override("font_color",
			UITheme.MONEY_POSITIVE if trade > 0 else (UITheme.MONEY_NEGATIVE if trade < 0 else UITheme.MONEY_NEUTRAL))


# ── Public helpers ───────────────────────────────────────────────────────

## "name | population | links | trade" for one edge (0 north .. 3 west).
func card_text(edge: int) -> String:
	if edge < 0 or edge >= _cards.size():
		return ""
	var card: Dictionary = _cards[edge]
	var name_label: Label = card["name"]
	var population_label: Label = card["population"]
	var links_label: Label = card["links"]
	var trade_label: Label = card["trade"]
	return "%s | %s | %s | %s" % [name_label.text, population_label.text, links_label.text, trade_label.text]


func compass_text() -> String:
	return _compass_label.text


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(_status_label)
	var grid := UIFactory.ResponsiveTileGrid.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	grid.add_theme_constant_override("v_separation", UITheme.MARGIN)
	var slots: Array = []
	for _i in 9:
		slots.append(null)
	for edge in EDGE_SLOTS.size():
		var slot := EDGE_SLOTS[edge]
		slots[slot.y * 3 + slot.x] = _make_card(edge)
	_compass_label = UIFactory.make_label("No city", UITheme.FONT_BODY, UITheme.TITLE_BAR_DARK)
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var compass := VBoxContainer.new()
	compass.alignment = BoxContainer.ALIGNMENT_CENTER
	var rose := UIFactory.make_label("N\nW + E\nS", UITheme.FONT_HEADER, UITheme.ACCENT_BRASS)
	rose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass.add_child(rose)
	compass.add_child(_compass_label)
	slots[4] = compass
	for slot in slots:
		if slot == null:
			var filler := Control.new()
			filler.custom_minimum_size = Vector2(150, 40)
			grid.add_child(filler)
		else:
			grid.add_child(slot)
	_body.add_child(grid)


func _make_card(edge: int) -> PanelContainer:
	var panel := UIFactory.make_panel()
	panel.custom_minimum_size = Vector2(170, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UIFactory.make_label(EDGE_TITLES[edge], UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	var name_label := UIFactory.make_label("Unknown", UITheme.FONT_HEADER, UITheme.HEADER)
	var population_label := UIFactory.make_label("Population -")
	var links_label := UIFactory.make_label("No links", UITheme.FONT_SMALL)
	var trade_label := UIFactory.make_label("Trade this year $0", UITheme.FONT_SMALL, UITheme.MONEY_NEUTRAL)
	box.add_child(name_label)
	box.add_child(population_label)
	box.add_child(links_label)
	box.add_child(trade_label)
	panel.add_child(box)
	_cards.append({"name": name_label, "population": population_label, "links": links_label, "trade": trade_label})
	return panel


static func _links_text(connected: Variant) -> String:
	if typeof(connected) != TYPE_DICTIONARY:
		return "No links"
	var flags: Dictionary = connected
	var names: Array[String] = []
	for entry: Array in [["road", "Road"], ["rail", "Rail"], ["power", "Power"], ["water", "Water"]]:
		if bool(flags.get(entry[0], false)):
			names.append(String(entry[1]))
	return "Links: " + ", ".join(names) if not names.is_empty() else "No links"


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
