# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Applies the player's options to the game and writes them to the
## preference file. Values that change continuously (typing, slider drags,
## camera moves) are written once they settle.
class_name PreferencesController
extends RefCounted

## Seconds a rapidly repeated value waits before it is written.
const WRITE_DELAY := 0.3

var _host: GameHost
var _dirty := false
var _delay := 0.0


func _init(host: GameHost) -> void:
	_host = host


## Apply one option to the game and remember it.
func set_option(key: StringName, value: Variant) -> void:
	if _host.is_exploring() and key == &"zoom": return
	var view := _host.city_view_3d
	match key:
		&"mayor_name":
			var mayor := ViewPreferences.clean_mayor_name(value)
			# Typed one keystroke at a time; written once typing pauses.
			defer("mayor_name",mayor)
			_host.title_screen.set_mayor_name(mayor)
			if _host.in_game and _host.sim.city != null: _host.sim.city.mayor = ViewPreferences.mayor_credit(mayor)
		&"explore_character":
			var settings := _host.preferences.duplicate()
			settings["explore_character"] = value
			var character: String = ViewPreferences.sanitize(settings).explore_character
			if is_instance_valid(_host.exploration): _host.exploration.set_pedestrian_character(character)
			set_value("explore_character",character)
		&"control_bindings":
			_host.interrupt_map_input()
			_host.controls.configure(value)
			set_value("control_bindings",_host.controls.values())
			_host.menu_bar.set_bindings(_host.controls)
			_host.toolbar.controls = _host.controls
			_host.refresh_toolbar()
		&"explore_sensitivity", &"explore_invert_y":
			var settings := _host.preferences.duplicate()
			settings[String(key)] = value
			settings = ViewPreferences.sanitize(settings)
			_host.explore_hud.sensitivity = settings.explore_sensitivity
			_host.explore_hud.invert_y = settings.explore_invert_y
			# A slider drag reports every step; write once it settles.
			if key == &"explore_sensitivity": defer(String(key),settings[String(key)])
			else: set_value(String(key),settings[String(key)])
		&"render_quality", &"render_scale":
			var settings := _host.preferences.duplicate()
			settings[String(key)] = value
			settings = ViewPreferences.sanitize(settings)
			view.set_render_options(settings.render_quality, settings.render_scale)
			_host.shell.update_explore_camera_chrome()
			set_value(String(key), settings[String(key)])
		&"water_animation":
			view.set_water_animation(bool(value))
			set_value("water_animation",bool(value))
		&"tile_grid":
			view.set_tile_grid_visible(bool(value))
			set_value("tile_grid",bool(value))
		&"pause_in_background":
			set_value("pause_in_background",bool(value))
		&"music_enabled", &"effects_enabled", &"music_volume", &"effects_volume":
			var settings := _host.preferences.duplicate()
			settings[String(key)] = value
			settings = ViewPreferences.sanitize(settings)
			if _host.audio != null: _host.audio.apply_preferences(settings)
			# A volume slider reports every step; write once it settles.
			if String(key).ends_with("_volume"): defer(String(key),settings[String(key)])
			else: set_value(String(key),settings[String(key)])
		&"ui_scale":
			_host.display_layout.set_ui_scale(int(value))
			set_value("ui_scale", _host.display_layout.ui_scale)
		&"fullscreen":
			_host.display_layout.set_fullscreen(bool(value))
			set_value("fullscreen", _host.display_layout.fullscreen)
		&"labels":
			view.set_labels_visible(bool(value))
			set_value("labels", bool(value))
		&"button_labels":
			_host.toolbar.set_button_labels_visible(bool(value))
			_host.toolbar.offset_right = _host.toolbar.custom_minimum_size.x
			_host.shell.schedule()
			set_value("button_labels", bool(value))
		&"vehicles":
			set_value("vehicles", bool(value))
		&"minimap":
			set_value("minimap", bool(value))
			_host.shell.update_minimap_visibility()
		&"zoom": view.set_zoom_level(int(value))
		&"disasters_enabled": _host.sim.stats.disasters_enabled = bool(value)
		&"auto_budget": _host.sim.stats.auto_budget = bool(value)
	_host.menu_bar.set_checked(key, bool(value) if typeof(value) == TYPE_BOOL else true, null if typeof(value) == TYPE_BOOL else value)
	refresh_options_window()


## Current values for the Options window.
func option_values() -> Dictionary:
	var preferences := _host.preferences
	return {
		"mayor_name": preferences.get("mayor_name",""),
		"control_bindings": _host.controls.values(),
		"explore_character": preferences.get("explore_character","woman"),
		"explore_sensitivity": preferences.get("explore_sensitivity",1.0),
		"explore_invert_y": preferences.get("explore_invert_y",false),
		"water_animation": preferences.get("water_animation",true),
		"pause_in_background": preferences.get("pause_in_background",true),
		"music_enabled": preferences.get("music_enabled",true),
		"effects_enabled": preferences.get("effects_enabled",true),
		"music_volume": preferences.get("music_volume",0.8),
		"effects_volume": preferences.get("effects_volume",0.9),
		"tile_grid": _host.city_view_3d.tile_grid_visible,
		"render_quality": preferences.get("render_quality", "high"),
		"render_scale": preferences.get("render_scale", 100),
		"ui_scale": _host.display_layout.ui_scale,
		"effective_percent": _host.display_layout.metrics.get("effective_percent", 100.0),
		"fullscreen": _host.display_layout.fullscreen,
		"labels": _host.city_view_3d.labels_visible,
		"minimap": bool(preferences.get("minimap", true)),
		"vehicles": bool(preferences.get("vehicles", true)),
		"zoom": _host.city_view_3d.zoom_level(),
		"disasters_enabled": _host.sim.stats.disasters_enabled,
		"auto_budget": _host.sim.stats.auto_budget,
	}


## Show the current values in the Options window, if it exists. With
## `display_metrics`, also refresh its display-scale readout.
func refresh_options_window(display_metrics: Variant = null) -> void:
	var options := _host.windows.get("options") as OptionsWindow
	if options == null:
		return
	options.set_values(option_values())
	if display_metrics != null:
		options.set_display_metrics(display_metrics)


## Push the loaded preferences into the view, toolbar and menus.
func apply() -> void:
	var preferences := _host.preferences
	var view := _host.city_view_3d
	var menu_bar := _host.menu_bar
	_host.title_screen.set_mayor_name(String(preferences.get("mayor_name","")))
	menu_bar.set_bindings(_host.controls)
	_host.toolbar.controls = _host.controls
	view.set_water_animation(bool(preferences.get("water_animation",true)))
	view.set_tile_grid_visible(bool(preferences.get("tile_grid",true)))
	view.set_render_options(String(preferences.get("render_quality", "high")), int(preferences.get("render_scale", 100)))
	view.camera_size = float(preferences.get("size_3d", 72.0))
	view.quarter_turn = int(preferences.get("rotation_3d", 0))
	view.set_labels_visible(bool(preferences.get("labels", true)))
	_host.toolbar.set_button_labels_visible(bool(preferences.get("button_labels", true)))
	# Data overlays are a quick look, not a setting: every session starts on
	# the ordinary city so a forgotten overlay never hides traffic or buildings.
	_host.presentation.set_overlay(&"")
	menu_bar.set_checked(&"zoom", true, view.zoom_level())
	menu_bar.set_checked(&"labels", view.labels_visible)
	menu_bar.set_checked(&"button_labels", _host.toolbar.button_labels_visible)
	menu_bar.set_checked(&"vehicles", bool(preferences.get("vehicles", true)))
	menu_bar.set_checked(&"minimap", bool(preferences.get("minimap", true)))
	menu_bar.set_checked(&"overlay", true, _host.presentation.get_overlay())


## Remember a preference and write it now.
func set_value(key: String, value: Variant) -> void:
	_host.preferences[key] = value
	save()


## Record a rapidly repeated preference and write it after a short pause.
## Window close, quit, scene exit and app suspension flush it immediately.
func defer(key: String, value: Variant) -> void:
	_host.preferences[key] = value
	_dirty = true
	_delay = WRITE_DELAY


## Count down a deferred write; called every frame.
func advance(delta: float) -> void:
	if not _dirty:
		return
	_delay -= delta
	if _delay <= 0.0:
		save()


## Write any preference still waiting for its debounce delay.
func flush() -> void:
	if _dirty:
		save()


func save() -> void:
	_host.save_preferences()
	_dirty = false
