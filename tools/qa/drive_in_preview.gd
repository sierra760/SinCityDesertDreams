# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Native night views of a drive-in theater through the actual CityView3D: the
## film on the screen, the parked cars and the seated audience, with
## two captures a few seconds apart to show the picture moving. Run only in an
## isolated project copy with private user data:
## DRIVE_IN_EVIDENCE=<dir> godot --path <copy> --script res://tools/qa/drive_in_preview.gd
extends SceneTree

const CITIES := ["La Presa","Valle del Mar","Foothills Ranch","Oro Canyon","Harbor Palms","Silver Ridge",
	"Juniper Basin","Bonanza Gap","Adaven","Aliso Niguel","Salton Shores","Grant Pass - Soledad"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_environment("DRIVE_IN_EVIDENCE")
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
			print("DRIVE_IN_CITY ",name," ",anchor)
			break
	if city == null: printerr("no city has a drive-in"); quit(3); return
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true,true)
	var show: DriveInNightShow = view.night.drive_ins
	var lot: Node3D = null
	for candidate: Node in view.buildings.get_children():
		if candidate.get_meta("cell",Vector2i(-1,-1)) == anchor and int(candidate.get_meta("code",-1)) == DriveInNightShow.code(): lot = candidate
	if show == null or lot == null: printerr("no show"); quit(4); return
	print("DRIVE_IN_SCREENS ",show.screen_count()," CARS ",show.parked_slots().size()," AUDIENCE ",show.audience_count())
	var centre := lot.global_position
	view.set_camera_state(centre,2,8.0)
	if not await _capture(view,view.camera,output,"aerial-close",1.0): return
	var camera := Camera3D.new()
	camera.fov = 58
	camera.near = .01
	camera.far = 300
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	var frame := lot.global_transform
	var poses := {
		"rows-toward-screen": [frame*Vector3(0,.32,1.25),frame*Vector3(0,.8,-1.0)],
		"rows-oblique": [frame*Vector3(1.3,.45,1.4),frame*Vector3(-.2,.35,-.4)],
		"from-the-street": [frame*Vector3(.6,.18,2.2),frame*Vector3(0,.5,-.9)],
		"chairs-close": [frame*Vector3(.42,.09,.62),frame*Vector3(.6,.05,-.3)],
		"audience-side": [frame*Vector3(-.15,.1,-.42),frame*Vector3(-.65,.04,-.1)],
	}
	for name: String in poses:
		camera.position = poses[name][0]
		camera.look_at(poses[name][1])
		if not await _capture(view,camera,output,name,0.5): return
	# The same view a few seconds later: the picture has moved on.
	camera.position = poses["rows-toward-screen"][0]
	camera.look_at(poses["rows-toward-screen"][1])
	if not await _capture(view,camera,output,"rows-toward-screen-later",4.0): return
	print("DRIVE_IN_PREVIEW_CAPTURED on ",RenderingServer.get_current_rendering_method()," playing ",show.is_playing())
	quit()

func _find(city: City) -> Vector2i:
	var code := DriveInNightShow.code()
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if city.building.at(x,y) == code: return Vector2i(x,y)
	return Vector2i(-1,-1)

func _capture(view: CityView3D, camera: Camera3D, output: String, name: String, seconds: float) -> bool:
	var until := Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec() < until:
		view.traffic.advance(1.0/30.0,false,[],camera)
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(name+".png")) != OK:
		quit(1)
		return false
	return true
