# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Small synthetic cities and a traversal world for the Explore physics tests.
extends RefCounted

const TestCase := preload("res://tests/test_case.gd")

static func bridge_city() -> City:
	var city: City = TestCase.flat_city()
	for x: int in range(20,24):
		city.building.put(x,20,83)
		city.flags.put(x,20,2)
		if x in [21,22]:
			city.terrain.put(x,20,Terrain.SUBMERGED)
			city.set_heights(x,20,2,4)
	return city

static func underpass_city() -> City:
	var city: City = TestCase.flat_city()
	city.building.put(22,20,75)
	return city

static func attach(tree: SceneTree, city: City) -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "TraversalFixture"
	tree.root.add_child(fixture)
	var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	fixture.set_meta("chunks",chunks)
	var networks := CityNetworks3D.new()
	networks.name = "networks"
	fixture.add_child(networks)
	networks.rebuild(city)
	var shells := Node3D.new()
	shells.name = "shells"
	fixture.add_child(shells)
	var traversal := CityTraversalWorld3D.new()
	traversal.name = "traversal"
	fixture.add_child(traversal)
	traversal.rebuild(city,chunks,networks.physical_data(),1)
	return fixture

static func box(parent: Node3D, center: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = center
	return body
