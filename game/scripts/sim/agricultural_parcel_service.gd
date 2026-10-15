# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name AgriculturalParcelService
extends RefCounted
## Exact-member adapters; bounds never substitute for ownership.

static func land_reason(city: City, record: Dictionary) -> String:
	for i in record.members:
		var p := AgriculturalParcels.tile(i)
		if p.x < 2 or p.y < 2 or p.x >= 126 or p.y >= 126: return "Too close to the city boundary."
		if city.zone_kind_at(p.x,p.y) != Zones.AGR_LOW: return "Requires the same agricultural density."
		if not city.is_flat(p.x,p.y) or city.ground_height(p.x,p.y) != record.height: return "Requires flat, level ground."
		if city.is_water(p.x,p.y) or city.flood_overlay.has(p): return "Requires dry ground."
		if city.flags.has_bits(p.x,p.y,TileFlags.LANDMARK): return "Protected land."
		var id := city.building_at(p.x,p.y)
		if id == Buildings.id_of(&"contamination"): return "Contaminated ground."
		if id != Buildings.NONE and city.agricultural_parcels.id_at(p) != record.id: return "Occupied land."
	return ""

static func has_access(city: City, members: PackedInt32Array) -> bool:
	for i in members:
		if ZoneSystem.has_access(city,Rect2i(AgriculturalParcels.tile(i),Vector2i.ONE)): return true
	return false

static func all_members_served(city: City, members: PackedInt32Array, flag: int) -> bool:
	for i in members:
		var p := AgriculturalParcels.tile(i)
		if not city.flags.has_bits(p.x,p.y,flag): return false
	return true

static func summary(ctx: SimContext, record: Dictionary, supplied_city: City) -> Dictionary:
	var id := AgricultureParams.building_id(record.archetype)
	var water := AgricultureParams.water_load(id)
	var power := AgricultureParams.power_load(id)
	var reason := land_reason(ctx.city,record)
	var disasters := ctx.system(&"disasters")
	if reason.is_empty() and disasters != null:
		var fires: Array = disasters.call("fires") if disasters.has_method("fires") else []
		for i in record.members:
			if AgriculturalParcels.tile(i) in fires: reason = "Active fire.";break
		if reason.is_empty() and record.state != &"active" and disasters.has_method("is_emergency") and disasters.call("is_emergency"):
			reason = "Development waits until the emergency ends."
	if reason.is_empty() and not has_access(ctx.city,record.members): reason = "Needs road or station access within three tiles."
	var watered := water == 0 or (supplied_city != null and all_members_served(supplied_city,record.members,TileFlags.WATERED))
	var powered := power == 0 or (ctx.system(&"power") != null and supplied_city != null and all_members_served(supplied_city,record.members,TileFlags.POWERED))
	if reason.is_empty() and not watered: reason = "Needs water for the whole footprint."
	if reason.is_empty() and not powered: reason = "Needs power for the whole footprint."
	return {"water_required":water*record.members.size(),"water_supplied":watered,
		"power_required":power*record.members.size(),"power_supplied":powered,"blocked_reason":reason}

## Detached store, source policy, facilities, statistics and network instances.
## A list also permits final joint allocation and rollback without live mutations.
static func project(ctx: SimContext, record: Dictionary = {}, proposals: Array[Dictionary] = []) -> City:
	var city := ctx.city.duplicate_city()
	city.imported_power_links = ctx.city.imported_power_links.duplicate()
	var values := proposals.duplicate()
	if not record.is_empty(): values.append(record)
	for value in values:
		if value.has("members"):
			if city.agricultural_parcels.put(city,value) != OK: return null
		else:
			city.stamp_building(value.anchor.x,value.anchor.y,AgricultureParams.building_id(value.archetype),value.zone_kind)
	var detached := SimContext.new()
	detached.city = city
	detached.stats = CityStats.new()
	detached.events = CityEvents.new()
	var full := Rect2i(0,0,City.WIDTH,City.HEIGHT)
	var power := ctx.system(&"power") as PowerSystem
	var water := ctx.system(&"water") as WaterSystem
	if power != null:
		var system := PowerSystem.new()
		system.copy_supply_policy(power)
		system.reallocate_established(detached,full)
	if water != null:
		var system := WaterSystem.new()
		system.reallocate_established(detached,full)
	else:
		for i in city.flags.data.size(): city.flags.data[i] &= ~TileFlags.WATERED
	return city


## Necessary source capability only. Never reject using stale supply or power
## flags: candidate conduction may power a pump, and any tower keeps the full
## storage/refill allocation path. Established previews never generate output.
static func has_established_water_source(ctx: SimContext) -> bool:
	if (ctx.system(&"water") as WaterSystem) == null: return false
	var city := ctx.city
	if city.building.data.has(Buildings.WATER_TOWER): return true
	for anchor: Vector2i in city.facilities:
		if not city.in_bounds(anchor.x,anchor.y): continue
		var id := city.building_at(anchor.x,anchor.y)
		if id not in [Buildings.WATER_PUMP,Buildings.DESALINATION]: continue
		if not UtilityParams.is_anchor_tile(city.building.data,city.zone.data,AgriculturalParcels.cell(anchor)): continue
		var facility: Dictionary = city.facilities[anchor]
		if facility.get("key",&"") == Buildings.key(id) and int(facility.get("output",0)) > 0: return true
	return false
