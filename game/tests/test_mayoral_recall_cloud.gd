# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_cloud_save_session.gd"

func test_removal_preserves_cloud_checkpoint_and_blocks_all_capture_routes() -> void:
	var previous := saved("recall-last-good")
	var saved_hash := FileAccess.get_sha256(previous)
	host.sim.casino_begin_visit(&"arcology_comstock")
	check(host.sim.casino_commit(&"arcology_comstock", &"blackjack", 11000))
	host.sim.casino_settle(&"arcology_comstock", &"blackjack", 11000, 0)
	host.sim.casino_end_visit()
	check_eq(cloud.capture(&"campaign"), OK)
	var checkpoint := row().duplicate(true)
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.stats.approval = 0
	var recalled := host.sim.casino().recall.save()
	recalled.rng_state = str(SimRng.new(0).state())
	host.sim.casino().recall.load(recalled)
	host.sim.clock.day = 150
	host.sim.city.day = 150
	host.sim.advance_day()
	check(host.sim.is_mayor_dismissed())
	check_eq(cloud.capture(&"dismissed"), ERR_UNAVAILABLE)
	check_eq(cloud._capture(&"forced", true), ERR_UNAVAILABLE)
	check_eq(cloud.prepare_application_recovery(CityFileFlow.application_recovery_path()), ERR_UNAVAILABLE)
	check_eq(cloud.capture_background(), ERR_UNAVAILABLE)
	cloud.tick(61.0)
	check_eq(row(), checkpoint, "dismissed run cannot replace cloud continuation")
	check_eq(FileAccess.get_sha256(previous),saved_hash)
