# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared presentation and integer settlement for the six original tables.
class_name OriginalSignatureGame
extends CasinoGame

var title := ""
var rules_text := ""

func spots() -> Array[Dictionary]:
	return [_spot(&"stake", "Stake", "Gross returns include the opening stake", "stake")]

@warning_ignore("integer_division")
static func scale(value: int, numerator: int, denominator: int) -> int:
	return value * numerator / denominator

func _presentation(phase: String, instruction: String, status: String, details: Dictionary = {}) -> Dictionary:
	var choices: Array[Dictionary] = []
	if state == PLAYING:
		for action in _playing_actions():
			if bool(action["enabled"]):
				choices.append({"id": action["id"], "label": action["label"], "detail": String(details.get(action["id"], ""))})
	return {"title": title, "phase_label": "Round settled" if state == SETTLED else phase,
		"instruction": instruction, "status": String(_outcome.get("summary", status)),
		"choices": choices, "rules_text": rules_text}

func _finish(returned: int, summary: String, detail: Dictionary = {}) -> void:
	_settle(returned, summary, detail, _plain_reaction(returned))
