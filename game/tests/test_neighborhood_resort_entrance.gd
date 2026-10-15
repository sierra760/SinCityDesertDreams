# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Real physical shells on small lots, in each street orientation and on slopes.
extends "res://tests/exploration/async_test_case.gd"
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)

func test_small_resort_doors_are_supported_and_clear_in_every_orientation() -> void:
	for code: int in [262,263,264,265]:
		var size := Buildings.size(code)
		for direction: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
			for sloped: bool in [false,true]:
				var city := flat_city()
				var front := ANCHOR+(size-Vector2i.ONE) if direction.x>0 or direction.y>0 else ANCHOR
				if sloped:
					for y: int in City.HEIGHT:
						for x: int in City.WIDTH:
							var offset := Vector2i(x,y)-front
							var delta := offset.x*direction.x+offset.y*direction.y
							if delta>=0:city.set_heights(x,y,3,0)
							if delta==0:
								var slope := Terrain.SLOPE_N if direction==Vector2i.DOWN else Terrain.SLOPE_W if direction==Vector2i.RIGHT else Terrain.SLOPE_S if direction==Vector2i.UP else Terrain.SLOPE_E
								city.terrain.put(x,y,slope)
				city.stamp_building(ANCHOR.x,ANCHOR.y,code)
				var road := ANCHOR+Vector2i(size.x>>1,size.y>>1)
				if direction==Vector2i.DOWN:road.y=ANCHOR.y+size.y
				elif direction==Vector2i.RIGHT:road.x=ANCHOR.x+size.x
				elif direction==Vector2i.UP:road.y=ANCHOR.y-1
				else:road.x=ANCHOR.x-1
				city.building.putv(road,Buildings.ROAD_FIRST)
				var view := CityView3D.new();root.add_child(view);view.bind_city(city);view.buildings.rebuild(city,view.catalog)
				var traversal := CityTraversalWorld3D.new();view.world.add_child(traversal)
				traversal.rebuild(city,[CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))],{},1)
				await physics_frame;await physics_frame
				var pose := Access.threshold(city,ANCHOR,code)
				var label := "%d %s sloped=%s"%[code,direction,sloped]
				var facing := pose.basis*Vector3.FORWARD
				check(facing.is_equal_approx(Vector3(-direction.x,0,-direction.y)),label+": visible front faces street")
				var exclude: Array[RID] = []
				var support := traversal.support_near(pose.origin+Vector3.UP*.002,.01,.02,exclude)
				check(not support.is_empty(),label+": physical support")
				var normal: Vector3 = support.get("normal",Vector3.UP)
				var skin := .003+.018*(1.0/normal.y-1.0)
				var at := Transform3D(Basis.IDENTITY,Vector3(pose.origin.x,float(support.get("position",pose.origin).y)+skin+.0575,pose.origin.z))
				check(traversal.has_clearance(at,ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK),exclude),label+": full walking capsule fits")
				check_eq(Access.nearby(city,pose.origin).get("code",0),code,label+": correct portal")
				check(not traversal.touches_water(pose.origin),label+": dry supported exit")
				view.free()

func test_compact_toolbar_captions_fit_without_changing_tool_names() -> void:
	var font: Font = load("res://assets/fonts/biorhyme/BioRhyme-Medium.ttf")
	for tool: int in [Tools.Kind.ARCOLOGY_BODDY,Tools.Kind.ARCOLOGY_WOOLIER,Tools.Kind.ARCOLOGY_STOCKGROWERS,Tools.Kind.ARCOLOGY_FREMONT]:
		var caption := Toolbar.caption_for(tool)
		for line: String in caption.split("\n"):
			check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=76,"new caption fits compact column")
		check(not Tools.display_name(tool).contains("\n"),"full venue name remains intact")
