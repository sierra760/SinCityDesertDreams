# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only entity records shared by the live 3D feedback view.
class_name CityEntityRecords
extends RefCounted

var simulation: Simulation

## Records from every source, normalised to {kind, pos, heading, altitude, frame}.
func gather() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if simulation == null:
		return out
	_collect(out, &"transport", "vehicles", &"car")
	_collect(out, &"ports", "vehicles", &"plane")
	_collect(out, &"disasters", "entities", &"tornado")
	_collect(out, &"disasters", "fires", &"fire")
	_collect(out, &"disasters", "riots", &"riot")
	_collect(out, &"disasters", "crews", &"fire_crew")
	return out


func _collect(out: Array[Dictionary], system_key: StringName, getter: String, default_kind: StringName) -> void:
	var system: SimSystem = simulation.get_system(system_key)
	if system == null or not system.has_method(getter):
		return
	var records: Variant = system.call(getter)
	if not records is Array:
		return
	for raw: Variant in records:
		var record := normalize(raw, default_kind)
		if not record.is_empty():
			record["source"] = system_key
			if getter == "crews" and not String(record.kind).ends_with("_crew"):
				record.kind = StringName(String(record.kind) + "_crew")
			out.append(record)


## Turn one source record into the layer's own shape, or {} when unusable.
static func normalize(raw: Variant, default_kind: StringName) -> Dictionary:
	var record := {"kind": default_kind, "pos": Vector2.ZERO, "heading": 0, "altitude": 0.0, "frame": -1}
	if raw is Vector2i:
		record["pos"] = Vector2(raw as Vector2i)
		return record
	if raw is Vector2:
		record["pos"] = raw
		return record
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	if data.has("source"):
		record["source"] = StringName(String(data.source))
	var kind: Variant = data.get("kind", default_kind)
	if typeof(kind) == TYPE_STRING or typeof(kind) == TYPE_STRING_NAME:
		record["kind"] = StringName(kind)
	var pos: Variant = data.get("pos", data.get("tile", null))
	if pos == null and data.has("x") and data.has("y"):
		if (typeof(data.x) == TYPE_INT or typeof(data.x) == TYPE_FLOAT) and (typeof(data.y) == TYPE_INT or typeof(data.y) == TYPE_FLOAT):
			pos = Vector2(float(data.x),float(data.y))
	if pos is Vector2:
		record["pos"] = pos
	elif pos is Vector2i:
		record["pos"] = Vector2(pos as Vector2i)
	else:
		return {}
	var heading: Variant = data.get("heading", -1)
	if (typeof(heading) == TYPE_INT or typeof(heading) == TYPE_FLOAT) and is_finite(float(heading)) and int(heading) >= 0:
		record["heading"] = posmod(int(heading), 8)
	else:
		var dir: Variant = data.get("dir", data.get("velocity", null))
		if dir is Vector2 and (dir as Vector2).is_finite() and (dir as Vector2).length_squared() > 0.0:
			record["heading"] = heading_from_direction(dir)
		elif dir is Vector2i and dir != Vector2i.ZERO:
			record["heading"] = heading_from_direction(Vector2(dir as Vector2i))
	var altitude: Variant = data.get("altitude", 0.0)
	if typeof(altitude) == TYPE_INT or typeof(altitude) == TYPE_FLOAT:
		record["altitude"] = float(altitude)
	var frame: Variant = data.get("frame", -1)
	if typeof(frame) == TYPE_INT:
		record["frame"] = int(frame)
	return record


## Heading 0..7 (north, then clockwise) for a data-space direction.
static func heading_from_direction(dir: Vector2) -> int:
	var angle := atan2(dir.y, dir.x)
	return posmod(roundi(angle / (PI / 4.0)) + 2, 8)
