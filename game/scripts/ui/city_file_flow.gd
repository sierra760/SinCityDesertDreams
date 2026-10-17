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
const CLOUD_STORE_ROOT := "user://cloud-saves"
## Shown when a close request has to wait for an open window.
const QUIT_WAITING_MESSAGE := "Close the open window to quit."

var import_dialog: FileDialog
var native_load_dialog: FileDialog
## True while a file picker owns input.
var picker_modal := false
var _host: GameHost
var _share_return_path := ""
## A native close request that arrived while a dialog owned input.
var _quit_waiting := false
## The open-file picker was reached from Load City's Browse; Cancel returns there.
var _browse_from_load := false
var _saved_content: Dictionary = {}
## The freshly generated (or reset) unfounded map, before any player edits.
## Regenerating land that still matches it asks nothing.
var _generated_content: Dictionary = {}
var _pending_city_action: StringName = &""
var _after_save_action: StringName = &""
var _save_name_submitted := false
var _failed_save_name := ""
## The city this session loaded from, or wrote to, the background recovery
## copy. Only that city's named save supersedes the copy: another session's
## (possibly newer) copy of a city with the same name is never deleted.
var _recovery_city: WeakRef = null
var _recovery_path := ""
var _cloud_load_intent: Dictionary = {}
var _cloud_refresh_queued := false
var _last_sync_rows_key: Array = []


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
	dialog.set_sync_status(_host.cloud_saves.coordinator.status())
	dialog.open(_load_entries(), BundledCities.entries())
	_host.cloud_saves.coordinator.refresh(&"visible")


func _load_entries() -> Array[Dictionary]:
	var saves := SaveFormat.list_saves()
	var backup := SaveFormat.read_header(autosave_path())
	if not backup.is_empty():
		backup["automatic_backup"] = true
		saves.append(backup)
	for path in [application_recovery_path(), application_recovery_fallback_path()]:
		var recovery := SaveFormat.read_header(path)
		if not recovery.is_empty():
			recovery["suspended_recovery"] = true
			saves.append(recovery)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return _host.cloud_saves.coordinator.library_entries(saves)


func connect_cloud_library() -> void:
	var service := _host.cloud_saves.coordinator
	service.library_changed.connect(_queue_cloud_refresh)
	service.status_changed.connect(_sync_status_changed)
	_host.load_dialog.remote_load_requested.connect(_request_cloud_load)
	_host.load_dialog.manual_load_requested.connect(restore_last_manual_save)
	_host.load_dialog.selection_changed.connect(_cancel_cloud_load)
	_host.load_dialog.closed.connect(func() -> void:
		_cancel_cloud_load()
		service.refresh(&"hidden"))


func _sync_status_changed(status: Dictionary) -> void:
	_host.load_dialog.set_sync_status(status)
	var options := _host.windows.get("options") as OptionsWindow
	if options != null: options.set_sync_status(status)
	# Rows depend on the account and library, not on retry timing or counts;
	# library_changed covers content changes.
	var key := [status.get("state", ""), status.get("owner", ""), status.get("epoch", 0)]
	if key == _last_sync_rows_key: return
	_last_sync_rows_key = key
	_queue_cloud_refresh()


func _queue_cloud_refresh() -> void:
	if _cloud_refresh_queued: return
	_cloud_refresh_queued = true
	_refresh_cloud_library.call_deferred()


func _refresh_cloud_library() -> void:
	_cloud_refresh_queued = false
	if not _host.load_dialog.is_open(): return
	var status := _host.cloud_saves.coordinator.status()
	if not _cloud_load_intent.is_empty() and not _valid_cloud_intent(_cloud_load_intent): _cancel_cloud_load()
	_host.load_dialog.set_sync_status(status)
	_host.load_dialog.refresh(_load_entries(), BundledCities.entries())
	if _cloud_load_intent.is_empty(): return
	var entry := _cloud_entry(_cloud_load_intent.slot_id)
	if entry.is_empty():
		_cancel_cloud_load()
		return
	if entry.get("download_failed", false):
		_cancel_cloud_load()
		return
	if not entry.get("path", "").is_empty():
		var intent := _cloud_load_intent.duplicate(true)
		_cancel_cloud_load()
		_host.load_dialog.close()
		_host.run_loading("Loading city…", String(entry.get("name", "City")), _load_cloud_intent.bind(intent))
	elif not String(status.get("error", "")).is_empty():
		_cancel_cloud_load()


func _cloud_entry(id: String) -> Dictionary:
	for entry in _host.cloud_saves.coordinator.library_entries([]):
		if entry.get("slot_id", "") == id: return entry
	return {}


func _valid_cloud_intent(intent: Dictionary) -> bool:
	var status := _host.cloud_saves.coordinator.status()
	return not intent.get("owner", "").is_empty() and status.owner == intent.owner and status.epoch == intent.epoch and status.enabled


func _request_cloud_load(id: String) -> void:
	var service := _host.cloud_saves.coordinator
	var status := service.status()
	if not service.select_download(id, status.owner, status.epoch): return
	_cloud_load_intent = {"slot_id": id, "owner": status.owner, "epoch": status.epoch}
	_host.load_dialog.set_waiting(true)


func _cancel_cloud_load() -> void:
	_cloud_load_intent = {}
	_host.cloud_saves.coordinator.cancel_selected_download()
	_host.load_dialog.set_waiting(false)


func _load_cloud_intent(intent: Dictionary) -> bool:
	# A completion may arrive on the final draw boundary, before _process.
	_host.cloud_saves.coordinator.advance(Time.get_ticks_msec())
	if not _valid_cloud_intent(intent): return false
	var entry := _cloud_entry(intent.slot_id)
	var path := String(entry.get("path", ""))
	if path.is_empty(): return false
	return _host.session.load_city(path)


func load_selected_path(path: String) -> void:
	var entry := _host.load_dialog.selected_entry()
	if entry.get("cloud_owned", false):
		var status := _host.cloud_saves.coordinator.status()
		var intent := {"slot_id": entry.slot_id, "owner": status.owner, "epoch": status.epoch}
		_host.run_loading("Loading city…", String(entry.get("name", "City")), _load_cloud_intent.bind(intent))
	else:
		_host.run_loading("Loading city…", path.get_file(), _host.session.load_city.bind(path))


func restore_last_manual_save(id: String) -> void:
	var status := _host.cloud_saves.coordinator.status()
	var intent := {"slot_id": id, "owner": status.owner, "epoch": status.epoch}
	var entry := _cloud_entry(id)
	if not _valid_cloud_intent(intent) or entry.get("manual", {}).is_empty(): return
	_host.load_dialog.close()
	_host.run_loading("Loading last manual save…", String(entry.get("name", "City")), _restore_cloud_manual.bind(intent))


func _restore_cloud_manual(intent: Dictionary) -> Error:
	_host.cloud_saves.coordinator.advance(Time.get_ticks_msec())
	if not _valid_cloud_intent(intent): return ERR_UNAUTHORIZED
	var error := _host.cloud_saves.restore_selected_manual(intent.slot_id, intent.owner, intent.epoch)
	if error != OK: _host.notices.show("Cannot Load", "The last manual save could not be restored. Your current city is still open.")
	return error


## Write a share copy without changing the manual save path/checkpoint.
func prepare_city_share(path: String = "") -> Dictionary:
	if not path.is_empty(): return CityShare.copy_saved(path)
	if not _host.in_game: return {"ok":false,"error":"Open a city before sharing it."}
	var editing := _host.stage == GameHost.Stage.EDITING
	return CityShare.create_current(_host.sim.city,_host.sim.snapshot() if _host.stage == GameHost.Stage.PLAY else {},SaveFormat.STAGE_EDITING if editing else SaveFormat.STAGE_PLAY,_host.editing_params if editing else {},CityShare.DIRECTORY,_host.explore_progress_snapshot())


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
	if not from_browser and (host.modal_depth > 0 or not host.in_game): return
	# Settings is not modal; it steps aside rather than silently refusing Share.
	if host.window_manager.is_open("options"): host.window_manager.windows["options"].close()
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
	dialog.open(_failed_save_name if not _failed_save_name.is_empty() else (save_path.get_file().get_basename() if not save_path.is_empty() else _host.sim.city.name), {"population": _host.sim.stats.total_population() if _host.stage == GameHost.Stage.PLAY else 0, "tourists": _host.sim.stats.tourists if _host.stage == GameHost.Stage.PLAY else 0, "count_schema": 1})


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
	_browse_from_load = _host.load_dialog.is_open()
	if _host.load_dialog.is_open(): _host.load_dialog.close()
	if native_load_dialog == null:
		native_load_dialog = _make_city_picker("Open Saved City", "*.sc2d ; Desert Dreams city")
		native_load_dialog.file_selected.connect(func(path: String) -> void:
			_browse_from_load = false
			_end_file_picker()
			_host.run_loading("Loading city…",path.get_file(),_host.session.load_city.bind(path)))
		native_load_dialog.canceled.connect(_return_to_load_list)
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
	# A desktop picker otherwise opens in the process working directory (the
	# disk root for a Finder-launched app). It keeps the last folder after that.
	var start_dir := MobilePlatform.desktop_picker_start_dir()
	if not start_dir.is_empty(): picker.current_dir = start_dir
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


## Cancelling the picker opened from Load City's Browse returns to the list.
func _return_to_load_list() -> void:
	if not _browse_from_load: return
	_browse_from_load = false
	_host.run_loading("Finding saved cities…","Reading your saved-city list.",open_load_dialog)


func quit_game() -> void:
	raise_window_for_prompt()
	# A native close (Cmd+Q, the window's close button) can arrive while a
	# dialog, file picker or covered save owns input. Do not nest another
	# prompt or interrupt that work; resume the normal close flow when it ends.
	if _city_action_blocked() and _pending_city_action.is_empty() and _after_save_action.is_empty():
		# A form or file picker is closed as Cancel would, and the close goes on.
		_close_simple_dialogs()
		if not _city_action_blocked():
			request_city_action(&"quit")
			return
		_quit_waiting = true
		# The player is told why the close waits instead of nothing.
		if _host.is_casino_open(): _host.casino_overlay.say(CasinoLines.QUIT_SEATED)
		else: _host.show_message(QUIT_WAITING_MESSAGE)
		return
	request_city_action(&"quit")


## A close from the Dock, the taskbar or an OS logout can reach a minimized or
## background window. When a prompt may follow (a city is open, or a dialog
## holds the close), restore and raise the window first so the question is
## visible instead of the app seeming to refuse to quit. Returns the window
## mode restored from minimized, or -1.
func raise_window_for_prompt() -> int:
	if not (_host.in_game or _city_action_blocked()): return -1
	var layout: DisplayLayout = _host.display_layout
	var restored := layout.restore_from_minimized() if is_instance_valid(layout) else -1
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		var window := get_window()
		if window != null and not window.has_focus():
			window.move_to_foreground()
			window.request_attention()
	return restored


## Close the dialogs that only gather a choice (New City and its terrain
## chooser, Load, Save As, Share, file pickers and, before any city exists, an
## informational notice), as their Cancel would.
func _close_simple_dialogs() -> void:
	var host := _host
	for picker: FileDialog in [import_dialog, native_load_dialog]:
		if picker != null and picker.visible:
			picker.hide()
			_browse_from_load = false
			_end_file_picker()
	if host.share_dialog.is_open():
		_share_return_path = ""
		host.share_dialog.close()
	if host.save_dialog.is_open(): host.save_dialog.close()
	if host.load_dialog.is_open(): host.load_dialog.close()
	if host.new_city_dialog.is_open(): host.new_city_dialog.close()
	if not host.in_game and host.notice_dialog.is_open() and _pending_city_action.is_empty():
		host.notice_dialog.dismiss()


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
		"stage": _host.stage, "generator": _host.editing_params, "explore_mods": _host.explore_progress_snapshot()}.duplicate(true)


func has_unsaved_changes() -> bool:
	return _host.in_game and (_saved_content.is_empty() or _saved_content != save_content())


## Record the current city as matching its file.
func mark_saved() -> void:
	_saved_content = save_content()


## The content at the last local save or load ({} when never saved).
func saved_content() -> Dictionary:
	return _saved_content


## Restore the explicit manual baseline when loading a newer continuation.
func set_saved_content(content: Dictionary) -> void:
	_saved_content = content.duplicate(true)


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
	# A close that waited for a dialog is dropped when that dialog started or
	# loaded a city instead of being cancelled.
	_quit_waiting = false


## Leave the current city (New, Load, Import, Regenerate or Quit), first
## offering to save unsaved changes.
func request_city_action(action: StringName) -> void:
	# A dialog already open is handling the decision; don't nest another.
	if _city_action_blocked(): return
	if not _pending_city_action.is_empty() or not _after_save_action.is_empty(): return
	# Fresh generated land has nothing worth keeping (its seed rebuilds it), so
	# leaving it needs no prompt. Downloaded real-world land is still offered a
	# save except when rolling another map.
	var untouched := is_unchanged_generated_land()
	# A city reopened from its iCloud copy and left unchanged loses nothing.
	if not has_unsaved_changes() or (_host.cloud_saves != null and _host.cloud_saves.unchanged_since_opened()) \
			or (untouched and (action == &"regenerate" or _host.editing_params.get("source") != "real_world")):
		_perform_city_action(action)
		return
	_pending_city_action = action
	_host.notices.queue("Save Your City?", "Save changes to %s %s?" % [_host.sim.city.name, _leaving_phrase(action)],
		[["Cancel", &"cancel"], ["Don't Save", &"discard"], ["Save", &"save"]],
		func(choice: StringName) -> void:
			_pending_city_action = &""
			if choice == &"discard":
				# Load/New/Import can still be cancelled back to this same city.
				var cancellable := action in [&"new", &"load", &"import"]
				var error: Error = _host.cloud_saves.discard(cancellable) if _host.cloud_saves != null else OK
				if error == OK: _perform_city_action(action)
				else: _host.notices.show("Cannot Discard Yet", "Your local save choice could not be recorded. Check free space and try again.")
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
	# Saving over the file that is already open is an ordinary save.
	var same_file := not _host.save_path.is_empty() and ProjectSettings.globalize_path(save_path_for(clean)).simplify_path() == ProjectSettings.globalize_path(_host.save_path).simplify_path()
	if FileAccess.file_exists(save_path_for(clean)) and not same_file:
		_host.notices.queue("Replace Saved City?", "A save named %s.sc2d already exists. Replace it with this city?" % clean,
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
	var existed := FileAccess.file_exists(path)
	var error := write_save(path)
	if error == OK:
		_host.save_path = path
		if _host.cloud_saves != null: _host.cloud_saves.manual_saved(path, false, existed)
	return error


## Save under a new name; returns the path written (empty on failure).
func save_city_as(save_name: String) -> String:
	if not _host.in_game:
		return ""
	var path := save_path_for(save_name)
	var existed := FileAccess.file_exists(path)
	if write_save(path) != OK:
		return ""
	_host.save_path = path
	if _host.cloud_saves != null: _host.cloud_saves.manual_saved(path, true, existed)
	return path


## Write the city to `path`. An unfounded map is written without a
## simulation snapshot and marked as still being shaped, with its generator
## settings.
func write_save(path: String) -> Error:
	var sim := _host.sim
	var err: Error
	if _host.stage == GameHost.Stage.EDITING:
		err = SaveFormat.save(path, sim.city, {}, SaveFormat.STAGE_EDITING, _host.editing_params, _host.explore_progress_snapshot())
	else:
		err = SaveFormat.save(path, sim.city, sim.snapshot(), SaveFormat.STAGE_PLAY, {}, _host.explore_progress_snapshot())
	if err == OK:
		mark_saved()
		# A named save supersedes the background recovery copy this session
		# loaded or wrote; any other copy, even of a same-named city, stays.
		if not is_managed_recovery_path(path) and holds_recovery_copy(sim.city):
			discard_recovery_copy()
		_host.show_message("Saved %s." % path.get_file())
	else:
		_host.notices.show("Cannot Save", "%s couldn't be saved. Check free space, or try Save As with another name." % sim.city.name)
	return err


## Managed recovery storage is separate from every player-named save.
static func autosave_path() -> String:
	return "user://autosaves".path_join("%s.%s" % [AUTOSAVE_NAME, SaveFormat.EXTENSION])


static func application_recovery_path() -> String:
	return "user://recovery/suspended.sc2d"

static func application_recovery_fallback_path() -> String:
	return "user://recovery/suspended-untracked.sc2d"

static func recovery_destination_path() -> String:
	return "user://recovery/suspended-destination.json"

## While cloud sync is off, the tracked recovery keeps its named destination
## in this small note, bound to the exact recovery bytes it describes.
static func write_recovery_destination(recovery_path: String, manual_path: String) -> void:
	if not valid_recovery_destination(manual_path) or not FileAccess.file_exists(recovery_path):
		clear_recovery_destination()
		return
	var note := {"version": 1, "recovery": ProjectSettings.globalize_path(recovery_path).simplify_path(),
		"sha256": FileAccess.get_sha256(recovery_path), "manual": manual_path}
	if SaveFormat._write_replacement(recovery_destination_path(), JSON.stringify(note).to_utf8_buffer()) != OK:
		clear_recovery_destination()

## The named destination for exactly these recovery bytes, or "".
static func recovery_destination(recovery_path: String) -> String:
	var file := FileAccess.open(recovery_destination_path(), FileAccess.READ)
	if file == null or file.get_length() > 8192: return ""
	var note: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not note is Dictionary or note.get("version") != 1.0 or not note.get("manual") is String or not note.get("sha256") is String: return ""
	if note.get("recovery") != ProjectSettings.globalize_path(recovery_path).simplify_path(): return ""
	var manual: String = note.manual
	if not valid_recovery_destination(manual): return ""
	return manual if FileAccess.get_sha256(recovery_path) == note.sha256 else ""

## Only an ordinary personal save may be a recovery destination: never a cloud
## store payload, managed recovery/backup copy or other location.
static func valid_recovery_destination(path: String) -> bool:
	if path.is_empty() or path.to_utf8_buffer().size() > 4096 or not CloudSaveStore.personal_path(path) or is_managed_recovery_path(path): return false
	return not CloudSaveStore._inside_root(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(CLOUD_STORE_ROOT))

static func clear_recovery_destination() -> void:
	if FileAccess.file_exists(recovery_destination_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_destination_path()))

## A newer canonical write is already durable before retiring this old fallback.
func retire_fallback_recovery() -> void:
	var path := application_recovery_fallback_path()
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Remove the background recovery copy once it is no longer needed: the app
## came back cleanly, or the city it holds was saved under a name.
func discard_recovery_copy() -> void:
	_recovery_city = null
	var path := _recovery_path
	_recovery_path = ""
	if path.is_empty(): return
	if is_tracked_application_recovery_path(path): clear_recovery_destination()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Remember that `city` is the one in the background recovery copy: this
## session loaded it from there, or just wrote it there.
func note_recovery_copy(city: City, path: String = "") -> void:
	_recovery_city = weakref(city) if city != null else null
	_recovery_path = application_recovery_path() if path.is_empty() else path


## True when the background recovery copy holds this session's `city`.
func holds_recovery_copy(city: City) -> bool:
	if city == null or _recovery_city == null or _recovery_city.get_ref() != city:
		return false
	return not _recovery_path.is_empty() and FileAccess.file_exists(_recovery_path)


static func is_application_recovery_path(path: String) -> bool:
	return is_tracked_application_recovery_path(path) or _same_recovery_path(path, application_recovery_fallback_path())

static func is_tracked_application_recovery_path(path: String) -> bool:
	return _same_recovery_path(path, application_recovery_path())

static func _same_recovery_path(a: String, b: String) -> bool:
	return not a.is_empty() and not b.is_empty() and ProjectSettings.globalize_path(a).simplify_path() == ProjectSettings.globalize_path(b).simplify_path()


static func is_managed_recovery_path(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	for managed in [autosave_path(), application_recovery_path(), application_recovery_fallback_path()]:
		if absolute == ProjectSettings.globalize_path(managed).simplify_path(): return true
	return false
