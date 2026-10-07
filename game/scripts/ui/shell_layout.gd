# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Places the in-game chrome (menu bar, toolbar, footer, minimap and
## inspector) inside the display's safe bounds, shows or hides it with the
## city, and runs the phone layout's collapsible Tools drawer.
class_name GameShellLayout
extends Node

## True when the display is classified as a phone (see `DisplayLayout.is_phone`).
var phone_layout := false
## Whether the phone Tools drawer is showing.
var phone_tools_open := false
var _host: GameHost
var _pending := false


func _init(host: GameHost) -> void:
	_host = host
	name = "ShellLayout"


## Create the menu bar, toolbar, footer, cursor caption and inspector on
## `layer`. The host connects their signals.
func build_chrome(layer: CanvasLayer) -> void:
	var menu_bar := GameMenuBar.new()
	_host.menu_bar = menu_bar
	menu_bar.set_quit_closes_city(not _host.can_quit_application())
	menu_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	menu_bar.offset_bottom = GameMenuBar.BAR_HEIGHT
	layer.add_child(menu_bar)
	var toolbar := Toolbar.new()
	_host.toolbar = toolbar
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	toolbar.offset_top = GameMenuBar.BAR_HEIGHT
	toolbar.offset_right = Toolbar.WIDTH
	toolbar.offset_bottom = -StatusBar.BAR_HEIGHT
	layer.add_child(toolbar)
	menu_bar.set_shown(&"city_found", false)
	var status_bar := StatusBar.new()
	_host.status_bar = status_bar
	status_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status_bar.offset_top = -StatusBar.BAR_HEIGHT
	layer.add_child(status_bar)
	var caption := Label.new()
	_host.cursor_caption_3d = caption
	caption.name = "CursorCaption3D"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.hide()
	layer.add_child(caption)
	var query_panel := QueryPanel.new()
	_host.query_panel = query_panel
	query_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	query_panel.offset_left = -(QueryPanel.PANEL_WIDTH + 8)
	query_panel.offset_right = -8
	query_panel.offset_top = GameMenuBar.BAR_HEIGHT + 8
	query_panel.offset_bottom = GameMenuBar.BAR_HEIGHT + 8
	layer.add_child(query_panel)


## Reflow the chrome for new display metrics (size, scale, safe area or
## keyboard) and remember the window settings they carry.
func apply_metrics(metrics: Dictionary) -> void:
	if is_instance_valid(_host.presentation): _host.cancel_map_gesture()
	if _host.is_exploring(): _host.exploration.suspend()
	if _host.toolbar == null or metrics.is_empty():
		return
	var bounds: Rect2 = metrics["logical_rect"]
	phone_layout = DisplayLayout.is_phone(metrics)
	phone_tools_open = false
	_host.menu_bar.set_phone_layout(phone_layout)
	_host.status_bar.set_phone_layout(phone_layout)
	update_phone_tools()
	_host.title_screen.apply_layout(bounds)
	_host.toolbar.apply_layout(bool(metrics["compact"]))
	_host.toolbar.offset_right = _host.toolbar.custom_minimum_size.x
	_host.new_city_dialog.apply_layout(bool(metrics["compact"]))
	_host.status_bar.apply_layout(bounds.size.x)
	update_minimap_visibility()
	schedule()
	var display := _host.display_layout
	_host.prefs.defer("ui_scale", display.ui_scale)
	_host.prefs.defer("fullscreen", display.fullscreen)
	_host.prefs.defer("windowed_size", display.windowed_size)
	_host.prefs.defer("maximized", display.maximized)
	_host.prefs.refresh_options_window(metrics)
	apply_popups(_host.menu_bar)
	_host.sync_3d_cursor()


## Measure the chrome once its sizes have settled, at the end of the frame.
func schedule() -> void:
	if _pending:
		return
	_pending = true
	_measure.call_deferred()


func _measure() -> void:
	_pending = false
	var menu_bar := _host.menu_bar
	var status_bar := _host.status_bar
	var toolbar := _host.toolbar
	var query_panel := _host.query_panel
	var metrics := _host.display_layout.metrics
	var bounds := _host.display_layout.logical_rect()
	var full: Rect2 = metrics.get("full_logical_rect",bounds)
	menu_bar.offset_left = bounds.position.x
	menu_bar.offset_right = bounds.end.x - full.size.x
	menu_bar.offset_top = bounds.position.y
	menu_bar.offset_bottom = bounds.position.y + GameMenuBar.BAR_HEIGHT
	status_bar.offset_left = bounds.position.x
	status_bar.offset_right = bounds.end.x - full.size.x
	status_bar.apply_phone_height_limit(maxf(109.0,bounds.size.y-menu_bar.size.y-200.0))
	# Anchored size includes the previous safe/keyboard inset. Always measure
	# content so dismissing a keyboard or wrapped row restores natural height.
	var footer_height := maxf(StatusBar.BAR_HEIGHT,status_bar.get_combined_minimum_size().y)
	status_bar.offset_top = bounds.end.y - full.size.y - footer_height
	status_bar.offset_bottom = bounds.end.y - full.size.y
	# The footer's face reaches the mobile display edge; its text, buttons and
	# hit rectangle keep the safe/keyboard bounds used by the rest of the UI.
	var footer_edge_fill := Vector3.ZERO
	if bool(metrics.get("mobile",false)):
		var keyboard := float(metrics.get("keyboard_height_px",0)) / float(metrics.get("scale",1.0))
		footer_edge_fill = Vector3(bounds.position.x-full.position.x,full.end.x-bounds.end.x,maxf(0.0,full.end.y-keyboard-bounds.end.y))
	status_bar.set_bottom_edge_fill(footer_edge_fill)
	toolbar.offset_left = bounds.position.x
	toolbar.offset_right = bounds.position.x + toolbar.custom_minimum_size.x
	toolbar.offset_top = bounds.position.y + menu_bar.size.y
	toolbar.offset_bottom = bounds.end.y - full.size.y - status_bar.size.y
	if is_instance_valid(_host.explore_hud): _host.explore_hud.set_chrome_insets(menu_bar.size.y,status_bar.size.y)
	update_explore_camera_chrome()
	_host.mini_map.apply_layout(bounds, menu_bar.size.y, status_bar.size.y, toolbar.size.x if toolbar.visible else 0.0)
	query_panel.offset_right = bounds.end.x - full.size.x - 8
	query_panel.set_meta("display_usable_rect",bounds)
	query_panel.offset_left = query_panel.offset_right - minf(QueryPanel.PANEL_WIDTH,maxf(44,bounds.size.x - 16))
	query_panel.offset_top = bounds.position.y + menu_bar.size.y + 8
	query_panel.offset_bottom = minf(bounds.end.y - status_bar.size.y - 8, query_panel.offset_top + 500)
	_host.presentation.refresh_query_pointer_hover()
	if _host.street_names != null: _host.street_names.refresh_layout()


## Open or close the phone Tools drawer. Ignored outside the phone layout.
func set_phone_tools_open(on: bool) -> void:
	if not phone_layout: return
	_host.cancel_map_gesture()
	phone_tools_open = on and _host.in_game and not _host.is_exploring() and not _host.is_input_blocked()
	if phone_tools_open: _host.query_panel.close()
	update_phone_tools()
	if not phone_tools_open: _host.display_layout.release_city_focus()
	schedule()


func update_phone_tools() -> void:
	var building := _host.in_game and not _host.is_exploring()
	_host.toolbar.visible = building and (not phone_layout or phone_tools_open)
	_host.menu_bar.set_phone_build_available(building,phone_tools_open,_host.stage == GameHost.Stage.PLAY)


## Keep the Explore camera's framing clear of the menu bar and footer.
func update_explore_camera_chrome() -> void:
	var exploration := _host.exploration
	if not is_instance_valid(exploration) or not is_instance_valid(exploration.camera_rig):
		return
	var view := _host.city_view_3d
	var scale := float(view.viewport.size.y) / maxf(view.container.size.y,1.0)
	var bounds := _host.display_layout.logical_rect()
	var full: Rect2 = _host.display_layout.metrics.get("full_logical_rect",bounds)
	exploration.camera_rig.set_chrome_insets((bounds.position.y + _host.menu_bar.size.y) * scale,(full.size.y - bounds.end.y + _host.status_bar.size.y) * scale)


## Register every window panel under `node` with the display layout, once.
func register_chrome(node: Node) -> void:
	if node is Control and node.has_meta("window_chrome") and not node.has_meta("display_registered"):
		var chrome: Dictionary = node.get_meta("window_chrome")
		_host.display_layout.register_window(chrome, node.get_meta("preferred_size", (node as Control).size.max((node as Control).get_combined_minimum_size())))
		node.set_meta("display_registered", true)
	for child in node.get_children():
		register_chrome(child)


## Register every popup window under `node` with the display layout.
func apply_popups(node: Node) -> void:
	if node is Window:
		_host.display_layout.register_popup(node)
	if node is OptionButton:
		_host.display_layout.register_popup(node.get_popup())
	for child in node.get_children(true):
		apply_popups(child)


## Show the city chrome while a city is open; hide it for the title screen.
func set_chrome_visible(on: bool) -> void:
	var menu_bar := _host.menu_bar
	_host.refresh_street_menus()
	phone_tools_open = false
	update_phone_tools()
	menu_bar.set_enabled(&"city_share",on)
	menu_bar.set_enabled(&"city_quit", on or _host.can_quit_application())
	if not on: _host.toolbar.hide()
	menu_bar.set_enabled(&"explore",on and _host.stage == GameHost.Stage.PLAY and not _host.is_exploring())
	_host.status_bar.visible = on
	update_minimap_visibility(on)
	if not on:
		_host.query_panel.close()


func update_minimap_visibility(on: bool = true) -> void:
	# Touch actions and the compact Explore panel reserve this corner. Keep
	# the preference so roomy layouts and returning to Build can restore it.
	var exploration := _host.exploration
	var reserved: bool = phone_layout or (_host.is_exploring() and (exploration.touch_controls_enabled() or bool(_host.display_layout.metrics.get("compact",false))))
	_host.mini_map.visible = on and _host.in_game and bool(_host.preferences.get("minimap",true)) and not reserved
