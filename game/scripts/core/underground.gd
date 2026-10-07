# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Underground network codes.
##
## The `underground` layer stores one byte per tile. Codes are connection
## masks (N=1, E=2, S=4, W=8) so the builder and the utility systems can reason
## about them directly: pipes use the mask itself (1..15), subways the mask
## plus 15 (16..30). Four crossing codes and the station link follow. Imported
## city files store underground pieces in shape order (straight, corners, tees,
## cross) instead; from_art_code converts them on import.
class_name Underground
extends RefCounted

const NONE := 0
const PIPE_FIRST := 1
const PIPE_LAST := 15
const SUBWAY_FIRST := 16
const SUBWAY_LAST := 30
const SUBWAY_OFFSET := 15
const PIPE_NS_UNDER_SUBWAY_EW := 31
const PIPE_EW_UNDER_SUBWAY_NS := 32
const PIPE_NS_OVER_SUBWAY_EW := 33
const PIPE_EW_OVER_SUBWAY_NS := 34
const STATION_LINK := 35

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

## Connection mask for each shape index (1..15). Shape order: 1 east-west,
## 2 north-south, 3..6 sloped straights (unused underground), 7 south-east,
## 8 south-west, 9 north-west, 10 north-east, 11 tee open west, 12 tee open
## north, 13 tee open east, 14 tee open south, 15 four-way.
const MASK_OF_SHAPE := {
	1: 10, 2: 5, 3: 5, 4: 10, 5: 5, 6: 10,
	7: 6, 8: 12, 9: 9, 10: 3,
	11: 7, 12: 14, 13: 13, 14: 11,
	15: 15,
}


static func is_pipe(code: int) -> bool:
	return code >= PIPE_FIRST and code <= PIPE_LAST


static func is_subway(code: int) -> bool:
	return code >= SUBWAY_FIRST and code <= SUBWAY_LAST


static func is_crossing(code: int) -> bool:
	return code >= PIPE_NS_UNDER_SUBWAY_EW and code <= PIPE_EW_OVER_SUBWAY_NS


static func pipe_code(mask: int) -> int:
	return clampi(mask & 0x0F, PIPE_FIRST, PIPE_LAST)


static func subway_code(mask: int) -> int:
	return clampi(mask & 0x0F, PIPE_FIRST, PIPE_LAST) + SUBWAY_OFFSET


## A shape-ordered code (subways 1..15, pipes 16..30) as a mask-based one.
## Used when importing classic city files, whose underground layer is shape
## ordered.
static func from_art_code(code: int) -> int:
	if code >= 1 and code <= 15:
		return subway_code(int(MASK_OF_SHAPE.get(code, 5)))
	if code >= 16 and code <= 30:
		return pipe_code(int(MASK_OF_SHAPE.get(code - 15, 5)))
	return code
