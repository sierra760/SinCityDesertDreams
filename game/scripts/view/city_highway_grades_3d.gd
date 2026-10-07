# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only highway platforms and longitudinal grades. Terrain may change the
## grade along the route, never the cross section of an individual carriageway.
extends RefCounted
const HighwayHeight := preload("res://scripts/view/city_highway_height_3d.gd")
const Approaches := preload("res://scripts/view/city_bridge_approaches_3d.gd")

static func profiles(city: City, decks: Dictionary) -> Dictionary:
	var result := {}
	var blocks := {}
	var straight := {}
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			var code := city.building.atv(cell)
			if not NetworkShapes.is_highway(code) or NetworkShapes.is_onramp(code) or decks.has(cell): continue
			if code in range(101,106):
				var anchor := CityNetworks3D.highway_footprint(city,cell,code)
				if anchor.x>=0: blocks[anchor]=code
			else:
				var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.HIGHWAY)
				if mask in [5,10]: straight[cell]=mask==10
	# Back-to-back corner blocks share a platform, rather than twisting each
	# quadrant over its own terrain. Their saved horizontal route stays exact.
	var visited := {}
	for anchor: Vector2i in blocks:
		if visited.has(anchor): continue
		var pending: Array[Vector2i] = [anchor]
		var group: Array[Vector2i] = []
		visited[anchor]=true
		while not pending.is_empty():
			var at: Vector2i = pending.pop_back()
			group.append(at)
			var mask := CityNetworks3D.network_mask(blocks[at],NetworkShapes.Family.HIGHWAY)
			for direction: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var next := at+direction*2
				var mouth := _mouth(direction)
				if not blocks.has(next) or visited.has(next) or not (mask&mouth): continue
				if not (CityNetworks3D.network_mask(blocks[next],NetworkShapes.Family.HIGHWAY)&_mouth(-direction)): continue
				visited[next]=true;pending.append(next)
		var level := -INF
		for at: Vector2i in group:
			for dy: int in 2:
				for dx: int in 2:
					for corner: Vector3 in CityGeometry3D.ground_corners(city,at+Vector2i(dx,dy)):
						level=maxf(level,corner.y+CityNetworks3D.HIGHWAY_ELEVATION)
		for at: Vector2i in group:
			for dy: int in 2:
				for dx: int in 2:
					result[at+Vector2i(dx,dy)]={"family":NetworkShapes.Family.HIGHWAY,"grade_level":level}
	visited.clear()
	for first: Vector2i in straight:
		if visited.has(first): continue
		var ew: bool = straight[first]
		var pending: Array[Vector2i] = [first]
		var group: Array[Vector2i] = []
		visited[first]=true
		while not pending.is_empty():
			var at: Vector2i = pending.pop_back()
			group.append(at)
			for direction: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var next := at+direction
				if not straight.has(next) or visited.has(next) or straight[next]!=ew: continue
				visited[next]=true;pending.append(next)
		_corridor(city,group,ew,decks,result)
	# Keep already-flat pavement on its compact geometry and plain height
	# arithmetic. Only a changed surface needs the resolved grade projection.
	for cell: Vector2i in result.keys():
		var profile: Dictionary = result[cell]
		var level := INF
		if profile.has("grade_level"): level=profile.grade_level
		elif profile.has("grade_stencil"):
			var h: PackedFloat64Array = profile.grade_stencil
			if h[0]==h[1] and h[1]==h[2] and h[2]==h[3]: level=h[0]+CityNetworks3D.HIGHWAY_ELEVATION
		elif profile.grade_near==profile.grade_far and profile.grade_near.y==0 and profile.grade_cap==0:
			var h: PackedFloat64Array = profile.grade_base
			if h[0]==h[1] and h[1]==h[2] and h[2]==h[3] and absf(h[0]+CityNetworks3D.HIGHWAY_ELEVATION-profile.grade_near.x)<.000000001:
				level=profile.grade_near.x
		if not is_finite(level): continue
		var unchanged := true
		for h: float in HighwayHeight.stencil(city,cell):
			if absf(h+CityNetworks3D.HIGHWAY_ELEVATION-level)>.000000001: unchanged=false;break
		if unchanged: result.erase(cell)
	return result

static func _mouth(direction: Vector2i) -> int:
	return NetworkShapes.EAST if direction.x>0 else NetworkShapes.WEST if direction.x<0 else NetworkShapes.SOUTH if direction.y>0 else NetworkShapes.NORTH

static func _corridor(city: City, cells: Array[Vector2i], ew: bool, decks: Dictionary, result: Dictionary) -> void:
	var axis := 0 if ew else 1
	var across_axis := 1-axis
	var low := City.WIDTH; var high := -1
	var start := City.WIDTH; var end := -1
	for cell: Vector2i in cells:
		low=mini(low,cell[across_axis]);high=maxi(high,cell[across_axis]+1)
		start=mini(start,cell[axis]);end=maxi(end,cell[axis]+1)
	var rows := {}
	for along: int in range(start,end+1): rows[along]=-INF
	# Imported terrain can retain different corner readings on either side
	# of a cell boundary. Include the actual road-owned terrain facets.
	for cell: Vector2i in cells:
		var corners := CityGeometry3D.ground_corners(city,cell)
		for i: int in 4:
			var along := cell[axis]+(i%2 if ew else i/2)
			rows[along]=maxf(rows[along],corners[i].y)
	# Only road-owned facets define the envelope. An imported neighboring
	# lot's northwest corner may disagree with this highway's boundary.
	rows[start-1]=rows[start]
	rows[end+1]=rows[end]
	for cell: Vector2i in cells:
		var along := cell[axis]
		result[cell]={"family":NetworkShapes.Family.HIGHWAY,"ew":ew,"grade_stencil":PackedFloat64Array([rows[along-1],rows[along],rows[along+1],rows[along+2]])}
	var endpoints: Array[Vector2] = []
	var joins: Array[bool] = []
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	for side: int in 2:
		var target := -INF
		for cell: Vector2i in cells:
			if cell[axis]!=(start if side==0 else end-1): continue
			var neighbor := cell+direction*(-1 if side==0 else 1)
			if decks.has(neighbor) and decks[neighbor].ew==ew:
				target=maxf(target,decks[neighbor].deck)
			elif result.has(neighbor) and result[neighbor].has("grade_level"):
				var mask := CityNetworks3D.network_mask(city.building.atv(neighbor),NetworkShapes.Family.HIGHWAY)
				if mask&_mouth(direction*(1 if side==0 else -1)): target=maxf(target,result[neighbor].grade_level)
		joins.append(is_finite(target))
		endpoints.append(Vector2(target,0))
	var length := end-start
	if joins[0] and joins[1] and length<=12:
		_join(city,cells,ew,start,length,endpoints[0],endpoints[1],true,true,result)
	else:
		for side: int in 2:
			if not joins[side]: continue
			var count := mini(6,length)
			var begin := start if side==0 else end-count
			var edge := begin+count if side==0 else begin
			var cell := Vector2i(edge-1,low) if ew else Vector2i(low,edge-1)
			var offset := Vector2(1,.5) if ew else Vector2(.5,1)
			if side==1:
				cell+=direction;offset-=Vector2(direction)
			# A damaged low-side carriageway must not invalidate the surviving
			# lane's grade. Select an extant cell at the same longitudinal slice.
			if not result.has(cell):
				for candidate: Vector2i in cells:
					if candidate[axis]==cell[axis]: cell=candidate;break
			var baseline: Dictionary = result[cell]
			var h := Approaches.height(baseline,offset)
			var d := (Approaches.height(baseline,offset+Vector2(direction)*.001)-Approaches.height(baseline,offset-Vector2(direction)*.001))/.002
			_join(city,cells,ew,begin,count,endpoints[0] if side==0 else Vector2(h,d),Vector2(h,d) if side==0 else endpoints[1],side==0,side==1,result)

static func _join(city: City, cells: Array[Vector2i], ew: bool, start: int, length: int, near: Vector2, far: Vector2, near_fixed: bool, far_fixed: bool, result: Dictionary) -> void:
	var cap := .0
	var ceiling := maxf(near.x,far.x)
	for cell: Vector2i in cells:
		var index := (cell.x if ew else cell.y)-start
		if index<0 or index>=length: continue
		for corner: Vector3 in CityGeometry3D.ground_corners(city,cell):
			ceiling=maxf(ceiling,corner.y+CityNetworks3D.HIGHWAY_ELEVATION)
	for step: int in range(1,length*32):
		var along := start+step/32.0
		var u := step/float(length*32)
		var baseline_cell := Vector2i.ZERO
		for candidate: Vector2i in cells:
			if (candidate.x if ew else candidate.y)==floori(along): baseline_cell=candidate;break
		var baseline_offset := Vector2(along-baseline_cell.x,.5) if ew else Vector2(.5,along-baseline_cell.y)
		var baseline := Approaches.height(result[baseline_cell],baseline_offset)
		var smooth := Approaches.highway_blend(near.x,far.x,baseline,u,near_fixed,far_fixed)
		# Sample each highway cell's own terrain, including its boundary
		# facets. Flooring an outer edge selects the neighboring lot instead
		# and can turn a discontinuous imported bank into an enormous cap.
		for cell: Vector2i in cells:
			if (cell.x if ew else cell.y)!=floori(along): continue
			for across_step: int in 5:
				var offset := Vector2(along-cell.x,across_step/4.0) if ew else Vector2(across_step/4.0,along-cell.y)
				var required := CityGeometry3D.point_on_ground(city,cell,offset).y+.12
				if required>smooth:
					# Bound a clearance bump by the real terrain/bank envelope.
					# An unconstrained quartic fitted near an endpoint can create
					# a much larger dome at the middle of a short approach.
					var room := ceiling-smooth
					cap=maxf(cap,-room*log((ceiling-required)/room)/(u*u*(1-u)*(1-u)))
	for cell: Vector2i in cells:
		var index := (cell.x if ew else cell.y)-start
		if index<0 or index>=length: continue
		result[cell]={"family":NetworkShapes.Family.HIGHWAY,"ew":ew,"index":index,"length":length,"grade_near":near,"grade_far":far,"grade_base":result[cell].grade_stencil,"grade_near_fixed":near_fixed,"grade_far_fixed":far_fixed,"grade_cap":cap,"grade_ceiling":ceiling}

## A ramp meets the resolved highway mouth, including its longitudinal tangent.
static func ramp_endpoint(profiles: Dictionary, decks: Dictionary, cell: Vector2i, road: Vector2, high: Vector2, radius: float) -> Vector2:
	var neighbor := cell+Vector2i(high)
	var end := Vector2(.5,.5)+(road+high)*.5-road*radius-high
	if decks.has(neighbor): return Vector2(decks[neighbor].deck,0)
	if not profiles.has(neighbor): return Vector2(INF,0)
	var profile: Dictionary = profiles[neighbor]
	var h := Approaches.height(profile,end)
	var slope := (Approaches.height(profile,end+high*.001)-Approaches.height(profile,end-high*.001))/.002
	return Vector2(h,slope)
