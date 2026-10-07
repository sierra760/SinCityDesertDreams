# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 6: await process_frame

func actions(title: TitleScreen) -> Array[Button]:
	return [title.new_button, title.load_button, title.import_button, title.settings_button, title.quit_button]

func test_title_actions_fit_and_keep_focus_across_display_sizes() -> void:
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(640,400),Vector2i(1000,640),Vector2i(640,900)]:
		root.size = dimensions
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		title.apply_layout(bounds)
		await settle()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), "title frame fits " + str(dimensions))
		for button: Button in actions(title):
			button.grab_focus()
			await settle()
			check(button.has_focus(), "original action retains focus")
			check(bounds.encloses(button.get_global_rect()), "action reachable after display reflow: " + button.text)
			check(title._actions_scroll.get_global_rect().encloses(button.get_global_rect()), "focused action clears the scroll clip")
			check(button.size.x >= 44 and button.size.y >= 44, "action target retained")
	title.free()

func test_actions_fill_the_available_column_when_artwork_is_hidden() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(not title._poster.visible,"restricted layout concentrates on actions")
		check(absf(title._actions_scroll.size.x - title._content.size.x) <= 1.0,"actions use the complete restricted column width")
	title.free()

func test_title_respects_narrow_safe_areas_and_keyboard() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), "title frame stays in usable area: " + str(bounds))
		for button: Button in actions(title):
			button.grab_focus()
			await settle()
			check(bounds.encloses(button.get_global_rect()), "focused action reachable above keyboard/in safe area: " + button.text)
			check(title._actions_scroll.get_global_rect().encloses(button.get_global_rect()), "restricted focused action clears the scroll clip")
	title.free()

func test_focused_title_action_follows_live_safe_area_reflow() -> void:
	root.size = Vector2i(640,400)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	title.apply_layout(Rect2(0,0,640,400))
	await settle()
	title.quit_button.grab_focus()
	await settle()
	for bounds: Rect2 in [Rect2(40,16,560,368),Rect2(12,12,616,220),Rect2(160,0,320,400)]:
		title.apply_layout(bounds)
		await settle()
		check(title.quit_button.has_focus(), "display reflow preserves focused action")
		check(bounds.encloses(title.quit_button.get_global_rect()), "same focus follows the resized title scroll viewport")
		check(title._actions_scroll.get_global_rect().encloses(title.quit_button.get_global_rect()), "same focus remains within the scroll clip")
	title.free()

func test_brand_and_artwork_follow_a_clear_reading_order_and_grid() -> void:
	root.size = Vector2i(1280,800)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	title.apply_layout(Rect2(0,0,1280,800))
	await settle()
	var headline := title._title.get_global_rect()
	var edition := title._logo.get_global_rect()
	var art := title._poster.get_global_rect()
	check(headline.end.y <= edition.position.y,"main identity precedes the edition line")
	check(edition.end.y < art.position.y,"typography has its own area above the illustration")
	check(absf(headline.position.x - edition.position.x) <= 1.0,"title lockup shares a left edge")
	check(absf(headline.position.x - art.position.x) <= 1.0,"artwork follows the title grid")
	check(art.end.x < title.new_button.get_global_rect().position.x,"artwork and action column remain separate")
	title.free()
