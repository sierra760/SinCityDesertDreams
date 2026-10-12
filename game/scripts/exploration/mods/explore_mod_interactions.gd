# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModInteractions
extends RefCounted
var actors: ExploreActorRegistry
var present: Callable
var dismiss: Callable
var busy: Callable
var _owned: Dictionary = {}
var _dialogue: Dictionary = {}
var _choices: Array[Dictionary] = []

func register(owner: String, key: String, target: Dictionary, label: String) -> Dictionary:
	if key.is_empty() or label.is_empty() or label.to_utf8_buffer().size() > 4096: return {"code":"invalid_argument"}
	if not target.has("id") and not ExploreWorldQueries.point(target).is_finite(): return {"code":"invalid_argument"}
	if target.has("id"):
		if not target.id is String: return {"code":"invalid_argument"}
		if actors == null or not actors._actors.has(target.id): return {"code":"stale_id"}
		if actors._actors[target.id].owner != owner: return {"code":"wrong_owner"}
	var entries: Dictionary = _owned.get(owner,{})
	if entries.size() >= 16 and not entries.has(key): return {"code":"quota_exceeded"}
	entries[key] = {"owner":owner,"key":key,"target":target.duplicate(true),"label":label}
	_owned[owner] = entries
	return {"code":"ok"}

func nearby(player: Dictionary) -> Dictionary:
	var position := ExploreWorldQueries.point(player)
	if not position.is_finite(): return {}
	var closest: Dictionary = {}
	var distance := 1.5 * 1.5
	for entries: Dictionary in _owned.values():
		for entry: Dictionary in entries.values():
			var target: Dictionary = entry.target
			var at := ExploreWorldQueries.point(target)
			if target.has("id"):
				if actors == null or not actors._actors.has(target.id): continue
				at = actors.traffic.actor_pose(actors._actors[target.id].record).origin
			var d := at.distance_squared_to(position)
			# Exact ties use the stable (pack owner, interaction key) tuple.
			# A tie with the initial empty choice stays outside the strict radius.
			var earlier: bool = not closest.is_empty() and (String(entry.owner) < String(closest.owner) or (entry.owner == closest.owner and String(entry.key) < String(closest.key)))
			if d < distance or (d == distance and earlier):
				distance = d
				closest = entry
	return closest.duplicate(true)

func activate(player: Dictionary) -> Dictionary:
	if not _dialogue.is_empty() or (busy.is_valid() and busy.call()): return {"code":"busy"}
	var entry := nearby(player)
	if entry.is_empty(): return {"code":"not_found"}
	return {"code":"ok","event":{"owner":entry.owner,"kind":"interaction","key":entry.key,"code":"ok","data":{}}}

func dialogue(owner: String, key: String, speaker: String, text: String, choices: Array) -> Dictionary:
	if not _dialogue.is_empty() or (busy.is_valid() and busy.call()): return {"code":"busy"}
	if key.is_empty() or text.to_utf8_buffer().size() > 2048 or choices.size() > 8 or choices.is_empty(): return {"code":"invalid_argument"}
	var keys: Dictionary = {}
	for choice in choices:
		if not choice is Dictionary or not choice.get("key") is String or not choice.get("label") is String: return {"code":"invalid_argument"}
		if choice.key.is_empty() or keys.has(choice.key) or choice.label.to_utf8_buffer().size() > 4096: return {"code":"invalid_argument"}
		keys[choice.key] = true
	_dialogue = {"owner":owner,"key":key,"speaker":speaker,"text":text,"choices":choices.duplicate(true)}
	if present.is_valid() and not present.call(_dialogue.duplicate(true)):
		_dialogue.clear()
		return {"code":"busy"}
	return {"code":"ok"}

func choose(key: String) -> void:
	if _dialogue.is_empty(): return
	if not key.is_empty() and not _dialogue.choices.any(func(choice: Dictionary) -> bool: return choice.key == key): return
	var event := {"owner":String(_dialogue.owner),"kind":"dialogue_choice","key":String(_dialogue.key),"code":"ok","data":{"choice":key}}
	_dialogue.clear()
	if dismiss.is_valid(): dismiss.call()
	_choices.append(event)

func take_choices() -> Array[Dictionary]:
	var result := _choices
	_choices = []
	return result

func unregister(owner: String, key: String) -> Dictionary:
	if _owned.has(owner): _owned[owner].erase(key)
	return {"code":"ok"}

func dismiss_owned(owner: String, key: String) -> Dictionary:
	if not _dialogue.is_empty() and _dialogue.owner == owner and _dialogue.key == key:
		_dialogue.clear()
		if dismiss.is_valid(): dismiss.call()
	return {"code":"ok"}

func clear_owner(owner: String) -> void:
	_owned.erase(owner)
	if not _dialogue.is_empty() and _dialogue.owner == owner: dismiss_owned(owner,_dialogue.key)
	_choices = _choices.filter(func(event: Dictionary) -> bool: return event.owner != owner)
