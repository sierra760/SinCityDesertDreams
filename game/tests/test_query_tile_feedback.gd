# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Query feedback uses canonical surfaces without participating in picking.
extends "res://tests/test_case.gd"
const PATH := "res://scripts/view/city_query_feedback_3d.gd"
var drawing: Node3D

func before_each() -> void:
	if not ResourceLoader.exists(PATH):
		check(false,"Query tile feedback exists")
		return
	drawing=load(PATH).new()
	root.add_child(drawing)

func after_each() -> void:
	if drawing!=null: drawing.free()

func test_selection_and_hover_are_distinct_and_never_collide() -> void:
	if drawing==null: return
	var city:=flat_city()
	var before:=SaveFormat.encode_city(city)
	drawing.show_tiles(city,Vector2i(63,64),Vector2i(64,64),0)
	check_eq(drawing.get_child_count(),2,"two independent targets are visible")
	check(drawing.get_node("Selected").get_child_count()>drawing.get_node("Hovered").get_child_count(),"selection adds filled surface as well as outline")
	check_eq(drawing.find_children("*","CollisionObject3D",true,false).size(),0,"feedback cannot alter ray picking")
	check_eq(SaveFormat.encode_city(city),before,"drawing never changes encoded city")
	drawing.show_tiles(city,Vector2i(64,64),Vector2i(64,64),0)
	check_eq(drawing.get_child_count(),1,"same hover/selection does not double its geometry")

func test_outline_follows_canonical_surface_and_rebuilds_on_edit() -> void:
	if drawing==null: return
	var city:=flat_city()
	var cell:=Vector2i(64,64)
	var surface:=TerrainSurface.new(4)
	surface.set_vertex(65,64,5)
	surface.project(city)
	drawing.show_tiles(city,cell,Vector2i(-1,-1),0)
	var node:=drawing.get_node("Hovered")
	var edge:=node.get_child(0) as MeshInstance3D
	var corners:=CityGeometry3D.surface_corners(city,cell)
	check_eq(edge.position,(corners[0]+corners[1])/2.0+Vector3.UP*0.075)
	var previous:=edge.position
	surface.set_vertex(65,64,8)
	drawing.show_tiles(city,cell,Vector2i(-1,-1),1)
	check_ne(drawing.get_node("Hovered").get_child(0).position,previous,"geometry revision refreshes same selected coordinate")

func test_invalid_and_cleared_targets_remove_feedback() -> void:
	if drawing==null: return
	drawing.show_tiles(flat_city(),Vector2i(-1,-1),Vector2i(128,64),0)
	check_eq(drawing.get_child_count(),0)
	drawing.show_tiles(flat_city(),Vector2i(64,64),Vector2i(-1,-1),0)
	drawing.clear()
	check_eq(drawing.get_child_count(),0)
	check_eq(drawing.hovered,Vector2i(-1,-1))
	check_eq(drawing.selected,Vector2i(-1,-1))
