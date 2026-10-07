# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Report numeric edits must keep their simulation contracts when their small
## stacked arrows are replaced by separate touch actions.
extends "res://tests/test_case.gd"

var _mounted: Array[Node] = []


func after_each() -> void:
	for node in _mounted:
		root.remove_child(node)
		node.free()
	_mounted.clear()


func _mount(node: Node) -> Node:
	root.add_child(node)
	_mounted.append(node)
	return node


func _field() -> Control:
	var path := "res://scripts/ui/touch_number_field.gd"
	if not ResourceLoader.exists(path):
		check(false, "numeric editing has separate minus and plus actions")
		return null
	return _mount(load(path).new())


func _action(field: Control, caption: String) -> Button:
	for child in field.get_children():
		if child is Button and child.text == caption:
			return child
	check(false, "numeric edit exposes the %s adjustment action" % caption)
	return null


func _simulation() -> Simulation:
	var sim := make_simulation(flat_city(20000), 921)
	_mounted.append(sim)
	return sim


func test_touch_actions_apply_one_step_and_stop_at_bounds() -> void:
	var field := _field()
	if field == null:
		return
	field.min_value = 0
	field.max_value = 20
	field.step = 1
	field.value = 19
	var plus := _action(field, "+")
	var minus := _action(field, "−")
	plus.pressed.emit()
	check_eq(field.value, 20.0, "plus changes the tax by one")
	check(plus.disabled, "increase is unavailable at the upper bound")
	minus.pressed.emit()
	check_eq(field.value, 19.0, "minus changes the tax by one")
	field.value = 0
	check(minus.disabled, "decrease is unavailable at the lower bound")


func test_typing_preserves_expression_snapping_clamping_and_invalid_recovery() -> void:
	var field := _field()
	if field == null:
		return
	field.min_value = 1000
	field.max_value = 10000
	field.step = 1000
	field.value = 5000
	var edit: LineEdit = field.get_line_edit()
	edit.text = "2000+1000"
	edit.text_submitted.emit(edit.text)
	check_eq(field.value, 3000.0, "typed arithmetic still applies")
	edit.text = "2600"
	edit.text_submitted.emit(edit.text)
	check_eq(field.value, 3000.0, "typed amounts snap to the bond step")
	edit.text = "99999"
	edit.text_submitted.emit(edit.text)
	check_eq(field.value, 10000.0, "typed values retain the upper bound")
	edit.text = "0"
	edit.text_submitted.emit(edit.text)
	check_eq(field.value, 1000.0, "typed values retain the lower bound")
	edit.text = "invalid"
	edit.text_submitted.emit(edit.text)
	check_eq(field.value, 1000.0, "invalid text cannot alter the amount")
	check_eq(edit.text, "1000", "invalid text returns to the current numeric value")


func test_action_commits_pending_typing_before_adjusting() -> void:
	var field := _field()
	if field == null:
		return
	field.max_value = 20
	field.value = 7
	field.get_line_edit().text = "9"
	_action(field, "+").pressed.emit()
	check_eq(field.value, 10.0, "a tap adjusts the number the player was editing")


func test_pending_typing_can_adjust_away_from_an_old_range_bound() -> void:
	var field := _field()
	if field == null:
		return
	field.max_value = 20
	field.value = 20
	var edit: LineEdit = field.get_line_edit()
	edit.text = "9"
	edit.text_changed.emit(edit.text)
	var plus := _action(field, "+")
	check(not plus.disabled, "a newly typed amount can use the old disabled action")
	plus.pressed.emit()
	check_eq(field.value, 10.0, "the action commits the pending amount and then adjusts")


func test_silent_and_signal_blocked_refreshes_still_update_visible_value() -> void:
	var field := _field()
	if field == null:
		return
	field.max_value = 20
	var changes: Array[float] = []
	field.value_changed.connect(func(amount: float) -> void: changes.append(amount))
	field.set_value_no_signal(12)
	check_eq(field.get_line_edit().text, "12", "silent refresh updates the editable value")
	check(changes.is_empty(), "silent refresh does not notify the simulation")
	field.set_block_signals(true)
	field.value = 15
	field.set_block_signals(false)
	check_eq(field.get_line_edit().text, "15", "blocked refresh updates the editable value")
	check(changes.is_empty(), "blocked refresh does not notify the simulation")
	_action(field, "−").pressed.emit()
	check_eq(changes, [14.0], "the next touch action emits one actual value change")


func test_budget_tax_actions_and_typing_keep_limits_and_other_taxes() -> void:
	var sim := _simulation()
	var window: BudgetWindow = _mount(BudgetWindow.new())
	window.bind(sim)
	var field: Control = window._tax_spinners[&"residential"]
	var plus := _action(field, "+")
	if plus == null:
		return
	plus.pressed.emit()
	check_eq(sim.stats.tax_residential, 8, "touch action writes the real residential tax")
	check_eq(sim.stats.tax_commercial, 7, "other zone taxes remain owned by their controls")
	field.get_line_edit().text = "99"
	field.get_line_edit().text_submitted.emit("99")
	check_eq(sim.stats.tax_residential, 20, "typing preserves Budget's tax cap")
	sim.stats.tax_residential = 3
	window.refresh()
	check_eq(field.value, 3.0, "refresh reads current simulation values")
	check_eq(sim.stats.tax_residential, 3, "refresh does not write a new tax")


func test_budget_bond_actions_update_quote_and_issue_exact_principal() -> void:
	var sim := _simulation()
	var window: BudgetWindow = _mount(BudgetWindow.new())
	window.bind(sim)
	window.set_bond_amount(5000)
	var field: Control = window._bond_amount
	var plus := _action(field, "+")
	if plus == null:
		return
	plus.pressed.emit()
	check(window.quote_text().contains("6,000"), "touch adjustment refreshes the live quote")
	var funds := sim.city.funds
	check(window.issue_bond(), "the adjusted bond can be issued")
	check_eq(sim.city.funds, funds + 6000, "the adjusted principal reaches the treasury")
	check(window.repay_oldest(), "repayment still uses the existing oldest-bond contract")
	check_eq(sim.city.funds, funds, "repayment debits the same principal")


func test_industry_actions_and_typing_change_only_the_selected_sector() -> void:
	var sim := _simulation()
	var window: IndustriesWindow = _mount(IndustriesWindow.new())
	window.bind(sim)
	var field: Control = window._sector_rows[3][4]
	var plus := _action(field, "+")
	if plus == null:
		return
	plus.pressed.emit()
	check_eq(sim.stats.sector_taxes[3], 8, "touch adjustment writes its selected sector")
	check_eq(sim.stats.sector_taxes[4], 7, "neighbor sector remains unchanged")
	field.get_line_edit().text = "12"
	field.get_line_edit().text_submitted.emit("12")
	check_eq(sim.stats.sector_taxes[3], 12, "typing writes the selected sector")
	check(window.sector_text(3).ends_with("| 12"), "report still shows its current sector tax")
	window.refresh()
	check_eq(sim.stats.sector_taxes[3], 12, "report refresh does not change tax policy")
