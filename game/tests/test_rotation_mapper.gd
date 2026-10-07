# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rotated screen and canonical data coordinates round-trip.
extends "res://tests/test_case.gd"


func test_screen_and_data_coordinates_round_trip() -> void:
	for r: int in 4:
		for tile: Vector2i in [Vector2i(0, 0), Vector2i(127, 0), Vector2i(5, 99), Vector2i(127, 127)]:
			var s := RotationMapper.data_to_screen_i(tile, r)
			check(s.x >= 0 and s.y >= 0 and s.x < 128 and s.y < 128)
			check_eq(RotationMapper.screen_to_data(s.x, s.y, r), tile, "rotation %d" % r)
	check_eq(RotationMapper.screen_to_data(0, 0, 1), Vector2i(127, 0))
	check_eq(RotationMapper.data_to_screen(Vector2(1.5, 2.5), 0), Vector2(1.5, 2.5))


func test_each_quarter_turn_moves_the_origin_to_another_corner() -> void:
	check_eq(RotationMapper.data_to_screen_i(Vector2i(0, 0), 1), Vector2i(0, 127))
	check_eq(RotationMapper.data_to_screen_i(Vector2i(0, 0), 2), Vector2i(127, 127))
	check_eq(RotationMapper.data_to_screen_i(Vector2i(0, 0), 3), Vector2i(127, 0))
	check_eq(RotationMapper.data_to_screen(Vector2(1.25, 2.75), 2), Vector2(125.75, 124.25))
