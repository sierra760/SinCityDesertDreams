# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The player's construction tools.
##
## One entry per toolbar button: what it places, what it costs, how the pointer
## drives it and when it becomes available. `Builder` reads this table; the
## toolbar reads it for names, icons and lock reasons.
class_name Tools
extends RefCounted

enum Kind {
	QUERY, BULLDOZE, DEZONE, SIGN,
	ROAD, HIGHWAY, ONRAMP, TUNNEL, RAIL, SUBWAY, SUBWAY_PORTAL, POWER_LINE, WATER_PIPE,
	ZONE_RES_LOW, ZONE_RES_HIGH, ZONE_COM_LOW, ZONE_COM_HIGH, ZONE_IND_LOW, ZONE_IND_HIGH,
	AIRPORT, SEAPORT,
	TREES, SMALL_PARK, LARGE_PARK,
	WATER_PUMP, WATER_TOWER, WATER_TREATMENT, DESALINATION,
	POLICE, FIRE, HOSPITAL, SCHOOL, COLLEGE, LIBRARY, MUSEUM, STADIUM, MARINA, ZOO, PRISON,
	BUS_DEPOT, RAIL_STATION, SUBWAY_STATION,
	COAL_PLANT, HYDRO_PLANT, WIND_PLANT, GAS_PLANT, OIL_PLANT, NUCLEAR_PLANT,
	SOLAR_PLANT, MICROWAVE_PLANT, FUSION_PLANT,
	ARCOLOGY_COMSTOCK, ARCOLOGY_JUNCTION, ARCOLOGY_BOULDER, ARCOLOGY_ORBIT,
	REWARD_MAYORS_RESIDENCE, REWARD_CITY_HALL, REWARD_MONUMENT, REWARD_MILITARY_BASE, REWARD_NEON_DOME,
	DISPATCH_FIRE, DISPATCH_POLICE, DISPATCH_MILITARY,
	RAISE_LAND, LOWER_LAND, LEVEL_LAND, PLACE_WATER, FOREST, RAISE_SEA, LOWER_SEA,
	PLANT_TREE,
}

## How the pointer drives a tool. RECT tools cover the dragged area; GLOBAL
## tools act on the whole map as soon as their button is pressed.
enum Mode { POINT, LINE, RECT, BLOCK_LINE, GLOBAL }

## Toolbar grouping, for the UI.
enum Group { INSPECT, DEMOLISH, TRANSPORT, UTILITY, ZONE, NATURE, CIVIC, TRANSIT, PLANT, ARCOLOGY, REWARD, EMERGENCY, TERRAIN }

const NO_BUILDING := -1

## Lock reason for the nuclear plant while the Nuclear Free Zone ordinance
## is enacted. Plants already standing keep running.
const NUCLEAR_FREE_ZONE_REASON := "the Nuclear Free Zone ordinance forbids nuclear plants"

## Row layout: [name, cost, building id (or NO_BUILDING), zone kind (or -1),
## footprint, icon, mode, group]. Building prices come from the roster.
const _TABLE := {
	Kind.QUERY: ["Inspect", 0, NO_BUILDING, -1, Vector2i.ONE, &"query", Mode.POINT, Group.INSPECT],
	Kind.BULLDOZE: ["Bulldoze", 1, NO_BUILDING, -1, Vector2i.ONE, &"bulldoze", Mode.LINE, Group.DEMOLISH],
	Kind.DEZONE: ["Remove zone", 1, NO_BUILDING, Zones.NONE, Vector2i.ONE, &"dezone", Mode.RECT, Group.DEMOLISH],
	Kind.SIGN: ["Sign", 0, NO_BUILDING, -1, Vector2i.ONE, &"sign", Mode.POINT, Group.INSPECT],
	Kind.ROAD: ["Road", 10, NO_BUILDING, -1, Vector2i.ONE, &"road", Mode.LINE, Group.TRANSPORT],
	Kind.HIGHWAY: ["Highway", 100, NO_BUILDING, -1, Vector2i(2, 2), &"highway", Mode.BLOCK_LINE, Group.TRANSPORT],
	Kind.ONRAMP: ["Highway Ramp", 25, NO_BUILDING, -1, Vector2i.ONE, &"onramp", Mode.POINT, Group.TRANSPORT],
	Kind.TUNNEL: ["Tunnel", 150, NO_BUILDING, -1, Vector2i.ONE, &"tunnel", Mode.POINT, Group.TRANSPORT],
	Kind.RAIL: ["Rail", 25, NO_BUILDING, -1, Vector2i.ONE, &"rail", Mode.LINE, Group.TRANSPORT],
	Kind.SUBWAY: ["Subway", 100, NO_BUILDING, -1, Vector2i.ONE, &"subway", Mode.LINE, Group.TRANSPORT],
	Kind.SUBWAY_PORTAL: ["Subway Portal", 500, NO_BUILDING, -1, Vector2i.ONE, &"subway_portal", Mode.POINT, Group.TRANSPORT],
	Kind.POWER_LINE: ["Power Line", 2, NO_BUILDING, -1, Vector2i.ONE, &"power_line", Mode.LINE, Group.UTILITY],
	Kind.WATER_PIPE: ["Water Pipe", 3, NO_BUILDING, -1, Vector2i.ONE, &"water_pipe", Mode.LINE, Group.UTILITY],
	Kind.ZONE_RES_LOW: ["Light Residential", 5, NO_BUILDING, Zones.RES_LOW, Vector2i.ONE, &"zone_res_low", Mode.RECT, Group.ZONE],
	Kind.ZONE_RES_HIGH: ["Dense Residential", 10, NO_BUILDING, Zones.RES_HIGH, Vector2i.ONE, &"zone_res_high", Mode.RECT, Group.ZONE],
	Kind.ZONE_COM_LOW: ["Light Commercial", 5, NO_BUILDING, Zones.COM_LOW, Vector2i.ONE, &"zone_com_low", Mode.RECT, Group.ZONE],
	Kind.ZONE_COM_HIGH: ["Dense Commercial", 10, NO_BUILDING, Zones.COM_HIGH, Vector2i.ONE, &"zone_com_high", Mode.RECT, Group.ZONE],
	Kind.ZONE_IND_LOW: ["Light Industrial", 5, NO_BUILDING, Zones.IND_LOW, Vector2i.ONE, &"zone_ind_low", Mode.RECT, Group.ZONE],
	Kind.ZONE_IND_HIGH: ["Dense Industrial", 10, NO_BUILDING, Zones.IND_HIGH, Vector2i.ONE, &"zone_ind_high", Mode.RECT, Group.ZONE],
	Kind.AIRPORT: ["Airport", 250, NO_BUILDING, Zones.AIRPORT, Vector2i.ONE, &"airport", Mode.RECT, Group.TRANSIT],
	Kind.SEAPORT: ["Seaport", 150, NO_BUILDING, Zones.SEAPORT, Vector2i.ONE, &"seaport", Mode.RECT, Group.TRANSIT],
	Kind.TREES: ["Trees", 3, Buildings.TREES_1, -1, Vector2i.ONE, &"trees", Mode.LINE, Group.NATURE],
	Kind.SMALL_PARK: ["Pocket Park", 10, Buildings.SMALL_PARK, -1, Vector2i.ONE, &"small_park", Mode.POINT, Group.NATURE],
	Kind.LARGE_PARK: ["City Park", 150, Buildings.LARGE_PARK, -1, Vector2i(3, 3), &"large_park", Mode.POINT, Group.NATURE],
	Kind.WATER_PUMP: ["Water Pump", 100, Buildings.WATER_PUMP, -1, Vector2i.ONE, &"water_pump", Mode.POINT, Group.UTILITY],
	Kind.WATER_TOWER: ["Water Tower", 250, Buildings.WATER_TOWER, -1, Vector2i(2, 2), &"water_tower", Mode.POINT, Group.UTILITY],
	Kind.WATER_TREATMENT: ["Water Treatment Plant", 500, Buildings.WATER_TREATMENT, -1, Vector2i(2, 2), &"water_treatment", Mode.POINT, Group.UTILITY],
	Kind.DESALINATION: ["Desalination Plant", 1000, Buildings.DESALINATION, -1, Vector2i(3, 3), &"desalination", Mode.POINT, Group.UTILITY],
	Kind.POLICE: ["Police Station", 500, Buildings.POLICE_STATION, -1, Vector2i(3, 3), &"police", Mode.POINT, Group.CIVIC],
	Kind.FIRE: ["Fire Station", 500, Buildings.FIRE_STATION, -1, Vector2i(3, 3), &"fire", Mode.POINT, Group.CIVIC],
	Kind.HOSPITAL: ["Hospital", 500, Buildings.HOSPITAL, -1, Vector2i(3, 3), &"hospital", Mode.POINT, Group.CIVIC],
	Kind.SCHOOL: ["School", 250, Buildings.SCHOOL, -1, Vector2i(3, 3), &"school", Mode.POINT, Group.CIVIC],
	Kind.COLLEGE: ["College", 1000, Buildings.COLLEGE, -1, Vector2i(4, 4), &"college", Mode.POINT, Group.CIVIC],
	Kind.LIBRARY: ["Library", 500, Buildings.LIBRARY, -1, Vector2i(2, 2), &"library", Mode.POINT, Group.CIVIC],
	Kind.MUSEUM: ["Museum", 100, Buildings.MUSEUM, -1, Vector2i(3, 3), &"museum", Mode.POINT, Group.CIVIC],
	Kind.STADIUM: ["Stadium", 3000, Buildings.STADIUM, -1, Vector2i(4, 4), &"stadium", Mode.POINT, Group.CIVIC],
	Kind.MARINA: ["Marina", 1000, Buildings.MARINA, -1, Vector2i(3, 3), &"marina", Mode.POINT, Group.CIVIC],
	Kind.ZOO: ["Zoo", 3000, Buildings.ZOO, -1, Vector2i(4, 4), &"zoo", Mode.POINT, Group.CIVIC],
	Kind.PRISON: ["Prison", 3000, Buildings.PRISON, -1, Vector2i(4, 4), &"prison", Mode.POINT, Group.CIVIC],
	Kind.BUS_DEPOT: ["Bus Depot", 250, Buildings.BUS_DEPOT, -1, Vector2i(2, 2), &"bus_depot", Mode.POINT, Group.TRANSIT],
	Kind.RAIL_STATION: ["Rail Station", 500, Buildings.RAIL_STATION, -1, Vector2i(2, 2), &"rail_station", Mode.POINT, Group.TRANSIT],
	Kind.SUBWAY_STATION: ["Subway Station", 250, Buildings.SUBWAY_STATION, -1, Vector2i.ONE, &"subway_station", Mode.POINT, Group.TRANSIT],
	Kind.COAL_PLANT: ["Coal Power Plant", 4000, Buildings.COAL_PLANT, -1, Vector2i(4, 4), &"coal_plant", Mode.POINT, Group.PLANT],
	Kind.HYDRO_PLANT: ["Hydroelectric Dam", 400, Buildings.HYDRO_PLANT_A, -1, Vector2i.ONE, &"hydro_plant", Mode.POINT, Group.PLANT],
	Kind.WIND_PLANT: ["Wind Turbine", 100, Buildings.WIND_PLANT, -1, Vector2i.ONE, &"wind_plant", Mode.POINT, Group.PLANT],
	Kind.GAS_PLANT: ["Gas Power Plant", 2000, Buildings.GAS_PLANT, -1, Vector2i(4, 4), &"gas_plant", Mode.POINT, Group.PLANT],
	Kind.OIL_PLANT: ["Oil Power Plant", 6600, Buildings.OIL_PLANT, -1, Vector2i(4, 4), &"oil_plant", Mode.POINT, Group.PLANT],
	Kind.NUCLEAR_PLANT: ["Nuclear Power Plant", 15000, Buildings.NUCLEAR_PLANT, -1, Vector2i(4, 4), &"nuclear_plant", Mode.POINT, Group.PLANT],
	Kind.SOLAR_PLANT: ["Solar Farm", 1300, Buildings.SOLAR_PLANT, -1, Vector2i(4, 4), &"solar_plant", Mode.POINT, Group.PLANT],
	Kind.MICROWAVE_PLANT: ["Microwave Receiver", 28000, Buildings.MICROWAVE_PLANT, -1, Vector2i(4, 4), &"microwave_plant", Mode.POINT, Group.PLANT],
	Kind.FUSION_PLANT: ["Fusion Power Plant", 40000, Buildings.FUSION_PLANT, -1, Vector2i(4, 4), &"fusion_plant", Mode.POINT, Group.PLANT],
	Kind.ARCOLOGY_COMSTOCK: ["Comstock Grand", 100000, Buildings.ARCOLOGY_COMSTOCK, -1, Vector2i(4, 4), &"arcology_comstock", Mode.POINT, Group.ARCOLOGY],
	Kind.ARCOLOGY_JUNCTION: ["Silver Junction", 120000, Buildings.ARCOLOGY_JUNCTION, -1, Vector2i(4, 4), &"arcology_junction", Mode.POINT, Group.ARCOLOGY],
	Kind.ARCOLOGY_BOULDER: ["Boulder Crown", 150000, Buildings.ARCOLOGY_BOULDER, -1, Vector2i(4, 4), &"arcology_boulder", Mode.POINT, Group.ARCOLOGY],
	Kind.ARCOLOGY_ORBIT: ["Desert Orbit", 200000, Buildings.ARCOLOGY_ORBIT, -1, Vector2i(4, 4), &"arcology_orbit", Mode.POINT, Group.ARCOLOGY],
	Kind.REWARD_MAYORS_RESIDENCE: ["Mayor's Residence", 0, Buildings.MAYORS_RESIDENCE, -1, Vector2i(2, 2), &"reward_mayors_residence", Mode.POINT, Group.REWARD],
	Kind.REWARD_CITY_HALL: ["City Hall", 0, Buildings.CITY_HALL, -1, Vector2i(3, 3), &"reward_city_hall", Mode.POINT, Group.REWARD],
	Kind.REWARD_MONUMENT: ["Monument", 0, Buildings.MONUMENT, -1, Vector2i.ONE, &"reward_monument", Mode.POINT, Group.REWARD],
	Kind.REWARD_MILITARY_BASE: ["Military Base", 0, NO_BUILDING, Zones.MILITARY, Vector2i.ONE, &"reward_military_base", Mode.RECT, Group.REWARD],
	Kind.REWARD_NEON_DOME: ["Neon Dome", 0, Buildings.NEON_DOME, -1, Vector2i(4, 4), &"reward_neon_dome", Mode.POINT, Group.REWARD],
	Kind.DISPATCH_FIRE: ["Dispatch Firefighters", 0, NO_BUILDING, -1, Vector2i.ONE, &"dispatch_fire", Mode.POINT, Group.EMERGENCY],
	Kind.DISPATCH_POLICE: ["Dispatch Police", 0, NO_BUILDING, -1, Vector2i.ONE, &"dispatch_police", Mode.POINT, Group.EMERGENCY],
	Kind.DISPATCH_MILITARY: ["Dispatch Military", 0, NO_BUILDING, -1, Vector2i.ONE, &"dispatch_military", Mode.POINT, Group.EMERGENCY],
	Kind.RAISE_LAND: ["Raise Land", 25, NO_BUILDING, -1, Vector2i.ONE, &"raise_land", Mode.POINT, Group.TERRAIN],
	Kind.LOWER_LAND: ["Lower Land", 25, NO_BUILDING, -1, Vector2i.ONE, &"lower_land", Mode.POINT, Group.TERRAIN],
	Kind.LEVEL_LAND: ["Level Land", 25, NO_BUILDING, -1, Vector2i.ONE, &"level_land", Mode.RECT, Group.TERRAIN],
	Kind.PLACE_WATER: ["Water", 100, NO_BUILDING, -1, Vector2i.ONE, &"place_water", Mode.POINT, Group.TERRAIN],
	Kind.PLANT_TREE: ["Tree", 3, Buildings.TREES_1, -1, Vector2i.ONE, &"plant_tree", Mode.POINT, Group.TERRAIN],
	Kind.FOREST: ["Forest", 3, Buildings.TREES_1, -1, Vector2i.ONE, &"forest", Mode.RECT, Group.TERRAIN],
	Kind.RAISE_SEA: ["Raise Sea Level", 25, NO_BUILDING, -1, Vector2i.ONE, &"raise_sea", Mode.GLOBAL, Group.TERRAIN],
	Kind.LOWER_SEA: ["Lower Sea Level", 25, NO_BUILDING, -1, Vector2i.ONE, &"lower_sea", Mode.GLOBAL, Group.TERRAIN],
}

## Technology each tool waits for. The key is the economy's invention key:
## the tool unlocks in the year the city rolled for it in `stats.inventions`,
## or at the technology's base year in `EconomyParams.TECHNOLOGIES` when the
## city has no rolled year. Tools not listed are available from the start.
const _INVENTIONS := {
	Kind.SUBWAY: &"subway",
	Kind.SUBWAY_STATION: &"subway",
	Kind.SUBWAY_PORTAL: &"subway",
	Kind.BUS_DEPOT: &"bus",
	Kind.HIGHWAY: &"highways",
	Kind.ONRAMP: &"highways",
	Kind.WATER_TREATMENT: &"water_treatment",
	Kind.GAS_PLANT: &"gas_plant",
	Kind.NUCLEAR_PLANT: &"nuclear_plant",
	Kind.DESALINATION: &"desalination",
	Kind.WIND_PLANT: &"wind_plant",
	Kind.SOLAR_PLANT: &"solar_plant",
	Kind.ARCOLOGY_COMSTOCK: &"arcology_comstock",
	Kind.MICROWAVE_PLANT: &"microwave_plant",
	Kind.FUSION_PLANT: &"fusion_plant",
	Kind.ARCOLOGY_JUNCTION: &"arcology_junction",
	Kind.ARCOLOGY_BOULDER: &"arcology_boulder",
	Kind.ARCOLOGY_ORBIT: &"arcology_orbit",
}

## Reward tools and the key the reward system offers them under.
const _REWARDS := {
	Kind.REWARD_MAYORS_RESIDENCE: &"mayors_residence",
	Kind.REWARD_CITY_HALL: &"city_hall",
	Kind.REWARD_MONUMENT: &"monument",
	Kind.REWARD_MILITARY_BASE: &"military_base",
	Kind.REWARD_NEON_DOME: &"neon_dome",
}

const _DISPATCH_KINDS := {
	Kind.DISPATCH_FIRE: &"fire",
	Kind.DISPATCH_POLICE: &"police",
	Kind.DISPATCH_MILITARY: &"military",
}


static func _row(tool: int) -> Array:
	var row: Array = _TABLE.get(tool, [])
	return row


static func all() -> Array[int]:
	var out: Array[int] = []
	for k in _TABLE:
		out.append(k)
	out.sort()
	return out


static func display_name(tool: int) -> String:
	var row := _row(tool)
	return String(row[0]) if not row.is_empty() else "Unknown"


## Price per tile, block or building.
static func cost(tool: int) -> int:
	var row := _row(tool)
	return int(row[1]) if not row.is_empty() else 0


## Roster id placed by the tool, or NO_BUILDING for networks, zones and
## terrain tools.
static func building_id(tool: int) -> int:
	var row := _row(tool)
	return int(row[2]) if not row.is_empty() else NO_BUILDING


## Zone kind written by rectangle zoning tools, -1 otherwise.
static func zone_kind(tool: int) -> int:
	var row := _row(tool)
	return int(row[3]) if not row.is_empty() else -1


static func footprint(tool: int) -> Vector2i:
	var row := _row(tool)
	if row.is_empty():
		return Vector2i.ONE
	var size: Vector2i = row[4]
	return size


## Icon key matching a SVG file name in assets/ui/tool-icons.
static func icon(tool: int) -> StringName:
	var row := _row(tool)
	return StringName(row[5]) if not row.is_empty() else &"query"


static func mode(tool: int) -> int:
	var row := _row(tool)
	return int(row[6]) if not row.is_empty() else Mode.POINT


static func group(tool: int) -> int:
	var row := _row(tool)
	return int(row[7]) if not row.is_empty() else Group.INSPECT


static func is_zone_tool(tool: int) -> bool:
	return zone_kind(tool) > Zones.NONE


static func is_building_tool(tool: int) -> bool:
	return building_id(tool) > Buildings.NONE and not is_tree_tool(tool)


static func is_tree_tool(tool: int) -> bool:
	return tool == Kind.TREES or tool == Kind.FOREST or tool == Kind.PLANT_TREE


static func is_terrain_tool(tool: int) -> bool:
	return group(tool) == Group.TERRAIN


## Whole-map tools that act once per button press instead of on a map click.
static func is_immediate(tool: int) -> bool:
	return mode(tool) == Mode.GLOBAL


## Tools only available while the land is shaped, before the city is founded.
static func is_editing_only(tool: int) -> bool:
	return tool == Kind.RAISE_SEA or tool == Kind.LOWER_SEA


static func is_reward_tool(tool: int) -> bool:
	return _REWARDS.has(tool)


static func is_dispatch_tool(tool: int) -> bool:
	return _DISPATCH_KINDS.has(tool)


## Reward key a reward tool is offered under, or empty.
static func reward_key(tool: int) -> StringName:
	var key: StringName = _REWARDS.get(tool, &"")
	return key


## Emergency service a dispatch tool sends, or empty.
static func dispatch_kind(tool: int) -> StringName:
	var kind: StringName = _DISPATCH_KINDS.get(tool, &"")
	return kind


## Technology key gating the tool, or empty when it is always available.
static func invention_key(tool: int) -> StringName:
	return _INVENTIONS.get(tool, &"")


## First year the tool is available, honouring `stats.inventions` when the
## technology has a recorded year. 0 when it is always available.
static func available_year(tool: int, stats: CityStats) -> int:
	var tech := invention_key(tool)
	if tech == &"":
		return 0
	if stats != null and stats.inventions.has(tech):
		return int(stats.inventions[tech])
	return int(EconomyParams.TECHNOLOGIES.get(tech, 0))


## Why the tool cannot be used right now, or an empty string when it can.
## Covers rewards, inventions and the Nuclear Free Zone ordinance.
static func locked_reason(tool: int, city: City, stats: CityStats) -> String:
	if not _TABLE.has(tool):
		return "unknown tool"
	if _REWARDS.has(tool):
		var key: StringName = _REWARDS[tool]
		if stats == null or not bool(stats.rewards_offered.get(key, false)):
			return "not yet offered to the city"
		if bool(stats.rewards_built.get(key, false)):
			return "already built"
		return ""
	var year := available_year(tool, stats)
	if year > 0 and city != null and city.current_year() < year:
		return "not available until %d" % year
	if tool == Kind.NUCLEAR_PLANT and stats != null \
			and bool(stats.ordinances.get(&"nuclear_free_zone", false)):
		return NUCLEAR_FREE_ZONE_REASON
	return ""


static func is_available(tool: int, city: City, stats: CityStats) -> bool:
	return locked_reason(tool, city, stats).is_empty()
