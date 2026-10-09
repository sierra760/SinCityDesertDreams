# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Industries window: the national trend, the city's assessed value and the
## eleven industry sectors with their demand, size, share and tax rate.
class_name IndustriesWindow
extends Control

signal closed

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _syncing := false
var _status_label: Label
var _phase_label: Label
var _value_label: Label
var _grid: GridContainer
var _sector_rows: Array[Array] = []    ## per sector: [name Label, demand Label, units Label, share Label, tax TouchNumberField]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Industries")
	_root = chrome["root"]
	# Wide enough for the sector table and its tax steppers at desktop size.
	_root.size = Vector2(780, 540)
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
	var economy: SimSystem = _sim.get_system(&"economy") if has_city else null
	_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()] if has_city else "No city loaded"
	var national := 0
	if economy != null:
		national = int(economy.call("national_population"))
	_phase_label.text = "National trend: %s (national population %s)" % [
		EconomySystem.phase_name(stats.economy_phase), UIFactory.commafy(national)]
	_value_label.text = "City value %s, aggregate industrial tax %d%%" % [
		UIFactory.format_amount(stats.city_value), stats.tax_industrial]
	var report: Array = []
	if economy != null:
		report = economy.call("sector_report")
	for i in _sector_rows.size():
		var row: Array = _sector_rows[i]
		var name_label: Label = row[0]
		var demand_label: Label = row[1]
		var units_label: Label = row[2]
		var share_label: Label = row[3]
		var spinner: TouchNumberField = row[4]
		var entry: Dictionary = report[i] if i < report.size() else {}
		var heavy := bool(entry.get("heavy", false))
		name_label.text = EconomySystem.sector_name(i) + (" (heavy)" if heavy else "")
		demand_label.text = str(int(entry.get("demand", 0)))
		units_label.text = UIFactory.commafy(int(entry.get("units", 0)))
		share_label.text = "%.1f%%" % (float(entry.get("share", 0.0)) * 100.0)
		spinner.value = stats.sector_taxes[i] if i < stats.sector_taxes.size() else 0
	_syncing = false


# ── Public helpers ───────────────────────────────────────────────────────

func set_sector_tax(index: int, rate: int) -> void:
	if index < 0 or index >= _sector_rows.size():
		return
	var row: Array = _sector_rows[index]
	var spinner: TouchNumberField = row[4]
	spinner.value = clampi(rate, 0, EconomyParams.SECTOR_TAX_MAX)


## "name | demand | units | share | tax" for one sector.
func sector_text(index: int) -> String:
	if index < 0 or index >= _sector_rows.size():
		return ""
	var row: Array = _sector_rows[index]
	var name_label: Label = row[0]
	var demand_label: Label = row[1]
	var units_label: Label = row[2]
	var share_label: Label = row[3]
	var spinner: TouchNumberField = row[4]
	return "%s | %s | %s | %s | %d" % [name_label.text, demand_label.text, units_label.text, share_label.text, int(spinner.value)]


func phase_text() -> String:
	return _phase_label.text


func value_text() -> String:
	return _value_label.text


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_phase_label = UIFactory.make_label("", UITheme.FONT_HEADER)
	_value_label = UIFactory.make_label("")
	_body.add_child(_status_label)
	_body.add_child(_phase_label)
	_body.add_child(_value_label)
	_body.add_child(UIFactory.make_section_header("Sectors"))
	_grid = UIFactory.ResponsiveTable.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	_grid.add_theme_constant_override("v_separation", 2)
	for header in ["Sector", "Demand", "Units", "Share", "Tax %"]:
		var h := UIFactory.make_label(header, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		if header != "Sector":
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(h)
	for i in EconomyParams.SECTOR_COUNT:
		var name_label := UIFactory.make_label(EconomySystem.sector_name(i))
		name_label.custom_minimum_size = Vector2(150, 0)
		var demand_label := _number_label()
		var units_label := _number_label()
		var share_label := _number_label()
		var spinner := TouchNumberField.new()
		spinner.min_value = 0
		spinner.max_value = EconomyParams.SECTOR_TAX_MAX
		spinner.step = 1
		# A one- or two-digit rate needs only a narrow value field.
		spinner.get_line_edit().custom_minimum_size.x = 48
		spinner.get_line_edit().size_flags_horizontal = Control.SIZE_FILL
		spinner.value_changed.connect(_on_tax_changed.bind(i))
		_grid.add_child(name_label)
		_grid.add_child(demand_label)
		_grid.add_child(units_label)
		_grid.add_child(share_label)
		_grid.add_child(spinner)
		_sector_rows.append([name_label, demand_label, units_label, share_label, spinner])
	_body.add_child(_grid)
	_body.add_child(UIFactory.make_label("Raising a sector's tax steers new industry toward the others. The city collects the share-weighted aggregate.",
		UITheme.FONT_SMALL, UITheme.TEXT_MUTED))


static func _number_label() -> Label:
	var l := UIFactory.make_label("0")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(60, 0)
	return l


func _on_tax_changed(value: float, index: int) -> void:
	if _syncing or _sim == null:
		return
	var taxes := _sim.stats.sector_taxes
	if index < 0 or index >= taxes.size():
		return
	taxes[index] = clampi(int(value), 0, EconomyParams.SECTOR_TAX_MAX)
	_sim.stats.sector_taxes = taxes
	var economy := _sim.get_system(&"economy")
	if economy != null and economy.has_method("sector_taxes_changed"):
		economy.call("sector_taxes_changed")
	refresh()
	BudgetWindow.refresh_other_windows(self)


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
