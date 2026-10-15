# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Exercise the imported resort shells with the real Explore walking capsule.
extends "res://tests/exploration/async_test_case.gd"
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)
const DECK_TOP := .6/16.0
var previous_scale: float

class Driver extends Node:
	signal completed
	var actor: ExplorePedestrian
	var local_from_world: Transform3D
	var yaw := 0.0
	var goal := 0.0
	var reverse := false
	var ticks := 0
	var settling := -1
	var samples: Array[Vector3] = []
	func _physics_process(delta: float) -> void:
		var frame := ExploreInputFrame.idle()
		frame.sprint=true
		if settling<0:frame.move=Vector2(0,1 if reverse else -1)
		actor.step(frame,yaw,delta)
		var feet := local_from_world*actor.global_position
		samples.append(feet);ticks+=1
		if settling<0 and ((feet.z>=goal if reverse else feet.z<=goal) or ticks>=180):
			actor.stop_input();settling=0
		if settling>=0:settling+=1
		if settling>=12:
			set_physics_process(false);completed.emit()

func before_all() -> void:
	previous_scale=Engine.time_scale;Engine.time_scale=4
func after_all() -> void:Engine.time_scale=previous_scale

func setup_case(code: int, direction: Vector2i, sloped: bool) -> Dictionary:
	var city := flat_city()
	var size := Buildings.size(code)
	var front := ANCHOR+(size-Vector2i.ONE) if direction.x>0 or direction.y>0 else ANCHOR
	if sloped:
		for y: int in City.HEIGHT:
			for x: int in City.WIDTH:
				var offset := Vector2i(x,y)-front
				var distance := offset.x*direction.x+offset.y*direction.y
				if distance>=0:city.set_heights(x,y,3,0)
				if distance==0:
					var slope := Terrain.SLOPE_N if direction==Vector2i.DOWN else Terrain.SLOPE_W if direction==Vector2i.RIGHT else Terrain.SLOPE_S if direction==Vector2i.UP else Terrain.SLOPE_E
					city.terrain.put(x,y,slope)
	city.stamp_building(ANCHOR.x,ANCHOR.y,code)
	var road := ANCHOR+Vector2i(size.x>>1,size.y>>1)
	if direction==Vector2i.DOWN:road.y=ANCHOR.y+size.y
	elif direction==Vector2i.RIGHT:road.x=ANCHOR.x+size.x
	elif direction==Vector2i.UP:road.y=ANCHOR.y-1
	else:road.x=ANCHOR.x-1
	city.building.putv(road,Buildings.ROAD_FIRST)
	var view := CityView3D.new();root.add_child(view);view.bind_city(city)
	view.buildings.rebuild(city,view.catalog)
	var traversal := CityTraversalWorld3D.new();view.world.add_child(traversal)
	traversal.rebuild(city,[CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))],{},1)
	await physics_frame;await physics_frame
	var rect := Rect2i(ANCHOR,size)
	var yaw := CityBuildings3D.resort_yaw(city,rect)
	var center := Vector2(ANCHOR)+Vector2(size)*.5
	var pose := Transform3D(Basis(Vector3.UP,yaw),Vector3(center.x,CityBuildings3D.base_height(city,rect,code),center.y))
	return {"city":city,"view":view,"traversal":traversal,"pose":pose,"yaw":yaw}

func test_imported_porch_support_and_threshold_match_visible_top_in_all_orientations() -> void:
	for code: int in [263,264]:
		var edge := 14.75 if code==263 else 22.0
		var inside := 12.9 if code==263 else 20.8
		for direction: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
			for sloped: bool in [false,true]:
				var c: Dictionary = await setup_case(code,direction,sloped)
				var label := "%d %s sloped=%s"%[code,direction,sloped]
				var pose: Transform3D = c.pose
				var exclude: Array[RID]=[]
				for x: float in [-3.0,0.0,3.0]:
					for z: float in [edge-.6,inside]:
						var point := pose*Vector3(x/16,DECK_TOP+.002,z/16)
						var hit: Dictionary = c.traversal.support_near(point,.003,.005,exclude)
						check(not hit.is_empty(),label+": imported deck physically supports visible top")
						if not hit.is_empty():check_between(float(hit.position.y)-pose.origin.y,DECK_TOP-.0001,DECK_TOP+.0001,label+": exact deck height")
				var threshold := Access.threshold(c.city,ANCHOR,code)
				check_between(threshold.origin.y-pose.origin.y,DECK_TOP-.0001,DECK_TOP+.0001,label+": doorway return pose stands on porch")
				c.view.free()

func drive(c: Dictionary, actor: ExplorePedestrian, goal: float, reverse := false) -> Driver:
	var driver := Driver.new();driver.actor=actor;driver.local_from_world=(c.pose as Transform3D).affine_inverse()
	driver.yaw=c.yaw;driver.goal=goal;driver.reverse=reverse
	c.view.world.add_child(driver);await driver.completed;await process_frame
	return driver

func test_real_walker_steps_onto_crosses_and_leaves_both_rotated_porches() -> void:
	for code: int in [263,264]:
		var edge := (14.75 if code==263 else 22.0)/16
		var inside := (12.9 if code==263 else 20.8)/16
		for direction: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
			var c: Dictionary = await setup_case(code,direction,false)
			var actor := ExplorePedestrian.new();c.view.world.add_child(actor);actor.bind(c.traversal)
			var reports: Array[String]=[]
			actor.recovery_requested.connect(func(reason: String) -> void:reports.append(reason))
			actor.place(Transform3D(Basis.IDENTITY,c.pose*Vector3(0,.002,edge+.9/16)))
			await physics_frame;await physics_frame
			var approach := await drive(c,actor,inside)
			var feet: Vector3=(c.pose as Transform3D).affine_inverse()*actor.global_position
			var label := "%d %s"%[code,direction]
			check(feet.z<=inside+.003,label+": reaches door along porch without jumping")
			check_between(feet.y,DECK_TOP-.002,DECK_TOP+.005,label+": feet stand above visible deck")
			var on_deck := 0
			for sample: Vector3 in approach.samples:
				if sample.z<edge-.4/16:
					on_deck+=1
					check(sample.y>=DECK_TOP-.002,label+": never walks through deck")
			check(on_deck>0,label+": traverses deck surface")
			if direction==Vector2i.DOWN:await capture_porch(c,actor,code)
			await drive(c,actor,edge+.9/16,true)
			feet=(c.pose as Transform3D).affine_inverse()*actor.global_position
			check(feet.z>=edge+.8/16,label+": walks back off porch")
			check_between(feet.y,-.002,.005,label+": settles back onto ground")
			check(reports.is_empty(),label+": no unsupported recovery")
			c.view.free();await physics_frame

func capture_porch(c: Dictionary, actor: ExplorePedestrian, code: int) -> void:
	var output := OS.get_environment("PORCH_CAPTURE_DIR")
	if output.is_empty():return
	DirAccess.make_dir_recursive_absolute(output)
	var view: CityView3D=c.view
	view.visible=true
	root.size=Vector2i(1280,800)
	view.viewport.size=Vector2i(1280,800)
	view.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new();view.world.add_child(camera);camera.current=true;camera.near=.005;camera.fov=55
	for angle: int in 2:
		camera.position=actor.global_position+Vector3(3.7 if angle==0 else -3.7,1.3,4.5)/16
		camera.look_at(actor.global_position+Vector3.UP*.055)
		for frame in 8:await process_frame
		RenderingServer.force_draw(false)
		check_eq(view.viewport.get_texture().get_image().save_png(output.path_join("%d-porch-%d.png"%[code,angle])),OK,"native porch capture")
	camera.free()
