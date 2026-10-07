# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Simulation systems on lots saved at another rotation: their corner flags
## sit shifted around the ring, so CORNER_NW is not on the top-left tile.
## Every system that needs a lot's position must use its anchor and give the
## same results as the same lots stored in this game's own orientation.
extends "res://tests/test_case.gd"

const Rotated := preload("res://tests/test_rotated_footprints.gd")
const RewardSystemScript := preload("res://scripts/sim/reward_system.gd")

const PRISON_AT := Vector2i(40, 40)
const STATION_AT := Vector2i(60, 40)
## Far enough west that its pollution reaches only the edge of the treatment
## plant's reach, which a misplaced anchor would shift.
const PLANT_AT := Vector2i(64, 80)
## On odd coordinates so a misplaced anchor lands in another pollution block.
const TREATMENT_AT := Vector2i(85, 81)


func make_ctx(c: City, seed_value: int = 11) -> SimContext:
	return make_context(c, seed_value)


static func power_lot(c: City, at: Vector2i, id: int) -> void:
	var s := Buildings.size(id)
	for dy in s.y:
		for dx in s.x:
			c.set_flag(at.x + dx, at.y + dy, TileFlags.POWERED, true)


## A prison and a police station with records, a polluting plant and a water
## treatment plant, each lot's corner flags turned `turn` steps.
func _service_city(turn: int, powered: bool = true) -> City:
	var c := flat_city()
	for entry: Array in [[PRISON_AT, Buildings.PRISON], [STATION_AT, Buildings.POLICE_STATION],
			[PLANT_AT, Buildings.COAL_PLANT], [TREATMENT_AT, Buildings.WATER_TREATMENT]]:
		var at: Vector2i = entry[0]
		var id: int = entry[1]
		Rotated.stamp_rotated(c, at, id, Zones.NONE, turn)
		c.add_facility(at, {"key": Buildings.key(id), "built_day": 0})
		if powered:
			power_lot(c, at, id)
	for by in range(15, 30):
		for bx in range(15, 30):
			c.crime.put(bx, by, 120)
	return c


func test_services_use_the_lot_anchor_in_every_rotation() -> void:
	var reference_police := PackedByteArray()
	var reference_prison := {}
	for turn in 4:
		var c := _service_city(turn)
		var services := ServicesSystem.new()
		services.monthly(make_ctx(c))
		var report: Dictionary = services.prison_report()
		check_eq(int(report["prisons"]), 1, "turn %d one prison" % turn)
		var records: Array = report["records"]
		if records.size() != 1:
			continue
		var rec: Dictionary = records[0]
		check_eq(Vector2i(int(rec["x"]), int(rec["y"])), PRISON_AT, "turn %d prison keyed by its anchor" % turn)
		check(bool(rec["powered"]), "turn %d prison powered" % turn)
		check_gt(int(rec["inmates"]), 0, "turn %d prison takes arrests" % turn)
		check_eq(int(c.facility(PRISON_AT).get("inmates", -1)), int(rec["inmates"]),
			"turn %d prison facility record mirrors the inmates" % turn)
		check_eq(services.police_modifier(), 1, "turn %d powered prison helps the police" % turn)
		if turn == 0:
			reference_police = c.police.data.duplicate()
			reference_prison = rec
		else:
			check_eq(c.police.data, reference_police, "turn %d police coverage matches the unrotated station" % turn)
			check_eq(rec, reference_prison, "turn %d prison record matches the unrotated prison" % turn)


func test_services_power_reads_only_the_lot() -> void:
	# Turn 2 puts CORNER_NW on the bottom-right tile; power ground just past
	# that corner, outside the lot, and leave the lot itself unpowered.
	var c := _service_city(2, false)
	var s := Buildings.size(Buildings.PRISON)
	var far := PRISON_AT + s - Vector2i.ONE
	for dy in range(1, s.y):
		for dx in range(1, s.x):
			c.set_flag(far.x + dx, far.y + dy, TileFlags.POWERED, true)
	var services := ServicesSystem.new()
	services.monthly(make_ctx(c))
	var records: Array = services.prison_report()["records"]
	check_eq(records.size(), 1)
	if records.size() == 1:
		check(not bool(records[0]["powered"]), "power beside the lot does not reach the prison")
	check_eq(services.police_modifier(), 0, "an unpowered prison gives no police bonus")


func test_water_treatment_works_in_every_rotation() -> void:
	var reference := PackedByteArray()
	var untreated := PackedByteArray()
	for turn in 4:
		var c := _service_city(turn)
		var env := EnvironmentSystem.new()
		env.monthly(make_ctx(c))
		if turn == 0:
			reference = c.pollution.data.duplicate()
			var bare := _service_city(0)
			bare.clear_footprint(TREATMENT_AT.x, TREATMENT_AT.y)
			var bare_env := EnvironmentSystem.new()
			bare_env.monthly(make_ctx(bare))
			untreated = bare.pollution.data.duplicate()
			check_ne(reference, untreated, "the treatment plant changes pollution")
		else:
			check_eq(c.pollution.data, reference, "turn %d pollution matches the unrotated plant" % turn)


func test_rotated_arcology_anchor() -> void:
	var at := Vector2i(30, 30)
	for turn in 4:
		var c := flat_city()
		Rotated.stamp_rotated(c, at, Buildings.ARCOLOGY_COMSTOCK, Zones.NONE, turn)
		var anchors := RewardSystemScript._arcology_anchors(c)
		check_eq(anchors, [at] as Array[Vector2i], "turn %d arcology found at its anchor" % turn)


func test_rotated_residential_lot_starts_trips_at_its_anchor() -> void:
	var at := Vector2i(20, 20)
	for turn in 4:
		var c := flat_city()
		Rotated.stamp_rotated(c, at, Buildings.RES_2X2_FIRST, Zones.RES_HIGH, turn)
		c.stamp_building(50, 50, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		var origins := TransportSystem.new()._collect_origins(c)
		check_eq(origins, PackedInt32Array([at.y * City.WIDTH + at.x, 50 * City.WIDTH + 50]),
			"turn %d origins at each lot's anchor" % turn)


func test_rotated_civic_power_read_at_anchor() -> void:
	# Turn 2: CORNER_NW is on the bottom-right tile. Only the anchor is powered.
	for turn in 4:
		var c := flat_city()
		Rotated.stamp_rotated(c, PRISON_AT, Buildings.HOSPITAL, Zones.NONE, turn)
		c.set_flag(PRISON_AT.x, PRISON_AT.y, TileFlags.POWERED, true)
		var ctx := make_ctx(c)
		var population := PopulationSystem.new()
		population._run_census(ctx)
		check_eq(int(population._census["hospitals"]), 1, "turn %d powered hospital counted" % turn)
