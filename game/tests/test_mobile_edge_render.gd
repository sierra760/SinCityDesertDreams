# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Safe areas constrain interaction, while the city fills the whole display.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")

func test_city_fills_display_without_moving_safe_controls_or_changing_city() -> void:
	var host: GameHost = HostFixture.make_host(self, "mobile-edge-render")
	host.city_view_3d.set_camera_state(Vector3(64.5,2.4,64.5),0,20)
	var city_before := SaveFormat.encode_city(host.sim.city)
	var sim_before := host.sim.snapshot().duplicate(true)
	var geometry_revision: int = host.city_view_3d.traversal_snapshot().revision
	for display: Dictionary in [
		{"size":Vector2i(2388,1668),"backing":2.0,"safe":Rect2i(0,48,2388,1580)},
		{"size":Vector2i(1668,2388),"backing":2.0,"safe":Rect2i(0,48,1668,2300)},
		{"size":Vector2i(1170,2532),"backing":3.0,"safe":Rect2i(0,141,1170,2289)},
		{"size":Vector2i(844,390),"backing":1.0,"safe":Rect2i(47,0,750,369)}]:
		root.size = display.size
		for keyboard: int in [0,300,0]:
			host.display_layout.refresh_with_mobile_metrics(display.size,display.backing,display.safe,keyboard)
			for frame in 6: await process_frame
			var full: Rect2 = host.display_layout.metrics.full_logical_rect
			var usable := host.display_layout.logical_rect()
			check_eq(host.city_view_3d.container.get_rect(),full,"city paints through every safe/keyboard inset")
			for control: Control in [host.menu_bar,host.status_bar]:
				check(usable.grow(.1).encloses(control.get_global_rect()),"interactive chrome stays safe")
			check_eq(host.status_bar.get_global_rect().end.y,usable.end.y,"footer retains its natural safe position")
			check(host.touch_ui_owned(Vector2(full.size.x*.5,full.end.y-1)),"home/keyboard edge cannot build")
			for scale: int in [50,75,100]:
				host.city_view_3d.set_render_options("balanced",scale)
				await physics_frame
				for cell: Vector2i in [Vector2i(64,64),Vector2i(66,65)]:
					check_eq(host.city_view_3d.pick_cell(host.city_view_3d.project_cell(cell)),cell,"edge rendering preserves projection/picking")
	check_eq(host.city_view_3d.traversal_snapshot().revision,geometry_revision,"layout never rebuilds city geometry")
	check_eq(SaveFormat.encode_city(host.sim.city),city_before)
	check_eq(host.sim.snapshot(),sim_before)
	host.free()
	await process_frame
