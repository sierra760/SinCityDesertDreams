# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Run on an imported, caller-owned isolated game copy with a real renderer.
## CASINO_ART_EVIDENCE is an absolute output directory. Posed presentation
## fixtures only; no city, treasury, player saves or preferences are loaded.
extends SceneTree

var output := ""

class CardFlipProbe extends CasinoStage:
	func design_size(_tall_layout: bool) -> Vector2:
		return Vector2(1200,520)
	func _draw_stage() -> void:
		for back: bool in [false,true]:
			for index: int in 5:
				var turn: float = [1.0,.5,.25,.02,.75][index]
				var rect := Rect2(80+index*220,50 if not back else 290,112,160)
				_draw_card(rect,{"rank":11,"suit":2,"face_up":not back},turn)
				_text(rect.get_center()+Vector2(0,108),str(turn),18,palette.paper)

class SuitShapeProbe extends CasinoStage:
	func design_size(_tall_layout: bool) -> Vector2:
		return Vector2(900,420)
	func _draw_stage() -> void:
		for suit: int in 4:
			var x := 165+suit*190
			_draw_card(Rect2(x-56,90,112,160),CasinoDeck.card(suit+1,suit))
			for index: int in 3:
				var radius: float = [7.0,12.0,22.0][index]
				_draw_suit(Vector2(x+(index-1)*48,320),radius,suit,palette.paper)

func _initialize() -> void:
	output = OS.get_environment("CASINO_ART_EVIDENCE")
	if output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func _capture(name: String) -> void:
	for index: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(name+".png"))
	if error != OK:
		push_error("Capture failed: "+name)
	print("Captured "+name)

func _run() -> void:
	for key: StringName in ResortThemes.keys():
		var stem := String(ResortArtwork.SETS[key])
		for phone: bool in [false,true]:
			root.size = Vector2i(520,900) if phone else Vector2i(1280,800)
			for kind: StringName in [&"slots",&"video_poker",&"blackjack",&"baccarat",&"faro"]:
				var game := ResortThemes.make_game(kind)
				game.begin(CasinoRng.new(),{"minimum":100,"maximum":1000})
				var stage: CasinoStage = SlotStage.new() if kind == &"slots" else (FaroStage.new() if kind == &"faro" else CardStage.new())
				root.add_child(stage)
				stage.size = Vector2(root.size)
				stage.setup(game,key,CasinoPalette.for_resort(key))
				if stage is CardStage:
					stage.set("_cards",[CasinoDeck.card(11,0),CasinoDeck.card(12,1),CasinoDeck.card(13,2),CasinoDeck.card(1,3),{"rank":0,"suit":0,"face_up":false}])
					stage.set("_dealer",[CasinoDeck.card(13,0),{"rank":0,"suit":0,"face_up":false}])
					stage.set("_hands",[{"cards":[CasinoDeck.card(11,2),CasinoDeck.card(12,3)],"result":"","doubled":false}])
					stage.set("_player",[CasinoDeck.card(12,1),CasinoDeck.card(3,0)])
					stage.set("_banker",[CasinoDeck.card(11,3),CasinoDeck.card(13,2)])
				if stage is FaroStage:
					stage.set("_banker",CasinoDeck.card(13,0))
					stage.set("_player",CasinoDeck.card(12,2))
				stage.queue_redraw()
				await _capture(stem+"-"+String(kind)+("-phone" if phone else "-desktop"))
				stage.free()
		root.size = Vector2i(1280,800)
		var flips := CardFlipProbe.new()
		root.add_child(flips)
		flips.size = Vector2(root.size)
		var cards := BlackjackGame.new()
		cards.begin(CasinoRng.new(),{"minimum":100,"maximum":1000})
		flips.setup(cards,key,CasinoPalette.for_resort(key))
		await _capture(stem+"-card-flips")
		flips.free()
		var suits := SuitShapeProbe.new()
		root.add_child(suits)
		suits.size = Vector2(root.size)
		suits.setup(cards,key,CasinoPalette.for_resort(key))
		await _capture(stem+"-suits")
		suits.free()
		var world := ResortInteriorWorld3D.new()
		root.add_child(world)
		world.build(key,ResortThemes.building(key),Vector2i.ZERO)
		var fill := ResortPropDresser.make_fill()
		root.add_child(fill)
		var camera := Camera3D.new()
		camera.near = .015
		camera.far = 20
		camera.fov = 85
		camera.cull_mask = ResortInteriorWorld3D.LAYER
		root.add_child(camera)
		camera.current = true
		camera.position = world.position+Vector3(0,.28,-.65)
		camera.look_at(world.position+Vector3(0,.40,1.30),Vector3.UP)
		await _capture(stem+"-gallery")
		camera.position = world.position+Vector3(-.4,.31,-.85)
		camera.look_at(world.position+Vector3(-1.32,.40,-.75),Vector3.UP)
		await _capture(stem+"-exhibit")
		camera.position = world.position+Vector3(-.94,.40625,-.75)
		camera.look_at(world.position+Vector3(-1.313,.40625,-.75),Vector3.UP)
		camera.fov = 55
		await _capture(stem+"-painting")
		camera.position = world.position+Vector3(0,.3875,.85)
		camera.look_at(world.position+Vector3(0,.3875,1.374),Vector3.UP)
		camera.fov = 70
		await _capture(stem+"-sign")
		for side: int in [-1,1]:
			camera.position = world.position+Vector3(side*.9375,.4125,.97)
			camera.look_at(world.position+Vector3(side*.9375,.4125,1.325),Vector3.UP)
			camera.fov = 55
			await _capture(stem+("-history" if side < 0 else "-industry"))
		camera.position = world.position+Vector3(-.74,.092,-.31)
		camera.look_at(world.position+Vector3(-.853,.080,-.31),Vector3.UP)
		camera.fov = 60
		await _capture(stem+"-cabinet")
		camera.free()
		fill.free()
		world.free()
	print("CASINO_ART_PREVIEW_COMPLETE: 76 captures")
	quit()
