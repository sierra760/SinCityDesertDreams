# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Terrain layer encoding and slope geometry helpers.
##
## A terrain byte holds a slope shape in its low nibble and a water kind in its
## high nibble. The fourteen slope shapes describe which of a tile's corners
## are raised.
class_name Terrain
extends RefCounted

## Slope shapes (low nibble). "Raised" means one level above the tile base.
## The numbering is the one imported city files use: edges first (west, north, east, south),
## then the three-corner valleys named by their one low corner, then the
## single raised corners, then the raised plateau.
const FLAT := 0
const SLOPE_W := 1        ## west edge raised
const SLOPE_N := 2        ## north edge raised
const SLOPE_E := 3
const SLOPE_S := 4
const VALLEY_SE := 5      ## three raised corners, south-east corner low
const VALLEY_SW := 6
const VALLEY_NW := 7
const VALLEY_NE := 8
const CORNER_NW := 9      ## single raised corner
const CORNER_NE := 10
const CORNER_SE := 11
const CORNER_SW := 12
const PLATEAU := 13       ## flat, one level above its base

const SLOPE_MASK := 0x0F
const WATER_MASK := 0xF0

## Water kinds (high nibble). Streams and the waterfall use the dry slope
## shapes but render as flowing water.
const DRY := 0x00
const SUBMERGED := 0x10   ## land under open water
const SHORE := 0x20       ## partially submerged slope
const SURFACE := 0x30     ## open water surface
const WATERFALL := 0x3E   ## whole code, not a nibble
const STREAM := 0x40      ## 0x40..0x45 are stream segments over flat land

const WIDTH := 128
const HEIGHT := 128


static func slope(code: int) -> int:
	return code & SLOPE_MASK


static func water_kind(code: int) -> int:
	if code == WATERFALL:
		return WATERFALL
	if code >= STREAM:
		return STREAM
	return code & WATER_MASK


static func is_water(code: int) -> bool:
	return code >= SUBMERGED


static func is_open_water(code: int) -> bool:
	var k := water_kind(code)
	return k == SURFACE or k == SUBMERGED


static func is_flat(code: int) -> bool:
	var s := slope(code)
	return s == FLAT or s == PLATEAU


static func make(slope_shape: int, water: int = DRY) -> int:
	return (water & WATER_MASK) | (slope_shape & SLOPE_MASK)


## Raised corners of a slope shape as a bitmask: 1=NE, 2=SE, 4=SW, 8=NW.
static func raised_corners(shape: int) -> int:
	match shape:
		FLAT: return 0
		SLOPE_W: return 8 | 4
		SLOPE_N: return 8 | 1
		SLOPE_E: return 1 | 2
		SLOPE_S: return 4 | 2
		VALLEY_SE: return 8 | 1 | 4
		VALLEY_SW: return 8 | 1 | 2
		VALLEY_NW: return 1 | 4 | 2
		VALLEY_NE: return 8 | 4 | 2
		CORNER_NW: return 8
		CORNER_NE: return 1
		CORNER_SE: return 2
		CORNER_SW: return 4
		PLATEAU: return 15
	return 0


## Edge slopes in compass order north, east, south, west: 0..3, or -1 when
## the shape is not a straight edge slope.
static func edge_index(shape: int) -> int:
	match shape:
		SLOPE_N: return 0
		SLOPE_E: return 1
		SLOPE_S: return 2
		SLOPE_W: return 3
	return -1


static func edge_shape(index: int) -> int:
	return [SLOPE_N, SLOPE_E, SLOPE_S, SLOPE_W][posmod(index, 4)]


static func is_edge_slope(shape: int) -> bool:
	return shape >= SLOPE_W and shape <= SLOPE_S


## Inverse of raised_corners. Returns -1 for corner sets that have no shape
## (two opposite corners raised).
static func shape_from_corners(mask: int) -> int:
	for s in range(PLATEAU + 1):
		if raised_corners(s) == mask:
			return s
	return -1
