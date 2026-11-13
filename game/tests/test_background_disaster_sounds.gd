# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A disaster makes no new sound while the desktop window is paused in the
## background, and is heard again on return.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-background-disaster-sounds.cfg"

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	var city := flat_city(20000)
	for x in range(20, 60): city.building.put(x, 30, 30)
	host.begin_city(city, {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	for i in 4: await process_frame


func after_each() -> void:
	if host.audio.is_background(): host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.free()
	if FileAccess.file_exists(PREFERENCES): DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func _footsteps() -> int:
	var count := 0
	for cue: StringName in host.audio.played:
		if cue == &"giant_footsteps": count += 1
	return count


func _start_monster() -> bool:
	host.audio.record_cues = true
	var started := host.request_disaster(&"monster")
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.advance_day()
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.set_speed(GameClock.Speed.SLOW)
	host.audio.played.clear()
	return started


func test_disaster_one_shots_wait_for_the_window_to_return() -> void:
	check(_start_monster(), "the disaster starts")
	for i in 60: host.audio._process(0.25)
	check(_footsteps() > 0, "the disaster is heard in the foreground")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(host.audio.is_background(), "the window is paused in the background")
	check(host.audio.is_city_frozen(), "the held city is quiet")
	host.audio.played.clear()
	for i in 60: host.audio._process(0.25)
	check_eq(_footsteps(), 0, "no footsteps start while the game is in the background")
	check_eq(host.audio.played.size(), 0, "nothing else starts either: %s" % str(host.audio.played))
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not host.audio.is_city_frozen())
	host.audio.played.clear()
	# A repeat of the same sound is dropped within a twentieth of a second.
	await create_timer(0.2).timeout
	for i in 60: host.audio._process(0.25)
	check(_footsteps() > 0, "the disaster is heard again on return")


func test_a_city_that_keeps_running_in_the_background_keeps_its_sounds() -> void:
	host.preferences["pause_in_background"] = false
	check(_start_monster())
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not host.audio.is_background())
	for i in 60: host.audio._process(0.25)
	check(_footsteps() > 0, "with background pausing off the city and its sounds carry on")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
