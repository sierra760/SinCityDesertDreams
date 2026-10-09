# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Help guide names the player's own keys, before and after rebinding.
extends "res://tests/test_case.gd"

class BindingHost extends Control:
	var controls := ControlBindings.new()

var holder: Control

func before_each() -> void:
	holder = Control.new()
	root.add_child(holder)

func after_each() -> void:
	root.remove_child(holder)
	holder.free()

func test_default_guide_names_the_default_keys() -> void:
	var help := HelpWindow.new()
	holder.add_child(help)
	help.open()
	var text := help.guide_text()
	check(not text.contains("{") and not text.contains("}"),"every key placeholder is filled")
	if MobilePlatform.uses_touch(): return
	for phrase: String in ["P pauses","W/A/S/D or the arrow keys","keys 1–5","R rotates","Hold B","Q inspects",
			"Shift sprints","Space jumps or brakes","F enters","Q and E climb","press F to step","press F to sit"]:
		check(text.contains(phrase),"default guide: "+phrase)

func test_rebound_keys_appear_when_help_opens() -> void:
	var host := BindingHost.new()
	holder.add_child(host)
	var help := HelpWindow.new()
	host.add_child(help)
	help.open()
	check_eq(host.controls.assign(&"rotate",0,KEY_T),"","fixture: rotate rebinds to T")
	check_eq(host.controls.assign(&"interact",0,KEY_G),"","fixture: interact rebinds to G")
	check_eq(host.controls.assign(&"pause",0,KEY_K),"","fixture: pause rebinds to K")
	check_eq(host.controls.assign(&"brake",0,KEY_V),"","fixture: brake rebinds to V")
	help.close()
	help.open()
	var text := help.guide_text()
	check(not text.contains("{"),"no placeholder is left")
	if MobilePlatform.uses_touch(): return
	for phrase: String in ["T rotates","G enters and exits vehicles","press G to step","press G to sit","K pauses",
			"Space jumps, V brakes"]:
		check(text.contains(phrase),"rebound guide: "+phrase)
	check(not text.contains("R rotates") and not text.contains("F enters") and not text.contains("press F"),"old keys are gone")

func test_explicit_bindings_take_precedence() -> void:
	var help := HelpWindow.new()
	holder.add_child(help)
	var bindings := ControlBindings.new()
	check_eq(bindings.assign(&"move_forward",0,KEY_I),"")
	check_eq(bindings.assign(&"move_left",0,KEY_J),"")
	check_eq(bindings.assign(&"move_back",0,KEY_K),"")
	check_eq(bindings.assign(&"move_right",0,KEY_L),"")
	help.controls = bindings
	help.open()
	if MobilePlatform.uses_touch(): return
	check(help.guide_text().contains("I/J/K/L or the arrow keys move or steer"),"rebound movement keys are listed")

# Guards against: the Camera row promising a two-finger swipe pans on every
# desktop, when Windows reports a vertical swipe as wheel scrolling (zoom).
func test_camera_swipe_wording_follows_the_operating_system() -> void:
	var bindings := ControlBindings.new()
	var row := ""
	for entry: Array in HelpWindow.ROWS:
		if String(entry[0]) == "Camera": row = String(entry[1])
	check(not row.is_empty(),"the desktop guide has a Camera row")
	var mac := HelpWindow.fill_keys(row,bindings,false,"macOS")
	check(mac.contains("a two-finger trackpad swipe."),"macOS: a two-finger swipe pans: "+mac)
	check(not mac.contains("vertical"),mac)
	var windows := HelpWindow.fill_keys(row,bindings,false,"Windows")
	check(windows.contains("a sideways two-finger touchpad swipe"),"Windows: only a sideways swipe pans: "+windows)
	check(windows.contains("the wheel (or a vertical two-finger touchpad swipe)"),"Windows: a vertical swipe zooms: "+windows)
	check(not windows.contains("two-finger trackpad swipe."),windows)
	for text: String in [mac,windows]:
		check(not text.contains("{") and not text.contains("}"),"no placeholder left: "+text)
