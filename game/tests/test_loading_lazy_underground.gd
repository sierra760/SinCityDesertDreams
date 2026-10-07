# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
var view: CityView3D
func after_each() -> void:
	if is_instance_valid(view): view.free()
	await process_frame

func test_surface_city_binding_defers_hidden_utility_geometry() -> void:
	var city := flat_city()
	city.underground.put(30,30,35)
	view=CityView3D.new()
	root.add_child(view)
	view.set_active(false)
	var utilities := CityUnderground3D.new()
	view.bind_analytics(null,utilities)
	view.bind_city(city)
	check_eq(utilities.rebuild_count,0,"surface city load does not construct the hidden underground mesh")
	check(utilities.mesh_instance.mesh==null,"hidden binding clears old city geometry")
	var before := SaveFormat.encode_city(city)
	view.set_underground(true)
	check_eq(utilities.rebuild_count,1,"first underground reveal constructs current city geometry")
	check(utilities.mesh_instance.mesh!=null and utilities.mesh_instance.mesh.get_surface_count()>0,"station and utility geometry appears")
	var reference := CityUnderground3D.new()
	reference.bind_city(city)
	check_eq(utilities.mesh_instance.mesh.get_faces(),reference.mesh_instance.mesh.get_faces(),"lazy reveal matches the original eager mesh")
	reference.free()
	view.set_underground(false);view.set_underground(true)
	check_eq(utilities.rebuild_count,1,"unchanged toggles retain the generated mesh")
	view.set_underground(false)
	city.underground.put(31,30,5)
	view.refresh_analytics()
	view.set_underground(true)
	check_eq(utilities.rebuild_count,2,"hidden edits appear on next reveal")
	city.underground.put(31,30,0)
	check_eq(SaveFormat.encode_city(city),before,"presentation never mutates city state")
	view.set_underground(false)
	var other := flat_city()
	view.bind_city(other)
	check(utilities.mesh_instance.mesh==null,"switching cities retires the previous hidden geometry")
	check_eq(utilities.rebuild_count,2,"new surface city binding stays lazy")
	view.set_underground(true)
	check_eq(utilities.rebuild_count,3,"new city gets its own geometry")
