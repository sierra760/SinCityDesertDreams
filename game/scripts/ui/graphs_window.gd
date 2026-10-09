# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Graphs window: monthly histories from the statistics system drawn as
## overlaid lines over a one, ten or hundred year span.
class_name GraphsWindow
extends Control

signal closed

const RANGES: Array[int] = [1, 10, 100]
const PALETTE: Array[Color] = [
	Color("17806c"), Color("c79a3a"), Color("3f6fb0"), Color("9a3b1a"),
	Color("6a3d9a"), Color("3f9d3f"), Color("b03f6f"), Color("2a2a22"),
]
const SERIES_LABELS := {
	&"population": "Population", &"residents": "Residential", &"commercial": "Commercial",
	&"industrial": "Industrial", &"money": "Funds", &"crime": "Crime", &"pollution": "Pollution",
	&"land_value": "Land Value", &"traffic": "Traffic", &"power_percent": "Power spare %",
	&"water_percent": "Water spare %", &"unemployment": "Unemployment", &"health": "Life expectancy",
	&"education": "Education", &"demand_residential": "Residential demand",
	&"demand_commercial": "Commercial demand", &"demand_industrial": "Industrial demand",
	&"transit_riders": "Transit riders",
}

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _range_years := 10
var _status_label: Label
var _picker: GridContainer
var _series_boxes: Dictionary = {}     ## name -> CheckBox
var _range_buttons: Dictionary = {}    ## years -> Button
var _canvas: GraphCanvas
var _legend_label: Label
var _scale_label: Label

## Shown under the plot when several series each use their own scale.
const OWN_SCALE_CAPTION := "Each line uses its own scale; current values at right"


## The plot area. Holds the sampled series and turns them into screen lines.
class GraphCanvas extends Control:
	const PAD_LEFT := 52.0
	const PAD_RIGHT := 64.0
	const PAD_TOP := 12.0
	const PAD_BOTTOM := 22.0
	const GRID_LINES := 4

	## [{name: StringName, label: String, values: PackedInt32Array, color: Color}]
	var series: Array[Dictionary] = []
	var months := 12

	func _init() -> void:
		custom_minimum_size = Vector2(260, 220)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func set_series(rows: Array[Dictionary], span_months: int) -> void:
		series = rows
		months = maxi(span_months, 2)
		queue_redraw()

	func plot_rect() -> Rect2:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			s = custom_minimum_size
		return Rect2(PAD_LEFT, PAD_TOP, maxf(s.x - PAD_LEFT - PAD_RIGHT, 1.0), maxf(s.y - PAD_TOP - PAD_BOTTOM, 1.0))

	## Lowest and highest value across every drawn series, widened so a flat
	## line still has room.
	func value_range() -> Vector2i:
		var lo := 0
		var hi := 0
		var any := false
		for row in series:
			var values: PackedInt32Array = row["values"]
			for v in values:
				if not any:
					lo = v
					hi = v
					any = true
				else:
					lo = mini(lo, v)
					hi = maxi(hi, v)
		if hi <= lo:
			hi = lo + 1
		return Vector2i(lo, hi)

	## Whether each series is scaled to its own low and high. One shared axis
	## would flatten small series beside large ones, so several series each
	## fill the plot and the shared axis numbers are hidden.
	func own_scales() -> bool:
		return series.size() > 1

	## The value range one series is drawn against.
	func range_of(row: Dictionary) -> Vector2i:
		if not own_scales():
			return value_range()
		var values: PackedInt32Array = row["values"]
		if values.is_empty():
			return Vector2i(0, 1)
		var lo := values[0]
		var hi := values[0]
		for v in values:
			lo = mini(lo, v)
			hi = maxi(hi, v)
		if hi <= lo:
			# A flat line sits mid-height rather than on the floor.
			return Vector2i(lo - 1, lo + 1)
		return Vector2i(lo, hi)

	## A value as the axis and end labels print it: dollars for Funds.
	static func value_text(name: StringName, value: int) -> String:
		if name == &"money":
			return NoticeLines.money(value)
		return UIFactory.commafy_signed(value)

	## Screen points of one series' polyline, newest sample at the right edge.
	func points_for(name: StringName) -> PackedVector2Array:
		var out := PackedVector2Array()
		for row in series:
			if row["name"] != name:
				continue
			var values: PackedInt32Array = row["values"]
			if values.is_empty():
				return out
			var rect := plot_rect()
			var range_v := range_of(row)
			var span := float(range_v.y - range_v.x)
			var step := rect.size.x / float(months - 1)
			var first := months - values.size()
			for i in values.size():
				var x := rect.position.x + float(first + i) * step
				var t := float(values[i] - range_v.x) / span
				var y := rect.position.y + rect.size.y * (1.0 - t)
				out.append(Vector2(x, y))
		return out

	func _draw() -> void:
		var rect := plot_rect()
		var font := get_theme_default_font()
		var font_size := UITheme.FONT_SMALL
		draw_rect(rect, UITheme.BEVEL_LIGHT, true)
		draw_rect(rect, UITheme.BEVEL_DARK, false, 1.0)
		var range_v := value_range()
		# Axis numbers only when every line shares the axis; dollars when the
		# one line is Funds.
		var axis_name: StringName = series[0]["name"] if series.size() == 1 else &""
		# A narrow range rounds several grid lines to one number; label it once.
		var labelled := {}
		for i in GRID_LINES + 1:
			var t := float(i) / float(GRID_LINES)
			var y := rect.position.y + rect.size.y * (1.0 - t)
			if i > 0 and i < GRID_LINES:
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), UITheme.DIVIDER, 1.0)
			if own_scales():
				continue
			var value := int(round(float(range_v.x) + float(range_v.y - range_v.x) * t))
			if labelled.has(value):
				continue
			labelled[value] = true
			draw_string(font, Vector2(2.0, y + 4.0), value_text(axis_name, value),
				HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 4.0, font_size, UITheme.TEXT_MUTED)
		var years := maxi(months / GameClock.MONTHS_PER_YEAR, 1)
		draw_string(font, Vector2(rect.position.x, rect.end.y + 16.0), "%d year%s" % [years, "" if years == 1 else "s"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.TEXT_MUTED)
		draw_string(font, Vector2(rect.end.x - 30.0, rect.end.y + 16.0), "now",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.TEXT_MUTED)
		for row in series:
			var points := points_for(row["name"])
			var color: Color = row["color"]
			if points.size() >= 2:
				draw_polyline(points, color, 2.0, true)
			if points.size() >= 1:
				var last := points[points.size() - 1]
				draw_circle(last, 3.0, color)
				var values: PackedInt32Array = row["values"]
				draw_string(font, Vector2(rect.end.x + 4.0, last.y + 4.0), value_text(row["name"], values[values.size() - 1]),
					HORIZONTAL_ALIGNMENT_LEFT, PAD_RIGHT - 4.0, font_size, color)
		var legend_y := rect.position.y + 14.0
		for row in series:
			var color: Color = row["color"]
			draw_rect(Rect2(rect.position.x + 6.0, legend_y - 8.0, 10.0, 10.0), color, true)
			draw_string(font, Vector2(rect.position.x + 20.0, legend_y), String(row["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.TEXT_PRIMARY)
			legend_y += 14.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Graphs")
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
	var statistics := _statistics()
	_ensure_picker(statistics)
	if statistics == null:
		_status_label.text = "No city loaded"
	else:
		_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()]
	for years: int in _range_buttons:
		var button: Button = _range_buttons[years]
		button.add_theme_stylebox_override("normal", UITheme.button_stylebox(years == _range_years))
		button.add_theme_color_override("font_color", UITheme.TITLE_TEXT if years == _range_years else UITheme.TEXT_PRIMARY)
	var rows: Array[Dictionary] = []
	var index := 0
	for name: StringName in _series_boxes:
		var box: CheckBox = _series_boxes[name]
		if not box.button_pressed:
			continue
		var values := PackedInt32Array()
		if statistics != null:
			values = statistics.call("series", name, _range_years)
		rows.append({
			"name": name,
			"label": _label_of(name),
			"values": values,
			"color": PALETTE[index % PALETTE.size()],
		})
		index += 1
	_canvas.set_series(rows, _range_years * GameClock.MONTHS_PER_YEAR)
	var legend: Array[String] = []
	for row in rows:
		var values: PackedInt32Array = row["values"]
		var current := "-" if values.is_empty() else GraphCanvas.value_text(row["name"], values[values.size() - 1])
		legend.append("%s: %s" % [String(row["label"]), current])
	_legend_label.text = ", ".join(legend) if not legend.is_empty() else "No series selected"
	_scale_label.visible = _canvas.own_scales()


# ── Public helpers ───────────────────────────────────────────────────────

func set_series_enabled(name: StringName, on: bool) -> void:
	if _series_boxes.has(name):
		var box: CheckBox = _series_boxes[name]
		box.button_pressed = on


func selected_series() -> Array[StringName]:
	var out: Array[StringName] = []
	for name: StringName in _series_boxes:
		var box: CheckBox = _series_boxes[name]
		if box.button_pressed:
			out.append(name)
	return out


func set_range_years(years: int) -> void:
	_range_years = years if years in RANGES else RANGES[0]
	refresh()


func range_years() -> int:
	return _range_years


func legend_text() -> String:
	return _legend_label.text


## The own-scale caption, or "" while one shared axis is in use.
func scale_caption() -> String:
	return _scale_label.text if _scale_label.visible else ""


func canvas() -> GraphCanvas:
	return _canvas


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(_status_label)
	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN)
	_body.add_child(columns)

	var left := VBoxContainer.new()
	left.add_child(UIFactory.make_section_header("Series"))
	_picker = GridContainer.new()
	_picker.columns = 1
	left.add_child(_picker)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var range_row := UIFactory.WrappingActions.new()
	var span := UIFactory.make_label("Span")
	# Before entering the tree, inherited theme lookup still uses the engine font.
	span.custom_minimum_size.x = ceilf(UITheme.DISPLAY_FONT.get_string_size(span.text,HORIZONTAL_ALIGNMENT_LEFT,-1,UITheme.FONT_BODY).x)
	range_row.add_child(span)
	for years in RANGES:
		var button := UIFactory.make_button("%d yr" % years)
		button.pressed.connect(set_range_years.bind(years))
		range_row.add_child(button)
		_range_buttons[years] = button
	right.add_child(range_row)
	_canvas = GraphCanvas.new()
	right.add_child(_canvas)
	_scale_label = UIFactory.make_label(OWN_SCALE_CAPTION, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_scale_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scale_label.custom_minimum_size = Vector2(0, 0)
	_scale_label.visible = false
	right.add_child(_scale_label)
	_legend_label = UIFactory.make_label("No series selected", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_legend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend_label.custom_minimum_size = Vector2(0, 0)
	right.add_child(_legend_label)
	columns.add_child(right)


## The picker lists whatever the statistics system offers; it is filled the
## first time a system is seen and kept afterwards.
func _ensure_picker(statistics: SimSystem) -> void:
	if not _series_boxes.is_empty():
		return
	var names: Array = []
	if statistics != null:
		names = statistics.call("names")
	else:
		for n in StatisticsParams.SERIES:
			names.append(n)
	for n in names:
		var name := StringName(String(n))
		var box := CheckBox.new()
		box.custom_minimum_size.y = 44
		box.text = _label_of(name)
		box.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		box.toggled.connect(_on_series_toggled)
		_picker.add_child(box)
		_series_boxes[name] = box
	if _series_boxes.has(&"population"):
		var first: CheckBox = _series_boxes[&"population"]
		first.set_pressed_no_signal(true)


static func _label_of(name: StringName) -> String:
	return String(SERIES_LABELS.get(name, String(name).capitalize()))


func _statistics() -> SimSystem:
	if _sim == null or _sim.city == null:
		return null
	return _sim.get_system(&"statistics")


func _on_series_toggled(_on: bool) -> void:
	refresh()


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
