# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Switching between Build and Explore. Entering Explore remembers the Build
## camera, tool and map presentation and hides the Build chrome; returning
## restores them.
class_name ExploreModeSwitch
extends RefCounted

var _host: GameHost
## The Build camera, tool and presentation saved on entering Explore.
var _snapshot: Dictionary = {}


func _init(host: GameHost) -> void:
	_host = host


## Whether Explore can start: a founded city with nothing else holding input.
func can_enter() -> bool:
	var host := _host
	return host.stage == GameHost.Stage.PLAY and not host.is_input_blocked() and not host.is_exploring() \
		and not host.street_names.is_active() and is_instance_valid(host.exploration)


## Enter Explore now. Returns false when it cannot start.
func enter() -> bool:
	if not can_enter():
		return false
	return _enter()


## Enter Explore behind the loading screen.
func request() -> void:
	if not can_enter(): return
	_host.run_loading("Preparing Explore…","Preparing walking paths, vehicles and station interiors.",_enter)


func _enter() -> bool:
	var host := _host
	var view := host.city_view_3d
	var snapshot := {"center":view.center,"quarter_turn":view.quarter_turn,
		"camera_size":view.camera_size,"tool":host.chosen_tool(),
		"presentation":host.presentation.capture_state()}
	# Notices and dialogs suspend Explore and resume it once closed; an open
	# Build window keeps it paused until the window is closed.
	host.exploration.modal_open = host.is_input_blocked
	host.exploration.window_open = func() -> bool:
		return is_instance_valid(host.window_manager) and host.window_manager.front() != null
	if not host.exploration.enter(host.sim.city,view.center):
		host.notices.show("Cannot Enter Explore Mode", "Explore mode requires a safe outdoor road. Build a road with clear space and try again.")
		return false
	host.shell.update_explore_camera_chrome()
	_snapshot = snapshot
	host.drop_temporary_bulldoze()
	host.cancel_map_gesture()
	host.presentation.set_exploration_suspended(true)
	host.query_panel.close()
	host.sync_query_feedback()
	host.toolbar.hide()
	host.shell.phone_tools_open = false
	host.shell.update_phone_tools()
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
	_snapshot.clear()
	host.shell.phone_tools_open = false
	host.shell.update_phone_tools()
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
	for action: StringName in [&"zoom_in",&"zoom_out",&"rotate",&"recenter",&"underground"]:
		menu_bar.set_enabled(action,on)
	for level: int in range(5): menu_bar.set_enabled(&"zoom",on,level)
	menu_bar.set_enabled(&"overlay",on,&"")
	for kind: StringName in CityOverlaySampler.LAYERS: menu_bar.set_enabled(&"overlay",on,kind)
	menu_bar.set_enabled(&"explore",on and playing)
