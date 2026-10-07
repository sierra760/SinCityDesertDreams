# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only, shared highway height field. Positive cubic B-spline weights
## round quantized hill feet/crests without changing the terrain or save grids.
extends RefCounted

static func stencil(city: City, cell: Vector2i) -> PackedFloat64Array:
	var heights := PackedFloat64Array()
	for y: int in range(-1,3):
		for x: int in range(-1,3):
			var vx := clampi(cell.x+x,0,City.WIDTH)
			var vy := clampi(cell.y+y,0,City.HEIGHT)
			if city.terrain_surface is TerrainSurface:
				heights.append(city.terrain_surface.vertex(vx,vy)*CityGeometry3D.HEIGHT)
			else:
				var sample := Vector2i(mini(vx,City.WIDTH-1),mini(vy,City.HEIGHT-1))
				var corner := (1 if vx==City.WIDTH else 0)+(2 if vy==City.HEIGHT else 0)
				heights.append(CityGeometry3D.ground_corners(city,sample)[corner].y)
	return heights

static func weights(t: float) -> PackedFloat64Array:
	return PackedFloat64Array([pow(1-t,3)/6.0,(3*t*t*t-6*t*t+4)/6.0,(-3*t*t*t+3*t*t+3*t+1)/6.0,t*t*t/6.0])

static func height(heights: PackedFloat64Array, offset: Vector2) -> float:
	# The four B-spline weights per axis, in the same order as weights().
	var tx: float = offset.x
	var ty: float = offset.y
	var wx0 := pow(1-tx,3)/6.0
	var wx1 := (3*tx*tx*tx-6*tx*tx+4)/6.0
	var wx2 := (-3*tx*tx*tx+3*tx*tx+3*tx+1)/6.0
	var wx3 := tx*tx*tx/6.0
	var wy0 := pow(1-ty,3)/6.0
	var wy1 := (3*ty*ty*ty-6*ty*ty+4)/6.0
	var wy2 := (-3*ty*ty*ty+3*ty*ty+3*ty+1)/6.0
	var wy3 := ty*ty*ty/6.0
	var result := 0.0
	result += heights[0]*wx0*wy0
	result += heights[1]*wx1*wy0
	result += heights[2]*wx2*wy0
	result += heights[3]*wx3*wy0
	result += heights[4]*wx0*wy1
	result += heights[5]*wx1*wy1
	result += heights[6]*wx2*wy1
	result += heights[7]*wx3*wy1
	result += heights[8]*wx0*wy2
	result += heights[9]*wx1*wy2
	result += heights[10]*wx2*wy2
	result += heights[11]*wx3*wy2
	result += heights[12]*wx0*wy3
	result += heights[13]*wx1*wy3
	result += heights[14]*wx2*wy3
	result += heights[15]*wx3*wy3
	return result

static func curved(heights: PackedFloat64Array) -> bool:
	var dx := heights[1]-heights[0]
	var dy := heights[4]-heights[0]
	for y: int in 4:
		for x: int in 4:
			if absf(heights[y*4+x]-heights[0]-dx*x-dy*y)>.000001: return true
	return false

## Cosine easing has continuous acceleration at the joins with the constant
## climb; unlike a full smoothstep it does not steepen the tight inner lane.
static func ramp_rise(t: float) -> float:
	const EASE := .12
	if t<EASE: return (t-EASE/PI*sin(PI*t/EASE))/(2*(1-EASE))
	if t>1-EASE: return 1-ramp_rise(1-t)
	return (t-EASE*.5)/(1-EASE)

static func ramp_height(city: City, cell: Vector2i, road: Vector2, high: Vector2,
		t: float, radius: float, heights: PackedFloat64Array, elevation: float, endpoint: Vector2 = Vector2(INF,0)) -> float:
	return ramp_profile_height(ramp_profile(city,cell,road,high,radius,heights,elevation,endpoint),t)


## The step-independent part of ramp_height for one lateral radius:
## [low, top, incoming, outgoing, arc_length]. Combining it with any step
## through ramp_profile_height reproduces ramp_height exactly.
static func ramp_profile(city: City, cell: Vector2i, road: Vector2, high: Vector2,
		radius: float, heights: PackedFloat64Array, elevation: float, endpoint: Vector2 = Vector2(INF,0)) -> PackedFloat64Array:
	var pivot := Vector2(.5,.5)+(road+high)*.5
	var start := pivot-high*radius
	var end := pivot-road*radius
	var low := CityGeometry3D.point_on_ground(city,cell,start).y+.04
	var top := endpoint.x if is_finite(endpoint.x) else height(heights,end)+elevation
	# Endpoint derivatives follow the adjoining road and rounded highway, even
	# when the ramp is on a hill. Each radial strip meets its entire mouth.
	var neighbor := cell+Vector2i(road)
	var road_offset := start-road
	var incoming := 0.0
	if city.in_bounds(neighbor.x,neighbor.y):
		incoming = (CityGeometry3D.point_on_ground(city,neighbor,road_offset).y-
			CityGeometry3D.point_on_ground(city,neighbor,road_offset+road*.01).y)/.01
	var outgoing := endpoint.y if is_finite(endpoint.x) else (height(heights,end+high*.001)-height(heights,end-high*.001))/.002
	var arc_length := radius*PI*.5
	return PackedFloat64Array([low,top,incoming,outgoing,arc_length])


static func ramp_profile_height(profile: PackedFloat64Array, t: float) -> float:
	var low: float = profile[0]
	var top: float = profile[1]
	var incoming: float = profile[2]
	var outgoing: float = profile[3]
	var arc_length: float = profile[4]
	return lerpf(low,top,ramp_rise(t))+incoming*arc_length*t*pow(1-t,2)+outgoing*arc_length*t*t*(t-1)
