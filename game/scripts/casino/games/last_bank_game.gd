# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rig values are indices into the shrinking fresh 52-card pool, not ranks.
class_name LastBankGame
extends OriginalSignatureGame

var _pool: Array[Dictionary] = []
var _offers: Array[Dictionary] = []
var _anchor := {}
var _bankcard := {}
var _contract_counts := {}

func _init() -> void:
	kind = &"last_bank"
	title = "Last Bank Contracts"
	rules_text = "Draft one of three face-up offers from a fresh 52-card deck. All three offers leave the deck. Choose Rise, Fall or Match against your drafted rank; aces are low. One bank card comes from the remaining 49. Exact win counts and gross returns are shown before you choose. Winning gross return is floor(stake × 0.96 × 49 / winning cards); losing returns nothing."

func commit_action() -> StringName:
	return &"draft"

func commit_label() -> String:
	return "Deal three offers"

func _on_round_start() -> void:
	_pool.clear()
	for suit in 4:
		for rank in range(1, 14):
			_pool.append(CasinoDeck.card(rank, suit))
	_offers.clear()
	_anchor = {}
	_bankcard = {}
	_contract_counts = {}

func background_action() -> StringName:
	if _anchor.is_empty():
		return &"draft_0"
	var counts := _counts()
	return &"rise" if int(counts["rise"]) >= int(counts["fall"]) else &"fall"

func _playing_actions() -> Array[Dictionary]:
	if _anchor.is_empty():
		var out: Array[Dictionary] = []
		for i in 3:
			out.append(_action(StringName("draft_%d" % i), "Draft %s" % CasinoDeck.card_name(_offers[i]), true, i == 0))
		return out
	var counts := _counts()
	var closing := background_action()
	return [_action(&"rise", "Rise", int(counts["rise"]) > 0, closing == &"rise"), _action(&"fall", "Fall", int(counts["fall"]) > 0, closing == &"fall"), _action(&"match", "Match", int(counts["match"]) > 0, false)]

func _draw_card() -> Dictionary:
	var index := _draw_below(_pool.size())
	var card: Dictionary = _pool[index]
	_pool.remove_at(index)
	return card

func _counts() -> Dictionary:
	if not _contract_counts.is_empty():
		return _contract_counts.duplicate()
	var out := {"rise": 0, "fall": 0, "match": 0}
	if _anchor.is_empty():
		return out
	for card in _pool:
		var result := _comparison(card)
		out[result] = int(out[result]) + 1
	return out

func _comparison(card: Dictionary) -> String:
	var rank := int(card["rank"])
	var anchor := int(_anchor["rank"])
	return "rise" if rank > anchor else ("fall" if rank < anchor else "match")

func _quotes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _anchor.is_empty():
		return out
	var counts := _counts()
	for id in [&"rise", &"fall", &"match"]:
		var winners := int(counts[String(id)])
		out.append({"id": id, "label": String(id).capitalize(), "winners": winners, "chance_numerator": winners,
			"chance_denominator": 49, "returned": scale(total_staked(), 960 * 49, 1000 * winners) if winners > 0 else 0})
	return out

func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action == &"draft":
		state = PLAYING
		for _i in 3:
			_offers.append(_draw_card())
		_emit({"kind": "offers", "cards": _offers.duplicate(true)})
	elif String(action).begins_with("draft_"):
		_anchor = _offers[int(String(action).trim_prefix("draft_"))].duplicate()
		_contract_counts = _counts()
	else:
		var winners := int(_counts()[String(action)])
		_bankcard = _draw_card()
		var success := _comparison(_bankcard) == String(action)
		var returned := scale(total_staked(), 960 * 49, 1000 * winners) if success else 0
		_emit({"kind": "bank_card", "card": _bankcard.duplicate(), "contract": String(action), "success": success})
		_finish(returned, "%s against %s: %s. $%d returned." % [String(action).capitalize(), CasinoDeck.card_name(_anchor), CasinoDeck.card_name(_bankcard), returned])
	return _accept()

func _view() -> Dictionary:
	var details := {}
	for quote in _quotes():
		details[quote["id"]] = "%d / 49 winning cards; $%d gross on success; $0 on loss" % [int(quote["winners"]), int(quote["returned"])]
	if _anchor.is_empty() and _offers.size() == 3:
		for i in 3:
			details[StringName("draft_%d" % i)] = "Choose this anchor; all three offers stay out of the bank deck"
	var out := _presentation("Draft an anchor" if _anchor.is_empty() else "Choose a contract", "Aces are low. All three offers have left the bank deck.", "49 cards back each contract.", details)
	var offers: Array[Dictionary] = []
	for card in _offers:
		offers.append(_card_view(card))
	out.merge({"offers": offers, "candidatecard": _card_view(_anchor) if not _anchor.is_empty() else {},
		"remainingcounts": _counts(), "contract_quotes": _quotes(), "bankcard": _card_view(_bankcard) if not _bankcard.is_empty() else {}})
	return out
