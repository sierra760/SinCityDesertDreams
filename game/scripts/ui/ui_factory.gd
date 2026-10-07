# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared UI widget builders. Every window builds its labels, buttons and
## panels here so styling stays centralized in UITheme.
class_name UIFactory
extends RefCounted

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const ZOOM_NAMES := ["far","medium","near","close","closest"]

static func make_label(text: String, size := UITheme.FONT_BODY,
		color := UITheme.TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.theme = UITheme.control_theme()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_section_header(text: String) -> Label:
	var label := make_label(text, UITheme.FONT_HEADER, UITheme.HEADER)
	label.add_theme_font_override("font", UITheme.DISPLAY_FONT)
	return label

static func make_primary_button(text: String, tooltip := "") -> Button:
	var button := make_button(text, tooltip)
	button.theme_type_variation = "PrimaryButton"
	button.remove_theme_stylebox_override("normal")
	button.remove_theme_color_override("font_color")
	return button

static func make_title_close_button(tooltip := "Close window (Esc)") -> Button:
	var button := make_button("×", tooltip)
	button.theme_type_variation = "TitleCloseButton"
	button.remove_theme_stylebox_override("normal")
	button.remove_theme_color_override("font_color")
	button.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	return button

static func make_button(text: String, tooltip := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(44, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.theme = UITheme.control_theme()
	b.text = text
	if not tooltip.is_empty():
		b.tooltip_text = tooltip
	b.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	b.add_theme_stylebox_override("normal", UITheme.button_stylebox(false))
	b.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	return b

static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = UITheme.control_theme()
	p.add_theme_stylebox_override("panel", UITheme.window_stylebox())
	return p

## Theme and enlarge the embedded fallback picker once MobilePlatform has
## configured it. Native OS dialogs keep their own look.
static func polish_file_picker(picker: FileDialog) -> void:
	TouchFilePicker.polish(picker)

## Formats an integer's absolute value with thousands separators and no symbol.
## commafy(1234567) == "1,234,567"; commafy(0) == "0"; commafy(-500) == "500".
static func commafy(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

## "+$1,240" / "-$340" / "$0" with thousands separators.
static func format_money(amount: int) -> String:
	var sign_str := ""
	if amount > 0: sign_str = "+"
	elif amount < 0: sign_str = "-"
	return "%s$%s" % [sign_str, commafy(amount)]

## "$1,240" / "$0" — unsigned amount display (no leading + or -).
## Use for cash balances, bond principals, ledger row amounts, and
## income/expense totals that are always non-negative by definition.
static func format_amount(amount: int) -> String:
	return "$%s" % commafy(amount)

## "$1,240" / "-$1,240" — amount display that keeps a minus sign for the
## rare negative balance (net trade imports, refunds) without adding "+".
static func format_signed_amount(amount: int) -> String:
	return ("-$%s" if amount < 0 else "$%s") % commafy(amount)

## "1,240" / "-1,240" — a plain number with thousands separators and its sign.
static func commafy_signed(n: int) -> String:
	return ("-" if n < 0 else "") + commafy(n)

## Standard teal-title window chrome. Returns a dict of nodes; caller adds rows
## to body and connects close_button.pressed to its hide handler.
static func make_window_chrome(title: String) -> Dictionary:
	var root := ResponsivePanel.new()
	root.theme = UITheme.control_theme()
	root.add_theme_stylebox_override("panel",UITheme.window_stylebox())
	root.size = Vector2(880,560) if title in ["Budget","Graphs","Population","Newspaper"] else Vector2(680,500)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.VSEP)
	root.add_child(vbox)

	var title_bar := HBoxContainer.new()
	var title_label := make_label(title, UITheme.FONT_TITLE, UITheme.TITLE_TEXT)
	title_label.add_theme_font_override("font", UITheme.DISPLAY_FONT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := make_title_close_button()
	title_bar.add_child(title_label)
	title_bar.add_child(close_button)

	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", UITheme.title_bar_stylebox())
	bar_panel.add_child(title_bar)
	vbox.add_child(bar_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.VSEP)
	var body_scroll := ScrollContainer.new()
	body_scroll.name = "BodyScroll"
	body_scroll.custom_minimum_size.y = 80
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body_scroll.follow_focus = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	vbox.add_child(body_scroll)
	var actions := WrappingActions.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	var chrome := {"root": root, "title_bar": bar_panel, "title_label": title_label, "close_button": close_button, "body": body, "body_scroll": body_scroll, "actions": actions}
	root.set_meta("window_chrome",chrome)
	return chrome


## Constrain keyboard navigation only while this modal is visible. Dialog owners
## call after creating choices; ordinary information windows remain nonmodal.
static func contain_modal_focus(modal: Control, preferred: Control = null) -> void:
	var guard: ModalFocusGuard = modal.get_node_or_null("ModalFocusGuard") as ModalFocusGuard
	if guard == null:
		guard = ModalFocusGuard.new()
		guard.name = "ModalFocusGuard"
		modal.add_child(guard)
	guard.refresh(preferred)


class ModalFocusGuard:
	extends Node
	static var _active: Array[WeakRef] = []
	var previous: WeakRef
	var _preferred: WeakRef
	var _was_visible := false
	func _ready() -> void:
		(get_parent() as Control).visibility_changed.connect(_visibility_changed)
	func _visibility_changed() -> void:
		var modal := get_parent() as Control
		if not modal.is_visible_in_tree() and _was_visible:
			_was_visible = false
			_remove_active()
			var old := previous.get_ref() as Control if previous != null else null
			if is_instance_valid(old) and old.is_visible_in_tree(): old.grab_focus()
	func _exit_tree() -> void:
		_remove_active()
	func _remove_active() -> void:
		for i in range(_active.size()-1,-1,-1):
			if _active[i].get_ref() == null or _active[i].get_ref() == self: _active.remove_at(i)
	func _is_front() -> bool:
		for i in range(_active.size()-1,-1,-1):
			var guard := _active[i].get_ref() as ModalFocusGuard
			if guard == null or not (guard.get_parent() as Control).is_visible_in_tree():
				_active.remove_at(i)
			else: return guard == self
		return false
	func refresh(preferred: Control = null) -> void:
		var modal := get_parent() as Control
		if not modal.is_visible_in_tree(): return
		var current := modal.get_viewport().gui_get_focus_owner()
		if not _was_visible:
			previous = weakref(current) if current != null and not modal.is_ancestor_of(current) else null
			_was_visible = true
			_active.append(weakref(self))
		if preferred != null: _preferred = weakref(preferred)
		var controls: Array[Control] = []
		_collect(modal,controls)
		for i in controls.size():
			controls[i].focus_next = controls[i].get_path_to(controls[(i+1)%controls.size()])
			controls[i].focus_previous = controls[i].get_path_to(controls[posmod(i-1,controls.size())])
		if not _is_front(): return
		if preferred != null and preferred in controls:
			preferred.grab_focus()
		elif not controls.is_empty() and (current == null or not modal.is_ancestor_of(current)):
			var remembered := _preferred.get_ref() as Control if _preferred != null else null
			if remembered in controls: remembered.grab_focus()
			else: controls[0].grab_focus()
	func _collect(node: Node, result: Array[Control]) -> void:
		if node.is_queued_for_deletion() or node is Window: return
		if node is Control:
			if not node.is_visible_in_tree(): return
			if node.focus_mode == Control.FOCUS_ALL and not (node is BaseButton and node.disabled):
				result.append(node)
		for child: Node in node.get_children(): _collect(child,result)
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_TAB and _is_front():
			# Rebuild links when affordability or dynamic choices change.
			refresh()


## Drop-in HBoxContainer for dialog actions whose long labels can wrap onto
## more rows. Children are moved into an inner flow in their original order.
class WrappingActions:
	extends HBoxContainer
	var _flow := HFlowContainer.new()
	func _init() -> void:
		_flow.name = "WrappedActions"
		_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_flow)
		child_entered_tree.connect(func(child: Node) -> void:
			if child != _flow: _adopt.call_deferred())
	func _ready() -> void:
		_adopt.call_deferred()
	func _adopt() -> void:
		if not is_inside_tree(): return
		_flow.alignment = FlowContainer.ALIGNMENT_END if alignment == ALIGNMENT_END else FlowContainer.ALIGNMENT_BEGIN
		_flow.add_theme_constant_override("h_separation",get_theme_constant("separation"))
		_flow.add_theme_constant_override("v_separation",get_theme_constant("separation"))
		for child: Node in get_children():
			if child != _flow and child is Control: child.reparent(_flow,false)
		# The HBox now measures the flow's widest action, not the sum. Refit
		# panels after the temporary pre-adoption minimum and refresh focus
		# paths after reparenting; references to the buttons stay valid.
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor is ResponsivePanel: ancestor._schedule_fit()
			var guard := ancestor.get_node_or_null("ModalFocusGuard") as ModalFocusGuard
			if guard != null: guard.refresh.call_deferred()
			ancestor = ancestor.get_parent()

## A panel that refits itself on resize, even before Main registers it with
## DisplayLayout.
class ResponsivePanel:
	extends PanelContainer
	var preferred_size := Vector2.ZERO
	var _fit_pending := false
	func _ready() -> void:
		get_viewport().size_changed.connect(_schedule_fit)
		visibility_changed.connect(_schedule_fit)
		minimum_size_changed.connect(_schedule_fit)
		call_deferred("_initial_fit")
	func _exit_tree() -> void:
		if get_viewport().size_changed.is_connected(_schedule_fit):
			get_viewport().size_changed.disconnect(_schedule_fit)
	func _initial_fit() -> void:
		preferred_size = get_meta("preferred_size",size)
		set_meta("preferred_size",preferred_size)
		_fit()
	func _schedule_fit() -> void:
		if _fit_pending: return
		_fit_pending = true
		call_deferred("_fit")
	func _fit() -> void:
		_fit_pending = false
		if not is_inside_tree():
			return
		var available := get_viewport().get_visible_rect()
		available = get_meta("display_usable_rect",available)
		var wanted := preferred_size if preferred_size != Vector2.ZERO else size
		var fitted := DisplayLayout.fit_window_rect(Rect2(position,wanted),available,44.0)
		var chrome: Dictionary = get_meta("window_chrome",{})
		if chrome.has("body_scroll"):
			var column := (chrome.body_scroll as Control).get_parent() as VBoxContainer
			var chrome_height := get_theme_stylebox("panel").get_minimum_size().y + float(column.get_theme_constant("separation"))*2.0
			chrome_height += (chrome.title_bar as Control).get_combined_minimum_size().y + (chrome.actions as Control).get_combined_minimum_size().y
			(chrome.body_scroll as Control).custom_minimum_size.y = minf(80.0,maxf(0.0,fitted.size.y-chrome_height))
		if chrome.has("body"):
			for label: Label in (chrome.body as Control).find_children("*","Label",true,false):
				if not label.has_meta("report_original_wrap"):
					label.set_meta("report_original_wrap",label.autowrap_mode)
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if fitted.size.x < 600.0 else label.get_meta("report_original_wrap")
		position = fitted.position
		size = fitted.size

## Reports use the visible scroll width, not the overflowing body's width.
## A column reflow keeps every control and its signal connections.
static func report_scroll(node: Node) -> ScrollContainer:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: return ancestor
		ancestor = ancestor.get_parent()
	return null

class ResponsiveColumns:
	extends BoxContainer
	var _scroll: ScrollContainer
	var _reflow_pending := false
	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll = UIFactory.report_scroll(self)
		minimum_size_changed.connect(_queue_reflow)
		if _scroll != null:
			_scroll.resized.connect(_queue_reflow)
			_scroll.get_v_scroll_bar().visibility_changed.connect(_queue_reflow)
		_queue_reflow()
	func _queue_reflow() -> void:
		if _reflow_pending: return
		_reflow_pending=true
		_reflow.call_deferred()
	func _reflow() -> void:
		_reflow_pending=false
		if not is_instance_valid(_scroll): return
		var needed := float(get_theme_constant("separation"))*maxi(0,get_child_count()-1)
		for child in get_children():
			if child is Control and child.visible: needed += child.get_combined_minimum_size().x
		var available := _scroll.size.x
		var scrollbar := _scroll.get_v_scroll_bar()
		if scrollbar.is_visible_in_tree(): available -= scrollbar.size.x
		vertical = available < maxf(600.0,needed)

## Narrow financial/industry tables become labeled rows. The value and field
## nodes are moved, not copied; restoring width restores the grid.
class ResponsiveTable:
	extends GridContainer
	var has_headers := true
	var headings: Array[String] = []
	var _original: Array[Control] = []
	var _cards: Array[Control] = []
	var _wide_columns := 1
	var _narrow := false
	var _scroll: ScrollContainer
	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll = UIFactory.report_scroll(self)
		_capture.call_deferred()
	func _capture() -> void:
		_wide_columns = columns
		for child: Control in get_children(): _original.append(child)
		if has_headers:
			for index in _wide_columns: headings.append((_original[index] as Label).text)
		if _scroll != null:
			_scroll.resized.connect(_reflow)
			_scroll.get_v_scroll_bar().visibility_changed.connect(func() -> void: _reflow.call_deferred())
		_reflow()
	func _fit_captions() -> void:
		var available := _scroll.size.x
		var scrollbar := _scroll.get_v_scroll_bar()
		if scrollbar.is_visible_in_tree(): available -= scrollbar.size.x
		for card: Control in _cards:
			for row: HBoxContainer in card.get_children():
				if row.get_child_count() < 2: continue
				var caption := row.get_child(0) as Label
				var cell := row.get_child(1) as Control
				if caption == null: continue
				var longest_word := 0.0
				for word: String in caption.text.split(" "):
					longest_word = maxf(longest_word,caption.get_theme_font("font").get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,UITheme.FONT_SMALL).x)
				caption.custom_minimum_size.x = maxf(ceilf(longest_word),minf(96.0,available-cell.get_combined_minimum_size().x-row.get_theme_constant("separation")))
	func _reflow() -> void:
		if not is_instance_valid(_scroll) or _original.is_empty(): return
		var narrow := _scroll.size.x < 560.0
		if narrow == _narrow:
			if narrow: _fit_captions()
			return
		_narrow = narrow
		if not narrow:
			for index in _original.size():
				var cell := _original[index]
				if cell.get_parent() != self: cell.reparent(self,false)
				move_child(cell,index)
				if has_headers and index < _wide_columns: cell.show()
			for card in _cards:
				remove_child(card)
				card.queue_free()
			_cards.clear()
			columns = _wide_columns
			return
		columns = 1
		var first := _wide_columns if has_headers else 0
		for index in first: _original[index].hide()
		for start in range(first,_original.size(),_wide_columns):
			var card := VBoxContainer.new()
			card.add_theme_constant_override("separation",4)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			add_child(card)
			_cards.append(card)
			for offset in _wide_columns:
				if start+offset >= _original.size(): break
				var cell := _original[start+offset]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation",8)
				card.add_child(row)
				if offset > 0 and offset < headings.size() and not headings[offset].is_empty():
					var caption := UIFactory.make_label(headings[offset],UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
					caption.custom_minimum_size.x = 96.0
					row.add_child(caption)
				cell.reparent(row,false)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if cell is Label: cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fit_captions.call_deferred()

class ResponsiveTileGrid:
	extends GridContainer
	var _wide_columns := 1
	var _scroll: ScrollContainer
	func _ready() -> void:
		_wide_columns = columns
		_scroll = UIFactory.report_scroll(self)
		if _scroll != null: _scroll.resized.connect(_reflow)
		_reflow.call_deferred()
	func _reflow() -> void:
		if not is_instance_valid(_scroll): return
		var narrow := _scroll.size.x < 560.0
		columns = 1 if narrow else _wide_columns
		for child: Control in get_children():
			if child.get_class() == "Control": child.visible = not narrow
