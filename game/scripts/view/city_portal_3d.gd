# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Visual entrance contract shared by terrain cutouts and transport geometry.
## No stored city state or simulation height is changed by this projection.
class_name CityPortal3D
extends RefCounted


## Local XY coordinates map to world XZ. The opening is the rectangle
## outside + inward * d + across * s, 0 <= d <= depth, |s| <= width / 2.
## floor_start/floor_end are absolute world Y at d=0/depth respectively.
## A tunnel faces into its named raised hillside; a subway faces out to rail.
static func profile(city: City, cell: Vector2i, height_scale: float) -> Dictionary:
	var code := city.building.atv(cell)
	var tunnel := NetworkShapes.is_tunnel(code)
	if not tunnel and not NetworkShapes.is_subway_portal(code):
		return {}
	var inward: Vector2
	if tunnel:
		inward = [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN][code - Buildings.TUNNEL_FIRST]
	else:
		inward = -Vector2(_rail_outward(city,cell,code))
	var base := city.ground_height(cell.x, cell.y) * height_scale
	return {"rail_cell": cell-Vector2i(inward), "subway_cells": subway_connections(city,cell) if not tunnel else [], "inward": inward, "outside": Vector2(0.5, 0.5) - inward * 0.5,
		"across": Vector2(-inward.y, inward.x), "width": 0.68,
		"depth": 0.78 if tunnel else 0.82, "tunnel": tunnel,
		"floor_start": base + (0.04 if tunnel else 0.055),
		"floor_end": base + (0.04 if tunnel else -0.46), "mouth_height": 0.48}


## Imported portals encode E/S/W/N, while the native builder labels them
## N/E/S/W. Reciprocal approaches settle that difference without rewriting
## either city or globally rotating masks. Isolated or ambiguous sites fall
## back to the direction encoded in the code.
static func _rail_outward(city: City, cell: Vector2i, code: int) -> Vector2i:
	var fallback: Vector2i = NetworkShapes.DIRECTIONS[code-Buildings.SUBWAY_PORTAL_FIRST]
	var candidates: Array[Vector2i] = []
	for d: int in 4:
		var direction: Vector2i = NetworkShapes.DIRECTIONS[d]
		var neighbor := cell+direction
		if not city.in_bounds(neighbor.x,neighbor.y): continue
		var other := city.building.atv(neighbor)
		if not NetworkShapes.in_rail_family(other) or NetworkShapes.is_subway_portal(other): continue
		var mask := CityNetworks3D.network_mask(other,NetworkShapes.Family.RAIL)
		if NetworkShapes.is_rail_bridge(other): mask = 10 if city.flags.atv(neighbor)&RotationMapper.AXIS_FLAG else 5
		if mask & (1<<((d+2)%4)): candidates.append(direction)
	if candidates.has(fallback): return fallback
	if candidates.size()==1: return candidates[0]
	return candidates[0] if not candidates.is_empty() else fallback

## A subway portal is also a subway node, including elbows and branches. The
## underground route need not continue opposite the surface railway mouth.
static func subway_connections(city: City, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var own := NetworkShapes.underground_mask(city.underground.atv(cell),NetworkShapes.Family.SUBWAY)
	# A portal with no underground piece acts as a four-way converter.
	if own==0: own=15
	for d: int in 4:
		if not own & (1<<d): continue
		var neighbor: Vector2i = cell+NetworkShapes.DIRECTIONS[d]
		if not city.in_bounds(neighbor.x,neighbor.y): continue
		var mask := NetworkShapes.underground_mask(city.underground.atv(neighbor),NetworkShapes.Family.SUBWAY)
		if mask & (1<<((d+2)%4)): out.append(neighbor)
	return out
