# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore keeps its own clock: the city's simulation is held from entry to
## return (no days, no random draws), the chosen speed survives and resumes,
## and Explore's own ambient traffic keeps moving while the city waits.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://test_explore_city_clock.cfg"
var host: GameHost

func before_each() -> void:
	root.size = Vector2i(1280,800)
	host = MAIN.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)

func after_each() -> void:
	if host.exploration.is_active(): host.return_to_build()
	if host.sim._ctx != null: host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await physics_frame

func _play(speed: int) -> void:
	var city := flat_city()
	city.building.put(10,10,30)
	host.begin_city(city,{},4242,CityStats.new())
	host.city_view_3d.set_camera_state(Vector3(10.5,4*CityGeometry3D.HEIGHT,10.5),1,12.0)
	host.sim.set_speed(speed)
	await physics_frame

## Wait real time so a running city would advance several days.
func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds*1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func _run_explore_clock() -> void:
	if host.exploration.is_suspended(): host.exploration.resume()

func test_running_city_holds_while_exploring_and_resumes_on_return() -> void:
	await _play(GameClock.Speed.FAST)
	await _wait(.4)
	var day_before_entry := host.sim.clock.day
	check_gt(day_before_entry,0,"a Fast city advances days before Explore")
	check(host.enter_explore(),"Main enters Explore")
	if not host.exploration.is_active(): return
	var city_before := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var sim_before := host.sim.snapshot().duplicate(true)
	check(not host.sim.is_processing(),"the simulation is held while exploring")
	check_eq(host.sim.speed,GameClock.Speed.FAST,"the chosen speed is remembered, not discarded")
	check_eq(host.status_bar.speed_label.text,"Paused","the footer shows the city paused")
	var day_in_explore := host.sim.clock.day
	_run_explore_clock()
	await _wait(.6)
	check_eq(host.sim.clock.day,day_in_explore,"no days pass while exploring")
	check_eq(SaveFormat.encode_city(host.sim.city),city_before,"no city change while exploring")
	check_eq(host.sim.snapshot(),sim_before,"no simulated days or random draws while exploring")
	host.return_to_build()
	check(host.sim.is_processing(),"returning releases the hold")
	check_eq(host.sim.speed,GameClock.Speed.FAST)
	check_eq(host.status_bar.speed_label.text,"Fast","the footer shows the resumed speed")
	var day_on_return := host.sim.clock.day
	await _wait(.4)
	check_gt(host.sim.clock.day,day_on_return,"the city runs again after returning")

func test_speed_chosen_while_exploring_takes_effect_on_return() -> void:
	await _play(GameClock.Speed.PAUSED)
	check(host.enter_explore())
	if not host.exploration.is_active(): return
	var day_in_explore := host.sim.clock.day
	host.sim.set_speed(GameClock.Speed.MEDIUM)
	check_eq(host.status_bar.speed_label.text,"Paused","a new speed does not start the city during Explore")
	check(not host.sim.is_processing())
	_run_explore_clock()
	await _wait(.5)
	check_eq(host.sim.clock.day,day_in_explore,"Medium chosen in Explore still runs no days")
	host.return_to_build()
	check_eq(host.sim.speed,GameClock.Speed.MEDIUM)
	check_eq(host.status_bar.speed_label.text,"Medium")
	check(host.sim.is_processing())

func test_modal_during_explore_keeps_the_hold_and_speed() -> void:
	await _play(GameClock.Speed.SLOW)
	check(host.enter_explore())
	if not host.exploration.is_active(): return
	host.push_modal()
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	host.pop_modal()
	check_eq(host.sim.speed,GameClock.Speed.SLOW,"the modal restores the remembered speed")
	check(not host.sim.is_processing(),"closing a modal does not release Explore's hold")
	check_eq(host.status_bar.speed_label.text,"Paused")
	host.return_to_build()
	check(host.sim.is_processing())
	check_eq(host.status_bar.speed_label.text,"Slow")

func test_explore_traffic_runs_on_explore_clock_while_city_paused() -> void:
	await _play(GameClock.Speed.PAUSED)
	var traffic: CityTraffic3D = host.city_view_3d.traffic
	check(traffic != null,"the view has ambient traffic")
	if traffic == null: return
	var build_elapsed := traffic._elapsed
	await _wait(.3)
	check_eq(traffic._elapsed,build_elapsed,"a paused city's Build view holds its traffic")
	check(host.enter_explore())
	if not host.exploration.is_active(): return
	_run_explore_clock()
	check(not host.exploration.is_suspended(),"Explore's clock is running")
	var elapsed := traffic._elapsed
	await _wait(.3)
	check_gt(traffic._elapsed,elapsed,"Explore's traffic moves although the city is paused")
	check(traffic.records_held,"city-owned records stay where the last day left them")
	host.exploration.pause()
	await process_frame
	var paused_elapsed := traffic._elapsed
	await _wait(.3)
	check_eq(traffic._elapsed,paused_elapsed,"pausing Explore pauses its traffic")
	host.return_to_build()
	await process_frame
	check(traffic.records_held,"a paused city still holds its records in Build")
	host.sim.set_speed(GameClock.Speed.SLOW)
	await process_frame
	check(not traffic.records_held,"a running city moves its records again")
