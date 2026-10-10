# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A rotating public crowd distribution drives three optional cyclic duels.
class_name VelvetEncoreGame
extends OriginalSignatureGame

const TOKENS := [&"rose", &"fan", &"spotlight"]
const WEIGHTS := [[50, 30, 20], [20, 50, 30], [30, 20, 50]]
var _round := 0
var _bank := 0
var _last := {}

func _init() -> void:
	kind = &"velvet_encore"
	title = "Encore"
	rules_text = "Your opening bank is 96% of your stake, rounded down. Bow to collect it, or play up to three encores. Rose beats Fan, Fan beats Spotlight, and Spotlight beats Rose. The crowd's visible percentages rotate after each duel. A win multiplies your bank by 1.30; a tie keeps it; a loss loses everything. After three duels the bank is collected automatically. Gross returns include the stake."

func commit_action() -> StringName:
	return &"take_stage"

func commit_label() -> String:
	return "Take the stage"

func _on_round_start() -> void:
	_round = 0
	_bank = 0
	_last = {}

func background_action() -> StringName:
	return &"bow"

func _playing_actions() -> Array[Dictionary]:
	return [_action(&"bow", "Bow", true, true), _action(&"rose", "Rose", true, false), _action(&"fan", "Fan", true, false), _action(&"spotlight", "Spotlight", true, false)]

func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action == &"take_stage":
		state = PLAYING
		_bank = scale(total_staked(), 96, 100)
	elif action == &"bow":
		_finish(_bank, "The curtain falls. $%d returned." % _bank)
	else:
		var draw := _draw_below(100)
		var weights: Array = WEIGHTS[_round % 3]
		var audience := 0 if draw < int(weights[0]) else (1 if draw < int(weights[0]) + int(weights[1]) else 2)
		var lead := TOKENS.find(action)
		var result := "tie" if lead == audience else ("win" if (lead + 1) % 3 == audience else "loss")
		_last = {"lead": String(action), "audience": String(TOKENS[audience]), "result": result}
		_emit({"kind": "encore", "lead": String(action), "audience": String(TOKENS[audience]), "result": result})
		_round += 1
		if result == "loss":
			_bank = 0
			_finish(0, "The crowd chose %s. The encore lost its bank." % String(TOKENS[audience]))
		else:
			if result == "win":
				_bank = scale(_bank, 130, 100)
			if _round == 3:
				_finish(_bank, "Three encores completed. $%d returned." % _bank)
	return _accept()

func _view() -> Dictionary:
	var weights: Array = WEIGHTS[_round % 3]
	var crowd := {}
	var details := {&"bow": "$%d gross return now" % _bank}
	for i in 3:
		crowd[String(TOKENS[i])] = int(weights[i])
		details[TOKENS[i]] = "%d%% win ×1.30; %d%% tie; %d%% loss" % [int(weights[(i + 1) % 3]), int(weights[i]), int(weights[(i + 2) % 3])]
	var out := _presentation("Encore %d of 3" % (_round + 1), "Read the crowd. Choose a lead or bow with your bank.", "$%d in your bank" % _bank, details)
	out.merge({"audienceweights": crowd, "roundindex": _round, "bank": _bank, "lasttokens": _last.duplicate()})
	return out
