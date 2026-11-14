# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Native views of the Mirage Menagerie (Zoo, 218) through the actual
## CityView3D: aerial, the gate from the street, the promenade, each pen from
## its plaque with its animal moving, a plaque trick and the gate at night.
## Run only in an isolated project copy with private user data:
## ZOO_EVIDENCE=<dir> godot --path <copy> --script res://tools/qa/zoo_preview.gd
extends SceneTree

const CITIES := ["Valle del Mar","La Presa","Foothills Ranch","Oro Canyon","Harbor Palms","Silver Ridge",
	"Juniper Basin","Bonanza Gap","Adaven","Aliso Niguel","Salton Shores","Grant Pass - Soledad"]

var _view: CityView3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_environment("ZOO_EVIDENCE")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,860)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	var city: City = null
	var anchor := Vector2i(-1,-1)
	for name: String in CITIES:
		var loaded := SaveFormat.load("res://assets/cities/%s.sc2d" % name)
		if not bool(loaded.ok): continue
		var found := _find(loaded.city)
		if found.x >= 0:
			city = loaded.city
			anchor = found
			print("ZOO_CITY ",name," ",anchor)
			break
	if city == null: printerr("no city has a zoo"); quit(3); return
	_view = CityView3D.new()
	root.add_child(_view)
	await process_frame
	_view.bind_city(city)
	_view.set_active(true)
	_view.refresh(true)
	var lot: Node3D = null
	for candidate: Node in _view.buildings.get_children():
		if candidate.get_meta("cell",Vector2i(-1,-1)) == anchor and int(candidate.get_meta("code",-1)) == Buildings.ZOO: lot = candidate
	if lot == null: printerr("no zoo lot"); quit(4); return
	var metres: Transform3D = _view.buildings.global_transform*(lot.get_meta("authored_transform") as Transform3D)
	_view.set_camera_state(lot.global_position,2,8.0)
	if not await _capture(_view.camera,output,"aerial-close",1.0): return
	_view.set_camera_state(lot.global_position,0,5.0)
	if not await _capture(_view.camera,output,"aerial-wide",.5): return
	var camera := Camera3D.new()
	camera.fov = 60
	camera.near = .005
	camera.far = 300
	_view.world.add_child(camera)
	_view.set_exploration_camera(camera)
	var poses := {
		"gate-from-street": [Vector3(0,2.0,44.0),Vector3(0,3.2,18.0)],
		"promenade": [Vector3(1.0,1.9,27.0),Vector3(0,1.4,-4.0)],
		"plaza": [Vector3(-3.5,2.0,-8.0),Vector3(8.0,1.0,10.0)],
		"pen-saguaroo": [Vector3(2.6,1.9,13.0),Vector3(17.0,1.0,17.0)],
		"pen-flamingoat": [Vector3(-2.6,1.9,13.0),Vector3(-17.0,1.0,17.0)],
		"pen-tortoise": [Vector3(-2.6,1.9,-12.0),Vector3(-17.0,1.0,-16.0)],
		"pen-tumbleweasel": [Vector3(2.6,1.9,-12.0),Vector3(17.0,.5,-17.0)],
	}
	for name: String in poses:
		camera.global_position = metres*poses[name][0]
		camera.look_at(metres*poses[name][1])
		if not await _capture(camera,output,name,1.5): return
	# Read the Saguaroo's plaque: it leaps.
	var exhibit := _view.zoo.nearest_exhibit(metres*ZooAnimal.plaque_point(Vector2(1,1)))
	print("ZOO_PLAQUE ",exhibit.get("name","")," ",_view.zoo.perform(exhibit))
	camera.global_position = metres*Vector3(2.6,1.9,13.0)
	camera.look_at(metres*Vector3(17.0,1.6,17.0))
	if not await _capture(camera,output,"saguaroo-trick",1.2): return
	_view.set_night_mode(true,true)
	camera.global_position = metres*Vector3(0,2.0,44.0)
	camera.look_at(metres*Vector3(0,3.2,18.0))
	if not await _capture(camera,output,"gate-at-night",1.0): return
	print("ZOO_PREVIEW_CAPTURED on ",RenderingServer.get_current_rendering_method()," animals ",_view.zoo.animals().size())
	quit()

func _find(city: City) -> Vector2i:
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if city.building.at(x,y) == Buildings.ZOO: return Vector2i(x,y)
	return Vector2i(-1,-1)

func _capture(camera: Camera3D, output: String, name: String, seconds: float) -> bool:
	var until := Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec() < until:
		_view.traffic.advance(1.0/30.0,false,[],camera)
		_view.zoo.advance(1.0/30.0,camera,false,camera.global_position)
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name+".png")) != OK:
		quit(1)
		return false
	return true
