# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Editor HUD must not advertise running-city actions before founding.
extends "res://tests/test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://editor_clock_controls.cfg"
const SAVE := "user://editor_clock_controls.sc2d"
var host: GameHost

func before_all() -> void:
	root.size = Vector2i(1280, 800)

func before_each() -> void:
	ViewPreferences.write({}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.start_new_city({"name":"Editor Clock", "seed":4123}, flat_city())

func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	host = null
	for path in [PREFS, SAVE]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_editing_controls() -> void:
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.status_bar.speed_label.text, "Stopped")
	check(host.status_bar.speed_label.tooltip_text.contains("Found City"), "clock explains how to start time")
	var clock_buttons: Array[Node] = host.status_bar.find_children("*", "Button", true, false).filter(func(button: Node) -> bool:
		return button != host.status_bar.emergency_button and button != host.status_bar.get("_details_button"))
	check(clock_buttons.is_empty(), "footer has no clock controls")
	for speed: int in GameClock.Speed.values():
		host.menu_bar.press(&"speed", speed)
		check_eq(host.sim.speed, GameClock.Speed.PAUSED, "menu cannot start the editor clock")
		check_eq(host.status_bar.speed_label.text, "Stopped")

func test_editor_clock_stays_stopped_through_modal_speed_updates() -> void:
	_check_editing_controls()
	host.files.open_save_dialog()
	host.sim.speed_changed.emit(GameClock.Speed.PAUSED)
	_check_editing_controls()
	host.save_dialog.close()
	_check_editing_controls()
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)

func test_founding_enables_menu_clock_then_new_editor_stops_it() -> void:
	check(host.found_city())
	check_eq(host.status_bar.speed_label.text, "Slow")
	check(not host.status_bar.speed_label.tooltip_text.contains("Found City"), "founding hint clears")
	for speed: int in GameClock.Speed.values():
		check(host.menu_bar.is_enabled(&"speed", speed), "founded city can select menu speed")
		host.menu_bar.press(&"speed", speed)
		check_eq(host.sim.speed, speed, "speed menu reaches Main")
		check_eq(host.status_bar.speed_label.text, GameClock.SPEED_NAMES[speed])
		check(host.menu_bar.is_checked(&"speed", speed), "speed menu stays selected")
	host.start_new_city({"name":"Second Editor", "seed":123}, flat_city())
	_check_editing_controls()

func test_loading_running_city_restores_clock_controls() -> void:
	check(host.found_city())
	host.save_path = SAVE
	check_eq(host.save_city(), OK)
	host.start_new_city({"name":"Editor Again", "seed":123}, flat_city())
	_check_editing_controls()
	check(host.load_city(SAVE))
	check_eq(host.stage, GameHost.Stage.PLAY)
	for speed: int in GameClock.Speed.values():
		host.menu_bar.press(&"speed", speed)
		check_eq(host.sim.speed, speed, "loaded city speed menu works")
		check_eq(host.status_bar.speed_label.text, GameClock.SPEED_NAMES[speed])

func test_show_editing_clears_old_alert_visibility_and_help() -> void:
	host.status_bar.set_alerts(PackedStringArray(["Power shortage"]))
	check(host.status_bar.alert_label.visible)
	host.status_bar.show_editing("Editor Clock")
	check_eq(host.status_bar.alert_label.text, "")
	check_eq(host.status_bar.alert_label.tooltip_text, "")
	check(not host.status_bar.alert_label.visible, "old warning must not reserve an empty row")
