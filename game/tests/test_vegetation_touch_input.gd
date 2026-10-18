# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

var scroll: ScrollContainer
var chart: VegetationHistogram

func before_each() -> void:
	root.size = Vector2i(800,600)
	scroll = ScrollContainer.new()
	scroll.size = Vector2(400,250)
	root.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	chart = VegetationHistogram.new()
	column.add_child(chart)
	var filler := Control.new()
	filler.custom_minimum_size.y = 600
	column.add_child(filler)
	var bins := PackedInt32Array()
	bins.resize(32)
	bins.fill(1)
	chart.set_data(bins,bins,VegetationZones.make([true,true,true],[10,22]))
	chart.cutoff_changed.connect(func(index: int, level: int) -> void:
		chart.set_settings(VegetationZones.with_cutoff(chart.settings,index,level)))
	IOSGestureScroll._install(scroll)
	for frame in 8: await process_frame

func after_each() -> void:
	scroll.free()
	await process_frame

func touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	root.push_input(event,true)

func test_touch_drag_moves_boundary_without_scrolling_its_window() -> void:
	var start := chart.get_global_position()+Vector2(chart.level_x(10),130)
	var finish := chart.get_global_position()+Vector2(chart.level_x(15),80)
	touch(start,true)
	var drag := InputEventScreenDrag.new()
	drag.position = finish
	drag.relative = finish-start
	root.push_input(drag,true)
	check_eq(scroll.scroll_vertical,0,"the elevation chart owns this drag")
	check_eq(int(chart.settings.cutoffs[0]),15,"the same contact moves the palm boundary")
	touch(finish,false)
	for frame in 4: await process_frame
	check(not chart.is_dragging(),"lifting the finger ends the chart drag")

func test_engine_emulated_mouse_and_touch_keep_one_chart_gesture() -> void:
	var before := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	var start := chart.get_global_position()+Vector2(chart.level_x(10),130)
	var finish := chart.get_global_position()+Vector2(chart.level_x(15),80)
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = start
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var drag := InputEventScreenDrag.new()
	drag.position = finish
	drag.relative = finish-start
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	var release := press.duplicate() as InputEventScreenTouch
	release.pressed = false
	release.position = finish
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	for frame in 4: await process_frame
	Input.emulate_mouse_from_touch = before
	check_eq(scroll.scroll_vertical,0,"emulated mouse and raw touch leave the body in place")
	check_eq(int(chart.settings.cutoffs[0]),15,"the actual engine contact moves the boundary")
	check(not chart.is_dragging(),"the engine release ends the drag")

func test_swiping_the_surrounding_body_still_scrolls() -> void:
	var start := Vector2(100,225)
	touch(start,true)
	var drag := InputEventScreenDrag.new()
	drag.position = start-Vector2(0,50)
	drag.relative = Vector2(0,-50)
	root.push_input(drag,true)
	touch(drag.position,false)
	check_eq(scroll.scroll_vertical,50,"body content keeps swipe scrolling")
	check_eq(int(chart.settings.cutoffs[0]),10,"body swipe does not edit a boundary")
