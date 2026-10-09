# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The notice dialog's queue: one notice on screen at a time, each with its
## choices and a handler for the player's answer. Also turns the notices the
## simulation raises (rewards, objections, retired plants) into dialog specs.
class_name NoticeQueue
extends RefCounted

var _host: GameHost
var _queue: Array[Dictionary] = []
var _handler: Callable


func _init(host: GameHost) -> void:
	_host = host


## Flavour notices with nothing to decide: they go to the status line instead
## of pausing the city behind a dialog.
const STATUS_ONLY: Array[StringName] = [&"tree_protest", &"approval_milestone"]


## Show the notice for something the simulation raised, if it has one.
func raise(kind: StringName, payload: Dictionary) -> void:
	var spec := notice_for(kind, payload)
	if spec.is_empty():
		return
	if kind in STATUS_ONLY:
		_host.show_message(status_line(String(spec["title"]), String(spec["body"])))
		return
	if _host.audio != null:
		_host.audio.on_notice(kind)
	_host.refresh_toolbar()
	queue(String(spec["title"]), String(spec["body"]), spec.get("choices", [["OK", &"ok"]]),
		spec.get("handler", Callable()))


## Title, body, choices and handler for a notice kind; empty to show nothing.
## Text comes from `NoticeLines`.
func notice_for(kind: StringName, payload: Dictionary) -> Dictionary:
	match kind:
		&"newspaper":
			if not bool(payload.get("extra", false)):
				return {}
			var extra := lines(kind, payload)
			extra["choices"] = [["Read", &"read"], ["Close", &"ok"]]
			extra["handler"] = _on_newspaper_answered
			return extra
		&"reward_offered":
			return _reward_notice(payload)
		&"opposition":
			var objection := lines(kind, payload)
			objection["choices"] = [["Build Anyway", &"proceed"], ["Cancel", &"cancel"]]
			return objection
		&"plant_retired":
			var retired := lines(kind, payload)
			var anchor := NewsStories.position_of(payload.get("anchor", Vector2i(-1, -1)))
			if anchor.x >= 0 and _host.in_game:
				retired["choices"] = [["Show Me", &"show"], ["OK", &"ok"]]
				retired["handler"] = _on_retired_plant_answered.bind(anchor)
			return retired
	return lines(kind, payload)


func _reward_notice(payload: Dictionary) -> Dictionary:
	var key := StringName(String(payload.get("key", "")))
	var spec := lines(&"reward_offered", payload)
	if key == RewardParams.MILITARY_KEY:
		var site: Array = payload.get("site", [])
		if site.size() == 4:
			spec["body"] = "%s\n\nThe proposed site is %d tiles square at %d, %d." % [String(spec["body"]), int(site[2]), int(site[0]), int(site[1])]
		spec["choices"] = [["Accept", &"accept"], ["Decline", &"decline"]]
		spec["handler"] = _on_military_offer_answered
		return spec
	var reward_tool := reward_tool_for(key)
	spec["choices"] = [["Build Now", &"accept"], ["Later", &"ok"]]
	spec["handler"] = _on_reward_answered.bind(reward_tool)
	return spec


# Handlers are method callables rather than lambdas: a lambda would hold this
# queue alive from inside its own queue and leak it when the host is freed.

func _on_newspaper_answered(choice: StringName) -> void:
	if choice == &"read":
		_host.window_manager.open("newspaper")


func _on_retired_plant_answered(choice: StringName, anchor: Vector2i) -> void:
	if choice == &"show" and not _host.is_exploring():
		_host.city_view_3d.set_center_cell(anchor)


func _on_military_offer_answered(choice: StringName) -> void:
	answer_military_offer(choice == &"accept")


func _on_reward_answered(choice: StringName, reward_tool: int) -> void:
	if choice == &"accept" and reward_tool != GameHost.NO_TOOL:
		_host.select_tool(reward_tool)


## Accept or decline the pending military base through the rewards system.
func answer_military_offer(accept: bool) -> bool:
	var rewards := _host.sim.get_system(&"rewards")
	if rewards == null:
		return false
	if accept and rewards.has_method("accept_military"):
		var ok := bool(rewards.call("accept_military"))
		if ok:
			_host.sim.networks_changed()
		_host.refresh_toolbar()
		return ok
	if rewards.has_method("decline_military"):
		rewards.call("decline_military")
	return false


static func reward_tool_for(key: StringName) -> int:
	for t in Tools.all():
		if Tools.is_reward_tool(t) and Tools.reward_key(t) == key:
			return t
	return GameHost.NO_TOOL


## Title and body for a notice or prompt, filled with the city's values.
func lines(kind: StringName, payload: Dictionary) -> Dictionary:
	var sim := _host.sim
	var city_name := sim.city.name if sim.city != null else "the city"
	var mayor := sim.city.mayor if sim.city != null else "Mayor"
	var year := sim.clock.year() if sim.city != null else 0
	return NoticeLines.render(kind, payload, city_name, mayor, year)


## A notice condensed for the status line: its title and first sentence.
static func status_line(title: String, body: String) -> String:
	var first := body.strip_edges()
	var end := first.find(". ")
	if end >= 0:
		first = first.substr(0, end + 1)
	return "%s: %s" % [title, first] if not first.is_empty() else title


## A notice with a single OK button.
func show(title: String, body: String) -> void:
	queue(title, body, [["OK", &"ok"]], Callable())


## Queue a notice. `handler` receives the chosen key; a `prompt` notice also
## has a text field, filled with `initial`.
func queue(title: String, body: String, choices: Array, handler: Callable, prompt := false, initial := "") -> void:
	_queue.append({"title": title, "body": body, "choices": choices, "handler": handler,
		"prompt": prompt, "initial": initial})
	_show_next()


func _show_next() -> void:
	var dialog := _host.notice_dialog
	if dialog.is_open() or _queue.is_empty():
		return
	var spec: Dictionary = _queue.pop_front()
	_handler = spec["handler"]
	_host.modal_layer.move_child(dialog, _host.modal_layer.get_child_count() - 1)
	_host.push_modal()
	dialog.show_notice(String(spec["title"]), String(spec["body"]), spec["choices"],
		bool(spec["prompt"]), String(spec["initial"]))


func _on_notice_closed(choice: StringName) -> void:
	var handler := _handler
	_handler = Callable()
	_host.pop_modal()
	if handler.is_valid():
		handler.call(choice)
	_show_next()


## Notices waiting behind the one on screen.
func pending() -> int:
	return _queue.size()


## Drop the notices waiting behind the one on screen.
func clear_pending() -> void:
	_queue.clear()
