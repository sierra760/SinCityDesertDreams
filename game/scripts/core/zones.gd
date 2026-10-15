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
const AGR_LOW := 10
const AGR_HIGH := 11

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
	AGR_LOW: "Low-density Agriculture",
	AGR_HIGH: "High-density Agriculture",
}

## Traditional U.S. planning land-use colors, tuned for the desert presentation.
## Keep these literal hex tokens: tools/build_ui_icons.py reads them when authoring SVGs.
const COLOR_RES_LOW := Color("f2cf57")
const COLOR_RES_HIGH := Color("b78538")
const COLOR_COM_LOW := Color("e68a80")
const COLOR_COM_HIGH := Color("ba4548")
const COLOR_IND_LOW := Color("b99bd8")
const COLOR_IND_HIGH := Color("8054a6")
const COLOR_MILITARY := Color("d99bae")
const COLOR_AIRPORT := Color("acb2b8")
const COLOR_SEAPORT := Color("747c84")
const COLOR_AGR_LOW := Color("b7c985")
const COLOR_AGR_HIGH := Color("71884a")
const COLORS := {
	RES_LOW: COLOR_RES_LOW, RES_HIGH: COLOR_RES_HIGH,
	COM_LOW: COLOR_COM_LOW, COM_HIGH: COLOR_COM_HIGH,
	IND_LOW: COLOR_IND_LOW, IND_HIGH: COLOR_IND_HIGH,
	AGR_LOW: COLOR_AGR_LOW, AGR_HIGH: COLOR_AGR_HIGH,
	MILITARY: COLOR_MILITARY, AIRPORT: COLOR_AIRPORT, SEAPORT: COLOR_SEAPORT,
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


static func is_agricultural(zone_kind: int) -> bool:
	return zone_kind == AGR_LOW or zone_kind == AGR_HIGH


## RCI-only domain: ZoneParams uses this to index its three-component vectors.
static func is_growth_zone(zone_kind: int) -> bool:
	return zone_kind >= RES_LOW and zone_kind <= IND_HIGH


static func is_dense(zone_kind: int) -> bool:
	return zone_kind == RES_HIGH or zone_kind == COM_HIGH or zone_kind == IND_HIGH or zone_kind == AGR_HIGH


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
