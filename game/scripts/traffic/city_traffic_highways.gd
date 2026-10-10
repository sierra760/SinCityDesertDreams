# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Lane geometry for paired US highways; does not alter the numerical network.
extends RefCounted

const INVALID := Vector2i(-1,-1)
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var routes: Dictionary = {}
var shape_cells: Array[Vector2i] = []
static var _highway_codes := PackedByteArray()

## Raw indices holding any code marked in `table`, in row-major order: the
## cells a full scan testing the same per-code predicate would visit.
static func cells_with(codes: PackedInt32Array, table: PackedByteArray) -> PackedInt32Array:
	var found := PackedInt32Array()
	for value: int in table.size():
		if table[value] == 0: continue
		var at := codes.find(value)
		while at >= 0:
			found.append(at)
			at = codes.find(value, at + 1)
	found.sort()
	return found

## 1 for every highway code: the cells (with their zone corners) that routes read.
static func highway_codes() -> PackedByteArray:
	if _highway_codes.is_empty():
		_highway_codes.resize(Buildings.COUNT)
		for value: int in Buildings.COUNT: _highway_codes[value] = 1 if NetworkShapes.is_highway(value) else 0
	return _highway_codes

## Builds fresh containers, so a caller may keep the previous tables to compare.
## Visits the highway cells in row-major order, exactly as a full scan would.
func rebuild(city: City) -> void:
	routes = {}
	var shapes: Array[Vector2i] = []
	shape_cells = shapes
	var blocks: Dictionary = {}
	var codes := city.building.data
	for at: int in cells_with(codes, highway_codes()):
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		var code: int = codes[at]
		var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.HIGHWAY)
		if mask in [3,6,12,9]:
			shape_cells.append(cell)
			var anchor := CityNetworks3D.highway_footprint(city,cell,code)
			if anchor.x < 0 or blocks.has(anchor): continue
			blocks[anchor] = true
			_curve(anchor,[3,6,12,9].find(mask))
		elif mask in [5,10]:
			var transverse := Vector2i.RIGHT if mask == 5 else Vector2i.DOWN
			var first := cell
			while _straight(city,first-transverse,mask): first -= transverse
			var index := (cell.x-first.x) if mask==5 else (cell.y-first.y)
			var partner := cell+transverse if index%2==0 else cell-transverse
			if not _straight(city,partner,mask): continue
			var direction := (Vector2i.DOWN if index%2==0 else Vector2i.UP) if mask==5 else (Vector2i.LEFT if index%2==0 else Vector2i.RIGHT)
			for lane: int in 2: _append(cell,{"lane":lane,"previous":cell-direction,"next":cell+direction,"length":1.0})
		elif mask == 15:
			shape_cells.append(cell)
			var anchor := CityNetworks3D.highway_footprint(city,cell,code)
			if anchor.x < 0: continue
			# A 2x2 crossing permits forward/right/left exits while preserving
			# the destination carriageway. Never reverse into an opposing lane.
			var local := cell-anchor
			var incoming: Array[Vector2i] = [Vector2i.DOWN if local.x==0 else Vector2i.UP,Vector2i.LEFT if local.y==0 else Vector2i.RIGHT]
			for direction: Vector2i in incoming:
				for outgoing: Vector2i in incoming:
					for lane: int in 2: _append(cell,{"lane":lane,"previous":cell-direction,"next":cell+outgoing,"length":.7 if outgoing!=direction else 1.0})

func _straight(city: City, cell: Vector2i, mask: int) -> bool:
	return city.in_bounds(cell.x,cell.y) and NetworkShapes.is_highway(city.building.atv(cell)) and CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.HIGHWAY)==mask

func _append(cell: Vector2i, segment: Dictionary) -> void:
	if not routes.has(cell): routes[cell] = []
	routes[cell].append(segment)

func _curve(anchor: Vector2i, quarter: int) -> void:
	for outer: bool in [false,true]:
		for lane: int in 2:
			var radius := (1.28 if lane==0 else 1.72) if outer else (.72 if lane==0 else .28)
			var cuts: Array[float] = [0.0,PI*.5]
			if radius>1:
				cuts.append(asin(1.0/radius))
				cuts.append(acos(1.0/radius))
			cuts.sort()
			for i: int in cuts.size()-1:
				var start: float = cuts[i] if outer else cuts[i+1]
				var end: float = cuts[i+1] if outer else cuts[i]
				var sign := 1.0 if outer else -1.0
				var middle := curve_point(anchor,quarter,radius,(start+end)*.5)
				var previous := curve_point(anchor,quarter,radius,start-sign*.0001)
				var next := curve_point(anchor,quarter,radius,end+sign*.0001)
				_append(Vector2i(floori(middle.x),floori(middle.y)),{"lane":lane,"previous":Vector2i(floori(previous.x),floori(previous.y)),"next":Vector2i(floori(next.x),floori(next.y)),"length":absf(end-start)*radius,"anchor":anchor,"quarter":quarter,"radius":radius,"start":start,"end":end})

static func curve_point(anchor: Vector2i, quarter: int, radius: float, angle: float) -> Vector2:
	var p := Vector2(2.0-radius*cos(angle),radius*sin(angle))-Vector2.ONE
	# Exact quarter rotations avoid floating-point floor errors at tile borders.
	match quarter:
		1: p = Vector2(-p.y,p.x)
		2: p = -p
		3: p = Vector2(p.y,-p.x)
	return Vector2(anchor)+Vector2.ONE+p

func mask(cell: Vector2i, fallback: int) -> int:
	if not routes.has(cell): return fallback
	var result := 0
	for segment: Dictionary in routes[cell]:
		for neighbor: Vector2i in [segment.previous,segment.next]:
			var index := DIRECTIONS.find(neighbor-cell)
			if index>=0: result |= 1<<index
	return result

func segments(cell: Vector2i, previous: Vector2i, lane: int) -> Array:
	var found: Array = []
	for segment: Dictionary in routes.get(cell,[]):
		if int(segment.lane)==lane and (previous==INVALID or segment.previous==previous): found.append(segment)
	# Side-entry ramps merge into the matching forward straight carriageway.
	if found.is_empty():
		for segment: Dictionary in routes.get(cell,[]):
			if int(segment.lane)==lane and not segment.has("radius") and previous != segment.next: found.append(segment)
	return found
