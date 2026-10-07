# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Street Names editor panel. Typing changes nothing until Apply, which
## the session turns into a saved street name.
class_name StreetNamesPanel
extends PanelContainer
signal apply_requested
signal remove_requested
signal select_entire_requested
signal clear_requested
signal done_requested
signal branch_requested(segment_id: String)
var name_edit: LineEdit
var apply_button: Button
var remove_button: Button
var entire_button: Button
var clear_button: Button
var done_button: Button
var hint: Label
var summary: Label
var message: Label
var scroll: ScrollContainer
var footer: HBoxContainer
var branches: VBoxContainer
var suggestions: VBoxContainer
const SELECT_PROMPT := "Click or tap a road to select it."
var _count := 0
var _current := ""
var _names: Array[String] = []
var _matching: Label

func _init() -> void:
	name = "StreetNamesPanel"
	theme = UITheme.control_theme()
	add_theme_stylebox_override("panel",UITheme.window_stylebox())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	add_child(column)
	column.add_child(UIFactory.make_section_header("Street Names"))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	summary = _label(SELECT_PROMPT)
	content.add_child(summary)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Street name"
	name_edit.custom_minimum_size.y = 44
	name_edit.expand_to_text_length = false
	# API and field share validation; do not silently truncate a pasted name.
	name_edit.text_changed.connect(func(_text: String): _validate())
	# Return in the field applies the name, like the Apply button.
	name_edit.text_submitted.connect(func(_text: String):
		if not apply_button.disabled: apply_requested.emit())
	content.add_child(name_edit)
	_matching = _label("")
	content.add_child(_matching)
	suggestions = VBoxContainer.new()
	content.add_child(suggestions)
	remove_button = UIFactory.make_button("Remove name")
	remove_button.pressed.connect(func(): remove_requested.emit())
	content.add_child(remove_button)
	entire_button = UIFactory.make_button("Select entire named street")
	entire_button.pressed.connect(func(): select_entire_requested.emit())
	content.add_child(entire_button)
	clear_button = UIFactory.make_button("Clear selection")
	clear_button.pressed.connect(func(): clear_requested.emit())
	content.add_child(clear_button)
	branches = VBoxContainer.new()
	content.add_child(branches)
	message = _label("")
	content.add_child(message)
	hint = _label("Changes save when you press Apply.")
	content.add_child(hint)
	footer = HBoxContainer.new()
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_child(footer)
	apply_button = UIFactory.make_primary_button("Apply")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(func(): apply_requested.emit())
	footer.add_child(apply_button)
	done_button = UIFactory.make_button("Done")
	done_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_button.pressed.connect(func(): done_requested.emit())
	footer.add_child(done_button)
	set_selection(0,"",false)
	hide()

func _label(text: String) -> Label:
	var label := UIFactory.make_label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func set_selection(count: int, current_name: String, mixed: bool) -> void:
	_count = count
	_current = "" if mixed else current_name
	if count == 0:
		summary.text = SELECT_PROMPT
	else:
		summary.text = "%d road segment%s selected · %s" % [count,"" if count == 1 else "s","Multiple names" if mixed else (current_name if not current_name.is_empty() else "Unnamed")]
	entire_button.disabled = mixed or current_name.is_empty() or count == 0
	remove_button.disabled = count == 0
	clear_button.disabled = count == 0 and name_edit.text.is_empty()
	_validate()

func draft_text() -> String:
	return name_edit.text

## A valid typed name for a selection that does not carry it yet.
func has_unapplied_draft() -> bool:
	if _count == 0: return false
	var valid := StreetNamingCodec.normalize_name(name_edit.text)
	return valid.ok and String(valid.display) != _current

func set_draft(text: String) -> void:
	name_edit.text = text
	_validate()

func set_names(names: Array[String]) -> void:
	_names = names.duplicate()
	_names.sort()
	_validate()

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _validate() -> void:
	if apply_button == null: return
	var valid := StreetNamingCodec.normalize_name(name_edit.text)
	apply_button.disabled = _count == 0 or not valid.ok
	clear_button.disabled = _count == 0 and name_edit.text.is_empty()
	_matching.text = ""
	_clear_children(suggestions)
	var query := name_edit.text.strip_edges().to_lower()
	var shown := 0
	for saved: String in _names:
		if valid.ok and saved.to_lower() == valid.comparison:
			_matching.text = "Use existing street: " + saved
		if shown >= 5 or (not query.is_empty() and not saved.to_lower().contains(query)): continue
		var button := UIFactory.make_button(saved)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func(): set_draft(saved))
		suggestions.add_child(button)
		shown += 1
	if not valid.ok and not name_edit.text.is_empty(): _matching.text = valid.error

func set_branches(choices: Array) -> void:
	_clear_children(branches)
	for choice: Dictionary in choices:
		var button := UIFactory.make_button(choice.label)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func(): branch_requested.emit(choice.id))
		branches.add_child(button)

func apply_layout(bounds: Rect2, compact: bool) -> void:
	var width := minf(360,bounds.size.x-16)
	var height := minf(520,bounds.size.y-16)
	if compact: height = minf(height,maxf(160,bounds.size.y*.56))
	size = Vector2(maxf(0,width),maxf(0,height))
	position = Vector2(bounds.end.x-size.x-8,bounds.end.y-size.y-8 if compact else bounds.position.y+8)
