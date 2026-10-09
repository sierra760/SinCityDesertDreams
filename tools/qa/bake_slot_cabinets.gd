# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Render reusable static cabinet faces from the actual table reel renderer.
## SLOT_CABINET_OUTPUT names a caller-owned destination; isolated project only.
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_environment("SLOT_CABINET_OUTPUT")
	if output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var venues := ResortThemes.keys()
	var requested := OS.get_environment("SLOT_CABINET_VENUE")
	if not requested.is_empty():
		if not ResortThemes.has(StringName(requested)):
			quit(2)
			return
		venues.assign([StringName(requested)])
	for key: StringName in venues:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(480,280)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		root.add_child(viewport)
		var stage := SlotCabinetDisplay.new()
		viewport.add_child(stage)
		stage.size = Vector2(viewport.size)
		var game := SlotsGame.new()
		game.begin(CasinoRng.new(),{"minimum":100,"maximum":1000})
		stage.setup(game,key,CasinoPalette.for_resort(key))
		for index: int in 5: await process_frame
		await RenderingServer.frame_post_draw
		var folder := output.path_join(String(ResortArtwork.SETS[key]))
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("cabinet-reels.png")
		var error := viewport.get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Could not save cabinet face")
			quit(1)
			return
		viewport.free()
	print("SLOT_CABINETS_BAKED: %d full three-reel faces" % venues.size())
	quit()
