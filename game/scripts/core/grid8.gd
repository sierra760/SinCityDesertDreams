# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A square byte grid with bounds-checked access.
##
## Backed by a PackedByteArray so it copies and serializes cheaply. Out-of-range
## reads return 0 and out-of-range writes are ignored, which keeps neighbor
## scans at the map edge free of special cases.
class_name Grid8
extends RefCounted

var width: int
var height: int
var data: PackedByteArray


func _init(w: int = 128, h: int = 128, fill: int = 0) -> void:
	width = w
	height = h
	data = PackedByteArray()
	data.resize(w * h)
	if fill != 0:
		data.fill(fill)


## Position of (x, y) inside `data`, for scans that walk the array directly.
func index(x: int, y: int) -> int:
	return y * width + x


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return data[y * width + x]


func put(x: int, y: int, value: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	data[y * width + x] = value & 0xFF


func atv(p: Vector2i) -> int:
	return at(p.x, p.y)


func putv(p: Vector2i, value: int) -> void:
	put(p.x, p.y, value)


func set_bits(x: int, y: int, mask: int, on: bool) -> void:
	var v := at(x, y)
	put(x, y, (v | mask) if on else (v & ~mask))


func has_bits(x: int, y: int, mask: int) -> bool:
	return (at(x, y) & mask) == mask


func fill(value: int) -> void:
	data.fill(value & 0xFF)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func duplicate_grid() -> Grid8:
	var g := Grid8.new(width, height)
	g.data = data.duplicate()
	return g


## Count cells equal to a value. Handy for statistics.
func count(value: int) -> int:
	return data.count(value)
