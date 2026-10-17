# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The bottom status bar: active tool, funds, date, population, the RCI and agricultural
## demand bars, simulation speed and the current alerts.
class_name StatusBar
extends PanelContainer

signal emergency_requested

const BAR_HEIGHT := 48
const DEMAND_LIMIT := 999
## Successive space savings for a narrow footer, applied only until the city
## metrics fit on one line: shrink the tool cell to its text, abbreviate the
## month, show the tool's bare name, drop the demand caption, compact the
## counts, then narrow the meter. Full values stay in the tooltips.
const COMPACT_LEVELS := 7
const METER_WIDTH := 80.0
const METER_COMPACT_WIDTH := 64.0

var tool_label: Label
var funds_label: Label
var date_label: Label
var population_label: Label
var tourists_label: Label
var _counts_row: HBoxContainer
var _population := 0
var _population_details := ""
var _tourists := 0
## Width the shell grants the footer; zero until the first layout.
var _available_width := 0.0
var _tool_reservation := 220.0
var _tool_name := "None"
var _full_date := "—"
var _demand_caption: Label
var speed_label: Label
var alert_label: Label
var message_label: Label
var demand_meter: DemandMeter
var emergency_button: Button
var _metrics_row: HFlowContainer
var _column: VBoxContainer
var _editing := false
## True while no tool is selected ("Tool: None").
var _no_tool := true
var _phone := false
var _details_open := false
var _phone_face: HBoxContainer
var _phone_text: VBoxContainer
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
	for label: Label in [population_label,tourists_label]:
		label.add_theme_font_size_override("font_size",UITheme.FONT_SMALL if on else UITheme.FONT_BODY)
	if on and _details_button == null:
		_details_button = UIFactory.make_button("Details")
		_details_button.pressed.connect(func() -> void: set_details_open(not _details_open))
		# Spans both face lines so the counts get their own row without
		# growing the compact footer.
		_details_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_phone_face.add_child(_details_button)
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
	if on:
		if _counts_row.get_parent() != _phone_text: _counts_row.reparent(_phone_text,false)
		_phone_text.move_child(_counts_row,1)
	else:
		if _counts_row.get_parent() != _metrics_row: _counts_row.reparent(_metrics_row,false)
		_metrics_row.move_child(_counts_row,3)
	set_details_open(false)

func set_details_open(on: bool) -> void:
	_details_open = on and _phone
	_phone_face.visible = _phone
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
	var fixed_height := _phone_face.get_combined_minimum_size().y + get_theme_stylebox("panel").get_minimum_size().y + 8.0
	_details_scroll.custom_minimum_size.y = minf(_details_content.get_combined_minimum_size().y,maxf(44.0,height-fixed_height))

## One line beside Details: treasury, short date, paused state and tool.
## The counts take the second line; the full fields stay in Details.
func _sync_phone_summary() -> void:
	_sync_counts()
	if _phone_summary == null or _details_button == null: return
	var paused := speed_label != null and speed_label.text == String(GameClock.SPEED_NAMES[GameClock.Speed.PAUSED])
	var parts := PackedStringArray()
	if not _editing: parts.append(funds_label.text)
	parts.append(_short_date(_full_date))
	if paused: parts.append("Paused")
	if not _no_tool: parts.append(_tool_name)
	_phone_summary.text = " · ".join(parts)
	_phone_summary.tooltip_text = "\n".join(PackedStringArray(([] if _editing else [funds_label.text]) + [_full_date, speed_label.text if speed_label != null else "", "Tool: " + _tool_name]))
	_details_button.text = "Less" if _details_open else ("Alerts" if not alert_label.text.is_empty() else "Details")
	_details_button.add_theme_color_override("font_color",UITheme.MONEY_NEGATIVE if not alert_label.text.is_empty() else UITheme.TEXT_PRIMARY)
	_details_button.tooltip_text = alert_label.text if not alert_label.text.is_empty() else "Tool, resident population, tourists, demand and simulation speed"


## Four bars, one per zone family, growing up for positive demand and down
## for negative demand around a shared baseline.
class DemandMeter:
	extends Control
	var demand := Vector3i.ZERO
	var agricultural_demand := 0

	func _init() -> void:
		custom_minimum_size = Vector2(METER_WIDTH,28)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_update_tooltip()

	func set_demand(value: Vector3i) -> void:
		demand = value
		_update_tooltip()
		queue_redraw()

	func set_agricultural_demand(value: int) -> void:
		agricultural_demand = clampi(value, -DEMAND_LIMIT, DEMAND_LIMIT)
		_update_tooltip()
		queue_redraw()

	func _update_tooltip() -> void:
		tooltip_text = "Demand: Residential %d · Commercial %d · Industrial %d · Agriculture %d\nPositive: room to grow. Negative: excess capacity." % [demand.x,demand.y,demand.z,agricultural_demand]

	func _draw() -> void:
		var colors: Array[Color] = [UITheme.ZONE_R, UITheme.ZONE_C, UITheme.ZONE_I, Zones.COLOR_AGR_HIGH]
		var values: Array[int] = [demand.x, demand.y, demand.z, agricultural_demand]
		var mid := size.y / 2.0
		var half := mid - 1.0
		var bar_w := size.x / 4.0 - 4.0
		draw_line(Vector2(0, mid), Vector2(size.x, mid), UITheme.BEVEL_DARK, 1.0)
		for i in 4:
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
	_phone_face = HBoxContainer.new()
	_phone_face.name = "PhoneFace"
	_phone_face.add_theme_constant_override("separation",8)
	_phone_face.hide()
	_phone_text = VBoxContainer.new()
	_phone_text.name = "PhoneLines"
	_phone_text.add_theme_constant_override("separation",0)
	_phone_text.alignment = BoxContainer.ALIGNMENT_CENTER
	_phone_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_face.add_child(_phone_text)
	_phone_row = HBoxContainer.new()
	_phone_row.name = "PhoneSummary"
	_phone_row.add_theme_constant_override("separation",8)
	_phone_row.hide()
	# The phone face is two small-type lines beside a 44-unit Details target.
	_phone_summary = UIFactory.make_label("$0 · —",UITheme.FONT_SMALL)
	_phone_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_phone_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phone_row.add_child(_phone_summary)
	_phone_text.add_child(_phone_row)
	_column.add_child(_phone_face)
	_metrics_row = HFlowContainer.new()
	_metrics_row.add_theme_constant_override("h_separation",16)
	_metrics_row.add_theme_constant_override("v_separation",8)
	_column.add_child(_metrics_row)
	tool_label = _cell(_metrics_row,"Tool: none",0)
	funds_label = _cell(_metrics_row,"$0",0,UITheme.MONEY_POSITIVE)
	funds_label.tooltip_text = "City treasury"
	date_label = _cell(_metrics_row,"—",0)
	# One flow item keeps the counts together even when other metrics wrap.
	_counts_row = HBoxContainer.new()
	_counts_row.name = "PopulationAndTourists"
	_counts_row.add_theme_constant_override("separation",16)
	_metrics_row.add_child(_counts_row)
	population_label = _cell(_counts_row,"Pop: 0",0)
	tourists_label = _cell(_counts_row,"Tourists: 0",0)
	_sync_counts()
	_demand_caption = UIFactory.make_label("R / C / I / A",UITheme.FONT_SMALL)
	_demand_caption.name = "DemandCaption"
	_metrics_row.add_child(_demand_caption)
	demand_meter = DemandMeter.new()
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
	_available_width = available_width
	custom_minimum_size.x = 0
	_metrics_row.custom_minimum_size.x = 0
	# A long tool name is cut with an ellipsis (full name in the tooltip)
	# rather than wrapping and growing the row.
	tool_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tool_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tool_reservation = minf(220.0,available_width * 0.35)
	_sync_counts()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _fit_metrics()


func set_tool_text(text: String) -> void:
	_no_tool = text == "none" or text.is_empty()
	_tool_name = "None" if _no_tool else text
	tool_label.text = "Tool: " + _tool_name
	tool_label.tooltip_text = tool_label.text
	# Before founding, an empty tool cell says nothing worth reading.
	tool_label.visible = not (_editing and _no_tool)
	_sync_phone_summary()


func set_funds(funds: int) -> void:
	funds_label.text = ("-$" if funds < 0 else "$") + UIFactory.commafy(funds)
	funds_label.add_theme_color_override("font_color",
		UITheme.MONEY_NEGATIVE if funds < 0 else UITheme.MONEY_POSITIVE)
	_sync_phone_summary()


func set_date(text: String) -> void:
	_full_date = text
	date_label.text = text
	date_label.tooltip_text = text
	_sync_phone_summary()


func set_population(population: int) -> void:
	_population = population
	_sync_counts()


func set_tourists(value: int) -> void:
	_tourists = value
	_sync_counts()


## Exact counts remain in tooltips when the face needs compact text.
func _sync_counts() -> void:
	if _counts_row == null: return
	_counts_row.visible = not (_phone and _editing)
	tourists_label.visible = not _editing
	if not _editing:
		population_label.tooltip_text = "Permanent residents: " + UIFactory.commafy(_population) + _population_details
		tourists_label.tooltip_text = "Current tourists: " + UIFactory.commafy(_tourists) + " (overnight guests and day visitors)"
	_fit_metrics()


func _set_count_texts(compact: bool) -> void:
	if _editing: return
	population_label.text = "Pop: " + (_compact_count(_population) if compact else UIFactory.commafy(_population))
	tourists_label.text = "Tourists: " + (_compact_count(_tourists) if compact else UIFactory.commafy(_tourists))


## Keep the closed footer at one line of metrics (one face plus counts on a
## phone) by applying only as many space savings as the width requires.
## The emergency action is excluded: it legitimately takes its own row.
func _fit_metrics() -> void:
	if demand_meter == null: return
	var available := _content_width()
	if _phone or is_inf(available):
		_apply_compact(0)
		if _phone and not _editing and _counts_width() > available - _details_width():
			_set_count_texts(true)
		return
	for level in COMPACT_LEVELS:
		_apply_compact(level)
		if _metrics_width() <= available: return


func _apply_compact(level: int) -> void:
	tool_label.text = ("Tool: " if level < 3 else "") + _tool_name
	tool_label.custom_minimum_size.x = _tool_reservation if level < 1 else minf(_tool_reservation,_ink_width(tool_label))
	date_label.text = _full_date if level < 2 else _short_date(_full_date)
	_demand_caption.visible = level < 4
	_set_count_texts(level >= 5)
	demand_meter.custom_minimum_size.x = METER_WIDTH if level < 6 else METER_COMPACT_WIDTH


## The footer's content width, or INF before the shell has laid it out.
func _content_width() -> float:
	var width := _available_width if _available_width > 0.0 else INF
	if is_inside_tree() and size.x > 0.0: width = minf(width,size.x)
	if is_inf(width): return width
	return width - get_theme_stylebox("panel").get_minimum_size().x


func _metrics_width() -> float:
	var total := 0.0
	var items := 0
	for child: Node in _metrics_row.get_children():
		var control := child as Control
		if control == null or not control.visible or control == emergency_button: continue
		total += _counts_width() if control == _counts_row else maxf(control.custom_minimum_size.x,control.get_minimum_size().x)
		items += 1
	return total + float(maxi(items-1,0) * _metrics_row.get_theme_constant("h_separation"))


func _counts_width() -> float:
	var total := 0.0
	var items := 0
	for label: Label in [population_label,tourists_label]:
		if not label.visible: continue
		total += _ink_width(label)
		items += 1
	return total + float(maxi(items-1,0) * _counts_row.get_theme_constant("separation"))


func _details_width() -> float:
	if _details_button == null: return 0.0
	return _details_button.get_combined_minimum_size().x + float(_phone_face.get_theme_constant("separation"))


## Natural one-line width of a label's current text, including its style.
static func _ink_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var ink := font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
	var style := label.get_theme_stylebox("normal")
	return ceilf(ink + (style.get_minimum_size().x if style != null else 0.0))


## "January 1900" becomes "Jan 1900"; other text is unchanged.
static func _short_date(text: String) -> String:
	var space := text.find(" ")
	if space > 3 and GameClock.MONTH_NAMES.has(text.substr(0,space)):
		return text.substr(0,3) + text.substr(space)
	return text


## Three significant digits: 7.89K, 123K, 2.15B.
static func _compact_count(value: int) -> String:
	for tier: Array in [[1000000000,"B"],[1000000,"M"],[1000,"K"]]:
		# 999,500 reads as 1M rather than 1000K.
		if value >= int(tier[0]) - int(tier[0]) / 2000:
			var scaled := float(value)/float(tier[0])
			var text := "%.0f" % scaled if scaled >= 100.0 else ("%.1f" % scaled if scaled >= 10.0 else "%.2f" % scaled)
			if text.contains("."): text = text.trim_suffix("0").trim_suffix("0").trim_suffix(".")
			return text + tier[1]
	return str(value)


func set_demand(demand: Vector3i) -> void:
	demand_meter.set_demand(demand)


## Independent scalar: saved RCI demand remains three components.
func set_agricultural_demand(value: int) -> void:
	demand_meter.set_agricultural_demand(value)


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
	_population = 0
	_population_details = ""
	_tourists = 0
	set_emergency_available(false)
	# There is no treasury before founding.
	funds_label.visible = false
	tool_label.visible = not _no_tool
	funds_label.text = "—"
	funds_label.add_theme_color_override("font_color", UITheme.MONEY_NEUTRAL)
	_full_date = "Shaping the land"
	date_label.text = _full_date
	date_label.tooltip_text = ""
	population_label.text = city_name
	# No earlier city's summary while the land is shaped.
	population_label.tooltip_text = "The city's name. Found the city to start its clock and treasury."
	set_demand(Vector3i.ZERO)
	set_agricultural_demand(0)
	set_speed(GameClock.Speed.PAUSED)
	set_alerts(PackedStringArray())
	_sync_phone_summary()


## Read every field from the running simulation.
func refresh(sim: Simulation) -> void:
	if sim == null or sim.city == null:
		return
	_editing = false
	funds_label.visible = true
	tool_label.visible = true
	set_funds(sim.city.funds)
	set_date(sim.date_text())
	set_population(sim.stats.total_population())
	set_tourists(sim.stats.tourists)
	set_demand(sim.stats.demand)
	set_agricultural_demand(sim.stats.demand_agricultural)
	_population_details = ""
	var statistics := sim.get_system(&"statistics")
	if statistics != null and statistics.has_method("status_lines"):
		# Built from the city as it is now, so it never contradicts the bar.
		var lines: Array = statistics.call("status_lines_now") if statistics.has_method("status_lines_now") \
			else statistics.call("status_lines")
		_population_details = ("\n" + "\n".join(PackedStringArray(lines))) if not lines.is_empty() else ""
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
	return "%s | %s | %s | %s | %s | %s | %s" % ["Tool: " + _tool_name, funds_label.text, _full_date,
		population_label.text if _editing else "Pop: " + UIFactory.commafy(_population),
		"Tourists: " + UIFactory.commafy(_tourists), speed_label.text, alert_label.text]
