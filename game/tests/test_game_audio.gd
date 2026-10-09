# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Music, interface sounds and effects through Main: every cue has a file,
## settings reach the buses, and building, notices, the casino and the title
## screen each make their sound.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const COMSTOCK := &"arcology_comstock"
const PREFERENCES := "user://game-audio.cfg"

## Every effect the director can ask for by name, beyond its tables.
const NAMED_EFFECTS: Array[StringName] = [
	&"bulldoze", &"fire_engine", &"police_siren", &"civil_siren", &"school_bell", &"resort_jackpot",
	&"explosion", &"giant_footsteps", &"thunder", &"tire_skid", &"car_door", &"subway_arrive",
	&"train_doors", &"station_chime", &"elevator_ding", &"chips_bet", &"chips_collect", &"card_deal",
	&"card_shuffle", &"roulette_spin", &"slot_spin", &"slot_reel_stop", &"coins_payout",
	&"money_wheel_spin", &"dice_cage", &"rocket_launch", &"rocket_burnout", &"crowd_cheer",
	&"crowd_boo",
]
const LOOPS: Array[StringName] = [
	&"fire_loop", &"flood_loop", &"riot_loop", &"lava_loop", &"firestorm_loop", &"tornado_loop",
	&"windstorm_loop", &"rain_loop", &"city_day_loop", &"desert_loop", &"footsteps_pavement_loop",
	&"footsteps_sand_loop", &"car_idle_loop", &"car_drive_loop", &"helicopter_loop",
	&"boat_motor_loop", &"sailing_loop", &"train_ride_loop", &"elevator_loop", &"casino_floor_loop",
]

var host: GameHost


func before_all() -> void:
	CasinoTableOverlay.animation_scale = 0.0


func after_all() -> void:
	CasinoTableOverlay.animation_scale = 1.0


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	host.audio.record_cues = true


func after_each() -> void:
	host.free()
	if FileAccess.file_exists(PREFERENCES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func found(funds: int = 200000) -> void:
	host.begin_city(flat_city(funds), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.audio.played.clear()


func test_every_song_and_cue_has_a_file() -> void:
	var audio := host.audio
	for song: StringName in GameAudio.SONGS:
		check(audio.stream(song, "music") != null, "song %s" % song)
	for cue: StringName in GameAudio.UI_CUES:
		check(audio.stream(cue) != null, "interface %s" % cue)
	var effects: Array[StringName] = NAMED_EFFECTS.duplicate()
	for cues: Array in GameAudio.DISASTER_STINGS.values():
		for cue: StringName in cues:
			effects.append(cue)
	for cue: StringName in GameAudio.NOTICE_CUES.values() + GameAudio.STORY_CUES.values():
		if not cue in GameAudio.UI_CUES:
			effects.append(cue)
	for cue: StringName in effects:
		check(audio.stream(cue) != null, "effect %s" % cue)
	for cue: StringName in LOOPS:
		var loop := audio.stream(cue) as AudioStreamOggVorbis
		check(loop != null and loop.loop, "%s loops" % cue)
	var one_shot := audio.stream(&"explosion") as AudioStreamOggVorbis
	check(one_shot != null and not one_shot.loop, "one-shots do not loop")


func test_missing_cues_stay_silent() -> void:
	check(host.audio.stream(&"no_such_sound") == null)
	host.audio.play(&"no_such_sound")
	host.audio.hold_loop(&"no_such_loop")
	check(not host.audio.is_looping(&"no_such_loop"))


func test_sound_settings_sanitize_and_reach_the_buses() -> void:
	var clean := ViewPreferences.sanitize({"music_volume": 7, "effects_volume": -2.0, "music_enabled": "no"})
	check_eq(clean["music_volume"], 1.0)
	check_eq(clean["effects_volume"], 0.0)
	check_eq(clean["music_enabled"], true, "a non-boolean keeps the default")
	host.prefs.set_option(&"music_enabled", false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(GameAudio.BUS_MUSIC)))
	check_eq(host.preferences["music_enabled"], false)
	host.prefs.set_option(&"music_enabled", true)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(GameAudio.BUS_MUSIC)))
	host.prefs.set_option(&"effects_volume", 0.5)
	check_between(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(GameAudio.BUS_EFFECTS)),
		linear_to_db(0.5) - 0.01, linear_to_db(0.5) + 0.01)
	check_between(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(GameAudio.BUS_INTERFACE)),
		linear_to_db(0.5) - 0.01, linear_to_db(0.5) + 0.01, "interface follows effects")
	host.prefs.set_option(&"effects_enabled", false)
	host.audio.played.clear()
	host.audio.play(&"click")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(GameAudio.BUS_INTERFACE)))
	var options := host.prefs.option_values()
	check_eq(options["effects_enabled"], false)
	check_eq(options["effects_volume"], 0.5)


func test_title_screen_plays_the_title_theme() -> void:
	for frame in 3:
		await process_frame
	check(host.title_screen.visible)
	check(GameAudio.TITLE_SONG in host.audio.played, "title theme starts on the title screen")


func test_playlist_plays_every_city_song_before_repeating() -> void:
	var heard: Array[StringName] = []
	for i in GameAudio.SONGS.size() - 1:
		heard.append(host.audio._next_song())
	check(not GameAudio.TITLE_SONG in heard, "the title theme stays on the title screen")
	var unique := {}
	for song in heard:
		unique[song] = true
	check_eq(unique.size(), GameAudio.SONGS.size() - 1, "no repeats within a round")


func test_building_and_refusals_make_their_sounds() -> void:
	found()
	host.select_tool(Tools.Kind.ROAD)
	check(host.handle_drag(Vector2i(50, 60), Vector2i(60, 60)).ok)
	check(&"build_network" in host.audio.played, "a road lays down")
	host.select_tool(Tools.Kind.BULLDOZE)
	check(host.handle_drag(Vector2i(50, 60), Vector2i(52, 60)).ok)
	check(&"bulldoze" in host.audio.played)
	host.sim.city.funds = 0
	host.audio.played.clear()
	host.select_tool(Tools.Kind.ROAD)
	check(not host.handle_drag(Vector2i(50, 62), Vector2i(60, 62)).ok)
	check(&"error" in host.audio.played, "an unaffordable road is refused with a sound")


func test_notices_and_the_tool_bar_make_their_sounds() -> void:
	found()
	host.notices.raise(&"fiscal_crisis", {"funds": -1200, "year": 2001})
	check(&"alert" in host.audio.played)
	host.notice_dialog.dismiss()
	host.audio.played.clear()
	host.notices.raise(&"approval_milestone", {"approval": 72})
	check(host.audio.played.is_empty(), "status-line notices stay quiet")
	host.toolbar.tool_selected.emit(Tools.Kind.ROAD)
	check(&"tool_select" in host.audio.played)


func test_disasters_sting_and_hold_their_loops() -> void:
	found()
	host.sim.disaster_started.emit(&"earthquake", Vector2i(60, 60))
	check(&"earthquake" in host.audio.played)
	host.sim.disaster_started.emit(&"monster", Vector2i(60, 60))
	check(&"giant_roar" in host.audio.played)
	host.audio.hold_loop(&"fire_loop", -8.0)
	check(host.audio.is_looping(&"fire_loop"))
	host.audio.release_loop(&"fire_loop")
	check(not host.audio.is_looping(&"fire_loop"))


func test_casino_rounds_make_their_sounds() -> void:
	found()
	check(host.open_casino_table(COMSTOCK, &"blackjack", CasinoRng.new(3)))
	var overlay := host.casino_overlay
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(8, 3)])
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	overlay.perform_action(&"stand")
	for frame in 3:
		await process_frame
	var played := host.audio.played
	check(&"chips_bet" in played, "the stake goes down")
	check(&"card_deal" in played, "cards are dealt")
	check(&"casino_win" in played or &"casino_lose" in played or &"chips_collect" in played
		or &"casino_big_win" in played, "the result is announced")
	host.escape()


# Guards against: the short pause before the first city song becoming a
# 30–90 second silence once the title theme finished fading.
func test_first_city_song_follows_the_title_after_a_short_pause() -> void:
	var audio := host.audio
	audio._on_title = true
	audio._song = GameAudio.TITLE_SONG
	host.title_screen.close()
	audio._update_music(0.0)
	check_between(audio._gap_left, 4.0, 10.0, "leaving the title sets a short pause")
	var gap := audio._gap_left
	audio._fading_out = true
	audio._finish_fade_out()
	check_eq(audio._gap_left, gap, "the finished fade keeps that pause")
	check_eq(audio._song, &"")
	check(not audio._fading_out)


# Guards against: music and loops playing over other apps with "Pause while
# in the background" on.
func test_background_pauses_music_and_loops() -> void:
	found()
	var audio := host.audio
	audio.hold_loop(&"fire_loop", -8.0)
	audio.set_background(true)
	check(audio.is_sound_paused(), "music and loops are held in the background")
	# Headless players never start, so Godot reports no paused playback; the
	# held state also keeps the next song from starting while away.
	audio._gap_left = 1.0
	var song := audio._song
	audio._update_music(5.0)
	check_eq(audio._gap_left, 1.0, "the pause before the next song waits")
	check_eq(audio._song, song, "no song starts in the background")
	audio.set_background(false)
	check(not audio.is_sound_paused())
	audio._update_music(5.0)
	check(audio._gap_left != 1.0 or audio._song != song, "the music schedule moves again on return")
	# Main follows the window focus only when the player chose to pause there.
	host.preferences["pause_in_background"] = false
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not audio.is_background(), "sound keeps playing when pausing in the background is off")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	host.preferences["pause_in_background"] = true
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not MobilePlatform.is_mobile(): check(audio.is_background(), "focus-out pauses the sound")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not audio.is_background(), "focus-in resumes it")


# Guards against: a fire loop roaring over a paused city or the January review.
func test_disaster_loops_rest_while_the_city_is_frozen() -> void:
	found()
	var audio := host.audio
	audio.hold_loop(&"fire_loop", -8.0)
	audio._poll_left = 0.0
	audio._process(0.3)
	check(audio.is_city_frozen(), "a paused city is frozen")
	check(not audio.is_looping(&"fire_loop"), "disaster loops stop while time stands still")
	host.sim.set_speed(GameClock.Speed.SLOW)
	check(not audio.is_city_frozen())
	host.push_modal()
	check(audio.is_city_frozen(), "a modal window freezes the city too")
	host.pop_modal()
	host.sim.set_speed(GameClock.Speed.PAUSED)


# Guards against: the effects slider giving no sample of its level.
func test_effects_volume_plays_a_sample() -> void:
	host.audio.played.clear()
	host.prefs.set_option(&"effects_volume", 0.6)
	check(&"click" in host.audio.played, "moving the effects level plays a sample")
