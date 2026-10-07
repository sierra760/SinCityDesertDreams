# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Tile-scale actor geometry. Root transforms locate feet, shapes locate centres.
class_name ExploreActorProfile
extends RefCounted

enum Mode { WALK, DRIVE, FLY }
const FLOOR := 8
const OBSTACLE := 16
const ACTOR := 32
const WORLD := 4 | FLOOR | OBSTACLE
const METRES_PER_TILE := 16.0

static func geometry(mode: int) -> Dictionary:
	var dimensions := [Vector3(.036,.115,.036),Vector3(.12,.08,.28),Vector3(.50,.14,.28)]
	var size: Vector3 = dimensions[clampi(mode,Mode.WALK,Mode.FLY)]
	return {"size":size,"foot_offset":size.y*.5,"step":.045,"margin":.001,
		"gravity":.613,"walk_speed":.09,"sprint_speed":.20,"car_speed":1.2,
		"flight_speed":1.5,"vertical_speed":.5}

static func shape(mode: int) -> Shape3D:
	if mode == Mode.WALK:
		var capsule := CapsuleShape3D.new()
		capsule.height = .115
		capsule.radius = .018
		return capsule
	var box := BoxShape3D.new()
	box.size = geometry(mode).size
	return box
