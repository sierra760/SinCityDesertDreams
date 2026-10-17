# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Real GUI routing of native contacts and their synthesized mouse stream.
extends "res://tests/exploration/async_test_case.gd"

var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
var original_size: Vector2i


func before_each() -> void:
	original_size = root.size
	CasinoTableOverlay.animation_scale = 0.0
	sim = make_simulation(flat_city(1000000), 7)
	sim.set_speed(GameClock.Speed.PAUSED)
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	overlay = CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)


func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	CasinoTableOverlay.animation_scale = 1.0
	root.content_scale_factor = 1.0
	root.size = original_size
	await process_frame


func display(drawable: Vector2i, backing: float = 1.0) -> void:
	root.size = drawable
	layout.refresh_with_metrics(drawable, backing, Rect2i(), 0, true)
	await frames()


func frames() -> void:
	for frame in 6:
		await process_frame


func mouse(at: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)


func finger(at: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	event.index = index
	root.push_input(event, true)


func tap(at: Vector2, emulated: bool = true, index: int = 0) -> void:
	# Godot sends the synthesized mouse before the corresponding raw touch.
	for pressed: bool in [true, false]:
		if emulated:
			mouse(at, pressed, InputEvent.DEVICE_ID_EMULATION)
		finger(at, pressed, index)


func card_point(index: int, below: bool = false) -> Vector2:
	var stage := overlay.stage as CardStage
	var rect := stage._poker_card_rect(index)
	var point := Vector2(rect.get_center().x, rect.end.y + 20.0) if below else rect.get_center()
	return stage.get_global_transform_with_canvas() * stage.to_local_point(point)


func deal_poker(resort: StringName) -> void:
	overlay.open(sim, resort, &"video_poker", CasinoRng.new(4))
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	await frames()
	check_eq(overlay.game.state, CasinoGame.PLAYING)


func test_ipad_taps_hold_and_unhold_each_card_once() -> void:
	for drawable: Vector2i in [Vector2i(1536, 2048), Vector2i(2048, 1536)]:
		await display(drawable, 2.0)
		for resort: StringName in [&"arcology_boulder", &"com_corner_store"]:
			await deal_poker(resort)
			var funds := sim.city.funds
			for index in 5:
				tap(card_point(index))
				var want := [false, false, false, false, false]
				want[index] = true
				check_eq(overlay.game.view_state()["held"], want, "%s card %d holds on %s" % [resort, index, drawable])
				tap(card_point(index, true))
				check_eq(overlay.game.view_state()["held"], [false, false, false, false, false], "the HELD tag unholds once")
			check_eq(sim.city.funds, funds, "holds never spend money")
			overlay.close()


func test_native_touch_without_emulation_and_hardware_mouse_still_work() -> void:
	await display(Vector2i(1024, 768))
	await deal_poker(&"arcology_boulder")
	tap(card_point(0), false)
	tap(card_point(1), false, 1)
	check_eq(overlay.game.view_state()["held"], [true, true, false, false, false], "independent native contacts work")
	mouse(card_point(0), true)
	mouse(card_point(0), false)
	check_eq(overlay.game.view_state()["held"], [false, true, false, false, false], "a real mouse still toggles")


func test_touch_places_one_chip_on_every_shared_stage() -> void:
	await display(Vector2i(2048, 1536), 2.0)
	for spec: Array in [
		[&"arcology_comstock", &"roulette", &"red"],
		[&"arcology_comstock", &"faro", &"rank_7"],
		[&"arcology_junction", &"money_wheel", &"seg_1"],
		[&"arcology_junction", &"chuck_a_luck", &"die_1"],
		[&"arcology_comstock", &"blackjack", &"main"],
		[&"arcology_boulder", &"baccarat", &"player"],
		[&"com_corner_store", &"slots", &"line"],
		[&"arcology_orbit", &"trajectory", &"stake"],
		[&"arcology_fix", &"vault_circuit", &"stake"],
	]:
		overlay.open(sim, spec[0], spec[1], CasinoRng.new(11))
		await frames()
		var spot: StringName = spec[2]
		var rect := overlay.stage.spot_rect(spot)
		check(rect.has_area(), "%s exposes a drawn bet spot" % spec[1])
		var at := overlay.stage.get_global_transform_with_canvas() * overlay.stage.to_local_point(rect.get_center())
		var funds := sim.city.funds
		tap(at)
		check_eq(overlay.game.total_staked(), int(overlay.game.limits["minimum"]), "%s adds exactly one chip" % spec[1])
		check_eq(sim.city.funds, funds, "selecting a bet leaves treasury alone")
		overlay.close()


func test_touch_makes_only_one_signature_decision() -> void:
	await display(Vector2i(2048, 1536), 2.0)
	overlay.open(sim, &"arcology_fix", &"vault_circuit", CasinoRng.new(11))
	overlay.game.rig([0, 0, 0])
	overlay.press_chip(0)
	overlay.perform_action(&"case_vault")
	await frames()
	var stage := overlay.stage as OriginalSignatureStage
	var rect: Rect2 = stage.choice_rects[&"quiet"]
	tap(stage.get_global_transform_with_canvas() * stage.to_local_point(rect.get_center()))
	check_eq(overlay.game.view_state()["locklevel"], 1, "one tap attempts only one lock")
	check_eq(overlay.game.state, CasinoGame.PLAYING, "the player retains the next decision")


func test_engine_generated_mouse_stream_toggles_only_once() -> void:
	await display(Vector2i(1024, 768))
	await deal_poker(&"arcology_boulder")
	var previous := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = card_point(2)
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await frames()
	Input.emulate_mouse_from_touch = previous
	check_eq(overlay.game.view_state()["held"], [false, false, true, false, false], "the actual engine mouse/touch stream holds once")


func test_explore_host_routes_table_touches_without_moving_player() -> void:
	overlay.hide()
	var host := load("res://scenes/main.tscn").instantiate() as GameHost
	host.preferences_path = "user://casino-touch-host.cfg"
	root.add_child(host)
	host.begin_city(flat_city(1000000), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(Vector2i(22, 20), Vector2i(24, 20))
	await physics_frame
	host.city_view_3d.set_camera_state(Vector3(22.5, 2.4, 20.5), 0, 48)
	check(host.enter_explore(), "fixture enters Explore")
	await physics_frame
	root.size = Vector2i(2048, 1536)
	host.display_layout.refresh_with_metrics(root.size, 2.0, Rect2i(), 0, true)
	check(host.open_casino_table(&"arcology_boulder", &"video_poker", CasinoRng.new(4)))
	var table := host.casino_overlay
	table.press_chip(0)
	table.perform_action(&"deal")
	await frames()
	var feet := host.exploration.pedestrian.global_position
	var stage := table.stage as CardStage
	var at := stage.get_global_transform_with_canvas() * stage.to_local_point(stage._poker_card_rect(3).get_center())
	tap(at)
	check_eq(table.game.view_state()["held"], [false, false, false, true, false], "Main and Explore preserve the card tap")
	tap(at)
	check_eq(table.game.view_state()["held"], [false, false, false, false, false], "Main and Explore preserve the second tap")
	await physics_frame
	check_eq(host.exploration.pedestrian.global_position, feet, "table touches never move the player")
	host.free()
	if FileAccess.file_exists("user://casino-touch-host.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://casino-touch-host.cfg"))
