# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Switching between Build and Explore. Entering Explore remembers the Build
## camera, tool and map presentation and hides the Build chrome; returning
## restores them. The city's simulation is held for the whole Explore session:
## no days pass while the player walks or drives, and the chosen speed resumes
## on return. Explore's own world (the player, ambient traffic, livestock,
## casino patrons and mod scripts) runs on Explore's clock instead.
class_name ExploreModeSwitch
extends RefCounted

## The simulation hold Explore keeps from entry until return.
const HOLD := &"explore"

var _host: GameHost
## The Build camera, tool and presentation saved on entering Explore.
var _snapshot: Dictionary = {}
var _choice_city: City
var _choice_token := 0


func _init(host: GameHost) -> void:
	_host = host


## Whether Explore can start: a founded city with nothing else holding input.
func can_enter() -> bool:
	var host := _host
	return _choice_city == null and host.stage == GameHost.Stage.PLAY and not host.is_input_blocked() and not host.is_exploring() \
		and not host.street_names.is_active() and is_instance_valid(host.exploration)


## Enter Explore now. Returns false when it cannot start.
func enter() -> bool:
	if not can_enter():
		return false
	return _request_start(false)


## Enter Explore behind the loading screen.
func request() -> void:
	if not can_enter(): return
	_request_start(true)


func _request_start(loading: bool) -> bool:
	var city := _host.sim.city
	var house := ExploreMayorsHouse.find(city)
	if house.is_empty(): return _start(false,loading)
	_choice_city = city
	_choice_token += 1
	_host.notices.queue("Start Exploring","Where would you like to start? The Mayor’s House has the all-terrain Mayormobile, police cruiser, fire truck and helicopter waiting at ground level.",
		[["Current View",&"center"],["Mayor’s House",&"house"],["Cancel",&"cancel"]],_answer_start.bind(city,_choice_token,loading))
	return true

func _answer_start(choice: StringName, city: City, token: int, loading: bool) -> void:
	if token != _choice_token or _choice_city != city: return
	_choice_city = null
	if choice not in [&"center",&"house"] or _host.stage != GameHost.Stage.PLAY or _host.sim.city != city: return
	_start(choice == &"house",loading)

func _start(at_house: bool, loading: bool) -> bool:
	var city := _host.sim.city
	var token := _choice_token
	if loading:
		_host.run_loading("Preparing Explore…","Preparing walking paths, vehicles and station interiors.",_enter_current.bind(city,token,at_house))
		return true
	return _enter_current(city,token,at_house)

## Loading yields before its work runs. Revalidate on the far side of that
## yield, so replacing/closing a city or disposing the switch cancels entry.
func _enter_current(city: City, token: int, at_house: bool) -> bool:
	if token != _choice_token or city != _host.sim.city or _host.stage != GameHost.Stage.PLAY or _host.is_exploring(): return false
	return _enter(at_house)

func _enter(at_house: bool = false) -> bool:
	var host := _host
	var view := host.city_view_3d
	var snapshot := {"center":view.center,"quarter_turn":view.quarter_turn,
		"camera_size":view.camera_size,"tool":host.chosen_tool(),
		"presentation":host.presentation.capture_state()}
	# Notices and dialogs suspend Explore and resume it once closed; a Build
	# window opened during Explore keeps it paused until the window is closed.
	host.exploration.modal_open = host.is_input_blocked
	host.exploration.window_open = func() -> bool:
		return is_instance_valid(host.window_manager) and host.window_manager.front() != null
	if not host.exploration.enter(host.sim.city,view.center,at_house):
		host.notices.show("Cannot Enter Explore Mode", "Explore mode requires a safe outdoor road. Build a road with clear space and try again.")
		return false
	# A Build window (Budget, Graphs, Options…) would sit over the walk with
	# the pointer captured; Explore starts with them closed.
	if is_instance_valid(host.window_manager): host.window_manager.close_all()
	host.shell.update_explore_camera_chrome()
	_snapshot = snapshot
	host.drop_temporary_bulldoze()
	host.cancel_map_gesture()
	host.acquire_sim_process_hold(HOLD)
	host.sync_status_speed()
	host.presentation.set_exploration_suspended(true)
	host.query_panel.close()
	host.sync_query_feedback()
	host.toolbar.hide()
	host.shell.phone_tools_open = false
	host.shell.update_phone_tools()
	host.shell.schedule()
	host.shell.update_minimap_visibility()
	_set_menus_enabled(false)
	return true


## Leave Explore and restore the Build view and tool.
func leave() -> void:
	var host := _host
	if not host.is_exploring(): return
	var snapshot := _snapshot.duplicate(true)
	var view := host.city_view_3d
	var exit_message: String = host.exploration.take_exit_message()
	host.exploration.leave()
	host.release_sim_process_hold(HOLD)
	host.sync_status_speed()
	_snapshot.clear()
	host.shell.phone_tools_open = false
	host.shell.update_phone_tools()
	host.shell.schedule()
	host.shell.update_minimap_visibility()
	host.select_tool(int(snapshot.get("tool",GameHost.NO_TOOL)))
	host.presentation.restore_state(snapshot.get("presentation",{}))
	host.presentation.set_exploration_suspended(false)
	view.set_camera_state(snapshot.get("center",view.center),int(snapshot.get("quarter_turn",0)),float(snapshot.get("camera_size",64.0)))
	_set_menus_enabled(true)
	host.menu_bar.set_checked(&"underground",host.presentation.is_underground())
	host.menu_bar.set_checked(&"overlay",true,host.presentation.get_overlay())
	# Explore ended itself (the route became unsafe or no safe ground remains):
	# tell the player why once Build is restored.
	if not exit_message.is_empty(): host.notices.show("Explore Ended", exit_message)


## Leave Explore if needed and release its actors and world.
func dispose() -> void:
	var pending := _choice_city != null
	_choice_token += 1
	_choice_city = null
	if pending and _host.notice_dialog.is_open() and _host.notice_dialog.title_label.text == "Start Exploring":
		_host.notice_dialog.dismiss(&"cancel")
	# Closing the city discards any pending explanation for the old session.
	if is_instance_valid(_host.exploration): _host.exploration.take_exit_message()
	leave()
	if is_instance_valid(_host.exploration): _host.exploration.dispose()
	_snapshot.clear()
	_host.drop_temporary_bulldoze()


func _set_menus_enabled(on: bool) -> void:
	var menu_bar := _host.menu_bar
	var playing := _host.stage == GameHost.Stage.PLAY
	menu_bar.set_enabled(&"street_names",on and playing)
	menu_bar.set_enabled(&"vegetation",on)
	for action: StringName in [&"zoom_in",&"zoom_out",&"rotate",&"recenter",&"underground"]:
		menu_bar.set_enabled(action,on)
	for level: int in range(5): menu_bar.set_enabled(&"zoom",on,level)
	menu_bar.set_enabled(&"overlay",on,&"")
	for kind: StringName in CityOverlaySampler.LAYERS: menu_bar.set_enabled(&"overlay",on,kind)
	menu_bar.set_enabled(&"explore",on and playing)
