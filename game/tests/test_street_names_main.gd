# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Street naming through the full game host; all construction goes through
## paid host transactions.
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
const SAVE := "user://street-main.sc2d"
const RECOVERY := "user://street-main-recovery.sc2d"
var host: GameHost

static func paid_setup(target: GameHost) -> Array[Dictionary]:
	var city := flat_city(100000,42)
	city.name = "Street Names Test"
	city.founded_year=2000
	var stats := CityStats.new()
	target.begin_city(city,{},4242,stats)
	target.sim.set_speed(GameClock.Speed.PAUSED)
	var results: Array[Dictionary]=[]
	for item: Array in [
		[Tools.Kind.RAIL,Vector2i(18,20),Vector2i(34,20)],
		[Tools.Kind.RAIL_STATION,Vector2i(20,21),Vector2i(20,21)],
		[Tools.Kind.RAIL_STATION,Vector2i(29,21),Vector2i(29,21)],
		[Tools.Kind.ROAD,Vector2i(18,24),Vector2i(34,24)],
		[Tools.Kind.ROAD,Vector2i(25,22),Vector2i(25,26)],
		[Tools.Kind.SUBWAY_STATION,Vector2i(20,28),Vector2i(20,28)],
		[Tools.Kind.SUBWAY_STATION,Vector2i(29,28),Vector2i(29,28)],
		[Tools.Kind.SUBWAY,Vector2i(18,28),Vector2i(34,28)],
		[Tools.Kind.ROAD,Vector2i(18,30),Vector2i(34,30)],
		[Tools.Kind.HIGHWAY,Vector2i(40,16),Vector2i(55,16)],
		[Tools.Kind.ROAD,Vector2i(45,18),Vector2i(49,18)],
		[Tools.Kind.ROAD,Vector2i(49,18),Vector2i(49,21)],
		[Tools.Kind.ONRAMP,Vector2i(44,18),Vector2i(44,18)]]:
		target.select_tool(item[0])
		results.append(target.handle_drag(item[1],item[2]))
		# A road meeting the highway asks about ramps; the setup places its
		# one ramp explicitly below, so it skips each offer.
		while target.choice_dialog.is_open(): target.choice_dialog.cancel()
	target.presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	target.city_view_3d.set_camera_state(Vector3(29,1,24),0,32)
	return results

static func preserved(target: GameHost, allow_custom: bool = false) -> Dictionary:
	var encoded := SaveFormat.encode_city(target.sim.city).duplicate(true)
	encoded.erase("street_naming")
	if allow_custom:
		# Custom Rename legitimately owns facility name only.
		var copy := target.sim.city.duplicate_city()
		for record: Dictionary in copy.facilities.values(): record.erase("name")
		encoded = SaveFormat.encode_city(copy)
		encoded.erase("street_naming")
	return {"city":encoded,"runtime":target.sim.snapshot().duplicate(true),"rng":target.sim.rng.state(),"funds":target.sim.city.funds}

func before_each() -> void:
	host=MAIN.instantiate(); host.preferences_path="user://street-main.cfg"; root.add_child(host)
	var total := 0
	for result: Dictionary in paid_setup(host):
		check(result.ok and result.applied,"normal paid setup: "+str(result))
		check_gt(int(result.cost),0)
		total += int(result.cost)
	check_eq(host.sim.city.funds,100000-total,"paid setup pinned independently of free naming")
	await physics_frame

func after_each() -> void:
	host.free(); await process_frame
	for path: String in [SAVE,RECOVERY]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _pick(cell: Vector2i) -> void:
	host.presentation.street_selection_requested.emit(host.city_view_3d.project_cell(cell))

func _apply(text: String) -> void:
	var before := preserved(host)
	host.street_names.panel.set_draft(text)
	check(not host.street_names.panel.apply_button.disabled)
	host.street_names.panel.apply_button.pressed.emit()
	check_eq(preserved(host),before,"Apply preserves complete non-naming city/runtime/RNG/funds")
	check_eq(host.street_names.panel.message.text,"Street name applied.")

func test_main_select_name_explore_customize_rename_and_reload() -> void:
	host.menu_bar.press(&"street_names")
	check(host.street_names.is_active(),"actual View action enters session")
	_pick(Vector2i(22,24)); _pick(Vector2i(31,24)); _pick(Vector2i(23,30))
	check_eq(host.street_names.selected_links().size(),32,"both junction arms and disconnected subway road selected")
	_apply("  Palm   Avenue ")
	var street_id: int=host.sim.city.street_naming.links["18,24,open>19,24,open"]
	check_eq(host.sim.city.street_naming.streets[street_id],"Palm Avenue")
	var titles: Array[String]=[]
	for anchor: Vector2i in [Vector2i(20,21),Vector2i(29,21),Vector2i(20,28),Vector2i(29,28)]:
		var title := StationNameResolver.display_name(host.sim.city,anchor,anchor.y==28)
		check(title.begins_with("Palm Avenue"),"automatic station source: "+title)
		check(not titles.has(title),"shared rail/subway uniqueness")
		titles.append(title)
	host.street_names.panel.clear_button.pressed.emit()
	_pick(Vector2i(25,23)); _pick(Vector2i(25,25)); _apply("Fremont Street")
	host.street_names.panel.clear_button.pressed.emit()
	host.city_view_3d.set_center_cell(Vector2i(47,18)); _pick(Vector2i(46,18)); _apply("Canyon Way")
	host.street_names.panel.done_button.pressed.emit()
	var before := preserved(host,true)
	host.construction.prompt_rename(Vector2i(20,21))
	check_eq(host.notice_dialog.line_edit.text,"")
	host.notice_dialog.line_edit.text="Sierra Central"
	host.notice_dialog.dismiss(&"submit")
	check_eq(preserved(host,true),before,"custom Rename changes only name and automatic reservations")
	check_eq(StationNameResolver.display_name(host.sim.city,Vector2i(20,21),false),"Sierra Central")
	host.menu_bar.press(&"street_names")
	_pick(Vector2i(31,24))
	host.street_names.panel.entire_button.pressed.emit()
	check_eq(host.street_names.selected_links().size(),32)
	_apply("Desert Rose Avenue")
	check_eq(host.sim.city.street_naming.streets[street_id],"Desert Rose Avenue","whole rename keeps identity")
	host.street_names.panel.done_button.pressed.emit()
	host.city_view_3d.set_center_cell(Vector2i(25,24))
	var complete := host.files.save_content().duplicate(true)
	check(host.enter_explore())
	check(host.city_view_3d.street_signage.visible)
	var found_intersection := false
	var found_exit := false
	for sign_node: Node in host.city_view_3d.street_signage.find_children("*","Node3D",true,false):
		if sign_node.get_meta("sign_kind","")=="intersection":
			found_intersection=sign_node.get_meta("display_texts",[]).has("Desert Rose Avenue")
		if not sign_node.has_meta("display_text"): continue
		var text: String=sign_node.get_meta("display_text")
		if text=="Canyon Way":
			found_exit=true
			check(sign_node.has_meta("travel_direction"),"real connected exit owns incoming facing")
	check(found_intersection,"real Explore mounts named intersection")
	check(found_exit,"paid highway/ramp connector produces destination")
	host.return_to_build()
	check_eq(host.files.save_content(),complete,"Explore presentation preserves exact city/sim")
	var metadata := host.sim.city.street_naming.duplicate(true)
	check_eq(host.files.write_save(SAVE),OK)
	check(host.load_city(SAVE))
	check_eq(host.sim.city.street_naming,metadata,"native reload preserves IDs and allocated suffixes")
	if host.files.save_content()!=complete:
		var diagnostic := FileAccess.open("user://street-main-reload-difference.json",FileAccess.WRITE)
		diagnostic.store_string(JSON.stringify({"before":complete,"after":host.files.save_content()},"\t")); diagnostic.close()
	check(host.files.save_content()==complete,"exact reload contents; differences retained in private profile")
	check_eq(StationNameResolver.display_name(host.sim.city,Vector2i(20,21),false),"Sierra Central")

func test_applied_only_background_recovery_and_replacement_clear_stale_session() -> void:
	host.menu_bar.press(&"street_names"); _pick(Vector2i(22,24)); _apply("Applied Street")
	var committed := host.sim.city.street_naming.duplicate(true)
	host.street_names.panel.set_draft("Unapplied draft")
	var before := preserved(host)
	check_eq(host.suspend_for_background(RECOVERY),OK)
	var recovered := SaveFormat.load(RECOVERY)
	check(recovered.ok)
	check_eq(recovered.city.street_naming,committed,"recovery has committed names only")
	check_eq(preserved(host),before)
	host.resume_from_background()
	var old_city := host.sim.city
	var old_revision := host.street_topology.revision
	var old_keys := host.street_names.selected_links()
	host.begin_city(flat_city(50000,43),{},43,CityStats.new())
	check(not host.street_names.is_active())
	check(host.street_names.selected_links().is_empty())
	check_eq(host.street_names.panel.draft_text(),"")
	check(not host.street_naming_service.assign(old_keys,"Stale",old_revision).ok)
	check(host.sim.city.street_naming.links.is_empty())
	check_eq(old_city.street_naming,committed)
