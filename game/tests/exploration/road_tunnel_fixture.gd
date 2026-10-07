# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends RefCounted
const TestCase := preload("res://tests/test_case.gd")

static func city(vertical := false, end_height := 4) -> City:
	var result: City = TestCase.flat_city()
	# Broad ridge, rather than a one-cell spike smoothed into its flat neighbors.
	for along: int in range(21,26):
		for across: int in range(16,25):
			var p := Vector2i(across,along) if vertical else Vector2i(along,across)
			result.set_heights(p.x,p.y,8,0)
	for along: int in [17,18,28,29]:
		result.building.putv(Vector2i(20,along) if vertical else Vector2i(along,20),29 if vertical else 30)
	for i: int in range(19,28):
		var cell := Vector2i(20,i) if vertical else Vector2i(i,20)
		if i in [19,27]:
			result.building.putv(cell,29 if vertical else 30)
			result.set_heights(cell.x,cell.y,4 if i==19 else end_height,0)
		else:
			result.set_tunnel_bits(cell.x,cell.y,1 if vertical else 2)
			if i in [20,26]:
				result.set_heights(cell.x,cell.y,4 if i==20 else end_height,0)
				result.building.putv(cell,(66 if i==20 else 64) if vertical else (65 if i==20 else 63))
				result.terrain.putv(cell,(4 if i==20 else 2) if vertical else (3 if i==20 else 1))
			else:
				result.set_heights(cell.x,cell.y,8,0)
	return result
