# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Wrapped credits need a real width before title sizing on a fresh phone.
extends "res://tests/exploration/async_test_case.gd"
func test_fresh_phone_title_keeps_credits_and_new_city_inside_safe_bounds() -> void:
	for bounds: Rect2 in [Rect2(0,20,320,548),Rect2(0,47,390,763),Rect2(0,0,667,375),Rect2(12,12,616,220)]:
		root.size=Vector2i(bounds.end)
		var title := TitleScreen.new()
		root.add_child(title)
		title.apply_layout(bounds)
		title.open()
		for frame in 8: await process_frame
		check(bounds.grow(.1).encloses(title._panel.get_global_rect()),"title fits from its first layout")
		check(bounds.grow(.1).encloses(title.new_button.get_global_rect()),"New City remains visible")
		check(bounds.grow(.1).encloses(title.license_button.get_global_rect()),"License remains reachable")
		check(title.developer_credit.get_line_count()<=4,"credit text wraps as words")
		title.free()
