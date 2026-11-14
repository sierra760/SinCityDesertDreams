# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pose every street-crowd figure sitting and save them, with distance LODs,
## for the drive-in audience. Posing in the game would read each figure's mesh
## back from the renderer, which stalls a frame; loading this file does not.
## Run after changing a crowd figure or DriveInNightShow.seated_mesh():
## godot --headless --path game --script res://tools/bake_drive_in_audience.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var host := Node.new()
	root.add_child(host)
	var library := MeshLibrary.new()
	for figure: int in CityTrafficCatalog.pedestrian_variants():
		var mesh := DriveInNightShow.seated_mesh(figure,host)
		if mesh == null:
			printerr("figure %d could not be posed" % figure)
			quit(1)
			return
		library.create_item(figure)
		library.set_item_name(figure,"Moviegoer %d" % figure)
		library.set_item_mesh(figure,mesh)
	var error := ResourceSaver.save(library,DriveInNightShow.AUDIENCE_LIBRARY,ResourceSaver.FLAG_COMPRESS)
	print("saved %d seated figures to %s (%s)" % [CityTrafficCatalog.pedestrian_variants(),DriveInNightShow.AUDIENCE_LIBRARY,error_string(error)])
	quit(0 if error == OK else 1)
