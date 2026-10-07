# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The construction toolbar: one icon button per player tool, grouped by
## `Tools.Group`. Buttons carry the tool name, price and lock reason as a
## tooltip; the active tool is drawn in the teal accent. The host listens to
## `tool_selected` and calls `refresh` when availability may have changed.
## Whole-map tools (the sea level) sit in their own block below their group
## and act on each press; the host applies them instead of selecting them.
## Editing-only tools (the sea level) show only before the city is founded.
##
## Before the city is founded the bar is in the EDITING stage: only the
## terrain group shows, its tools are free, and a panel above it offers
## Regenerate and Found City.
class_name Toolbar
extends PanelContainer

var controls := ControlBindings.new()

signal tool_selected(tool: int)
signal found_requested
signal regenerate_requested

enum Stage { EDITING, PLAY }

const WIDTH := 224
const COMPACT_WIDTH := 196
const COLUMNS := 2
const BUTTON_SIZE := 82
const ICON_ONLY_WIDTH := 160
const ICON_ONLY_BUTTON_SIZE := 44

## Section order and titles.
const GROUP_ORDER: Array[int] = [
	Tools.Group.INSPECT, Tools.Group.DEMOLISH, Tools.Group.TRANSPORT, Tools.Group.TRANSIT,
	Tools.Group.UTILITY, Tools.Group.ZONE, Tools.Group.NATURE, Tools.Group.CIVIC,
	Tools.Group.PLANT, Tools.Group.ARCOLOGY, Tools.Group.REWARD, Tools.Group.EMERGENCY,
	Tools.Group.TERRAIN,
]
const GROUP_NAMES := {
	Tools.Group.INSPECT: "Inspect", Tools.Group.DEMOLISH: "Demolish",
	Tools.Group.TRANSPORT: "Transport", Tools.Group.UTILITY: "Utilities",
	Tools.Group.ZONE: "Zones", Tools.Group.NATURE: "Parks and Trees",
	Tools.Group.CIVIC: "Civic", Tools.Group.TRANSIT: "Transit",
	Tools.Group.PLANT: "Power", Tools.Group.ARCOLOGY: "Gaming Resorts",
	Tools.Group.REWARD: "Rewards", Tools.Group.EMERGENCY: "Emergency",
	Tools.Group.TERRAIN: "Terrain",
}

## Short player captions; full identity, price and availability stay in tooltips.
const CAPTIONS := {
	Tools.Kind.QUERY: "Inspect",
	Tools.Kind.SIGN: "Place sign",
	Tools.Kind.BULLDOZE: "Bulldoze",
	Tools.Kind.DEZONE: "Remove\nzone",
	Tools.Kind.ROAD: "Road",
	Tools.Kind.HIGHWAY: "Highway",
	Tools.Kind.ONRAMP: "Highway\nramp",
	Tools.Kind.TUNNEL: "Road\ntunnel",
	Tools.Kind.RAIL: "Rail",
	Tools.Kind.SUBWAY: "Subway\ntrack",
	Tools.Kind.SUBWAY_PORTAL: "Subway\nportal",
	Tools.Kind.POWER_LINE: "Power\nline",
	Tools.Kind.WATER_PIPE: "Water\npipe",
	Tools.Kind.ZONE_RES_LOW: "Homes\nlight",
	Tools.Kind.ZONE_RES_HIGH: "Homes\ndense",
	Tools.Kind.ZONE_COM_LOW: "Shops\nlight",
	Tools.Kind.ZONE_COM_HIGH: "Offices\ndense",
	Tools.Kind.ZONE_IND_LOW: "Industry\nlight",
	Tools.Kind.ZONE_IND_HIGH: "Industry\ndense",
	Tools.Kind.AIRPORT: "Airport",
	Tools.Kind.SEAPORT: "Seaport",
	Tools.Kind.TREES: "Trees",
	Tools.Kind.SMALL_PARK: "Pocket\npark",
	Tools.Kind.LARGE_PARK: "City park",
	Tools.Kind.WATER_PUMP: "Water\npump",
	Tools.Kind.WATER_TOWER: "Water\ntower",
	Tools.Kind.WATER_TREATMENT: "Treat\nwater",
	Tools.Kind.DESALINATION: "Desalinate",
	Tools.Kind.POLICE: "Police\nstation",
	Tools.Kind.FIRE: "Fire\nstation",
	Tools.Kind.HOSPITAL: "Hospital",
	Tools.Kind.SCHOOL: "School",
	Tools.Kind.COLLEGE: "College",
	Tools.Kind.LIBRARY: "Library",
	Tools.Kind.MUSEUM: "Museum",
	Tools.Kind.STADIUM: "Stadium",
	Tools.Kind.MARINA: "Marina",
	Tools.Kind.ZOO: "Zoo",
	Tools.Kind.PRISON: "Prison",
	Tools.Kind.BUS_DEPOT: "Bus\ndepot",
	Tools.Kind.RAIL_STATION: "Rail\nstation",
	Tools.Kind.SUBWAY_STATION: "Subway\nstation",
	Tools.Kind.COAL_PLANT: "Coal",
	Tools.Kind.HYDRO_PLANT: "Hydro\ndam",
	Tools.Kind.WIND_PLANT: "Wind",
	Tools.Kind.GAS_PLANT: "Gas",
	Tools.Kind.OIL_PLANT: "Oil",
	Tools.Kind.NUCLEAR_PLANT: "Nuclear",
	Tools.Kind.SOLAR_PLANT: "Solar",
	Tools.Kind.MICROWAVE_PLANT: "Microwave",
	Tools.Kind.FUSION_PLANT: "Fusion",
	Tools.Kind.ARCOLOGY_COMSTOCK: "Comstock\nGrand",
	Tools.Kind.ARCOLOGY_JUNCTION: "Silver\nJunction",
	Tools.Kind.ARCOLOGY_BOULDER: "Boulder\nCrown",
	Tools.Kind.ARCOLOGY_ORBIT: "Desert\nOrbit",
	Tools.Kind.REWARD_MAYORS_RESIDENCE: "Mayor’s\nhome",
	Tools.Kind.REWARD_CITY_HALL: "City hall",
	Tools.Kind.REWARD_MONUMENT: "Monument",
	Tools.Kind.REWARD_MILITARY_BASE: "Military\nbase",
	Tools.Kind.REWARD_NEON_DOME: "Neon\ndome",
	Tools.Kind.DISPATCH_FIRE: "Send\nfire crews",
	Tools.Kind.DISPATCH_POLICE: "Send\npolice",
	Tools.Kind.DISPATCH_MILITARY: "Send\nmilitary",
	Tools.Kind.RAISE_LAND: "Raise\nland",
	Tools.Kind.LOWER_LAND: "Lower\nland",
	Tools.Kind.LEVEL_LAND: "Level\nland",
	Tools.Kind.PLACE_WATER: "Place\nwater",
	Tools.Kind.FOREST: "Forest",
	Tools.Kind.PLANT_TREE: "Tree",
	Tools.Kind.RAISE_SEA: "Raise sea",
	Tools.Kind.LOWER_SEA: "Lower sea",
}


## Title and hint over a group's block of press-to-apply tools.
const ACTION_BLOCKS := {
	Tools.Group.TERRAIN: ["Sea level", "Set before founding. Each press moves the sea one level."],
}


static func caption_for(tool: int) -> String:
	return String(CAPTIONS.get(tool, Tools.display_name(tool)))


var selected_label: Label
var active_tool := -1
var stage := Stage.PLAY
## tool -> Button
var buttons: Dictionary = {}
## tool -> lock reason shown in the tooltip ("" when usable)
var lock_reasons: Dictionary = {}
var editing_panel: VBoxContainer
var found_button: Button
var regenerate_button: Button
var reset_reason_label: Label
var section_picker: OptionButton
var button_labels_visible := true
var _compact := false

var _normal_style: StyleBoxFlat
var _active_style: StyleBoxFlat
var _headers: Dictionary = {}
var _grids: Dictionary = {}
## group -> block holding that group's press-to-apply tools
var _action_blocks: Dictionary = {}
var _action_grids: Dictionary = {}
var _reveal_pending := false
var _lock_info_buttons: Dictionary = {}
var _lock_details: PanelContainer
var _lock_identity: Label
var _lock_reason: Label
var _explained_tool := -1


func _init() -> void:
	name = "Toolbar"
	theme = UITheme.control_theme()
	_normal_style = UITheme.button_stylebox(false)
	_active_style = UITheme.button_stylebox(true)
	var style := UITheme.window_stylebox()
	style.shadow_size = 0
	style.set_corner_radius_all(0)
	style.border_width_right = 2
	style.border_color = UITheme.DIVIDER
	style.set_content_margin_all(4.0)
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	_build()
	set_stage(stage)


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.name = "Shell"
	shell.add_theme_constant_override("separation",8)
	add_child(shell)
	selected_label = UIFactory.make_label("Tool: none",UITheme.FONT_SMALL)
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.name = "SelectedTool"
	shell.add_child(selected_label)
	section_picker = OptionButton.new()
	section_picker.name = "ToolSection"
	section_picker.allow_reselect = true
	section_picker.theme = UITheme.control_theme()
	section_picker.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	section_picker.custom_minimum_size.y = 44
	section_picker.tooltip_text = "Jump to a tool category"
	section_picker.add_item("Find tools…", -1)
	for group: int in GROUP_ORDER:
		section_picker.add_item(GROUP_NAMES[group], group)
	section_picker.item_selected.connect(_jump_to_section)
	shell.add_child(section_picker)
	shell.add_child(_make_lock_details())
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.resized.connect(func() -> void: _reveal_focused_tool.call_deferred())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	column.add_child(_make_editing_panel())
	var tools_by_group: Dictionary = {}
	for tool in Tools.all():
		var g := Tools.group(tool)
		if not tools_by_group.has(g):
			tools_by_group[g] = []
		(tools_by_group[g] as Array).append(tool)
	for g in GROUP_ORDER:
		if not tools_by_group.has(g):
			continue
		var header := UIFactory.make_section_header(String(GROUP_NAMES.get(g, "Tools")))
		header.name = "Header%d" % g
		column.add_child(header)
		_headers[g] = header
		var grid := _make_grid()
		column.add_child(grid)
		_grids[g] = grid
		var immediate: Array = []
		for tool in tools_by_group[g]:
			if Tools.is_immediate(tool):
				immediate.append(tool)
			else:
				grid.add_child(_make_button(tool))
		if not immediate.is_empty():
			column.add_child(_make_action_block(g, immediate))


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## A group's press-to-apply tools, set apart under their own small title so
## they read as actions rather than map tools.
func _make_action_block(g: int, tools: Array) -> VBoxContainer:
	var titles: Array = ACTION_BLOCKS.get(g, ["Actions", "Each press applies at once."])
	var block := VBoxContainer.new()
	block.name = "Actions%d" % g
	block.add_theme_constant_override("separation", 4)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	block.add_child(gap)
	var title := UIFactory.make_label(String(titles[0]), UITheme.FONT_SMALL, UITheme.HEADER)
	title.name = "Title"
	block.add_child(title)
	var hint := UIFactory.make_label(String(titles[1]), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(hint)
	var grid := _make_grid()
	block.add_child(grid)
	for tool: int in tools:
		grid.add_child(_make_button(tool))
	_action_blocks[g] = block
	_action_grids[g] = grid
	return block


## A tap-readable explanation stays in the sidebar without changing tools.
func _make_lock_details() -> PanelContainer:
	_lock_details = UIFactory.make_panel()
	_lock_details.name = "LockDetails"
	_lock_details.visible = false
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation",4)
	_lock_details.add_child(body)
	_lock_identity = UIFactory.make_label("",UITheme.FONT_SMALL,UITheme.HEADER)
	_lock_identity.name = "Identity"
	_lock_identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_lock_identity)
	_lock_reason = UIFactory.make_label("",UITheme.FONT_SMALL)
	_lock_reason.name = "Reason"
	_lock_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_lock_reason)
	var close := UIFactory.make_button("Close details")
	close.name = "Close"
	close.pressed.connect(_close_lock_details)
	body.add_child(close)
	return _lock_details


## Regenerate and Found City, shown only while the land is being shaped.
func _make_editing_panel() -> VBoxContainer:
	editing_panel = VBoxContainer.new()
	editing_panel.name = "EditingPanel"
	editing_panel.add_theme_constant_override("separation", 4)
	editing_panel.visible = false
	editing_panel.add_child(UIFactory.make_section_header("Shape the Land"))
	var hint := UIFactory.make_label("Terrain tools are free until the city is founded.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editing_panel.add_child(hint)
	regenerate_button = UIFactory.make_button("Regenerate", "Roll a fresh map with the same settings")
	regenerate_button.name = "Regenerate"
	regenerate_button.pressed.connect(func() -> void: regenerate_requested.emit())
	editing_panel.add_child(regenerate_button)
	reset_reason_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	reset_reason_label.name = "ResetReason"
	reset_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_reason_label.visible = false
	editing_panel.add_child(reset_reason_label)
	found_button = UIFactory.make_primary_button("Found City", "Start the clock and open the treasury")
	found_button.name = "FoundCity"
	found_button.pressed.connect(func() -> void: found_requested.emit())
	editing_panel.add_child(found_button)
	editing_panel.add_child(HSeparator.new())
	return editing_panel


func _make_button(tool: int) -> Button:
	var b := Button.new()
	b.name = "Tool%d" % tool
	b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.theme = UITheme.control_theme()
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	b.add_theme_constant_override("icon_max_width", 32)
	b.add_theme_constant_override("h_separation", 4)
	b.add_theme_color_override("font_disabled_color", UITheme.TEXT_DISABLED)
	# Authored pictograms already contain their badge, strokes and zone colors.
	# Generic control icons can follow text contrast; tool artwork keeps its palette.
	for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.5))
	b.text = caption_for(tool)
	# Reserve two lines for consistent icon and caption alignment.
	if not b.text.contains("\n"): b.text += "\n"
	b.expand_icon = true
	b.add_theme_stylebox_override("normal", _normal_style)
	var icon := _icon_texture(Tools.icon(tool))
	if icon != null:
		b.icon = icon

	b.tooltip_text = tooltip_for(tool, "", false, controls)
	b.pressed.connect(_on_button_pressed.bind(tool))
	# The construction button stays disabled. Its transparent child
	# only explains the lock, including on touch where hover is unavailable.
	var info := Button.new()
	info.name = "LockInfo"
	info.theme = UITheme.control_theme()
	info.custom_minimum_size = Vector2(44,44)
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	for style: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		info.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	b.add_child(info)
	info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info.visible = false
	info.pressed.connect(_show_lock_details.bind(tool))
	_lock_info_buttons[tool] = info
	buttons[tool] = b
	lock_reasons[tool] = ""
	return b


static func _icon_texture(icon: StringName) -> Texture2D:
	var path := "res://assets/ui/tool-icons/%s.svg" % String(icon)
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	return tex


## "Road — $10" plus the lock reason on a second line when locked. `free`
## overrides the price (terrain tools before founding).
static func tooltip_for(tool: int, reason: String, free: bool = false, bindings: ControlBindings = null) -> String:
	var price := 0 if free else Tools.cost(tool)
	var text := "%s — %s" % [Tools.display_name(tool), "free" if price <= 0 else "$" + UIFactory.commafy(price)]
	var input := bindings if bindings != null else ControlBindings.new()
	if tool == Tools.Kind.QUERY: text += " [%s]" % input.caption(&"query")
	elif tool == Tools.Kind.BULLDOZE: text += " [hold %s]" % input.caption(&"bulldoze")
	if Tools.is_immediate(tool): text += " · applies on press"
	if not reason.is_empty():
		text += "\n" + reason
	return text


func _on_button_pressed(tool: int) -> void:
	if is_locked(tool):
		_show_lock_details(tool)
		return
	_close_lock_details()
	tool_selected.emit(tool)


func _show_lock_details(tool: int) -> void:
	if not is_locked(tool) or not is_shown(tool): return
	_explained_tool = tool
	_lock_identity.text = tooltip_for(tool,"",is_free(tool),controls).get_slice("\n",0)
	_lock_reason.text = String(lock_reasons[tool])
	_lock_details.show()
	_reveal_focused_tool()


func _close_lock_details() -> void:
	var tool := _explained_tool
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var restore := focused != null and _lock_details.is_ancestor_of(focused)
	_explained_tool = -1
	_lock_details.hide()
	if restore and buttons.has(tool) and is_shown(tool):
		var target: Button = _lock_info_buttons[tool] if is_locked(tool) else buttons[tool]
		if target.is_visible_in_tree(): target.grab_focus()


func _jump_to_section(index: int) -> void:
	if index == 0: return
	var group := section_picker.get_item_id(index)
	var scroll: ScrollContainer = get_node("Shell/Scroll")
	# Focus starts in the chosen category for subsequent keyboard navigation.
	var locked_fallback: Button
	for child: Button in _grids[group].get_children():
		if not child.disabled:
			child.grab_focus()
			locked_fallback = null
			break
		if locked_fallback == null:
			locked_fallback = child.get_node("LockInfo") as Button
	# Entirely locked categories still expose their requirements by keyboard.
	if locked_fallback != null: locked_fallback.grab_focus()
	# Reveal the tools below the heading, rather than just the heading at the
	# bottom edge of the viewport. Focus-following can then keep the button in view.
	scroll.scroll_vertical = int((_headers[group] as Control).position.y)


func _reveal_focused_tool() -> void:
	# Selected identity and status text can wrap after a press and resize the
	# scroll viewport without changing focus. Keep that same button reachable.
	if _reveal_pending or not is_inside_tree(): return
	_reveal_pending = true
	# Allow two nested-container layout passes. Bound one-shot connections
	# disconnect when this toolbar is freed; a suspended member coroutine
	# would instead resume on a destroyed instance during host teardown.
	get_tree().process_frame.connect(_reveal_after_layout.bind(1), CONNECT_ONE_SHOT)


func _reveal_after_layout(frames_left: int) -> void:
	if not is_inside_tree():
		_reveal_pending = false
		return
	if frames_left > 0:
		get_tree().process_frame.connect(_reveal_after_layout.bind(frames_left - 1), CONNECT_ONE_SHOT)
		return
	_reveal_pending = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (buttons.values().has(focused) or _lock_info_buttons.values().has(focused)):
		(get_node("Shell/Scroll") as ScrollContainer).ensure_control_visible(focused)


## Highlight `tool` (or nothing when negative).
func set_active(tool: int) -> void:
	if buttons.has(active_tool):
		var previous: Button = buttons[active_tool]
		previous.add_theme_stylebox_override("normal", _normal_style)
		previous.remove_theme_stylebox_override("hover")
		previous.remove_theme_color_override("font_color")
		previous.remove_theme_color_override("font_hover_color")
		previous.remove_theme_color_override("font_focus_color")
	active_tool = tool
	_update_selected_identity()
	if buttons.has(tool):
		var selected: Button = buttons[tool]
		selected.add_theme_stylebox_override("normal", _active_style)
		selected.add_theme_stylebox_override("hover", _active_style)
		selected.add_theme_color_override("font_color", UITheme.TITLE_TEXT)
		selected.add_theme_color_override("font_hover_color", UITheme.TITLE_TEXT)
		selected.add_theme_color_override("font_focus_color", UITheme.TITLE_TEXT)


func _update_selected_identity() -> void:
	var identity := tooltip_for(active_tool, String(lock_reasons.get(active_tool,"")), is_free(active_tool),controls) if buttons.has(active_tool) else "none"
	selected_label.text = "Tool: " + identity.get_slice("\n",0)
	selected_label.tooltip_text = identity


## Update every button's enabled state and tooltip from the city, its stats
## and the disaster system (which decides whether crews can be sent).
func refresh(city: City, stats: CityStats, disasters: SimSystem = null) -> void:
	var emergency := false
	if disasters != null and disasters.has_method("is_emergency"):
		emergency = bool(disasters.call("is_emergency"))
	# Crew counts scan the whole map, so gather every kind once per refresh.
	var crew_counts: Dictionary = {}
	var crews_known := false
	if emergency and disasters != null:
		if disasters.has_method("crews_summary"):
			crew_counts = disasters.call("crews_summary")
			crews_known = true
	for tool in buttons:
		var reason := Tools.locked_reason(tool, city, stats)
		if reason.is_empty() and Tools.is_dispatch_tool(tool):
			if not emergency:
				reason = "only during an emergency"
			elif crews_known or (disasters != null and disasters.has_method("crews_available")):
				var kind: StringName = Tools.dispatch_kind(tool)
				var crews := int(crew_counts.get(kind, 0)) if crews_known \
						else int(disasters.call("crews_available", kind))
				if crews <= 0:
					reason = "no crews available"
				else:
					reason = ""
		lock_reasons[tool] = reason
		var b: Button = buttons[tool]
		b.disabled = not reason.is_empty()
		b.tooltip_text = tooltip_for(tool, reason, is_free(tool), controls)
		var info: Button = _lock_info_buttons[tool]
		info.visible = b.disabled
		info.tooltip_text = b.tooltip_text
	_update_selected_identity()
	if _explained_tool >= 0:
		if is_locked(_explained_tool): _show_lock_details(_explained_tool)
		else: _close_lock_details()


func is_locked(tool: int) -> bool:
	return not String(lock_reasons.get(tool, "")).is_empty()


## Terrain tools cost nothing while the land is being shaped.
func is_free(tool: int) -> bool:
	return stage == Stage.EDITING and Tools.is_terrain_tool(tool)


## Switch between the editing stage (terrain tools only, free, with the
## Regenerate and Found City panel) and ordinary play (every group).
func set_stage(new_stage: int) -> void:
	stage = new_stage
	_close_lock_details()
	var editing := stage == Stage.EDITING
	editing_panel.visible = editing
	section_picker.visible = not editing
	for g in _headers:
		var shown: bool = not editing or g == Tools.Group.TERRAIN
		(_headers[g] as Control).visible = shown
		(_grids[g] as Control).visible = shown
		if _action_blocks.has(g):
			var any := false
			for b: Button in (_action_grids[g] as Control).get_children():
				b.visible = editing or not Tools.is_editing_only(buttons.find_key(b))
				any = any or b.visible
			(_action_blocks[g] as Control).visible = shown and any
	for tool in buttons:
		(buttons[tool] as Button).tooltip_text = tooltip_for(tool, String(lock_reasons.get(tool, "")), is_free(tool), controls)
	_update_selected_identity()


## For imported terrain, the regenerate button becomes Reset imported terrain.
func set_imported_terrain_reset(enabled: bool, reason: String = "") -> void:
	regenerate_button.text = "Reset imported terrain"
	regenerate_button.disabled = not enabled
	reset_reason_label.text = reason
	reset_reason_label.visible = not enabled and not reason.is_empty()
	regenerate_button.tooltip_text = "Restore the original imported land, water and trees offline" if enabled else reason


func set_procedural_regeneration() -> void:
	reset_reason_label.visible = false
	reset_reason_label.text = ""
	regenerate_button.text = "Regenerate"
	regenerate_button.disabled = false
	regenerate_button.tooltip_text = "Roll a fresh map with the same settings"


## Whether the button for `tool` can be reached in the current stage.
func is_shown(tool: int) -> bool:
	var grid: Control = _grids.get(Tools.group(tool), null)
	if Tools.is_immediate(tool):
		grid = _action_blocks.get(Tools.group(tool), null)
	return grid != null and grid.visible and (buttons[tool] as Control).visible


func button_for(tool: int) -> Button:
	return buttons.get(tool, null)

## Keep the same nodes, selection, tooltips and focus when captions change.
func set_button_labels_visible(on: bool) -> void:
	button_labels_visible = on
	for tool: int in buttons:
		var button: Button = buttons[tool]
		var caption := caption_for(tool)
		if not caption.contains("\n"): caption += "\n"
		button.text = caption if on else ""
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP if on else VERTICAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE) if on else Vector2(ICON_ONLY_BUTTON_SIZE, ICON_ONLY_BUTTON_SIZE)
	apply_layout(_compact)
	_reveal_focused_tool()

func apply_layout(compact: bool) -> void:
	_compact = compact
	custom_minimum_size.x = (COMPACT_WIDTH if compact else WIDTH) if button_labels_visible else ICON_ONLY_WIDTH
	for group in _grids:
		(_grids[group] as GridContainer).columns = COLUMNS
		(_headers[group] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for group in _action_grids:
		(_action_grids[group] as GridContainer).columns = COLUMNS
	# Keep both columns inside the sidebar, including the visible scrollbar.
	# BioRhyme's long captions need a small size adjustment on compact panels.
	var scroll := get_node("Shell/Scroll") as ScrollContainer
	var scrollbar_width := scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var panel_width := get_theme_stylebox("panel").get_minimum_size().x
	var caption_width := floorf((custom_minimum_size.x - panel_width - scrollbar_width - 4.0) / COLUMNS) - _normal_style.get_minimum_size().x
	for tool: int in buttons:
		var button: Button = buttons[tool]
		var font := button.get_theme_font("font")
		var font_size := UITheme.FONT_SMALL
		while font_size > 12:
			var widest := 0.0
			for line: String in button.text.split("\n"):
				widest = maxf(widest,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
			if widest <= caption_width: break
			font_size -= 1
		button.add_theme_font_size_override("font_size",font_size)
