# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Bakes the cabinet's three full reel drums using the actual table renderer.
## Used by the asset rebuild probe, not an extra viewport in every live hall.
class_name SlotCabinetDisplay
extends SlotStage

func _draw() -> void:
	if palette == null: return
	_xf = Transform2D.IDENTITY
	draw_rect(Rect2(Vector2.ZERO,size),palette.paper)
	var gap := 8.0
	var width := (size.x-gap*4)/3.0
	for reel: int in 3:
		_draw_reel(reel,Rect2(gap+reel*(width+gap),0,width,size.y))
	for reel: int in 3:
		var x := gap+reel*(width+gap)
		draw_line(Vector2(x,size.y*.5),Vector2(x+8,size.y*.5),palette.metal,3,true)
		draw_line(Vector2(x+width-8,size.y*.5),Vector2(x+width,size.y*.5),palette.metal,3,true)
