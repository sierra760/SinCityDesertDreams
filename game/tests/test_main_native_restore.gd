# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Native reload must restore a saved simulation, not initialize a new one.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://test_main_native_restore.cfg"
const SAVE := "user://test_main_native_restore.sc2d"
const WIND := Vector2i(10, 10)
const SOLAR := Vector2i(30, 30)
var host: GameHost


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)


func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	host = null
	for path in [PREFS, SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await physics_frame


func _play_power_city() -> void:
	var city := flat_city(20000, 17)
	city.name = "Native restoration"
	city.stamp_building(WIND.x, WIND.y, Buildings.WIND_PLANT)
	city.stamp_building(SOLAR.x, SOLAR.y, Buildings.SOLAR_PLANT)
	city.stamp_building(11, 10, Buildings.RES_1X1_FIRST)
	host.begin_city(city, {}, 4242, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)


## Use the engine's raw signed seed assignment, deliberately bypassing the
## new-city negative sentinel. This is legal persisted data, including -1.
func _set_raw_seed(seed_value: int) -> void:
	host.sim.rng._rng.seed = seed_value
	for draw in 5:
		host.sim.rng.range_int(0, 1000000)


func test_main_reload_preserves_raw_signed_seed_state_and_next_draws() -> void:
	_play_power_city()
	for raw_seed: int in [-6917706731718869851, -9223372036854775807, -1, 0, 4242]:
		_set_raw_seed(raw_seed)
		var runtime := host.sim.snapshot().duplicate(true)
		var city := SaveFormat.encode_city(host.sim.city).duplicate(true)
		var expected := RandomNumberGenerator.new()
		expected.seed = raw_seed
		expected.state = host.sim.rng.state()
		check_eq(host.files.write_save(SAVE), OK, "real Main writes native save")
		var decoded := SaveFormat.load(SAVE)
		check(bool(decoded.ok))
		check_eq(decoded.snapshot.rng_seed, str(raw_seed), "JSON preserves signed64-bit seed string")
		check_eq(decoded.snapshot.rng_state, runtime.rng_state, "JSON preserves signed64-bit state string")
		check(host.load_city(SAVE), "real Main native load succeeds")
		check_eq(host.sim.rng.seed_value(), raw_seed, "saved seed is raw data, including negative values")
		check_eq(host.sim.rng.state(), int(runtime.rng_state), "saved stream state is exact")
		check(host.sim.snapshot() == runtime, "complete runtime restored for seed %s" % raw_seed)
		check(SaveFormat.encode_city(host.sim.city) == city, "complete city restored for seed %s" % raw_seed)
		for draw in 12:
			check_eq(host.sim.rng.range_int(-1000000, 1000000), expected.randi_range(-1000000, 1000000),
				"next draw %d for signed seed %s" % [draw, raw_seed])


func test_saved_power_capacity_flags_summary_and_scheduled_continuation() -> void:
	_play_power_city()
	var power := host.sim.get_system(&"power") as PowerSystem
	var saved_city := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var saved_runtime := host.sim.snapshot().duplicate(true)
	var summary := power.network_summary()
	var wind_capacity := int(host.sim.city.facility(WIND).capacity)
	var solar_capacity := int(host.sim.city.facility(SOLAR).capacity)
	check_eq(host.files.write_save(SAVE), OK)
	# The uninterrupted branch reaches the next ordinary scheduled power pass.
	host.sim.advance_day()
	var continued_city := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var continued_runtime := host.sim.snapshot().duplicate(true)
	var continued_summary := power.network_summary()
	for repeat in 3:
		check(host.load_city(SAVE), "repeat native reload %d" % repeat)
		power = host.sim.get_system(&"power") as PowerSystem
		check_eq(host.sim.city.facility(WIND).capacity, wind_capacity, "saved wind generation retained")
		check_eq(host.sim.city.facility(SOLAR).capacity, solar_capacity, "saved solar generation retained")
		check_eq(power.plant_capacity(WIND), wind_capacity, "wind cache agrees with saved facility")
		check_eq(power.plant_capacity(SOLAR), solar_capacity, "solar cache agrees with saved facility")
		check_eq(power.network_summary(), summary, "summary uses saved generation and powered flags")
		check(SaveFormat.encode_city(host.sim.city) == saved_city, "all saved city fields/layers remain exact")
		check(host.sim.snapshot() == saved_runtime, "all saved runtime fields remain exact")
		host.sim.advance_day()
		check(SaveFormat.encode_city(host.sim.city) == continued_city, "next scheduled pass matches uninterrupted city")
		check(host.sim.snapshot() == continued_runtime, "next scheduled pass matches uninterrupted runtime")
		check_eq(power.network_summary(), continued_summary)


func test_new_city_and_native_save_without_power_runtime_keep_initialization() -> void:
	_play_power_city()
	var expected_city := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var expected_runtime := host.sim.snapshot().duplicate(true)
	# Empty snapshots are the new/import path, and must still initialize output.
	var city := flat_city(20000, 17)
	city.name = "Native restoration"
	city.stamp_building(WIND.x, WIND.y, Buildings.WIND_PLANT)
	city.stamp_building(SOLAR.x, SOLAR.y, Buildings.SOLAR_PLANT)
	city.stamp_building(11, 10, Buildings.RES_1X1_FIRST)
	host.begin_city(city, {}, 4242, CityStats.new())
	check(SaveFormat.encode_city(host.sim.city) == expected_city, "deterministic new/import initialization unchanged")
	check(host.sim.snapshot() == expected_runtime, "new/import runtime initialization unchanged")
	var legacy := host.sim.snapshot().duplicate(true)
	legacy.systems.erase("power")
	host.sim.city.facility(WIND).capacity = -999
	host.sim.city.facility(SOLAR).capacity = -999
	check_eq(SaveFormat.save(SAVE, host.sim.city, legacy), OK)
	check(host.load_city(SAVE))
	check_ge(int(host.sim.city.facility(WIND).capacity), 8, "legacy missing power state initializes wind")
	check_ge(int(host.sim.city.facility(SOLAR).capacity), 80, "legacy missing power state initializes solar")
	var power := host.sim.get_system(&"power") as PowerSystem
	check_eq(power.plant_capacity(WIND), host.sim.city.facility(WIND).capacity)
	check_eq(power.plant_capacity(SOLAR), host.sim.city.facility(SOLAR).capacity)
