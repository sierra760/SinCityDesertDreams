# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Street Names mode: the selected road segments, the name being typed
## and the simulation hold taken while the editor is open.
class_name StreetNamesSession
extends Node
var panel: StreetNamesPanel
var overlay: StreetNamingOverlay3D
var _host: GameHost
var _service: StreetNamingService
var _topology: StreetTopology
var _city: City
var _active := false
var _keys: Array[String] = []
var _selection_revision := 0
var _snapshot: Dictionary = {}
var _focus: WeakRef

func bind(host: GameHost, service: StreetNamingService, topology: StreetTopology) -> void:
	_host = host
	_service = service
	_topology = topology
	panel = StreetNamesPanel.new()
	host.ui_layer.add_child(panel)
	overlay = StreetNamingOverlay3D.new()
	host.city_view_3d.world.add_child(overlay)
	overlay.hide()
	panel.apply_requested.connect(apply_draft)
	panel.remove_requested.connect(remove_selected)
	panel.select_entire_requested.connect(select_entire)
	panel.clear_requested.connect(clear_selection)
	panel.done_requested.connect(finish)
	panel.branch_requested.connect(_branch)
	host.presentation.street_selection_requested.connect(toggle_segment_at)
	host.presentation.street_hovered.connect(_hover)
	host.display_layout.metrics_changed.connect(func(_metrics): refresh_layout())
	service.changed.connect(func(_revision,_affected):
		if _active: overlay.refresh(); _update_panel(false))

func is_active() -> bool:
	return _active

func enter() -> bool:
	if _active: return true
	if _host.stage != GameHost.Stage.PLAY or _host.is_input_blocked() or _host.is_exploring() or not _topology.is_bound_to(_host.sim.city): return false
	_city = _host.sim.city
	var focus := _host.get_viewport().gui_get_focus_owner()
	_focus = weakref(focus) if focus != null else null
	_host.restore_temporary_bulldoze()
	_snapshot = {"presentation":_host.presentation.capture_state(),"tool":_host.tool}
	_host.cancel_map_gesture()
	_host.query_panel.close()
	_host.select_tool(GameHost.NO_TOOL)
	_host.presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	_host.presentation.set_overlay(&"")
	_host.acquire_sim_process_hold(&"street_names")
	_active = true
	_host.presentation.set_street_names_active(true)
	_topology.rebuild(_city)
	_selection_revision = _topology.revision
	overlay.bind(_host.city_view_3d,_topology,_service)
	overlay.show()
	clear_selection()
	panel.show()
	refresh_layout()
	_host.refresh_street_menus()
	return true

func leave() -> void:
	if not _active: return
	_active = false
	_host.presentation.set_street_names_active(false)
	panel.hide()
	clear_selection()
	overlay.hide()
	overlay.clear()
	_host.select_tool(int(_snapshot.get("tool",GameHost.NO_TOOL)))
	_host.presentation.restore_state(_snapshot.get("presentation",{}))
	_host.menu_bar.set_checked(&"underground",_host.presentation.is_underground())
	_host.menu_bar.set_checked(&"overlay",true,_host.presentation.get_overlay())
	_host.release_sim_process_hold(&"street_names")
	var focus := _focus.get_ref() as Control if _focus != null else null
	if is_instance_valid(focus) and focus.is_visible_in_tree() and not _host.is_input_blocked(): focus.grab_focus()
	_focus = null
	_snapshot.clear()
	_city = null
	_host.refresh_street_menus()

## Done: a valid name typed for the selection but not yet applied is applied
## first rather than dropped; if it cannot be applied the editor stays open
## showing why.
func finish() -> void:
	if not _active: return
	if panel.has_unapplied_draft():
		var result := apply_draft()
		if not bool(result.get("ok",false)): return
	leave()

func selected_links() -> Array[String]:
	return _keys.duplicate()

func toggle_segment_at(point: Vector2) -> Dictionary:
	if not _active or _city != _host.sim.city: return {"error":"Street Names is not active."}
	var result := overlay.pick_segment(point)
	panel.message.text = String(result.get("error",""))
	panel.set_branches(result.get("branches",[]))
	if result.has("segment"): _toggle(result.segment)
	elif result.has("branches"):
		var branches: Array[String] = []
		for branch: Dictionary in result.branches:
			for key: String in branch.links: if not branches.has(key): branches.append(key)
		overlay.show_selection(_keys,branches)
	return result

func _toggle(segment: Dictionary) -> void:
	if _selection_revision != _topology.revision:
		_keys.clear()
		_selection_revision = _topology.revision
	var selected := true
	for key: String in segment.links: selected = selected and _keys.has(key)
	for key: String in segment.links:
		if selected: _keys.erase(key)
		elif not _keys.has(key): _keys.append(key)
	_keys.sort()
	_update_panel(true)
	overlay.show_selection(_keys,[])

func _branch(id: String) -> void:
	var segment := overlay.segment_by_id(id)
	if not segment.is_empty(): _toggle(segment)
	panel.set_branches([])

func _hover(point: Vector2) -> void:
	if not _active: return
	var result := overlay.pick_segment(point) if point.x >= 0 else {}
	var keys: Array[String] = []
	if result.has("segment"): keys.assign(result.segment.links)
	overlay.show_selection(_keys,keys)

func _single_id() -> int:
	if _city == null or _keys.is_empty(): return 0
	var id := int(_city.street_naming.links.get(_keys[0],0))
	for key: String in _keys:
		if int(_city.street_naming.links.get(key,0)) != id: return 0
	return id

func _update_panel(update_draft: bool) -> void:
	if _city == null: return
	var ids: Dictionary = {}
	for key: String in _keys: ids[_city.street_naming.links.get(key,0)] = true
	var current := String(_city.street_naming.streets.get(_single_id(),""))
	panel.set_selection(_keys.size(),current,ids.size()>1)
	var names: Array[String] = []
	names.assign(_city.street_naming.streets.values())
	panel.set_names(names)
	if update_draft: panel.set_draft(current)

func apply_draft() -> Dictionary:
	if not _active: return {"ok":false,"error":"Street Names is not active."}
	var result := _service.assign(_keys,panel.draft_text(),_selection_revision)
	panel.message.text = "Street name applied." if result.ok else String(result.error)
	if result.ok:
		_update_panel(true)
		overlay.refresh()
	return result

func remove_selected() -> Dictionary:
	if not _active: return {"ok":false,"error":"Street Names is not active."}
	var result := _service.remove(_keys,_selection_revision)
	panel.message.text = "Name removed from selection." if result.ok else String(result.error)
	if result.ok: _update_panel(true); overlay.refresh()
	return result

func select_entire() -> void:
	var id := _single_id()
	if not _active or id == 0: return
	_keys.clear()
	for key: String in _city.street_naming.links:
		if int(_city.street_naming.links[key]) == id: _keys.append(key)
	_keys.sort()
	_selection_revision = _topology.revision
	_update_panel(true)
	overlay.show_selection(_keys,[])

func clear_selection() -> void:
	_keys.clear()
	panel.set_draft("")
	panel.set_selection(0,"",false)
	panel.message.text = ""
	panel.set_branches([])
	if _active: _update_panel(false); overlay.show_selection(_keys,[])

func refresh_layout() -> void:
	if not _active: return
	var bounds := _host.display_layout.logical_rect()
	bounds.position.y += _host.menu_bar.size.y
	bounds.size.y -= _host.menu_bar.size.y+_host.status_bar.size.y
	panel.apply_layout(bounds,bool(_host.display_layout.metrics.get("compact",false)))

func structural_changed() -> void:
	if _active: overlay.refresh()
