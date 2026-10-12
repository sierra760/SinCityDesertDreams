# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModsPanel
extends Control
signal closed
var registry: ExploreModRegistry
var service: ExploreModService
var progress: ExploreModProgress
var panel: PanelContainer
var body: VBoxContainer
var status: Label
var rows: VBoxContainer
var import_path: LineEdit
var _reset_pending := ""

func _init() -> void:
	name = "ExploreModsPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Explore Mods")
	panel = chrome.root
	(chrome.close_button as Button).pressed.connect(close)
	body = chrome.body
	status = _label("",body)
	_label("Enable packs here, then close this window and Resume Explore. Imported packs start disabled. Saved cities never enable packs.",body)
	import_path = LineEdit.new()
	import_path.name = "ImportPath"
	import_path.placeholder_text = "Source folder, .scddmod or .zip path"
	import_path.custom_minimum_size.y = 44
	import_path.max_length = 4096
	body.add_child(import_path)
	var import_button := UIFactory.make_button("Import source pack")
	import_button.name = "ImportPack"
	import_button.pressed.connect(func() -> void:
		if registry != null: _result(registry.import_pack(import_path.text.strip_edges())))
	body.add_child(import_button)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	body.add_child(rows)
	var copy := UIFactory.make_button("Copy diagnostics")
	copy.pressed.connect(func() -> void:
		if registry != null:
			DisplayServer.clipboard_set(registry.diagnostic_text())
			status.text = "Copied bounded diagnostics.")
	body.add_child(copy)
	var done := UIFactory.make_button("Done")
	done.pressed.connect(close)
	(chrome.actions as HBoxContainer).add_child(done)
	panel.set_meta("preferred_size",Vector2(640,640))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320; panel.offset_right = 320
	panel.offset_top = -320; panel.offset_bottom = 320
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _label(text: String, parent: Node) -> Label:
	var label := UIFactory.make_label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func bind(value: ExploreModRegistry, current_service: ExploreModService) -> void:
	registry = value
	service = current_service
	registry.service = service
	refresh()

func refresh() -> void:
	if registry == null: return
	status.text = registry.runtime_label()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for entry in registry.entries():
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation",6)
		rows.add_child(card)
		if not entry.ok:
			_label("Unavailable pack: "+String(entry.code),card)
			_label(String(entry.path),card)
			continue
		var id: String = entry.manifest.id
		_label(String(entry.manifest.name)+" · "+String(entry.manifest.version),card)
		_label(String(entry.manifest.get("description",id)),card)
		var state := "Enabled • starts on Resume" if entry.enabled else "Disabled"
		if service != null and service.runtime.has_owner(id): state = "Running • paused while this window is open"
		if progress != null and not progress.get_state(id,int(entry.manifest.state_version)).ok: state = "Saved state version differs • reset to start"
		_label(state,card)
		var source_label := _label("Source: "+String(entry.source_path),card)
		source_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		var last_error := ""
		var last_error_time := -1
		var errors: Array = registry.diagnostics.duplicate()
		if service != null: errors.append_array(service.runtime.diagnostics)
		for diagnostic: Dictionary in errors:
			if diagnostic.owner == id and diagnostic.reason != "disabled" and int(diagnostic.get("time_usec",0)) >= last_error_time:
				last_error = ExploreLuaBridge.diagnostic_summary(diagnostic)
				last_error_time = int(diagnostic.get("time_usec",0))
		if not last_error.is_empty(): _label("Last error: "+last_error,card)
		var buttons := HFlowContainer.new()
		buttons.add_theme_constant_override("h_separation",8)
		buttons.add_theme_constant_override("v_separation",6)
		card.add_child(buttons)
		var toggle := UIFactory.make_button("Disable" if entry.enabled else "Enable")
		toggle.name = "Toggle_"+id
		toggle.pressed.connect(func() -> void: _result(registry.set_enabled(id,not entry.enabled)))
		buttons.add_child(toggle)
		var reload_button := UIFactory.make_button("Reload")
		reload_button.name = "Reload_"+id
		reload_button.tooltip_text = "Validate the edited source as a new version. Only this pack restarts on Resume."
		reload_button.pressed.connect(func() -> void: _result(registry.reload(id,service == null or service.controller.is_suspended())))
		buttons.add_child(reload_button)
		var reset := UIFactory.make_button("Confirm reset" if _reset_pending == id else "Reset progress")
		reset.name = "Reset_"+id
		reset.disabled = progress == null
		reset.pressed.connect(func() -> void:
			if _reset_pending != id:
				_reset_pending = id
				refresh()
				status.text = "Reset clears this pack's progress in the current city. Press Confirm reset to continue."
				return
			if service != null: service.disable(id)
			progress.reset(id)
			_reset_pending = ""
			registry.changed.emit()
			refresh())
		buttons.add_child(reset)

func _result(result: Dictionary) -> void:
	refresh()
	status.text = ("Ready: " if result.ok else "Could not apply: ")+String(result.code).replace("_"," ")
	if result.code == "session_limit": status.text = "Eight packs is the limit. Disable a pack before enabling or validating another."

func open() -> void:
	_reset_pending = ""
	refresh()
	show()
func close() -> void:
	hide()
	closed.emit()
