# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Classic highway bridges retain straight highway ids on wet tiles.
## Resolve connected carriageways as rigid crossings without editing city grids.
extends RefCounted
const HighwayHeight := preload("res://scripts/view/city_highway_height_3d.gd")
const DIRECTIONS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]

static func _mask(city: City, cell: Vector2i) -> int:
	if not city.in_bounds(cell.x,cell.y): return 0
	match city.building.atv(cell):
		NetworkShapes.HIGHWAY_NS,NetworkShapes.HIGHWAY_SLOPE_N,NetworkShapes.HIGHWAY_SLOPE_S: return 5
		NetworkShapes.HIGHWAY_EW,NetworkShapes.HIGHWAY_SLOPE_W,NetworkShapes.HIGHWAY_SLOPE_E: return 10
	return 0

static func profiles(city: City) -> Dictionary:
	var crossing := {}
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			var mask := _mask(city,cell)
			# Temporary flood overlays do not construct permanent bridge decks.
			if mask==0 or not Terrain.is_water(city.terrain.atv(cell)): continue
			crossing[cell] = mask
			var transverse := Vector2i.DOWN if mask==10 else Vector2i.RIGHT
			# Match the existing highway routing's paired carriageway ownership.
			# On an uneven shore the dry mate shares the same rigid span edge.
			var first := cell
			while _mask(city,first-transverse)==mask: first -= transverse
			var index := (cell.y-first.y) if mask==10 else (cell.x-first.x)
			var partner := cell+transverse if index%2==0 else cell-transverse
			if _mask(city,partner)==mask: crossing[partner] = mask
	var result := {}
	var visited := {}
	for seed: Vector2i in crossing:
		if visited.has(seed): continue
		var mask: int = crossing[seed]
		var ew := mask==10
		var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
		var component: Array[Vector2i] = [seed]
		visited[seed] = true
		var cursor := 0
		while cursor<component.size():
			var cell := component[cursor]
			cursor += 1
			for step: Vector2i in DIRECTIONS:
				var neighbor := cell+step
				if int(crossing.get(neighbor,0))==mask and not visited.has(neighbor):
					visited[neighbor] = true
					component.append(neighbor)
		var deck := -INF
		for cell: Vector2i in component:
			if Terrain.is_water(city.terrain.atv(cell)):
				deck = maxf(deck,city.water_height(cell.x,cell.y)*CityGeometry3D.HEIGHT+.12)
				# Native shoreline corners retain real relief above the water.
				# Imported wet art uses its visible, presentation-clamped envelope.
				for corner: Vector3 in CityGeometry3D.visible_cell_corners(city,cell):
					deck = maxf(deck,corner.y+.12)
			else:
				# Dry ground can rise inside an irregular shoreline crossing.
				for corner: Vector3 in CityGeometry3D.ground_corners(city,cell):
					deck = maxf(deck,corner.y+CityNetworks3D.HIGHWAY_ELEVATION)
			for outward: Vector2i in [-direction,direction]:
				var bank := cell+outward
				if int(crossing.get(bank,0))==mask or not city.in_bounds(bank.x,bank.y) or Terrain.is_water(city.terrain.atv(bank)): continue
				var heights := HighwayHeight.stencil(city,bank)
				for across: float in [0.0,.5,1.0]:
					var edge := Vector2(.5,.5)-Vector2(outward)*.5
					if ew: edge.y = across
					else: edge.x = across
					deck = maxf(deck,maxf(HighwayHeight.height(heights,edge),CityGeometry3D.point_on_ground(city,bank,edge).y)+CityNetworks3D.HIGHWAY_ELEVATION)
		# A damaged lane retains its hole. Each remaining contiguous lane run
		# owns its bank indices, with one common level across the connected span.
		for start: Vector2i in component:
			if int(crossing.get(start-direction,0))==mask: continue
			var run: Array[Vector2i] = []
			var cell := start
			while int(crossing.get(cell,0))==mask:
				run.append(cell)
				cell += direction
			for i: int in run.size():
				result[run[i]] = {"ew":ew,"start":deck,"end":deck,"deck":deck,"index":i,"length":run.size(),"family":NetworkShapes.Family.HIGHWAY}
	return result
