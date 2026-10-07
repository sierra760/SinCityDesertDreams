# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The top menu bar: City, Speed, View, Reports, Disasters and Help.
## Every item resolves to an action name plus an optional value, emitted as
## `action_requested`; the host does the work. Check items toggle themselves
## before emitting, radio items are set by the host through `set_checked`.
class_name GameMenuBar
extends MenuBar

signal action_requested(action: StringName, value: Variant)
signal popup_opened
signal tools_requested
signal inspect_requested

const BAR_HEIGHT := 44

const WINDOW_NAMES: Array[String] = ["budget", "graphs", "population", "industries",
	"ordinances", "newspaper", "city_maps", "neighbors"]
const WINDOW_TITLES := {
	"budget": "Budget", "graphs": "Graphs", "population": "Population",
	"industries": "Industries", "ordinances": "Ordinances", "newspaper": "Newspaper",
	"city_maps": "City Maps", "neighbors": "Neighbors",
}
const OVERLAY_TITLES := {
	&"": "None", &"zones": "Zones", &"power": "Power", &"water": "Water", &"crime": "Crime",
	&"pollution": "Pollution", &"land_value": "Land Value", &"traffic": "Traffic",
	&"police": "Police Coverage", &"fire": "Fire Coverage", &"density": "Density", &"growth": "Growth",
}

## "action|value" -> {menu: PopupMenu, id: int, kind: "item"|"check"|"radio", action, value}
var _entries: Dictionary = {}
var _by_id: Dictionary = {}
var _next_id := 1
var _menus: Dictionary = {}
var _phone_row: HBoxContainer
var _phone_menu: MenuButton
var phone_tools_button: Button
var phone_inspect_button: Button
var _phone := false

## Reuse the desktop PopupMenus and action registry in the phone menu.
## Reparenting keeps radio/check/disabled states and dynamic captions intact.
func set_phone_layout(on: bool) -> void:
	if on == _phone: return
	if _phone_row == null:
		_phone_row = HBoxContainer.new()
		_phone_row.name = "PhoneActions"
		_phone_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_phone_row.add_theme_constant_override("separation",8)
		phone_tools_button = UIFactory.make_button("Tools")
		phone_tools_button.pressed.connect(func() -> void: tools_requested.emit())
		_phone_row.add_child(phone_tools_button)
		phone_inspect_button = UIFactory.make_button("Inspect")
		phone_inspect_button.pressed.connect(func() -> void: inspect_requested.emit())
		_phone_row.add_child(phone_inspect_button)
		var space := Control.new()
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_phone_row.add_child(space)
		_phone_menu = MenuButton.new()
		_phone_menu.text = "Menu"
		_phone_menu.custom_minimum_size = Vector2(80,44)
		_phone_menu.theme = UITheme.control_theme()
		_phone_menu.get_popup().about_to_popup.connect(func() -> void: popup_opened.emit())
		_phone_row.add_child(_phone_menu)
		add_child(_phone_row)
	for popup: PopupMenu in _menus.values(): popup.hide()
	_phone_menu.get_popup().hide()
	_phone_menu.get_popup().clear(false)
	for title: String in _menus:
		var popup: PopupMenu = _menus[title]
		popup.reparent(_phone_menu.get_popup() if on else self)
		if on:
			_phone_menu.get_popup().add_submenu_node_item(title,popup)
		else:
			set_menu_title(get_menu_count()-1,title)
	_phone = on
	_phone_row.visible = on
	update_minimum_size()

func set_phone_build_available(on: bool, tools_open: bool = false, inspect_on: bool = true) -> void:
	if _phone_row == null: return
	phone_tools_button.disabled = not on
	phone_inspect_button.disabled = not on or not inspect_on
	phone_tools_button.text = "Close tools" if tools_open else "Tools"


func _init() -> void:
	name = "MenuBar"
	prefer_global_menu = false
	theme = UITheme.control_theme()
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_build()
	var background := Panel.new()
	background.name = "MenuSurface"
	background.show_behind_parent = true
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", UITheme.shell_stylebox())
	add_child(background)
	# MenuBar and phone buttons fill the 44-unit input region. Keep the
	# shell's bottom rule visible over their faces without shrinking targets.
	var border := Panel.new()
	border.name = "MenuBorder"
	border.z_index = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border_style := UITheme.shell_stylebox()
	border_style.draw_center = false
	border.add_theme_stylebox_override("panel", border_style)
	add_child(border)


func _build() -> void:
	var city := _menu("City")
	_item(city, "New City…", &"city_new")
	_accelerator(&"city_new", KEY_N)
	_item(city, "Found City", &"city_found")
	_item(city, "Load City…", &"city_load")
	_accelerator(&"city_load", KEY_O)
	_item(city, "Save City", &"city_save")
	_accelerator(&"city_save", KEY_S)
	_item(city, "Save City As…", &"city_save_as")
	_accelerator(&"city_save_as", KEY_S, true)
	_item(city, "Share City…", &"city_share")
	_item(city, "Import Classic City…", &"city_import")
	city.add_separator()
	_item(city, "Settings…", &"options")
	_accelerator(&"options", KEY_COMMA)
	_item(city, "Quit", &"city_quit")

	var speed := _menu("Speed")
	for s in GameClock.Speed.values():
		_radio(speed, String(GameClock.SPEED_NAMES[s]), &"speed", s)

	var view := _menu("View")
	_item(view, "Explore City", &"explore")
	view.add_separator()
	var zoom := _submenu(view, "Zoom")
	_item(zoom, "Zoom In", &"zoom_in")
	_item(zoom, "Zoom Out", &"zoom_out")
	zoom.add_separator()
	for level in UIFactory.ZOOM_NAMES.size():
		_radio(zoom, "%s [%d]" % [String(UIFactory.ZOOM_NAMES[level]).capitalize(),level+1], &"zoom", level)
	view.add_separator()
	_item(view, "Rotate [R]", &"rotate")
	_item(view, "Center on Map", &"recenter")
	_check(view, "Underground [U]", &"underground")
	_item(view,"Street Names",&"street_names")
	set_enabled(&"street_names",false)
	var overlays := _submenu(view, "Data Overlays")
	_radio(overlays, "None", &"overlay", &"")
	for kind in CityOverlaySampler.LAYERS:
		_radio(overlays, String(OVERLAY_TITLES.get(kind, String(kind).capitalize())), &"overlay", kind)
	view.add_separator()
	_check(view, "Show Button Labels", &"button_labels")
	var visibility := _submenu(view, "Show")
	_check(visibility, "Signs and Labels", &"labels")
	_check(visibility, "Traffic and Pedestrians", &"vehicles")
	_check(visibility, "Minimap", &"minimap")

	var windows := _menu("Reports")
	for w in WINDOW_NAMES:
		_item(windows, String(WINDOW_TITLES[w]), &"window", w)

	var disasters := _menu("Disasters")
	_item(disasters, "Go to Emergency", &"go_to_emergency")
	set_enabled(&"go_to_emergency", false)
	disasters.add_separator()
	_check(disasters, "Disasters Enabled", &"disasters_enabled")
	var trigger := _submenu(disasters, "Start a Disaster")
	for kind in DisasterParams.KINDS:
		_item(trigger, DisasterParams.display_name(kind), &"disaster", kind)

	var help := _menu("Help")
	_item(help, "Playing the Game…", &"help")
	_item(help, "Secret Codes…", &"cheats")
	_item(help, "About", &"about")


func _menu(title: String) -> PopupMenu:
	var m := PopupMenu.new()
	m.name = title
	add_child(m)
	set_menu_title(get_menu_count() - 1, title)
	m.id_pressed.connect(_on_id_pressed.bind(m))
	m.about_to_popup.connect(func() -> void: popup_opened.emit())
	_menus[title] = m
	return m

func set_bindings(bindings: ControlBindings) -> void:
	for entry: Dictionary in _entries.values():
		var caption := ""
		match entry.action:
			&"rotate": caption = "Rotate [%s]" % bindings.caption(&"rotate")
			&"underground": caption = "Underground [%s]" % bindings.caption(&"underground")
			&"speed":
				if int(entry.value) == GameClock.Speed.PAUSED:
					caption = "%s [%s]" % [String(GameClock.SPEED_NAMES[GameClock.Speed.PAUSED]), bindings.caption(&"pause")]
			&"zoom": caption = "%s [%s]" % [String(UIFactory.ZOOM_NAMES[int(entry.value)]).capitalize(),bindings.caption(StringName("zoom_%d" % (int(entry.value)+1)))]
		if not caption.is_empty():
			var menu: PopupMenu = entry.menu
			menu.set_item_text(menu.get_item_index(int(entry.id)),caption)


func _submenu(parent: PopupMenu, title: String) -> PopupMenu:
	var popup := PopupMenu.new()
	popup.name = title.replace(" ", "")
	parent.add_child(popup)
	parent.add_submenu_item(title, String(popup.name))
	popup.id_pressed.connect(_on_id_pressed.bind(popup))
	popup.about_to_popup.connect(func() -> void: popup_opened.emit())
	return popup


static func _key(action: StringName, value: Variant) -> String:
	return "%s|%s" % [String(action), str(value)]


func _register(menu: PopupMenu, kind: String, action: StringName, value: Variant) -> int:
	var id := _next_id
	_next_id += 1
	var entry := {"menu": menu, "id": id, "kind": kind, "action": action, "value": value}
	_entries[_key(action, value)] = entry
	_by_id[id] = entry
	return id


func _item(menu: PopupMenu, label: String, action: StringName, value: Variant = null) -> void:
	menu.add_item(label, _register(menu, "item", action, value))


## Show and accept a Cmd (macOS) or Ctrl chord for an item already added.
func _accelerator(action: StringName, keycode: Key, shift: bool = false) -> void:
	var entry: Dictionary = _entries[_key(action, null)]
	var menu: PopupMenu = entry["menu"]
	var chord := InputEventKey.new()
	chord.keycode = keycode
	chord.command_or_control_autoremap = true
	chord.shift_pressed = shift
	var shortcut := Shortcut.new()
	shortcut.events = [chord]
	menu.set_item_shortcut(menu.get_item_index(int(entry["id"])), shortcut)


func _check(menu: PopupMenu, label: String, action: StringName, value: Variant = null) -> void:
	menu.add_check_item(label, _register(menu, "check", action, value))


func _radio(menu: PopupMenu, label: String, action: StringName, value: Variant) -> void:
	menu.add_radio_check_item(label, _register(menu, "radio", action, value))


func _on_id_pressed(id: int, _menu: PopupMenu) -> void:
	if not _by_id.has(id):
		return
	var entry: Dictionary = _by_id[id]
	var action: StringName = entry["action"]
	var value: Variant = entry["value"]
	match String(entry["kind"]):
		"check":
			var on := not is_checked(action, value)
			set_checked(action, on, value)
			action_requested.emit(action, on)
		"radio":
			set_checked(action, true, value)
			action_requested.emit(action, value)
		_:
			action_requested.emit(action, value)


## Fire an action as if its item were clicked (keyboard shortcuts, tests).
## A disabled item does nothing, as it would under the mouse.
func press(action: StringName, value: Variant = null) -> void:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty():
		action_requested.emit(action, value)
		return
	if not is_enabled(action, value):
		return
	_on_id_pressed(int(entry["id"]), entry["menu"])


## iOS closes the current city because the OS owns application termination.
func set_quit_closes_city(on: bool) -> void:
	var entry: Dictionary = _entries[_key(&"city_quit", null)]
	var menu: PopupMenu = entry["menu"]
	menu.set_item_text(menu.get_item_index(int(entry["id"])), "Close City" if on else "Quit")


## Grey an item out (or back in). A hidden item keeps the choice for when
## it is shown again.
func set_enabled(action: StringName, on: bool, value: Variant = null) -> void:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty():
		return
	if entry.has("hidden"):
		entry["hidden"]["disabled"] = not on
		return
	var menu: PopupMenu = entry["menu"]
	menu.set_item_disabled(menu.get_item_index(int(entry["id"])), not on)


## A hidden item is never enabled.
func is_enabled(action: StringName, value: Variant = null) -> bool:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty() or entry.has("hidden"):
		return false
	var menu: PopupMenu = entry["menu"]
	return not menu.is_item_disabled(menu.get_item_index(int(entry["id"])))


## Remove a plain item from its menu (or restore it at its old position).
## PopupMenu has no per-item visibility or insertion, so the item is taken
## out with its caption, position and disabled state kept on the entry, and
## restoring re-adds the items that followed it after it.
func set_shown(action: StringName, on: bool, value: Variant = null) -> void:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty() or on != entry.has("hidden"):
		return
	var menu: PopupMenu = entry["menu"]
	var id := int(entry["id"])
	if on:
		var saved: Dictionary = entry["hidden"]
		entry.erase("hidden")
		var trailing: Array[Dictionary] = []
		while menu.item_count > int(saved["index"]):
			trailing.append(_take_item(menu, int(saved["index"])))
		menu.add_item(String(saved["text"]), id)
		menu.set_item_disabled(menu.item_count - 1, bool(saved["disabled"]))
		for item in trailing:
			_put_item(menu, item)
		return
	var index := menu.get_item_index(id)
	entry["hidden"] = {"text": menu.get_item_text(index), "index": index,
		"disabled": menu.is_item_disabled(index)}
	menu.remove_item(index)


static func _take_item(menu: PopupMenu, index: int) -> Dictionary:
	var item := {
		"separator": menu.is_item_separator(index), "text": menu.get_item_text(index),
		"id": menu.get_item_id(index), "submenu": menu.get_item_submenu_node(index),
		"checkable": menu.is_item_checkable(index), "radio": menu.is_item_radio_checkable(index),
		"checked": menu.is_item_checked(index), "disabled": menu.is_item_disabled(index),
		"shortcut": menu.get_item_shortcut(index), "tooltip": menu.get_item_tooltip(index),
	}
	menu.remove_item(index)
	return item


static func _put_item(menu: PopupMenu, item: Dictionary) -> void:
	var id := int(item["id"])
	if bool(item["separator"]):
		menu.add_separator(String(item["text"]), id)
		return
	var submenu: PopupMenu = item["submenu"]
	if submenu != null:
		menu.add_submenu_node_item(String(item["text"]), submenu, id)
	elif bool(item["radio"]):
		menu.add_radio_check_item(String(item["text"]), id)
	elif bool(item["checkable"]):
		menu.add_check_item(String(item["text"]), id)
	else:
		menu.add_item(String(item["text"]), id)
	var index := menu.item_count - 1
	menu.set_item_checked(index, bool(item["checked"]))
	menu.set_item_disabled(index, bool(item["disabled"]))
	menu.set_item_tooltip(index, String(item["tooltip"]))
	if item["shortcut"] != null:
		menu.set_item_shortcut(index, item["shortcut"])


func is_shown(action: StringName, value: Variant = null) -> bool:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	return not entry.is_empty() and not entry.has("hidden")


## Set a check item, or select one radio item of an action group.
func set_checked(action: StringName, on: bool, value: Variant = null) -> void:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty():
		return
	var menu: PopupMenu = entry["menu"]
	if String(entry["kind"]) == "radio":
		for k in _entries:
			var other: Dictionary = _entries[k]
			if other["action"] == action and String(other["kind"]) == "radio":
				var om: PopupMenu = other["menu"]
				om.set_item_checked(om.get_item_index(int(other["id"])), other["value"] == value and on)
		return
	menu.set_item_checked(menu.get_item_index(int(entry["id"])), on)


func is_checked(action: StringName, value: Variant = null) -> bool:
	var entry: Dictionary = _entries.get(_key(action, value), {})
	if entry.is_empty():
		return false
	var menu: PopupMenu = entry["menu"]
	return menu.is_item_checked(menu.get_item_index(int(entry["id"])))


func has_action(action: StringName, value: Variant = null) -> bool:
	return _entries.has(_key(action, value))


func menu_titles() -> Array[String]:
	var out: Array[String] = []
	for i in get_menu_count():
		out.append(get_menu_title(i))
	return out
