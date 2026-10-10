# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const VENUES := [&"arcology_fix", &"arcology_alibi", &"arcology_velvet", &"arcology_afterglow", &"arcology_last", &"arcology_dust"]
var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
var original_size: Vector2i
func before_all() -> void:
	original_size = root.size
	CasinoTableOverlay.animation_scale = 0
func after_all() -> void:
	CasinoTableOverlay.animation_scale = 1
	root.content_scale_factor = 1
	root.size = original_size
func before_each() -> void:
	sim = make_simulation(flat_city(1000000), 3)
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	root.size = Vector2i(1280, 800)
	layout.refresh_with_metrics(root.size, 1, Rect2i(), 0, false)
	overlay = CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)
func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	root.content_scale_factor = 1
	await process_frame
func frames() -> void:
	for i in 4: await process_frame
func start(index: int) -> void:
	overlay.open(sim, VENUES[index], OriginalSignatureStage.KINDS[index], CasinoRng.new(31))
	check(overlay.stage is OriginalSignatureStage, "signature stage factory")
	overlay.add_to_spot(overlay.stage.default_spot(), int(overlay.game.limits["minimum"]))
	check(overlay.perform_action(overlay.game.commit_action()).get("ok", false), "commit accepted")
func test_six_games_settle_once_through_actual_overlay() -> void:
	for index in 6:
		var before := sim.city.funds
		start(index)
		var stake := overlay.game.total_staked()
		check_eq(sim.city.funds, before - stake + (int(overlay.game.outcome()["returned"]) if overlay.game.state == CasinoGame.SETTLED else 0), "opening debit precedes decisions or immediate settlement")
		var guard := 8
		while overlay.game.state == CasinoGame.PLAYING and guard > 0:
			guard -= 1
			var action := overlay.game.background_action()
			check(not action.is_empty(), "explicit background decision")
			check(overlay.perform_action(action).get("ok", false), "legal next decision")
		check_eq(overlay.game.state, CasinoGame.SETTLED, "game settles")
		check_eq(sim.city.funds, before - stake + int(overlay.game.outcome()["returned"]), "single opening debit and settlement")
		var settled_funds := sim.city.funds
		overlay.perform_action(&"not_an_action")
		check_eq(sim.city.funds, settled_funds, "illegal repeat never changes money")
		overlay.close()
func test_background_finishes_committed_risk_without_refund() -> void:
	for index in 6:
		var before := sim.city.funds
		start(index)
		overlay.game.rig([999, 999, 999])
		var stake := overlay.game.total_staked()
		var was_playing := overlay.game.state == CasinoGame.PLAYING
		var summary := overlay.resolve_round_now()
		check(not overlay.visible, "background closes table")
		check_eq(overlay.game.state, CasinoGame.SETTLED, "background settles")
		check(not summary.is_empty() if was_playing else summary.is_empty(), "summary only for a round settled in background")
		check_eq(sim.city.funds, before - stake + int(overlay.game.outcome()["returned"]), "risk settled rather than refunded")
		check_eq(overlay.resolve_round_now(), "", "second background is inert")
		check(CasinoTableOverlay.rules_text(OriginalSignatureStage.KINDS[index], VENUES[index], overlay.game.limits).to_lower().contains("gross"), "rules explain gross returns")
func test_every_display_contains_buttons_text_and_all_decisions() -> void:
	var displays := [[Vector2i(1280,800),1.0,Rect2i(),false], [Vector2i(640,400),1.0,Rect2i(),false], [Vector2i(2560,1600),2.0,Rect2i(),false], [Vector2i(1170,2532),3.0,Rect2i(0,141,1170,2289),true], [Vector2i(2532,1170),3.0,Rect2i(141,0,2250,1107),true]]
	for spec: Array in displays:
		root.size = spec[0]
		layout.refresh_with_metrics(spec[0],spec[1],spec[2],0,spec[3])
		for index in 6:
			start(index)
			await frames()
			var bounds := layout.logical_rect().grow(0.5)
			for node in overlay.find_children("*", "Control", true, false):
				var control := node as Control
				if not control.is_visible_in_tree() or control.name == "Shade": continue
				check(bounds.encloses(control.get_global_rect()), "display %s game %s %s rect %s bounds %s" % [spec[0],index,control.name,control.get_global_rect(),bounds])
				if control is Button: check(control.size.x >= 44 and control.size.y >= 44, "44 minimum touch button")
			for label: Label in [overlay.chrome.resort_label,overlay.chrome.place_label,overlay.patter_label]:
				check_eq(label.get_visible_line_count(),label.get_line_count(),"wrapped text all visible")
			var stage := overlay.stage as OriginalSignatureStage
			check(stage.text_overflows.is_empty(), "board text fits its panels: %s" % [stage.text_overflows])
			for rect: Rect2 in stage.text_boxes: check(Rect2(Vector2.ZERO,stage.size).grow(0.5).encloses(rect),"board text box %s in %s game %s display %s" % [rect,stage.size,index,spec[0]])
			for choice: Dictionary in overlay.game.view_state().get("choices",[]):
				var button: Button = overlay.bet_bar.action_buttons.get(StringName(choice["id"]))
				check(button != null and button.is_visible_in_tree() and not button.disabled,"choice focusable")
			overlay.resolve_round_now()
			await frames()
func test_board_hit_regions_use_overlay_without_extra_debit() -> void:
	for index in 6:
		start(index)
		await frames()
		var stage := overlay.stage as OriginalSignatureStage
		var choices: Array = overlay.game.view_state().get("choices",[])
		if not choices.is_empty():
			var id := StringName(choices[0]["id"])
			check(stage.choice_rects.has(id),"live choice has board hit region")
			var before := sim.city.funds
			check(stage._press((stage.choice_rects[id] as Rect2).get_center()),"board click accepted")
			if overlay.game.state == CasinoGame.PLAYING: check_eq(sim.city.funds,before,"decision has no extra stake")
		var state := overlay.game.view_state()
		check(not overlay.perform_action(&"spend_hidden_money").get("ok",false),"invalid choice refused")
		check_eq(overlay.game.view_state(),state,"refusal preserves state")
		overlay.resolve_round_now()

func test_live_terms_and_encore_feedback_remain_visible_on_short_displays() -> void:
	var displays := [[Vector2i(640,400),1.0,Rect2i(),false], [Vector2i(2532,1170),3.0,Rect2i(141,0,2250,1107),true]]
	for spec: Array in displays:
		root.size = spec[0]
		layout.refresh_with_metrics(spec[0],spec[1],spec[2],0,spec[3])
		for index in [0,1,2,3,4,5]:
			start(index)
			if index == 1: overlay.perform_action(&"night")
			if index == 2:
				overlay.game.rig([50])
				overlay.perform_action(&"rose")
			if index == 4: overlay.perform_action(&"draft_1")
			await frames()
			var stage := overlay.stage as OriginalSignatureStage
			var text := "\n".join(stage.rendered_text)
			var view := overlay.game.view_state()
			if index == 0:
				check(text.contains("Quiet 80% ×1.20") and text.contains("Force 55% ×1.70") and text.contains(CasinoLines.money(int(view["currentbank"]))),"both vault risk methods and current bank visible")
			if index == 1:
				var chosen: Dictionary = view["route_quotes"][1]
				check(text.contains(CasinoLines.money(int(chosen["returned"]))) and text.contains(CasinoLines.money(int(chosen["covered_returned"]))) and text.contains(CasinoLines.money(int(chosen["loss_returned"]))),"both route coverage win and loss returns visible")
			if index == 2:
				check(text.contains(CasinoLines.money(int(view["bank"]))),"live Encore bank visible")
				check(text.contains("Rose") and text.contains("Fan") and text.contains("WIN"),"player lead, audience and outcome shown")
			if index == 3:
				for quote: Dictionary in view["forecast_quotes"]:
					check(text.contains("%.3fx" % (float(quote["gross_basis"])/1000)),"exact forecast gross multiplier visible")
			if index == 4:
				for quote: Dictionary in view["contract_quotes"]:
					check(text.contains("%d/49" % int(quote["chance_numerator"])) and text.contains(CasinoLines.money(int(quote["returned"]))),"exact 49-card count and gross quote visible")
			if index == 5:
				for quote: Dictionary in view["claim_quotes"]:
					check(text.contains("%.1f%%" % (float(quote["chance"])/10)) and text.contains(CasinoLines.money(int(quote["returned"]))),"claim odds and gross returns visible")
			check(stage.text_overflows.is_empty(),"all live terms fit: %s" % [stage.text_overflows])
			overlay.resolve_round_now()
			await frames()
