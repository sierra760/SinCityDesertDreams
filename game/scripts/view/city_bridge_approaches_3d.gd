# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only road/rail/highway grading on land beside rigid, level bridge spans.
extends RefCounted
const HighwayHeight := preload("res://scripts/view/city_highway_height_3d.gd")

static func profiles(city: City, decks: Dictionary) -> Dictionary:
	var segments: Array[Dictionary] = []
	for start: Vector2i in decks:
		var deck: Dictionary = decks[start]
		if deck.index!=0: continue
		var code := city.building.atv(start)
		var family := NetworkShapes.Family.ROAD if NetworkShapes.is_road_bridge(code) else NetworkShapes.Family.RAIL if NetworkShapes.is_rail_bridge(code) else NetworkShapes.Family.HIGHWAY if NetworkShapes.is_highway(code) else NetworkShapes.Family.NONE
		if family==NetworkShapes.Family.NONE: continue
		var direction := Vector2i.RIGHT if deck.ew else Vector2i.DOWN
		for side: int in 2:
			var edge := start if side==0 else start+direction*int(deck.length)
			var outward := -direction if side==0 else direction
			var bank := edge+outward if side==0 else edge
			var cells := _cells(city,bank,outward,family,deck.deck,true)
			if cells.is_empty(): continue
			if side==0: cells.reverse()
			var near := _samples(city,cells[0],deck.ew,0,1,family)
			var far := _samples(city,cells[-1],deck.ew,1,-1,family)
			for index: int in 17:
				if side==0: far[index] = Vector2(deck.start,0)
				else: near[index] = Vector2(decks[start+direction*(int(deck.length)-1)].end,0)
			segments.append({"cells":cells,"ew":deck.ew,"family":family,"near":near,"far":far})
	# Overlapping approaches between neighboring bridges are one land road.
	# Its two bridge endpoints own the grade, rather than competing profiles
	# independently dipping to the unmodified terrain at the shared junction.
	var merged := true
	while merged:
		merged = false
		for i: int in segments.size():
			for j: int in range(i+1,segments.size()):
				var a: Dictionary = segments[i]
				var b: Dictionary = segments[j]
				if a.ew!=b.ew or a.family!=b.family: continue
				var overlap := false
				for cell: Vector2i in a.cells:
					if cell in b.cells: overlap = true; break
				if not overlap: continue
				var axis := 0 if a.ew else 1
				var cells: Array[Vector2i] = a.cells.duplicate()
				for cell: Vector2i in b.cells:
					if cell not in cells: cells.append(cell)
				cells.sort_custom(func(x: Vector2i,y: Vector2i) -> bool: return x[axis]<y[axis])
				segments[i] = {"cells":cells,"ew":a.ew,"family":a.family,"near":a.near if a.cells[0][axis]<=b.cells[0][axis] else b.near,"far":a.far if a.cells[-1][axis]>=b.cells[-1][axis] else b.far}
				segments.remove_at(j)
				merged = true
				break
			if merged: break
	var result := {}
	for segment: Dictionary in segments: _project(city,segment,result)
	_level_junctions(result)
	# A graded bend/junction shares its elevated side mouth with the existing
	# branch road. Ease that branch back onto its terrain as well.
	for cell: Vector2i in result.keys():
		var profile: Dictionary = result[cell]
		var mask := CityNetworks3D.network_mask(city.building.atv(cell),profile.family)
		if mask in [5,10]: continue
		for outward: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var ew := outward.x!=0
			var side := 0 if outward.x<0 or outward.y<0 else 1
			var mouth := NetworkShapes.WEST if outward.x<0 else NetworkShapes.EAST if outward.x>0 else NetworkShapes.NORTH if outward.y<0 else NetworkShapes.SOUTH
			if (mask&mouth)==0 or result.has(cell+outward): continue
			var boundary := PackedVector2Array()
			var highest := -INF
			for index: int in 17:
				var offset := Vector2(side,index/16.0) if ew else Vector2(index/16.0,side)
				var h := height(profile,offset)
				var inner := height(profile,offset-Vector2(outward)*.001)
				boundary.append(Vector2(h,(h-inner)/(.001*(outward.x if ew else outward.y))))
				highest = maxf(highest,h)
			var cells := _cells(city,cell+outward,outward,profile.family,highest,false)
			if cells.is_empty(): continue
			var conflict := false
			for branch: Vector2i in cells:
				if result.has(branch): conflict = true; break
			if conflict: continue
			if side==0: cells.reverse()
			var near := _samples(city,cells[0],ew,0,1,profile.family) if side==0 else boundary
			var far := boundary if side==0 else _samples(city,cells[-1],ew,1,-1,profile.family)
			_project(city,{"cells":cells,"ew":ew,"family":profile.family,"near":near,"far":far},result)
	return _join_junctions(city,result)

## Straight approaches and side branches meet the actual graded junction
## field. A junction may be owned by a perpendicular bridge approach; raw
## terrain endpoints would otherwise leave a step at its raised road mouth.
static func _level_junctions(profiles: Dictionary) -> void:
	for cell: Vector2i in profiles.keys():
		var p: Dictionary = profiles[cell]
		if not p.corner: continue
		var level := -INF
		for along: float in [0.0,.5,1.0]:
			for across: float in [.2,.5,.8]:
				level = maxf(level,_raw_height(p,Vector2(along,across) if p.ew else Vector2(across,along)))
		var samples := PackedVector2Array()
		var caps := PackedFloat64Array()
		for index: int in 17:
			samples.append(Vector2(level,0))
			caps.append(0)
		var flat: Dictionary = p.duplicate()
		flat.index = 0
		flat.length = 1
		flat.near = samples
		flat.far = samples
		flat.cap = caps
		profiles[cell] = flat

static func _join_junctions(city: City, profiles: Dictionary) -> Dictionary:
	var groups := {}
	for cell: Vector2i in profiles:
		var p: Dictionary = profiles[cell]
		if p.corner: continue
		var direction := Vector2i.RIGHT if p.ew else Vector2i.DOWN
		var first := cell-direction*int(p.index)
		var key := Vector3i(first.x,first.y,int(p.family)*2+(1 if p.ew else 0))
		if not groups.has(key): groups[key] = []
		groups[key].append(cell)
	var result := profiles.duplicate()
	for collection: Array in groups.values():
		var ordered: Array[Vector2i] = []
		ordered.assign(collection)
		var p: Dictionary = profiles[ordered[0]]
		var axis := 0 if p.ew else 1
		var direction := Vector2i.RIGHT if p.ew else Vector2i.DOWN
		ordered.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a[axis]<b[axis])
		var runs: Array[Array] = []
		for cell: Vector2i in ordered:
			if runs.is_empty() or runs[-1][-1]+direction!=cell: runs.append([])
			runs[-1].append(cell)
		for run: Array in runs:
			var cells: Array[Vector2i] = []
			cells.assign(run)
			var near := PackedVector2Array()
			var far := PackedVector2Array()
			var joins := false
			for side: int in 2:
				var cell := cells[0] if side==0 else cells[-1]
				var outward := -direction if side==0 else direction
				var other: Dictionary = profiles.get(cell+outward,{})
				var join: bool = not other.is_empty() and other.family==p.family and other.corner
				joins = joins or join
				var samples := near if side==0 else far
				for index: int in 17:
					var edge := Vector2(side,index/16.0) if p.ew else Vector2(index/16.0,side)
					var field: Dictionary = other if join else profiles[cell]
					var offset := edge-Vector2(outward) if join else edge
					var inner := offset+Vector2(outward)*(.001 if join else -.001)
					var h := height(field,offset) if join else _raw_height(field,offset)
					var inside := height(field,inner) if join else _raw_height(field,inner)
					samples.append(Vector2(h,(inside-h)/(.001*(outward.x if p.ew else outward.y)*(1 if join else -1))))
			if joins:
				for cell: Vector2i in cells: result.erase(cell)
				_project(city,{"cells":cells,"ew":p.ew,"family":p.family,"near":near,"far":far},result)
	return result

static func _cells(city: City, bank: Vector2i, outward: Vector2i, family: int, target: float, corner: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var ew := outward.x!=0
	for step: int in 6:
		var cell := bank+outward*step
		if not city.in_bounds(cell.x,cell.y) or city.is_water(cell.x,cell.y): break
		var code := city.building.atv(cell)
		if Buildings.category(code)==Buildings.Category.BRIDGE or not NetworkShapes.in_family(code,family) or NetworkShapes.is_onramp(code) or NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code) or (NetworkShapes.is_highway(code) and family!=NetworkShapes.Family.HIGHWAY): break
		var straight := _straight(code,family,ew)
		var toward := -outward
		var mouth := NetworkShapes.EAST if toward.x>0 else NetworkShapes.WEST if toward.x<0 else NetworkShapes.SOUTH if toward.y>0 else NetworkShapes.NORTH
		if not straight and (family==NetworkShapes.Family.HIGHWAY or not corner or step==0 or (CityNetworks3D.network_mask(code,family)&mouth)==0): break
		cells.append(cell)
		if not straight: break
		var outside := Vector2(.5,.5)+Vector2(outward)*.5
		var ground := HighwayHeight.height(HighwayHeight.stencil(city,cell),outside)+CityNetworks3D.HIGHWAY_ELEVATION if family==NetworkShapes.Family.HIGHWAY else CityGeometry3D.point_on_ground(city,cell,outside).y+.04
		if cells.size()>=2 and cells.size()>=1.5*absf(target-ground)/.577350269: break
	return cells

static func _straight(code: int, family: int, ew: bool) -> bool:
	var mask := CityNetworks3D.network_mask(code,family)
	return mask==(10 if ew else 5)

static func _samples(city: City, cell: Vector2i, ew: bool, along: float, inward: float, family: int) -> PackedVector2Array:
	var samples := PackedVector2Array()
	var corners := CityGeometry3D.ground_corners(city,cell)
	var stencil := HighwayHeight.stencil(city,cell) if family==NetworkShapes.Family.HIGHWAY else PackedFloat64Array()
	for index: int in 17:
		var edge := Vector2(along,index/16.0) if ew else Vector2(index/16.0,along)
		var inner := edge+(Vector2(inward*.001,0) if ew else Vector2(0,inward*.001))
		var h := _baseline(corners,stencil,cell,edge)
		var derivative := (_baseline(corners,stencil,cell,inner)-h)/(.001*inward)
		samples.append(Vector2(h,derivative))
	return samples

static func _baseline(corners: PackedVector3Array, stencil: PackedFloat64Array, cell: Vector2i, offset: Vector2) -> float:
	return HighwayHeight.height(stencil,offset)+CityNetworks3D.HIGHWAY_ELEVATION if not stencil.is_empty() else CityGeometry3D.point_over_corners(corners,cell,offset).y+.04

static func _project(city: City, segment: Dictionary, result: Dictionary) -> void:
	var cells: Array[Vector2i] = segment.cells
	var count := cells.size()
	var ground: Array[PackedVector3Array] = []
	var stencils: Array[PackedFloat64Array] = []
	for cell: Vector2i in cells:
		ground.append(CityGeometry3D.ground_corners(city,cell))
		stencils.append(HighwayHeight.stencil(city,cell) if segment.family==NetworkShapes.Family.HIGHWAY else PackedFloat64Array())
	var caps := PackedFloat64Array()
	var changed := false
	for index: int in 17:
		var across := index/16.0
		var a: Vector2 = segment.near[index]
		var b: Vector2 = segment.far[index]
		var lift := .0
		for step: int in count*32-1:
			var along := (step+1)/32.0
			var u := along/count
			var cell_index := mini(floori(along),count-1)
			var offset := Vector2(along-cell_index,across) if segment.ew else Vector2(across,along-cell_index)
			# Highway approaches may ease below the ordinary elevated highway
			# field, while keeping the slab clear of actual terrain. Capping at
			# that field forces a sharp crest when the bank rises into the span.
			var actual := CityGeometry3D.point_over_corners(ground[cell_index],cells[cell_index],offset).y+.12 if segment.family==NetworkShapes.Family.HIGHWAY else _baseline(ground[cell_index],stencils[cell_index],cells[cell_index],offset)
			var smooth := _hermite(a,b,count,u)
			if absf(smooth-actual)>.00001: changed = true
			lift = maxf(lift,(actual-smooth)/(u*u*(1-u)*(1-u)))
		caps.append(lift)
	if not changed: return
	for index: int in count:
		var mask := CityNetworks3D.network_mask(city.building.atv(cells[index]),segment.family)
		var low := NetworkShapes.NORTH if segment.ew else NetworkShapes.WEST
		var high := NetworkShapes.SOUTH if segment.ew else NetworkShapes.EAST
		result[cells[index]] = {"ew":segment.ew,"family":segment.family,"index":index,"length":count,"near":segment.near,"far":segment.far,"cap":caps,"ground":ground[index],"cell":cells[index],"corner":mask not in [5,10],"blend_low":not bool(mask&low),"blend_high":not bool(mask&high)}

static func _hermite(a: Vector2, b: Vector2, length: float, u: float) -> float:
	var u2 := u*u
	var u3 := u2*u
	return (2*u3-3*u2+1)*a.x+(u3-2*u2+u)*length*a.y+(-2*u3+3*u2)*b.x+(u3-u2)*length*b.y

static func _raw_height(profile: Dictionary, offset: Vector2) -> float:
	var across := offset.y if profile.ew else offset.x
	var along := offset.x if profile.ew else offset.y
	var at := clampf(across,0,1)*16
	var index := mini(floori(at),15)
	var a: Vector2 = profile.near[index].lerp(profile.near[index+1],at-index)
	var b: Vector2 = profile.far[index].lerp(profile.far[index+1],at-index)
	var cap := lerpf(profile.cap[index],profile.cap[index+1],at-index)
	var u: float = (profile.index+along)/float(profile.length)
	return _hermite(a,b,profile.length,u)+cap*u*u*(1-u)*(1-u)

static func height(profile: Dictionary, offset: Vector2) -> float:
	if profile.has("grade_level"): return profile.grade_level
	if profile.has("grade_stencil"):
		var weights := HighwayHeight.weights(offset.x if profile.ew else offset.y)
		var h := CityNetworks3D.HIGHWAY_ELEVATION
		for i: int in 4: h+=profile.grade_stencil[i]*weights[i]
		return h
	if profile.has("grade_near"):
		var u: float = (profile.index+(offset.x if profile.ew else offset.y))/float(profile.length)
		var weights := HighwayHeight.weights(offset.x if profile.ew else offset.y)
		var road := CityNetworks3D.HIGHWAY_ELEVATION
		for i: int in 4: road+=profile.grade_base[i]*weights[i]
		var baseline := highway_blend(profile.grade_near.x,profile.grade_far.x,road,u,profile.grade_near_fixed,profile.grade_far_fixed)
		if profile.grade_cap==0: return baseline
		var room: float = maxf(0,profile.grade_ceiling-baseline)
		if room<.00000001: return baseline
		return baseline+room*(1-exp(-profile.grade_cap*u*u*(1-u)*(1-u)/room))
	# Elevated highway shoulders keep the complete carriageway grade.
	if profile.family==NetworkShapes.Family.HIGHWAY: return _raw_height(profile,offset)
	var across := offset.y if profile.ew else offset.x
	var smooth := _raw_height(profile,offset)
	var ground := CityGeometry3D.point_over_corners(profile.ground,profile.cell,offset).y+.04
	var blend := (smoothstep(0,.1625,across) if profile.blend_low else 1.0)*(smoothstep(0,.1625,1-across) if profile.blend_high else 1.0)
	return lerpf(ground,smooth,blend)

static func subdivisions(profile: Dictionary) -> Vector2i:
	if profile.has("grade_level"): return Vector2i.ONE
	if profile.has("grade_stencil"):
		var h: PackedFloat64Array = profile.grade_stencil
		if absf(h[0]-2*h[1]+h[2])<.000001 and absf(h[1]-2*h[2]+h[3])<.000001: return Vector2i.ONE
	if profile.has("grade_near") and profile.grade_near==profile.grade_far and profile.grade_near.y==0 and profile.grade_cap==0:
		var h: PackedFloat64Array = profile.grade_base
		if h[0]==h[1] and h[1]==h[2] and h[2]==h[3]: return Vector2i.ONE
	if profile.has("grade_near"):
		var count := 256 if int(profile.length)<=2 else 64
		return Vector2i(count,1) if profile.ew else Vector2i(1,count)
	if profile.has("grade_stencil"):
		return Vector2i(32,1) if profile.ew else Vector2i(1,32)
	var along := 64 if int(profile.length)==1 else 32
	return Vector2i(along,16) if profile.ew else Vector2i(16,along)

## Keep the rounded longitudinal terrain curve, then ease it
## into the fixed platform. Convex blending cannot add a Hermite overshoot.
static func highway_blend(near: float, far: float, road: float, u: float, near_fixed: bool, far_fixed: bool) -> float:
	if near_fixed and far_fixed:
		var platform := lerpf(near,far,smoothstep(0,1,u))
		var weight := smoothstep(0,.5,u)*smoothstep(0,.5,1-u)
		return lerpf(platform,road,weight)
	if near_fixed: return lerpf(near,road,smoothstep(0,1,u))
	return lerpf(road,far,smoothstep(0,1,u))
