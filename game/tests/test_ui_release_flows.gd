# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Presentation contracts for the release-facing city flows; no save writes.
extends "res://tests/test_case.gd"
var holder: Control
func _run_all() -> void:
	root.size = Vector2i(640,400)
	for method in get_method_list():
		if not String(method.name).begins_with("test_"): continue
		_current = method.name
		holder = Control.new()
		root.add_child(holder)
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var before := _failed
		await call(method.name)
		holder.free()
		if before == _failed: _passed += 1
	print("Results: %d passed, %d failed" % [_passed,_failed])
	quit(0 if _failed == 0 else 1)
func _settle() -> void:
	for frame in 4: await process_frame
func _texts(node: Node) -> String:
	var result := str(node.get("text")) if node is Label or node is Button else ""
	for child in node.get_children(): result += "\n" + _texts(child)
	return result
func test_title_routes_settings() -> void:
	var title := TitleScreen.new()
	holder.add_child(title)
	for key in ["settings"]:
		check(title.has_signal(key+"_requested"), key+" signal")
		var button: Button = title.get(key+"_button")
		check(button != null, key+" button")
		if button == null or not title.has_signal(key+"_requested"): continue
		var requests := [0]
		title.connect(key+"_requested",func(): requests[0] += 1)
		button.pressed.emit()
		check_eq(requests[0],1)
	await _settle()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(title.quit_button.get_global_rect()),"title actions fit compact screen")
func test_changed_preview_is_explicit_and_start_is_editor_entry() -> void:
	var dialog := NewCityDialog.new()
	holder.add_child(dialog)
	dialog.set_params({"name":"Release Test","seed":123,"hills":0,"water":0,"trees":0,"river":false})
	dialog.generate_preview()
	var shown := dialog.preview_city
	dialog.hills_slider.value = 20
	check(dialog.preview_label.text.to_lower().contains("changed"),"stale preview is marked")
	check_eq(dialog.preview_city,shown,"editing controls does not secretly regenerate")
	check(dialog.start_button.text.to_lower().contains("shape"),"action names terrain editing")
	check(_texts(dialog).contains("Found City"),"founding sequence explained")
func test_load_rows_distinguish_files_and_dates() -> void:
	var dialog := LoadDialog.new()
	holder.add_child(dialog)
	dialog.open([
		{"name":"Same Town","path":"user://saves/town-second.sc2d","date_text":"2026-10-03 10:30","year":1950,"population":1234,"stage":"play"},
		{"name":"Same Town","path":"user://saves/terrain-draft.sc2d","date_text":"2026-10-02 09:00","year":1950,"population":0,"stage":"editing"},
	])
	var details: Label = dialog.get("details_label")
	check(details != null,"selected-save details have a wrapping label outside ItemList")
	if details == null: return
	check(not dialog.item_list.get_item_text(0).contains("\n"),"rows do not rely on unsupported ItemList wrapping")
	check_eq(details.autowrap_mode,TextServer.AUTOWRAP_WORD_SMART)
	for phrase in ["town-second.sc2d","2026-10-03","Founded city","1,234"]:
		check(details.text.contains(phrase),"selected detail: "+phrase)
	dialog.select(1)
	check(details.text.contains("terrain-draft.sc2d") and details.text.contains("Unfounded map"),"programmatic selection updates details")
	dialog.item_list.select(0)
	dialog.item_list.item_selected.emit(0)
	check(details.text.contains("town-second.sc2d"),"list interaction updates details")
	await _settle()
	check(details.get_global_rect().size.x <= dialog.panel.size.x,"details wrap within panel width")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(details.get_global_rect()),"selected details remain onscreen at640x400")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(dialog.load_button.get_global_rect()),"compact Load stays reachable")
	check(dialog.has_signal("browse_requested"),"native browse route")
	dialog.open([] as Array[Dictionary])
	check(dialog.empty_label.text.contains("Browse"),"empty state provides next action")
	check(dialog.load_button.disabled)
	check(details.text.is_empty() and not details.visible,"empty refresh clears previous save details")
func test_save_resolved_name_and_error_reset() -> void:
	var dialog := SaveDialog.new()
	holder.add_child(dialog)
	dialog.open("Round Trip: 2?")
	check(_texts(dialog).contains("Round Trip 2.sc2d"),"resolved filename visible")
	dialog.name_edit.text = " "
	dialog.confirm()
	check(dialog.is_open())
	dialog.close()
	dialog.open("Retained")
	check(not dialog.hint_label.text.contains("Type a name"),"old validation cleared on reopen")
	dialog.set_error("Try another location.")
	check_eq(dialog.name_edit.text,"Retained")
func test_options_sections_and_fixed_done_fit_compact() -> void:
	var options := OptionsWindow.new()
	holder.add_child(options)
	options.open()
	var text := _texts(options)
	check(text.contains("Graphics") and text.contains("Display") and not text.contains("City gameplay"),"options groups contain only display and graphics preferences")
	check(text.to_lower().contains("apply immediately"),"instant preference behavior explained")
	var done: Button = options.get("done_button")
	check(done != null,"explicit Done action")
	await _settle()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(options.panel.get_global_rect()),"options fits 640x400")
	if done != null:
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(done.get_global_rect()),"Done reachable")
		done.pressed.emit()
		check(not options.visible)
func test_help_covers_first_city_and_exploration() -> void:
	var help := HelpWindow.new()
	holder.add_child(help)
	var text := _texts(help)
	for phrase in ["Found City","Explore City","Settings → Controls","Recover","Return to Build","not saved"]:
		check(text.contains(phrase),"help explains "+phrase)

func test_modal_navigation_restores_the_previous_control() -> void:
	var previous := Button.new()
	previous.text = "Previous"
	holder.add_child(previous)
	previous.grab_focus()
	var dialog := SaveDialog.new()
	holder.add_child(dialog)
	dialog.open("Focus")
	check_eq(root.gui_get_focus_owner(),dialog.name_edit)
	var next := dialog.cancel_button.get_node_or_null(dialog.cancel_button.focus_next)
	check(next != null and dialog.is_ancestor_of(next),"Tab stays in the modal")
	dialog.close()
	check_eq(root.gui_get_focus_owner(),previous,"closing restores previous control")
func test_title_options_are_display_preferences_only() -> void:
	var options := OptionsWindow.new()
	holder.add_child(options)
	var sim := Simulation.new()
	options.bind(sim)
	check(not options.checks.has(&"disasters_enabled"))
	check(not options.checks.has(&"auto_budget"))
	check(not options.quality_button.disabled and not options.scale_button.disabled)
	check(_texts(options).contains("Map visibility and zoom: View menu."))
	var changes := [0]
	options.option_changed.connect(func(_key,_value): changes[0] += 1)
	options.set_values({"render_quality":"balanced","disasters_enabled":false})
	check_eq(changes[0],0,"programmatic state does not emit changes")
	sim.city = City.new()
	options.bind(sim)
	check(not options.checks.has(&"disasters_enabled"), "city toggles stay in their owning menus")
	sim.free()
