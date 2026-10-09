# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Plays the game's music, interface sounds and effects.
##
## One node owned by GameHost. It listens to signals the game already has
## (simulation events, the toolbar, Explore status, casino table events,
## every button) and polls a few states each frame (active disasters, the
## weather, what the player is driving). Streams come from
## res://assets/audio/{music,ui,sfx}; a missing file is skipped quietly so
## headless tests and partial checkouts stay silent rather than noisy.
##
## Music plays the title theme on the title screen, then a shuffled playlist
## with 30–90 seconds of quiet between songs. Notices and casino tables duck
## it. Three buses (Music, Effects, Interface) carry the player's volume and
## on/off choices; Interface follows the Effects setting.
class_name GameAudio
extends Node

const ROOT := "res://assets/audio/"
const TITLE_SONG := &"glitter_gulch"
const SONGS: Array[StringName] = [
	&"glitter_gulch", &"swizzle_stick", &"tonopah_turnoff", &"cabana_number_nine",
	&"cashiers_cage_cha_cha", &"keno_at_three", &"amargosa_lope", &"tip_jar_waltz",
	&"yucca_flat_luau", &"pawn_shop_boogie",
]
const GAP_MIN := 30.0
const GAP_MAX := 90.0
const MUSIC_DB := -4.0
const DUCK_NOTICE_DB := -6.0
const DUCK_CASINO_DB := -10.0
const FADE_SECONDS := 1.5

## Loops that stop while city time stands still, and the city bed's level then.
const FROZEN_RELEASED: Array[StringName] = [&"fire_loop", &"flood_loop", &"riot_loop", &"lava_loop",
	&"firestorm_loop", &"tornado_loop", &"windstorm_loop", &"rain_loop"]
const FROZEN_BED_DB := -30.0

const BUS_MUSIC := &"Music"
const BUS_EFFECTS := &"Effects"
const BUS_INTERFACE := &"Interface"

## Interface sounds live in ui/; everything else in sfx/.
const UI_CUES: Array[StringName] = [
	&"click", &"toggle", &"tool_select", &"place_zone", &"build_network", &"error", &"cash",
	&"notice", &"alert", &"reward", &"window_open", &"window_close", &"casino_win",
	&"casino_lose", &"casino_big_win", &"poker_hold", &"poker_deal", &"trajectory_tick",
]

## Per-cue trim in dB so one-shots sit together; anything unlisted plays at 0.
const TRIM := {
	&"click": -10.0, &"toggle": -10.0, &"tool_select": -8.0, &"window_open": -12.0,
	&"window_close": -12.0, &"place_zone": -6.0, &"build_network": -6.0, &"error": -6.0,
	&"poker_hold": -8.0, &"trajectory_tick": -12.0, &"card_deal": -4.0, &"chips_bet": -3.0,
	&"bulldoze": -4.0, &"newspaper": -4.0, &"gunshot": -8.0,
}

## Sounds that start with a disaster, by disaster kind.
const DISASTER_STINGS := {
	&"earthquake": [&"earthquake"], &"monster": [&"giant_roar"], &"meltdown": [&"meltdown_alarm"],
	&"volcano": [&"volcano_eruption"], &"plane_crash": [&"plane_dive"], &"microwave": [&"beam_strike"],
	&"tornado": [&"civil_siren"], &"hurricane": [&"civil_siren"], &"major_flood": [&"civil_siren"],
	&"firestorm": [&"civil_siren"], &"hazard": [&"civil_siren"], &"chemical_spill": [&"civil_siren"],
	&"riot": [&"police_siren"], &"mass_riots": [&"police_siren"],
}

## Notice kinds raised by the simulation, and the sound that goes with them.
const NOTICE_CUES := {
	&"newspaper": &"newspaper", &"reward_offered": &"reward", &"disaster": &"alert",
	&"national_guard": &"alert", &"bankruptcy": &"alert", &"fiscal_crisis": &"alert",
	&"opposition": &"crowd_boo", &"exodus": &"alert",
}

## Newspaper stories that deserve a sound of their own.
const STORY_CUES := {
	&"city_milestone": &"crowd_cheer", &"prison_escape": &"prison_alarm",
	&"traffic_jam": &"car_horns", &"port_opened": &"ship_horn", &"bridge_collapse": &"building_collapse",
	&"casino_debut": &"resort_jackpot", &"ordinance_enacted": &"crowd_cheer",
}

var music_enabled := true
var effects_enabled := true
var music_volume := 0.8
var effects_volume := 0.9
## When true every cue is appended to `played` (tests read it).
var record_cues := false
var played: Array[StringName] = []

var _host: GameHost
var _cache: Dictionary = {}
var _music: AudioStreamPlayer
var _song := &""
var _queue: Array[StringName] = []
var _gap_left := 0.0
var _fading_out := false
var _on_title := false
var _duck_db := 0.0
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _loops: Dictionary = {}          ## loop id -> AudioStreamPlayer
var _loop_targets: Dictionary = {}   ## loop id -> target dB (or -INF to fade out)
var _last_cue_ms: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _poll_left := 0.0
var _thunder_left := 30.0
var _monster_step_left := 0.0
var _explore_status: Dictionary = {}
var _last_speed := 0.0
var _last_vehicle := ""
var _last_doors := ""
var _lift_states: Dictionary = {}
var _casino: Node
var _trajectory_step := 0
var _hooked: Dictionary = {}
## The Dummy driver (headless tests) hears nothing: cues are still chosen and
## recorded, but no player starts, so nothing is left playing at exit.
var _silent := false
## The desktop window is in the background with "Pause while in the background" on.
var _background := false
## The OS paused the application (mobile).
var _app_paused := false


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	_silent = AudioServer.get_driver_name() == "Dummy"
	_ensure_buses()
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = BUS_MUSIC
	_music.finished.connect(_on_song_finished)
	add_child(_music)
	for i in 10:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		add_child(voice)
		_voices.append(voice)
	_apply_levels()


## Connect to the host's signals. Call once, after the host built its UI.
func bind(host: GameHost) -> void:
	_host = host
	var sim := host.sim
	if sim != null:
		sim.disaster_started.connect(_on_disaster_started)
		sim.news_published.connect(_on_story)
	if host.toolbar != null:
		host.toolbar.tool_selected.connect(func(_tool: int) -> void: play(&"tool_select"))
	if host.exploration != null:
		host.exploration.status_changed.connect(func(status: Dictionary) -> void: _explore_status = status)
		host.exploration.active_changed.connect(_on_explore_active)
	_hook_tree(host)
	host.get_tree().node_added.connect(_hook_node)


# ── Preferences ──────────────────────────────────────────────────────────

## Read the four sound settings from the player's preferences.
func apply_preferences(preferences: Dictionary) -> void:
	music_enabled = bool(preferences.get("music_enabled", music_enabled))
	effects_enabled = bool(preferences.get("effects_enabled", effects_enabled))
	music_volume = clampf(float(preferences.get("music_volume", music_volume)), 0.0, 1.0)
	effects_volume = clampf(float(preferences.get("effects_volume", effects_volume)), 0.0, 1.0)
	_apply_levels()
	if not music_enabled and _music != null:
		_music.stop()
		_song = &""
	elif music_enabled and _music != null and not _music.playing:
		_gap_left = minf(_gap_left, 2.0)


func _ensure_buses() -> void:
	for bus in [BUS_MUSIC, BUS_EFFECTS, BUS_INTERFACE]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")


func _apply_levels() -> void:
	_set_bus(BUS_MUSIC, music_enabled, music_volume)
	_set_bus(BUS_EFFECTS, effects_enabled, effects_volume)
	_set_bus(BUS_INTERFACE, effects_enabled, effects_volume)


func _set_bus(bus: StringName, enabled: bool, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, not enabled or volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


# ── Streams ──────────────────────────────────────────────────────────────

## The stream for a cue or song, or null when the file is not present.
func stream(cue: StringName, folder := "") -> AudioStream:
	var key := "%s/%s" % [folder, cue]
	if _cache.has(key):
		return _cache[key]
	if folder.is_empty():
		folder = "ui" if cue in UI_CUES else "sfx"
	var path := "%s%s/%s.ogg" % [ROOT, folder, cue]
	var loaded: AudioStream = null
	if ResourceLoader.exists(path):
		loaded = load(path) as AudioStream
		if loaded is AudioStreamOggVorbis:
			(loaded as AudioStreamOggVorbis).loop = String(cue).ends_with("_loop")
	_cache[key] = loaded
	return loaded


## Play a one-shot. Repeats of the same cue within `min_gap` seconds are
## dropped so bursts (a skipped casino animation, a long drag) stay calm.
func play(cue: StringName, volume_db := 0.0, pitch := 1.0, min_gap := 0.05) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_cue_ms.get(cue, -100000)) < int(min_gap * 1000.0):
		return
	_last_cue_ms[cue] = now
	if record_cues:
		played.append(cue)
	if not effects_enabled or _silent:
		return
	var sound := stream(cue)
	if sound == null or _voices.is_empty():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = sound
	voice.bus = BUS_INTERFACE if cue in UI_CUES else BUS_EFFECTS
	voice.volume_db = volume_db + float(TRIM.get(cue, 0.0))
	voice.pitch_scale = pitch
	voice.play()


## Start (or keep) a loop at a target level; it fades toward that level.
func hold_loop(cue: StringName, volume_db := -6.0, pitch := 1.0) -> void:
	var player: AudioStreamPlayer = _loops.get(cue)
	if player == null:
		var sound := stream(cue)
		if sound == null:
			return
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + String(cue)
		player.stream = sound
		player.bus = BUS_EFFECTS
		player.volume_db = -40.0
		add_child(player)
		_loops[cue] = player
		if record_cues:
			played.append(cue)
	if effects_enabled and not _silent and not player.playing:
		player.play()
		# Godot keeps a pause only on a live playback: apply it after starting.
		player.stream_paused = is_sound_paused()
	_loop_targets[cue] = volume_db
	player.pitch_scale = lerpf(player.pitch_scale, pitch, 0.2)


## Fade a loop out; it is freed once silent.
func release_loop(cue: StringName) -> void:
	if _loops.has(cue):
		_loop_targets[cue] = -INF


## Pause (or resume) the music and every loop while the game window is in
## the background. Main calls this only when the player asked to pause there.
func set_background(on: bool) -> void:
	_background = on
	_apply_stream_pause()


func is_background() -> bool:
	return _background


## True while music and loops are held (window in the background, or the
## OS paused the application).
func is_sound_paused() -> bool:
	return _background or _app_paused


func _apply_stream_pause() -> void:
	var paused := is_sound_paused()
	if _music != null: _music.stream_paused = paused
	for player: AudioStreamPlayer in _loops.values():
		player.stream_paused = paused


## A short sample at the current effects level (Settings → Sound).
func preview_effects() -> void:
	play(&"click", 0.0, 1.0, 0.15)


func is_looping(cue: StringName) -> bool:
	return _loops.has(cue) and float(_loop_targets.get(cue, -INF)) > -INF


func _fade_loops(delta: float) -> void:
	for cue: StringName in _loops.keys():
		var player: AudioStreamPlayer = _loops[cue]
		var target: float = _loop_targets.get(cue, -INF)
		var goal := target if target > -INF else -60.0
		player.volume_db = move_toward(player.volume_db, goal, delta * 30.0)
		if target == -INF and player.volume_db <= -59.0:
			player.queue_free()
			_loops.erase(cue)
			_loop_targets.erase(cue)


# ── Music ────────────────────────────────────────────────────────────────

func _start_song(song: StringName) -> void:
	_song = song
	if record_cues:
		played.append(song)
	var sound := stream(song, "music")
	if sound == null or not music_enabled or _silent:
		_gap_left = GAP_MIN
		return
	_music.stream = sound
	_music.volume_db = MUSIC_DB + _duck_db
	_music.play()
	_music.stream_paused = is_sound_paused()


func _next_song() -> StringName:
	if _queue.is_empty():
		_queue = SONGS.duplicate()
		_queue.erase(TITLE_SONG)
		for i in range(_queue.size() - 1, 0, -1):  # shuffle with our own generator
			var j := _rng.randi_range(0, i)
			var held := _queue[i]
			_queue[i] = _queue[j]
			_queue[j] = held
		if _queue.size() > 1 and _queue[0] == _song:
			_queue.append(_queue.pop_front())
	return _queue.pop_front()


func _on_song_finished() -> void:
	_song = &""
	_gap_left = _rng.randf_range(GAP_MIN, GAP_MAX)


func _update_music(delta: float) -> void:
	# Held music keeps its place; no fade or next song starts meanwhile.
	if is_sound_paused(): return
	var title := _host != null and is_instance_valid(_host.title_screen) and _host.title_screen.visible
	if title and not _on_title:
		_on_title = true
		_music.stop()
		_start_song(TITLE_SONG)
	elif not title and _on_title:
		_on_title = false
		if _song == TITLE_SONG:
			_fade_out_song()
		_gap_left = _rng.randf_range(4.0, 10.0)  # a breath before the first city song
	var duck := 0.0
	if _host != null:
		if is_instance_valid(_host.notice_dialog) and _host.notice_dialog.is_open():
			duck = DUCK_NOTICE_DB
		if _host.is_casino_open() or bool(_explore_status.get("resort", {}).get("inside", false)):
			duck = DUCK_CASINO_DB
	_duck_db = move_toward(_duck_db, duck, delta * 12.0)
	if _music.playing:
		var goal := MUSIC_DB + _duck_db
		if _fading_out:
			_music.volume_db -= delta * (40.0 / FADE_SECONDS)
			if _music.volume_db < -50.0:
				_finish_fade_out()
		else:
			_music.volume_db = move_toward(_music.volume_db, goal, delta * 20.0)
		return
	if not music_enabled:
		return
	_gap_left -= delta
	if _gap_left <= 0.0:
		_start_song(TITLE_SONG if _on_title else _next_song())


func _fade_out_song() -> void:
	if _music.playing:
		_fading_out = true


## A faded song ends without choosing a new gap: the short pause set when the
## title closed stays in place for the first city song.
func _finish_fade_out() -> void:
	_music.stop()
	_fading_out = false
	_song = &""


# ── Per-frame state ──────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_music(delta)
	_fade_loops(delta)
	if _host == null:
		return
	_update_casino()
	_poll_left -= delta
	if _poll_left > 0.0:
		_update_explore(delta)
		return
	_poll_left = 0.25
	var playing := _host.stage == GameHost.Stage.PLAY and _host.sim != null and _host.sim.city != null
	if not playing:
		for cue: StringName in _loops.keys():
			release_loop(cue)
		return
	if is_city_frozen():
		# A paused city (or one held by a window such as the January review)
		# is quiet: disasters and weather fall silent, the city bed drops low.
		for cue: StringName in FROZEN_RELEASED:
			release_loop(cue)
		for cue: StringName in [&"city_day_loop", &"desert_loop"]:
			if is_looping(cue): hold_loop(cue, FROZEN_BED_DB)
		_update_explore(delta)
		return
	_update_disasters(0.25)
	_update_ambience(0.25)
	_update_explore(delta)


## True while city time stands still: paused, or held by a modal window.
func is_city_frozen() -> bool:
	return _host != null and _host.sim != null and (_host.sim.speed == GameClock.Speed.PAUSED or _host.modal_depth > 0)


func _update_disasters(step: float) -> void:
	var system := _host.sim.get_system(&"disasters")
	var wanted: Dictionary = {}
	if system != null:
		var fires: Array = system.call("fires")
		if not fires.is_empty():
			wanted[&"fire_loop"] = clampf(-14.0 + 2.0 * log(float(fires.size())) / log(2.0), -14.0, -4.0)
		if not (system.call("flooded") as Array).is_empty():
			wanted[&"flood_loop"] = -8.0
		if not (system.call("riots") as Array).is_empty():
			wanted[&"riot_loop"] = -8.0
		var active: Dictionary = system.call("active")
		match StringName(String(active.get("kind", ""))):
			&"volcano": wanted[&"lava_loop"] = -8.0
			&"firestorm": wanted[&"firestorm_loop"] = -6.0
			&"hurricane":
				wanted[&"windstorm_loop"] = -6.0
				wanted[&"rain_loop"] = -8.0
		for entity: Dictionary in system.call("entities"):
			match StringName(String(entity.get("kind", ""))):
				&"tornado": wanted[&"tornado_loop"] = -5.0
				&"monster":
					_monster_step_left -= step
					if _monster_step_left <= 0.0:
						_monster_step_left = 2.5
						play(&"giant_footsteps", -4.0)
	for cue: StringName in [&"fire_loop", &"flood_loop", &"riot_loop", &"lava_loop",
			&"firestorm_loop", &"tornado_loop", &"windstorm_loop"]:
		if wanted.has(cue):
			hold_loop(cue, wanted[cue])
		else:
			release_loop(cue)
	if wanted.has(&"rain_loop"):
		hold_loop(&"rain_loop", wanted[&"rain_loop"])


func _update_ambience(step: float) -> void:
	var exploring := _host.is_exploring()
	var city := _host.sim.city
	var bed := &"city_day_loop" if city.status >= 1 else &"desert_loop"
	var other := &"desert_loop" if bed == &"city_day_loop" else &"city_day_loop"
	hold_loop(bed, -14.0 if exploring else -20.0)
	release_loop(other)
	var environment := _host.sim.get_system(&"environment")
	var rain := int(environment.call("precipitation")) if environment != null and environment.has_method("precipitation") else 0
	var storming := is_looping(&"windstorm_loop")  # a hurricane holds its own rain
	if rain >= 60 and not storming:
		hold_loop(&"rain_loop", -12.0 + float(rain - 60) / 8.0)
	elif not storming:
		release_loop(&"rain_loop")
	if storming or rain >= 85:
		_thunder_left -= step
		if _thunder_left <= 0.0:
			_thunder_left = _rng.randf_range(20.0, 60.0)
			play(&"thunder", -4.0)


# ── Explore ──────────────────────────────────────────────────────────────

func _on_explore_active(on: bool) -> void:
	_explore_status = {}
	_last_vehicle = ""
	_last_doors = ""
	_lift_states.clear()
	if not on:
		for cue: StringName in [&"footsteps_pavement_loop", &"footsteps_sand_loop", &"car_idle_loop",
				&"car_drive_loop", &"helicopter_loop", &"boat_motor_loop", &"sailing_loop",
				&"train_ride_loop", &"elevator_loop", &"casino_floor_loop", &"fountain_loop"]:
			release_loop(cue)


func _update_explore(delta: float) -> void:
	if not _host.is_exploring() or _explore_status.is_empty():
		return
	var status := _explore_status
	var mode := int(status.get("mode", 0))
	var speed := float(status.get("speed", 0.0))
	var vehicle := String(status.get("vehicle", ""))
	var domain := String(CityTrafficCatalog.domain(StringName(vehicle))) if not vehicle.is_empty() else ""
	var inside_resort := bool((status.get("resort", {}) as Dictionary).get("inside", false))
	var transit := _transit_status()
	var on_foot := mode == ExploreActorProfile.Mode.WALK

	# Footsteps, by surface; playback rate follows walking speed.
	var walker: Node = _host.exploration.pedestrian
	var walking := on_foot and speed > 0.02 and walker != null and walker.has_method("landed") and bool(walker.call("landed"))
	var sandy := walking and not inside_resort and not bool(transit.get("interior", false)) and _bare_ground(walker)
	var rate := clampf(speed / 0.09, 0.8, 1.9)
	if walking and sandy:
		hold_loop(&"footsteps_sand_loop", -8.0, rate)
		release_loop(&"footsteps_pavement_loop")
	elif walking:
		hold_loop(&"footsteps_pavement_loop", -8.0, rate)
		release_loop(&"footsteps_sand_loop")
	else:
		release_loop(&"footsteps_pavement_loop")
		release_loop(&"footsteps_sand_loop")

	# What the player is driving, flying or sailing.
	var engine := {}
	if mode != ExploreActorProfile.Mode.WALK and not vehicle.is_empty():
		match domain:
			"road":
				var t := clampf(speed / 1.2, 0.0, 1.0)
				engine[&"car_idle_loop"] = -6.0 - 14.0 * t
				if speed > 0.04: engine[&"car_drive_loop"] = -14.0 + 10.0 * t
				if delta > 0.0 and _last_speed > 0.5 and (_last_speed - speed) / delta > 2.0:
					play(&"tire_skid", -6.0, 1.0, 2.0)
			"air": engine[&"helicopter_loop"] = -5.0
			"water": engine[&"sailing_loop" if vehicle == "sailboat" else &"boat_motor_loop"] = -6.0
			"rail": engine[&"train_ride_loop"] = -8.0
	if vehicle != _last_vehicle:
		if domain == "road" or _last_vehicle_domain() == "road":
			play(&"car_door", -4.0)
		_last_vehicle = vehicle
	if bool(transit.get("passenger", false)) and float(transit.get("speed_mps", 0.0)) > 0.5:
		engine[&"train_ride_loop"] = -10.0 + clampf(float(transit.get("speed_mps", 0.0)) / 20.0, 0.0, 1.0) * 4.0
	for cue: StringName in [&"car_idle_loop", &"car_drive_loop", &"helicopter_loop", &"boat_motor_loop",
			&"sailing_loop", &"train_ride_loop"]:
		if engine.has(cue):
			var pitch := 0.85 + clampf(speed / 1.2, 0.0, 1.0) * 0.6 if cue == &"car_drive_loop" else 1.0
			hold_loop(cue, engine[cue], pitch)
		else:
			release_loop(cue)
	_last_speed = speed

	# Stations: arrivals, doors, the elevator.
	var doors := String(transit.get("doors", ""))
	if doors != _last_doors:
		if doors == "approaching":
			play(&"subway_arrive", -6.0)
		elif doors == "opening":
			play(&"train_doors", -4.0)
			play(&"station_chime", -6.0)
		_last_doors = doors
	_update_elevators(walker)
	if inside_resort:
		hold_loop(&"casino_floor_loop", -10.0)
	else:
		release_loop(&"casino_floor_loop")


func _last_vehicle_domain() -> String:
	return String(CityTrafficCatalog.domain(StringName(_last_vehicle))) if not _last_vehicle.is_empty() else ""


func _transit_status() -> Dictionary:
	var service: Node = _host.exploration.transit_service
	if not is_instance_valid(service) or not service.has_method("status") or service.get("network") == null:
		return {}
	return service.call("status")


func _update_elevators(walker: Node) -> void:
	var service: Node = _host.exploration.transit_service
	var world: Node = service.get("world") if is_instance_valid(service) else null
	if not is_instance_valid(world) or not is_instance_valid(walker) or not world.has_method("in_elevator"):
		release_loop(&"elevator_loop")
		return
	var riding := bool(world.call("in_elevator", (walker as Node3D).global_position))
	var moving := false
	for lift: Node in world.get("elevators"):
		var state := String(lift.get("state"))
		var before := String(_lift_states.get(lift.get_instance_id(), state))
		if riding and before == "moving" and state != "moving":
			play(&"elevator_ding", -4.0)
		moving = moving or state == "moving"
		_lift_states[lift.get_instance_id()] = state
	if riding and moving:
		hold_loop(&"elevator_loop", -8.0)
	else:
		release_loop(&"elevator_loop")


func _bare_ground(walker: Node) -> bool:
	var city := _host.sim.city
	var at := (walker as Node3D).global_position
	var x := int(floor(at.x))
	var y := int(floor(at.z))
	return city != null and city.in_bounds(x, y) and city.building_at(x, y) == 0 and not city.is_water(x, y)


# ── Events ───────────────────────────────────────────────────────────────

## A Builder result reached the construction flow.
func on_construction(result: Dictionary, tool: int) -> void:
	if not bool(result.get("ok", false)):
		var reason := String(result.get("reason", ""))
		if reason != "no tool" and not reason.begins_with("Return to Build"):
			play(&"error")
		return
	if not bool(result.get("applied", true)) or bool(result.get("needs_confirmation", false)):
		return
	match tool:
		Tools.Kind.BULLDOZE, Tools.Kind.DEZONE:
			play(&"bulldoze", 0.0, 1.0, 0.3)
		Tools.Kind.DISPATCH_FIRE:
			play(&"fire_engine")
		Tools.Kind.DISPATCH_POLICE:
			play(&"police_siren")
		Tools.Kind.DISPATCH_MILITARY:
			play(&"civil_siren", -4.0)
		Tools.Kind.SCHOOL, Tools.Kind.COLLEGE:
			play(&"place_zone")
			play(&"school_bell", -8.0)
		Tools.Kind.ARCOLOGY_COMSTOCK, Tools.Kind.ARCOLOGY_JUNCTION, Tools.Kind.ARCOLOGY_BOULDER, Tools.Kind.ARCOLOGY_ORBIT:
			play(&"resort_jackpot")
		Tools.Kind.ROAD, Tools.Kind.HIGHWAY, Tools.Kind.ONRAMP, Tools.Kind.TUNNEL, Tools.Kind.RAIL, \
				Tools.Kind.SUBWAY, Tools.Kind.SUBWAY_PORTAL, Tools.Kind.POWER_LINE, Tools.Kind.WATER_PIPE:
			play(&"build_network")
		_:
			if Tools.is_reward_tool(tool):
				play(&"reward")
			elif Tools.is_terrain_tool(tool) or Tools.is_tree_tool(tool):
				play(&"build_network", -4.0)
			else:
				play(&"place_zone")


## The notice queue is about to show (or status-line) something.
func on_notice(kind: StringName) -> void:
	play(NOTICE_CUES.get(kind, &"notice"))


func _on_disaster_started(kind: StringName, _center: Vector2i) -> void:
	for cue: StringName in DISASTER_STINGS.get(kind, []):
		play(cue)
	if kind == &"plane_crash":
		get_tree().create_timer(3.2).timeout.connect(func() -> void: play(&"explosion"))


func _on_story(story: Dictionary) -> void:
	var kind := StringName(String(story.get("kind", "")))
	if kind == &"approval_vote":
		var args: Dictionary = story.get("args", {})
		play(&"crowd_cheer" if bool(args.get("passed", args.get("approved", true))) else &"crowd_boo")
	elif STORY_CUES.has(kind):
		play(STORY_CUES[kind])


# ── Casino ───────────────────────────────────────────────────────────────

## Listen to a casino table overlay's events.
func bind_casino(overlay: Node) -> void:
	_casino = overlay
	if overlay.has_signal("event_played"):
		overlay.connect("event_played", _on_casino_event)


func _on_casino_event(game: StringName, event: Dictionary) -> void:
	var kind := StringName(String(event.get("kind", "")))
	match kind:
		&"bet":
			play(&"chips_bet", 0.0, _rng.randf_range(0.95, 1.05), 0.08)
		&"hold":
			play(&"poker_hold")
		&"card":
			if game == &"video_poker":
				play(&"poker_deal", 0.0, 1.0, 0.4)
			else:
				play(&"card_deal", 0.0, _rng.randf_range(0.94, 1.06), 0.06)
		&"shuffle":
			play(&"card_shuffle")
		&"spin":
			play(&"roulette_spin" if game == &"roulette" else &"slot_spin")
		&"reel_stop":
			play(&"slot_reel_stop", 0.0, 1.0, 0.08)
		&"jackpot":
			play(&"coins_payout")
			play(&"resort_jackpot")
		&"wheel":
			play(&"money_wheel_spin")
		&"dice":
			play(&"dice_cage")
		&"launch":
			_trajectory_step = 10
			play(&"rocket_launch")
		&"crash":
			play(&"rocket_burnout")
		&"settle":
			match String(event.get("reaction", "")):
				"blackjack", "jackpot":
					play(&"casino_big_win")
				"win":
					play(&"casino_win")
					play(&"chips_collect", -2.0)
				"push":
					play(&"chips_collect", -4.0)
				_:
					play(&"casino_lose")


func _update_casino() -> void:
	if not is_instance_valid(_casino) or not _casino.call("is_open") or StringName(String(_casino.get("kind"))) != &"trajectory":
		return
	var stage: Node = _casino.get("stage")
	if not is_instance_valid(stage) or not stage.has_method("current_multiplier"):
		return
	var multiplier := float(stage.call("current_multiplier"))
	var step := int(floor(multiplier * 10.0))
	if step > _trajectory_step:
		_trajectory_step = step
		play(&"trajectory_tick", 0.0, clampf(0.8 + (multiplier - 1.0) * 0.25, 0.8, 2.6), 0.0)


# ── Buttons ──────────────────────────────────────────────────────────────

func _hook_tree(node: Node) -> void:
	_hook_node(node)
	for child in node.get_children():
		_hook_tree(child)


func _hook_node(node: Node) -> void:
	if _hooked.has(node.get_instance_id()):
		return
	if node is CheckBox or node is CheckButton:
		_hooked[node.get_instance_id()] = true
		(node as BaseButton).toggled.connect(func(_on: bool) -> void: play(&"toggle"))
	elif node is BaseButton:
		_hooked[node.get_instance_id()] = true
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))
	elif node is PopupMenu:
		_hooked[node.get_instance_id()] = true
		(node as PopupMenu).id_pressed.connect(func(_id: int) -> void: play(&"click"))


func _on_button_pressed(button: BaseButton) -> void:
	# Tool buttons have their own sound, sent from the toolbar's signal.
	var node: Node = button
	while node != null:
		if node is Toolbar:
			return
		node = node.get_parent()
	play(&"click")


## Stop every player before the host goes away, so no playback outlives it.
func _exit_tree() -> void:
	if _music != null:
		_music.stop()
	for voice in _voices:
		voice.stop()
	for player: AudioStreamPlayer in _loops.values():
		player.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_paused = true
		_apply_stream_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_paused = false
		_apply_stream_pause()
