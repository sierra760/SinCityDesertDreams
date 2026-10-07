# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## City Maps window: picks the data overlay drawn over the map and explains
## its colours.
class_name CityMapsWindow
extends Control

signal closed
signal overlay_selected(kind: StringName)

const OVERLAY_LABELS := {
	&"": "None", &"zones": "Zones", &"power": "Power", &"water": "Water", &"crime": "Crime",
	&"pollution": "Pollution", &"land_value": "Land Value", &"traffic": "Traffic",
	&"police": "Police Coverage", &"fire": "Fire Coverage", &"density": "Density", &"growth": "Growth",
}

var _sim: Simulation
var _presentation: CityPresentationController
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _selected: StringName = &""
var _status_label: Label
var _buttons: Dictionary = {}    ## kind -> Button
var _legend_box: VBoxContainer
var _legend_lines: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("City Maps")
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


## Attach the presentation controller and adopt the layer it already draws.
## Binding never changes the active overlay or its saved preference.
func bind_presentation(controller: CityPresentationController) -> void:
	_presentation = controller
	if _presentation != null:
		_selected = _presentation.get_overlay()
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
	if _sim != null and _sim.city != null:
		_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()]
	else:
		_status_label.text = "No city loaded"
	if _presentation != null and _presentation.get_overlay() != _selected:
		_selected = _presentation.get_overlay()
	for kind: StringName in _buttons:
		var button: Button = _buttons[kind]
		var active := kind == _selected
		button.add_theme_stylebox_override("normal", UITheme.button_stylebox(active))
		button.add_theme_color_override("font_color", UITheme.TITLE_TEXT if active else UITheme.TEXT_PRIMARY)
	_refresh_legend()


# ── Public helpers ───────────────────────────────────────────────────────

func select_overlay(kind: StringName) -> void:
	if kind == &"none":
		kind = &""
	if kind != &"" and not CityOverlaySampler.LAYERS.has(kind):
		return
	_selected = kind
	if _presentation != null:
		_presentation.set_overlay(kind)
	overlay_selected.emit(kind)
	refresh()


func selected_overlay() -> StringName:
	return _selected


func legend_text() -> String:
	return "; ".join(_legend_lines)


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_body.add_child(_status_label)
	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN)
	_body.add_child(columns)
	var picker := VBoxContainer.new()
	picker.add_child(UIFactory.make_section_header("Overlay"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN_COMPACT)
	grid.add_theme_constant_override("v_separation", UITheme.MARGIN_COMPACT)
	var kinds: Array[StringName] = [&""]
	for k in CityOverlaySampler.LAYERS:
		kinds.append(k)
	for kind in kinds:
		var button := UIFactory.make_button(String(OVERLAY_LABELS.get(kind, String(kind).capitalize())))
		button.custom_minimum_size.x = 120
		button.pressed.connect(select_overlay.bind(kind))
		grid.add_child(button)
		_buttons[kind] = button
	picker.add_child(grid)
	columns.add_child(picker)
	var legend := VBoxContainer.new()
	legend.custom_minimum_size = Vector2(200, 0)
	legend.add_child(UIFactory.make_section_header("Legend"))
	_legend_box = VBoxContainer.new()
	_legend_box.add_theme_constant_override("separation", 2)
	legend.add_child(_legend_box)
	columns.add_child(legend)


## The legend uses the same palette as the 3D overlay sampler.
func _refresh_legend() -> void:
	for child in _legend_box.get_children():
		_legend_box.remove_child(child)
		child.queue_free()
	_legend_lines.clear()
	var entries := CityOverlaySampler.legend_entries(_selected)
	for entry in entries:
		var color: Color = entry[0]
		var caption: String = entry[1]
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(14, 14)
		row.add_child(swatch)
		row.add_child(UIFactory.make_label(caption, UITheme.FONT_SMALL))
		_legend_box.add_child(row)
		_legend_lines.append(caption)


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
