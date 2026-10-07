# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A square grid of 16-bit values, used for the altitude layer.
class_name Grid16
extends RefCounted

var width: int
var height: int
var data: PackedInt32Array


func _init(w: int = 128, h: int = 128, fill: int = 0) -> void:
	width = w
	height = h
	data = PackedInt32Array()
	data.resize(w * h)
	if fill != 0:
		data.fill(fill)


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return data[y * width + x]


func put(x: int, y: int, value: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	data[y * width + x] = value & 0xFFFF


func atv(p: Vector2i) -> int:
	return at(p.x, p.y)


func putv(p: Vector2i, value: int) -> void:
	put(p.x, p.y, value)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func duplicate_grid() -> Grid16:
	var g := Grid16.new(width, height)
	g.data = data.duplicate()
	return g


## Pack to bytes (little-endian pairs) for saving.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(data.size() * 2)
	for i in data.size():
		var v := data[i]
		out[i * 2] = v & 0xFF
		out[i * 2 + 1] = (v >> 8) & 0xFF
	return out


func from_bytes(bytes: PackedByteArray) -> void:
	var n := mini(bytes.size() / 2, data.size())
	for i in n:
		data[i] = bytes[i * 2] | (bytes[i * 2 + 1] << 8)
