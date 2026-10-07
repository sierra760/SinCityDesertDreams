# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Live incident navigation must not advance the city or consume simulation RNG.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
var host: GameHost

func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://test_emergency_navigation.cfg"
	root.add_child(host)
	var city := flat_city()
	for x in range(20, 70):
		city.building.put(x, 40, Buildings.ROAD_FIRST)
		city.stamp_building(x, 39, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	host.begin_city(city, {}, 17, null)
	host.sim.stats.disasters_enabled = false
	host.sim.set_process(false)
	host.set_process(false)

func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	if FileAccess.file_exists("user://test_emergency_navigation.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_emergency_navigation.cfg"))
	if FileAccess.file_exists("user://test_emergency_navigation.sc2d"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_emergency_navigation.sc2d"))
	await process_frame

func _system() -> DisasterSystem:
	return host.sim.get_system(&"disasters") as DisasterSystem

func _target() -> Vector2i:
	check(_system().has_method("emergency_target"), "disasters expose a live navigation target")
	return _system().call("emergency_target") if _system().has_method("emergency_target") else Vector2i(-1, -1)

func _button() -> Button:
	var found := host.status_bar.find_child("GoToEmergency", true, false) as Button
	check(found != null, "footer exposes the emergency button")
	return found

func test_quiet_and_editor_have_no_emergency_action() -> void:
	var button := _button()
	if button != null: check(button.disabled and not button.visible, "quiet city hides unavailable navigation")
	check(not host.menu_bar.is_enabled(&"go_to_emergency"))
	check_eq(_target(), Vector2i(-1, -1))
	host.status_bar.show_editing("Test")
	if button != null: check(button.disabled, "terrain editor has no emergency action")
	_system().load({"active": {"kind": "earthquake", "x": 50, "y": 51, "remaining": 4}})
	host.refresh_toolbar()
	host.session.begin_editing(flat_city(), {})
	check(not host.menu_bar.is_enabled(&"go_to_emergency"), "switching to editor disables the former incident action")

func test_button_centers_live_fire_without_changing_simulation() -> void:
	check(host.sim.request_disaster(&"fire", Vector2i(32, 39)))
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.refresh_toolbar()
	var button := _button()
	if button == null: return
	check(not button.disabled, "fire-only emergencies enable button immediately")
	check(host.menu_bar.is_enabled(&"go_to_emergency"))
	host.city_view_3d.set_center_cell(Vector2i(90, 90))
	var before := host.sim.snapshot().duplicate(true)
	var payload := SaveFormat.encode_city(host.sim.city)
	button.pressed.emit()
	check_eq(Vector2i(host.city_view_3d.center.x, host.city_view_3d.center.z), Vector2i(32, 39))
	check_eq(host.sim.snapshot(), before, "navigation changes no simulation state")
	check_eq(SaveFormat.encode_city(host.sim.city), payload)

func test_moving_incident_target_tracks_entity_and_skips_invalid_records() -> void:
	check(host.sim.request_disaster(&"tornado", Vector2i(50, 50)))
	_system().daily(host.sim._ctx)
	var live: Vector2i = _system().entities()[0].pos
	check_ne(live, Vector2i(50, 50), "tornado has moved")
	var before := host.sim.rng.state()
	check_eq(_target(), live, "follow current entity rather than original epicenter")
	check_eq(host.sim.rng.state(), before)
	var saved := _system().save()
	saved.entities.push_front({"kind": "tornado", "x": -10, "y": 50, "frame": 0})
	_system().load(saved)
	check_eq(_target(), live, "out-of-city entities cannot become navigation targets")

func test_riot_flood_and_aftermath_targets_survive_json_restore() -> void:
	for entry: Array in [["riots", "33,40", 1, Vector2i(33, 40)],
			["flood", "44,40", 2, Vector2i(44, 40)], ["hot", "55,39", 3, Vector2i(55, 39)]]:
		var saved := {"active": {"kind": "hurricane", "x": 80, "y": 80, "remaining": 1}, entry[0]: {entry[1]: entry[2]}}
		_system().load(JSON.parse_string(JSON.stringify(saved)))
		check_eq(_target(), entry[3], "find actual remaining hazard")
	_system().load({"active": {"kind": "earthquake", "x": 65, "y": 66, "remaining": 4}})
	check_eq(_target(), Vector2i(65, 66), "static incident falls back to its epicenter")

func test_ending_fire_disables_button_and_stale_action_cannot_move_camera() -> void:
	check(host.sim.request_disaster(&"fire", Vector2i(32, 39)))
	_system().load({})
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host._on_day_advanced(1900, 1, 2)
	var button := _button()
	if button != null: check(button.disabled)
	check(not host.menu_bar.is_enabled(&"go_to_emergency"))
	var center := host.city_view_3d.center
	host.menu_bar.press(&"go_to_emergency")
	check_eq(host.city_view_3d.center, center)

func test_navigation_returns_from_explore_and_reveals_surface() -> void:
	check(host.enter_explore(), "fixture offers a safe outdoor road")
	check(host.sim.request_disaster(&"fire", Vector2i(32, 39)))
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host._on_menu_action(&"go_to_emergency", null)
	check(not host.is_exploring(), "emergency navigation returns to Build")
	check_eq(Vector2i(host.city_view_3d.center.x, host.city_view_3d.center.z), Vector2i(32, 39))
	check(not host.presentation.is_underground())
	check_eq(host.presentation.get_overlay(), &"")

func test_modal_blocks_navigation_and_loaded_emergency_enables_it() -> void:
	check(host.sim.request_disaster(&"fire", Vector2i(32, 39)))
	var center := host.city_view_3d.center
	host._on_menu_action(&"go_to_emergency", null)
	check_eq(host.city_view_3d.center, center, "blocking notice owns input")
	check_eq(host.files.write_save("user://test_emergency_navigation.sc2d"), OK)
	check(host.load_city("user://test_emergency_navigation.sc2d"), "Main reloads the active emergency")
	var button := _button()
	if button != null: check(not button.disabled, "restored disaster needs no new start signal")
	check(host.menu_bar.is_enabled(&"go_to_emergency"))

func test_menu_navigation_reveals_incident_under_underground_and_data_overlays() -> void:
	_system().load({"active": {"kind": "earthquake", "x": 50, "y": 51, "remaining": 4}})
	host.refresh_toolbar()
	host.presentation.set_overlay(&"pollution")
	host.presentation.set_view_mode(CityPresentationController.ViewMode.UNDERGROUND)
	host.menu_bar.press(&"go_to_emergency")
	check(not host.presentation.is_underground(), "incident navigation reveals above-ground hazards")
	check_eq(host.presentation.get_overlay(), &"")
	check_eq(Vector2i(host.city_view_3d.center.x, host.city_view_3d.center.z), Vector2i(50, 51))

func test_compact_footer_retains_keyboard_and_touch_target() -> void:
	root.size = Vector2i(640, 400)
	var button := _button()
	if button == null: return
	host.status_bar.set_emergency_available(true)
	host.status_bar.apply_layout(640)
	for frame in 5: await process_frame
	check_ge(button.size.y, 44.0, "touch target remains usable")
	check_ne(button.focus_mode, Control.FOCUS_NONE)
	check(Rect2(0, 0, 640, 400).encloses(button.get_global_rect()), "compact footer contains emergency control")

func test_dispatched_crews_retain_their_authored_vehicles_and_explore_selection() -> void:
	for station: Array in [[Buildings.FIRE_STATION, Vector2i(10, 10)], [Buildings.POLICE_STATION, Vector2i(15, 10)]]:
		host.sim.city.stamp_building(station[1].x, station[1].y, station[0])
	# A city with local stations needs its own military facility for that crew.
	host.sim.city.stamp_building(20, 10, Buildings.MILITARY_TOWER)
	check(host.sim.request_disaster(&"fire", Vector2i(32, 39)))
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	for example: Array in [[&"fire", &"fire_engine", Vector2i(30, 40)],
			[&"police", &"police", Vector2i(40, 40)], [&"military", &"military", Vector2i(50, 40)]]:
		check(_system().dispatch(example[0], example[2]), "actual crew dispatch succeeds")
	host._process(0.016)
	for example: Array in [[&"fire_engine", Vector2i(30, 40)], [&"police", Vector2i(40, 40)], [&"military", Vector2i(50, 40)]]:
		var vehicles := host.city_view_3d.traffic._external.filter(func(record: Dictionary) -> bool: return record.kind == example[0])
		check_eq(vehicles.size(), 1, "response crew retains its authored traffic model")
		var point := host.city_view_3d.traffic.graph.point(example[1], &"road")
		var selected := host.city_view_3d.traffic.claim_nearby_vehicle(point, 0.2)
		check_eq(selected.get("kind", &""), example[0], "response vehicle remains selectable in Explore")
		host.city_view_3d.traffic.release_vehicle(selected, point)
