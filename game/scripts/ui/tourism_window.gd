# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Visitor results and constraints. Reading this report never advances tourism.
class_name TourismWindow
extends Control

signal closed
signal report_requested(window_name: String, page: String)

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _overview: VBoxContainer
var _status: Label
var _tourism_values: Dictionary = {}
var _tourism_tax: Label
var _tourism_capacity: Label
var _tourism_limiter: Label
var _tourism_calendar: Label
var _tourism_accrued: Label
var _tourism_label: Label
var _tourism_detail_body: VBoxContainer
var _sections: Dictionary = {}
var _buttons: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Tourism")
	_root = chrome.root
	_body = chrome.body
	_root.size = Vector2(600, 460)
	_root.set_meta("preferred_size", Vector2(600, 460))
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	(chrome.close_button as Button).pressed.connect(close)
	WindowDrag.enable(chrome.title_bar, _root)
	_status = _text("")
	_body.add_child(_status)
	_overview = VBoxContainer.new()
	_overview.name = "TourismOverview"
	_overview.add_theme_constant_override("separation", UITheme.VSEP)
	_body.add_child(_overview)
	var grid := UIFactory.ResponsiveTable.new()
	grid.narrow_width = 320.0
	grid.caption_width = 160.0
	grid.name = "TourismComparison"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	for title in ["", "Latest monthly", "Supported forecast"]:
		var heading := _text(title)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not title.is_empty(): heading.name = "TourismActualHeader" if title == "Latest monthly" else "TourismForecastHeader"
		if title == "Supported forecast": heading.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(heading)
	for entry in [["guests", "Guests"], ["day", "Day visitors"], ["occupancy", "Occupancy"]]:
		var caption := _text(entry[1])
		caption.name = "TourismMetric" + String(entry[0]).capitalize()
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.custom_minimum_size.x = 90.0
		grid.add_child(caption)
		var pair: Array[Label] = []
		for i in 2:
			var value := _text("0")
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(value)
			pair.append(value)
		_tourism_values[entry[0]] = pair
	_overview.add_child(grid)
	_tourism_capacity = _text("")
	_overview.add_child(_tourism_capacity)
	_overview.add_child(UIFactory.make_section_header("Estimated city taxes"))
	_tourism_tax = _text("$0 / year", UITheme.MONEY_POSITIVE)
	_tourism_tax.name = "TourismTaxEstimate"
	_overview.add_child(_tourism_tax)
	_tourism_limiter = _text("")
	_tourism_limiter.name = "TourismLimiter"
	_body.add_child(_tourism_limiter)
	_body.move_child(_tourism_limiter, 1)
	_tourism_calendar = _text("", UITheme.TEXT_MUTED)
	_overview.add_child(_tourism_calendar)
	for title in ["Visitors and jobs", "Access and utilities", "Reputation and events", "Income"]:
		var button := UIFactory.make_button(title + " ▸", "Show " + title.to_lower())
		button.toggle_mode = true
		button.name = "TourismDetails" if title == "Visitors and jobs" else title.replace(" ", "")
		_overview.add_child(button)
		var section := VBoxContainer.new()
		if title == "Visitors and jobs": section.name = "TourismDetailBody"
		section.hide()
		_overview.add_child(section)
		var label := _text("")
		section.add_child(label)
		_sections[title] = {"body": section, "label": label}
		_buttons[title] = button
		button.toggled.connect(_toggle_section.bind(title))
		if title == "Visitors and jobs": _tourism_detail_body = section
		if title == "Income":
			_tourism_label = label
			_tourism_accrued = _text("")
			section.add_child(_tourism_accrued)
	var taxes := UIFactory.make_button("Visitor taxes", "Open Budget → Taxes")
	taxes.name = "VisitorTaxLink"
	taxes.pressed.connect(func() -> void: report_requested.emit("budget", "Taxes"))
	chrome.actions.add_child(taxes)
	var policies := UIFactory.make_button("Ordinances", "Tourist advertising, carnival and casino safety")
	policies.pressed.connect(func() -> void: report_requested.emit("ordinances", "Finance"))
	chrome.actions.add_child(policies)
	hide()

static func _text(text: String, color: Color = UITheme.TEXT_PRIMARY) -> Label:
	var label := UIFactory.make_label(text, UITheme.FONT_SMALL, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func bind(sim: Simulation) -> void:
	if _sim != null and _sim != sim:
		if _sim.month_ended.is_connected(_month): _sim.month_ended.disconnect(_month)
		if _sim.year_ended.is_connected(_year): _sim.year_ended.disconnect(_year)
	_sim = sim
	if sim != null:
		if not sim.month_ended.is_connected(_month): sim.month_ended.connect(_month)
		if not sim.year_ended.is_connected(_year): sim.year_ended.connect(_year)
	refresh()

func open() -> void:
	show()
	refresh()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _toggle_section(on: bool, title: String) -> void:
	for other: String in _sections:
		var selected := on and other == title
		(_buttons[other] as Button).set_pressed_no_signal(selected)
		(_buttons[other] as Button).text = other + (" ▾" if selected else " ▸")
		(_sections[other].body as Control).visible = selected
	refresh()

func refresh() -> void:
	if _status == null: return
	var tourism := _sim.tourism() if _sim != null and _sim.city != null else null
	var projection: Dictionary = tourism.supported_forecast(-1, -1, true) if tourism != null else {}
	var stats := _sim.stats if tourism != null else CityStats.new()
	_status.text = _sim.date_text() if tourism != null else "No city loaded"
	var metrics := {
		"guests": [UIFactory.commafy(stats.tourist_guests), UIFactory.commafy(int(projection.get("guests", 0)))],
		"day": [UIFactory.commafy(stats.tourist_day_visitors), UIFactory.commafy(int(projection.get("day_visitors", 0)))],
		"occupancy": ["%d%%" % stats.tourist_occupancy, "%d%%" % int(projection.get("occupancy", 0))]}
	for metric in metrics:
		for column in 2: _tourism_values[metric][column].text = metrics[metric][column]
	var budget := _sim.get_system(&"budget") if tourism != null else null
	var estimate: Dictionary = budget.call("estimated_ledger") if budget != null else {}
	_tourism_tax.text = UIFactory.format_amount(int(estimate.get(&"taxes_occupancy", 0)) + int(estimate.get(&"taxes_gaming", 0))) + " / year at this month’s pace"
	_tourism_accrued.text = "Visitor taxes owed this year: " + UIFactory.format_amount(int(stats.ledger.get(&"taxes_occupancy", 0)) + int(stats.ledger.get(&"taxes_gaming", 0)))
	if tourism == null:
		_show_activity(false)
		_tourism_capacity.text = "No active tourism economy"
		_tourism_limiter.text = ""
		_tourism_calendar.text = ""
		for section: Dictionary in _sections.values(): (section.label as Label).text = "No city loaded"
		return
	var active := int(projection.stock_venues) > 0 or stats.tourist_guests > 0 or stats.tourist_day_visitors > 0
	active = active or int(stats.ledger.get(&"taxes_occupancy", 0)) != 0 or int(stats.ledger.get(&"taxes_gaming", 0)) != 0
	_show_activity(active)
	var utilities := tourism.utility_report()
	var staff := tourism.staffing_report()
	_tourism_capacity.text = "Lodging: %s beds" % UIFactory.commafy(int(projection.physical_capacity))
	_tourism_capacity.visible = int(projection.physical_capacity) > 0
	var limiter := "Demand at current taxes and season"
	if int(projection.stock_venues) == 0: limiter = "No tourism venues"
	elif int(projection.operating_venues) == 0: limiter = "Closed venues: power, water, access or fire"
	elif int(projection.support_limited_venues) > 0: limiter = "Local power or water capacity"
	elif int(projection.awaiting_support_venues) > 0: limiter = "Awaiting monthly support plan"
	elif int(projection.staff_limited_guest_venues) + int(projection.staff_limited_day_venues) > 0: limiter = "Available staff"
	elif int(projection.capacity) > 0 and int(projection.guests) >= int(projection.capacity): limiter = "Available beds"
	elif int(projection.day_capacity) > 0 and int(projection.day_visitors) >= int(projection.day_capacity): limiter = "Available day-visitor capacity"
	_tourism_limiter.text = "Main limit: " + limiter
	var calendar: Dictionary = projection.calendar
	var event: Dictionary = calendar.get("next_event", {})
	_tourism_calendar.text = "Next event: %s, %s — %s" % [event.name, event.date, event.status] if not event.is_empty() else ""
	_tourism_calendar.visible = not event.is_empty()
	# Populate only useful results; no raw source fractions, yield multipliers or planning dumps.
	_sections["Visitors and jobs"].label.text = "Jobs filled: %s of %s" % [UIFactory.commafy(staff.local_staff + staff.incoming_staff), UIFactory.commafy(staff.positions)]
	if staff.incoming_staff > 0:
		_sections["Visitors and jobs"].label.text += "\nIncoming staff: " + UIFactory.commafy(staff.incoming_staff)
	var effects := tourism.extension_report()
	var trips := tourism.transport_report()
	_sections["Access and utilities"].label.text = "Gateways: %d · Capacity: %s / month\nVisitor trips completed: %s" % [int(effects.access.gateway_count), UIFactory.commafy(int(effects.access.arrival_capacity)), UIFactory.commafy(int(trips.get("completed", 0)))]
	if int(trips.get("pending", 0)) > 0:
		_sections["Access and utilities"].label.text += "\nTrips waiting: " + UIFactory.commafy(int(trips.pending))
	if int(utilities.limited_venues) > 0:
		_sections["Access and utilities"].label.text += "\n%d venues short of power or water" % int(utilities.limited_venues)
	var rep := tourism.reputation_report()
	_sections["Reputation and events"].label.text = "Reputation: %.1f / 100.\nSeasonal demand: %d%%.\n%s" % [int(rep.value_milli) / 1000.0, int(calendar.season_percent), _tourism_calendar.text]
	_tourism_label.text = "Visitor taxes settle in January."
	if effects.program_active or int(effects.program_completed_half_cents) > 0:
		_tourism_label.text += "\nCasino Safety Program: $%.2f spent; $%.2f / year if enabled." % [int(effects.program_completed_half_cents) / 200.0, int(effects.program_estimated_annual_cents) / 100.0]
	var forecast := find_child("TourismForecastHeader", true, false) as Label
	forecast.tooltip_text = "Estimated attendance at current taxes and season, limited by the last accepted power and water support."

func _show_activity(on: bool) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not on and focused != null and _overview.is_ancestor_of(focused):
		var chrome: Dictionary = _root.get_meta("window_chrome")
		(chrome.close_button as Button).grab_focus()
	var changed := _overview.visible != on
	_overview.visible = on
	if changed:
		var wanted := Vector2(600, 460) if on else Vector2(420, 220)
		_root.set("preferred_size", wanted)
		_root.set_meta("preferred_size", wanted)
		_root.call("_schedule_fit")

func _month(_year: int, _month: int) -> void:
	if visible: refresh()

func _year(_year_number: int) -> void:
	if visible: refresh()
