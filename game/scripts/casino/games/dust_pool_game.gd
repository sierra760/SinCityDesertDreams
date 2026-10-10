# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The public crew is a fictional table mechanism, never actual city money.
class_name DustPoolGame
extends OriginalSignatureGame

var _bids: Array[int] = []
var _total := 0
var _pot := 0

func _init() -> void:
	kind = &"dust_pool"
	title = "Common Pot"
	rules_text = "Three fictional crew pledges of 1–4 are shown. The house sponsors a gross pot of stake × (pledge total + 5). Choose 1, 2 or 3 virtual claim units; there is no additional debit. More units claim more of the pot but reduce the chance of agreement. The exact agreement probability and whole-dollar gross return are shown before you choose. No agreement returns nothing."

func commit_action() -> StringName:
	return &"convene"

func commit_label() -> String:
	return "Gather the crew"

func _on_round_start() -> void:
	_bids.clear()
	_total = 0
	_pot = 0

func background_action() -> StringName:
	return &"share_1"

func _playing_actions() -> Array[Dictionary]:
	return [_action(&"share_1", "Claim 1 unit", true, true), _action(&"share_2", "Claim 2 units", true, false), _action(&"share_3", "Claim 3 units", true, false)]

func _quotes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _total == 0:
		return out
	for units in range(1, 4):
		out.append({"id": StringName("share_%d" % units), "label": "Claim %d units" % units, "share": units,
			"chance": scale(960, _total + units, units * (_total + 5)), "returned": scale(_pot, units, _total + units)})
	return out

func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action == &"convene":
		state = PLAYING
		for _i in 3:
			var pledge := _draw_below(4) + 1
			_bids.append(pledge)
			_total += pledge
		_pot = total_staked() * (_total + 5)
		_emit({"kind": "pledges", "bids": _bids.duplicate(), "pot": _pot})
	else:
		var units := int(String(action).trim_prefix("share_"))
		var quote: Dictionary = _quotes()[units - 1]
		var success := _draw_below(1000) < int(quote["chance"])
		var returned := int(quote["returned"]) if success else 0
		_emit({"kind": "agreement", "units": units, "success": success})
		_finish(returned, "%s. $%d returned." % ["The crew agreed to your claim" if success else "The crew could not agree", returned])
	return _accept()

func _view() -> Dictionary:
	var details := {}
	for quote in _quotes():
		details[quote["id"]] = "%d / %d of the pot; %.1f%% agreement; $%d gross on success" % [int(quote["share"]), _total + int(quote["share"]), int(quote["chance"]) / 10.0, int(quote["returned"])]
	var out := _presentation("Choose a claim", "Larger claims pay more when everyone agrees, and fail more often.", "$%d gross pot sponsored by the house" % _pot, details)
	out.merge({"crewbids": _bids.duplicate(), "pot": _pot, "claim_quotes": _quotes()})
	return out
