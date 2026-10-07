# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
class MalformedTransport extends SimSystem:
	func _init(): key = &"transport"
	func vehicles() -> Variant: return {"not": "an array"}
class PortRecords extends SimSystem:
	func _init(): key = &"ports"
	func vehicles() -> Array: return [{"x":4,"y":5}, {"x":6,"y":7,"kind":&"ship"}, null]
class IncidentRecords extends SimSystem:
	func _init(): key = &"disasters"
	func entities() -> Array: return [Vector2i(8, 9)]
	func fires() -> Array: return [Vector2i(10, 11)]
	func crews() -> Array: return [{"kind":&"fire","x":12,"y":13}]
func test_records_skip_malformed_sources() -> void:
	var records = CityEntityRecords.new()
	check(records.gather().is_empty(), "absent simulation is guarded")
	var sim := Simulation.new()
	records.simulation = sim
	check(records.gather().is_empty(), "absent systems are guarded")
	var transport := MalformedTransport.new()
	var ports := PortRecords.new()
	var incidents := IncidentRecords.new()
	sim.systems = [transport, ports, incidents]
	sim._system_index = {&"transport": transport, &"ports": ports, &"disasters": incidents}
	var gathered: Array = records.gather()
	check(gathered.size() == 5, "malformed sources and records are skipped")
	check(gathered.map(func(record): return record.kind) == [&"plane", &"ship", &"tornado", &"fire", &"fire_crew"], "all optional source defaults retained")
	var before := var_to_bytes(sim.snapshot())
	records.gather()
	check(var_to_bytes(sim.snapshot()) == before, "gathering preserves simulation runtime")
	sim.free()
	check(CityEntityRecords.normalize(null, &"car").is_empty(), "malformed source rejected")
	check(CityEntityRecords.normalize({"tile": "bad"}, &"fire").is_empty(), "malformed tile rejected")
	check(CityEntityRecords.normalize(Vector2i(2, 3), &"plane").kind == &"plane", "bare tiles preserve source default")
	check(CityEntityRecords.normalize({"tile": Vector2i(2, 3), "heading": 10}, &"car").heading == 2, "heading wraps canonically")
	check(CityEntityRecords.normalize({"pos": Vector2(2, 3), "velocity": Vector2.UP}, &"car").heading == 0, "direction yields north heading")
	for i: int in 8:
		var angle := (i - 2) * PI / 4.0
		check(CityEntityRecords.heading_from_direction(Vector2(cos(angle), sin(angle))) == i, "all normalized headings")
