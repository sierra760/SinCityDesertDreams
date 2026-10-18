# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Budget window: tax rates, service funding, the year's books, the bond
## market and the auto-budget switch. It also serves as the January review;
## the host finishes the review when this window emits `closed`.
class_name BudgetWindow
extends Control

signal closed
signal report_requested(window_name: String, page: String)

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
	[&"taxes_agricultural", "Agricultural taxes"],
	[&"taxes_occupancy", "Occupancy tax"],
	[&"taxes_gaming", "Gaming revenue tax"],
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
var _pages: ReportPages
var _summary_values: Array[Label] = []
var _visitor_tax: Label
var _ledger_period: OptionButton
var _ledger_body: VBoxContainer
var _ledger_subtotals: Dictionary = {}
var _funding_pages: Array[VBoxContainer] = []
var _funding_picker: OptionButton
var _review_showing := false
var _tax_spinners: Dictionary = {}       ## kind -> TouchNumberField
var _funding_sliders: Dictionary = {}    ## service -> HSlider
var _funding_values: Dictionary = {}     ## service -> Label
var _ledger_rows: Dictionary = {}        ## account -> [year_to_date Label, estimate Label, previous_year Label]
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
	_root.size = Vector2(640, 500)
	_root.set_meta("preferred_size", Vector2(640, 500))
	_pages = ReportPages.new(chrome, ["Summary", "Taxes", "Funding", "Debt"])
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
	_bind_chrome_bounds.call_deferred()


## Budget can fill a short display. Its title must stay below the host's actual
## menu edge, including the existing portrait camera-band placement.
func _layout_host() -> GameHost:
	var node:=get_parent()
	while node!=null:
		if node is GameHost: return node as GameHost
		node=node.get_parent()
	return null

func _bind_chrome_bounds() -> void:
	var host:=_layout_host()
	if host==null: return
	host.menu_bar.item_rect_changed.connect(_schedule_chrome_fit)
	host.menu_bar.visibility_changed.connect(_schedule_chrome_fit)
	host.display_layout.metrics_changed.connect(func(_metrics: Dictionary): _schedule_chrome_fit())
	_schedule_chrome_fit()

func _schedule_chrome_fit() -> void:
	_fit_below_menu.call_deferred()

func _fit_below_menu() -> void:
	var host:=_layout_host()
	if host==null or not is_instance_valid(_root): return
	var bounds:=host.display_layout.logical_rect()
	_status_label.visible = bounds.size.y >= 500
	if host.menu_bar.visible:
		var top:=maxf(bounds.position.y,host.menu_bar.get_global_rect().end.y)
		bounds=Rect2(Vector2(bounds.position.x,top),Vector2(bounds.size.x,maxf(0.0,bounds.end.y-top)))
	_root.set_meta("display_usable_rect",bounds)
	_root.call("_schedule_fit")


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
		if _sim.funds_changed.is_connected(_on_funds_changed):
			_sim.funds_changed.disconnect(_on_funds_changed)
	_sim = sim
	if sim != null:
		if not sim.month_ended.is_connected(_on_month_ended):
			sim.month_ended.connect(_on_month_ended)
		if not sim.year_ended.is_connected(_on_year_ended):
			sim.year_ended.connect(_on_year_ended)
		if not sim.funds_changed.is_connected(_on_funds_changed):
			sim.funds_changed.connect(_on_funds_changed)
	refresh()


func select_page(page_name: String) -> void:
	_pages.select(page_name)

func selected_page() -> String:
	return _pages.selected()

func begin_review() -> void:
	_pages.select("Summary")

func open() -> void:
	var review := _sim != null and _sim.budget_review_pending
	if review and not _review_showing: begin_review()
	_review_showing = review
	show()
	refresh()
	_fit_below_menu.call_deferred()


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
		_review_label.text = "Review for %d · City paused until Done." % _sim.clock.year()
	var stats := _sim.stats if _sim != null else CityStats.new()
	_tax_spinners[&"residential"].value = stats.tax_residential
	_tax_spinners[&"commercial"].value = stats.tax_commercial
	_tax_spinners[&"industrial"].value = stats.tax_industrial
	_tax_spinners[&"agricultural"].value = stats.tax_agricultural
	_tax_spinners[&"occupancy"].value = stats.tax_occupancy
	_tax_spinners[&"gaming"].value = stats.tax_gaming
	for service: StringName in _funding_sliders:
		var pct := stats.funding_of(service)
		var slider: HSlider = _funding_sliders[service]
		slider.value = pct
		var value_label: Label = _funding_values[service]
		value_label.text = "%d%%" % pct
	_auto_budget.button_pressed = stats.auto_budget
	_condition_label.text = condition_text(_sim)
	_refresh_ledger(stats)
	_refresh_visitor_tax()
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
		var built := false
		for category: StringName in TRANSPORT_FUNDING:
			if int(counts.get(category, 0)) <= 0 and int(lost.get(category, 0)) <= 0:
				continue
			built = true
			# Only networks that are wearing or have lost pieces are listed.
			var worn := int(wear.call("wear_percent", category))
			if worn <= 0 and int(lost.get(category, 0)) <= 0:
				continue
			var text := "%s %d%% worn" % [String(FUNDING_LABELS.get(category, String(category))), worn]
			if int(lost.get(category, 0)) > 0:
				text += ", %s lost" % UIFactory.commafy(int(lost[category]))
			parts.append(text)
		var condition := "; ".join(parts)
		if parts.is_empty():
			condition = "all networks in good repair" if built else "no networks built yet"
		lines.append("Condition: " + condition)
	var history := sim.stats.history
	var riders: PackedStringArray = []
	for entry: Array in [[&"riders_bus", "bus"], [&"riders_rail", "rail"], [&"riders_subway", "subway"]]:
		var series: PackedInt32Array = history.get(entry[0], PackedInt32Array())
		# Modes nobody rode last year are left out.
		if not series.is_empty() and series[series.size() - 1] > 0:
			riders.append("%s %s" % [entry[1], UIFactory.commafy(series[series.size() - 1])])
	if not riders.is_empty():
		lines.append("Transit riders last year: " + ", ".join(riders))
	var transport := sim.get_system(&"transport")
	if transport != null:
		var trips: Dictionary = transport.tourism_report()
		lines.append("Visitor trips: %s completed; %s pending; %s unsampled. Resident commutes are counted separately." % [UIFactory.commafy(int(trips.completed)),UIFactory.commafy(int(trips.pending)),UIFactory.commafy(int(trips.unsampled))])
	return "\n".join(lines)


## Redraw the other open report windows beside `from` after it changed
## something they show (a tax rate, an ordinance's cost).
static func refresh_other_windows(from: Control) -> void:
	var parent := from.get_parent() if from != null else null
	if parent == null:
		return
	for w: Node in parent.get_children():
		if w != from and (w is BudgetWindow or w is IndustriesWindow or w is TourismWindow or w is OrdinancesWindow) and (w as Control).visible:
			w.call("refresh")


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
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_funds_label = UIFactory.make_label("Treasury: $0", UITheme.FONT_HEADER, UITheme.MONEY_POSITIVE)
	_funds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_label = _wrapped("", UITheme.ACCENT_BRASS)
	_review_label.hide()
	_pages.header.add_child(_status_label)
	_pages.header.add_child(_funds_label)
	_pages.header.add_child(_review_label)
	var summary := _pages.page(0)
	var cards := UIFactory.ResponsiveColumns.new()
	cards.add_theme_constant_override("separation", 8)
	for title in ["Annual income", "Annual expenses", "Surplus / deficit"]:
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(UIFactory.make_label(title, UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
		var value := UIFactory.make_label("$0", UITheme.FONT_TITLE)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(value)
		_summary_values.append(value)
		cards.add_child(card)
	summary.add_child(cards)
	summary.add_child(_wrapped("Estimates for the full year. Income and expenses settle each January.", UITheme.TEXT_MUTED))
	_last_year_label = _wrapped("Last year: no books yet", UITheme.TEXT_MUTED)
	summary.add_child(_last_year_label)
	_totals_label = Label.new() # Stable textual reader; the three figures above are the presentation.
	_totals_label.hide()
	summary.add_child(_totals_label)
	var breakdown := UIFactory.make_button("Account breakdown", "Show income and expenses by account")
	breakdown.name = "AccountBreakdown"
	breakdown.toggle_mode = true
	summary.add_child(breakdown)
	_ledger_body = VBoxContainer.new()
	_ledger_body.hide()
	summary.add_child(_ledger_body)
	breakdown.toggled.connect(func(on: bool) -> void: _ledger_body.visible = on)
	_build_ledger(_ledger_body)
	_build_taxes(_pages.page(1))
	_build_funding(_pages.page(2))
	_build_bonds(_pages.page(3))
	_auto_budget = CheckBox.new()
	_auto_budget.text = "Auto budget"
	_auto_budget.tooltip_text = "Skip the January review and keep the current taxes and funding"
	_auto_budget.custom_minimum_size.y = 44
	_auto_budget.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_auto_budget.toggled.connect(_on_auto_budget_toggled)
	_auto_budget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(_auto_budget)
	var done := UIFactory.make_button("Done", "Close the budget and finish any annual review")
	done.pressed.connect(close)
	_actions.add_child(done)

static func _wrapped(text: String, color: Color = UITheme.TEXT_PRIMARY) -> Label:
	var label := UIFactory.make_label(text, UITheme.FONT_SMALL, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_taxes(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Property taxes"))
	var grid := UIFactory.ResponsiveTable.new()
	grid.columns = 2
	grid.has_headers = false
	grid.headings = ["", "Rate"]
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	for entry: Array in [[&"residential", "Residential"], [&"commercial", "Commercial"], [&"industrial", "Industrial"], [&"agricultural", "Agriculture"]]:
		var kind: StringName = entry[0]
		var caption := UIFactory.make_label(String(entry[1]) + " %")
		grid.add_child(caption)
		var spinner := TouchNumberField.new()
		spinner.min_value = 0
		spinner.max_value = TAX_MAX
		spinner.step = 1
		if kind == &"agricultural":
			caption.tooltip_text = "Independent agricultural tax, 0–20%. Active farm jobs assess $100 each; prepared and dormant land earns no tax."
			caption.mouse_filter = Control.MOUSE_FILTER_PASS
			spinner.tooltip_text = caption.tooltip_text
		if kind == &"industrial":
			caption.tooltip_text = "The share-weighted average of the eleven industry rates (Reports → Industries). Changing it shifts every sector by the same points."
			caption.mouse_filter = Control.MOUSE_FILTER_PASS
			spinner.tooltip_text = caption.tooltip_text
		spinner.value_changed.connect(_on_tax_changed.bind(kind))
		grid.add_child(spinner)
		_tax_spinners[kind] = spinner
	parent.add_child(grid)
	parent.add_child(UIFactory.make_section_header("Visitor taxes"))
	for entry in [[&"occupancy", "Occupancy tax", "Tax on visitor lodging"], [&"gaming", "Gaming revenue tax", "Tax on gaming revenue after payouts"]]:
		var row := UIFactory.WrappingActions.new()
		var caption := UIFactory.make_label(String(entry[1]) + " %")
		caption.tooltip_text = entry[2]
		row.add_child(caption)
		var field := TouchNumberField.new()
		field.min_value = TourismParams.TAX_MIN
		field.max_value = TourismParams.TAX_MAX
		field.step = TourismParams.TAX_STEP
		field.tooltip_text = entry[2]
		field.value_changed.connect(_on_tax_changed.bind(entry[0]))
		_tax_spinners[entry[0]] = field
		row.add_child(field)
		parent.add_child(row)
	_visitor_tax = _wrapped("")
	parent.add_child(_visitor_tax)
	var tourism := UIFactory.make_button("Open Tourism Report", "Visitor attendance, capacity and services")
	tourism.pressed.connect(func() -> void: report_requested.emit("tourism", ""))
	parent.add_child(tourism)
	var industries := UIFactory.make_button("Industry tax rates", "Adjust taxes for individual industry sectors")
	industries.pressed.connect(func() -> void: report_requested.emit("industries", ""))
	parent.add_child(industries)


func _refresh_visitor_tax() -> void:
	var budget := _budget()
	var estimate: Dictionary = budget.call("estimated_ledger") if budget != null else {}
	_visitor_tax.text = "Estimated visitor taxes: %s / year at this month’s pace" % UIFactory.format_amount(int(estimate.get(&"taxes_occupancy", 0)) + int(estimate.get(&"taxes_gaming", 0)))


func _build_funding(parent: VBoxContainer) -> void:
	_funding_picker = OptionButton.new()
	_funding_picker.name = "FundingCategory"
	_funding_picker.custom_minimum_size.y = 44
	_funding_picker.add_item("Services")
	_funding_picker.add_item("Transportation")
	_funding_picker.item_selected.connect(select_funding)
	parent.add_child(_funding_picker)
	for i in 2:
		var section := VBoxContainer.new()
		section.name = "ServiceFunding" if i == 0 else "TransportFunding"
		section.visible = i == 0
		parent.add_child(section)
		_funding_pages.append(section)
		section.add_child(_funding_grid(SERVICE_FUNDING if i == 0 else TRANSPORT_FUNDING))
	_condition_label = _wrapped("", UITheme.TEXT_MUTED)
	_funding_pages[1].add_child(_condition_label)

func select_funding(index: int) -> void:
	if index < 0 or index >= _funding_pages.size(): return
	_funding_picker.select(index)
	for i in _funding_pages.size(): _funding_pages[i].visible = i == index


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
	_ledger_period = OptionButton.new()
	_ledger_period.name = "LedgerPeriod"
	_ledger_period.custom_minimum_size.y = 44
	for title in ["Year to date", "Previous year", "Year-end estimate"]: _ledger_period.add_item(title)
	_ledger_period.select(2)
	_ledger_period.item_selected.connect(_select_ledger_period)
	parent.add_child(_ledger_period)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	parent.add_child(grid)
	for expense in [false, true]:
		grid.add_child(UIFactory.make_section_header("Expenses" if expense else "Income"))
		grid.add_child(Control.new())
		for entry in ACCOUNTS:
			var account: StringName = entry[0]
			if (account in BudgetParams.EXPENSE_KEYS) != expense: continue
			var caption := _wrapped(String(entry[1]))
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(caption)
			var values := VBoxContainer.new()
			grid.add_child(values)
			var labels: Array[Label] = []
			for i in 3:
				var amount := _amount_label("$0")
				amount.visible = i == 1
				values.add_child(amount)
				labels.append(amount)
			_ledger_rows[account] = labels
		grid.add_child(_wrapped("Expenses total" if expense else "Income total"))
		var total := _amount_label("$0")
		grid.add_child(total)
		_ledger_subtotals[expense] = total

func _select_ledger_period(index: int) -> void:
	_ledger_period.select(index)
	var selected: int = [0, 2, 1][index]
	for labels: Array in _ledger_rows.values():
		for i in 3: (labels[i] as Label).visible = i == selected
	var stats := _sim.stats if _sim != null else CityStats.new()
	var source: Dictionary = stats.ledger if index == 0 else stats.last_year_ledger
	if index == 2:
		var budget := _budget()
		source = budget.call("estimated_ledger") if budget != null else {}
	for expense in [false, true]:
		var amount := 0
		for entry in ACCOUNTS:
			var key: StringName = entry[0]
			if (key in BudgetParams.EXPENSE_KEYS) != expense: continue
			amount += int(source.get(key, 0))
		_set_amount(_ledger_subtotals[expense], amount, expense)


func _build_bonds(parent: VBoxContainer) -> void:
	parent.add_child(UIFactory.make_section_header("Bonds"))
	_bond_rows = VBoxContainer.new()
	_bond_rows.add_theme_constant_override("separation", 2)
	parent.add_child(_bond_rows)
	_debt_label = UIFactory.make_label("Total debt $0", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	parent.add_child(_debt_label)
	parent.move_child(_debt_label, 1)
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
		_set_amount(pair[2], int(stats.last_year_ledger.get(account, 0)), expense)
	var income := int(summary.get("estimated_income", 0))
	var expenses := int(summary.get("estimated_expenses", 0))
	for i in 3:
		_summary_values[i].text = UIFactory.format_signed_amount([income, expenses, income - expenses][i])
		var effect: int = [income, -expenses, income - expenses][i]
		_summary_values[i].add_theme_color_override("font_color", UITheme.MONEY_NEGATIVE if effect < 0 else UITheme.MONEY_POSITIVE)
	_select_ledger_period(_ledger_period.selected)
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
	var interest := 0
	for bond: Dictionary in stats.bonds: interest += int(bond.get("principal", 0)) * int(bond.get("rate", 0)) / 100
	_debt_label.text = "Debt %s · Interest %s / year\n%d of %d bonds" % [UIFactory.format_amount(debt), UIFactory.format_amount(interest), stats.bonds.size(), BudgetParams.MAX_BONDS]
	_refresh_quote()
	_refresh_repay(stats)


## Repay is possible when the treasury covers the oldest bond; otherwise the
## button says what it needs.
func _refresh_repay(stats: CityStats) -> void:
	var budget := _budget()
	if budget == null or stats.bonds.is_empty():
		_repay_button.disabled = true
		_repay_button.tooltip_text = "No bonds to repay"
		return
	var principal := int(stats.bonds[0].get("principal", 0))
	_repay_button.disabled = _sim.city.funds < principal
	_repay_button.tooltip_text = "Pay off the oldest bond in full" if not _repay_button.disabled \
		else "Needs %s in the treasury to repay bond 1" % UIFactory.format_amount(principal)


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
		&"agricultural": _sim.stats.tax_agricultural = rate
		&"occupancy": _sim.stats.tax_occupancy = rate
		&"gaming": _sim.stats.tax_gaming = rate
	_syncing = true
	if kind == &"industrial":
		# The rate is the average of the eleven sector rates: shift them now so
		# a sector edit in Industries cannot throw this change away.
		var economy := _sim.get_system(&"economy")
		if economy != null and economy.has_method("industrial_rate_written"):
			economy.call("industrial_rate_written")
		(_tax_spinners[&"industrial"] as TouchNumberField).value = _sim.stats.tax_industrial
	_refresh_ledger(_sim.stats)
	_refresh_visitor_tax()
	_syncing = false
	refresh_other_windows(self)


func _on_funding_changed(value: float, service: StringName) -> void:
	var value_label: Label = _funding_values[service]
	value_label.text = "%d%%" % int(value)
	if _syncing or _sim == null:
		return
	_sim.stats.set_funding(service, int(value))
	_syncing = true
	_refresh_ledger(_sim.stats)
	_refresh_visitor_tax()
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


## The treasury moves every day the city runs; keep its line and Repay current
## without rebuilding the rest of the window.
func _on_funds_changed(funds: int) -> void:
	if not visible or not _built or _sim == null or _sim.city == null:
		return
	_funds_label.text = "Treasury: " + UIFactory.format_signed_amount(funds)
	_refresh_repay(_sim.stats)


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
