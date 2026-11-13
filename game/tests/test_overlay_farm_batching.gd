# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Lots, farms and networks built while the underground view or a data overlay
## hides the surface are batched exactly as when the surface is showing: after
## the overlay is left nothing stays behind as separate meshes.
extends "res://tests/exploration/async_test_case.gd"

const CITY := "res://assets/cities/Juniper Basin.sc2d"


static func _visible_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).visible and (node as MeshInstance3D).mesh != null: count += 1
	for child: Node in node.get_children(): count += _visible_meshes(child)
	return count


static func _summary(view: CityView3D) -> Dictionary:
	return {"batched": int(view.mesh_batches.statistics.batched_instances), "batches": view.mesh_batches.get_child_count(),
		"buildings": _visible_meshes(view.buildings), "agriculture": _visible_meshes(view.agriculture), "networks": _visible_meshes(view.networks)}


func _view() -> CityView3D:
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_analytics(CityOverlay3D.new(), CityUnderground3D.new())
	view.set_active(true)
	return view


func test_surface_built_under_an_overlay_is_batched() -> void:
	var city: City = SaveFormat.load(CITY).city
	var view := _view()
	view.bind_city(city)
	var surface := _summary(view)
	check(int(surface.batched) > 1000 and int(surface.agriculture) > 0, "the city has batched lots and farm meshes")
	var everywhere: Array[Rect2i] = [Rect2i(0, 0, City.WIDTH, City.HEIGHT)]
	# A farm change while the surface is hidden rebatches hidden meshes.
	view.set_underground(true)
	view._agriculture_changed(everywhere)
	view.set_underground(false)
	check_eq(_summary(view), surface, "a farm change under the underground view keeps every batch")
	view.set_overlay(&"pollution")
	view._agriculture_changed(everywhere)
	view.refresh(true)
	view.set_overlay(&"none")
	check_eq(_summary(view), surface, "a complete refresh under a data overlay keeps every batch")
	view.free()
	await process_frame
	# The whole city built while the surface is hidden.
	for underground: bool in [true, false]:
		view = _view()
		if underground: view.set_underground(true)
		else: view.set_overlay(&"pollution")
		view.bind_city(city)
		check(not view.agriculture.visible and not view.buildings.visible and not view.networks.visible, "the surface is hidden while the %s shows" % ("underground view" if underground else "overlay"))
		if underground: view.set_underground(false)
		else: view.set_overlay(&"none")
		check_eq(_summary(view), surface, "a city loaded under the %s is batched like one loaded on the surface" % ("underground view" if underground else "overlay"))
		view.free()
		await process_frame
