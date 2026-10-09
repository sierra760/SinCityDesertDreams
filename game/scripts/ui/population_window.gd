# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Population window: headline counts, the twenty age cohorts with their
## education and health, the March complaints and the arcologies.
class_name PopulationWindow
extends Control

signal closed

const COHORTS := 20
const YEARS_PER_COHORT := 5

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
var _status_label: Label
var _headline_label: Label
var _scores_label: Label
var _chart: CohortChart
var _cohort_rows: Array[Array] = []    ## per cohort: [people Label, education Label, health Label]
var _complaints_box: VBoxContainer
var _arcology_box: VBoxContainer


## Twenty bars for the cohorts with education and health ticks over each bar.
class CohortChart extends Control:
	const PAD := 8.0
	const BASE := 18.0

	var people := PackedInt32Array()
	var education := PackedInt32Array()
	var health := PackedInt32Array()

	func _init() -> void:
		custom_minimum_size = Vector2(260, 150)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_data(p: PackedInt32Array, e: PackedInt32Array, h: PackedInt32Array) -> void:
		people = p
		education = e
		health = h
		queue_redraw()

	func largest() -> int:
		var top := 1
		for v in people:
			top = maxi(top, v)
		return top

	## Bar rectangle of one cohort in local coordinates.
	func bar_rect(index: int) -> Rect2:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			s = custom_minimum_size
		var count := maxi(people.size(), 1)
		var slot := (s.x - PAD * 2.0) / float(count)
		var height_avail := s.y - PAD - BASE
		var value := people[index] if index < people.size() else 0
		var h := height_avail * float(value) / float(largest())
		return Rect2(PAD + slot * float(index) + slot * 0.15, PAD + height_avail - h, slot * 0.7, h)

	func _draw() -> void:
		var font := get_theme_default_font()
		var s := size
		var floor_y := s.y - BASE
		draw_line(Vector2(PAD, floor_y), Vector2(s.x - PAD, floor_y), UITheme.BEVEL_DARK, 1.0)
		for i in people.size():
			var r := bar_rect(i)
			draw_rect(r, UITheme.ZONE_C, true)
			var tick_span := floor_y - PAD
			if i < education.size():
				var ey := floor_y - tick_span * clampf(float(education[i]) / 150.0, 0.0, 1.0)
				draw_line(Vector2(r.position.x, ey), Vector2(r.end.x, ey), UITheme.TITLE_BAR, 2.0)
			if i < health.size():
				var hy := floor_y - tick_span * clampf(float(health[i]) / 90.0, 0.0, 1.0)
				draw_line(Vector2(r.position.x, hy), Vector2(r.end.x, hy), UITheme.ACCENT_BRASS, 2.0)
			if i % 4 == 0:
				draw_string(font, Vector2(r.position.x - 2.0, s.y - 4.0), str(i * YEARS_PER_COHORT),
					HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Population")
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


func open() -> void:
	show()
	refresh()


func close() -> void:
	hide()
	closed.emit()


func refresh() -> void:
	if not _built:
		return
	var has_city := _sim != null and _sim.city != null
	var stats := _sim.stats if _sim != null else CityStats.new()
	var population: SimSystem = _sim.get_system(&"population") if has_city else null
	if has_city:
		_status_label.text = "%s, %s" % [_sim.city.name, _sim.date_text()]
	else:
		_status_label.text = "No city loaded"
	var status := PopulationSystem.status_name(_sim.city.status) if has_city else "-"
	if stats.arcology_population > 0:
		_headline_label.text = "Population %s (%s residents, %s in gaming resorts), a %s" % [
			UIFactory.commafy(stats.total_population()), UIFactory.commafy(stats.population),
			UIFactory.commafy(stats.arcology_population), status]
	else:
		_headline_label.text = "Population %s, a %s" % [UIFactory.commafy(stats.total_population()), status]
	_scores_label.text = "Employment %d%%, approval %d%%, education %d, life expectancy %d, jobs %s" % [
		clampi(100 - stats.unemployment, 0, 100), stats.approval, stats.education_quotient,
		stats.life_expectancy, UIFactory.commafy(stats.jobs)]
	var people := PackedInt32Array()
	var education := PackedInt32Array()
	var health := PackedInt32Array()
	people.resize(COHORTS)
	education.resize(COHORTS)
	health.resize(COHORTS)
	for i in COHORTS:
		people[i] = stats.cohorts[i] if i < stats.cohorts.size() else 0
		if population != null:
			education[i] = int(population.call("cohort_education", i, stats))
			health[i] = int(population.call("cohort_health", i, stats))
		var row: Array = _cohort_rows[i]
		var people_label: Label = row[0]
		var education_label: Label = row[1]
		var health_label: Label = row[2]
		people_label.text = UIFactory.commafy(people[i])
		education_label.text = str(education[i])
		health_label.text = str(health[i])
	_chart.set_data(people, education, health)
	_refresh_complaints(population)
	_refresh_arcologies(has_city)


# ── Public helpers ───────────────────────────────────────────────────────

func headline_text() -> String:
	return _headline_label.text


func scores_text() -> String:
	return _scores_label.text


## "people | education | health" for one cohort.
func cohort_text(index: int) -> String:
	if index < 0 or index >= COHORTS:
		return ""
	var row: Array = _cohort_rows[index]
	var people_label: Label = row[0]
	var education_label: Label = row[1]
	var health_label: Label = row[2]
	return "%s | %s | %s" % [people_label.text, education_label.text, health_label.text]


## The complaint line at a rank, empty past the end of the list.
func complaint_text(rank: int) -> String:
	var children := _complaints_box.get_children()
	if rank < 0 or rank >= children.size():
		return ""
	var label := children[rank] as Label
	return label.text if label != null else ""


func arcology_count() -> int:
	return _arcology_box.get_child_count()


func chart() -> CohortChart:
	return _chart


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	_status_label = UIFactory.make_label("No city loaded", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_headline_label = UIFactory.make_label("", UITheme.FONT_HEADER)
	_scores_label = UIFactory.make_label("")
	for label: Label in [_status_label,_headline_label,_scores_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status_label)
	_body.add_child(_headline_label)
	_body.add_child(_scores_label)

	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN)
	_body.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UIFactory.make_section_header("Age cohorts"))
	_chart = CohortChart.new()
	left.add_child(_chart)
	var key := HFlowContainer.new()
	key.add_child(_swatch(UITheme.ZONE_C, "People"))
	key.add_child(_swatch(UITheme.TITLE_BAR, "Education"))
	key.add_child(_swatch(UITheme.ACCENT_BRASS, "Health"))
	left.add_child(key)
	left.add_child(UIFactory.make_section_header("Complaints"))
	_complaints_box = VBoxContainer.new()
	_complaints_box.add_theme_constant_override("separation", 2)
	left.add_child(_complaints_box)
	left.add_child(UIFactory.make_section_header("Gaming Resorts"))
	_arcology_box = VBoxContainer.new()
	_arcology_box.add_theme_constant_override("separation", 2)
	left.add_child(_arcology_box)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.add_child(UIFactory.make_section_header("By age"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UITheme.MARGIN_COMPACT)
	grid.add_theme_constant_override("v_separation", 0)
	for header in ["Age", "People", "Educ.", "Health"]:
		grid.add_child(UIFactory.make_label(header, UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
	for i in COHORTS:
		var low := i * YEARS_PER_COHORT
		grid.add_child(UIFactory.make_label("%d-%d" % [low, low + YEARS_PER_COHORT - 1], UITheme.FONT_SMALL))
		var people_label := _number_label()
		var education_label := _number_label()
		var health_label := _number_label()
		grid.add_child(people_label)
		grid.add_child(education_label)
		grid.add_child(health_label)
		_cohort_rows.append([people_label, education_label, health_label])
	right.add_child(grid)
	columns.add_child(right)


static func _number_label() -> Label:
	var l := UIFactory.make_label("0", UITheme.FONT_SMALL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(52, 0)
	return l


static func _swatch(color: Color, caption: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = Vector2(10, 10)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(rect)
	var label := UIFactory.make_label(caption, UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	# Preserve each short word's natural width when the report enables wrapping.
	label.custom_minimum_size.x = label.get_minimum_size().x
	box.add_child(label)
	return box


# ── Refreshing ───────────────────────────────────────────────────────────

func _refresh_complaints(population: SimSystem) -> void:
	_clear(_complaints_box)
	var ranking: Array = []
	if population != null:
		ranking = population.call("complaints")
	if ranking.is_empty():
		_complaints_box.add_child(UIFactory.make_label("No vote held yet. Residents vote each %s." % GameClock.MONTH_NAMES[PopulationSystem.VOTE_MONTH - 1], UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
		return
	for i in ranking.size():
		var row: Dictionary = ranking[i]
		var votes := int(row.get("votes", 0))
		var line := "%d. %s: %d vote%s" % [i + 1, String(row.get("name", "")), votes, "" if votes == 1 else "s"]
		_complaints_box.add_child(UIFactory.make_label(line, UITheme.FONT_SMALL))


func _refresh_arcologies(has_city: bool) -> void:
	_clear(_arcology_box)
	var rewards: SimSystem = _sim.get_system(&"rewards") if has_city else null
	var report: Array = []
	if rewards != null and rewards.has_method("arcology_report"):
		report = rewards.call("arcology_report")
	if report.is_empty():
		_arcology_box.add_child(UIFactory.make_label("None built", UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
		return
	for entry in report:
		var rec: Dictionary = entry
		var anchor: Vector2i = rec.get("anchor", Vector2i(-1, -1))
		var line := "%s at %d,%d: %s of %s residents, built %d" % [
			_resort_name(StringName(String(rec.get("key", "")))), anchor.x, anchor.y,
			UIFactory.commafy(int(rec.get("residents", 0))), UIFactory.commafy(int(rec.get("capacity", 0))),
			int(rec.get("built_year", 0))]
		_arcology_box.add_child(UIFactory.make_label(line, UITheme.FONT_SMALL))


## A gaming resort's display name from its building key.
static func _resort_name(key: StringName) -> String:
	var id := Buildings.id_of(key)
	return Buildings.display_name(id) if id != Buildings.NONE else String(key).capitalize()


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_month_ended(_year: int, _month: int) -> void:
	if visible:
		refresh()


func _on_year_ended(_year: int) -> void:
	if visible:
		refresh()
