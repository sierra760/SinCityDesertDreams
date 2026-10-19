# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

## One current map scan. These are temporary observations, never a census
## publication or a call to a system's potentially rebuilding report getter.
var counts := PackedInt32Array()
var tiles := PackedInt32Array()
var wear := PackedInt32Array()
var powered := PackedInt32Array()
var stations: Dictionary = {Buildings.POLICE_STATION: [], Buildings.FIRE_STATION: []}
var occupied: Array[Vector2i] = []
var units := Vector3i.ZERO
var agriculture := 0
var airport_tiles := 0
var seaport_tiles := 0

func _init(city: City) -> void:
	counts.resize(Buildings.COUNT)
	tiles.resize(Buildings.COUNT)
	wear.resize(TransportParams.CATEGORY_KEYS.size())
	powered.resize(Buildings.COUNT)
	var bld := city.building.data
	var zones := city.zone.data
	var flags := city.flags.data
	var underground := city.underground.data
	var owners := city.agricultural_parcels.owners()
	var seen_parcels := {}
	var multi := UtilityParams.multi_tile_table()
	var wear_table := PackedInt32Array()
	wear_table.resize(Buildings.COUNT)
	for id in Buildings.COUNT: wear_table[id] = TransportParams.wear_category(id)
	for i: int in bld.size():
		var zone := Zones.kind(zones[i])
		if zone == Zones.AIRPORT: airport_tiles += 1
		elif zone == Zones.SEAPORT: seaport_tiles += 1
		var id := bld[i]
		tiles[id] += 1
		var wear_category := wear_table[id]
		if wear_category != TransportParams.NO_CATEGORY: wear[wear_category] += 1
		if UtilityParams.is_subway(underground[i]): wear[TransportParams.SUBWAY] += 1
		if id == Buildings.NONE or (multi[id] and not (zones[i] & Zones.CORNER_NW)):
			continue
		var at := Vector2i(i % City.WIDTH, i / City.WIDTH)
		if multi[id]: at = City.footprint_anchor(bld, zones, at.x, at.y)
		counts[id] += 1
		# Civic education/health uses the anchor's power, exactly as Population.
		if flags[at.y * City.WIDTH + at.x] & TileFlags.POWERED: powered[id] += 1
		if stations.has(id):
			stations[id].append({"anchor": at, "powered": ServicesSystem._footprint_powered(flags, at.x, at.y, Buildings.size(id))})
		var category := Buildings.category(id)
		if Buildings.is_agricultural(id):
			var owner := owners[i]
			if owner == 0 or not seen_parcels.has(owner):
				seen_parcels[owner] = true
				agriculture += 1
				occupied.append(at)
		elif category in [Buildings.Category.RESIDENTIAL, Buildings.Category.COMMERCIAL, Buildings.Category.INDUSTRIAL]:
			occupied.append(at)
			var amount := ZoneParams.STAGE_UNITS[ZoneParams.stage_of(id)]
			if category == Buildings.Category.RESIDENTIAL: units.x += amount
			elif category == Buildings.Category.COMMERCIAL: units.y += amount
			else: units.z += amount
		elif category == Buildings.Category.ARCOLOGY:
			occupied.append(at)

func count_keys(keys: Array[StringName]) -> int:
	var total := 0
	for key in keys: total += counts[Buildings.id_of(key)]
	return total
