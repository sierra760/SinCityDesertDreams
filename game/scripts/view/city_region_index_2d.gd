# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Bounded broad phase for one synchronous old/new ownership update.
## Every candidate is still tested with Rect2i.intersects.
extends RefCounted

const CELL_SIZE := 32
const MIN_REGIONS := 16
const MAX_REFERENCES := 16384
const MAX_QUERY_CELLS := 256
var _regions: Array[Rect2i] = []
var _buckets: Dictionary = {}

func _init(regions: Array[Rect2i]) -> void:
	_regions = regions.duplicate()
	if regions.size() < MIN_REGIONS: return
	var references := 0
	for region: Rect2i in regions:
		var cells := _cells(region)
		if cells == Rect2i():
			_buckets.clear()
			return
		references += cells.size.x*cells.size.y
		if references > MAX_REFERENCES:
			_buckets.clear()
			return
		for y: int in range(cells.position.y,cells.end.y):
			for x: int in range(cells.position.x,cells.end.x):
				var key := Vector2i(x,y)
				if not _buckets.has(key): _buckets[key] = []
				_buckets[key].append(region)

func intersects(owned: Rect2i) -> bool:
	if _buckets.is_empty(): return _linear(owned)
	var cells := _cells(owned)
	if cells == Rect2i() or cells.size.x*cells.size.y > MAX_QUERY_CELLS:
		return _linear(owned)
	for y: int in range(cells.position.y,cells.end.y):
		for x: int in range(cells.position.x,cells.end.x):
			for region: Rect2i in _buckets.get(Vector2i(x,y),[]):
				if owned.intersects(region): return true
	return false

func _linear(owned: Rect2i) -> bool:
	for region: Rect2i in _regions:
		if owned.intersects(region): return true
	return false

static func _cells(rect: Rect2i) -> Rect2i:
	# Unsupported/empty sizes and integer-overflow endpoints fall back to a full
	# scan rather than changing their engine predicate or emitting new errors.
	if rect.size.x <= 0 or rect.size.y <= 0: return Rect2i()
	var end_x := int(rect.position.x)+int(rect.size.x)
	var end_y := int(rect.position.y)+int(rect.size.y)
	if end_x > 2147483647 or end_y > 2147483647: return Rect2i()
	var lo := Vector2i(floori(float(rect.position.x)/CELL_SIZE),floori(float(rect.position.y)/CELL_SIZE))
	var hi := Vector2i(floori(float(end_x-1)/CELL_SIZE),floori(float(end_y-1)/CELL_SIZE))
	return Rect2i(lo,hi-lo+Vector2i.ONE)
