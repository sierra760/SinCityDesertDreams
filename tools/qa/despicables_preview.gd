# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Posed native renderer captures in an isolated project; no player data.
extends SceneTree

var output := ""
const STORE := &"com_corner_store"

func _initialize() -> void:
	output = OS.get_environment("DESPICABLES_EVIDENCE")
	if output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func _capture(label: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("Captured "+label)

func _run() -> void:
	for phone: bool in [false,true]:
		root.size = Vector2i(520,900) if phone else Vector2i(1280,800)
		for kind: StringName in [&"slots",&"video_poker"]:
			var game := ResortThemes.make_game(kind)
			game.begin(CasinoRng.new(7),CasinoParams.table_limits(STORE))
			var stage: CasinoStage = SlotStage.new() if kind == &"slots" else CardStage.new()
			root.add_child(stage)
			stage.size = Vector2(root.size)
			stage.setup(game,STORE,CasinoPalette.for_resort(STORE))
			if stage is CardStage:
				stage.set("_cards",[CasinoDeck.card(11,0),CasinoDeck.card(12,1),CasinoDeck.card(13,2),CasinoDeck.card(1,3),{"rank":0,"suit":0,"face_up":false}])
			stage.queue_redraw()
			await _capture(String(kind)+("-phone" if phone else "-desktop"))
			stage.free()
	root.size = Vector2i(1280,800)
	var world := ResortInteriorWorld3D.new()
	root.add_child(world)
	world.build(STORE,126,Vector2i.ZERO)
	var fill := ResortPropDresser.make_fill()
	root.add_child(fill)
	var camera := Camera3D.new()
	camera.near = .015
	camera.far = 20
	camera.fov = 85
	camera.cull_mask = ResortInteriorWorld3D.LAYER
	root.add_child(camera)
	camera.current = true
	var views := {
		"entrance":[Vector3(0,1.7,4.05),Vector3(0,1.5,-1.7)],
		"store":[Vector3(-.6,1.7,2.5),Vector3(-3.7,1.0,-1.2)],
		"checkout":[Vector3(-.5,1.7,1.3),Vector3(-3.4,1.1,3.4)],
		"machines":[Vector3(1.5,1.7,3.9),Vector3(5.25,1.1,-.7)],
		"cabinet":[Vector3(3.9,1.4,-3.5),Vector3(5.25,1.29,-3.5)],
		"exit":[Vector3(0,1.7,1.5),Vector3(0,1.6,5.0)],
		"cabinet-high":[Vector3(3.9,2.05,-3.5),Vector3(5.25,1.70,-3.5)],
		"painting-west":[Vector3(-2.5,1.7,-.5),Vector3(-5.8,2.08,-2)]}
	for label: String in views:
		camera.position = world.position+views[label][0]/16.0
		camera.look_at(world.position+views[label][1]/16.0,Vector3.UP)
		await _capture(label)
	camera.free()
	fill.free()
	world.free()
	print("DESPICABLES_PREVIEW_COMPLETE: 12 captures")
	quit()
