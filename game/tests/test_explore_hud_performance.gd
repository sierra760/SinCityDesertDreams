# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

class CountedHUD extends ExploreHUD:
	var reflows := 0
	func _reflow() -> void:
		reflows += 1
		super._reflow()

func test_unchanged_status_ticks_retain_layout_and_display() -> void:
	var hud := CountedHUD.new()
	root.add_child(hud)
	var status := {"mode":0,"speed":.25,"prompt":"F to enter nearby vehicle"}
	var transit := {"passenger":false,"message":"Wait behind the yellow edge."}
	hud.set_status(status)
	hud.set_transit_status(transit)
	hud.reflows = 0
	var started := Time.get_ticks_usec()
	for tick: int in 1000:
		hud.set_status(status)
		hud.set_transit_status(transit)
	print("HUD_COST ",JSON.stringify({"case":"walking","pairs":1000,"microseconds":Time.get_ticks_usec()-started,"reflows":hud.reflows}))
	check_eq(hud.reflows,0,"identical ticks do not invalidate layout")
	check_eq(hud._actor_label.text,"Walking")
	check_eq(hud._speed_label.text,"Speed: 4.0 m/s")
	check_eq(hud._transit_label.text,"Wait behind the yellow edge.")
	status.speed=.2501
	hud.set_status(status)
	check_eq(hud.reflows,0,"a speed change below displayed precision does not invalidate layout")
	hud.free()

func test_passenger_ticks_do_not_flip_actor_text_and_alighting_is_immediate() -> void:
	var hud := CountedHUD.new()
	root.add_child(hud)
	var status := {"mode":0,"speed":0.0}
	var transit := {"passenger":true,"transit_kind":"subway","speed_mps":8.5,"current_stop":"East","next_stop":"West","door_state":"boarding","departure_seconds":5}
	hud.set_status(status)
	hud.set_transit_status(transit)
	hud.reflows = 0
	var started := Time.get_ticks_usec()
	for tick: int in 1000:
		hud.set_status(status)
		hud.set_transit_status(transit)
	print("HUD_COST ",JSON.stringify({"case":"passenger","pairs":1000,"microseconds":Time.get_ticks_usec()-started,"reflows":hud.reflows}))
	check_eq(hud.reflows,0,"a stable ride does not alternate Walking/Riding layout")
	check_eq(hud._actor_label.text,"Riding subway")
	check_eq(hud._speed_label.text,"Speed: 8.5 m/s")
	check(hud._transit_label.text.contains("Doors: open · Departs in 5s"))
	status.speed=.25
	hud.set_status(status)
	check_eq(hud._actor_label.text,"Riding subway","paired base status retains the passenger display")
	check_eq(hud.reflows,0,"underlying pedestrian movement does not invalidate passenger labels")
	hud.set_transit_status({"passenger":false})
	check_eq(hud._actor_label.text,"Walking","alighting is synchronous")
	check_eq(hud._speed_label.text,"Speed: 4.0 m/s","alighting uses latest pedestrian speed")
	check(not hud._transit_label.visible,"alighting removes the empty transit line")
	check_gt(hud.reflows,0,"alighting updates layout immediately")
	hud.free()

func test_changed_content_and_layout_events_keep_synchronous_bounds() -> void:
	var hud := CountedHUD.new()
	root.add_child(hud)
	var layout := DisplayLayout.new()
	layout.refresh_with_mobile_metrics(Vector2i(390,844),1.0,Rect2i(0,44,390,766))
	hud.bind_layout(layout)
	hud.set_touch_controls_enabled(true)
	hud.show_session(true)
	hud.set_status({"mode":0,"speed":.25,"prompt":"F to enter nearby vehicle"})
	check_eq(hud._prompt_label.text,"Interact to enter nearby vehicle")
	hud.reflows = 0
	hud.set_status({"mode":2,"speed":.5,"altitude":.25,"prompt":"F to exit","message":"Land before exiting"})
	check_gt(hud.reflows,0,"displayed text and visibility changes update layout")
	check(hud._altitude_label.visible and hud._status_scroll.visible)
	check_eq(hud._speed_label.text,"Speed: 8.0 m/s")
	check_eq(hud._altitude_label.text,"Altitude: 4.0 m")
	check_eq(hud.touch_controls._status_rect,hud._status_panel.get_rect(),"touch ownership rect remains immediate")
	hud.reflows = 0
	hud.set_chrome_insets(44,44)
	check_gt(hud.reflows,0,"chrome callbacks remain synchronous")
	check_eq(hud.touch_controls._status_rect,hud._status_panel.get_rect())
	hud.reflows = 0
	layout.refresh_with_mobile_metrics(Vector2i(844,390),1.0,Rect2i(44,0,756,369))
	check_gt(hud.reflows,0,"rotation/metrics still update immediately")
	check_eq(hud.touch_controls._status_rect,hud._status_panel.get_rect())
	hud.reflows = 0
	hud._status_panel.minimum_size_changed.emit()
	check_gt(hud.reflows,0,"theme/content minimum-size notifications still update layout")
	hud.set_transit_status({"station_id":2,"destinations":[{"id":3,"name":"East"},{"id":4,"name":"West"}],"selected_destination":4,"can_choose_destination":true})
	check(hud._destination_picker.visible)
	check_eq(hud._destination_picker.get_selected_metadata(),4)
	hud.set_transit_status({"station_id":2,"destinations":[{"id":3,"name":"East"},{"id":4,"name":"West"}],"selected_destination":3,"can_choose_destination":false})
	check(hud._destination_picker.disabled)
	check_eq(hud._destination_picker.get_selected_metadata(),3,"selection stays live even without a layout change")
	hud.free()
	layout.free()
