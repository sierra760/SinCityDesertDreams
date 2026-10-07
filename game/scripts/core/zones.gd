# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Zone layer encoding.
##
## The low nibble is the zone kind. The high nibble marks which corners of a
## building footprint this tile occupies, which is how multi-tile lots find
## their anchor without a separate index.
class_name Zones
extends RefCounted

const NONE := 0
const RES_LOW := 1
const RES_HIGH := 2
const COM_LOW := 3
const COM_HIGH := 4
const IND_LOW := 5
const IND_HIGH := 6
const MILITARY := 7
const AIRPORT := 8
const SEAPORT := 9

const KIND_MASK := 0x0F

## Footprint corner flags. A 1×1 lot sets all four.
const CORNER_NW := 0x10
const CORNER_NE := 0x20
const CORNER_SE := 0x40
const CORNER_SW := 0x80
const CORNER_MASK := 0xF0
const ALL_CORNERS := 0xF0

const NAMES := {
	NONE: "Unzoned",
	RES_LOW: "Light Residential",
	RES_HIGH: "Dense Residential",
	COM_LOW: "Light Commercial",
	COM_HIGH: "Dense Commercial",
	IND_LOW: "Light Industrial",
	IND_HIGH: "Dense Industrial",
	MILITARY: "Military",
	AIRPORT: "Airport",
	SEAPORT: "Seaport",
}


static func kind(code: int) -> int:
	return code & KIND_MASK


static func corners(code: int) -> int:
	return code & CORNER_MASK


static func make(zone_kind: int, corner_flags: int = ALL_CORNERS) -> int:
	return (corner_flags & CORNER_MASK) | (zone_kind & KIND_MASK)


static func is_residential(zone_kind: int) -> bool:
	return zone_kind == RES_LOW or zone_kind == RES_HIGH


static func is_commercial(zone_kind: int) -> bool:
	return zone_kind == COM_LOW or zone_kind == COM_HIGH


static func is_industrial(zone_kind: int) -> bool:
	return zone_kind == IND_LOW or zone_kind == IND_HIGH


static func is_growth_zone(zone_kind: int) -> bool:
	return zone_kind >= RES_LOW and zone_kind <= IND_HIGH


static func is_dense(zone_kind: int) -> bool:
	return zone_kind == RES_HIGH or zone_kind == COM_HIGH or zone_kind == IND_HIGH


static func is_port(zone_kind: int) -> bool:
	return zone_kind == AIRPORT or zone_kind == SEAPORT


## Corner flags for the tile at (dx, dy) inside a w×h footprint.
static func corner_flags_for(dx: int, dy: int, w: int, h: int) -> int:
	var f := 0
	if dx == 0 and dy == 0: f |= CORNER_NW
	if dx == w - 1 and dy == 0: f |= CORNER_NE
	if dx == w - 1 and dy == h - 1: f |= CORNER_SE
	if dx == 0 and dy == h - 1: f |= CORNER_SW
	return f
