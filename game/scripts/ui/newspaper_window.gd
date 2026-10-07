# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Newspaper window: The Desert Dispatch, one issue at a time with the lead
## story on top, the archive behind Previous and Next, and the advisors.
class_name NewspaperWindow
extends Control

signal closed

const MASTHEAD := "The Desert Dispatch"

var _sim: Simulation
var _root: PanelContainer
var _body: VBoxContainer
var _built := false
## Index into the archive; -1 shows the latest issue.
var _index := -1
var _masthead_label: Label
var _date_label: Label
var _extra_label: Label
var _stories_box: VBoxContainer
var _page_label: Label
var _prev_button: Button
var _next_button: Button
var _advice_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Newspaper")
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


## Opening always jumps to the newest issue.
func open() -> void:
	_index = -1
	show()
	refresh()


func close() -> void:
	hide()
	closed.emit()


func refresh() -> void:
	if not _built:
		return
	var issues := _issues()
	var count := issues.size()
	var shown := -1
	if count > 0:
		shown = count - 1 if _index < 0 or _index >= count else _index
	_clear(_stories_box)
	if shown < 0:
		_date_label.text = "No issue printed yet" if _has_city() else "No city loaded"
		_extra_label.visible = false
		_page_label.text = ""
		_stories_box.add_child(UIFactory.make_label("The presses are waiting for the first month to end.",
			UITheme.FONT_BODY, UITheme.TEXT_MUTED))
	else:
		var issue: Dictionary = issues[shown]
		_date_label.text = String(issue.get("date", ""))
		_extra_label.visible = bool(issue.get("extra", false))
		_page_label.text = "Issue %d of %d" % [shown + 1, count]
		var stories: Array = issue.get("stories", [])
		for i in stories.size():
			var story: Dictionary = stories[i]
			var lead := i == 0
			var headline := UIFactory.make_label(String(story.get("headline", "")),
				UITheme.FONT_TITLE if lead else UITheme.FONT_HEADER,
				UITheme.TEXT_PRIMARY if lead else UITheme.HEADER)
			headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			headline.custom_minimum_size = Vector2(0, 0)
			_stories_box.add_child(headline)
			var body := UIFactory.make_label(String(story.get("body", "")),
				UITheme.FONT_BODY if lead else UITheme.FONT_SMALL,
				UITheme.TEXT_PRIMARY if lead else UITheme.TEXT_MUTED)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size = Vector2(0, 0)
			_stories_box.add_child(body)
			if lead and stories.size() > 1:
				_stories_box.add_child(HSeparator.new())
	_prev_button.disabled = shown <= 0
	_next_button.disabled = shown < 0 or shown >= count - 1
	_refresh_advice()


# ── Public helpers ───────────────────────────────────────────────────────

func show_issue(index: int) -> void:
	_index = index
	refresh()


func show_previous() -> void:
	var count := _issues().size()
	var shown := count - 1 if _index < 0 else _index
	if shown > 0:
		show_issue(shown - 1)


func show_next() -> void:
	var count := _issues().size()
	var shown := count - 1 if _index < 0 else _index
	if shown < count - 1:
		show_issue(shown + 1)


## Index of the issue on display, -1 when there is none.
func current_index() -> int:
	var count := _issues().size()
	if count == 0:
		return -1
	return count - 1 if _index < 0 or _index >= count else _index


func issue_count() -> int:
	return _issues().size()


## The lead story's headline, empty when nothing is printed.
func headline_text() -> String:
	if _stories_box.get_child_count() == 0 or current_index() < 0:
		return ""
	var label := _stories_box.get_child(0) as Label
	return label.text if label != null else ""


func date_text() -> String:
	return _date_label.text


func story_count() -> int:
	var n := 0
	for child in _stories_box.get_children():
		if child is Label:
			n += 1
	return n / 2


func advice_count() -> int:
	return _advice_box.get_child_count() / 2


# ── Building ─────────────────────────────────────────────────────────────

func _build() -> void:
	var masthead := VBoxContainer.new()
	masthead.add_theme_constant_override("separation", 0)
	_masthead_label = UIFactory.make_label(MASTHEAD, UITheme.FONT_TITLE + 6, UITheme.TITLE_BAR_DARK)
	_masthead_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_masthead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	masthead.add_child(_masthead_label)
	var date_row := HBoxContainer.new()
	_date_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_row.add_child(_date_label)
	_extra_label = UIFactory.make_label("EXTRA", UITheme.FONT_SMALL, UITheme.MONEY_NEGATIVE)
	_extra_label.visible = false
	date_row.add_child(_extra_label)
	masthead.add_child(date_row)
	masthead.add_child(HSeparator.new())
	_body.add_child(masthead)

	var columns := UIFactory.ResponsiveColumns.new()
	columns.add_theme_constant_override("separation", UITheme.MARGIN)
	_body.add_child(columns)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stories_box = VBoxContainer.new()
	_stories_box.add_theme_constant_override("separation", UITheme.MARGIN_COMPACT)
	page.add_child(_stories_box)
	var nav := HBoxContainer.new()
	_prev_button = UIFactory.make_button("Previous", "Older issue")
	_prev_button.pressed.connect(show_previous)
	nav.add_child(_prev_button)
	_page_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_page_label)
	_next_button = UIFactory.make_button("Next", "Newer issue")
	_next_button.pressed.connect(show_next)
	nav.add_child(_next_button)
	page.add_child(nav)
	columns.add_child(page)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(220, 0)
	side.add_child(UIFactory.make_section_header("Advisors"))
	_advice_box = VBoxContainer.new()
	_advice_box.add_theme_constant_override("separation", 2)
	side.add_child(_advice_box)
	columns.add_child(side)


# ── Refreshing ───────────────────────────────────────────────────────────

func _has_city() -> bool:
	return _sim != null and _sim.city != null


func _newspaper() -> SimSystem:
	if not _has_city():
		return null
	return _sim.get_system(&"newspaper")


func _issues() -> Array:
	var paper := _newspaper()
	if paper == null:
		return []
	var kept: Array = paper.call("archive")
	return kept


func _refresh_advice() -> void:
	_clear(_advice_box)
	var paper := _newspaper()
	var advice: Array = []
	if paper != null:
		advice = paper.call("advice")
	if advice.is_empty():
		_advice_box.add_child(UIFactory.make_label("Nothing pressing", UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
		_advice_box.add_child(UIFactory.make_label("The advisors have no concerns today.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED))
		return
	for entry in advice:
		var rec: Dictionary = entry
		var urgent := bool(rec.get("urgent", false))
		var title := UIFactory.make_label(String(rec.get("title", "")), UITheme.FONT_BODY,
			UITheme.MONEY_NEGATIVE if urgent else UITheme.HEADER)
		_advice_box.add_child(title)
		var text := UIFactory.make_label(String(rec.get("text", "")), UITheme.FONT_SMALL, UITheme.TEXT_PRIMARY)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(210, 0)
		_advice_box.add_child(text)


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
