# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Three locks; every attempt risks the entire accumulated bank.
class_name VaultCircuitGame
extends OriginalSignatureGame

var _level := 0
var _bank := 0

func _init() -> void:
	kind = &"vault_circuit"
	title = "Vault Circuit"
	rules_text = "Open up to three locks. Quiet succeeds 80% of the time and multiplies your bank by 1.20; Force succeeds 55% and multiplies it by 1.70. Failure loses the entire stake and bank. Bank after one success, or collect automatically after three. Gross returns include your stake; each multiplication rounds down to whole dollars."

func commit_action() -> StringName:
	return &"case_vault"

func commit_label() -> String:
	return "Case the vault"

func _on_round_start() -> void:
	_level = 0
	_bank = 0

func background_action() -> StringName:
	return &"quiet" if _level == 0 else &"bank"

func _playing_actions() -> Array[Dictionary]:
	return [_action(&"quiet", "Quiet", true, _level == 0), _action(&"force", "Force", true, false), _action(&"bank", "Bank", _level > 0, _level > 0)]

func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action == &"case_vault":
		state = PLAYING
		_bank = total_staked()
	elif action == &"bank":
		_finish(_bank, "Vault secured. $%d returned." % _bank)
	else:
		var chance := 80 if action == &"quiet" else 55
		var basis := 120 if action == &"quiet" else 170
		var success := _draw_below(100) < chance
		_emit({"kind": "lock", "lock": _level + 1, "method": String(action), "success": success})
		if not success:
			_bank = 0
			_finish(0, "The vault alarm ended the job.")
		else:
			_level += 1
			_bank = scale(_bank, basis, 100)
			if _level == 3:
				_finish(_bank, "Three locks opened. $%d returned." % _bank)
	return _accept()

func _view() -> Dictionary:
	var out := _presentation("Lock %d of 3" % (_level + 1), "Choose a method; one failed lock loses the whole bank.", "$%d available to bank" % _bank,
		{&"quiet": "80% success; gross bank ×1.20", &"force": "55% success; gross bank ×1.70", &"bank": "$%d gross return; end the job" % _bank})
	out.merge({"locklevel": _level, "currentbank": _bank})
	return out
