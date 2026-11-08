# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_cloud_save_ui.gd"

func test_dismissed_mayor_can_finish_cloud_only_load_without_capturing_run() -> void:
	setup_host()
	host.sim.casino().recall.load({"dismissed":true})
	host.recall_flow.sync()
	host.windows.newspaper.close()
	host.notice_dialog.dismiss(&"load")
	check(host.load_dialog.is_open())
	var remote := remote_city("recall-cloud-only", "Recovered Cloud City")
	fake.finish(fake.last("changes"), {"records":[remote],"deleted_ids":[],"token":PackedByteArray([9]),"more":false})
	# Advance ONLY through the session's ordinary per-frame entry point.
	host.cloud_saves.tick(0.0)
	check(fake.completions.is_empty(), "dismissal still drains coordinator completions")
	for frame in 4: await process_frame
	var request: Dictionary = fake.last("download")
	check(not request.is_empty(), "cloud-only recovery download starts while dismissed")
	if request.is_empty(): return
	select_slot("recall-cloud-only")
	host.load_dialog.confirm()
	fake.finish(request,{"downloaded":{"continuation":directory.path_join("recall-cloud-only.sc2d")}})
	host.cloud_saves.tick(0.0)
	for frame in 10: await process_frame
	check_eq(host.sim.city.name,"Recovered Cloud City")
	check(not host.sim.is_mayor_dismissed())
