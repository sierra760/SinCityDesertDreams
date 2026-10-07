# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const HUD_PATH := "res://scripts/ui/explore_hud.gd"

func test_destination_picker_matches_service_and_locks_during_a_ride() -> void:
	var hud := ExploreHUD.new()
	root.add_child(hud)
	var status := {"station_id":0,"destinations":[{"id":2,"name":"West"},{"id":3,"name":"East"}],"selected_destination":3,"can_choose_destination":true}
	hud.set_transit_status(status)
	check_eq(hud._destination_picker.get_selected_metadata(),3,"selected item is the actual service destination")
	status.passenger=true
	status.transit_kind="subway"
	status.can_choose_destination=false
	hud.set_transit_status(status)
	check(hud._destination_picker.disabled,"riding cannot show a misleading editable destination")
	check(hud._actor_label.text.contains("subway"),"subway ride has the correct name")
	status.passenger=false
	status.can_choose_destination=true
	hud.set_transit_status(status)
	check(not hud._destination_picker.disabled,"alighting restores selection")
	hud.free()

func test_elevator_action_is_not_repeated_and_stopped_rides_show_the_platform() -> void:
	var hud := ExploreHUD.new()
	root.add_child(hud)
	hud.set_status({"prompt":"F to call elevator"})
	hud.set_transit_status({"message":"F to call elevator","elevator_prompt":"F to call elevator"})
	check(not hud._transit_label.visible,"one action prompt instead of two identical lines")
	hud.set_status({})
	hud.set_transit_status({"passenger":true,"current_stop":"East","next_stop":"West","destination":"West","door_state":"boarding","message":"Walk through the open doorway to board or leave."})
	check(hud._transit_label.text.contains("At: East"),"open doors identify the current platform")
	check(hud._transit_label.text.contains("Next: West"),"next stop remains separate")
	hud.free()

func test_hud_script_and_actions() -> void:
	check(ResourceLoader.exists(HUD_PATH),"exploration HUD script exists")
	if not ResourceLoader.exists(HUD_PATH): return
	var hud: CanvasLayer = load(HUD_PATH).new()
	root.add_child(hud)
	hud.show_session(true)
	hud.set_suspended(true)
	for label in ["Resume","Recover","Return to Build","Reset camera"]:
		var button := _find_button(hud,label)
		check(button != null,label)
		if button != null: check(button.size.y >= 44 or button.custom_minimum_size.y >= 44,label+" touch target")
	check(_find_button(hud,"Control settings") != null,"controls have one Settings route")
	# The full legend lives in Settings; the paused panel keeps one short line.
	var hint: String = hud._panel_hint_label.text
	check(hint.contains("WASD move") and hint.contains("Esc menu"),"paused panel lists the walking controls")
	check(not hint.contains("\n"),"controls hint stays one line, not the full legend")
	check(hud.has_signal("resume_requested"))
	check(hud.has_signal("recover_requested"))
	check(hud.has_signal("return_requested"))
	check(hud.has_signal("recenter_requested"))
	check(hud.has_signal("settings_requested"))
	hud.free()

func test_status_metrics_and_small_window_scroll() -> void:
	if not ResourceLoader.exists(HUD_PATH): return
	var layout := DisplayLayout.new()
	layout.refresh_with_metrics(Vector2i(640,400),1.0)
	var hud: CanvasLayer = load(HUD_PATH).new()
	root.add_child(hud)
	hud.bind_layout(layout)
	hud.show_session(true)
	hud.set_status({"mode":2,"speed":.5,"altitude":.25,"prompt":"F to exit","message":"Land before exiting"})
	hud.set_suspended(true)
	check(_visible_text(hud).contains("8"),"speed displayed in metres per second")
	check(_visible_text(hud).contains("4"),"altitude displayed in metres")
	check(_visible_text(hud).contains("F to exit"))
	check(_visible_text(hud).contains("Land before exiting"))
	check(_has_scroll(hud),"controls fit compact logical window through scroll")
	check(_panel_fits(hud,layout.logical_rect()))
	check(not _status_overlaps_controls(hud),"compact suspended status remains visible above controls")
	layout.refresh_with_metrics(Vector2i(1280,800),2.0)
	check(_panel_fits(hud,layout.logical_rect()),"retina metrics use logical bounds")
	check(not _status_overlaps_controls(hud),"retina logical status remains visible")
	hud.free()
	layout.free()

func test_actions_and_settings_route_emit_requests() -> void:
	if not ResourceLoader.exists(HUD_PATH): return
	var hud: CanvasLayer = load(HUD_PATH).new()
	root.add_child(hud)
	hud.show_session(true)
	hud.set_suspended(true)
	var events: Array[String] = []
	hud.resume_requested.connect(func() -> void: events.append("resume"))
	hud.recover_requested.connect(func() -> void: events.append("recover"))
	hud.return_requested.connect(func() -> void: events.append("return"))
	hud.recenter_requested.connect(func() -> void: events.append("recenter"))
	for caption in ["Resume","Recover","Return to Build","Reset camera"]:
		var button := _find_button(hud,caption)
		if button != null: button.pressed.emit()
	check_eq(events,["resume","recover","return","recenter"])
	hud.settings_requested.connect(func() -> void: events.append("settings"))
	var settings_button := _find_button(hud,"Control settings")
	check(settings_button != null)
	if settings_button != null: settings_button.pressed.emit()
	check_eq(events,["resume","recover","return","recenter","settings"])
	hud.free()

func test_compact_layout_reserves_main_chrome_insets() -> void:
	if not ResourceLoader.exists(HUD_PATH): return
	var layout := DisplayLayout.new()
	layout.refresh_with_metrics(Vector2i(640,400),1.0)
	var hud: CanvasLayer = load(HUD_PATH).new()
	root.add_child(hud)
	hud.bind_layout(layout)
	hud.show_session(true)
	hud.set_suspended(true)
	hud.set_chrome_insets(44.0,44.0)
	var usable := Rect2(0,44,640,312)
	check(_panel_fits(hud,usable),"both panels stay below menu and above city status")
	check(not _status_overlaps_controls(hud),"reserved chrome keeps Explore status readable")
	layout.refresh_with_metrics(Vector2i(1280,800),2.0)
	check(_panel_fits(hud,usable),"retina backing does not double chrome insets")
	hud.free()
	layout.free()

func _find_button(node: Node, caption: String) -> Button:
	if node is Button and (node as Button).text == caption: return node
	for child in node.get_children():
		var found := _find_button(child,caption)
		if found != null: return found
	return null

func _visible_text(node: Node) -> String:
	var result := ""
	if node is Label: result += (node as Label).text + "\n"
	for child in node.get_children(): result += _visible_text(child)
	return result

func _has_scroll(node: Node) -> bool:
	if node is ScrollContainer: return true
	for child in node.get_children():
		if _has_scroll(child): return true
	return false

func _panel_fits(node: Node, available: Rect2) -> bool:
	for child in node.get_children():
		if child is PanelContainer and (child as PanelContainer).visible and not available.encloses((child as PanelContainer).get_rect()):
			print("Panel outside logical rect: ", child.name, " rect=", (child as PanelContainer).get_rect(), " available=", available)
			return false
		if not _panel_fits(child,available): return false
	return true

func _status_overlaps_controls(hud: Node) -> bool:
	var status: Control = hud.get_node("ExploreStatus")
	var controls: Control = hud.get_node("ExplorePanel")
	return status.get_rect().intersects(controls.get_rect())

func _find_named(node: Node, wanted: String) -> Control:
	if node.name == wanted and node is Control: return node
	for child in node.get_children():
		var found := _find_named(child,wanted)
		if found != null: return found
	return null

func test_passenger_status_shows_train_motion_and_friendly_doors() -> void:
	var hud := ExploreHUD.new()
	root.add_child(hud)
	hud.set_status({"mode":0,"speed":0})
	hud.set_transit_status({"passenger":true,"destination":"Rail West","next_stop":"Rail East","door_state":"closed","speed_mps":8.5})
	check(hud._actor_label.text.contains("Riding train"))
	check(hud._speed_label.text.contains("8.5"),"vehicle speed shown while pedestrian stands inside")
	check(hud._transit_label.text.contains("Doors: closed"))
	hud.set_transit_status({"passenger":true,"door_state":"boarding"})
	check(hud._transit_label.text.contains("Doors: open"))
	hud.set_status({"mode":0,"speed":.09})
	hud.set_transit_status({"passenger":false})
	check_eq(hud._actor_label.text,"Walking","alighting restores walking status")
	hud.free()
