# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_onramp_endpoints_follow_code_and_axis() -> void:
	var pairs: Array = [[Vector2i.RIGHT,Vector2i.UP],[Vector2i.LEFT,Vector2i.UP],[Vector2i.LEFT,Vector2i.DOWN],[Vector2i.RIGHT,Vector2i.DOWN]]
	for code in range(93,97):
		check_eq(NetworkShapes.onramp_endpoints(code,false,0),pairs[code-93])
		var axis_pair: Array = pairs[code-93]
		check_eq(NetworkShapes.onramp_endpoints(code,true,0),[Vector2i(axis_pair[0].y,axis_pair[0].x),Vector2i(axis_pair[1].y,axis_pair[1].x)])
