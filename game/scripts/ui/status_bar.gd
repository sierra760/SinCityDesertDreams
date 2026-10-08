# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The bottom status bar: active tool, funds, date, population, the three
## demand bars, simulation speed and the current alerts.
class_name StatusBar
extends PanelContainer

signal emergency_requested

const BAR_HEIGHT := 48
const DEMAND_LIMIT := 999

var tool_label: Label
var funds_label: Label
var date_label: Label
var population_label: Label
var speed_label: Label
var alert_label: Label
var message_label: Label
var demand_meter: DemandMeter
var emergency_button: Button
var _metrics_row: HFlowContainer
var _column: VBoxContainer
var _editing := false
var _phone := false
var _details_open := false
var _phone_row: HBoxContainer
var _phone_summary: Label
var _details_button: Button
var _details_scroll: ScrollContainer
var _details_content: VBoxContainer
var _phone_height_limit := 240.0
var _bottom_edge_fill := Vector3.ZERO

## Paint the bar through the home-indicator inset without extending its
## interactive rectangle or changing the content's natural height.
func set_bottom_edge_fill(insets: Vector3) -> void:
	var next := insets.max(Vector3.ZERO)
	if next == _bottom_edge_fill: return
	_bottom_edge_fill = next
	queue_redraw()

func _draw() -> void:
	if _bottom_edge_fill.z <= 0.0: return
	draw_rect(Rect2(-_bottom_edge_fill.x,size.y,size.x+_bottom_edge_fill.x+_bottom_edge_fill.y,_bottom_edge_fill.z),UITheme.PANEL_FACE)

func set_phone_layout(on: bool) -> void:
	_phone = on
	if on and _details_button == null:
		_details_button = UIFactory.make_button("Details")
		_details_button.pressed.connect(func() -> void: set_details_open(not _details_open))
		_phone_row.add_child(_details_button)
		_details_scroll = ScrollContainer.new()
		_details_scroll.name = "PhoneDetailsScroll"
		_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_details_scroll.follow_focus = true
		_details_content = VBoxContainer.new()
		_details_content.add_theme_constant_override("separation",8)
		_details_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_details_scroll.add_child(_details_content)
		_column.add_child(_details_scroll)
	if _details_scroll != null:
		var parent: Control = _details_content if on else _column
		if _metrics_row.get_parent() != parent: _metrics_row.reparent(parent,false)
		if alert_label.get_parent() != parent: alert_label.reparent(parent,false)
		if not on:
			_column.move_child(_metrics_row,1)
			_column.move_child(alert_label,2)
	set_details_open(false)

func set_details_open(on: bool) -> void:
	_details_open = on and _phone
	_phone_row.visible = _phone
	_metrics_row.visible = not _phone or _details_open
	alert_label.visible = not alert_label.text.is_empty() and (not _phone or _details_open)
	message_label.max_lines_visible = 1 if _phone else 2
	if _details_scroll != null:
		_details_scroll.visible = _details_open
		var parent: Control = _details_content if _details_open else _column
		if message_label.get_parent() != parent: message_label.reparent(parent,false)
		parent.move_child(message_label,parent.get_child_count()-1)
		apply_phone_height_limit(_phone_height_limit)
	if _details_button != null: _details_button.text = "Less" if _details_open else "Details"
	_sync_phone_summary()

## Expanded phone metrics scroll before they can crowd the Explore thumb area.
## The desktop footer keeps its natural height.
func apply_phone_height_limit(height: float) -> void:
	_phone_height_limit = height
	if not _phone or _details_scroll == null: return
	var fixed_height := _phone_row.get_combined_minimum_size().y + get_theme_stylebox("panel").get_minimum_size().y + 8.0
	_details_scroll.custom_minimum_size.y = minf(_details_content.get_combined_minimum_size().y,maxf(44.0,height-fixed_height))

func _sync_phone_summary() -> void:
	if _phone_summary == null or _details_button == null: return
	var paused := speed_label != null and speed_label.text == String(GameClock.SPEED_NAMES[GameClock.Speed.PAUSED])
	_phone_summary.text = funds_label.text+" · "+date_label.text+(" · Paused" if paused else "")+"\n"+tool_label.text
	_details_button.text = "Less" if _details_open else ("Alerts" if not alert_label.text.is_empty() else "Details")
	_details_button.add_theme_color_override("font_color",UITheme.MONEY_NEGATIVE if not alert_label.text.is_empty() else UITheme.TEXT_PRIMARY)
	_details_button.tooltip_text = alert_label.text if not alert_label.text.is_empty() else "Tool, population, demand and simulation speed"


## Three bars, one per zone family, growing up for positive demand and down
## for negative demand around a shared baseline.
class DemandMeter:
	extends Control
	var demand := Vector3i.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(60,28)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Residential, commercial and industrial demand"

	func set_demand(value: Vector3i) -> void:
		demand = value
		tooltip_text = "Demand: Residential %d · Commercial %d · Industrial %d\nPositive: room to grow. Negative: excess capacity." % [value.x,value.y,value.z]
		queue_redraw()

	func _draw() -> void:
		var colors: Array[Color] = [UITheme.ZONE_R, UITheme.ZONE_C, UITheme.ZONE_I]
		var values: Array[int] = [demand.x, demand.y, demand.z]
		var mid := size.y / 2.0
		var half := mid - 1.0
		var bar_w := size.x / 3.0 - 4.0
		draw_line(Vector2(0, mid), Vector2(size.x, mid), UITheme.BEVEL_DARK, 1.0)
		for i in 3:
			var x := i * (bar_w + 4.0) + 2.0
			var h := clampf(float(values[i]) / float(DEMAND_LIMIT), -1.0, 1.0) * half
			var rect := Rect2(x, mid - maxf(h, 0.0), bar_w, absf(h))
			draw_rect(rect, colors[i])


func _init() -> void:
	name = "StatusBar"
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.PANEL_FACE
	style.border_color = UITheme.ACCENT_BRASS
	style.border_width_top = 2
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_build()


func _build() -> void:
	theme = UITheme.control_theme()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation",8)
	add_child(_column)
	_phone_row = HBoxContainer.new()
	_phone_row.name = "PhoneSummary"
	_phone_row.add_theme_constant_override("separation",8)
	_phone_row.hide()
	_phone_summary = UIFactory.make_label("$0 · —")
	_phone_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_phone_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phone_row.add_child(_phone_summary)
	_column.add_child(_phone_row)
	_metrics_row = HFlowContainer.new()
	_metrics_row.add_theme_constant_override("h_separation",16)
	_metrics_row.add_theme_constant_override("v_separation",8)
	_column.add_child(_metrics_row)
	tool_label = _cell(_metrics_row,"Tool: none",0)
	funds_label = _cell(_metrics_row,"$0",0,UITheme.MONEY_POSITIVE)
	funds_label.tooltip_text = "City treasury"
	date_label = _cell(_metrics_row,"—",0)
	population_label = _cell(_metrics_row,"Pop: 0",0)
	population_label.tooltip_text = "Total city population"
	_metrics_row.add_child(UIFactory.make_label("R / C / I",UITheme.FONT_SMALL))
	demand_meter = DemandMeter.new()
	demand_meter.custom_minimum_size = Vector2(60,28)
	_metrics_row.add_child(demand_meter)
	speed_label = _cell(_metrics_row,"Paused",0)
	emergency_button = UIFactory.make_button("Go to emergency")
	emergency_button.name = "GoToEmergency"
	emergency_button.custom_minimum_size.y = 44
	emergency_button.tooltip_text = "Center the city view on the active emergency"
	emergency_button.disabled = true
	emergency_button.hide()
	emergency_button.pressed.connect(func() -> void: emergency_requested.emit())
	_metrics_row.add_child(emergency_button)
	alert_label = UIFactory.make_label("",UITheme.FONT_SMALL,UITheme.MONEY_NEGATIVE)
	alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alert_label.max_lines_visible = 2
	alert_label.visible = false
	_column.add_child(alert_label)
	message_label = UIFactory.make_label("",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.max_lines_visible = 2
	message_label.visible = false
	_column.add_child(message_label)

func _cell(row: Container, text: String, min_width: int, color := UITheme.TEXT_PRIMARY) -> Label:
	var l := UIFactory.make_label(text, UITheme.FONT_BODY, color)
	l.custom_minimum_size = Vector2(min_width,0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return l

func apply_layout(available_width: float) -> void:
	custom_minimum_size.x = 0
	_metrics_row.custom_minimum_size.x = 0
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_label.custom_minimum_size.x = minf(220.0,available_width * 0.35)


func set_tool_text(text: String) -> void:
	tool_label.text = "Tool: " + text
	_sync_phone_summary()


func set_funds(funds: int) -> void:
	funds_label.text = ("-$" if funds < 0 else "$") + UIFactory.commafy(funds)
	funds_label.add_theme_color_override("font_color",
		UITheme.MONEY_NEGATIVE if funds < 0 else UITheme.MONEY_POSITIVE)
	_sync_phone_summary()


func set_date(text: String) -> void:
	date_label.text = text
	_sync_phone_summary()


func set_population(population: int) -> void:
	population_label.text = "Pop: " + UIFactory.commafy(population)


func set_demand(demand: Vector3i) -> void:
	demand_meter.set_demand(demand)


func set_speed(speed: int) -> void:
	var editing_hint := "Found City to start the simulation clock."
	speed_label.text = "Stopped" if _editing else String(GameClock.SPEED_NAMES.get(speed, "Paused"))
	speed_label.tooltip_text = editing_hint if _editing else "Simulation speed. Change it from the Speed menu; %s pauses or resumes." % ("P" if not _phone else "Menu → Speed")
	_sync_phone_summary()


## Short warnings shown in red, joined with separators.
func set_alerts(alerts: PackedStringArray) -> void:
	alert_label.text = " · ".join(alerts)
	alert_label.tooltip_text = "\n".join(alerts)
	alert_label.visible = not alerts.is_empty() and (not _phone or _details_open)
	_sync_phone_summary()


## A transient note (a refused placement, a save confirmation).
func set_message(text: String) -> void:
	message_label.text = text
	message_label.tooltip_text = text
	message_label.visible = not text.is_empty()


## The editing stage: the land is being shaped, so there is no clock and no
## treasury yet, only the city's name.
func show_editing(city_name: String) -> void:
	_editing = true
	set_emergency_available(false)
	funds_label.text = "—"
	funds_label.add_theme_color_override("font_color", UITheme.MONEY_NEUTRAL)
	date_label.text = "Shaping the land"
	population_label.text = city_name
	set_demand(Vector3i.ZERO)
	set_speed(GameClock.Speed.PAUSED)
	set_alerts(PackedStringArray())
	_sync_phone_summary()


## Read every field from the running simulation.
func refresh(sim: Simulation) -> void:
	if sim == null or sim.city == null:
		return
	_editing = false
	set_funds(sim.city.funds)
	set_date(sim.date_text())
	set_population(sim.stats.total_population())
	set_demand(sim.stats.demand)
	var statistics := sim.get_system(&"statistics")
	if statistics != null and statistics.has_method("status_lines"):
		var lines: Array = statistics.call("status_lines")
		population_label.tooltip_text = "\n".join(PackedStringArray(lines)) if not lines.is_empty() else "Total city population"
	set_speed(sim.speed)
	set_alerts(alerts_for(sim))
	var disasters := sim.get_system(&"disasters") as DisasterSystem
	set_emergency_available(disasters != null and disasters.emergency_target().x >= 0)


## Keep emergency navigation available only while a live destination exists.
func set_emergency_available(available: bool) -> void:
	emergency_button.disabled = not available
	emergency_button.visible = available


## The warnings the bar shows for the simulation's current state.
static func alerts_for(sim: Simulation) -> PackedStringArray:
	var out := PackedStringArray()
	var power := sim.get_system(&"power")
	if power != null and power.has_method("is_shortage") and bool(power.call("is_shortage")):
		out.append("Power shortage")
	var water := sim.get_system(&"water")
	if water != null and water.has_method("is_shortage") and bool(water.call("is_shortage")):
		out.append("Water shortage")
	var disasters := sim.get_system(&"disasters")
	if disasters != null and disasters.has_method("is_emergency") and bool(disasters.call("is_emergency")):
		var kind := sim.stats.active_disaster
		out.append("Emergency: " + DisasterParams.display_name(kind) if kind != &"" else "Emergency")
	if sim.stats.bankrupt:
		out.append("Bankrupt")
	return out


## One line with every field, for tests and logs.
func summary() -> String:
	return "%s | %s | %s | %s | %s | %s" % [tool_label.text, funds_label.text, date_label.text,
		population_label.text, speed_label.text, alert_label.text]
