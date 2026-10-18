# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Altitude-based vegetation zones for natural tree tiles.
##
## Every tree tile keeps its saved code (TREES_1..TREES_7, its density); its
## ground level chooses which kind of tree grows there: desert palms low down,
## piñon and juniper woodland above, and pines at the top. The zones are a
## per-city presentation choice saved with the city. They never change the
## simulation, the map data or tree placement.
##
## A city's `vegetation` dictionary is empty while the zones are automatic. It
## then follows the terrain: real elevations for real-world cities, otherwise
## the share of the city's own relief. Once the player sets the zones it holds
## {"version": 1, "enabled": [palms, piñon-juniper, pines], "cutoffs": [a, b]}.
## A tile at ground level L belongs to the higher of two neighboring enabled
## zones when L reaches the cutoff that follows the lower zone; cutoff[0] ends
## the palms, cutoff[1] ends the piñon-juniper woodland. At least one zone is
## always enabled.
class_name VegetationZones
extends RefCounted

enum Zone { PALM, PINYON_JUNIPER, PINE }

const ZONES := [Zone.PALM, Zone.PINYON_JUNIPER, Zone.PINE]
const VERSION := 1
## Ground levels 0..31; a cutoff of LEVELS leaves the zone above it empty.
const LEVELS := 32

const TITLES := ["Desert palms", "Piñon and juniper", "Pines"]
const SHORT_TITLES := ["Palms", "Piñon-juniper", "Pines"]
## Mid-century map tones: warm oasis gold, sage woodland, deep forest green.
const COLORS := [Color("d6b25e"), Color("8ea47a"), Color("3f6b4c")]

## One name per density (TREES_1..TREES_7) for each zone.
const NAMES := [
	["Lone Palm", "Palm Pair", "Palm Cluster", "Palm Grove", "Dense Grove", "Oasis Thicket", "Riparian Woodland"],
	["Lone Juniper", "Piñon Pair", "Juniper Cluster", "Piñon-Juniper Stand", "Dense Piñon-Juniper", "Piñon Thicket", "Piñon-Juniper Woodland"],
	["Lone Pine", "Pine Pair", "Pine Cluster", "Pine Stand", "Dense Pines", "Pine Thicket", "Pine Forest"],
]

## Automatic zones for real-world cities: Mojave scrub and palms below about
## 1,500 m, Great Basin piñon-juniper to about 2,100 m, then pine forest.
const REAL_PINYON_METRES := 1500.0
const REAL_PINE_METRES := 2100.0
## Automatic zones elsewhere follow the city's own relief between its lowest
## and highest dry ground: gentle cities stay palm desert. The relief ignores
## the lowest and highest RELIEF_TRIM of the ground, so a small terrain edit
## cannot move every boundary (and replant trees city-wide).
const RELATIVE_WOODLAND_SPAN := 6
const RELATIVE_FOREST_SPAN := 12
const RELIEF_TRIM := 0.01
## Metres per ground level for cities without real elevation data:
## CityGeometry3D.HEIGHT tiles per level at 16 m per tile.
const METRES_PER_LEVEL := 0.6123724357 * 16.0

static var _auto_city: WeakRef
static var _auto_altitude := PackedInt32Array()
static var _auto_terrain := PackedByteArray()
static var _auto_scale: Dictionary = {}
static var _auto_value: Dictionary = {}


## A complete validated settings record, or {} when `value` is not one.
static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var record: Dictionary = value
	if record.size() != 3 or not record.has("version") or not record.has("enabled") or not record.has("cutoffs"):
		return {}
	if typeof(record.version) not in [TYPE_INT, TYPE_FLOAT] or int(record.version) != VERSION or float(record.version) != float(VERSION):
		return {}
	if not record.enabled is Array or (record.enabled as Array).size() != 3:
		return {}
	if not record.cutoffs is Array or (record.cutoffs as Array).size() != 2:
		return {}
	var enabled: Array[bool] = []
	for on: Variant in record.enabled:
		if typeof(on) != TYPE_BOOL: return {}
		enabled.append(bool(on))
	if not enabled.has(true):
		return {}
	var cutoffs: Array[int] = []
	for cut: Variant in record.cutoffs:
		if typeof(cut) not in [TYPE_INT, TYPE_FLOAT] or float(cut) != floorf(float(cut)): return {}
		if int(cut) < 0 or int(cut) > LEVELS: return {}
		cutoffs.append(int(cut))
	if cutoffs[0] > cutoffs[1]:
		return {}
	return make(enabled, cutoffs)


## A settings record from parts; the caller guarantees the invariants.
static func make(enabled: Array, cutoffs: Array) -> Dictionary:
	return {"version": VERSION, "enabled": [bool(enabled[0]), bool(enabled[1]), bool(enabled[2])],
		"cutoffs": [int(cutoffs[0]), int(cutoffs[1])]}


## The zones in effect: the city's saved choice, or the automatic zones for
## its current terrain. Always valid; "automatic" tells which.
static func resolve(city: City) -> Dictionary:
	var saved := sanitize(city.vegetation) if city != null else {}
	if not saved.is_empty():
		var out := saved.duplicate(true)
		out["automatic"] = false
		return out
	var out := automatic(city).duplicate(true)
	out["automatic"] = true
	return out


## Automatic zones for the city's current terrain. Cached per city until its
## altitude, terrain or real-world origin changes.
static func automatic(city: City) -> Dictionary:
	if city == null:
		return make([true, true, true], [LEVELS, LEVELS])
	var scale := real_scale(city)
	if _auto_city != null and _auto_city.get_ref() == city and city.altitude.data == _auto_altitude \
			and city.terrain.data == _auto_terrain and scale == _auto_scale:
		return _auto_value
	var value := _compute_automatic(city)
	_auto_city = weakref(city)
	_auto_altitude = city.altitude.data.duplicate()
	_auto_terrain = city.terrain.data.duplicate()
	_auto_scale = scale
	_auto_value = value
	return value


static func _compute_automatic(city: City) -> Dictionary:
	var scale := real_scale(city)
	if not scale.is_empty():
		return make([true, true, true], [level_for_metres(scale, REAL_PINYON_METRES), level_for_metres(scale, REAL_PINE_METRES)])
	var range := relief_range(histogram(city)[0])
	if range.x < 0:
		return make([true, true, true], [LEVELS, LEVELS])
	var span := range.y - range.x
	if span < RELATIVE_WOODLAND_SPAN:
		return make([true, true, true], [LEVELS, LEVELS])
	if span < RELATIVE_FOREST_SPAN:
		return make([true, true, true], [range.x + ceili(span * 0.6), LEVELS])
	return make([true, true, true], [range.x + ceili(span * 0.5), range.x + ceili(span * 0.78)])


## Real-world cities record their source elevation: level L stands at
## minimum + (L - 2) × metres per level. {} for every other city.
static func real_scale(city: City) -> Dictionary:
	if city == null or city.terrain_origin.is_empty():
		return {}
	var diagnostics: Variant = city.terrain_origin.get("diagnostics")
	if not diagnostics is Dictionary:
		return {}
	var minimum: Variant = diagnostics.get("source_min_metres")
	var per_level: Variant = diagnostics.get("metres_per_level")
	if typeof(minimum) not in [TYPE_INT, TYPE_FLOAT] or typeof(per_level) not in [TYPE_INT, TYPE_FLOAT] or float(per_level) <= 0.0:
		return {}
	return {"minimum": float(minimum), "per_level": float(per_level)}


## The lowest level at or above `metres` for a real-world scale.
static func level_for_metres(scale: Dictionary, metres: float) -> int:
	return clampi(ceili(2.0 + (metres - float(scale.minimum)) / float(scale.per_level) - 0.000001), 0, LEVELS)


## Elevation of a ground level in metres: real metres for real-world cities,
## otherwise height above level 0.
static func metres_for_level(city: City, level: int) -> float:
	var scale := real_scale(city)
	if scale.is_empty():
		return level * METRES_PER_LEVEL
	return float(scale.minimum) + (level - 2) * float(scale.per_level)


## Lowest and highest dry ground level, or (-1, -1) for an all-water map.
static func land_range(city: City) -> Vector2i:
	return land_range_of(histogram(city)[0])


## Ground levels at the RELIEF_TRIM and 1 - RELIEF_TRIM shares of the dry
## ground, or (-1, -1) for an all-water map.
static func relief_range(counts: PackedInt32Array) -> Vector2i:
	var total := 0
	for count: int in counts: total += count
	if total == 0:
		return Vector2i(-1, -1)
	var low_share := maxi(1, ceili(total * RELIEF_TRIM))
	var high_share := maxi(1, total - floori(total * RELIEF_TRIM))
	var lo := -1
	var hi := -1
	var seen := 0
	for level: int in counts.size():
		seen += counts[level]
		if lo < 0 and seen >= low_share: lo = level
		if hi < 0 and seen >= high_share: hi = level
	return Vector2i(lo, hi)


## Lowest and highest level with any count, or (-1, -1).
static func land_range_of(counts: PackedInt32Array) -> Vector2i:
	var lo := -1
	var hi := -1
	for level: int in LEVELS:
		if counts[level] == 0: continue
		if lo < 0: lo = level
		hi = level
	return Vector2i(lo, hi)


## [dry tiles per ground level, tree tiles per ground level].
static func histogram(city: City) -> Array:
	var land := PackedInt32Array()
	land.resize(LEVELS)
	var trees := PackedInt32Array()
	trees.resize(LEVELS)
	if city == null:
		return [land, trees]
	var altitude := city.altitude.data
	var terrain := city.terrain.data
	var building := city.building.data
	for i: int in altitude.size():
		if Terrain.is_water(terrain[i]): continue
		var level: int = altitude[i] & City.ALT_MASK
		land[level] += 1
		if Buildings.is_tree(building[i]): trees[level] += 1
	return [land, trees]


## Enabled zones in elevation order.
static func enabled_zones(settings: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for zone: int in ZONES:
		if settings.enabled[zone]: out.append(zone)
	return out


## Zone per ground level 0..LEVELS-1, for tile loops: index by
## `altitude & City.ALT_MASK`.
static func level_table(settings: Dictionary) -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(LEVELS)
	for level: int in LEVELS: table[level] = zone_for_level(settings, level)
	return table


## The zone of a tile at ground `level`.
static func zone_for_level(settings: Dictionary, level: int) -> int:
	var cutoffs: Array = settings.cutoffs
	var zone := -1
	for candidate: int in ZONES:
		if not settings.enabled[candidate]: continue
		if zone < 0 or level >= int(cutoffs[zone]): zone = candidate
	return maxi(zone, Zone.PALM)


static func zone_at(city: City, cell: Vector2i, settings: Dictionary = {}) -> int:
	if settings.is_empty(): settings = resolve(city)
	return zone_for_level(settings, city.ground_height(cell.x, cell.y))


## The cutoff a handle between `lower` and the next enabled zone moves.
static func boundary_cutoff(lower: int) -> int:
	return clampi(lower, 0, 1)


## Settings with one boundary moved, keeping cutoff[0] <= cutoff[1].
static func with_cutoff(settings: Dictionary, index: int, level: int) -> Dictionary:
	var cutoffs: Array = (settings.cutoffs as Array).duplicate()
	level = clampi(level, 0, LEVELS)
	cutoffs[index] = level
	if index == 0 and cutoffs[1] < level: cutoffs[1] = level
	if index == 1 and cutoffs[0] > level: cutoffs[0] = level
	return make(settings.enabled, cutoffs)


## Settings with one zone switched; refuses to switch off the last zone.
static func with_enabled(settings: Dictionary, zone: int, on: bool) -> Dictionary:
	var enabled: Array = (settings.enabled as Array).duplicate()
	enabled[zone] = on
	if not enabled.has(true):
		return make(settings.enabled, settings.cutoffs)
	return make(enabled, settings.cutoffs)


## Player-facing name of a tree tile at `cell`.
static func tree_name(city: City, cell: Vector2i, code: int) -> String:
	var density := clampi(code - Buildings.TREES_1, 0, 6)
	return String(NAMES[zone_at(city, cell)][density])


## Tree tiles per zone under `settings`; pass `trees` (histogram()[1]) to
## avoid scanning the map again.
static func zone_tree_counts(city: City, settings: Dictionary, trees := PackedInt32Array()) -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0, 0])
	if trees.is_empty(): trees = histogram(city)[1]
	for level: int in LEVELS:
		counts[zone_for_level(settings, level)] += trees[level]
	return counts
