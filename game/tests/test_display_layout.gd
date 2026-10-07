# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Layout := preload("res://scripts/ui/display_layout.gd")
const PREFS := "user://test_display_layout.cfg"
func test_scale_contract() -> void:
	for row in [[Vector2i(1280,800),1.0,0,1.0,Vector2(1280,800),100.0], [Vector2i(2560,1600),2.0,0,2.0,Vector2(1280,800),100.0], [Vector2i(2560,1600),2.0,200,4.0,Vector2(640,400),200.0], [Vector2i(2000,1280),2.0,200,3.125,Vector2(640,409.6),156.25], [Vector2i(3840,2160),2.0,200,4.0,Vector2(960,540),200.0]]:
		var m: Dictionary = Layout.resolve_scale(row[0],row[1],row[2])
		check_eq(m["scale"],row[3])
		check_eq(m["logical_rect"].size,row[4])
		check_eq(m["effective_percent"],row[5])
	check_eq(Layout.resolve_scale(Vector2i(1280,800),-2.0,42)["scale"],1.0)
	check(Layout.resolve_scale(Vector2i.ZERO,2.0,200).is_empty(),"invalid drawable deferred")
func test_preferences_validation_and_persistence() -> void:
	var clean := ViewPreferences.sanitize({"mode_3d":false,"ui_scale":42,"fullscreen":"yes","windowed_size":Vector2(-1,0)})
	check(not clean.has("mode_3d"))
	check_eq(clean["ui_scale"],0)
	check_eq(clean["fullscreen"],false)
	check_eq(clean["windowed_size"],Vector2(1280,800))
	check_eq(ViewPreferences.write({"ui_scale":175,"fullscreen":true,"windowed_size":Vector2(1000,700)},PREFS),OK)
	var loaded := ViewPreferences.read(PREFS)
	check_eq(loaded["ui_scale"],175)
	check_eq(loaded["windowed_size"],Vector2(1000,700))
	check_eq(loaded["fullscreen"],true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
func test_window_and_caption_fit() -> void:
	var available := Rect2(0,0,640,400)
	var fitted := Layout.fit_window_rect(Rect2(700,-100,900,800),available,44)
	check(available.encloses(fitted))
	check_eq(fitted.size,Vector2(624,384))
	var caption := Layout.clamp_caption_rect(Rect2(620,390,200,60),available)
	check(available.encloses(caption))
func test_injected_metrics_and_coordinate_roundtrip() -> void:
	var layout := Layout.new()
	layout.refresh_with_metrics(Vector2i(2560,1600),2.0)
	layout.set_ui_scale(200)
	check_eq(layout.logical_rect().size,Vector2(640,400))
	check_eq(layout.ui_to_drawable(Vector2(100,50)),Vector2(400,200))
	check_eq(layout.drawable_to_ui(Vector2(400,200)),Vector2(100,50))
	var kept := layout.windowed_size
	layout.set_fullscreen(true)
	layout.refresh_with_metrics(Vector2i(3840,2160),2.0)
	check_eq(layout.windowed_size,kept,"fullscreen never rewrites windowed points")
	layout.set_fullscreen(false)
	check_eq(layout.windowed_size,kept)
	layout.free()

func test_nonfinite_and_obsolete_preferences_recover_to_auto() -> void:
	var clean := ViewPreferences.sanitize({"ui_scale":INF,"windowed_size":Vector2(NAN,800),"mode_3d":false})
	check_eq(clean["ui_scale"],0)
	check_eq(clean["windowed_size"],Vector2(1280,800))
	var config := ConfigFile.new()
	config.set_value("view","mode_3d",false)
	config.set_value("view","ui_scale","tiny")
	check_eq(config.save(PREFS),OK)
	check_eq(ViewPreferences.read(PREFS)["ui_scale"],0)
	check_eq(ViewPreferences.write({"ui_scale":125},PREFS),OK)
	config = ConfigFile.new()
	check_eq(config.load(PREFS),OK)
	check(not config.has_section_key("view","mode_3d"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_invalid_drawable_is_deferred_and_fullscreen_keeps_windowed_points() -> void:
	var layout := Layout.new()
	layout.refresh_with_metrics(Vector2i(2000,1280),2.0)
	var before := layout.metrics.duplicate(true)
	layout.refresh_with_metrics(Vector2i(0,-1),2.0)
	check_eq(layout.metrics,before)
	check_eq(layout.windowed_size,Vector2(1000,640))
	layout.set_fullscreen(true)
	layout.refresh_with_metrics(Vector2i(3840,2160),2.0)
	check_eq(layout.windowed_size,Vector2(1000,640))
	layout.set_fullscreen(false)
	check_eq(layout.windowed_size,Vector2(1000,640))
	layout.free()

func test_native_popup_scale_is_applied_once() -> void:
	var was_embedded := root.gui_embed_subwindows
	root.gui_embed_subwindows = false
	var layout := Layout.new()
	layout.refresh_with_metrics(Vector2i(2560,1600),2.0)
	var popup := Window.new()
	root.add_child(popup)
	popup.size = Vector2i(200,100)
	layout.apply_popup(popup)
	check_eq(popup.size,Vector2i(400,200))
	layout.apply_popup(popup)
	check_eq(popup.size,Vector2i(400,200),"reopening never doubles backing again")
	layout.set_ui_scale(200)
	layout.apply_popup(popup)
	check_eq(popup.size,Vector2i(800,400),"native popup follows effective UI size")
	root.gui_embed_subwindows = was_embedded
	popup.free()
	layout.free()
