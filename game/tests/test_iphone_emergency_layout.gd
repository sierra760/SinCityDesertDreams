# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Expanded emergency details must leave independent Explore input targets.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
	host = HostFixture.make_host(self, "iphone-emergency-tests")
func after_each() -> void:
	host.free()
	await process_frame
func test_emergency_details_leave_landscape_explore_touch_space() -> void:
	for display: Dictionary in [{"size":Vector2i(667,375),"safe":Rect2i(0,0,667,375)}, {"size":Vector2i(844,390),"safe":Rect2i(47,0,750,369)}]:
		root.size=display.size
		host.display_layout.refresh_with_mobile_metrics(root.size,1,display.safe)
		host.status_bar.set_emergency_available(true)
		host.status_bar.set_alerts(PackedStringArray(["Emergency", "Power shortage", "Water shortage"]))
		host.show_message("Emergency crews are responding.")
		host.status_bar.set_details_open(true)
		host.explore_hud.set_touch_controls_enabled(true)
		host.explore_hud.show_session(true)
		host.explore_hud.set_status({"mode":0,"prompt":"Interact to ride the elevator"})
		await HostFixture.settle(self, 10)
		host.explore_hud.set_suspended(false)
		await HostFixture.settle(self, 10)
		var touch := host.explore_hud.touch_controls
		var status := host.explore_hud._status_panel.get_global_rect()
		for action: StringName in [&"move",&"menu"]+touch._mode_actions():
			check(not status.intersects(touch.control_rect(action)),"emergency summary clears "+str(action))
		check(not status.intersects(touch._move_label.get_global_rect()),"movement caption clears critical status")
		check(host.status_bar.emergency_button.visible,"emergency action remains available in details")
		check_ge(host.status_bar.emergency_button.size.y,44)
		if host.status_bar.get("_details_scroll") != null:
			host.status_bar._details_scroll.ensure_control_visible(host.status_bar.emergency_button)
			await HostFixture.settle(self, 10)
			check(host.status_bar._details_scroll.get_global_rect().grow(.1).encloses(host.status_bar.emergency_button.get_global_rect()),"scroll reveals the complete emergency action")
