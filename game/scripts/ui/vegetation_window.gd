# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Vegetation Zones window: the city's elevation histogram with the heights
## where desert palms give way to piñon-juniper woodland and then to pines.
## Drag the brass lines to move a boundary; switch zones on or off (one always
## stays on). The chart and ranges follow a drag live; the trees are replanted
## once when the line is let go (or shortly after the last arrow key), because
## replanting a wooded city can take a moment. Changes are saved with the city;
## Automatic returns the zones to following the terrain.
class_name VegetationWindow
extends Control

signal closed
## The city's vegetation zones changed; its trees need redrawing.
signal vegetation_changed

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _syncing := false
var histogram: VegetationHistogram
var status_label: Label
var readout_label: Label
var automatic_button: Button
## Per zone: [CheckBox, range Label, trees Label].
var zone_rows: Array[Array] = []
## Boundary positions shown but not yet applied to the city; {} when none.
var pending: Dictionary = {}
## Pause after the last arrow key before replanting.
const KEY_SETTLE := 0.35
var _settle: Timer
var _bins: Array = [PackedInt32Array(), PackedInt32Array()]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Vegetation Zones")
	_root = chrome["root"]
	_root.size = Vector2(640, 500)
	_body = chrome["body"]
	(chrome["close_button"] as Button).pressed.connect(close)
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	WindowDrag.enable(chrome["title_bar"], _root)
	_build(chrome["actions"])
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
	if sim != _sim: pending = {}
	_sim = sim
	refresh()


func open() -> void:
	show()
	refresh()


func close() -> void:
	commit_pending()
	hide()
	closed.emit()


## Rescan the city's ground and show its zones.
func refresh() -> void:
	if not _built:
		return
	var city := _city()
	_bins = VegetationZones.histogram(city)
	histogram.level_caption = func(level: int) -> String: return _elevation(city, level)
	histogram.set_data(_bins[0], _bins[1], _shown())
	_show(_shown())


## The zones on screen: a pending preview or the city's own.
func _shown() -> Dictionary:
	if not pending.is_empty():
		var preview := pending.duplicate()
		preview["automatic"] = false
		return preview
	return VegetationZones.resolve(_city())


## Update every label from the last scan, without scanning the map again.
func _show(zones: Dictionary) -> void:
	_syncing = true
	var city := _city()
	histogram.set_settings(zones)
	var bins := _bins
	if city == null:
		status_label.text = "No city loaded"
	elif zones.automatic:
		status_label.text = "%s · Automatic: the zones follow the terrain%s." % [city.name, " and its real elevations" if not VegetationZones.real_scale(city).is_empty() else ""]
	else:
		status_label.text = "%s · Set by you; saved with the city." % city.name
	automatic_button.disabled = city == null or zones.automatic
	var counts := VegetationZones.zone_tree_counts(city, zones, bins[1]) if city != null else PackedInt32Array([0, 0, 0])
	var land := VegetationZones.land_range_of(bins[0])
	var enabled_count := VegetationZones.enabled_zones(zones).size()
	for zone: int in VegetationZones.ZONES:
		var row: Array = zone_rows[zone]
		var check: CheckBox = row[0]
		var on: bool = zones.enabled[zone]
		check.button_pressed = on
		check.disabled = city == null or (on and enabled_count == 1)
		check.tooltip_text = "At least one zone stays on." if on and enabled_count == 1 else ""
		(row[1] as Label).text = range_text(city, zones, zone, land) if on else "Off"
		var trees := counts[zone]
		(row[2] as Label).text = ("%s tree tile%s" % [UIFactory.commafy(trees), "" if trees == 1 else "s"]) if on else ""
	_show_readout(histogram.hovered)
	_syncing = false


## The heights a zone covers, as player-facing text.
static func range_text(city: City, zones: Dictionary, zone: int, land := Vector2i(-2, -2)) -> String:
	var enabled := VegetationZones.enabled_zones(zones)
	var at := enabled.find(zone)
	if at < 0:
		return "Off"
	var below := -1
	var above := -1
	if at > 0: below = int(zones.cutoffs[VegetationZones.boundary_cutoff(enabled[at - 1])])
	if at < enabled.size() - 1: above = int(zones.cutoffs[VegetationZones.boundary_cutoff(zone)])
	if land.x == -2: land = VegetationZones.land_range(city)
	if land.x >= 0:
		var lo := maxi(land.x, below if below >= 0 else land.x)
		var hi := mini(land.y, above - 1 if above >= 0 else land.y)
		if lo > hi:
			return "No ground at these heights"
	if below < 0 and above < 0:
		return "All heights"
	if below < 0:
		return "Below %s" % _elevation(city, above)
	if above < 0:
		return "From %s up" % _elevation(city, below)
	return "%s to %s" % [_elevation(city, below), _elevation(city, above)]


static func _elevation(city: City, level: int) -> String:
	var metres := VegetationZones.metres_for_level(city, level)
	return "%s m" % UIFactory.commafy_signed(roundi(metres)) if metres < 0.0 else "%s m" % UIFactory.commafy(roundi(metres))


func _city() -> City:
	return _sim.city if _sim != null else null


# ── Changes ──────────────────────────────────────────────────────────────

func _apply(zones: Dictionary) -> void:
	var city := _city()
	if city == null:
		return
	var record := VegetationZones.sanitize(zones)
	if record.is_empty() or record == VegetationZones.sanitize(city.vegetation):
		return
	city.vegetation = record
	_show(_shown())
	vegetation_changed.emit()


## Move a boundary: cutoff 0 ends the palms, cutoff 1 the woodland. The move
## shows at once and reaches the city on commit_pending(): when a drag ends, or
## KEY_SETTLE after a keyboard step.
func set_cutoff(index: int, level: int) -> void:
	if _city() == null:
		return
	pending = VegetationZones.with_cutoff(_shown(), index, level)
	_show(_shown())
	if not histogram.is_dragging(): _settle.start(KEY_SETTLE)


## Apply a previewed boundary to the city and replant its trees.
func commit_pending() -> void:
	if _settle != null: _settle.stop()
	if pending.is_empty():
		return
	var zones := pending
	pending = {}
	_apply(zones)
	_show(_shown())


func set_zone_enabled(zone: int, on: bool) -> void:
	commit_pending()
	var city := _city()
	if city != null: _apply(VegetationZones.with_enabled(VegetationZones.resolve(city), zone, on))


## Return to the zones that follow the terrain.
func use_automatic() -> void:
	pending = {}
	if _settle != null: _settle.stop()
	var city := _city()
	if city == null or city.vegetation.is_empty():
		return
	city.vegetation = {}
	_show(_shown())
	vegetation_changed.emit()


func _on_check_toggled(on: bool, zone: int) -> void:
	if not _syncing: set_zone_enabled(zone, on)


func _show_readout(level: int) -> void:
	var city := _city()
	if city == null or level < 0 or level >= histogram.land.size():
		readout_label.text = "Point at a bar to see the ground and trees at that height."
		return
	var ground := histogram.land[level]
	var trees := histogram.trees[level]
	var zone := VegetationZones.zone_for_level(histogram.settings, level)
	readout_label.text = "%s: %s tile%s of ground, %s with trees · %s" % [_elevation(city, level), UIFactory.commafy(ground),
		"" if ground == 1 else "s", UIFactory.commafy(trees), VegetationZones.SHORT_TITLES[zone]]


# ── Building ─────────────────────────────────────────────────────────────

func _build(actions: Container) -> void:
	status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(status_label)
	_body.add_child(UIFactory.make_section_header("Ground by elevation"))
	histogram = VegetationHistogram.new()
	histogram.cutoff_changed.connect(set_cutoff)
	histogram.drag_finished.connect(commit_pending)
	_settle = Timer.new()
	_settle.one_shot = true
	_settle.timeout.connect(commit_pending)
	add_child(_settle)
	histogram.level_hovered.connect(_show_readout)
	_body.add_child(histogram)
	readout_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	readout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(readout_label)
	_body.add_child(UIFactory.make_section_header("Zones, low to high"))
	var grid := UIFactory.ResponsiveTable.new()
	grid.has_headers = false
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN)
	grid.add_theme_constant_override("v_separation", 4)
	for zone: int in VegetationZones.ZONES:
		var check := CheckBox.new()
		check.text = VegetationZones.TITLES[zone]
		check.custom_minimum_size.y = 44
		check.add_theme_icon_override("unchecked", _swatch(zone, false))
		check.add_theme_icon_override("checked", _swatch(zone, true))
		check.add_theme_icon_override("unchecked_disabled", _swatch(zone, false))
		check.add_theme_icon_override("checked_disabled", _swatch(zone, true))
		check.toggled.connect(_on_check_toggled.bind(zone))
		var range_label := UIFactory.make_label("")
		range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var trees_label := UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
		trees_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(check)
		grid.add_child(range_label)
		grid.add_child(trees_label)
		zone_rows.append([check, range_label, trees_label])
	_body.add_child(grid)
	var hint := UIFactory.make_label("Drag a brass line to set where one kind of tree gives way to the next. Bars show the ground at each height; their colored feet are the tiles with trees. Trees, growth and the map stay as they are; only the kind of tree changes.",
		UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hint)
	automatic_button = UIFactory.make_button("Automatic", "Let the zones follow the terrain again")
	automatic_button.pressed.connect(use_automatic)
	actions.add_child(automatic_button)
	var done := UIFactory.make_primary_button("Done")
	done.pressed.connect(close)
	actions.add_child(done)


## A checkbox glyph in the zone's color: filled when on, outlined when off.
static func _swatch(zone: int, on: bool) -> Texture2D:
	var image := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var color: Color = VegetationZones.COLORS[zone]
	for y: int in 22:
		for x: int in 22:
			var edge := x < 2 or y < 2 or x > 19 or y > 19
			if edge: image.set_pixel(x, y, UITheme.TEXT_PRIMARY)
			elif on: image.set_pixel(x, y, color)
			else: image.set_pixel(x, y, UITheme.FIELD_FACE)
	if on:
		# A light check mark across the filled square.
		for i: int in 5:
			image.set_pixel(5 + i, 10 + i, UITheme.BEVEL_LIGHT)
			image.set_pixel(5 + i, 11 + i, UITheme.BEVEL_LIGHT)
		for i: int in 8:
			image.set_pixel(9 + i, 14 - i, UITheme.BEVEL_LIGHT)
			image.set_pixel(9 + i, 15 - i, UITheme.BEVEL_LIGHT)
	return ImageTexture.create_from_image(image)
