# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Compact gameplay guide. Follows the window contract: bind, refresh, open,
## close and the `closed` signal.
class_name HelpWindow
extends Control

signal closed

## Rows whose title starts with "#" are section headers. A third element
## limits a row to "desktop" or "touch" players. Braced names such as
## {interact} are filled from the player's current key bindings when the
## window opens (see `fill_keys`), so the guide stays right after rebinding.
const ROWS: Array = [
	["#Your first city"],
	["Shape, then found", "Choose terrain and edit the land for free. Found City starts the clock and opens your treasury."],
	["Build a neighborhood", "Zone level land; provide power, water and road access. Watch demand and review your budget."],
	["Choose a speed", "Cities open paused. Pick a speed from the Speed menu; {pause} pauses and resumes at the same speed.", "desktop"],
	["Choose a speed", "Cities open paused. Pick a speed from Menu → Speed.", "touch"],
	["Save and recover", "Save your city or an unfounded map from the City menu (Cmd/Ctrl+S). Load City also lists yearly automatic backups and recovery copies; save a recovered city under a name to keep it."],
	["#Moving around"],
	["Camera", "Pan with {pan}, a middle-button drag {swipe_pan}. Zoom with the wheel{swipe_zoom}, a pinch or {zoom}. {rotate} rotates the view.", "desktop"],
	["Tools", "Pick a tool on the left, then click or drag on the map; the price shows before you let go. Escape drops the tool. Hold {bulldoze} to bulldoze for a moment. Right-click or {query} inspects a tile.", "desktop"],
	["Camera and tools", "Drag one finger to preview a tool and lift to apply. Add a second finger to cancel, then pan or pinch to zoom.", "touch"],
	["#Explore"],
	["Walk or drive", "View → Explore City enters on an outdoor road. Choose vehicles from the Explore menu; trains need connected tracks. Approach a marina and use Interact to board a boat. Stop beside a marina or clear shoreline to exit; land aircraft before exiting."],
	["Explore keys", "{move} move or steer, the mouse looks around, {sprint} sprints, {jump_brake}, {interact} enters and exits vehicles, {ascend} and {descend} climb and descend in a helicopter. Escape opens and closes the Explore menu.", "desktop"],
	["Explore touch", "Use the pad on the left to move and drag on the right to look. Menu pauses movement; Resume starts it again.", "touch"],
	["Ride transit", "Walk through open train doors to board or leave. Use the station lift to reach subway platforms. Pick a destination in the Explore menu before boarding."],
	["Recover or return", "Recover always returns you to the nearest outdoor road. Return to Build restores your aerial view. Your Explore position is not saved; loading returns to Build."],
	["#Gaming resorts"],
	["Enter a resort", "In Explore, walk up to the front doors of a Gaming Resort and press {interact_touch} to step onto its casino floor. The mat by the door leads back outside."],
	["Play a table", "Walk up to a table or machine and press {interact_touch} to sit down; the city pauses while you play. Pick a chip and a spot, then play. Rules explains the game; Leave table (Escape) returns you to the floor between rounds."],
	["Limits and the treasury", "Each resort has its own table minimum and maximum, and a bet can never exceed the treasury. The city treasury pays every bet and collects every win; the Desert Dispatch notices big nights."],
	["#Where to find things"],
	["Settings → Controls", "Change keyboard bindings, look sensitivity and vertical inversion. Play with keyboard and mouse or touch; game controllers are not supported."],
	["Reports", "Review your budget, graphs, population, industries, ordinances, newspaper, maps and neighbors."],
	["View", "Choose zoom and overlays; show or hide traffic, labels and the minimap."],
	["Help → Secret Codes", "Try your luck in a founded city. DOUBLEDOWN bets a tenth of the treasury; HIGHROLLER brings cash and permits; MARKER is real debt; CHAPEL is just for fun."],
	["iPhone layout", "Tools opens the tool drawer; choosing a tool closes it. Inspect selects tile inspection. Menu contains the city, view and report commands. Details expands the status; Alerts opens current warnings.", "touch"],
	["iPhone / iPad files", "Copy .sc2 or .sc2d files into On My iPhone or On My iPad → SC2D in the Files app. Import Classic City or Load City → Browse opens the app folder.", "touch"],
]

var panel: PanelContainer
var body: VBoxContainer
var sources_dialog: TerrainSourcesDialog
var sources_button: Button
## The player's live bindings. Unset, the window uses the host's bindings
## (an ancestor's `controls`) when it opens, else the defaults.
var controls: ControlBindings
var _sim: Simulation
var _grid: Container
## Description labels and their unfilled text, refreshed in place on open
## (the responsive table keeps its own references to the row nodes).
var _descriptions: Array[Label] = []
var _templates: Array[String] = []


func _init() -> void:
	name = "HelpWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	var chrome := UIFactory.make_window_chrome("Playing the Game")
	panel = chrome["root"]
	panel.name = "Panel"
	(chrome["close_button"] as Button).pressed.connect(close)
	body = chrome["body"]
	var grid := UIFactory.ResponsiveTable.new()
	grid.columns = 2
	grid.has_headers = false
	grid.headings = ["", ""]
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	body.add_child(grid)
	_grid = grid
	_fill_rows()
	sources_button = UIFactory.make_button("Terrain Data Sources")
	sources_button.pressed.connect(func() -> void: sources_dialog.open())
	body.add_child(sources_button)
	var done := UIFactory.make_button("Done")
	done.pressed.connect(close)
	(chrome["actions"] as HBoxContainer).add_child(done)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -200
	panel.offset_bottom = 200
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	WindowDrag.enable(chrome["title_bar"], panel)
	sources_dialog = TerrainSourcesDialog.new()
	add_child(sources_dialog)


func bind(sim: Simulation) -> void:
	_sim = sim


func refresh() -> void:
	pass


func open() -> void:
	_fill_rows()
	visible = true


## Fill the guide's rows with the current key bindings: built once, then
## their descriptions are refreshed in place.
func _fill_rows() -> void:
	if not is_instance_valid(_grid): return
	var bindings := _bindings()
	# The same predicate as Explore's touch controls decides the audience.
	var touch := MobilePlatform.uses_touch()
	if not _descriptions.is_empty():
		for index: int in _descriptions.size():
			if is_instance_valid(_descriptions[index]): _descriptions[index].text = fill_keys(_templates[index],bindings,touch)
		return
	var audience := "touch" if touch else "desktop"
	for row in ROWS:
		if row.size() > 2 and String(row[2]) != audience:
			continue
		var first := String(row[0])
		if first.begins_with("#"):
			var header := UIFactory.make_section_header(first.substr(1))
			_grid.add_child(header)
			_grid.add_child(Control.new())
			continue
		var key := UIFactory.make_label(first)
		key.custom_minimum_size.x = 160
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(key)
		var description := UIFactory.make_label(fill_keys(String(row[1]),bindings,touch),UITheme.FONT_BODY,UITheme.TEXT_MUTED)
		description.custom_minimum_size.x = 240
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(description)
		_descriptions.append(description)
		_templates.append(String(row[1]))


func _bindings() -> ControlBindings:
	if controls != null: return controls
	var node := get_parent()
	while node != null:
		var value: Variant = node.get("controls")
		if value is ControlBindings: return value
		node = node.get_parent()
	return ControlBindings.new()


## Replace each braced binding name in `text` with the bound key captions.
## Trackpad swipes differ by OS: macOS reports a two-finger swipe as panning,
## while Windows and Linux report a vertical swipe as wheel scrolling (zoom).
static func fill_keys(text: String, bindings: ControlBindings, touch: bool = false, os_name: String = OS.get_name()) -> String:
	var out := text
	var mac := os_name == "macOS"
	out = out.replace("{swipe_pan}", "or a two-finger trackpad swipe" if mac else "or a sideways two-finger touchpad swipe")
	out = out.replace("{swipe_zoom}", "" if mac else " (or a vertical two-finger touchpad swipe)")
	out = out.replace("{pan}", _key_set(bindings, [&"pan_forward", &"pan_left", &"pan_back", &"pan_right"]))
	out = out.replace("{move}", _key_set(bindings, [&"move_forward", &"move_left", &"move_back", &"move_right"]))
	out = out.replace("{zoom}", _zoom_keys(bindings))
	var jump := bindings.caption(&"jump", 0)
	var brake := bindings.caption(&"brake", 0)
	out = out.replace("{jump_brake}", "%s jumps or brakes" % jump if jump == brake else "%s jumps, %s brakes" % [jump, brake])
	out = out.replace("{interact_touch}", "Interact" if touch else bindings.caption(&"interact", 0))
	for action: String in ["pause", "rotate", "bulldoze", "query", "sprint", "jump", "brake", "interact", "ascend", "descend"]:
		out = out.replace("{%s}" % action, bindings.caption(StringName(action), 0))
	return out


## "W/A/S/D or the arrow keys" style text for four direction actions: each
## binding slot that all four actions fill becomes one key set.
static func _key_set(bindings: ControlBindings, actions: Array) -> String:
	var sets := PackedStringArray()
	var values := bindings.values()
	for slot: int in 2:
		var keys := PackedStringArray()
		var codes: Array[int] = []
		for action: StringName in actions:
			var bound: Array = values.get(String(action), [])
			if slot >= bound.size(): break
			codes.append(int(bound[slot]))
			keys.append(bindings.caption(action, slot))
		if keys.size() != actions.size(): continue
		sets.append("the arrow keys" if codes == [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT] else "/".join(keys))
	return " or ".join(sets)


## "keys 1–5" while the zoom keys are the digit row in order, else each key.
static func _zoom_keys(bindings: ControlBindings) -> String:
	var keys := PackedStringArray()
	var digits := true
	for level: int in range(1, 6):
		var caption := bindings.caption(StringName("zoom_%d" % level), 0)
		keys.append(caption)
		digits = digits and caption == str(level)
	return "keys 1–5" if digits else "keys " + "/".join(keys)


## Every row's description as shown, one line per row, for checks.
func guide_text() -> String:
	var lines := PackedStringArray()
	for label: Label in _descriptions:
		if is_instance_valid(label): lines.append(label.text)
	return "\n".join(lines)


func close() -> void:
	if not visible:
		return
	sources_dialog.close()
	visible = false
	closed.emit()
