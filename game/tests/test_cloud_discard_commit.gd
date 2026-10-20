# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
## A failed deferred Don't Save must retain the open city and retryable intent.
const MainScene := preload("res://scenes/main.tscn")
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
class IOSHost extends GameHost:
	func can_quit_application() -> bool:
		return false
class FailingStore extends CloudSaveStore:
	var fail := false
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail else super._write_journal(bytes)
var host: GameHost
var store: FailingStore
var cloud: CloudSaveSession
var directory: String
var manual: String
var old_city: City
var old_slot: String
var saved_funds: int

func before_each() -> void:
	directory = "user://discard-commit/" + CloudSaveTypes.uuid()
	store = FailingStore.new(directory)
	check_eq(store.open_library(""), OK)
	var fake := Fake.new()
	var coordinator := CloudSaveCoordinator.new(store, fake)
	host = MainScene.instantiate()
	host.set_script(IOSHost)
	cloud = CloudSaveSession.new(host, coordinator, store)
	host.cloud_saves = cloud
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	current_scene = host
	host.set_process(false)
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	coordinator.set_enabled(true)
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("account"), {"owner": "a".repeat(64)})
	coordinator.advance(Time.get_ticks_msec())
	manual = host.files.save_city_as("discard-commit-" + CloudSaveTypes.uuid())
	check(not manual.is_empty())
	old_city = host.sim.city
	old_slot = cloud.slot_id
	saved_funds = old_city.funds
	old_city.funds -= 123
	check_eq(cloud.capture(&"test"), OK)
	coordinator.set_enabled(false)
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"discard")
	check(host.new_city_dialog.is_open())
	store.fail = true

func after_each() -> void:
	store.fail = false
	if is_instance_valid(current_scene): current_scene.free()
	if is_instance_valid(host): host.free()
	DirAccess.remove_absolute(manual)
	await process_frame

func _check_preserved() -> void:
	check_eq(host.sim.city, old_city, "the live city survives the refused replacement")
	check_eq(host.save_path, manual, "its save destination survives")
	check_eq(cloud.slot_id, old_slot, "its cloud identity survives")
	check(cloud._inert_discard_pending, "the failed discard remains retryable")
	check_eq(SaveFormat.load(manual).city.funds, saved_funds, "the named save is untouched")
	check(host.notice_dialog.is_open(), "the failure is visible")

func test_failed_session_end_keeps_discard_for_retry() -> void:
	check_eq(cloud.call("end_session"), ERR_CANT_CREATE)
	check(cloud._current(), "the session remains attached after a journal failure")
	check(cloud._inert_discard_pending)
	store.fail = false
	check_eq(cloud.call("end_session"), OK)
	check_eq(SaveFormat.load(store._state.slots[old_slot].continuation.path).city.funds, saved_funds)

func test_failed_replacement_keeps_city_then_retries() -> void:
	var next := flat_city()
	host.begin_city(next, {}, 3, null)
	_check_preserved()
	store.fail = false
	host.notice_dialog.dismiss()
	host.begin_city(next, {}, 3, null)
	check_eq(host.sim.city, next)
	check_eq(SaveFormat.load(store._state.slots[old_slot].continuation.path).city.funds, saved_funds, "retry commits the original Don't Save")

func test_failed_new_city_does_not_enter_editing_or_clear_save() -> void:
	check_eq(host.start_new_city({"seed": 3}, flat_city()), null)
	_check_preserved()
	check_eq(host.stage, GameHost.Stage.PLAY)
	check(host.editing_params.is_empty())

func test_failed_load_keeps_city_and_save_destination() -> void:
	var path := directory.path_join("replacement.sc2d")
	check_eq(SaveFormat.save(path, flat_city()), OK)
	check(not host.load_city(path))
	_check_preserved()

func test_final_discard_reports_failure_after_cancellable_choice() -> void:
	check_eq(cloud.discard(false), ERR_CANT_CREATE, "a subsequent Quit cannot bypass the pending choice")
	check_eq(host.sim.city, old_city)
	check(cloud._inert_discard_pending)

func test_cancel_after_failed_new_city_keeps_edited_checkpoint() -> void:
	var journal := store.journal_path()
	var before := FileAccess.get_sha256(journal)
	check(not before.is_empty(), "fixture has a durable verified-account journal")
	host.new_city_dialog.start()
	_check_preserved()
	check(not host.new_city_dialog.is_open())
	host.notice_dialog.dismiss()
	cloud.tick(0.0)
	check_eq(host.sim.city, old_city)
	check_eq(host.save_path, manual)
	check_eq(cloud.slot_id, old_slot)
	check(not cloud._inert_discard_pending)
	check(not cloud._discarded, "cancelling the leave resumes the same session")
	check_eq(SaveFormat.load(store._state.slots[old_slot].continuation.path).city.funds, saved_funds - 123)
	check_eq(FileAccess.get_sha256(journal), before, "cancelling with sync off performs no journal write")

func test_failed_close_keeps_host_and_simulation_attached() -> void:
	host.files._quit_now()
	await process_frame
	check(is_instance_valid(host), "Close City must not free the host after a discard failure")
	if not is_instance_valid(host): return
	check_eq(current_scene, host)
	check(host.sim.is_processing(), "the refused close does not stop simulation processing")
	_check_preserved()
