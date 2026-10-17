# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
func before_each() -> void:
	sim=make_simulation(flat_city(1000000),7)
	sim.set_speed(GameClock.Speed.PAUSED)
	layout=DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	overlay=CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)
	CasinoTableOverlay.animation_scale=0
func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	CasinoTableOverlay.animation_scale=1
	await process_frame
func display(size: Vector2i) -> void:
	root.size=size
	layout.refresh_with_mobile_metrics(size,1,Rect2i(Vector2i.ZERO,size))
	for frame in 8: await process_frame
func test_small_phone_tables_keep_header_chips_and_actions_inside_display() -> void:
	for size: Vector2i in [Vector2i(320,568),Vector2i(375,667),Vector2i(667,375)]:
		await display(size)
		for resort: StringName in ResortThemes.keys():
			for kind: StringName in ResortThemes.games(resort):
				overlay.open(sim,resort,kind,CasinoRng.new(11))
				for frame in 8: await process_frame
				var bounds := layout.logical_rect().grow(.5)
				check(bounds.encloses(overlay._root.get_global_rect()),"whole table %s/%s at %s" % [resort,kind,size])
				for button: Button in overlay.find_children("*","Button",true,false):
					if not button.is_visible_in_tree(): continue
					check(bounds.encloses(button.get_global_rect()),"reachable %s/%s %s at %s" % [resort,kind,button.name,size])
					check_ge(button.size.x,44)
					check_ge(button.size.y,44)
				overlay.close()
func test_phone_spot_picker_selects_exact_bets_without_spending() -> void:
	await display(Vector2i(390,844))
	for spec: Array in [[&"arcology_comstock",&"roulette"],[&"arcology_comstock",&"faro"],[&"arcology_junction",&"money_wheel"],[&"arcology_junction",&"chuck_a_luck"]]:
		overlay.open(sim,spec[0],spec[1],CasinoRng.new(11))
		for frame in 8: await process_frame
		var picker := overlay.bet_bar.get("spot_picker") as OptionButton
		check(picker!=null and picker.is_visible_in_tree(),"a phone can choose every small table spot with a full size control")
		if picker!=null:
			check_ge(picker.size.y,44)
			var ids := overlay.stage.spot_order()
			check_eq(picker.item_count,ids.size(),"every legal spot including copper bets stays selectable")
			var funds := sim.city.funds
			for index in ids.size():
				picker.select(index)
				picker.item_selected.emit(index)
				check_eq(overlay.stage.selected_spot,ids[index],"selection routes to real table spot")
				check_eq(overlay.game.total_staked(),0,"choosing a spot does not place a chip")
				check_eq(sim.city.funds,funds)
			overlay.bet_bar.chip_buttons[0].pressed.emit()
			check(overlay.game.bets().has(ids[-1]),"chip goes on selected spot")
		overlay.close()

func test_phone_casino_chrome_leaves_most_height_for_the_game() -> void:
	for size: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(667,375)]:
		await display(size)
		for spec: Array in [[&"arcology_comstock",&"roulette"],[&"arcology_comstock",&"faro"],[&"arcology_junction",&"money_wheel"],[&"arcology_junction",&"chuck_a_luck"],[&"arcology_comstock",&"blackjack"],[&"arcology_comstock",&"slots"],[&"arcology_comstock",&"video_poker"]]:
			overlay.open(sim,spec[0],spec[1],CasinoRng.new(11))
			for frame in 8: await process_frame
			check(overlay.chrome.size.y<=64,"phone header is compact: %s" % spec[1])
			check_ge(overlay.stage.size.y,size.y*.5,"game occupies most of the phone height: %s" % spec[1])
			var picker := overlay.bet_bar.get("chip_picker") as OptionButton
			check(picker!=null and picker.is_visible_in_tree(),"compact chip chooser exists")
			if picker!=null:
				var funds := sim.city.funds
				picker.select(2)
				picker.item_selected.emit(2)
				check_eq(overlay.game.total_staked(),0,"choosing denomination does not bet")
				check_eq(sim.city.funds,funds)
				overlay.bet_bar.plus_button.pressed.emit()
				check_gt(overlay.game.total_staked(),0,"plus places the chosen chip")
			overlay.close()

func test_closed_selector_popups_are_retired_before_rotation() -> void:
	await display(Vector2i(390,844))
	var picker := OptionButton.new()
	root.add_child(picker)
	layout.register_popup(picker.get_popup())
	var count := layout._popups.size()
	picker.free()
	await display(Vector2i(844,390))
	check_eq(layout._popups.size(),count-1,"freed popups leave no stale registry entry")

func test_phone_to_tablet_restores_money_terms_and_action_style() -> void:
	await display(Vector2i(390,844))
	overlay.open(sim,&"arcology_comstock",&"roulette",CasinoRng.new(11))
	for frame in 8: await process_frame
	await display(Vector2i(768,1024))
	check(overlay.bet_bar.total_label.text.contains("limits"),"tablet restores the full terms readout")
	check(overlay.bet_bar.chip_buttons[0].is_visible_in_tree())
	check(not overlay.bet_bar.chip_picker.is_visible_in_tree())
	for button: Button in overlay.bet_bar.action_buttons.values():
		check_eq(button.get_theme_font_size("font_size"),UITheme.FONT_BODY,"tablet restores normal action text")
func test_compact_max_chip_can_be_removed_with_minus() -> void:
	await display(Vector2i(390,844))
	overlay.open(sim,&"arcology_comstock",&"roulette",CasinoRng.new(11))
	for frame in 8: await process_frame
	var funds := sim.city.funds
	overlay.bet_bar.chip_picker.select(4)
	overlay.bet_bar.chip_picker.item_selected.emit(4)
	overlay.bet_bar.plus_button.pressed.emit()
	check_eq(overlay.game.total_staked(),int(overlay.game.limits.maximum),"Max fills the legal amount")
	overlay.bet_bar.minus_button.pressed.emit()
	check_eq(overlay.game.total_staked(),0,"minus removes the selected Max bet")
	check_eq(sim.city.funds,funds,"editing uncommitted bets does not spend funds")

func test_played_phone_rounds_keep_controls_inside_and_gameplay_central() -> void:
	for size: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		await display(size)
		for resort: StringName in ResortThemes.keys():
			for kind: StringName in ResortThemes.games(resort):
				overlay.open(sim,resort,kind,CasinoRng.new(11))
				overlay.press_chip(0)
				for action: Dictionary in overlay.game.actions():
					if action.get("primary",false) and action.get("enabled",true):
						overlay.perform_action(action.id)
						break
				for frame in 8: await process_frame
				var bounds := layout.logical_rect().grow(.5)
				check(bounds.encloses(overlay._root.get_global_rect()),"played table fits %s/%s at %s" % [resort,kind,size])
				for button: Button in overlay.find_children("*","Button",true,false):
					if button.is_visible_in_tree(): check(bounds.encloses(button.get_global_rect()),"played action fits %s/%s %s" % [resort,kind,button.name])
				check_ge(overlay.stage.size.y,size.y*.5,"played game keeps the main screen area %s/%s at %s" % [resort,kind,size])
				overlay.force_close()

func test_phone_large_stake_confirmation_remains_visible_and_bounded() -> void:
	for size: Vector2i in [Vector2i(320,568),Vector2i(844,390)]:
		await display(size)
		sim.city.funds=8000
		overlay.open(sim,&"arcology_comstock",&"blackjack",CasinoRng.new(11))
		overlay.bet_bar.chip_picker.select(4)
		overlay.bet_bar.chip_picker.item_selected.emit(4)
		overlay.bet_bar.plus_button.pressed.emit()
		overlay.perform_action(&"deal")
		for frame in 8: await process_frame
		check_eq(sim.city.funds,8000,"first press only asks for confirmation")
		check(overlay._patter_panel.is_visible_in_tree(),"critical confirmation stays visible")
		check(overlay.patter_label.text.contains("$8,000"),"confirmation names the real amount")
		check(overlay._patter_scroll.size.y<=44,"critical feedback has a fixed body height")
		check(layout.logical_rect().grow(.5).encloses(overlay._root.get_global_rect()),"confirmation keeps all controls in the phone")
		overlay._show_rules(true)
		check(overlay.rules_label.text.contains(overlay.patter_label.text),"full confirmation is also readable in Rules")
		overlay.force_close()

func test_each_new_confirmation_starts_at_the_stake_question() -> void:
	await display(Vector2i(320,568))
	for funds in [8000,7000]:
		sim.city.funds=funds
		overlay.open(sim,&"arcology_comstock",&"blackjack",CasinoRng.new(11))
		overlay.press_chip(4)
		overlay.perform_action(&"deal")
		for frame in 8: await process_frame
		check_eq(overlay._patter_scroll.scroll_vertical,0,"a new confirmation starts with its amount")
		overlay._patter_scroll.scroll_vertical=int(overlay._patter_scroll.get_v_scroll_bar().max_value)
		for frame in 4: await process_frame
		check_gt(overlay._patter_scroll.scroll_vertical,0,"fixture scrolled through the prior prompt")
		overlay.force_close()
