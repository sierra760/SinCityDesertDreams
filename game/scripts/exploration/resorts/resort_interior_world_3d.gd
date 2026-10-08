# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One resort's casino floor: a closed hall in its own pocket under the lot,
## with props, lettering, lights and collision. Explore-only presentation; it
## never reads or writes city data after it is built.
class_name ResortInteriorWorld3D
extends Node3D

const Layouts := preload("res://scripts/exploration/resorts/resort_interior_layouts.gd")
const Dresser := preload("res://scripts/exploration/resorts/resort_prop_dresser.gd")
## Hall and props render on layer 21 only; the Explore sun excludes it.
const LAYER := 1 << 20

var key: StringName = &""
var code := 0
var anchor := Vector2i(-1,-1)
var plan: Dictionary = {}
## Build time of this hall in microseconds, for the performance report.
var build_usec := 0
var stats: Dictionary = {}
var _tables: Array[Dictionary] = []

## Build the hall for `resort_key` under the lot at `lot_anchor`.
func build(resort_key: StringName, building_code: int, lot_anchor: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	key = resort_key
	code = building_code
	anchor = lot_anchor
	name = "ResortInterior_%d_%d" % [anchor.x,anchor.y]
	plan = Layouts.layout(key)
	position = Layouts.hall_origin(anchor)
	stats = Dresser.populate(self,key,code,plan)
	build_usec = Time.get_ticks_usec()-started

## True when `feet` (world) is inside this hall's walkable volume.
func contains(feet: Vector3) -> bool:
	if not feet.is_finite(): return false
	return Layouts.POCKET_BOUNDS.has_point(feet-position)

func to_world(local: Transform3D) -> Transform3D:
	return Transform3D(local.basis,local.origin+position)

## World pose of the entrance mat, facing into the hall.
func mat_transform() -> Transform3D:
	return to_world(plan.entrance.mat)

## The plan's tables with world-space seat, camera and pose added. Built
## once per hall (the hall never moves); callers must not modify the records.
func tables() -> Array[Dictionary]:
	if not _tables.is_empty() or plan.is_empty(): return _tables
	for table: Dictionary in plan.tables:
		var placed := table.duplicate()
		placed.seat = Vector3(table.seat)+position
		placed.camera = to_world(table.camera)
		placed.pose = to_world(table.pose)
		placed.resort = key
		_tables.append(placed)
	return _tables
