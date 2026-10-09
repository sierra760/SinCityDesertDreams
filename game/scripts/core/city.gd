# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The city: map layers, metadata and facility records.
##
## This is data, not behavior. Systems read and write it through the accessors
## below; the renderer reads it. Nothing here knows how the simulation works.
class_name City
extends RefCounted

const WIDTH := 128
const HEIGHT := 128
const HALF := 64
const QUARTER := 32

## Difficulty levels and their starting funds.
enum Difficulty { EASY, MEDIUM, HARD }
const STARTING_FUNDS := {Difficulty.EASY: 20000, Difficulty.MEDIUM: 10000, Difficulty.HARD: 10000}

var name := "New City"
var mayor := "Mayor"
var founded_year := 1900
var day := 0                 ## days since founding; 300 per year
var funds := 20000
var difficulty := Difficulty.EASY
var rotation := 0            ## view rotation 0..3, persisted with the city
var sea_level := -1          ## global water height, -1 when only per-tile water applies
var status := 0              ## settlement class: village .. megalopolis, see population system
var signs: Dictionary = {}   ## Vector2i -> String
## Applied street memberships and derived automatic station names only.
var street_naming: Dictionary = {"schema":1,"next_street_id":1,"streets":{},"links":{},"station_auto":{}}
## Conductive links from imported cities that the building ID alone cannot express.
## Row-major index -> Vector2i(building ID, zone kind). Edits expire the link.
var imported_power_links: Dictionary = {}
## Optional record of where imported terrain came from. Assignment deep-copies
## the dictionary; saves keep only the bounded manifest fields.
var terrain_origin: Dictionary = {}:
	set(value):
		terrain_origin = value.duplicate(true)

## Full-resolution layers.
var terrain := Grid8.new()
var altitude := Grid16.new()
var building := Grid8.new()
var zone := Grid8.new()
var flags := Grid8.new()
var underground := Grid8.new()

## Half-resolution maps (one byte per 2×2 block).
var traffic := Grid8.new(HALF, HALF)
var pollution := Grid8.new(HALF, HALF)
var land_value := Grid8.new(HALF, HALF)
var crime := Grid8.new(HALF, HALF)

## Quarter-resolution maps (one byte per 4×4 block).
var police := Grid8.new(QUARTER, QUARTER)
var fire_cover := Grid8.new(QUARTER, QUARTER)
var density := Grid8.new(QUARTER, QUARTER)
var growth := Grid8.new(QUARTER, QUARTER)

## Facility records keyed by anchor tile (Vector2i). Each is a Dictionary with
## at least "key" (building key) and "built_day"; systems add their own fields.
var facilities: Dictionary = {}

## Shared-vertex terrain lattice used by the terrain editor; may be null for
## imported cities until the terrain module rebuilds it.
var terrain_surface = null

## Temporary flood overlay maintained by the disaster system: tile -> depth.
var flood_overlay: Dictionary = {}

## Names of the layers read from a native save of a city in play (layer name ->
## true). Not saved. Systems keep these layers as saved when the simulation is
## set up, instead of deriving them again, so a reload continues exactly.
var restored_layers: Dictionary = {}

## Altitude packing: ground height in the low five bits, water height in the
## next five, tunnel direction bits above that.
const ALT_MASK := 0x1F
const WATER_SHIFT := 5
const TUNNEL_SHIFT := 10


func _init() -> void:
	pass


# ── Metadata ─────────────────────────────────────────────────────────────

func current_year() -> int:
	return founded_year + day / GameClock.DAYS_PER_YEAR


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < WIDTH and y < HEIGHT


# ── Altitude ─────────────────────────────────────────────────────────────

func ground_height(x: int, y: int) -> int:
	return altitude.at(x, y) & ALT_MASK


func water_height(x: int, y: int) -> int:
	return (altitude.at(x, y) >> WATER_SHIFT) & ALT_MASK


func set_heights(x: int, y: int, ground: int, water: int = -1) -> void:
	var v := altitude.at(x, y)
	if water < 0:
		water = (v >> WATER_SHIFT) & ALT_MASK
	var tunnel := v >> TUNNEL_SHIFT
	altitude.put(x, y, (ground & ALT_MASK) | ((water & ALT_MASK) << WATER_SHIFT) | (tunnel << TUNNEL_SHIFT))


func tunnel_bits(x: int, y: int) -> int:
	return altitude.at(x, y) >> TUNNEL_SHIFT


func set_tunnel_bits(x: int, y: int, bits: int) -> void:
	var v := altitude.at(x, y) & ((1 << TUNNEL_SHIFT) - 1)
	altitude.put(x, y, v | (bits << TUNNEL_SHIFT))


# ── Terrain and water ────────────────────────────────────────────────────

func is_water(x: int, y: int) -> bool:
	if flood_overlay.has(Vector2i(x, y)):
		return true
	return Terrain.is_water(terrain.at(x, y))


func is_open_water(x: int, y: int) -> bool:
	return Terrain.is_open_water(terrain.at(x, y))


func is_flat(x: int, y: int) -> bool:
	return Terrain.is_flat(terrain.at(x, y))


func is_salt_water(x: int, y: int) -> bool:
	return flags.has_bits(x, y, TileFlags.SALT_WATER)


# ── Buildings and footprints ─────────────────────────────────────────────

func building_at(x: int, y: int) -> int:
	return building.at(x, y)


func zone_kind_at(x: int, y: int) -> int:
	return Zones.kind(zone.at(x, y))


## Anchor (north-west tile) of the footprint that covers (x, y), or (x, y)
## itself for single tiles and empty ground.
func anchor_of(x: int, y: int) -> Vector2i:
	return footprint_anchor(building.data, zone.data, x, y)


## `anchor_of` on bare row-major building and zone layers, so packed scans
## (UtilityParams.is_anchor_tile) resolve footprints exactly like the city.
static func footprint_anchor(bld: PackedByteArray, zn: PackedByteArray, x: int, y: int) -> Vector2i:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return Vector2i(x, y)
	var id := bld[y * WIDTH + x]
	var packed := _sizes[id]
	if packed == 0x0101:
		return Vector2i(x, y)
	var s := Vector2i(packed & 0xFF, packed >> 8)
	# A box starting k rows above this cell covers the k cells above it in
	# this column, and likewise to the left, so only boxes within the runs
	# of the same id above and to the left can hold only `id`. With neither
	# run, only this cell's own box can match and the fallback walk stays.
	var west := x > 0 and bld[y * WIDTH + x - 1] == id
	var north := y > 0 and bld[(y - 1) * WIDTH + x] == id
	if not west and not north:
		return Vector2i(x, y)
	var up := 0
	while up < s.y - 1 and y - up > 0 and bld[(y - up - 1) * WIDTH + x] == id:
		up += 1
	var left := 0
	while left < s.x - 1 and x - left > 0 and bld[y * WIDTH + x - left - 1] == id:
		left += 1
	# A footprint's four corner cells carry one corner flag each, running
	# clockwise around the lot. The flags name the corners of the lot as it
	# was laid out, so a lot loaded in another orientation carries the same
	# four flags shifted around its ring; only the cyclic order is fixed.
	# Try every box of the right size that contains this cell and accept the
	# one whose corners form that ring, which also tells apart two lots of the
	# same kind standing side by side. Four identical 2×2 lots in a square
	# also form such a ring across their inner corners; a box in this game's
	# own orientation (CORNER_NW on its top-left tile) wins over that.
	var first := Vector2i(-1, -1)
	for ay in range(y - up, y + 1):
		if ay + s.y > HEIGHT:
			continue
		var row := ay * WIDTH
		for ax in range(x - left, x + 1):
			if ax + s.x > WIDTH:
				continue
			# Most boxes fail on their first corner: skip them before the call.
			var flag := zn[row + ax] & Zones.CORNER_MASK
			if flag == 0 or (flag & (flag - 1)) != 0:
				continue
			if _is_footprint(bld, zn, ax, ay, id, s):
				if flag == Zones.CORNER_NW:
					return Vector2i(ax, ay)
				if first.x < 0:
					first = Vector2i(ax, ay)
	if first.x >= 0:
		return first
	# Without usable corner flags, walk to the top-left of the same-id block.
	var ax := x
	var ay := y
	for _i in s.x:
		if zn[ay * WIDTH + ax] & (Zones.CORNER_NW | Zones.CORNER_SW):
			break
		if ax == 0 or bld[ay * WIDTH + ax - 1] != id:
			break
		ax -= 1
	for _i in s.y:
		if zn[ay * WIDTH + ax] & Zones.CORNER_NW:
			break
		if ay == 0 or bld[(ay - 1) * WIDTH + ax] != id:
			break
		ay -= 1
	return Vector2i(ax, ay)


## Whether (x, y) is its own `footprint_anchor`, answered without the box
## search for most cells: a cell is an anchor only when the box it would
## start is a valid footprint or the fallback walk would not leave it.
static func is_footprint_anchor(bld: PackedByteArray, zn: PackedByteArray, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return true
	var i := y * WIDTH + x
	var id := bld[i]
	var packed := _sizes[id]
	if packed == 0x0101:
		return true
	var west := x > 0 and bld[i - 1] == id
	var north := y > 0 and bld[i - WIDTH] == id
	if not west and not north:
		return true
	var corners := zn[i]
	var walks := ((corners & (Zones.CORNER_NW | Zones.CORNER_SW)) == 0 and west) \
		or ((corners & Zones.CORNER_NW) == 0 and north)
	if walks:
		var flag := corners & Zones.CORNER_MASK
		if flag == 0 or (flag & (flag - 1)) != 0 \
				or not _is_footprint(bld, zn, x, y, id, Vector2i(packed & 0xFF, packed >> 8)):
			return false
	return footprint_anchor(bld, zn, x, y) == Vector2i(x, y)


## Footprint width | height << 8 per building id, filled when the class
## loads so concurrent readers never see it half built.
static var _sizes: PackedInt32Array = _build_footprint_sizes()


static func _build_footprint_sizes() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		var s := Buildings.size(id)
		out[id] = s.x | (s.y << 8)
	return out


## True when the box at (ax, ay) of size `s` holds only `id` and its corner
## cells carry a clockwise ring of single corner flags. The cheap ring test
## runs first: nearly every candidate box fails it.
static func _is_footprint(bld: PackedByteArray, zn: PackedByteArray, ax: int, ay: int, id: int, s: Vector2i) -> bool:
	var ex := ax + s.x - 1
	var ey := ay + s.y - 1
	if ax < 0 or ay < 0 or ex >= WIDTH or ey >= HEIGHT:
		return false
	var flag := zn[ay * WIDTH + ax] & Zones.CORNER_MASK
	if flag == 0 or (flag & (flag - 1)) != 0:
		return false
	var next := zn[ay * WIDTH + ex] & Zones.CORNER_MASK
	if next != _next_corner(flag):
		return false
	flag = next
	next = zn[ey * WIDTH + ex] & Zones.CORNER_MASK
	if next != _next_corner(flag):
		return false
	flag = next
	next = zn[ey * WIDTH + ax] & Zones.CORNER_MASK
	if next != _next_corner(flag):
		return false
	# The ring closes back on the first corner by construction: four
	# clockwise steps from any single corner return to it.
	for yy in range(ay, ey + 1):
		var row := yy * WIDTH
		for xx in range(ax, ex + 1):
			if bld[row + xx] != id:
				return false
	return true


## The corner flag clockwise from a single corner flag.
static func _next_corner(flag: int) -> int:
	return Zones.CORNER_NW if flag == Zones.CORNER_SW else flag << 1


## Place a building and stamp its footprint. Does not validate; that is the
## Builder's job. Returns the anchor.
func stamp_building(x: int, y: int, id: int, zone_kind: int = -1) -> Vector2i:
	var s := Buildings.size(id)
	for dy in s.y:
		for dx in s.x:
			imported_power_links.erase((y + dy) * WIDTH + x + dx)
			building.put(x + dx, y + dy, id)
			var zk := zone_kind if zone_kind >= 0 else Zones.kind(zone.at(x + dx, y + dy))
			zone.put(x + dx, y + dy, Zones.make(zk, Zones.corner_flags_for(dx, dy, s.x, s.y)))
	return Vector2i(x, y)


## Clear a footprint back to open ground, keeping the zone kind.
func clear_footprint(x: int, y: int) -> Rect2i:
	var a := anchor_of(x, y)
	var id := building.at(a.x, a.y)
	var s := Buildings.size(id)
	for dy in s.y:
		for dx in s.x:
			imported_power_links.erase((a.y + dy) * WIDTH + a.x + dx)
			building.put(a.x + dx, a.y + dy, Buildings.NONE)
			var zk := Zones.kind(zone.at(a.x + dx, a.y + dy))
			zone.put(a.x + dx, a.y + dy, Zones.make(zk, Zones.ALL_CORNERS if zk != Zones.NONE else 0))
	facilities.erase(a)
	return Rect2i(a, s)


func facility(anchor: Vector2i) -> Dictionary:
	return facilities.get(anchor, {})


func has_imported_power_link(index: int) -> bool:
	if not imported_power_links.has(index): return false
	var signature: Vector2i = imported_power_links[index]
	if signature == Vector2i(building.data[index], zone.data[index] & Zones.KIND_MASK): return true
	imported_power_links.erase(index)
	return false


func add_facility(anchor: Vector2i, record: Dictionary) -> void:
	facilities[anchor] = record


func facilities_of(building_key: StringName) -> Array:
	var out: Array = []
	for anchor in facilities:
		if facilities[anchor].get("key", &"") == building_key:
			out.append(anchor)
	return out


# ── Service bits ─────────────────────────────────────────────────────────

func is_powered(x: int, y: int) -> bool:
	return flags.has_bits(x, y, TileFlags.POWERED)


func is_watered(x: int, y: int) -> bool:
	return flags.has_bits(x, y, TileFlags.WATERED)


func conducts_power(x: int, y: int) -> bool:
	return flags.has_bits(x, y, TileFlags.CONDUCTS_POWER)


func conducts_water(x: int, y: int) -> bool:
	return flags.has_bits(x, y, TileFlags.CONDUCTS_WATER)


func set_flag(x: int, y: int, mask: int, on: bool) -> void:
	flags.set_bits(x, y, mask, on)


# ── Half and quarter resolution helpers ──────────────────────────────────

func traffic_at(x: int, y: int) -> int:
	return traffic.at(x >> 1, y >> 1)


func pollution_at(x: int, y: int) -> int:
	return pollution.at(x >> 1, y >> 1)


func land_value_at(x: int, y: int) -> int:
	return land_value.at(x >> 1, y >> 1)


func crime_at(x: int, y: int) -> int:
	return crime.at(x >> 1, y >> 1)


func police_at(x: int, y: int) -> int:
	return police.at(x >> 2, y >> 2)


func fire_cover_at(x: int, y: int) -> int:
	return fire_cover.at(x >> 2, y >> 2)


func density_at(x: int, y: int) -> int:
	return density.at(x >> 2, y >> 2)


func growth_at(x: int, y: int) -> int:
	return growth.at(x >> 2, y >> 2)


# ── Statistics ───────────────────────────────────────────────────────────

## Count of anchors per building id, computed on demand.
func building_census() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(Buildings.COUNT)
	for y in HEIGHT:
		for x in WIDTH:
			var id := building.at(x, y)
			if id == Buildings.NONE:
				continue
			if Buildings.is_multi_tile(id) and not (Zones.corners(zone.at(x, y)) & Zones.CORNER_NW):
				continue
			counts[id] += 1
	return counts


func duplicate_city() -> City:
	var c := City.new()
	c.name = name
	c.mayor = mayor
	c.founded_year = founded_year
	c.day = day
	c.funds = funds
	c.difficulty = difficulty
	c.rotation = rotation
	c.sea_level = sea_level
	c.status = status
	c.signs = signs.duplicate()
	c.street_naming = street_naming.duplicate(true)
	c.terrain = terrain.duplicate_grid()
	c.altitude = altitude.duplicate_grid()
	c.building = building.duplicate_grid()
	c.zone = zone.duplicate_grid()
	c.flags = flags.duplicate_grid()
	c.underground = underground.duplicate_grid()
	c.traffic = traffic.duplicate_grid()
	c.pollution = pollution.duplicate_grid()
	c.land_value = land_value.duplicate_grid()
	c.crime = crime.duplicate_grid()
	c.police = police.duplicate_grid()
	c.fire_cover = fire_cover.duplicate_grid()
	c.density = density.duplicate_grid()
	c.growth = growth.duplicate_grid()
	c.facilities = facilities.duplicate(true)
	c.terrain_origin = terrain_origin
	c.terrain_surface = terrain_surface
	c.flood_overlay = flood_overlay.duplicate()
	c.restored_layers = restored_layers.duplicate()
	return c
