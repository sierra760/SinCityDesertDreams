# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Real Main/Builder must place roads at physical contacts, without charging
## during preview or allowing UI-owned/cancelled contacts to place anything.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self, "touch-contact-host")
	host.select_tool(Tools.Kind.ROAD)
	await process_frame
	await physics_frame

func after_each() -> void:
	host.free()
	await process_frame

func contact(pressed: bool, cell: Vector2i, cancelled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.canceled = cancelled
	event.position = host.city_view_3d.project_cell(cell) * float(host.display_layout.metrics.scale)
	root.push_input(event,false)

func drag(cell: Vector2i) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = host.city_view_3d.project_cell(cell) * float(host.display_layout.metrics.scale)
	root.push_input(event,false)

func test_main_places_drag_on_contacted_cells_on_phone_and_tablet() -> void:
	var index := 0
	for dimensions: Array in [[Vector2i(1170,2532),3.0],[Vector2i(2532,1170),3.0],[Vector2i(1668,2388),2.0],[Vector2i(2388,1668),2.0]]:
		root.size = dimensions[0]
		for percent: int in [100,150]:
			host.display_layout.ui_scale = percent
			host.display_layout.refresh_with_mobile_metrics(root.size,dimensions[1],Rect2i(Vector2i(0,48),root.size-Vector2i(0,88)))
			var row := 60 + index * 2
			index += 1
			host.city_view_3d.set_camera_state(Vector3(65.5,CityGeometry3D.surface_height(host.sim.city,Vector2i(65,row)),row+.5),index%4,16)
			for frame in 4: await process_frame
			await physics_frame
			for cell: Vector2i in [Vector2i(64,row),Vector2i(66,row),Vector2i(67,row)]:
				check(not host.touch_ui_owned(host.city_view_3d.project_cell(cell)),"fixture contacts are clear of GUI")
			var before := SaveFormat.encode_city(host.sim.city)
			contact(true,Vector2i(64,row))
			drag(Vector2i(66,row))
			check_eq(SaveFormat.encode_city(host.sim.city),before,"press/drag preview cannot change the city")
			contact(false,Vector2i(67,row))
			for x in range(64,68):
				check(Buildings.is_road_like(host.sim.city.building_at(x,row)),"Main builds each contacted road cell")
				check_eq(host.sim.city.building_at(x,row-1),Buildings.NONE,"adjacent uncontacted row stays empty")
			check_eq(host.sim.city.building_at(68,row),Buildings.NONE,"release cannot extend beyond the final contact")

func test_cancelled_contact_keeps_city_unchanged() -> void:
	root.size = Vector2i(2388,1668)
	host.display_layout.refresh_with_mobile_metrics(root.size,2.0,Rect2i(0,48,2388,1580))
	host.city_view_3d.set_camera_state(Vector3(64.5,CityGeometry3D.surface_height(host.sim.city,Vector2i(64,64)),64.5),0,16)
	for frame in 4: await process_frame
	await physics_frame
	var before := SaveFormat.encode_city(host.sim.city)
	contact(true,Vector2i(64,64))
	drag(Vector2i(66,64))
	contact(false,Vector2i(66,64),true)
	contact(false,Vector2i(66,64))
	check_eq(SaveFormat.encode_city(host.sim.city),before,"OS cancellation and trailing release cannot build")
