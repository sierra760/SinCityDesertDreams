# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Report and settings windows: each is created on first use, kept for reuse
## and stacked in the order it was opened.
class_name WindowManager
extends RefCounted

const SCRIPTS := {
	"budget": preload("res://scripts/ui/budget_window.gd"),
	"city_maps": preload("res://scripts/ui/city_maps_window.gd"),
	"graphs": preload("res://scripts/ui/graphs_window.gd"),
	"help": preload("res://scripts/ui/help_window.gd"),
	"industries": preload("res://scripts/ui/industries_window.gd"),
	"license": preload("res://scripts/ui/license_window.gd"),
	"neighbors": preload("res://scripts/ui/neighbors_window.gd"),
	"newspaper": preload("res://scripts/ui/newspaper_window.gd"),
	"options": preload("res://scripts/ui/options_window.gd"),
	"ordinances": preload("res://scripts/ui/ordinances_window.gd"),
	"population": preload("res://scripts/ui/population_window.gd"),
}
## Windows that can open before the city is founded.
const EDITING_WINDOWS: Array[String] = ["options", "help", "license"]

## name -> window, created on first use.
var windows: Dictionary = {}
## Open windows, front-most last.
var open_windows: Array[Control] = []
var _host: GameHost


func _init(host: GameHost) -> void:
	_host = host


## Show a window and bring it to the front. Returns null, with a status
## message, when the window does not exist or cannot open yet.
func open(window_name: String) -> Control:
	if _host.is_exploring(): _host.exploration.suspend()
	if _host.stage == GameHost.Stage.EDITING and not EDITING_WINDOWS.has(window_name):
		_host.show_message("%s opens once the city is founded." % String(GameMenuBar.WINDOW_TITLES.get(window_name, window_name.replace("_", " ").capitalize())))
		return null
	var w := window(window_name)
	if w == null:
		_host.status_bar.set_message("The %s window is not available." % window_name.replace("_", " "))
		return null
	if w.has_method("bind"):
		w.call("bind", _host.sim)
	if w is OptionsWindow:
		_host.prefs.refresh_options_window(_host.display_layout.metrics)
	if w.has_method("refresh"):
		w.call("refresh")
	w.call("open")
	_place(w)
	open_windows.erase(w)
	open_windows.append(w)
	var layer := _host.ui_layer if _host.in_game else _host.modal_layer
	if w.get_parent() != layer: w.reparent(layer)
	_place(w)
	layer.move_child(w, layer.get_child_count() - 1)
	return w


## The named window, created and connected on first use; null for an
## unknown name.
func window(window_name: String) -> Control:
	if windows.has(window_name):
		return windows[window_name]
	if not SCRIPTS.has(window_name):
		return null
	var w: Control = SCRIPTS[window_name].new()
	w.visible = false
	_host.ui_layer.add_child(w)
	_place(w)
	w.connect("closed", _on_window_closed.bind(w))
	if w is OptionsWindow:
		(w as OptionsWindow).option_changed.connect(_host.prefs.set_option)
	elif w is OrdinancesWindow:
		(w as OrdinancesWindow).ordinance_changed.connect(func(_key: StringName, _on: bool) -> void: _host.refresh_toolbar())
	elif w is CityMapsWindow:
		(w as CityMapsWindow).bind_presentation(_host.presentation)
	elif w is HelpWindow:
		(w as HelpWindow).sources_dialog.visibility_changed.connect(_host.sync_help_sources_hold)
	_host.shell.register_chrome(w)
	_host.shell.apply_popups(w)
	windows[window_name] = w
	return w


## Give a window the whole layer when it asked for full-rect anchors (its
## own centred panel then lands mid-screen), or centre it when it has no
## anchors of its own. Windows that placed themselves explicitly are left alone.
static func _place(w: Control) -> void:
	if w.anchor_right >= 1.0 and w.anchor_bottom >= 1.0 and w.anchor_left <= 0.0 and w.anchor_top <= 0.0:
		w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elif w.anchor_left == 0.0 and w.anchor_top == 0.0 and w.anchor_right == 0.0 and w.anchor_bottom == 0.0 \
			and w.offset_left == 0.0 and w.offset_top == 0.0:
		w.size = w.get_combined_minimum_size()
		w.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _on_window_closed(w: Control) -> void:
	open_windows.erase(w)
	_host.prefs.flush()
	if _host.title_screen.visible and open_windows.is_empty(): _host.title_screen.new_button.grab_focus()


func close_all() -> void:
	for w: Control in open_windows.duplicate():
		w.call("close")
	open_windows.clear()


func is_open(window_name: String) -> bool:
	return windows.has(window_name) and open_windows.has(windows[window_name])


## The front-most open window, or null.
func front() -> Control:
	return open_windows.back() if not open_windows.is_empty() else null


## Point every created window at the simulation of a newly bound city.
func bind_all(sim: Simulation) -> void:
	for w: Control in windows.values():
		if w.has_method("bind"):
			w.call("bind", sim)


## Redraw the open windows after a change they were not told about.
func refresh_open() -> void:
	for w: Control in open_windows:
		if w.has_method("refresh"): w.call("refresh")
