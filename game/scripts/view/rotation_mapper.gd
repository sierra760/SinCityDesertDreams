# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Maps between canonical city tiles and a rotated top-down screen grid.
##
## The city keeps one canonical orientation. Views that draw the map turned by
## quarter steps (the minimap and the 3D view's minimap footprint) convert
## coordinates here so they agree on which tile sits where.
class_name RotationMapper
extends RefCounted

## Per-tile axis flag for single-axis pieces (bridges, piers, runways, ramps).
## When set, the piece runs along its other axis. The city stores it in the
## flags layer.
const AXIS_FLAG := TileFlags.RESERVED_A


## Screen grid cell -> canonical data tile.
static func screen_to_data(sx: int, sy: int, r: int) -> Vector2i:
	match posmod(r, 4):
		1: return Vector2i(City.WIDTH - 1 - sy, sx)
		2: return Vector2i(City.WIDTH - 1 - sx, City.HEIGHT - 1 - sy)
		3: return Vector2i(sy, City.HEIGHT - 1 - sx)
	return Vector2i(sx, sy)


## Canonical data point -> screen grid point; fractional positions are kept.
static func data_to_screen(d: Vector2, r: int) -> Vector2:
	var w := float(City.WIDTH)
	var h := float(City.HEIGHT)
	match posmod(r, 4):
		1: return Vector2(d.y, w - 1.0 - d.x)
		2: return Vector2(w - 1.0 - d.x, h - 1.0 - d.y)
		3: return Vector2(h - 1.0 - d.y, d.x)
	return d


static func data_to_screen_i(d: Vector2i, r: int) -> Vector2i:
	var s := data_to_screen(Vector2(d), r)
	return Vector2i(roundi(s.x), roundi(s.y))
