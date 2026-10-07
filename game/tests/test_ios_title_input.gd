# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 8: await process_frame

func touch(point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	# Physical input is localized by the window; gesture replay is already
	# viewport-local. Exercise both sides of that boundary at nonunit scale.
	root.push_input(event,false)

func fixture(dimensions: Vector2i, scale_value: float) -> TitleScreen:
	root.size = dimensions
	root.content_scale_factor = scale_value
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	title.apply_layout(Rect2(Vector2.ZERO,Vector2(dimensions)/scale_value))
	# Exercise the iOS helper on desktop/headless without changing OS policy.
	IOSGestureScroll._install(title._actions_scroll)
	return title

func after_each() -> void:
	root.content_scale_factor = 1.0

func test_completed_title_taps_reach_each_action_at_backing_and_ui_scales() -> void:
	for scale_value: float in [1.0,2.0,2.5,3.0]:
		var title := fixture(Vector2i(2388,1668),scale_value)
		var actions: Array[String] = []
		title.new_city_requested.connect(func(): actions.append("new"))
		title.load_requested.connect(func(): actions.append("load"))
		title.import_requested.connect(func(): actions.append("import"))
		title.settings_requested.connect(func(): actions.append("settings"))
		await settle()
		for button: Button in [title.new_button,title.load_button,title.import_button,title.settings_button]:
			var count := actions.size()
			var point := button.get_global_rect().get_center()*scale_value
			touch(point,true)
			check_eq(actions.size(),count,"touch down defers "+button.text)
			touch(point,false)
			await settle()
			check_eq(actions.size(),count+1,"one completed tap activates "+button.text+" at scale "+str(scale_value))
		check_eq(actions,["new","load","import","settings"],"native action order and identity")
		title.free()

func test_swipes_canceled_touches_and_disabled_actions_do_not_activate() -> void:
	var title := fixture(Vector2i(780,440),2.0)
	var actions: Array[int] = []
	title.new_city_requested.connect(func(): actions.append(1))
	await settle()
	var point := title.new_button.get_global_rect().get_center()*2.0
	touch(point,true)
	touch(point,false,true)
	await settle()
	check(actions.is_empty(),"canceled contact does not activate")
	title.new_button.disabled = true
	touch(point,true)
	touch(point,false)
	await settle()
	check(actions.is_empty(),"disabled action retains native guard")
	title.new_button.disabled = false
	touch(point,true)
	var drag := InputEventScreenDrag.new()
	drag.position = point-Vector2(0,24)
	drag.relative = Vector2(0,-24)
	root.push_input(drag,false)
	touch(point-Vector2(0,24),false)
	await settle()
	check(actions.is_empty(),"swipe across an action never becomes a click")
	title.free()

func _owners_of(control: Control) -> Array[Object]:
	var out: Array[Object] = []
	for connection: Dictionary in control.gui_input.get_connections():
		var target: Object = (connection.callable as Callable).get_object()
		if target is IOSGestureScroll: out.append(target)
	return out

func test_late_children_bind_to_their_innermost_gesture_scroll() -> void:
	root.size = Vector2i(800,600)
	var outer := ScrollContainer.new()
	outer.size = Vector2(400,300)
	root.add_child(outer)
	var body := VBoxContainer.new()
	outer.add_child(body)
	IOSGestureScroll._install(outer)
	var outer_owner := outer.get_node("IOSGestureScroll") as IOSGestureScroll
	var inner := ScrollContainer.new()
	body.add_child(inner)
	IOSGestureScroll._install(inner)
	var inner_owner := inner.get_node("IOSGestureScroll") as IOSGestureScroll
	var plain := ScrollContainer.new()
	body.add_child(plain)
	await settle()
	var late := Button.new()
	body.add_child(late)
	var nested := Button.new()
	var inner_body := VBoxContainer.new()
	inner.add_child(inner_body)
	inner_body.add_child(nested)
	var unowned := Button.new()
	plain.add_child(unowned)
	var field := LineEdit.new()
	body.add_child(field)
	var outside := Button.new()
	root.add_child(outside)
	await settle()
	check_eq(_owners_of(late), [outer_owner] as Array[Object], "late child joins its scroll's gesture")
	check_eq(_owners_of(nested), [inner_owner] as Array[Object], "inner scroll keeps its own contents")
	check(_owners_of(unowned).is_empty(), "an inner scroll without a gesture is not claimed by the outer one")
	check(_owners_of(field).is_empty(), "editable fields keep native input")
	check(_owners_of(outside).is_empty(), "nodes outside every scroll are ignored")
	outer.free()
	outside.free()
