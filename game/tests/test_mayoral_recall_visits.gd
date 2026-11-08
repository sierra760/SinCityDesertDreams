# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_casino_session.gd"

func test_door_captures_treasury_and_tables_preserve_visit_until_exit() -> void:
	if not await _walk_inside(): return
	var r: Variant = host.sim.casino().get("recall")
	check(r != null, "recall exists")
	if r == null: return
	check_eq(r.entry_funds, START_FUNDS, "physical entry captures treasury")
	host.sim.adjust_funds(1000)
	check(host.open_casino_table(COMSTOCK, &"blackjack"))
	check_eq(r.entry_funds, START_FUNDS, "sitting does not recapture treasury")
	host.force_close_casino()
	check_eq(r.entry_funds, START_FUNDS, "leaving the table stays in the visit")
	check(host.exploration.resort_service.leave())
	check_eq(r.visit_resort, &"", "physical exit ends visit")

func test_clear_and_demolition_end_visit() -> void:
	if not await _walk_inside(): return
	var r: Variant = host.sim.casino().get("recall")
	if r == null:
		check(false,"recall exists")
		return
	host.sim.city.building.putv(ANCHOR, 0)
	host.exploration.resort_service.refresh_geometry()
	check_eq(r.visit_resort, &"", "demolition ejection ends visit")
	host.sim.casino_begin_visit(COMSTOCK)
	host.exploration.resort_service.clear()
	check_eq(r.visit_resort, &"", "Explore disposal ends visit")
