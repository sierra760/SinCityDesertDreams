# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The city's file workflow: the New, Load, Save, Import and Share dialogs
## and file pickers, the save-before-leaving prompt, quitting, and writing
## named saves, the annual backup and the background recovery copy.
class_name CityFileFlow
extends Node

const BundledCities := preload("res://scripts/io/bundled_cities.gd")
const AUTOSAVE_NAME := "autosave"

var import_dialog: FileDialog
var native_load_dialog: FileDialog
## True while a file picker owns input.
var picker_modal := false
var _host: GameHost
var _share_return_path := ""
## A native close request that arrived while a dialog owned input.
var _quit_waiting := false
var _saved_content: Dictionary = {}
## The freshly generated (or reset) unfounded map, before any player edits.
## Regenerating land that still matches it asks nothing.
var _generated_content: Dictionary = {}
var _pending_city_action: StringName = &""
var _after_save_action: StringName = &""
var _save_name_submitted := false
var _failed_save_name := ""


func _init(host: GameHost) -> void:
	_host = host
	name = "CityFiles"


func open_new_city_dialog() -> void:
	var dialog := _host.new_city_dialog
	if dialog.is_open(): return
	if _host.title_screen.visible: _host.window_manager.close_all()
	_host.modal_layer.move_child(dialog, _host.modal_layer.get_child_count() - 1)
	_host.push_modal()
	dialog.open()


func open_load_dialog() -> void:
	var dialog := _host.load_dialog
	if dialog.is_open(): return
	if _host.title_screen.visible: _host.window_manager.close_all()
	_host.modal_layer.move_child(dialog, _host.modal_layer.get_child_count() - 1)
	_host.push_modal()
	var saves := SaveFormat.list_saves()
	var backup := SaveFormat.read_header(autosave_path())
	if not backup.is_empty():
		backup["automatic_backup"] = true
		saves.append(backup)
	var recovery := SaveFormat.read_header(application_recovery_path())
	if not recovery.is_empty():
		recovery["suspended_recovery"] = true
		saves.append(recovery)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	dialog.open(saves, BundledCities.entries())


## Write a share copy without changing the manual save path/checkpoint.
func prepare_city_share(path: String = "") -> Dictionary:
	if not path.is_empty(): return CityShare.copy_saved(path)
	if not _host.in_game: return {"ok":false,"error":"Open a city before sharing it."}
	var editing := _host.stage == GameHost.Stage.EDITING
	return CityShare.create_current(_host.sim.city,_host.sim.snapshot() if _host.stage == GameHost.Stage.PLAY else {},SaveFormat.STAGE_EDITING if editing else SaveFormat.STAGE_PLAY,_host.editing_params if editing else {})


## Reopen the Load browser on the save a share started from.
func restore_share_browser() -> void:
	var previous := _share_return_path
	_share_return_path = ""
	if previous.is_empty(): return
	open_load_dialog()
	var index := _host.load_dialog.paths.find(previous)
	if index >= 0: _host.load_dialog.select(index)


func request_city_share(path: String = "") -> void:
	var host := _host
	if host.loading_screen.visible or host.share_dialog.visible or picker_modal: return
	var from_browser := host.load_dialog.visible and not path.is_empty()
	if not from_browser and (host.modal_depth > 0 or host.window_manager.is_open("options") or not host.in_game): return
	if from_browser:
		_share_return_path = path
		host.load_dialog.close()
	var prepared: Variant = await host.run_loading("Preparing city to share…","Making a separate playable city copy.",prepare_city_share.bind(path))
	if not prepared is Dictionary or not bool(prepared.get("ok",false)):
		restore_share_browser()
		host.notices.show("Cannot Share",String(prepared.get("error","The city copy could not be prepared.")) if prepared is Dictionary else "The city copy could not be prepared.")
		return
	host.modal_layer.move_child(host.share_dialog,host.modal_layer.get_child_count()-1)
	host.push_modal()
	host.share_dialog.open(prepared)


func open_save_dialog() -> void:
	var dialog := _host.save_dialog
	if not _host.in_game or dialog.is_open():
		return
	_host.modal_layer.move_child(dialog, _host.modal_layer.get_child_count() - 1)
	_host.push_modal()
	var save_path := _host.save_path
	dialog.open(_failed_save_name if not _failed_save_name.is_empty() else (save_path.get_file().get_basename() if not save_path.is_empty() else _host.sim.city.name))


func open_import_dialog() -> void:
	if picker_modal: return
	if import_dialog == null:
		import_dialog = _make_city_picker("Import Classic City", "*.sc2 ; Classic city")
		# Classic files often arrive with other or missing extensions; let the
		# player pick any file. The importer rejects files that are not cities.
		import_dialog.add_filter("*", "All files")
		import_dialog.name = "ImportDialog"
		import_dialog.file_selected.connect(func(path: String) -> void:
			_end_file_picker()
			_host.run_loading("Importing classic city…",path.get_file(),_host.session.import_city.bind(path)))
	_host.push_modal()
	picker_modal = true
	import_dialog.popup_centered_ratio(0.7)


func open_native_load_dialog() -> void:
	if picker_modal: return
	if _host.load_dialog.is_open(): _host.load_dialog.close()
	if native_load_dialog == null:
		native_load_dialog = _make_city_picker("Open Saved City", "*.sc2d ; Desert Dreams city")
		native_load_dialog.file_selected.connect(func(path: String) -> void:
			_end_file_picker()
			_host.run_loading("Loading city…",path.get_file(),_host.session.load_city.bind(path)))
	_host.push_modal()
	picker_modal = true
	native_load_dialog.popup_centered_ratio(0.7)


func _make_city_picker(title: String, filter: String) -> FileDialog:
	var picker := FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# Changing file mode resets Godot's title; apply the task label afterward.
	picker.title = title
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray([filter])
	MobilePlatform.configure_file_picker(picker)
	UIFactory.polish_file_picker(picker)
	picker.canceled.connect(_end_file_picker)
	_host.add_child(picker)
	_host.shell.apply_popups(picker)
	return picker


func _end_file_picker() -> void:
	if not picker_modal: return
	picker_modal = false
	_host.pop_modal()


func quit_game() -> void:
	# A native close (Cmd+Q, the window's close button) can arrive while a
	# dialog, file picker or covered save owns input. Do not nest another
	# prompt or interrupt that work; resume the normal close flow when it ends.
	if _city_action_blocked() and _pending_city_action.is_empty() and _after_save_action.is_empty():
		_quit_waiting = true
		# A seated mayor is told why the close waits instead of nothing.
		if _host.is_casino_open(): _host.casino_overlay.say(CasinoLines.QUIT_SEATED)
		return
	request_city_action(&"quit")


## Continue a close request that waited for a dialog or save to finish.
func resume_waiting_quit() -> void:
	if _quit_waiting and not _city_action_blocked():
		_quit_waiting = false
		quit_game()


func _city_action_blocked() -> bool:
	return _host.modal_depth > 0 or picker_modal or _host.loading_screen.visible


func _quit_now() -> void:
	_host.force_close_casino()
	_host.street_names.leave()
	_host.sim.set_process(false)
	_host.explore_switch.dispose()
	_host.prefs.save()
	if _host.can_quit_application():
		get_tree().quit()
	else:
		# Finish the dialog's closed signal before freeing its host. A fresh Main
		# releases the city, simulation, queued notices and Explore resources.
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## What a save would write, for comparing with the last save when leaving;
## nothing is serialized in the frame loop. Pause and fractional scheduling
## time do not count as unsaved work.
func save_content() -> Dictionary:
	if not _host.in_game or _host.sim.city == null: return {}
	var sim := _host.sim
	var runtime := sim.snapshot() if _host.stage == GameHost.Stage.PLAY else {}
	runtime.erase("speed")
	runtime.erase("accumulator")
	return {"city": SaveFormat.encode_city(sim.city), "runtime": runtime,
		"stage": _host.stage, "generator": _host.editing_params}.duplicate(true)


func has_unsaved_changes() -> bool:
	return _host.in_game and (_saved_content.is_empty() or _saved_content != save_content())


## Record the current city as matching its file.
func mark_saved() -> void:
	_saved_content = save_content()


## Treat the current city as never saved.
func forget_saved() -> void:
	_saved_content = {}


## Record the current unfounded map as generated land with no player edits.
func mark_generated() -> void:
	_generated_content = save_content()


## True while the unfounded map is exactly as it was generated or reset.
func is_unchanged_generated_land() -> bool:
	return _host.in_game and _host.stage == GameHost.Stage.EDITING and not _generated_content.is_empty() and _generated_content == save_content()


## Forget the previous city's save state when another city is bound.
func reset() -> void:
	# A city is being replaced: a table still open refunds its round first.
	_host.force_close_casino()
	_saved_content = {}
	_generated_content = {}
	_failed_save_name = ""


## Leave the current city (New, Load, Import, Regenerate or Quit), first
## offering to save unsaved changes.
func request_city_action(action: StringName) -> void:
	# A dialog already open is handling the decision; don't nest another.
	if _city_action_blocked(): return
	if not _pending_city_action.is_empty() or not _after_save_action.is_empty(): return
	# Fresh land has nothing worth keeping: rolling another map needs no prompt.
	if not has_unsaved_changes() or (action == &"regenerate" and is_unchanged_generated_land()):
		_perform_city_action(action)
		return
	_pending_city_action = action
	_host.notices.queue("Save your city?", "Save changes to %s %s?" % [_host.sim.city.name, _leaving_phrase(action)],
		[["Cancel", &"cancel"], ["Don't Save", &"discard"], ["Save", &"save"]],
		func(choice: StringName) -> void:
			_pending_city_action = &""
			if choice == &"discard": _perform_city_action(action)
			elif choice == &"save":
				_after_save_action = action
				if _host.save_path.is_empty(): open_save_dialog()
				else: _save_current_with_loading(true))


## What the player is about to do, for the save-before-leaving question.
func _leaving_phrase(action: StringName) -> String:
	match action:
		&"new": return "before starting a new city"
		&"load": return "before loading another city"
		&"import": return "before importing a classic city"
		&"regenerate": return "before generating new land"
		&"quit": return "before quitting" if _host.can_quit_application() else "before closing it"
	return "before continuing"


func _perform_city_action(action: StringName) -> void:
	match action:
		&"new": open_new_city_dialog()
		&"load": _host.run_loading("Finding saved cities…","Reading your saved-city list.",open_load_dialog)
		&"import": open_import_dialog()
		&"regenerate": _host.run_loading("Generating terrain…","Preparing a fresh map with your terrain settings.",_host.session.regenerate)
		&"quit": _quit_now()


func _on_save_name_submitted(save_name: String) -> void:
	_save_name_submitted = true
	# SaveDialog emits its close signal after submission. Balance that modal
	# before opening a replacement/error notice or continuing a city action.
	request_save_as.call_deferred(save_name,true)


func _on_save_dialog_closed() -> void:
	_host.pop_modal()
	if not _save_name_submitted: _after_save_action = &""


## Save under `save_name`, asking before replacing an existing save.
func request_save_as(save_name: String, show_loading: bool = false) -> void:
	_save_name_submitted = false
	var clean := SaveDialog.clean_name(save_name)
	if clean.is_empty():
		_after_save_action = &""
		return
	if FileAccess.file_exists(save_path_for(clean)):
		_host.notices.queue("Replace saved city?", "A save named %s.sc2d already exists. Replace it with this city?" % clean,
			[["Cancel", &"cancel"], ["Replace", &"replace"]], func(choice: StringName) -> void:
				if choice == &"replace": _save_requested_name(clean,show_loading)
				else: _after_save_action = &"")
	else:
		_save_requested_name(clean,show_loading)


func _save_requested_name(save_name: String, show_loading: bool = false) -> void:
	var path: String
	if show_loading:
		path = String(await _host.run_loading("Saving city…",save_name+"."+SaveFormat.EXTENSION,save_city_as.bind(save_name)))
	else:
		path = save_city_as(save_name)
	if path.is_empty():
		_failed_save_name = save_name
		_after_save_action = &""
		return
	_failed_save_name = ""
	_finish_saved_action()


## City → Save: write the current file, or ask for a name the first time.
func save_from_menu() -> void:
	if _host.save_path.is_empty():
		open_save_dialog()
	else:
		_save_current_with_loading()


func _save_current_with_loading(continue_action: bool = false) -> void:
	var error: Variant = await _host.run_loading("Saving city…",_host.save_path.get_file(),save_city)
	if error == OK:
		if continue_action: _finish_saved_action()
	else:
		_after_save_action = &""


func _finish_saved_action() -> void:
	var action := _after_save_action
	_after_save_action = &""
	if not action.is_empty(): _perform_city_action(action)


## Path of a save file with this name in the save directory.
static func save_path_for(save_name: String) -> String:
	return SaveFormat.default_dir().path_join("%s.%s" % [SaveDialog.clean_name(save_name), SaveFormat.EXTENSION])


## Save to the current file, or to one named after the city.
func save_city() -> Error:
	if not _host.in_game:
		return ERR_UNAVAILABLE
	var path := _host.save_path if not _host.save_path.is_empty() else save_path_for(_host.sim.city.name)
	var error := write_save(path)
	if error == OK: _host.save_path = path
	return error


## Save under a new name; returns the path written (empty on failure).
func save_city_as(save_name: String) -> String:
	if not _host.in_game:
		return ""
	var path := save_path_for(save_name)
	if write_save(path) != OK:
		return ""
	_host.save_path = path
	return path


## Write the city to `path`. An unfounded map is written without a
## simulation snapshot and marked as still being shaped, with its generator
## settings.
func write_save(path: String) -> Error:
	var sim := _host.sim
	var err: Error
	if _host.stage == GameHost.Stage.EDITING:
		err = SaveFormat.save(path, sim.city, {}, SaveFormat.STAGE_EDITING, _host.editing_params)
	else:
		err = SaveFormat.save(path, sim.city, sim.snapshot())
	if err == OK:
		mark_saved()
		_host.show_message("Saved %s." % path.get_file())
	else:
		_host.notices.show("Cannot Save", "%s couldn't be saved. Check free space, or try Save As with another name." % sim.city.name)
	return err


## Managed recovery storage is separate from every player-named save.
static func autosave_path() -> String:
	return "user://autosaves".path_join("%s.%s" % [AUTOSAVE_NAME, SaveFormat.EXTENSION])


static func application_recovery_path() -> String:
	return "user://recovery/suspended.sc2d"


static func is_managed_recovery_path(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	for managed in [autosave_path(), application_recovery_path()]:
		if absolute == ProjectSettings.globalize_path(managed).simplify_path(): return true
	return false
