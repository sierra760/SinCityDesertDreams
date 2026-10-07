# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Deterministic mixed construction edits for the incremental exactness suite:
## real Builder road/rail/highway/ramp/bridge/tunnel/bulldoze actions near the
## existing network, raw network writes with arbitrary orientation, lots,
## ground cover, power lines and congestion. Only stable public APIs are used.
extends RefCounted

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const KINDS: Array[String] = ["road", "road", "road", "rail", "rail", "highway", "highway", "onramp", "onramp", "bulldoze", "bulldoze",
	"raw_network", "raw_clear", "lots", "cover", "traffic", "bridge", "bridge", "tunnel", "power"]

static func network_cells(city: City) -> Array[Vector2i]:
	var kinds := CityTrafficGraph.network_kinds()
	var found: Array[Vector2i] = []
	var codes := city.building.data
	for i: int in codes.size():
		if kinds[codes[i]] != 0: found.append(Vector2i(i % City.WIDTH, i / City.WIDTH))
	return found

static func _clamp(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, 1, City.WIDTH - 2), clampi(cell.y, 1, City.HEIGHT - 2))

## Applies one edit; returns a short description ("" when nothing changed).
static func apply(city: City, builder: Builder, rng: RandomNumberGenerator) -> String:
	city.funds = 100000000
	var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	var nets := network_cells(city)
	var anchor: Vector2i = nets[rng.randi_range(0, nets.size() - 1)] if not nets.is_empty() else Vector2i(64, 64)
	var dir: Vector2i = DIRS[rng.randi_range(0, 3)]
	var length := rng.randi_range(1, 8)
	var result: Dictionary = {}
	match kind:
		"road", "rail", "power":
			# Clear the way first, as a player would, then build.
			var tool: int = {"road": Tools.Kind.ROAD, "rail": Tools.Kind.RAIL, "power": Tools.Kind.POWER_LINE}[kind]
			var from := _clamp(anchor + dir)
			var to := _clamp(anchor + dir * length)
			builder.apply(Tools.Kind.BULLDOZE, from, to)
			result = builder.apply(tool, from, to)
		"highway":
			var from := _clamp(anchor + dir * 2)
			var to := _clamp(anchor + dir * (2 + 2 * rng.randi_range(1, 4)))
			var side := Vector2i(dir.y, dir.x)
			builder.apply(Tools.Kind.BULLDOZE, from, to)
			builder.apply(Tools.Kind.BULLDOZE, _clamp(from + side), _clamp(to + side))
			result = builder.apply(Tools.Kind.HIGHWAY, from, to)
		"onramp":
			# Beside an existing highway cell, cleared first.
			var highways: Array[Vector2i] = []
			for cell: Vector2i in nets:
				if NetworkShapes.is_highway(city.building.atv(cell)): highways.append(cell)
			for attempt: int in 16:
				if highways.is_empty(): break
				var high: Vector2i = highways[rng.randi_range(0, highways.size() - 1)]
				var at := _clamp(high + DIRS[rng.randi_range(0, 3)])
				if NetworkShapes.is_highway(city.building.atv(at)): continue
				builder.apply(Tools.Kind.BULLDOZE, at, at)
				result = builder.apply(Tools.Kind.ONRAMP, at, at)
				if bool(result.get("ok", false)): break
		"bulldoze":
			result = builder.apply(Tools.Kind.BULLDOZE, anchor, _clamp(anchor + dir * rng.randi_range(0, 3)))
		"bridge":
			# From a network cell across the first water to past the far bank.
			var tool: int = Tools.Kind.ROAD if rng.randi() % 2 == 0 else Tools.Kind.RAIL
			for attempt: int in 24:
				var start: Vector2i = nets[rng.randi_range(0, nets.size() - 1)]
				var d: Vector2i = DIRS[rng.randi_range(0, 3)]
				var first := -1
				for n: int in range(1, 16):
					var c := start + d * n
					if not city.in_bounds(c.x, c.y): break
					if city.is_water(c.x, c.y):
						first = n
						break
				if first < 2: continue
				var last := first
				while last < 30 and city.in_bounds(start.x + d.x * (last + 1), start.y + d.y * (last + 1)) and city.is_water(start.x + d.x * (last + 1), start.y + d.y * (last + 1)): last += 1
				var from := start + d * (first - 1)
				var to := start + d * (last + 2)
				if not city.in_bounds(to.x, to.y): continue
				builder.apply(Tools.Kind.BULLDOZE, from, from)
				builder.apply(Tools.Kind.BULLDOZE, to - d, to)
				result = builder.apply(tool, from, to)
				if bool(result.get("ok", false)): break
		"tunnel":
			for attempt: int in 16:
				var at := _clamp(anchor + DIRS[attempt % 4] * (1 + attempt / 4))
				result = builder.apply(Tools.Kind.TUNNEL, at, at)
				if bool(result.get("ok", false)): break
		"raw_network":
			var codes: Array[int] = []
			for code: int in Buildings.COUNT:
				if CityTrafficGraph.network_kinds()[code] != 0: codes.append(code)
			for n: int in rng.randi_range(1, 3):
				var at := _clamp(anchor + DIRS[rng.randi_range(0, 3)] * rng.randi_range(0, 2))
				city.building.put(at.x, at.y, codes[rng.randi_range(0, codes.size() - 1)])
				city.flags.put(at.x, at.y, city.flags.at(at.x, at.y) ^ (RotationMapper.AXIS_FLAG if rng.randi() % 2 == 0 else 0))
			result = {"ok": true}
		"raw_clear":
			city.building.put(anchor.x, anchor.y, Buildings.NONE)
			result = {"ok": true}
		"lots", "cover":
			var placed := 0
			for attempt: int in 40:
				var at := _clamp(anchor + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4)))
				if city.is_water(at.x, at.y) or CityTrafficGraph.network_kinds()[city.building.at(at.x, at.y)] != 0: continue
				var code: int = Buildings.RES_1X1_FIRST + rng.randi_range(0, 40) if kind == "lots" else [Buildings.NONE, Buildings.TREES_1, Buildings.RUBBLE_1, Buildings.SMALL_PARK][rng.randi_range(0, 3)]
				city.building.put(at.x, at.y, code)
				placed += 1
				if placed >= 3: break
			result = {"ok": placed > 0}
		"traffic":
			for n: int in 6:
				city.traffic.put(rng.randi_range(0, city.traffic.width - 1), rng.randi_range(0, city.traffic.height - 1), rng.randi_range(0, 255))
			result = {"ok": true}
	return kind if bool(result.get("ok", false)) else ""
