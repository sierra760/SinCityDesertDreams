# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Options window: display, graphics, control and general preferences
## that persist between sessions. City settings live in their own menus and
## windows. Every change is emitted as
## `option_changed(key, value)`; the host applies and persists it.
class_name OptionsWindow
extends Control

signal option_changed(key: StringName, value: Variant)
signal closed

var panel: PanelContainer
var checks: Dictionary = {}
var scale_button: OptionButton
var quality_button: OptionButton
var resolution_button: OptionButton
var mayor_edit: LineEdit
var character_button: OptionButton
const QUALITY_VALUES := ["high", "balanced", "performance"]
const RESOLUTION_VALUES := [100, 75, 50]
var effective_label: Label
var done_button: Button
const SCALE_VALUES := [0,100,125,150,175,200]
var _updating := false
var _mobile_display := MobilePlatform.is_mobile()
var controls := ControlBindings.new()
var keyboard_section: VBoxContainer
var sensitivity_slider: HSlider
var music_slider: HSlider
var effects_slider: HSlider
## Percentage readouts beside the volume sliders, by volume key.
var volume_labels: Dictionary = {}
var invert_check: CheckBox
var tabs: TabBar
var display_page: VBoxContainer
var controls_page: VBoxContainer
var binding_buttons: Dictionary = {}
var binding_hint: Label
var _footer_label: Label
var _guidance_label: Label
const TOUCH_GUIDANCE := "Build: drag with one finger to preview; lift to apply. Add a second finger to cancel, then pan or pinch.\nExplore: movement pad on the left; drag on the right to look. Menu pauses movement; Resume starts it again."
const MOUSE_GUIDANCE := "Build: left drag uses your tool, right click inspects, middle drag pans and the wheel zooms.\nExplore: move the mouse to orbit. Escape opens the menu; Resume captures the pointer."
var _groups: Dictionary = {}
var _fullscreen_binding_row: Array[Control] = []
var _capture_action: StringName = &""
var _capture_slot := 0
var _keyboard_available := MobilePlatform.has_keyboard()
var _keyboard_poll := 0.0
var _release_code := 0


func _init() -> void:
	name = "OptionsWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	var chrome := UIFactory.make_window_chrome("Settings")
	panel = chrome["root"]
	panel.name = "Panel"
	(chrome["close_button"] as Button).pressed.connect(close)
	var root_body: VBoxContainer = chrome["body"]
	tabs = TabBar.new()
	tabs.custom_minimum_size.y = 44
	tabs.add_tab("General")
	tabs.add_tab("Controls")
	tabs.add_theme_stylebox_override("tab_unselected",UITheme.button_stylebox())
	tabs.add_theme_stylebox_override("tab_selected",UITheme.button_stylebox(true))
	tabs.add_theme_stylebox_override("tab_hovered",UITheme.button_stylebox())
	tabs.add_theme_font_size_override("font_size",UITheme.FONT_BODY)
	tabs.add_theme_color_override("font_unselected_color",UITheme.TEXT_PRIMARY)
	tabs.add_theme_color_override("font_hovered_color",UITheme.TEXT_PRIMARY)
	tabs.add_theme_color_override("font_selected_color",UITheme.TITLE_TEXT)
	# Separate the tab faces and give each a comfortable width.
	tabs.add_theme_constant_override("tab_separation",8)
	for state: String in ["tab_unselected","tab_selected","tab_hovered"]:
		var face := tabs.get_theme_stylebox(state).duplicate() as StyleBox
		face.content_margin_left = maxf(face.content_margin_left,24.0)
		face.content_margin_right = maxf(face.content_margin_right,24.0)
		tabs.add_theme_stylebox_override(state,face)
	root_body.add_child(tabs)
	display_page = VBoxContainer.new()
	display_page.add_theme_constant_override("separation",UITheme.VSEP)
	root_body.add_child(display_page)
	var body := display_page
	body.add_child(UIFactory.make_section_header("Mayor"))
	body.add_child(UIFactory.make_label("Your name"))
	mayor_edit = LineEdit.new()
	mayor_edit.name = "MayorName"
	mayor_edit.placeholder_text = "Mayor"
	mayor_edit.max_length = ViewPreferences.MAYOR_NAME_LIMIT
	mayor_edit.custom_minimum_size.y = 44
	mayor_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mayor_edit.expand_to_text_length = false
	mayor_edit.text_changed.connect(func(value: String) -> void: _changed(&"mayor_name",value))
	body.add_child(mayor_edit)
	var mayor_hint := UIFactory.make_label("Used in your welcome and new cities. Changing it here also updates the open city.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	mayor_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(mayor_hint)
	var ramps_check := CheckBox.new()
	ramps_check.text = "Ask about highway ramps"
	ramps_check.custom_minimum_size.y = 44
	ramps_check.tooltip_text = "After a road or highway meets a highway, ask whether to add ramps there."
	ramps_check.toggled.connect(func(on: bool) -> void: _changed(&"offer_ramps",on))
	checks[&"offer_ramps"] = ramps_check
	body.add_child(ramps_check)
	body.add_child(UIFactory.make_section_header("Explore"))
	body.add_child(UIFactory.make_label("Pedestrian character"))
	character_button = OptionButton.new()
	character_button.name = "PedestrianCharacter"
	character_button.custom_minimum_size.y = 44
	# The full roster can open over its button when clamped to a small screen.
	# Open after release so that same release cannot pick an unintended row.
	character_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	character_button.fit_to_longest_item = false
	character_button.clip_text = true
	character_button.tooltip_text = "Choose the character you control while exploring your city."
	for character: String in ViewPreferences.EXPLORE_CHARACTERS:
		character_button.add_item(ExploreCharacterCatalog.display_name(character))
	character_button.item_selected.connect(func(index: int) -> void: _changed(&"explore_character",ViewPreferences.EXPLORE_CHARACTERS[index]))
	body.add_child(character_button)
	var background_check := CheckBox.new()
	background_check.text = "Pause while in the background"
	background_check.custom_minimum_size.y = 44
	background_check.tooltip_text = "Time stops while another window is in front and resumes when you return."
	# Mobile builds always pause and save a recovery copy in the background.
	background_check.visible = not _mobile_display
	background_check.toggled.connect(func(on: bool) -> void: _changed(&"pause_in_background",on))
	checks[&"pause_in_background"] = background_check
	body.add_child(background_check)
	body.add_child(UIFactory.make_section_header("Display"))
	scale_button = OptionButton.new()
	scale_button.name = "UIScale"
	scale_button.custom_minimum_size.y = 44
	for percent in SCALE_VALUES:
		scale_button.add_item("Auto" if percent == 0 else "%d%%" % percent,percent)
	scale_button.item_selected.connect(func(index: int) -> void: _changed(&"ui_scale",SCALE_VALUES[index]))
	body.add_child(UIFactory.make_label("Interface size"))
	body.add_child(scale_button)
	effective_label = UIFactory.make_label("",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	effective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(effective_label)
	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = fullscreen_caption(controls.caption(&"fullscreen"))
	fullscreen_check.custom_minimum_size.y = 44
	fullscreen_check.visible = not _mobile_display
	fullscreen_check.disabled = _mobile_display
	fullscreen_check.toggled.connect(func(on: bool) -> void: _changed(&"fullscreen",on))
	checks[&"fullscreen"] = fullscreen_check
	body.add_child(fullscreen_check)
	body.add_child(UIFactory.make_section_header("Graphics"))
	var graphics_row := UIFactory.ResponsiveTileGrid.new()
	graphics_row.columns = 2
	graphics_row.add_theme_constant_override("h_separation", 12)
	graphics_row.add_theme_constant_override("v_separation", 8)
	graphics_row.add_child(UIFactory.make_label("3D quality"))
	quality_button = OptionButton.new()
	quality_button.custom_minimum_size.y = 44
	quality_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_button.tooltip_text = "High retains full shadows. Balanced reduces detail at a distance. Performance turns off shadows."
	for quality: String in QUALITY_VALUES:
		quality_button.add_item(quality.capitalize())
	quality_button.item_selected.connect(func(index: int) -> void: _changed(&"render_quality", QUALITY_VALUES[index]))
	graphics_row.add_child(quality_button)
	graphics_row.add_child(UIFactory.make_label("Resolution"))
	resolution_button = OptionButton.new()
	resolution_button.custom_minimum_size.y = 44
	resolution_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_button.tooltip_text = "Lower the 3D image resolution for faster rendering. Interface text stays sharp."
	for percent: int in RESOLUTION_VALUES:
		resolution_button.add_item("%d%%" % percent)
	resolution_button.item_selected.connect(func(index: int) -> void: _changed(&"render_scale", RESOLUTION_VALUES[index]))
	graphics_row.add_child(resolution_button)
	var grid_check := CheckBox.new()
	grid_check.text = "Show tile grid"
	grid_check.custom_minimum_size.y = 44
	grid_check.tooltip_text = "Faint tile boundaries follow the ground and soften in the distance."
	grid_check.toggled.connect(func(on: bool) -> void: _changed(&"tile_grid",on))
	checks[&"tile_grid"] = grid_check
	graphics_row.add_child(grid_check)
	var water_check := CheckBox.new()
	water_check.text = "Animate water"
	water_check.custom_minimum_size.y = 44
	water_check.toggled.connect(func(on: bool) -> void: _changed(&"water_animation",on))
	checks[&"water_animation"] = water_check
	graphics_row.add_child(water_check)
	body.add_child(graphics_row)
	body.add_child(UIFactory.make_section_header("Sound"))
	var sound_row := UIFactory.ResponsiveTileGrid.new()
	sound_row.columns = 2
	sound_row.add_theme_constant_override("h_separation", 12)
	sound_row.add_theme_constant_override("v_separation", 8)
	music_slider = _volume_row(sound_row, "Music", &"music_enabled", &"music_volume")
	effects_slider = _volume_row(sound_row, "Sound effects", &"effects_enabled", &"effects_volume")
	body.add_child(sound_row)
	var hint := UIFactory.make_label("Map visibility and zoom: View menu. Automatic budgeting: Reports → Budget. Disasters: Disasters menu.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	_build_controls(root_body)
	tabs.tab_changed.connect(func(index: int) -> void:
		cancel_capture()
		display_page.visible = index == 0
		controls_page.visible = index == 1)
	var footer := UIFactory.make_label("Changes apply immediately.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_footer_label = footer
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size.x = 180
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(chrome["actions"] as HBoxContainer).add_child(footer)
	done_button = UIFactory.make_button("Done")
	done_button.pressed.connect(close)
	(chrome["actions"] as HBoxContainer).add_child(done_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -300
	panel.offset_bottom = 300
	panel.set_meta("preferred_size",Vector2(560,600))
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	WindowDrag.enable(chrome["title_bar"], panel)


## A checkbox that turns a sound group on or off, beside its volume slider
## and the slider's percentage. A switched-off group's slider is inactive.
func _volume_row(row: Control, label: String, enabled_key: StringName, volume_key: StringName) -> HSlider:
	var check := CheckBox.new()
	check.text = label
	check.custom_minimum_size.y = 44
	checks[enabled_key] = check
	row.add_child(check)
	var level := HBoxContainer.new()
	level.add_theme_constant_override("separation", 8)
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(level)
	var slider := HSlider.new()
	slider.name = String(volume_key).capitalize().replace(" ", "")
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 0.8
	slider.custom_minimum_size = Vector2(120, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = label + " volume"
	level.add_child(slider)
	var percent := UIFactory.make_label(volume_percent(slider.value), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	percent.name = slider.name + "Percent"
	percent.custom_minimum_size.x = 44
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level.add_child(percent)
	volume_labels[volume_key] = percent
	check.toggled.connect(func(on: bool) -> void:
		slider.editable = on
		_changed(enabled_key, on))
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = volume_percent(value)
		_changed(volume_key, value))
	return slider


static func volume_percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


## The fullscreen checkbox caption. macOS keeps F11 for Show Desktop, so the
## Mac chord Ctrl+Cmd+F is named there (with any key the player bound).
static func fullscreen_caption(bound_key: String) -> String:
	if OS.get_name() != "macOS": return "Fullscreen [%s]" % bound_key
	if bound_key == ControlBindings.key_caption(KEY_F11): return "Fullscreen [Ctrl+Cmd+F]"
	return "Fullscreen [Ctrl+Cmd+F or %s]" % bound_key


func _changed(key: StringName, value: Variant) -> void:
	if _updating:
		return
	# Any other change ends a key capture, so a later key press is not bound
	# without the visible "Press key…" prompt.
	if key != &"control_bindings": cancel_capture()
	option_changed.emit(key, value)


func bind(_sim: Simulation) -> void:
	pass


func refresh() -> void:
	pass


## Set controls without emitting changes.
func set_values(values: Dictionary) -> void:
	_updating = true
	if values.has("mayor_name") and not mayor_edit.has_focus(): mayor_edit.text = String(values.mayor_name)
	if values.has("explore_character"):
		character_button.select(maxi(0,ViewPreferences.EXPLORE_CHARACTERS.find(values.explore_character)))
	if values.has("control_bindings"):
		controls.configure(values.control_bindings)
		_refresh_bindings()
		# A refresh from elsewhere keeps an active capture's prompt visible.
		if is_capturing(): (binding_buttons[String(_capture_action)][_capture_slot] as Button).text = "Press key…"
	if values.has("explore_sensitivity"): sensitivity_slider.value = float(values.explore_sensitivity)
	if values.has("music_volume"): music_slider.value = float(values.music_volume)
	if values.has("effects_volume"): effects_slider.value = float(values.effects_volume)
	if values.has("explore_invert_y"): invert_check.button_pressed = bool(values.explore_invert_y)
	if values.has("render_quality"):
		quality_button.select(maxi(0, QUALITY_VALUES.find(values.render_quality)))
	if values.has("render_scale"):
		resolution_button.select(maxi(0, RESOLUTION_VALUES.find(values.render_scale)))
	for key in checks:
		if values.has(String(key)) or values.has(key):
			var v: Variant = values.get(String(key), values.get(key, false))
			(checks[key] as CheckBox).button_pressed = bool(v)
	# A switched-off sound group's slider is inactive (toggled may not fire
	# when the value is unchanged).
	music_slider.editable = (checks[&"music_enabled"] as CheckBox).button_pressed
	effects_slider.editable = (checks[&"effects_enabled"] as CheckBox).button_pressed
	if values.has("ui_scale"):
		var selected := SCALE_VALUES.find(int(values["ui_scale"]))
		scale_button.select(maxi(selected,0))
	if values.has("effective_percent"):
		set_display_metrics({"requested_percent":scale_button.get_selected_id(),"effective_percent":values["effective_percent"]})
	_updating = false


func values() -> Dictionary:
	var out := {}
	out["mayor_name"] = ViewPreferences.clean_mayor_name(mayor_edit.text)
	out["explore_character"] = ViewPreferences.EXPLORE_CHARACTERS[character_button.selected]
	for key in checks:
		out[String(key)] = (checks[key] as CheckBox).button_pressed
	out["ui_scale"] = scale_button.get_selected_id()
	out["render_quality"] = QUALITY_VALUES[quality_button.selected]
	out["render_scale"] = RESOLUTION_VALUES[resolution_button.selected]
	out["control_bindings"] = controls.values()
	out["explore_sensitivity"] = sensitivity_slider.value
	out["music_volume"] = music_slider.value
	out["effects_volume"] = effects_slider.value
	out["explore_invert_y"] = invert_check.button_pressed
	return out


func open() -> void:
	set_keyboard_available(MobilePlatform.has_keyboard())
	visible = true


func close() -> void:
	if not visible:
		return
	cancel_capture()
	visible = false
	closed.emit()

func set_display_metrics(metrics: Dictionary) -> void:
	_mobile_display = bool(metrics.get("mobile",_mobile_display))
	var fullscreen_check: CheckBox = checks[&"fullscreen"]
	fullscreen_check.visible = not _mobile_display
	fullscreen_check.disabled = _mobile_display
	checks[&"pause_in_background"].visible = not _mobile_display
	for control: Control in _fullscreen_binding_row: control.visible = not _mobile_display
	_guidance_label.text = TOUCH_GUIDANCE if _mobile_display or MobilePlatform.uses_touch() else MOUSE_GUIDANCE
	var requested := int(metrics.get("requested_percent",0))
	var effective := float(metrics.get("effective_percent",100.0))
	var wanted := float(requested) if requested > 0 else 100.0
	effective_label.text = "Effective size: %d%% (capped to fit this window)" % roundi(effective) if effective < wanted - 0.01 else "Auto follows this display's pixel density." if requested == 0 else ""
	effective_label.visible = not effective_label.text.is_empty()

func _build_controls(body: VBoxContainer) -> void:
	controls_page = VBoxContainer.new()
	controls_page.add_theme_constant_override("separation",UITheme.VSEP)
	body.add_child(controls_page)
	controls_page.hide()
	controls_page.add_child(UIFactory.make_section_header("Explore camera"))
	controls_page.add_child(UIFactory.make_label("Look sensitivity"))
	sensitivity_slider = HSlider.new()
	sensitivity_slider.name = "Sensitivity"
	sensitivity_slider.min_value = .25
	sensitivity_slider.max_value = 3.0
	sensitivity_slider.step = .05
	sensitivity_slider.value = 1.0
	sensitivity_slider.custom_minimum_size.y = 44
	sensitivity_slider.value_changed.connect(func(value: float) -> void: _changed(&"explore_sensitivity",value))
	controls_page.add_child(sensitivity_slider)
	invert_check = CheckBox.new()
	invert_check.name = "InvertY"
	invert_check.text = "Invert vertical look"
	invert_check.custom_minimum_size.y = 44
	invert_check.toggled.connect(func(on: bool) -> void: _changed(&"explore_invert_y",on))
	controls_page.add_child(invert_check)
	controls_page.add_child(UIFactory.make_section_header("Touch & mouse"))
	var guidance := UIFactory.make_label(TOUCH_GUIDANCE if MobilePlatform.uses_touch() else MOUSE_GUIDANCE,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	_guidance_label = guidance
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_page.add_child(guidance)
	keyboard_section = VBoxContainer.new()
	keyboard_section.name = "KeyboardBindings"
	keyboard_section.add_theme_constant_override("separation",UITheme.VSEP)
	controls_page.add_child(keyboard_section)
	keyboard_section.add_child(UIFactory.make_section_header("Keyboard"))
	binding_hint = UIFactory.make_label("Select a key to change it. Escape cancels. Backspace clears an alternate.",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	binding_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keyboard_section.add_child(binding_hint)
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	for group: String in ControlBindings.GROUPS: picker.add_item(group)
	keyboard_section.add_child(picker)
	for group: String in ControlBindings.GROUPS:
		var rows := GridContainer.new()
		rows.columns = 3
		rows.add_theme_constant_override("h_separation",8)
		rows.add_theme_constant_override("v_separation",6)
		keyboard_section.add_child(rows)
		_groups[group] = rows
		rows.visible = group == "Build"
		for action: String in ControlBindings.GROUPS[group]:
			var label := UIFactory.make_label(ControlBindings.LABELS[action])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = 96
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.add_child(label)
			if action == "fullscreen":
				_fullscreen_binding_row.append(label)
				label.visible = not _mobile_display
			var buttons: Array[Button] = []
			for slot: int in 2:
				var button := UIFactory.make_button(controls.caption(StringName(action),slot))
				button.custom_minimum_size.x = 88
				button.clip_text = true
				button.tooltip_text = "%s — %s" % [ControlBindings.LABELS[action],"primary key" if slot == 0 else "alternate key"]
				button.pressed.connect(begin_capture.bind(StringName(action),slot))
				rows.add_child(button)
				if action == "fullscreen":
					_fullscreen_binding_row.append(button)
					button.visible = not _mobile_display
				buttons.append(button)
			binding_buttons[action] = buttons
	picker.item_selected.connect(func(index: int) -> void:
		cancel_capture()
		for group: String in _groups: _groups[group].visible = group == picker.get_item_text(index))
	var escape_hint := UIFactory.make_label("Escape always closes a window or opens the Explore menu. Jump and vehicle brake may share a key.",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	escape_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keyboard_section.add_child(escape_hint)
	var restore := UIFactory.make_button("Restore default bindings")
	restore.pressed.connect(func() -> void:
		cancel_capture()
		controls.reset()
		_refresh_bindings()
		_changed(&"control_bindings",controls.values()))
	keyboard_section.add_child(restore)
	controls_page.move_child(keyboard_section,0)
	set_keyboard_available(_keyboard_available)

func _process(delta: float) -> void:
	if not visible: return
	_keyboard_poll -= delta
	if _keyboard_poll > 0: return
	_keyboard_poll = .5
	set_keyboard_available(MobilePlatform.has_keyboard())

func set_keyboard_available(on: bool) -> void:
	if _keyboard_available == on and keyboard_section.visible == on: return
	_keyboard_available = on
	if not on:
		cancel_capture()
		var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if focused != null and keyboard_section.is_ancestor_of(focused): done_button.grab_focus()
	keyboard_section.visible = on

func _refresh_bindings() -> void:
	for action: String in binding_buttons:
		for slot: int in 2:
			(binding_buttons[action][slot] as Button).text = controls.caption(StringName(action),slot)
			(binding_buttons[action][slot] as Button).tooltip_text = "%s: %s" % [ControlBindings.LABELS[action],controls.caption(StringName(action),slot)]
	(checks[&"fullscreen"] as CheckBox).text = fullscreen_caption(controls.caption(&"fullscreen"))

func begin_capture(action: StringName, slot: int) -> void:
	if not visible or not _keyboard_available: return
	cancel_capture()
	_capture_action = action
	_capture_slot = slot
	binding_hint.text = "Press a key for %s. Escape cancels." % ControlBindings.LABELS[String(action)]
	_footer_label.text = binding_hint.text
	(binding_buttons[String(action)][slot] as Button).text = "Press key…"

func is_capturing() -> bool:
	return not _capture_action.is_empty()

func cancel_capture() -> void:
	_capture_action = &""
	if binding_hint != null: binding_hint.text = "Select a key to change it. Escape cancels. Backspace clears an alternate."
	if _footer_label != null: _footer_label.text = "Changes apply immediately."
	_refresh_bindings()

## Main calls before shortcuts and GUI delivery, including after capture ends
## to consume the captured release. No city/actor action receives these events.
func capture_event(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	var code := ControlBindings.event_code(event)
	if code == _release_code and not event.pressed:
		_release_code = 0
		return true
	if not visible or not is_capturing(): return false
	if not event.pressed or event.echo: return true
	_release_code = code
	if code == KEY_ESCAPE:
		cancel_capture()
		return true
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		binding_hint.text = "Choose a single key without Ctrl, Cmd or Alt."
		_footer_label.text = binding_hint.text
		return true
	if code == KEY_BACKSPACE and _capture_slot == 1:
		controls.clear_alternate(_capture_action)
	else:
		var error := controls.assign(_capture_action,_capture_slot,code)
		if not error.is_empty():
			binding_hint.text = error + " Choose another key, or Escape to cancel."
			_footer_label.text = binding_hint.text
			return true
	cancel_capture()
	_changed(&"control_bindings",controls.values())
	return true
