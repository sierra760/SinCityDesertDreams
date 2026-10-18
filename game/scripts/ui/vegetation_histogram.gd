# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Elevation histogram for the Vegetation Zones window. One bar per ground
## level across the city's relief: its height shows how much dry ground lies
## at that level and its colored foot how many of those tiles have trees, both
## square-root scaled so small hills stay visible. Bands behind the bars
## show the zone each level belongs to. Brass lines mark the zone boundaries;
## drag one (mouse or finger), or focus the chart and use Left/Right to move
## the selected line and Up/Down to pick another.
class_name VegetationHistogram
extends Control

## A boundary moved: cutoff `index` (0 ends the palms, 1 the woodland) to `level`.
## While dragging these are previews; `drag_finished` follows on release.
signal cutoff_changed(index: int, level: int)
## The pointer let go of a boundary it was dragging.
signal drag_finished
## The pointer or keyboard now points at `level` (-1 when nothing).
signal level_hovered(level: int)

const PAD := 10.0
const AXIS := 22.0
const GRIP := 9.0
## Horizontal reach of a boundary line for pointer presses.
const HIT := 22.0
const MIN_LEVELS := 8
const GROUND := Color("d9c9a3")

var land := PackedInt32Array()
var trees := PackedInt32Array()
var settings: Dictionary = VegetationZones.make([true, true, true], [VegetationZones.LEVELS, VegetationZones.LEVELS])
## Level -> axis caption (elevation text).
var level_caption: Callable = func(level: int) -> String: return str(level)
## First and last displayed ground level.
var low := 0
var high := MIN_LEVELS - 1
## Cutoff index the keyboard moves; the dragged one while dragging.
var selected := 0
var hovered := -1
var _dragging := -1
var _drag_touch := -1


func _init() -> void:
	set_meta("owns_pointer_gestures", true)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 190)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = "Drag a brass line to move a zone boundary. With the chart selected, Left/Right moves a line and Up/Down picks the other."


func set_data(land_counts: PackedInt32Array, tree_counts: PackedInt32Array, zones: Dictionary) -> void:
	land = land_counts
	trees = tree_counts
	settings = zones
	var lo := -1
	var hi := -1
	for level: int in land.size():
		if land[level] == 0: continue
		if lo < 0: lo = level
		hi = level
	if lo < 0:
		lo = 0
		hi = MIN_LEVELS - 1
	lo = maxi(0, lo - 1)
	hi = mini(VegetationZones.LEVELS - 1, hi + 1)
	while hi - lo + 1 < MIN_LEVELS:
		if lo > 0: lo -= 1
		if hi - lo + 1 < MIN_LEVELS and hi < VegetationZones.LEVELS - 1: hi += 1
	low = lo
	high = hi
	var lines := boundaries()
	if not lines.is_empty() and not lines.has(selected): selected = lines[0]
	queue_redraw()


func set_settings(zones: Dictionary) -> void:
	settings = zones
	queue_redraw()


## Cutoff indices of the visible boundaries, low to high.
func boundaries() -> Array[int]:
	var out: Array[int] = []
	var zones := VegetationZones.enabled_zones(settings)
	for i: int in range(1, zones.size()): out.append(VegetationZones.boundary_cutoff(zones[i - 1]))
	return out


func _plot() -> Rect2:
	var s := size if size.x > 0.0 and size.y > 0.0 else custom_minimum_size
	return Rect2(PAD, PAD + GRIP * 2.0, maxf(1.0, s.x - PAD * 2.0), maxf(1.0, s.y - PAD - GRIP * 2.0 - AXIS))


func _slot() -> float:
	return _plot().size.x / float(high - low + 1)


## X position of the boundary below ground level `level`.
func level_x(level: int) -> float:
	var plot := _plot()
	return plot.position.x + float(clampi(level, low, high + 1) - low) * _slot()


## The ground level whose bar spans local `x`.
func level_at(x: float) -> int:
	return clampi(low + floori((x - _plot().position.x) / _slot()), low, high)


## The nearest boundary position (a cutoff level) to local `x`.
func cutoff_at(x: float) -> int:
	return clampi(low + roundi((x - _plot().position.x) / _slot()), low, high + 1)


func bar_rect(level: int) -> Rect2:
	return _bar(level, land[level] if level < land.size() else 0)


## The wooded foot of a bar, on the same square-root scale as the ground.
func tree_rect(level: int) -> Rect2:
	return _bar(level, trees[level] if level < trees.size() else 0)


func _bar(level: int, value: int) -> Rect2:
	var plot := _plot()
	var top := 1
	for count: int in land: top = maxi(top, count)
	var h := plot.size.y * sqrt(float(value) / float(top))
	return Rect2(level_x(level) + _slot() * 0.1, plot.end.y - h, _slot() * 0.8, h)


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := _plot()
	for level: int in range(low, high + 1):
		var zone := VegetationZones.zone_for_level(settings, level)
		var band := Color(VegetationZones.COLORS[zone], 0.22)
		draw_rect(Rect2(level_x(level), plot.position.y, _slot(), plot.size.y), band, true)
		var bar := bar_rect(level)
		draw_rect(bar, GROUND.lightened(0.15) if level == hovered else GROUND, true)
		if level < trees.size() and trees[level] > 0:
			var foot := tree_rect(level)
			foot.size.y = maxf(2.0, foot.size.y)
			foot.position.y = bar.end.y - foot.size.y
			draw_rect(foot, VegetationZones.COLORS[zone], true)
	draw_line(Vector2(plot.position.x, plot.end.y), Vector2(plot.end.x, plot.end.y), UITheme.BEVEL_DARK, 1.0)
	# Elevation captions every few levels, never overlapping.
	var every := maxi(1, ceili(64.0 / _slot()))
	for level: int in range(low, high + 2, every):
		var x := level_x(level)
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 4.0), UITheme.BEVEL_DARK, 1.0)
		var text := String(level_caption.call(level))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
		var at := clampf(x - width * 0.5, 0.0, size.x - width)
		draw_string(font, Vector2(at, plot.end.y + AXIS - 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	for index: int in boundaries():
		var x := level_x(int(settings.cutoffs[index]))
		var active := index == selected and (has_focus() or _dragging >= 0)
		var color := UITheme.FOCUS if active else UITheme.ACCENT_BRASS
		draw_line(Vector2(x, plot.position.y - GRIP), Vector2(x, plot.end.y), color, 4.0 if active else 3.0)
		draw_circle(Vector2(x, plot.position.y - GRIP), GRIP, color)
		draw_circle(Vector2(x, plot.position.y - GRIP), GRIP - 3.0, UITheme.BEVEL_LIGHT)
	if has_focus():
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), UITheme.FOCUS, false, 2.0)


## The boundary a press at local `x` takes, or -1. Stacked lines resolve
## toward the side with room to move.
func boundary_near(x: float) -> int:
	var best := -1
	var distance := HIT
	for index: int in boundaries():
		var d := absf(level_x(int(settings.cutoffs[index])) - x)
		if d < distance - 0.5 or (best >= 0 and absf(d - distance) <= 0.5 and _prefer(index, best)):
			best = index
			distance = minf(d, distance)
	return best


func _prefer(index: int, other: int) -> bool:
	# At the high end move the lower boundary first; elsewhere the higher one.
	return index < other if int(settings.cutoffs[index]) > (low + high) / 2 else index > other


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position.x)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventMouseMotion:
		_point(event.position.x)
		if _dragging >= 0: accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and _drag_touch < 0:
			_drag_touch = event.index
			_begin(event.position.x)
		elif not event.pressed and event.index == _drag_touch:
			_drag_touch = -1
			_end_drag()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _drag_touch:
		_point(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed:
		_key(event as InputEventKey)


func _begin(x: float) -> void:
	grab_focus()
	var index := boundary_near(x)
	if index >= 0:
		selected = index
		_dragging = index
	_point(x)


func _end_drag() -> void:
	if _dragging < 0: return
	_dragging = -1
	queue_redraw()
	drag_finished.emit()


## True while a pointer holds a boundary.
func is_dragging() -> bool:
	return _dragging >= 0


func _point(x: float) -> void:
	var level := level_at(x)
	if level != hovered:
		hovered = level
		level_hovered.emit(level)
		queue_redraw()
	if _dragging >= 0:
		var cutoff := cutoff_at(x)
		if cutoff != int(settings.cutoffs[_dragging]): cutoff_changed.emit(_dragging, cutoff)


func _key(event: InputEventKey) -> void:
	var lines := boundaries()
	if lines.is_empty(): return
	if not lines.has(selected): selected = lines[0]
	match event.keycode:
		KEY_LEFT, KEY_RIGHT:
			var step := -1 if event.keycode == KEY_LEFT else 1
			var current := clampi(int(settings.cutoffs[selected]), low, high + 1)
			var target := clampi(current + step, low, high + 1)
			if target != current: cutoff_changed.emit(selected, target)
			hovered = clampi(target, low, high)
			level_hovered.emit(hovered)
			accept_event()
		KEY_UP, KEY_DOWN:
			var at := lines.find(selected)
			selected = lines[clampi(at + (1 if event.keycode == KEY_UP else -1), 0, lines.size() - 1)]
			queue_redraw()
			accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			if _dragging < 0:
				hovered = -1
				level_hovered.emit(-1)
				queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			_end_drag()
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_RESIZED:
			queue_redraw()
