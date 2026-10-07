# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
var host: GameHost
func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://street-input.cfg"
	root.add_child(host)
	host.begin_city(flat_city(),{},42,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	check(host.handle_drag(Vector2i(50,60),Vector2i(60,60)).ok)
	check(host.handle_drag(Vector2i(55,55),Vector2i(55,65)).ok)
	host.city_view_3d.set_camera_state(Vector3(55.5,1,60.5),0,18)
	await physics_frame
func after_each() -> void:
	host.free()
	await process_frame
func session() -> Node:
	var value: Node = host.get("street_names")
	check(value != null,"Main provides integrated Street Names session")
	return value
func touch(index: int,on: bool,point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = on
	event.position = point
	root.push_input(event)
func test_clean_touch_toggles_and_second_finger_cancels() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var before := SaveFormat.encode_city(host.sim.city)
	for rotation: int in 4:
		host.city_view_3d.set_camera_state(Vector3(55.5,1,60.5),rotation,18)
		var point := host.city_view_3d.project_cell(Vector2i(53,60))
		touch(0,true,point)
		check(s.selected_links().is_empty(),"press does not select")
		touch(0,false,point)
		check(not s.selected_links().is_empty(),"actual contact selects approach")
		touch(0,true,point)
		touch(0,false,point)
		check(s.selected_links().is_empty(),"second tap toggles off")
		touch(0,true,point)
		touch(1,true,Vector2(10,10))
		touch(1,false,Vector2(10,10))
		touch(0,false,point)
		check(s.selected_links().is_empty(),"UI second finger cancels selection")
	check_eq(SaveFormat.encode_city(host.sim.city),before,"selection is transient and free")
func test_center_junction_offers_branches() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var result: Dictionary = s.toggle_segment_at(host.city_view_3d.project_cell(Vector2i(55,60)))
	check(result.has("branches"),"a junction center offers its incident branches")
	check(s.selected_links().is_empty(),"junction never flood-selects")
	if result.has("branches"): check_eq(result.branches.size(),4)
func test_mouse_drag_touch_slop_and_panel_never_paint() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var point := host.city_view_3d.project_cell(Vector2i(53,60))
	touch(0,true,point)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point+Vector2(18,0)
	drag.relative = Vector2(18,0)
	root.push_input(drag)
	touch(0,false,point)
	check(s.selected_links().is_empty(),"exceeding slop stays cancelled after returning")
	var panel: Control = s.get("panel")
	var ui_point := panel.get_global_rect().get_center()
	touch(0,true,ui_point)
	touch(0,false,point)
	check(s.selected_links().is_empty(),"panel touch never transfers to map")
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = point+Vector2(30,0)
	motion.relative = Vector2(30,0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	press.pressed = false
	press.position = motion.position
	root.push_input(press)
	check(s.selected_links().is_empty(),"mouse drag never paints")
func test_typing_blocks_shortcuts_and_escape_outside_editing_leaves() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var panel: Control = s.get("panel")
	var edit: LineEdit = panel.get("name_edit")
	edit.grab_focus()
	var rotation := host.city_view_3d.quarter_turn
	var speed := host.sim.speed
	for code: int in [KEY_R,KEY_U,KEY_Q,KEY_SPACE]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = code+32 if code != KEY_SPACE else 32
		event.pressed = true
		root.push_input(event)
	check_eq(host.city_view_3d.quarter_turn,rotation)
	check_eq(host.sim.speed,speed)
	check_eq(host.tool,GameHost.NO_TOOL)
	check(not host.presentation.is_underground())
	check(s.is_active())
	edit.release_focus()
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	root.push_input(escape_key)
	check(not s.is_active())
func test_projected_bridge_and_tunnel_follow_actual_topology_points() -> void:
	var s := session()
	if s == null: return
	var banks := load("res://tests/test_bridge_approaches.gd")
	var bore := load("res://tests/exploration/road_tunnel_fixture.gd")
	for fixture: Dictionary in [{"city":banks.bank_city(true,3,87,true),"key":"22,22,open>23,22,open"},{"city":bore.city(),"key":"22,20,bore>23,20,bore"}]:
		host.begin_city(fixture.city,{},42,CityStats.new())
		host.sim.set_speed(GameClock.Speed.PAUSED)
		check(s.enter())
		var points: PackedVector3Array = host.street_topology.connection_points(fixture.key)
		check(not points.is_empty())
		if points.is_empty(): continue
		for rotation: int in 4:
			host.city_view_3d.set_camera_state(points[4],rotation,14)
			var result: Dictionary = s.toggle_segment_at(host.city_view_3d.project_world(points[4]))
			check(result.has("segment"),"real bridge deck/bore trace pick")
			if result.has("segment"): check(result.segment.links.has(fixture.key))
			s.clear_selection()
		s.leave()
func test_pointer_refresh_tracks_camera_scale_and_ui_ownership() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	await process_frame
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = host.city_view_3d.project_cell(Vector2i(53,60))
	root.push_input(motion)
	var overlay: Node = s.get("overlay")
	check(not overlay.get("_hovered").is_empty())
	host.city_view_3d.set_center_cell(Vector2i(90,90))
	check(overlay.get("_hovered").is_empty(),"stationary point repicks after camera move")
	host.city_view_3d.set_center_cell(Vector2i(55,60))
	host.city_view_3d.set_render_options("high",75)
	host.presentation.refresh_query_pointer_hover()
	var expected: Dictionary = overlay.pick_segment(motion.position)
	check_eq(overlay.get("_hovered"),expected.get("segment",{}).get("links",[]),"render scaling keeps logical point")
	motion.position = s.get("panel").get_global_rect().get_center()
	root.push_input(motion)
	check(overlay.get("_hovered").is_empty(),"delivered UI pointer immediately hides hover")
func test_clean_slop_pinch_and_isolated_tile_explanation() -> void:
	var s := session()
	if s == null: return
	host.select_tool(Tools.Kind.ROAD)
	check(host.handle_drag(Vector2i(51,63),Vector2i(51,63)).ok)
	await physics_frame
	check(s.enter())
	var point := host.city_view_3d.project_cell(Vector2i(53,60))
	touch(0,true,point)
	touch(0,false,point+Vector2(5,0))
	check(not s.selected_links().is_empty(),"movement within tap slop still selects on release")
	s.clear_selection()
	var size_before := host.city_view_3d.camera_size
	touch(0,true,point)
	touch(1,true,point+Vector2(60,0))
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = point+Vector2(90,0)
	drag.relative = Vector2(30,0)
	root.push_input(drag)
	touch(1,false,drag.position)
	touch(0,false,point)
	check_lt(host.city_view_3d.camera_size,size_before,"two city fingers retain pinch navigation")
	check(s.selected_links().is_empty())
	var result: Dictionary = s.toggle_segment_at(host.city_view_3d.project_cell(Vector2i(51,63)))
	check_eq(result.get("error",""),"Connect this road before naming a segment.")
	check(s.selected_links().is_empty())
# Explicit test-only owner models a release consumed before presentation. The
# ordinary headless panel route is covered separately and is not claimed to
# consume a map-origin release on this display server.
class PanelReleaseOwner extends Node:
	var panel: Control
	var consume := false
	var releases := 0
	func _input(event: InputEvent) -> void:
		if consume and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and panel.get_global_rect().has_point(event.position):
			releases += 1
			get_viewport().set_input_as_handled()

func test_mouse_panel_release_ends_click_and_drag_ownership_before_hover() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	await process_frame
	await process_frame
	var panel: Control = s.get("panel")
	var gui_owner := PanelReleaseOwner.new()
	gui_owner.panel = panel
	host.add_child(gui_owner)
	for consumed: bool in [false,true]:
		gui_owner.consume = consumed
		for dragging: bool in [false,true]:
			var point := host.city_view_3d.project_cell(Vector2i(53,60))
			var aim := InputEventMouseMotion.new()
			aim.position = point
			aim.global_position = point
			root.push_input(aim)
			await process_frame
			var press := InputEventMouseButton.new()
			press.position = point
			press.global_position = point
			press.button_index = MOUSE_BUTTON_LEFT
			press.button_mask = MOUSE_BUTTON_MASK_LEFT
			press.pressed = true
			root.push_input(press)
			if dragging:
				var motion := InputEventMouseMotion.new()
				motion.position = point+Vector2(30,0)
				motion.global_position = motion.position
				motion.relative = Vector2(30,0)
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				var before_drag := host.city_view_3d.center
				root.push_input(motion)
				check_ne(host.city_view_3d.center,before_drag,"fixture really pans before releasing on panel")
			aim.position = panel.get_global_rect().position+Vector2(6,6)
			aim.global_position = aim.position
			aim.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(aim)
			await process_frame
			check_eq(root.gui_get_hovered_control(),panel,"actual panel target established before release")
			press.pressed = false
			press.button_mask = 0
			press.position = aim.position
			press.global_position = aim.position
			root.push_input(press)
			var before_hover := host.city_view_3d.center
			var selected: Array = s.selected_links()
			var hover := InputEventMouseMotion.new()
			hover.position = point+Vector2(60,0)
			hover.global_position = hover.position
			hover.relative = Vector2(40,0)
			hover.button_mask = 0
			root.push_input(hover)
			check_eq(host.city_view_3d.center,before_hover,"button-free hover cannot pan after panel release (explicit consumption: %s)" % consumed)
			check_eq(s.selected_links(),selected,"panel release/ordinary hover cannot select")
	check_eq(gui_owner.releases,2,"test-only earlier input owner consumed both modeled panel releases")

func _naming_resource_ids(overlay: Node) -> Array:
	var ids: Array = []
	for child: Node in overlay.get_children():
		ids.append(child.get_instance_id())
		if child is MeshInstance3D:
			ids.append(child.mesh.get_instance_id())
			if child.material_override != null: ids.append(child.material_override.get_instance_id())
	return ids

## Strokes share one material per color: hover swaps materials, never edits one.
func _naming_materials(overlay: Node) -> Dictionary:
	var materials: Dictionary = {}
	for child: Node in overlay.get_children():
		if child is MeshInstance3D:
			for surface: int in child.mesh.get_surface_count():
				materials[child.mesh.surface_get_material(surface)] = true
	return materials

func _visible_naming_color_count(overlay: Node, color: Color) -> int:
	var count := 0
	for child: Node in overlay.get_children():
		if child is MeshInstance3D and child.visible:
			var material := child.mesh.surface_get_material(0) as StandardMaterial3D
			if material != null and material.albedo_color == color: count += 1
	return count

func test_hover_and_selection_retain_naming_layer_nodes_and_meshes() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var overlay: Node = s.get("overlay")
	var segments: Array = overlay.get("_segments")
	check_eq(segments.size(),4)
	var ids := _naming_resource_ids(overlay)
	check(not ids.is_empty())
	var count := overlay.get_child_count()
	for i: int in 12:
		var hovered: Array[String] = []
		hovered.assign(segments[i%segments.size()].links)
		overlay.show_selection([] as Array[String],hovered)
		check_eq(_naming_resource_ids(overlay),ids,"hover retains every existing strip/label/mesh instance")
		check_eq(overlay.get_child_count(),count,"hover does not allocate another layer")
		check_eq(_visible_naming_color_count(overlay,Color("dcaf61")),hovered.size(),"only current hover stays brass")
		check(_naming_materials(overlay).size() <= 4,"every strip shares the normal/hover/outline/selection materials")
	var selected: Array[String] = []
	selected.assign(segments[0].links)
	overlay.show_selection(selected,[] as Array[String])
	check_eq(_naming_resource_ids(overlay),ids,"selection keeps base geometry and labels")
	check_eq(overlay.get_child_count(),count,"selection toggles retained feedback")
	check_eq(_visible_naming_color_count(overlay,Color("38cbb5")),selected.size(),"retained selected strips stay teal")
	check_eq(_visible_naming_color_count(overlay,Color("173c3a")),selected.size(),"retained contrasting outlines stay visible")
	check_eq(_visible_naming_color_count(overlay,Color("dcaf61")),0,"old hover clears")
	var selected_labels := 0
	for child: Node in overlay.get_children():
		if child is Label3D and child.text.begins_with("✓ "): selected_labels += 1
	check_eq(selected_labels,1,"retained label still identifies the selected segment")
	overlay.show_selection([] as Array[String],[] as Array[String])
	for child: Node in overlay.get_children():
		if child is Label3D: check(not child.text.begins_with("✓ "),"clearing updates retained selected-state label")
	check_eq(_visible_naming_color_count(overlay,Color("cfcab7")),overlay.get("_link_visuals").size(),"cleared hover restores every base strip color")
	var degenerate: MeshInstance3D = overlay.call("_stroke",PackedVector3Array([Vector3.ZERO]),Color("cfcab7"),.045,false,121)
	check_eq(degenerate.mesh.get_surface_count(),0,"a one-point link emits no empty surface")
	degenerate.free()

func test_button_free_motion_cancels_pending_naming_mouse_owner() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var point := host.city_view_3d.project_cell(Vector2i(53,60))
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	var before := host.city_view_3d.center
	var hover := InputEventMouseMotion.new()
	hover.position = point+Vector2(35,0)
	hover.global_position = hover.position
	hover.relative = Vector2(35,0)
	hover.button_mask = 0
	root.push_input(hover)
	check_eq(host.city_view_3d.center,before,"delivered button state ends stale ownership even if release was consumed elsewhere")
	check(s.selected_links().is_empty())
	press.pressed = false
	press.button_mask = 0
	root.push_input(press)
	check(s.selected_links().is_empty(),"a later release cannot revive a cancelled pending click")

func test_naming_cache_invalidates_height_and_published_names() -> void:
	var s := session()
	if s == null: return
	check(s.enter())
	var overlay: Node = s.get("overlay")
	var before_ids := _naming_resource_ids(overlay)
	var first_mesh := overlay.get_child(0) as MeshInstance3D
	var before_y := first_mesh.mesh.get_aabb().position.y
	var revision := host.street_topology.revision
	for y: int in range(50,71):
		for x: int in range(45,66): host.sim.city.set_heights(x,y,5,0)
	check(not host.street_topology.rebuild(host.sim.city),"same-City height changes keep structural token")
	check_eq(host.street_topology.revision,revision)
	overlay.refresh()
	check_ne(_naming_resource_ids(overlay),before_ids,"geometry changes invalidate retained layer independently of topology revision")
	first_mesh = overlay.get_child(0) as MeshInstance3D
	check_gt(first_mesh.mesh.get_aabb().position.y,before_y,"refreshed strips actually follow raised road surface")
	var keys: Array[String] = []
	keys.assign(overlay.get("_segments")[0].links)
	check(host.street_naming_service.assign(keys,"Mesa Way",revision).ok)
	var named := false
	for child: Node in overlay.get_children():
		if child is Label3D and child.text.contains("Mesa Way"): named = true
	check(named,"published name change refreshes retained labels")
