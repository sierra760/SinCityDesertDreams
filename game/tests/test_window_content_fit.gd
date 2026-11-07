# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Windows and dialogs show their whole content when the display has room,
## and scroll only when it does not.

func _run_all() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			_current = method.name
			var before := _failed
			await call(method.name)
			if _failed == before:
				_passed += 1
			else:
				print("  FAIL ",method.name)
	print("Results: %d passed, %d failed" % [_passed,_failed])
	quit(0 if _failed == 0 else 1)

func _settle() -> void:
	for frame in 6:
		await process_frame

## A nonmodal report window: chrome under a full-rect holder, no modal guard.
func _report(title: String, rows: int, row_width: float = 0.0, modal := false) -> Dictionary:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var chrome := UIFactory.make_window_chrome(title)
	var panel: Control = chrome["root"]
	panel.set_meta("preferred_size",Vector2(600,300))
	holder.add_child(panel)
	panel.position = Vector2(40,40)
	for row in rows:
		var label := UIFactory.make_label("Report row %d: 2,147,483,647" % row)
		if row_width > 0.0: label.custom_minimum_size.x = row_width
		chrome["body"].add_child(label)
	chrome["actions"].add_child(UIFactory.make_button("Done"))
	if modal: UIFactory.contain_modal_focus(holder)
	chrome["holder"] = holder
	return chrome

func _scroll_hidden(chrome: Dictionary) -> bool:
	var scroll: ScrollContainer = chrome["body_scroll"]
	var body: Control = chrome["body"]
	return scroll.size.y + 0.5 >= body.get_combined_minimum_size().y and scroll.size.x + 0.5 >= body.get_combined_minimum_size().x

func test_report_window_grows_to_show_all_rows() -> void:
	root.size = Vector2i(1280,800)
	var chrome := _report("Treasury",14)
	await _settle()
	var panel: Control = chrome["root"]
	check_gt(panel.size.y,300.0,"window grows past its preferred height: %s" % panel.size)
	check(_scroll_hidden(chrome),"every row is visible without scrolling: scroll %s body %s" % [chrome["body_scroll"].size,chrome["body"].get_combined_minimum_size()])
	check(Rect2(Vector2.ZERO,Vector2(1280,800)).encloses(panel.get_global_rect()),"window stays on screen")
	check_eq(panel.position.x,40.0,"report keeps its own place rather than recentring")
	chrome["holder"].free()

func test_report_window_widens_for_wide_rows() -> void:
	root.size = Vector2i(1280,800)
	var chrome := _report("Industries",3,900.0)
	await _settle()
	var panel: Control = chrome["root"]
	check_gt(panel.size.x,900.0,"window widens to show wide rows: %s" % panel.size)
	check(_scroll_hidden(chrome),"no horizontal scrolling while the display has room")
	check(Rect2(Vector2.ZERO,Vector2(1280,800)).encloses(panel.get_global_rect()),"widened window stays on screen")
	chrome["holder"].free()

func test_short_content_keeps_preferred_size() -> void:
	root.size = Vector2i(1280,800)
	var chrome := _report("Neighbors",2)
	await _settle()
	var panel: Control = chrome["root"]
	check(panel.size.is_equal_approx(Vector2(600,300)),"short content keeps the preferred size: %s" % panel.size)
	chrome["holder"].free()

func test_content_beyond_display_still_scrolls() -> void:
	root.size = Vector2i(640,400)
	var chrome := _report("Newspaper",40,1000.0)
	await _settle()
	var panel: Control = chrome["root"]
	var available := Rect2(Vector2.ZERO,Vector2(640,400))
	check(available.encloses(panel.get_global_rect()),"oversized window is held inside the display: %s" % panel.get_global_rect())
	check_lt(chrome["body_scroll"].size.y,chrome["body"].get_combined_minimum_size().y,"tall content scrolls")
	check(available.encloses(chrome["close_button"].get_global_rect()),"close stays reachable")
	chrome["holder"].free()

func test_layout_reset_is_refitted() -> void:
	root.size = Vector2i(1280,800)
	var chrome := _report("Population",14)
	await _settle()
	var panel: Control = chrome["root"]
	var fitted := panel.size
	# DisplayLayout places registered windows at their preferred size on a
	# metrics change; the panel must return to its content size afterwards.
	panel.size = Vector2(600,300)
	await _settle()
	check(panel.size.is_equal_approx(fitted),"content size restored after a layout reset: %s vs %s" % [panel.size,fitted])
	chrome["holder"].free()

func test_modal_dialog_still_centres_on_content() -> void:
	root.size = Vector2i(1280,800)
	var chrome := _report("Notice",14,0.0,true)
	await _settle()
	var panel: Control = chrome["root"]
	check(_scroll_hidden(chrome),"dialog shows its whole body")
	check(absf(panel.get_global_rect().get_center().x-640.0) <= 1.0,"dialog is centred horizontally: %s" % panel.get_global_rect())
	check(absf(panel.get_global_rect().get_center().y-400.0) <= 1.0,"dialog is centred vertically: %s" % panel.get_global_rect())
	chrome["holder"].free()
