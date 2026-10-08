# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Compact gameplay guide. Follows the window contract: bind, refresh, open,
## close and the `closed` signal.
class_name HelpWindow
extends Control

signal closed

## Rows whose title starts with "#" are section headers. A third element
## limits a row to "desktop" or "touch" players.
const ROWS: Array = [
	["#Your first city"],
	["Shape, then found", "Choose terrain and edit the land for free. Found City starts the clock and opens your treasury."],
	["Build a neighborhood", "Zone level land; provide power, water and road access. Watch demand and review your budget."],
	["Choose a speed", "Cities open paused. Pick a speed from the Speed menu; P pauses and resumes at the same speed.", "desktop"],
	["Choose a speed", "Cities open paused. Pick a speed from Menu → Speed.", "touch"],
	["Save and recover", "Save your city or an unfounded map from the City menu (Cmd/Ctrl+S). Load City also lists yearly automatic backups and recovery copies; save a recovered city under a name to keep it."],
	["#Moving around"],
	["Camera", "Pan with W/A/S/D, the arrow keys, a middle-button drag or a two-finger trackpad swipe. Zoom with the wheel, a pinch or keys 1–5. R rotates the view.", "desktop"],
	["Tools", "Pick a tool on the left, then click or drag on the map; the price shows before you let go. Escape drops the tool. Hold B to bulldoze for a moment. Right-click or Q inspects a tile.", "desktop"],
	["Camera and tools", "Drag one finger to preview a tool and lift to apply. Add a second finger to cancel, then pan or pinch to zoom.", "touch"],
	["#Explore"],
	["Walk or drive", "View → Explore City enters on an outdoor road. Choose vehicles from the Explore menu; trains need connected tracks. Approach a marina and use Interact to board a boat. Stop beside a marina or clear shoreline to exit; land aircraft before exiting."],
	["Explore keys", "W/A/S/D or arrows move or steer, the mouse looks around, Shift sprints, Space jumps or brakes, F enters and exits vehicles, Q and E climb and descend in a helicopter. Escape opens and closes the Explore menu.", "desktop"],
	["Explore touch", "Use the pad on the left to move and drag on the right to look. Menu pauses movement; Resume starts it again.", "touch"],
	["Ride transit", "Walk through open train doors to board or leave. Use the station lift to reach subway platforms. Pick a destination in the Explore menu before boarding."],
	["Recover or return", "Recover always returns you to the nearest outdoor road. Return to Build restores your aerial view. Your Explore position is not saved; loading returns to Build."],
	["#Gaming resorts"],
	["Enter a resort", "In Explore, walk up to the front doors of a Gaming Resort and press F (Interact on touch) to step onto its casino floor. The mat by the door leads back outside."],
	["Play a table", "Walk up to a table or machine and press F to sit down; the city pauses while you play. Pick a chip and a spot, then play. Rules explains the game; Leave table (Escape) returns you to the floor between rounds."],
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
var _sim: Simulation


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
	var audience := "touch" if MobilePlatform.is_mobile() or MobilePlatform.uses_touch() else "desktop"
	for row in ROWS:
		if row.size() > 2 and String(row[2]) != audience:
			continue
		var first := String(row[0])
		if first.begins_with("#"):
			var header := UIFactory.make_section_header(first.substr(1))
			grid.add_child(header)
			grid.add_child(Control.new())
			continue
		var key := UIFactory.make_label(first)
		key.custom_minimum_size.x = 160
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(key)
		var description := UIFactory.make_label(String(row[1]),UITheme.FONT_BODY,UITheme.TEXT_MUTED)
		description.custom_minimum_size.x = 240
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(description)
	sources_button = UIFactory.make_button("Terrain data sources")
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
	visible = true


func close() -> void:
	if not visible:
		return
	sources_dialog.close()
	visible = false
	closed.emit()
