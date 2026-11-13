# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The result is read before choosing how to leave a dismissed tenure.
class_name MayoralRecallFlow
extends RefCounted

var _host: GameHost
var active := false
var reload_path := ""
var _paper: Control

func _init(host: GameHost) -> void:
	_host = host

func reset() -> void:
	active = false
	reload_path = ""
	if is_instance_valid(_paper) and _paper.closed.is_connected(_on_paper_closed):
		_paper.closed.disconnect(_on_paper_closed)
	_paper = null
	_host.release_sim_process_hold(&"recall")

func sync() -> void:
	if not _host.in_game or not _host.sim.is_mayor_dismissed(): return
	if active:
		if not is_instance_valid(_paper) and not _host.notice_dialog.is_open() and not _host.load_dialog.is_open() and not _host.loading_screen.visible:
			show_choices()
		return
	active = true
	_host.sim.set_speed(GameClock.Speed.PAUSED)
	_host.acquire_sim_process_hold(&"recall")
	_host.force_close_casino()
	_host.explore_switch.dispose()
	_host.interrupt_map_input()
	_host.street_names.leave()
	_host.notices.clear_pending()
	_host.notice_dialog.dismiss()
	_host.choice_dialog.cancel()
	_host.window_manager.close_all()
	_host.query_panel.close()
	_host.shell.phone_tools_open = false
	_host.shell.update_phone_tools()
	reload_path = latest_save()
	show_result()

func show_result() -> void:
	_paper = _host.window_manager.open("newspaper")
	if _paper == null:
		show_choices()
		return
	_paper.reparent(_host.modal_layer)
	_host.modal_layer.move_child(_paper, _host.modal_layer.get_child_count() - 1)
	_host.push_modal()
	_paper.closed.connect(_on_paper_closed, CONNECT_ONE_SHOT)

func _on_paper_closed() -> void:
	_paper = null
	_host.pop_modal()
	if active: show_choices()

func show_choices() -> void:
	if not active or not _host.sim.is_mayor_dismissed(): return
	var choices: Array = [["Load Latest Save", &"reload"], ["Return to Title", &"title"]]
	var message := "The recall passed and you have been removed from office. Your unsaved progress is lost. Load your most recent saved city to resume. Existing saves have been preserved."
	if reload_path.is_empty():
		message += "\n\nNo saved copy of this city was found on this device. Load another saved city or return to the title screen to start a new one."
		choices[0] = ["Load City…", &"load"]
	_host.notices.queue("Removed From Office", message, choices, answer)

func answer(choice: StringName) -> void:
	if not active: return
	match choice:
		&"reload":
			# The existing loader validates before replacing the active city.
			if not _host.session.load_city(reload_path): return
		&"load": _host.files.open_load_dialog()
		&"title":
			if not _host.files.finish_cloud_session(): return
			reset()
			# The removed mayor's city is paused for good; no later city inherits a stopped clock.
			_host.in_game = false
			_host.stage = GameHost.Stage.NONE
			_host._show_title()
		_:
			# Escape acknowledges neither a reload nor permission to keep playing.
			pass

## Local manual, annual and background copies are eligible. Cloud-only saves
## remain available through Load City. A name alone never identifies a city:
## also check the mayor, founding year and original simulation seed before selecting a recovery file.
func latest_save() -> String:
	var candidates: Array[String] = []
	if not _host.save_path.is_empty(): candidates.append(_host.save_path)
	for row in _host.files._load_entries():
		var path := String(row.get("path", ""))
		if not path.is_empty() and not candidates.has(path): candidates.append(path)
	var newest := ""
	var saved_at := -1
	for path in candidates:
		if not FileAccess.file_exists(path): continue
		var header := SaveFormat.read_header(path)
		if header.get("name", "") != _host.sim.city.name or header.get("mayor", "") != _host.sim.city.mayor: continue
		if int(header.get("saved_at", -1)) <= saved_at: continue
		var loaded := SaveFormat.load(path)
		if not loaded.ok or loaded.stage != SaveFormat.STAGE_PLAY: continue
		var city: City = loaded.city
		if city.founded_year != _host.sim.city.founded_year: continue
		if str(loaded.snapshot.get("rng_seed", "")) != str(_host.sim.rng.seed_value()): continue
		var recall: Dictionary = loaded.snapshot.get("systems", {}).get("casino", {}).get("recall", {})
		if bool(recall.get("dismissed", false)): continue
		newest = path
		saved_at = int(header.get("saved_at", -1))
	return newest
