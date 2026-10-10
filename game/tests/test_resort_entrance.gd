# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Gaming resort front doors: thresholds on flat and sloped lots stand on
## outdoor ground clear of the building and face it; only walkers near a
## resort's front are offered the door.
extends "res://tests/exploration/async_test_case.gd"

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)
const CODES := [Buildings.ARCOLOGY_COMSTOCK,Buildings.ARCOLOGY_JUNCTION,Buildings.ARCOLOGY_BOULDER,Buildings.ARCOLOGY_ORBIT,256,257,258,259,260,261]
const NAMES := ["Comstock Grand","Silver Junction","Boulder Crown","Desert Orbit","The Fix","Six-Week Alibi","Velvet Wardrobe","The Afterglow","Last Resort","Dust Republic"]

func _city(code: int, sloped: bool) -> City:
	var city := flat_city()
	if sloped:
		# The lot's front row falls one level toward the street.
		for y: int in range(ANCHOR.y+3,City.HEIGHT):
			for x: int in City.WIDTH: city.set_heights(x,y,3,0)
		for x: int in range(ANCHOR.x-2,ANCHOR.x+6): city.terrain.put(x,ANCHOR.y+3,Terrain.SLOPE_N)
	city.stamp_building(ANCHOR.x,ANCHOR.y,code)
	return city

## A view with this city's terrain and building shells plus a physical world.
func _world(city: City) -> Dictionary:
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.buildings.rebuild(city,view.catalog)
	var traversal := CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	var networks: Dictionary = {}
	traversal.rebuild(city,[CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))],networks,1)
	await physics_frame
	await physics_frame
	return {"view": view, "traversal": traversal}

func test_threshold_stands_outdoors_supported_clear_and_faces_the_door() -> void:
	for sloped: bool in [false,true]:
		for index: int in CODES.size():
			var code: int = CODES[index]
			var city := _city(code,sloped)
			var setup: Dictionary = await _world(city)
			var traversal: CityTraversalWorld3D = setup.traversal
			var pose := Access.threshold(city,ANCHOR)
			var label := "%d %s" % [code,"sloped" if sloped else "flat"]
			check_eq(pose.origin.x,ANCHOR.x+2.0,label+": front centre")
			check_between(pose.origin.z,ANCHOR.y+3.7,ANCHOR.y+3.9,label+": front edge of the lot")
			check((pose.basis*Vector3.FORWARD).is_equal_approx(Vector3(0,0,-1)),label+": faces into the building")
			var exclude: Array[RID] = []
			var support := traversal.support_near(pose.origin+Vector3.UP*.002,.01,.02,exclude)
			check(not support.is_empty(),label+": threshold is supported")
			check(not traversal.touches_water(pose.origin),label+": threshold is dry")
			check(not traversal.inside_road_tunnel(pose.origin),label+": threshold is outdoors")
			var shape := ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK)
			var normal: Vector3 = support.get("normal",Vector3.UP)
			var skin := .003+.018*(1.0/normal.y-1.0)
			var at := Transform3D(Basis.IDENTITY,Vector3(pose.origin.x,float(support.get("position",pose.origin).y)+skin+.0575,pose.origin.z))
			check(traversal.has_clearance(at,shape,exclude),label+": walker fits at the threshold beside the building")
			var found := Access.nearby(city,pose.origin+Vector3(.2,.002,.1))
			check_eq(found.get("code",0),code,label+": nearby finds the resort")
			check_eq(found.get("anchor",Vector2i(-1,-1)),ANCHOR,label+": nearby names the anchor")
			check_eq(ResortInteriorLayouts.theme(found.get("key",&"")).get("name",""),NAMES[index],label+": theme name")
			check(Access.nearby(city,pose.origin+Vector3(0,0,.9)).is_empty(),label+": beyond reach has no door")
			check(Access.nearby(city,pose.origin+Vector3(0,-2.6,0)).is_empty(),label+": a hall far below is not the street door")
			(setup.view as Node).free()

func test_not_a_resort_has_no_door() -> void:
	var city := flat_city()
	city.stamp_building(ANCHOR.x,ANCHOR.y,Buildings.MARINA)
	check(Access.nearby(city,Vector3(ANCHOR.x+2,4*CityGeometry3D.HEIGHT,ANCHOR.y+3.75)).is_empty(),"other buildings have no resort door")
	check(Access.nearby(flat_city(),Vector3(20.5,2.4,20.5)).is_empty(),"empty ground has no resort door")
	check(Access.nearby(null,Vector3.ZERO).is_empty())
	check(Access.nearby(city,Vector3(INF,0,0)).is_empty())

func test_no_door_prompt_from_car_or_helicopter() -> void:
	var city := flat_city()
	city.stamp_building(ANCHOR.x,ANCHOR.y,Buildings.ARCOLOGY_JUNCTION)
	city.building.putv(Vector2i(22,24),30)
	city.building.putv(Vector2i(23,24),30)
	var view := _SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	var hud := ExploreHUD.new()
	root.add_child(hud)
	var session := CityExplorationController.new()
	root.add_child(session)
	session.bind(view,hud)
	session.input_blocked = func() -> bool: return false
	await physics_frame
	check(session.enter(city,Vector3(22.5,4*CityGeometry3D.HEIGHT,24.5)),"session starts")
	var threshold := Access.threshold(city,ANCHOR)
	var prompts: Array[String] = []
	session.status_changed.connect(func(status: Dictionary) -> void: prompts.append(String(status.prompt)))
	for actor: CharacterBody3D in [session.car,session.helicopter]:
		if not is_instance_valid(actor): continue
		session._occupy(actor)
		actor.global_position = threshold.origin+Vector3.UP*.01
		prompts.clear()
		session._publish_status()
		check(not prompts.is_empty() and not prompts[-1].contains("Silver Junction"),"vehicle at the door is not offered the resort")
		var before := session.resort_service.is_inside()
		check(not before,"not inside")
	session.free()
	view.free()
	hud.free()

class _SnapshotView extends CityView3D:
	var sample_chunks: Array[Dictionary] = []
	var sample_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"city":city,"chunks":sample_chunks,"networks":sample_networks,"revision":1}
