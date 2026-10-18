# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Derived simulation cache. No serialization, money, RNG or view-time scans.
class_name TourismDistricts
extends RefCounted

const CATEGORIES := {
	&"small_park": &"outdoors", &"large_park": &"outdoors",
	&"museum": &"culture", &"monument": &"culture",
	&"zoo": &"recreation", &"marina": &"recreation",
	&"stadium": &"entertainment", &"neon_dome": &"entertainment"}
const BIN := 8
var _access := TourismAccess.new()
var _access_version := -1
var _city: City
var _buildings := PackedInt32Array()
var _zones := PackedByteArray()
var _flags := PackedByteArray()
var _terrain := PackedByteArray()
var _altitude := PackedInt32Array()
var _fires: Array = []
var _flooded := PackedInt32Array()
var _attendance: Array = []
var _attractions: Dictionary = {}
var _shops: Dictionary = {}
var _event_hosts := {"stadium":false,"city_hall":false}
## Tiles whose served bits the last _discover read, and those bits. Discovery
## reads only buildings, zones, terrain, flooding, fires and these bits; other
## flag bits, altitude and route versions change only the influence rebuild.
var _served_tiles := PackedInt32Array()
var _served_bits := PackedByteArray()
## Complete sites depend only on building and zone bytes. Service/flood/fire
## changes reuse them, while detached native comparisons catch raw edits.
var _site_inputs: Array = []
var _sites: Array[Dictionary] = []
var _inputs: Dictionary = {}
var _distribution: Dictionary = {}
var _summary := {"available_spending_cents":0, "accepted_spending_cents":0, "recipient_capacity_cents":0,
	"allocated_spending_cents":0, "unallocated_spending_cents":0, "commercial_demand_bonus":0}

## Packed comparisons also catch raw disaster/import edits. Discovery/influence
## rebuild only in simulation hooks; all public read methods return cached data.
func refresh(ctx: SimContext, rows: Array[Dictionary], access: TourismAccess = null) -> void:
	if access != null: _access = access
	else: _access.refresh(ctx)
	var city := ctx.city
	var fires: Array = []
	var disasters := ctx.system(&"disasters")
	if disasters != null and disasters.has_method("fires"):
		fires = disasters.call("fires")
	# is_water reads temporary flood membership independently of terrain. Keep
	# fresh sorted tile indices: overlay order/depth cannot affect eligibility,
	# and retaining the live Dictionary would hide in-place flood/drain edits.
	var flooded := PackedInt32Array()
	for tile: Variant in city.flood_overlay:
		if tile is Vector2i and city.in_bounds(tile.x,tile.y):
			flooded.append(tile.y * City.WIDTH + tile.x)
	flooded.sort()
	var attendance: Array = []
	for row in rows:
		attendance.append([row.anchor,row.key,row.get("instance",0),row.guests,row.day_visitors,row.operating,TourismMarkets.counts(row),TourismMarkets.counts(row,true)])
	var changed := _city != city or _buildings != city.building.data or _zones != city.zone.data \
		or _flags != city.flags.data or _terrain != city.terrain.data or _altitude != city.altitude.data or _fires != fires or _flooded != flooded or _access_version != _access.version
	if not changed and attendance == _attendance:
		return
	var discover := changed and (_city != city or _buildings != city.building.data or _zones != city.zone.data \
		or _terrain != city.terrain.data or _fires != fires or _flooded != flooded or _served(city) != _served_bits)
	_city = city
	_attendance = attendance
	_access_version = _access.version
	if changed:
		_buildings = city.building.data.duplicate()
		_zones = city.zone.data.duplicate()
		_flags = city.flags.data.duplicate()
		_terrain = city.terrain.data.duplicate()
		_altitude = city.altitude.data.duplicate()
		_fires = fires.duplicate()
		_flooded = flooded
		if discover: _discover(city)
	_rebuild(city, rows)
	_access_version = _access.version

func venue_inputs(anchor: Vector2i) -> Dictionary:
	return _inputs.get(anchor, {"district_categories":{}, "attraction_appeal_bonus":0,
		"resort_variety_bonus":0, "district_appeal_bonus":0, "commercial_spending_cents":0,
		"commercial_allocated_cents":0, "district_access":"Connected road/station routes"}).duplicate(true)

func commercial_bonus(anchor: Vector2i) -> int:
	return mini(TourismParams.COMMERCIAL_GROWTH_CAP,
		int(_distribution.get(anchor,0)) / TourismParams.COMMERCIAL_CENTS_PER_POINT)

func commercial_demand_bonus() -> int:
	return int(_summary.commercial_demand_bonus)

func spending_distribution() -> Dictionary:
	return _distribution.duplicate()

func report() -> Dictionary:
	return _summary.duplicate()

## Nearby recipients additionally require exact shared transport evidence.
func district_connected(_city_unused: City, source: Rect2i, destination: Rect2i, reach: int) -> bool:
	return _distance(source,destination) <= reach and _access.district_connected(source,destination)

static var _interest := PackedByteArray()

## 1 where category != "" or key == city_hall or (commercial and not a resort).
static func _interest_table() -> PackedByteArray:
	if _interest.is_empty():
		_interest.resize(Buildings.COUNT)
		for code in Buildings.COUNT:
			var key := Buildings.key(code)
			var category: StringName = CATEGORIES.get(key,&"")
			var commercial := Buildings.category(code) == Buildings.Category.COMMERCIAL and not RewardParams.ARCOLOGIES.has(key)
			_interest[code] = 0 if category == &"" and key != &"city_hall" and not commercial else 1
	return _interest

func _served(city: City) -> PackedByteArray:
	var flags := city.flags.data
	var mask := TileFlags.POWERED | TileFlags.WATERED
	var bits := PackedByteArray()
	bits.resize(_served_tiles.size())
	for k in _served_tiles.size(): bits[k] = flags[_served_tiles[k]] & mask
	return bits

func _discover(city: City) -> void:
	_event_hosts = {"stadium":false,"city_hall":false}
	_attractions.clear()
	_shops.clear()
	_served_tiles.clear()
	var fire_set := {}
	for at: Vector2i in _fires: fire_set[at] = true
	for site in _complete_sites(city):
		var at: Vector2i = site.at
		var rect: Rect2i = site.rect
		var key: StringName = site.key
		var category: StringName = site.category
		# Every served bit _operating may read for this complete footprint.
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): _served_tiles.append(y*City.WIDTH+x)
		if String(key) in _event_hosts and _operating(city,rect,key,fire_set): _event_hosts[String(key)] = true
		if category != &"":
			if _operating(city,rect,key,fire_set): _bin_add(_attractions,at,{"rect":rect,"category":category})
		elif site.retail:
			if _operating(city,rect,&"shop",fire_set): _bin_add(_shops,at,{"rect":rect,"anchor":at})
	_served_bits = _served(city)

## Native searches find only relevant codes and vacant commercial zone bytes;
## sorting restores the original row-major discovery and allocation order.
func _complete_sites(city: City) -> Array[Dictionary]:
	var inputs: Array = [_buildings,_zones]
	if inputs == _site_inputs: return _sites
	_site_inputs = inputs.duplicate(true)
	_sites.clear()
	var candidates := PackedInt32Array()
	var interest := _interest_table()
	for code in interest.size():
		if code == Buildings.NONE or interest[code] == 0: continue
		var index := _buildings.find(code)
		while index >= 0:
			candidates.append(index)
			index = _buildings.find(code,index+1)
	for kind: int in [Zones.COM_LOW,Zones.COM_HIGH]:
		for corner in 16:
			var raw := (corner<<4)|kind
			var index := _zones.find(raw)
			while index >= 0:
				if _buildings[index] == Buildings.NONE: candidates.append(index)
				index = _zones.find(raw,index+1)
	candidates.sort()
	for index in candidates:
		var code := _buildings[index]
		if not UtilityParams.is_anchor_tile(_buildings,_zones,index): continue
		@warning_ignore("integer_division")
		var at := Vector2i(index % City.WIDTH,index / City.WIDTH)
		var rect := Rect2i(at,Buildings.size(code))
		if not _complete(city,rect,code): continue
		var key := Buildings.key(code)
		_sites.append({"at":at,"rect":rect,"key":key,"category":CATEGORIES.get(key,&""),
			"retail":code == Buildings.NONE or (Buildings.category(code) == Buildings.Category.COMMERCIAL and not RewardParams.ARCOLOGIES.has(key))})
	return _sites

func _complete(city: City, rect: Rect2i, code: int) -> bool:
	if not city.in_bounds(rect.end.x-1,rect.end.y-1): return false
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if city.building_at(x,y) != code: return false
	return true

func _operating(city: City, rect: Rect2i, key: StringName, fires: Dictionary) -> bool:
	if not ZoneSystem.has_access(city,rect): return false
	var outdoors := key in [&"small_park",&"large_park",&"monument"]
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if fires.has(Vector2i(x,y)): return false
			if key != &"marina" and city.is_water(x,y): return false
			if not outdoors and not city.is_powered(x,y): return false
			if not outdoors and key != &"shop" and not city.is_watered(x,y): return false
	if key == &"marina":
		for y in range(maxi(0,rect.position.y-1),mini(City.HEIGHT,rect.end.y+1)):
			for x in range(maxi(0,rect.position.x-1),mini(City.WIDTH,rect.end.x+1)):
				if not rect.has_point(Vector2i(x,y)) and Terrain.is_open_water(city.terrain.at(x,y)): return true
		return false
	return true

func _rebuild(city: City, rows: Array[Dictionary]) -> void:
	_inputs.clear()
	_distribution.clear()
	_summary = {"available_spending_cents":0,"accepted_spending_cents":0, "recipient_capacity_cents":0,
		"allocated_spending_cents":0,"unallocated_spending_cents":0,"commercial_demand_bonus":0}
	var venues := {}
	var ordered: Array[Dictionary] = rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary): return _index(a.anchor)<_index(b.anchor))
	for row in ordered:
		if row.operating and RewardParams.ARCOLOGIES.has(StringName(row.key)):
			_bin_add(venues,row.anchor,row)
	var accepted := {}
	var cap := TourismParams.COMMERCIAL_GROWTH_CAP * TourismParams.COMMERCIAL_CENTS_PER_POINT
	for row in ordered:
		var source := Rect2i(row.anchor,Buildings.size(int(row.code)))
		var info := venue_inputs(row.anchor)
		var counts := {}
		if row.operating:
			for attraction: Dictionary in _near(_attractions,source,TourismParams.DISTRICT_REACH):
				if district_connected(city,source,attraction.rect,TourismParams.DISTRICT_REACH):
					counts[attraction.category] = int(counts.get(attraction.category,0)) + 1
		var appeal := 0
		for category: StringName in counts:
			var count := int(counts[category])
			appeal += mini(TourismParams.DISTRICT_CATEGORY_CAP,TourismParams.DISTRICT_CATEGORY_FIRST \
				+ (TourismParams.DISTRICT_CATEGORY_SECOND if count>1 else 0) \
				+ maxi(0,count-2)*TourismParams.DISTRICT_CATEGORY_LATER)
		var identities := {}
		if row.operating:
			for other: Dictionary in _near(venues,source,TourismParams.DISTRICT_REACH):
				if other.key != row.key and district_connected(city,source,Rect2i(other.anchor,Buildings.size(int(other.code))),TourismParams.DISTRICT_REACH):
					identities[other.key] = true
		info.district_categories = counts
		info.attraction_appeal_bonus = mini(TourismParams.DISTRICT_APPEAL_CAP,appeal)
		info.resort_variety_bonus = mini(TourismParams.RESORT_VARIETY_CAP,identities.size())
		info.district_appeal_bonus = info.attraction_appeal_bonus + info.resort_variety_bonus
		var spending := TourismEffects.commercial_spending_cents(row)
		info.commercial_spending_cents = spending
		info.commercial_allocated_cents = 0
		_summary.available_spending_cents += spending
		var candidates: Array[Dictionary] = []
		if spending>0:
			for shop: Dictionary in _near(_shops,source,TourismParams.COMMERCIAL_REACH):
				if district_connected(city,source,shop.rect,TourismParams.COMMERCIAL_REACH):
					candidates.append(shop)
		candidates.sort_custom(func(a: Dictionary,b: Dictionary): return _index(a.anchor)<_index(b.anchor))
		var desired := PackedInt64Array()
		for shop in candidates:
			accepted[shop.anchor] = cap
			desired.append(cap-int(_distribution.get(shop.anchor,0)))
		var allocated := TourismDemand.allocate(desired,spending)
		for i in candidates.size():
			var at: Vector2i = candidates[i].anchor
			_distribution[at] = int(_distribution.get(at,0))+allocated[i]
			info.commercial_allocated_cents += allocated[i]
		_summary.allocated_spending_cents += int(info.commercial_allocated_cents)
		_inputs[row.anchor] = info
	_summary.recipient_capacity_cents = accepted.size()*cap
	_summary.accepted_spending_cents = _summary.allocated_spending_cents
	_summary.unallocated_spending_cents = _summary.available_spending_cents-_summary.allocated_spending_cents
	_summary.commercial_demand_bonus = mini(TourismParams.COMMERCIAL_DEMAND_CAP,
		int(_summary.available_spending_cents)/TourismParams.COMMERCIAL_CENTS_PER_POINT)

func _bin_add(bins: Dictionary, at: Vector2i, value: Dictionary) -> void:
	var cell := Vector2i(at.x/BIN,at.y/BIN)
	if not bins.has(cell): bins[cell] = []
	bins[cell].append(value)

func _near(bins: Dictionary, rect: Rect2i, reach: int) -> Array:
	var result: Array = []
	# Attraction footprints are at most four tiles wide; anchors can lie just
	# outside the reach even when their frontage is inside it.
	var area := rect.grow(reach+4).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	for y in range(area.position.y/BIN,(area.end.y-1)/BIN+1):
		for x in range(area.position.x/BIN,(area.end.x-1)/BIN+1):
			result.append_array(bins.get(Vector2i(x,y),[]))
	return result

static func _distance(a: Rect2i,b: Rect2i) -> int:
	return maxi(maxi(0,maxi(a.position.x-b.end.x+1,b.position.x-a.end.x+1)),
		maxi(0,maxi(a.position.y-b.end.y+1,b.position.y-a.end.y+1)))

static func _index(at: Vector2i) -> int:
	return at.y*City.WIDTH+at.x

## Serviced complete hosts discovered by the same cached canonical scan.
func event_hosts() -> Dictionary:
	return _event_hosts.duplicate()
