# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared city view, HUD and session setup for Explore vehicle tests.
extends "res://tests/exploration/async_test_case.gd"
const TransitFixtures := preload("res://tests/test_explore_transit_network.gd")
class SnapshotView extends CityView3D:
	var sample_chunks: Array[Dictionary] = []
	var sample_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"city":city,"chunks":sample_chunks,"networks":sample_networks,"revision":_geometry_revision}
var view: SnapshotView
var hud: ExploreHUD
var session: CityExplorationController

func _setup(city: City, origin: Vector3 = Vector3(22.5,.5,23.5)) -> bool:
	# Session entry needs pavement; a lone tile supplies no driveable route.
	var has_road := false
	for code: int in city.building.data:
		if NetworkShapes.in_family(code,NetworkShapes.Family.ROAD): has_road = true; break
	if not has_road:
		var at := Vector2i(floori(origin.x),floori(origin.z))
		for offset: Vector2i in [Vector2i.ZERO,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
			var cell := at+offset
			if city.building.atv(cell)==Buildings.NONE and not city.is_water(cell.x,cell.y):
				city.building.putv(cell,30)
				break
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,16))]
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	hud = ExploreHUD.new()
	root.add_child(hud)
	session = CityExplorationController.new()
	root.add_child(session)
	session.bind(view,hud)
	session.input_blocked = func() -> bool: return false
	await physics_frame
	var entered := session.enter(city,origin)
	session.set_physics_process(false)
	check(entered)
	return entered

func after_each() -> void:
	if is_instance_valid(session): session.free()
	if is_instance_valid(view): view.free()
	if is_instance_valid(hud): hud.free()
	session = null
	view = null
	hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame

func _refresh_fixture_geometry() -> void:
	view._geometry_revision += 1
	view.networks.rebuild(view.city)
	view.sample_networks = view.networks.physical_data()
	view.sample_chunks = [CityGeometry3D.build_chunk(view.city,Rect2i(16,16,24,16))]
	session._on_geometry_rebuilt(view._geometry_revision)

