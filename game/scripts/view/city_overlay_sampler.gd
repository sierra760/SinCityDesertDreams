# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only data sampling and authored analytical palettes.
## Camera rotation never participates in city grid lookup.
class_name CityOverlaySampler
extends RefCounted

## Overlay kinds, in the order the cycle key steps through them.
const LAYERS: Array[StringName] = [&"zones", &"power", &"water", &"crime", &"pollution",
	&"land_value", &"traffic", &"police", &"fire", &"density", &"growth"]

## Tiles per side of one grid cell for each kind.
const TILES_PER_CELL := {
	&"zones": 1, &"power": 1, &"water": 1,
	&"crime": 2, &"pollution": 2, &"land_value": 2, &"traffic": 2,
	&"police": 4, &"fire": 4, &"density": 4, &"growth": 4,
}

const MAX_ALPHA := 0.55
## Growth is stored around a neutral point; values near it draw nothing.
const GROWTH_NEUTRAL := 128
const GROWTH_DEAD_BAND := 3

const RAMPS := {
	&"crime": [Color(0.95, 0.35, 0.15), Color(0.85, 0.05, 0.05)],
	&"pollution": [Color(0.9, 0.6, 0.2), Color(0.45, 0.27, 0.07)],
	&"land_value": [Color(0.95, 0.78, 0.1), Color(0.2, 0.7, 0.2)],
	&"traffic": [Color(0.2, 0.75, 0.2), Color(0.9, 0.12, 0.05)],
	&"police": [Color(0.45, 0.6, 0.95), Color(0.08, 0.2, 0.85)],
	&"fire": [Color(0.95, 0.72, 0.35), Color(0.9, 0.45, 0.05)],
	&"density": [Color(0.75, 0.5, 0.9), Color(0.5, 0.1, 0.7)],
}
const GROWTH_UP := Color(0.1, 0.85, 0.85)
const GROWTH_DOWN := Color(0.9, 0.1, 0.1)
const POWERED := Color(0.95, 0.85, 0.2)
const UNPOWERED := Color(0.9, 0.2, 0.15)
const WATERED := Color(0.25, 0.55, 0.95)
const UNWATERED := Color(0.9, 0.3, 0.2)

const ZONE_TINTS := {
	Zones.RES_LOW: Color(0.45, 0.85, 0.45),
	Zones.RES_HIGH: Color(0.20, 0.60, 0.25),
	Zones.COM_LOW: Color(0.45, 0.60, 0.95),
	Zones.COM_HIGH: Color(0.20, 0.35, 0.80),
	Zones.IND_LOW: Color(0.95, 0.85, 0.35),
	Zones.IND_HIGH: Color(0.75, 0.62, 0.15),
	Zones.MILITARY: Color(0.55, 0.60, 0.45),
	Zones.AIRPORT: Color(0.75, 0.75, 0.80),
	Zones.SEAPORT: Color(0.45, 0.70, 0.75),
}

static func tiles_per_cell(kind: StringName) -> int:
	return TILES_PER_CELL.get(kind, 0)


static func value_at(city: City, kind: StringName, tile: Vector2i) -> int:
	if city == null or not city.in_bounds(tile.x, tile.y):
		return 0
	match kind:
		&"crime": return city.crime_at(tile.x, tile.y)
		&"pollution": return city.pollution_at(tile.x, tile.y)
		&"land_value": return city.land_value_at(tile.x, tile.y)
		&"traffic": return city.traffic_at(tile.x, tile.y)
		&"police": return city.police_at(tile.x, tile.y)
		&"fire": return city.fire_cover_at(tile.x, tile.y)
		&"density": return city.density_at(tile.x, tile.y)
		&"growth": return city.growth_at(tile.x, tile.y)
		&"power":
			if not city.conducts_power(tile.x, tile.y):
				return 0
			return 255 if city.is_powered(tile.x, tile.y) else 128
		&"water":
			if not city.conducts_water(tile.x, tile.y):
				return 0
			return 255 if city.is_watered(tile.x, tile.y) else 128
		&"zones": return city.zone_kind_at(tile.x, tile.y)
	return 0


static func cell_color(kind: StringName, value: int) -> Color:
	match kind:
		&"power":
			if value == 0:
				return Color.TRANSPARENT
			var c := POWERED if value == 255 else UNPOWERED
			return Color(c.r, c.g, c.b, MAX_ALPHA)
		&"water":
			if value == 0:
				return Color.TRANSPARENT
			var c := WATERED if value == 255 else UNWATERED
			return Color(c.r, c.g, c.b, MAX_ALPHA)
		&"zones":
			if value == Zones.NONE:
				return Color.TRANSPARENT
			var tint: Color = ZONE_TINTS.get(value, Color(0.7, 0.7, 0.7))
			return Color(tint.r, tint.g, tint.b, MAX_ALPHA * 0.8)
		&"growth":
			var deviation := value - GROWTH_NEUTRAL
			if absi(deviation) <= GROWTH_DEAD_BAND:
				return Color.TRANSPARENT
			var t := clampf(absf(deviation) / 127.0, 0.0, 1.0)
			var base := GROWTH_UP if deviation > 0 else GROWTH_DOWN
			return Color(base.r, base.g, base.b, sqrt(t) * MAX_ALPHA)
	if not RAMPS.has(kind) or value <= 0:
		return Color.TRANSPARENT
	var ramp: Array = RAMPS[kind]
	var tv := clampf(value / 255.0, 0.0, 1.0)
	var low: Color = ramp[0]
	var high: Color = ramp[1]
	var c := low.lerp(high, tv)
	return Color(c.r, c.g, c.b, sqrt(tv) * MAX_ALPHA)


static func legend_entries(kind: StringName) -> Array:
	match kind:
		&"", &"none": return [[Color.TRANSPARENT, "No overlay drawn"]]
		&"power": return [[POWERED, "Powered"], [UNPOWERED, "Unpowered"]]
		&"water": return [[WATERED, "Watered"], [UNWATERED, "Unwatered"]]
		&"growth": return [[GROWTH_UP, "Growing"], [GROWTH_DOWN, "Declining"]]
		&"zones":
			var result: Array = []
			for zone_kind: int in ZONE_TINTS:
				result.append([ZONE_TINTS[zone_kind], String(Zones.NAMES.get(zone_kind, "Zone"))])
			return result
	if RAMPS.has(kind):
		return [[RAMPS[kind][0], "Low"], [RAMPS[kind][1], "High"]]
	return []
