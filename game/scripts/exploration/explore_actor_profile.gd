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
const WALK_HEIGHT := .115
const WALK_RADIUS := .018
## Entry reach, in tiles, from the walker's capsule to a vehicle's own body
## (4 m). Measured to the body, not its centre, so long buses and small
## cars are equally easy to get into.
const VEHICLE_REACH := .25
## Vertical band beyond the body, so a car on a bridge overhead is not
## reachable from the street below.
const VEHICLE_REACH_HEIGHT := .06

static func geometry(mode: int) -> Dictionary:
	var dimensions := [Vector3(.036,.115,.036),Vector3(.12,.08,.28),Vector3(.50,.14,.28)]
	var size: Vector3 = dimensions[clampi(mode,Mode.WALK,Mode.FLY)]
	return {"size":size,"foot_offset":size.y*.5,"step":.045,"margin":.001,
		"gravity":.613,"walk_speed":.09,"sprint_speed":.20,"car_speed":1.2,
		"flight_speed":1.5,"vertical_speed":.5}

static func shape(mode: int) -> Shape3D:
	if mode == Mode.WALK:
		var capsule := CapsuleShape3D.new()
		capsule.height = WALK_HEIGHT
		capsule.radius = WALK_RADIUS
		return capsule
	var box := BoxShape3D.new()
	box.size = geometry(mode).size
	return box

## Horizontal gap from a walker standing at `feet` (its capsule surface) to the
## nearest point of a body whose local envelope is `bounds` at `body`. Zero or
## less when the walker touches or stands inside the footprint; INF when the
## body lies above or below the walker beyond VEHICLE_REACH_HEIGHT.
static func reach_gap(feet: Vector3, body: Transform3D, bounds: AABB) -> float:
	var centre := feet+Vector3.UP*WALK_HEIGHT*.5
	var local := body.affine_inverse()*centre
	var nearest := body*local.clamp(bounds.position,bounds.end)
	var gap := centre-nearest
	if absf(gap.y) > WALK_HEIGHT*.5+VEHICLE_REACH_HEIGHT: return INF
	return Vector2(gap.x,gap.z).length()-WALK_RADIUS
