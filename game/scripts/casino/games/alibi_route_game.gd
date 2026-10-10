# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Select a route, then choose coverage before any outcome is drawn.
class_name AlibiRouteGame
extends OriginalSignatureGame

const ROUTES := {&"direct": [960, 1], &"night": [480, 2], &"express": [240, 4]}
var _route: StringName = &""
var _coverage: StringName = &""

func _init() -> void:
	kind = &"alibi_route"
	title = "Separate Ways"
	rules_text = "Choose Direct (96% success, ×1 gross), Night (48%, ×2), or Express (24%, ×4). Then choose Bare: full gross return on success and nothing on failure; or Covered: 80% of the route's gross return on success and 25% of your stake on failure. Coverage costs no additional stake. All returns round down to whole dollars."

func commit_action() -> StringName:
	return &"depart"

func commit_label() -> String:
	return "Buy the ticket"

func _on_round_start() -> void:
	_route = &""
	_coverage = &""

func background_action() -> StringName:
	return &"direct" if _route == &"" else &"bare"

func _playing_actions() -> Array[Dictionary]:
	if _route == &"":
		return [_action(&"direct", "Direct", true, true), _action(&"night", "Night", true, false), _action(&"express", "Express", true, false)]
	return [_action(&"bare", "Bare", true, true), _action(&"covered", "Covered", true, false)]

func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action == &"depart":
		state = PLAYING
	elif ROUTES.has(action):
		_route = action
	else:
		_coverage = action
		var terms: Array = ROUTES[_route]
		var success := _draw_below(1000) < int(terms[0])
		var returned := total_staked() * int(terms[1]) if success else 0
		if action == &"covered":
			returned = scale(returned, 80, 100) if success else scale(total_staked(), 25, 100)
		_emit({"kind": "arrival", "route": String(_route), "coverage": String(action), "success": success})
		_finish(returned, "%s route %s. $%d returned." % [String(_route).capitalize(), "arrived" if success else "missed its connection", returned])
	return _accept()

func _view() -> Dictionary:
	var quotes: Array[Dictionary] = []
	var details := {}
	for id in ROUTES:
		var terms: Array = ROUTES[id]
		var returned := total_staked() * int(terms[1])
		quotes.append({"id": id, "label": String(id).capitalize(), "chance": int(terms[0]), "returned": returned,
			"covered_returned": scale(returned, 80, 100), "loss_returned": scale(total_staked(), 25, 100)})
		details[id] = "%.1f%% arrival; $%d gross if bare; covered $%d / $%d on success / failure" % [int(terms[0]) / 10.0, returned, scale(returned, 80, 100), scale(total_staked(), 25, 100)]
	if _route != &"":
		var gross := total_staked() * int(ROUTES[_route][1])
		details[&"bare"] = "$%d gross on arrival; $0 on failure" % gross
		details[&"covered"] = "$%d gross on arrival; $%d on failure; no extra debit" % [scale(gross, 80, 100), scale(total_staked(), 25, 100)]
	var out := _presentation("Choose a route" if _route == &"" else "Choose coverage", "Choose your risk before the arrival is drawn.", "Your ticket is ready.", details)
	out.merge({"route": String(_route), "coverage": String(_coverage), "route_quotes": quotes})
	return out
