# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Budget window: tax rates, service funding, the year's books, the bond
## market and the auto-budget switch. It also serves as the January review;
## the host finishes the review when this window emits `closed`.
class_name BudgetWindow
extends Control

signal closed

const TAX_MAX := 20
const BOND_STEP := 1000

const SERVICE_FUNDING: Array[StringName] = [&"police", &"fire", &"health", &"schools", &"colleges"]
const TRANSPORT_FUNDING: Array[StringName] = [&"roads", &"highways", &"bridges", &"rail", &"subway", &"tunnels"]
const FUNDING_LABELS := {
	&"police": "Police", &"fire": "Fire", &"health": "Health", &"schools": "Schools",
	&"colleges": "Colleges", &"roads": "Roads", &"highways": "Highways", &"bridges": "Bridges",
	&"rail": "Rail", &"subway": "Subway", &"tunnels": "Tunnels",
}
## Ledger accounts in display order: key, label.
const ACCOUNTS: Array[Array] = [
	[&"taxes_residential", "Residential taxes"],
	[&"taxes_commercial", "Commercial taxes"],
	[&"taxes_industrial", "Industrial taxes"],
	[&"transit_fares", "Transit fares"],
	[&"ordinance_income", "Ordinance income"],
	[&"neighbor_trade", "Neighbor trade"],
	[&"ordinance_cost", "Ordinance costs"],
	[&"police", "Police"],
	[&"fire", "Fire"],
	[&"health", "Health"],
	[&"education", "Education"],
	[&"transport", "Transportation"],
	[&"bond_interest", "Bond interest"],
	[&"other", "Other"],
]

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _syncing := false

var _status_label: Label
var _funds_label: Label
var _review_label: Label
var _tax_spinners: Dictionary = {}       ## kind -> TouchNumberField
var _funding_sliders: Dictionary = {}    ## service -> HSlider
var _funding_values: Dictionary = {}     ## service -> Label
var _ledger_rows: Dictionary = {}        ## account -> [year_to_date Label, estimate Label]
var _totals_label: Label
var _condition_label: Label
var _last_year_label: Label
var _bond_rows: VBoxContainer
var _debt_label: Label
var _bond_amount: TouchNumberField
var _quote_label: Label
var _issue_button: Button
var _repay_button: Button
var _auto_budget: CheckBox
var _actions: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Budget")
	_root = chrome["root"]
	_body = chrome["body"]
	_actions = chrome["actions"]
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
	if not has_city:
		_status_label.text = "No city loaded"
		_funds_label.text = "Treasury: $0"
		_review_label.visible = false
	else:
		_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()]
		_funds_label.text = "Treasury: " + UIFactory.format_signed_amount(_sim.city.funds)
		_review_label.visible = _sim.budget_review_pending
		_review_label.text = "Year-end budget review for %d. The city is paused; adjust taxes and funding, then press Done to continue." % _sim.clock.year()
	var stats := _sim.stats if _sim != null else CityStats.new()
	_tax_spinners[&"residential"].value = stats.tax_residential
	_tax_spinners[&"commercial"].value = stats.tax_commercial
	_tax_spinners[&"industrial"].value = stats.tax_industrial
	for service: StringName in _funding_sliders:
		var pct := stats.funding_of(service)
		var slider: HSlider = _funding_sliders[service]
		slider.value = pct
		var value_label: Label = _funding_values[service]
		value_label.text = "%d%%" % pct
	_auto_budget.button_pressed = stats.auto_budget
	_condition_label.text = condition_text(_sim)
	_refresh_ledger(stats)
	_refresh_bonds(stats)
	_syncing = false


# ── Public helpers ───────────────────────────────────────────────────────

## Network wear, losses and last year's transit riders, for the
## Transportation section. Underfunded networks wear toward their next loss.
static func condition_text(sim: Simulation) -> String:
	if sim == null or sim.city == null:
		return ""
	var lines: PackedStringArray = []
	var wear := sim.get_system(&"wear")
	if wear != null and wear.has_method("wear_percent"):
		var counts: Dictionary = wear.call("network_counts")
		var lost: Dictionary = wear.call("losses")
		var parts: PackedStringArray = []
		for category: StringName in TRANSPORT_FUNDING:
			if int(counts.get(category, 0)) <= 0 and int(lost.get(category, 0)) <= 0:
				continue
			var text := "%s %d%% worn" % [String(FUNDING_LABELS.get(category, String(category))),
				int(wear.call("wear_percent", category))]
			if int(lost.get(category, 0)) > 0:
				text += ", %s lost" % UIFactory.commafy(int(lost[category]))
			parts.append(text)
		lines.append("Condition: " + ("; ".join(parts) if not parts.is_empty() else "no networks built yet"))
	var history := sim.stats.history
	var riders: PackedStringArray = []
	for entry: Array in [[&"riders_bus", "bus"], [&"riders_rail", "rail"], [&"riders_subway", "subway"]]:
		var series: PackedInt32Array = history.get(entry[0], PackedInt32Array())
		if not series.is_empty():
			riders.append("%s %s" % [entry[1], UIFactory.commafy(series[series.size() - 1])])
	if not riders.is_empty():
		lines.append("Transit riders last year: " + ", ".join(riders))
	return "\n".join(lines)


func set_tax(kind: StringName, rate: int) -> void:
	if _tax_spinners.has(kind):
		var spinner: TouchNumberField = _tax_spinners[kind]
		spinner.value = clampi(rate, 0, TAX_MAX)


func set_funding(service: StringName, pct: int) -> void:
	if _funding_sliders.has(service):
		var slider: HSlider = _funding_sliders[service]
		slider.value = clampi(pct, 0, 100)


func set_bond_amount(amount: int) -> void:
	_bond_amount.value = amount


func issue_bond() -> bool:
	var budget := _budget()
	if budget == null:
		return false
	var ok: bool = budget.call("issue_bond", int(_bond_amount.value))
	if ok and _sim != null:
		_sim.adjust_funds(0)
	refresh()
	return ok


func repay_oldest() -> bool:
	var budget := _budget()
	if budget == null:
		return false
	var ok: bool = budget.call("repay_bond", 0)
	if ok and _sim != null:
		_sim.adjust_funds(0)
	refresh()
	return ok


func set_auto_budget(on: bool) -> void:
	_auto_budget.button_pressed = on


## "Year to date | Year-end estimate" text of one ledger row, empty for unknown accounts.
func ledger_text(account: StringName) -> String:
	if not _ledger_rows.has(account):
		return ""
	var pair: Array = _ledger_rows[account]
	var ytd: Label = pair[0]
	var est: Label = pair[1]
	return "%s | %s" % [ytd.text, est.text]


func quote_text() -> String:
	return _quote_label.text


func funds_text() -> String:
	return _funds_label.text


func totals_text() -> String:
	return _totals_label.text


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_funds_label = UIFactory.make_label("Treasury: $0", UITheme.FONT_HEADER, UITheme.MONEY_POSITIVE)
	_review_label = UIFactory.make_label("", UITheme.FONT_BODY, UITheme.ACCENT_BRASS)
	_review_label.visible = false
	_review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_label.custom_minimum_size = Vector2(0, 0)
	_body.add_child(_status_label)
	_body.add_child(_funds_label)
	_body.add_child(_review_label)

	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN * 2)
	_body.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UITheme.VSEP)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	_build_taxes(left)
	_build_funding(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UITheme.VSEP)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_build_ledger(right)
	_build_bonds(right)

	var bottom := _actions
	_auto_budget = CheckBox.new()
	_auto_budget.text = "Auto budget"
	_auto_budget.tooltip_text = "Skip the January review and keep the current taxes and funding"
	_auto_budget.custom_minimum_size.y = 44
	_auto_budget.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_auto_budget.toggled.connect(_on_auto_budget_toggled)
	_auto_budget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_auto_budget)
	var done := UIFactory.make_button("Done", "Close the budget")
	done.pressed.connect(close)
	bottom.add_child(done)


func _build_taxes(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Tax rates"))
	var grid := UIFactory.ResponsiveTable.new()
	grid.columns = 2
	grid.has_headers = false
	grid.headings = ["", "Rate"]
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	for entry: Array in [[&"residential", "Residential"], [&"commercial", "Commercial"], [&"industrial", "Industrial"]]:
		var kind: StringName = entry[0]
		grid.add_child(UIFactory.make_label(String(entry[1]) + " %"))
		var spinner := TouchNumberField.new()
		spinner.min_value = 0
		spinner.max_value = TAX_MAX
		spinner.step = 1
		spinner.value_changed.connect(_on_tax_changed.bind(kind))
		grid.add_child(spinner)
		_tax_spinners[kind] = spinner
	parent.add_child(grid)


func _build_funding(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Services"))
	parent.add_child(_funding_grid(SERVICE_FUNDING))
	parent.add_child(UIFactory.make_section_header("Transportation"))
	parent.add_child(_funding_grid(TRANSPORT_FUNDING))
	_condition_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_condition_label)


func _funding_grid(services: Array[StringName]) -> GridContainer:
	var grid := UIFactory.ResponsiveTable.new()
	grid.columns = 3
	grid.has_headers = false
	grid.headings = ["", "Funding", "Value"]
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	for service in services:
		grid.add_child(UIFactory.make_label(String(FUNDING_LABELS.get(service, String(service)))))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(140,44)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_funding_changed.bind(service))
		grid.add_child(slider)
		var value_label := UIFactory.make_label("100%")
		value_label.custom_minimum_size = Vector2(44, 0)
		grid.add_child(value_label)
		_funding_sliders[service] = slider
		_funding_values[service] = value_label
	return grid


func _build_ledger(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Books"))
	var grid := UIFactory.ResponsiveTable.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	grid.add_child(UIFactory.make_label("Account", UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	grid.add_child(_amount_label("Year to date", UITheme.TEXT_MUTED))
	grid.add_child(_amount_label("Year-end estimate", UITheme.TEXT_MUTED))
	for entry in ACCOUNTS:
		var account: StringName = entry[0]
		grid.add_child(UIFactory.make_label(String(entry[1])))
		var ytd := _amount_label("$0")
		var est := _amount_label("$0")
		grid.add_child(ytd)
		grid.add_child(est)
		_ledger_rows[account] = [ytd, est]
	parent.add_child(grid)
	_totals_label = UIFactory.make_label("Income $0, expenses $0, net $0", UITheme.FONT_BODY)
	_last_year_label = UIFactory.make_label("Last year: no books yet", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	parent.add_child(_totals_label)
	parent.add_child(_last_year_label)


func _build_bonds(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Bonds"))
	_bond_rows = VBoxContainer.new()
	_bond_rows.add_theme_constant_override("separation", 2)
	parent.add_child(_bond_rows)
	_debt_label = UIFactory.make_label("Total debt $0", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	parent.add_child(_debt_label)
	var row := UIFactory.WrappingActions.new()
	row.add_theme_constant_override("separation", UITheme.MARGIN_COMPACT)
	row.add_child(UIFactory.make_label("Amount"))
	_bond_amount = TouchNumberField.new()
	_bond_amount.min_value = BudgetParams.BOND_MIN
	_bond_amount.max_value = BudgetParams.BOND_MAX
	_bond_amount.step = BOND_STEP
	_bond_amount.value = BudgetParams.BOND_DEFAULT
	_bond_amount.value_changed.connect(_on_bond_amount_changed)
	row.add_child(_bond_amount)
	_issue_button = UIFactory.make_button("Issue", "Borrow at the quoted rate")
	_issue_button.pressed.connect(func() -> void: issue_bond())
	row.add_child(_issue_button)
	_repay_button = UIFactory.make_button("Repay oldest", "Pay off the oldest bond in full")
	_repay_button.pressed.connect(func() -> void: repay_oldest())
	row.add_child(_repay_button)
	parent.add_child(row)
	_quote_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	parent.add_child(_quote_label)


static func _amount_label(text: String, color := UITheme.TEXT_PRIMARY) -> Label:
	var l := UIFactory.make_label(text, UITheme.FONT_BODY, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(90, 0)
	return l


# ── Refreshing ───────────────────────────────────────────────────────────

func _budget() -> SimSystem:
	if _sim == null or _sim.city == null:
		return null
	return _sim.get_system(&"budget")


func _refresh_ledger(stats: CityStats) -> void:
	var budget := _budget()
	var estimate: Dictionary = {}
	var summary: Dictionary = {}
	if budget != null:
		estimate = budget.call("estimated_ledger")
		summary = budget.call("review_summary")
	for account: StringName in _ledger_rows:
		var pair: Array = _ledger_rows[account]
		var ytd: Label = pair[0]
		var est: Label = pair[1]
		var expense := account in BudgetParams.EXPENSE_KEYS
		_set_amount(ytd, int(stats.ledger.get(account, 0)), expense)
		_set_amount(est, int(estimate.get(account, 0)), expense)
	var income := int(summary.get("estimated_income", 0))
	var expenses := int(summary.get("estimated_expenses", 0))
	_totals_label.text = "Estimated income %s, expenses %s, net %s" % [
		UIFactory.format_signed_amount(income), UIFactory.format_signed_amount(expenses), UIFactory.format_money(income - expenses)]
	if summary.is_empty() or int(summary.get("settled_year", -1)) < 0 or stats.last_year_ledger.is_empty():
		_last_year_label.text = "Last year: no books yet"
	else:
		_last_year_label.text = "Last year: income %s, expenses %s, net %s" % [
			UIFactory.format_signed_amount(int(summary.get("income", 0))),
			UIFactory.format_signed_amount(int(summary.get("expenses", 0))),
			UIFactory.format_money(int(summary.get("net", 0)))]


## Show one ledger amount with its sign. Colour follows the effect on the
## treasury: income and refunds are positive, spending and net imports negative.
static func _set_amount(label: Label, dollars: int, expense: bool) -> void:
	label.text = UIFactory.format_signed_amount(dollars)
	var effect := -dollars if expense else dollars
	var color := UITheme.MONEY_NEUTRAL
	if effect > 0:
		color = UITheme.MONEY_POSITIVE
	elif effect < 0:
		color = UITheme.MONEY_NEGATIVE
	label.add_theme_color_override("font_color", color)


func _refresh_bonds(stats: CityStats) -> void:
	for child in _bond_rows.get_children():
		_bond_rows.remove_child(child)
		child.queue_free()
	if stats.bonds.is_empty():
		_bond_rows.add_child(UIFactory.make_label("No bonds outstanding", UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	for i in stats.bonds.size():
		var bond: Dictionary = stats.bonds[i]
		var line := "%d. %s at %d%%, issued %d" % [i + 1,
			UIFactory.format_amount(int(bond.get("principal", 0))), int(bond.get("rate", 0)),
			int(bond.get("issued_year", 0))]
		_bond_rows.add_child(UIFactory.make_label(line, UITheme.FONT_SMALL))
	var budget := _budget()
	var debt := 0
	if budget != null:
		debt = int(budget.call("total_debt"))
	_debt_label.text = "Total debt %s, %d of %d bonds" % [UIFactory.format_amount(debt), stats.bonds.size(), BudgetParams.MAX_BONDS]
	_refresh_quote()
	var can_repay := budget != null and not stats.bonds.is_empty() \
		and _sim.city.funds >= int(stats.bonds[0].get("principal", 0))
	_repay_button.disabled = not can_repay


func _refresh_quote() -> void:
	var budget := _budget()
	if budget == null:
		_quote_label.text = "No bank without a city"
		_issue_button.disabled = true
		return
	var quote: Dictionary = budget.call("bond_quote", int(_bond_amount.value))
	var eligible := bool(quote.get("eligible", false))
	_issue_button.disabled = not eligible
	if eligible:
		_quote_label.text = "Quote: %s at %d%%, %s interest a year (prime %d%%)" % [
			UIFactory.format_amount(int(quote.get("amount", 0))), int(quote.get("rate", 0)),
			UIFactory.format_amount(int(quote.get("yearly_interest", 0))), _sim.stats.prime_rate]
	else:
		_quote_label.text = "The bank declines: %s" % String(quote.get("reason", ""))


# ── Control callbacks ────────────────────────────────────────────────────

func _on_tax_changed(value: float, kind: StringName) -> void:
	if _syncing or _sim == null:
		return
	var rate := clampi(int(value), 0, TAX_MAX)
	match kind:
		&"residential": _sim.stats.tax_residential = rate
		&"commercial": _sim.stats.tax_commercial = rate
		&"industrial": _sim.stats.tax_industrial = rate
	_syncing = true
	_refresh_ledger(_sim.stats)
	_syncing = false


func _on_funding_changed(value: float, service: StringName) -> void:
	var value_label: Label = _funding_values[service]
	value_label.text = "%d%%" % int(value)
	if _syncing or _sim == null:
		return
	_sim.stats.set_funding(service, int(value))
	_syncing = true
	_refresh_ledger(_sim.stats)
	_syncing = false


func _on_bond_amount_changed(_value: float) -> void:
	if _syncing:
		return
	_refresh_quote()


func _on_auto_budget_toggled(on: bool) -> void:
	if _syncing or _sim == null:
		return
	_sim.stats.auto_budget = on


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
