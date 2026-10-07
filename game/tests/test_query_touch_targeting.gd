# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Catch construction's aiming offset or press-time selection leaking into Query.
extends "res://tests/test_case.gd"

class PickView extends CityView3D:
	var pick_shift:=Vector2i.ZERO
	func _ready() -> void: pass
	func bind_city(value: City) -> void: city=value
	func pick_cell(point: Vector2, _purpose: int=0) -> Vector2i:
		if point.y<100: return Vector2i(-1,-1)
		return Vector2i(roundi(point.x/10),roundi(point.y/10))+pick_shift

var owner: CityPresentationController
var view: PickView
var clicks: Array[Vector2i]=[]
var hovers: Array[Vector2i]=[]
var construction_events:=0

func before_each() -> void:
	clicks.clear()
	hovers.clear()
	construction_events=0
	view=PickView.new()
	root.add_child(view)
	owner=CityPresentationController.new()
	owner.view=view
	root.add_child(owner)
	owner.bind_city(flat_city())
	owner.set_touch_ui_ownership_checker(func(point: Vector2): return point.x<200)
	owner.tile_clicked.connect(func(tile: Vector2i,_button: int): clicks.append(tile))
	owner.tile_hovered.connect(func(tile: Vector2i): hovers.append(tile))
	owner.drag_started.connect(func(_a,_b): construction_events+=1)
	owner.drag_ended.connect(func(_a,_b): construction_events+=1)
	owner.select_tool(Tools.Kind.QUERY)

func after_each() -> void:
	owner.free()
	view.free()

func touch(index: int,on: bool,point: Vector2=Vector2(400,448),cancelled: bool=false) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.pressed=on
	event.position=point
	event.canceled=cancelled
	owner._input(event)

func move(index: int,point: Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=index
	event.position=point
	owner._input(event)

func test_query_aims_at_contact_and_waits_for_release() -> void:
	touch(0,true)
	check_eq(hovers.back(),Vector2i(40,45),"Query preview is at finger, not 48 units above")
	check_eq(clicks.size(),0,"press only previews the Query target")
	touch(0,false)
	check_eq(clicks,[Vector2i(40,45)],"clean release selects the previewed tile once")
	check_eq(construction_events,0,"Query never emits construction drag commands")

func test_query_finger_can_adjust_target_before_release() -> void:
	touch(0,true)
	move(0,Vector2(430,458))
	check_eq(hovers.back(),Vector2i(43,46))
	touch(0,false,Vector2(430,458))
	check_eq(clicks,[Vector2i(43,46)],"release selects adjusted tile rather than press tile")

func test_second_finger_cancels_query_without_selecting() -> void:
	touch(0,true)
	touch(1,true,Vector2(600,448))
	touch(1,false,Vector2(600,448))
	touch(0,false)
	check_eq(clicks.size(),0,"navigation takeover cannot open a Query")
	touch(2,true)
	touch(2,false)
	check_eq(clicks,[Vector2i(40,45)],"new Query is allowed after all old fingers lift")

func test_query_cancel_ui_origin_and_invalid_release_cannot_select() -> void:
	touch(0,true)
	touch(0,false,Vector2(400,448),true)
	touch(1,true,Vector2(100,448))
	move(1,Vector2(400,448))
	touch(1,false)
	touch(2,true)
	move(2,Vector2(450,80))
	touch(2,false,Vector2(450,80))
	check_eq(clicks.size(),0,"cancelled, UI-origin and empty-space releases cannot select")

func test_query_and_construction_share_the_contact_target() -> void:
	owner.select_tool(Tools.Kind.ROAD)
	touch(0,true)
	check_eq(hovers.back(),Vector2i(40,45),"construction uses the same contact as Query")
	touch(0,false)
	check_eq(construction_events,2)

func test_pointer_hover_and_query_still_use_actual_pointer() -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=Vector2(400,448)
	owner._unhandled_input(motion)
	check_eq(hovers.back(),Vector2i(40,45))
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_RIGHT
	press.pressed=true
	press.position=motion.position
	owner._unhandled_input(press)
	check_eq(clicks,[Vector2i(40,45)])

func test_pointer_reentering_same_tile_restores_hover() -> void:
	var event:=InputEventMouseMotion.new()
	event.position=Vector2(400,448)
	owner._unhandled_input(event)
	# Main suppressed the outline while GUI owned the pointer, but controller
	# tile history still contains this same tile.
	hovers.clear()
	owner._unhandled_input(event)
	check_eq(hovers,[Vector2i(40,45)] as Array[Vector2i],"same-tile re-entry supplies fresh hover feedback")

func test_camera_change_refreshes_pointer_without_reviving_touch_hover() -> void:
	if not owner.has_method("refresh_query_pointer_hover"):
		check(false,"Query can refresh the actual stationary pointer")
		return
	var event:=InputEventMouseMotion.new()
	event.position=Vector2(400,448)
	owner._unhandled_input(event)
	view.pick_shift=Vector2i(1,0)
	owner.call("refresh_query_pointer_hover")
	check_eq(hovers.back(),Vector2i(41,45),"stationary pointer is re-picked after camera changes")
	touch(0,true)
	touch(0,false)
	hovers.clear()
	owner.call("refresh_query_pointer_hover")
	check(hovers.is_empty(),"touch release cannot revive an old mouse preview")

func test_mouse_query_press_never_claims_a_touch_contact() -> void:
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.position=Vector2(400,448)
	owner._unhandled_input(press)
	check(not owner.has_query_touch(),"a mouse held over GUI cannot bypass pointer ownership as a finger")

func test_stationary_pointer_rebases_when_ui_scale_changes() -> void:
	view.display_layout=DisplayLayout.new()
	view.add_child(view.display_layout)
	view.display_layout.refresh_with_mobile_metrics(Vector2i(1194,834),1,Rect2i())
	var event:=InputEventMouseMotion.new()
	event.position=Vector2(400,448)
	owner._unhandled_input(event)
	view.display_layout.set_ui_scale(125)
	owner.refresh_query_pointer_hover()
	check_eq(hovers.back(),Vector2i(32,36),"same physical pointer is converted to current logical coordinates")
	view.display_layout.refresh_with_mobile_metrics(Vector2i(2388,1668),2,Rect2i())
	owner.refresh_query_pointer_hover()
	check_eq(hovers.back(),Vector2i(32,36),"backing-scale change alone preserves physical point-space location")
