# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Real Main import/native-load checks using a synthetic classic city file.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const RewardSystem := preload("res://scripts/sim/reward_system.gd")
const CLASSIC := "user://test_imported_rewards.sc2"
const NATIVE := "user://test_imported_rewards.sc2d"
const PREFS := "user://test_imported_rewards.cfg"
const GIFTS := [
	[243, Vector2i(12, 20), Vector2i(2, 2), &"mayors_residence", Tools.Kind.REWARD_MAYORS_RESIDENCE],
	[208, Vector2i(28, 20), Vector2i(3, 3), &"city_hall", Tools.Kind.REWARD_CITY_HALL],
	[219, Vector2i(44, 20), Vector2i(1, 1), &"monument", Tools.Kind.REWARD_MONUMENT],
	[255, Vector2i(60, 20), Vector2i(4, 4), &"neon_dome", Tools.Kind.REWARD_NEON_DOME],
]
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
	for path in [CLASSIC, NATIVE, PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await physics_frame


static func _u32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255])


static func _chunk(tag: String, data: PackedByteArray) -> PackedByteArray:
	var packed := Sc2Import.rle_encode(data)
	var out := tag.to_ascii_buffer()
	out.append_array(_u32(packed.size()))
	out.append_array(packed)
	return out


func _write_classic(gift_count: int, military: bool) -> void:
	var altitude := PackedByteArray()
	altitude.resize(32768)
	for tile in 16384:
		altitude[2 * tile + 1] = 6
	var terrain := PackedByteArray()
	terrain.resize(16384)
	var buildings := PackedByteArray()
	buildings.resize(16384)
	var zones := PackedByteArray()
	zones.resize(16384)
	for index in gift_count:
		var gift: Array = GIFTS[index]
		var anchor: Vector2i = gift[1]
		var size: Vector2i = gift[2]
		for dy in size.y:
			for dx in size.x:
				# Classic columns and literal IDs/corner bits exercise import mapping.
				var tile := (anchor.x + dx) * 128 + anchor.y + dy
				buildings[tile] = gift[0]
				if dx == 0 and dy == 0: zones[tile] |= 0x10
				if dx == size.x - 1 and dy == 0: zones[tile] |= 0x20
				if dx == size.x - 1 and dy == size.y - 1: zones[tile] |= 0x40
				if dx == 0 and dy == size.y - 1: zones[tile] |= 0x80
	if military:
		zones[90 * 128 + 90] = 0xf7
		buildings[90 * 128 + 90] = 226
	var body := "SCDH".to_ascii_buffer()
	for entry in [["ALTM", altitude], ["XTER", terrain], ["XBLD", buildings], ["XZON", zones]]:
		body.append_array(_chunk(entry[0], entry[1]))
	var file := FileAccess.open(CLASSIC, FileAccess.WRITE)
	file.store_buffer("FORM".to_ascii_buffer())
	file.store_buffer(_u32(body.size()))
	file.store_buffer(body)
	file.close()


func _check_all_rewards_known() -> void:
	for gift in GIFTS:
		var anchor: Vector2i = gift[1]
		check_eq(host.sim.city.building_at(anchor.x, anchor.y), gift[0], "classic reward ID survives import/load")
		check(host.sim.stats.rewards_offered.get(gift[3], false), "%s already earned" % gift[3])
		check(host.sim.stats.rewards_built.get(gift[3], false), "%s already built" % gift[3])
		check(host.toolbar.is_locked(gift[4]), "standing %s cannot be placed twice" % gift[3])
	var rewards := host.sim.get_system(&"rewards") as RewardSystem
	check_eq(rewards.available(), [])
	check(host.sim.stats.rewards_offered.get(&"military_base", false))
	check(host.toolbar.is_locked(Tools.Kind.REWARD_MILITARY_BASE))
	check(not rewards.military_offer().pending)
	host.sim.stats.population = 130000
	var city_before := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var rng_before := host.sim.rng.state()
	for month in 8:
		host.sim.events.clear()
		rewards.monthly(host.sim._ctx)
		check_eq(host.sim.events.notices, [], "no duplicate reward proposal")
		check_eq(host.sim.events.news, [], "no duplicate milestone story")
	check_eq(SaveFormat.encode_city(host.sim.city), city_before, "reward detection preserves city data")
	check_eq(host.sim.rng.state(), rng_before, "known military base needs no random site search")


func test_main_import_and_native_reload_remember_existing_rewards() -> void:
	_write_classic(4, true)
	check(host.import_city(CLASSIC), "Main imports classic file")
	_check_all_rewards_known()
	check_eq(host.files.write_save(NATIVE), OK)
	check(host.load_city(NATIVE), "Main reloads native city")
	_check_all_rewards_known()


func test_main_legacy_native_load_repairs_missing_reward_history() -> void:
	_write_classic(4, true)
	check(host.import_city(CLASSIC))
	var legacy := host.sim.snapshot().duplicate(true)
	legacy.stats["rewards_offered"] = {}
	legacy.stats["rewards_built"] = {}
	legacy.systems["rewards"] = {"milestones_passed": 0}
	check_eq(SaveFormat.save(NATIVE, host.sim.city, legacy), OK)
	check(host.load_city(NATIVE))
	_check_all_rewards_known()


func test_main_import_keeps_missing_gift_buildable_at_its_milestone() -> void:
	_write_classic(2, false)
	check(host.import_city(CLASSIC))
	host.sim.stats.population = 30000
	var rewards := host.sim.get_system(&"rewards") as RewardSystem
	host.sim.events.clear()
	rewards.monthly(host.sim._ctx)
	check_eq(host.sim.events.notices.size(), 1)
	if not host.sim.events.notices.is_empty():
		check_eq(host.sim.events.notices[0].kind, &"reward_offered")
		check_eq(host.sim.events.notices[0].payload.key, &"monument")
	host.refresh_toolbar()
	check(host.toolbar.is_locked(Tools.Kind.REWARD_CITY_HALL))
	check(not host.toolbar.is_locked(Tools.Kind.REWARD_MONUMENT), "the missing gift is selectable")
	check_eq(rewards.available(), [&"monument"])

