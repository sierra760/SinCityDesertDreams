# SPDX-License-Identifier: GPL-3.0-or-later
## Explore Mods: one compact card per pack with an on/off checkbox. Reload,
## Reset progress and the source location live behind each card's Details,
## and packs are added with a file/folder picker or by dropping them here.
class_name ExploreModsPanel
extends Control
signal closed
const PACK_LIMIT := 8
const FILE_FILTER := "*.scddmod, *.zip ; Explore mod pack"
var registry: ExploreModRegistry
var service: ExploreModService
var progress: ExploreModProgress
var panel: PanelContainer
var body: VBoxContainer
## How many packs are on and when changes take effect.
var summary: Label
## Shown only when the Lua runtime cannot run on this computer.
var runtime_note: Label
## The outcome of the last action; hidden until something happens.
var status: Label
var rows: VBoxContainer
var picker: FileDialog
var _expanded := ""
var _reset_pending := ""

func _init() -> void:
	name = "ExploreModsPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Explore Mods")
	panel = chrome.root
	(chrome.close_button as Button).pressed.connect(close)
	body = chrome.body
	summary = _label("",body)
	summary.name = "Summary"
	runtime_note = _label("",body,UITheme.FONT_SMALL,UITheme.MONEY_NEGATIVE)
	runtime_note.name = "RuntimeNote"
	status = _label("",body,UITheme.FONT_BODY,UITheme.TITLE_BAR)
	status.name = "Status"
	status.visible = false
	var adding := HFlowContainer.new()
	adding.name = "AddPack"
	adding.add_theme_constant_override("h_separation",8)
	adding.add_theme_constant_override("v_separation",6)
	body.add_child(adding)
	var add_file := UIFactory.make_button("Add pack file…","Choose a .scddmod or .zip pack to add.")
	add_file.name = "AddPackFile"
	add_file.pressed.connect(_choose.bind(FileDialog.FILE_MODE_OPEN_FILE))
	adding.add_child(add_file)
	var add_folder := UIFactory.make_button("Add pack folder…","Choose a pack's source folder (the one holding its manifest).")
	add_folder.name = "AddPackFolder"
	add_folder.pressed.connect(_choose.bind(FileDialog.FILE_MODE_OPEN_DIR))
	adding.add_child(add_folder)
	_label("You can also drop a pack onto this window. Added packs start off, and opening a saved city never turns packs on.",body,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	rows = VBoxContainer.new()
	rows.name = "Packs"
	rows.add_theme_constant_override("separation",8)
	body.add_child(rows)
	var actions := chrome.actions as HBoxContainer
	var copy := UIFactory.make_button("Copy diagnostics","Copy a short error report for a pack author.")
	copy.name = "CopyDiagnostics"
	copy.pressed.connect(func() -> void:
		if registry != null:
			DisplayServer.clipboard_set(registry.diagnostic_text())
			_say("Copied the diagnostics report."))
	actions.add_child(copy)
	var done := UIFactory.make_primary_button("Done")
	done.name = "Done"
	done.pressed.connect(close)
	actions.add_child(done)
	panel.set_meta("preferred_size",Vector2(680,640))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340; panel.offset_right = 340
	panel.offset_top = -320; panel.offset_bottom = 320
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _label(text: String, parent: Node, font_size := UITheme.FONT_BODY, color := UITheme.TEXT_PRIMARY) -> Label:
	var label := UIFactory.make_label(text,font_size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _say(text: String) -> void:
	status.text = text
	status.visible = not text.is_empty()

func bind(value: ExploreModRegistry, current_service: ExploreModService) -> void:
	registry = value
	service = current_service
	registry.service = service
	refresh()

func refresh() -> void:
	if registry == null: return
	# Rebuilding the cards would otherwise drop keyboard focus to nowhere.
	var focused := ""
	if is_inside_tree():
		var owner_control := get_viewport().gui_get_focus_owner()
		if owner_control != null and rows.is_ancestor_of(owner_control): focused = owner_control.name
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var entries := registry.entries()
	var enabled := entries.filter(func(entry: Dictionary) -> bool: return entry.enabled).size()
	var at_limit := enabled >= PACK_LIMIT
	if entries.is_empty(): summary.text = "No packs are installed yet. Add one below."
	elif at_limit: summary.text = "%d of %d packs on, the most allowed. Turn one off to use another. Changes start when you resume Explore." % [enabled,PACK_LIMIT]
	else: summary.text = "%d of %d packs on. Tick a pack to turn it on; changes start when you resume Explore." % [enabled,PACK_LIMIT]
	var runtime := registry.runtime_label()
	runtime_note.text = runtime if runtime.begins_with("Runtime unavailable") else ""
	runtime_note.visible = not runtime_note.text.is_empty()
	for entry in entries:
		rows.add_child(_card(entry,at_limit))
	if not focused.is_empty():
		var again := rows.find_child(focused,true,false) as Control
		if again != null and again.focus_mode != Control.FOCUS_NONE: again.grab_focus.call_deferred()

func _card(entry: Dictionary, at_limit: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.FIELD_FACE if entry.enabled else UITheme.BUTTON_FACE
	style.border_color = UITheme.TITLE_BAR if entry.enabled else UITheme.DIVIDER
	style.set_border_width_all(2 if entry.enabled else UITheme.BORDER)
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(UITheme.MARGIN_COMPACT)
	style.content_margin_left = UITheme.MARGIN
	style.content_margin_right = UITheme.MARGIN
	card.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	card.add_child(column)
	if not entry.ok:
		card.name = "Unavailable"
		_label("This pack can't be loaded (%s)." % String(entry.code).replace("_"," "),column,UITheme.FONT_BODY,UITheme.MONEY_NEGATIVE)
		var where := _label(String(entry.path),column,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
		where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		return card
	var id: String = entry.manifest.id
	var title := String(entry.manifest.name)
	var expanded := _expanded == id
	card.name = "Pack_"+id
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",8)
	column.add_child(top)
	var toggle := CheckBox.new()
	toggle.name = "Toggle_"+id
	toggle.theme = UITheme.control_theme()
	toggle.text = title
	toggle.custom_minimum_size.y = 44
	toggle.add_theme_font_size_override("font_size",UITheme.FONT_HEADER)
	toggle.add_theme_color_override("font_color",UITheme.TEXT_PRIMARY)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.button_pressed = entry.enabled
	toggle.disabled = at_limit and not entry.enabled
	toggle.tooltip_text = "Eight packs is the most that can be on. Turn one off first." if toggle.disabled else ("Turn %s off" if entry.enabled else "Turn %s on") % title
	toggle.toggled.connect(func(on: bool) -> void: _result(registry.set_enabled(id,on),title,on))
	top.add_child(toggle)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var details := UIFactory.make_button("Hide details" if expanded else "Details","Reload, reset progress and the pack's location.")
	details.name = "Details_"+id
	details.flat = true
	details.pressed.connect(func() -> void:
		_expanded = "" if expanded else id
		_reset_pending = ""
		refresh())
	top.add_child(details)
	var description := _label(String(entry.manifest.get("description",id)),column,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	if not expanded:
		description.max_lines_visible = 2
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
		description.tooltip_text = description.text
		description.mouse_filter = Control.MOUSE_FILTER_PASS
	var state := ""
	var state_color := UITheme.MONEY_POSITIVE
	if entry.enabled: state = "On · starts when you resume Explore"
	if service != null and service.runtime.has_owner(id): state = "Running · paused while this window is open"
	if progress != null and not progress.get_state(id,int(entry.manifest.state_version)).ok:
		state = "Saved progress is from another version · open Details to reset it"
		state_color = UITheme.MONEY_NEGATIVE
	if not state.is_empty(): _label(state,column,UITheme.FONT_SMALL,state_color)
	var last_error := _last_error(id)
	if not last_error.is_empty():
		var problem := _label("Last error: "+last_error,column,UITheme.FONT_SMALL,UITheme.MONEY_NEGATIVE)
		problem.name = "Error_"+id
		if not expanded:
			problem.max_lines_visible = 2
			problem.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			problem.tooltip_text = problem.text
			problem.mouse_filter = Control.MOUSE_FILTER_PASS
	if expanded: _details(column,id,title,entry)
	return card

func _last_error(id: String) -> String:
	var last_error := ""
	var last_error_time := -1
	var errors: Array = registry.diagnostics.duplicate()
	if service != null: errors.append_array(service.runtime.diagnostics)
	for diagnostic: Dictionary in errors:
		if diagnostic.owner == id and diagnostic.reason != "disabled" and int(diagnostic.get("time_usec",0)) >= last_error_time:
			last_error = ExploreLuaBridge.diagnostic_summary(diagnostic)
			last_error_time = int(diagnostic.get("time_usec",0))
	return last_error

func _details(column: VBoxContainer, id: String, title: String, entry: Dictionary) -> void:
	var where := _label("Version %s · %s" % [String(entry.manifest.version),String(entry.source_path)],column,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation",8)
	buttons.add_theme_constant_override("v_separation",6)
	column.add_child(buttons)
	var reload_button := UIFactory.make_button("Reload","Read the pack's edited source again. Only this pack restarts when you resume Explore.")
	reload_button.name = "Reload_"+id
	reload_button.pressed.connect(func() -> void: _result(registry.reload(id,service == null or service.controller.is_suspended()),title))
	buttons.add_child(reload_button)
	var confirming := _reset_pending == id
	var reset := UIFactory.make_button("Yes, reset progress" if confirming else "Reset progress…","Clear this pack's progress in the current city.")
	reset.name = "Reset_"+id
	reset.disabled = progress == null
	reset.pressed.connect(func() -> void:
		if _reset_pending != id:
			_reset_pending = id
			refresh()
			_say("Resetting clears %s's progress in this city. Save the city afterward to keep the reset." % title)
			return
		if service != null: service.disable(id)
		progress.reset(id)
		_reset_pending = ""
		registry.changed.emit()
		refresh()
		_say("Reset %s's progress in this city." % title))
	buttons.add_child(reset)
	if confirming:
		var cancel := UIFactory.make_button("Keep progress")
		cancel.name = "KeepProgress_"+id
		cancel.pressed.connect(func() -> void:
			_reset_pending = ""
			refresh()
			_say(""))
		buttons.add_child(cancel)

func _choose(mode: FileDialog.FileMode) -> void:
	if picker == null:
		picker = FileDialog.new()
		picker.name = "PackPicker"
		picker.access = FileDialog.ACCESS_FILESYSTEM
		var start_dir := MobilePlatform.desktop_picker_start_dir()
		if not start_dir.is_empty(): picker.current_dir = start_dir
		MobilePlatform.configure_file_picker(picker)
		UIFactory.polish_file_picker(picker)
		picker.file_selected.connect(_import)
		picker.dir_selected.connect(_import)
		add_child(picker)
	picker.file_mode = mode
	# Changing the mode resets Godot's title, so set the task label afterward.
	picker.title = "Add a pack folder" if mode == FileDialog.FILE_MODE_OPEN_DIR else "Add a pack file"
	picker.filters = PackedStringArray([] if mode == FileDialog.FILE_MODE_OPEN_DIR else [FILE_FILTER])
	picker.popup_centered_ratio(0.7)

func _import(path: String) -> void:
	if registry == null or path.strip_edges().is_empty(): return
	_result(registry.import_pack(path.strip_edges()),"")

func _on_files_dropped(files: PackedStringArray) -> void:
	if not visible: return
	for path in files.slice(0,8): _import(path)

func _result(result: Dictionary, title: String, turning_on := false) -> void:
	refresh()
	var code := String(result.code)
	if result.ok:
		match code:
			"pending_resume": _say(("%s is on. It starts when you resume Explore." if turning_on else "%s is off.") % title)
			"imported_disabled": _say("Added %s. Tick it to turn it on." % _name_at(String(result.get("path",""))))
			"reloaded_pending_resume": _say("Reloaded %s. The new version starts when you resume Explore." % title)
			_: _say("Done.")
		return
	match code:
		"session_limit": _say("Eight packs is the limit. Turn a pack off before turning on or reloading another.")
		"pause_required": _say("Pause Explore before reloading a pack.")
		"duplicate_id": _say("That pack is already installed. Open its Details and choose Reload to pick up changes.")
		"installed_limit": _say("There's no room for more packs. Remove some from the mods folder first.")
		_: _say("Couldn't do that: %s." % code.replace("_"," "))

func _name_at(path: String) -> String:
	for entry in registry.entries():
		if entry.ok and String(entry.path) == path: return String(entry.manifest.name)
	return "the pack"

func open() -> void:
	_reset_pending = ""
	_expanded = ""
	_say("")
	refresh()
	show()
	if is_inside_tree() and not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)

func close() -> void:
	if is_inside_tree() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	hide()
	closed.emit()
