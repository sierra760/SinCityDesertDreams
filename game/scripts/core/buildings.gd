# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The building roster.
##
## Every building on the map is one of these ids. Saves, imported cities and the
## 3D model catalog all key on the id, so ids are stable: never renumber, only
## append. Simulation parameters (capacities, pollution, power
## draw) live in sim/data and are keyed by the `key` StringName, not the id.
class_name Buildings
extends RefCounted

enum Category { NONE, RUBBLE, TREE, POWER_LINE, ROAD, RAIL, HIGHWAY, BRIDGE, TUNNEL,
	RESIDENTIAL, COMMERCIAL, INDUSTRIAL, CONSTRUCTION, ABANDONED, PLANT, CIVIC,
	UTILITY, TRANSIT, PORT, MILITARY, REWARD, ARCOLOGY }

## Well-known ids used directly by systems.
const NONE := 0
const RUBBLE_1 := 1
const RUBBLE_4 := 4
const CONTAMINATION := 5
const TREES_1 := 6
const TREES_7 := 12
const SMALL_PARK := 13
const POWER_LINE_FIRST := 14
const POWER_LINE_LAST := 28
const ROAD_FIRST := 29
const ROAD_LAST := 43
const RAIL_FIRST := 44
const RAIL_LAST := 62
const TUNNEL_FIRST := 63
const TUNNEL_LAST := 66
const CROSSING_FIRST := 67
const CROSSING_LAST := 72
const HIGHWAY_FIRST := 73
const HIGHWAY_LAST := 80
const BRIDGE_FIRST := 81
const BRIDGE_LAST := 92
const ONRAMP_FIRST := 93
const ONRAMP_LAST := 96
const HIGHWAY_PIECE_FIRST := 97
const HIGHWAY_PIECE_LAST := 105
const REINFORCED_PYLON := 106
const REINFORCED_BRIDGE := 107
const SUBWAY_PORTAL_FIRST := 108
const SUBWAY_PORTAL_LAST := 111
const RES_1X1_FIRST := 112
const RES_1X1_LAST := 123
const COM_1X1_FIRST := 124
const COM_1X1_LAST := 131
const IND_1X1_FIRST := 132
const IND_1X1_LAST := 135
const CONSTRUCTION_1X1_A := 136
const CONSTRUCTION_1X1_B := 137
const ABANDONED_1X1_A := 138
const ABANDONED_1X1_B := 139
const RES_2X2_FIRST := 140
const RES_2X2_LAST := 147
const COM_2X2_FIRST := 148
const COM_2X2_LAST := 157
const IND_2X2_FIRST := 158
const IND_2X2_LAST := 165
const CONSTRUCTION_2X2_FIRST := 166
const CONSTRUCTION_2X2_LAST := 169
const ABANDONED_2X2_FIRST := 170
const ABANDONED_2X2_LAST := 173
const RES_3X3_FIRST := 174
const RES_3X3_LAST := 177
const COM_3X3_FIRST := 178
const COM_3X3_LAST := 187
const IND_3X3_FIRST := 188
const IND_3X3_LAST := 193
const CONSTRUCTION_3X3_A := 194
const CONSTRUCTION_3X3_B := 195
const ABANDONED_3X3_A := 196
const ABANDONED_3X3_B := 197
const HYDRO_PLANT_A := 198
const HYDRO_PLANT_B := 199
const WIND_PLANT := 200
const GAS_PLANT := 201
const OIL_PLANT := 202
const NUCLEAR_PLANT := 203
const SOLAR_PLANT := 204
const MICROWAVE_PLANT := 205
const FUSION_PLANT := 206
const COAL_PLANT := 207
const CITY_HALL := 208
const HOSPITAL := 209
const POLICE_STATION := 210
const FIRE_STATION := 211
const MUSEUM := 212
const LARGE_PARK := 213
const SCHOOL := 214
const STADIUM := 215
const PRISON := 216
const COLLEGE := 217
const ZOO := 218
const MONUMENT := 219
const WATER_PUMP := 220
const RUNWAY := 221
const RUNWAY_CROSS := 222
const PIER := 223
const CRANE := 224
const CONTROL_TOWER := 225
const MILITARY_TOWER := 226
const PORT_WAREHOUSE := 227
const PORT_BUILDING_A := 228
const PORT_BUILDING_B := 229
const TARMAC := 230
const FIGHTER_JET := 231
const HANGAR_SMALL := 232
const SUBWAY_STATION := 233
const RADAR := 234
const WATER_TOWER := 235
const BUS_DEPOT := 236
const RAIL_STATION := 237
const PARKING_CIVIL := 238
const PARKING_MILITARY := 239
const LOADING_BAY := 240
const RESTRICTED_FACILITY := 241
const CARGO_YARD := 242
const MAYORS_RESIDENCE := 243
const WATER_TREATMENT := 244
const LIBRARY := 245
const HANGAR_LARGE := 246
const CHAPEL := 247
const MARINA := 248
const MISSILE_SILO := 249
const DESALINATION := 250
const ARCOLOGY_COMSTOCK := 251
const ARCOLOGY_JUNCTION := 252
const ARCOLOGY_BOULDER := 253
const ARCOLOGY_ORBIT := 254
const NEON_DOME := 255
const COUNT := 256

## [key, name, width, height, category, cost]
const _ROSTER := [
	[&"nothing", "Open Ground", 1, 1, Category.NONE, 0],
	[&"rubble_1", "Rubble", 1, 1, Category.RUBBLE, 0],
	[&"rubble_2", "Rubble", 1, 1, Category.RUBBLE, 0],
	[&"rubble_3", "Rubble", 1, 1, Category.RUBBLE, 0],
	[&"rubble_4", "Rubble", 1, 1, Category.RUBBLE, 0],
	[&"contamination", "Contaminated Ground", 1, 1, Category.RUBBLE, 0],
	[&"trees_1", "Lone Palm", 1, 1, Category.TREE, 3],
	[&"trees_2", "Palm Pair", 1, 1, Category.TREE, 3],
	[&"trees_3", "Palm Cluster", 1, 1, Category.TREE, 3],
	[&"trees_4", "Palm Grove", 1, 1, Category.TREE, 3],
	[&"trees_5", "Dense Grove", 1, 1, Category.TREE, 3],
	[&"trees_6", "Oasis Thicket", 1, 1, Category.TREE, 3],
	[&"trees_7", "Riparian Woodland", 1, 1, Category.TREE, 3],
	[&"small_park", "Pocket Park", 1, 1, Category.TREE, 10],
	[&"power_ns", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_ew", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_slope_w", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_slope_n", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_slope_e", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_slope_s", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_ne", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_se", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_sw", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_nw", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_new", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_nes", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_esw", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_nsw", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"power_nesw", "Power Line", 1, 1, Category.POWER_LINE, 2],
	[&"road_ns", "Road", 1, 1, Category.ROAD, 10],
	[&"road_ew", "Road", 1, 1, Category.ROAD, 10],
	[&"road_slope_w", "Road", 1, 1, Category.ROAD, 10],
	[&"road_slope_n", "Road", 1, 1, Category.ROAD, 10],
	[&"road_slope_e", "Road", 1, 1, Category.ROAD, 10],
	[&"road_slope_s", "Road", 1, 1, Category.ROAD, 10],
	[&"road_ne", "Road", 1, 1, Category.ROAD, 10],
	[&"road_se", "Road", 1, 1, Category.ROAD, 10],
	[&"road_sw", "Road", 1, 1, Category.ROAD, 10],
	[&"road_nw", "Road", 1, 1, Category.ROAD, 10],
	[&"road_new", "Road", 1, 1, Category.ROAD, 10],
	[&"road_nes", "Road", 1, 1, Category.ROAD, 10],
	[&"road_esw", "Road", 1, 1, Category.ROAD, 10],
	[&"road_nsw", "Road", 1, 1, Category.ROAD, 10],
	[&"road_nesw", "Road", 1, 1, Category.ROAD, 10],
	[&"rail_ns", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_ew", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_slope_w", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_slope_n", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_slope_e", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_slope_s", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_ne", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_se", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_sw", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_nw", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_new", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_nes", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_esw", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_nsw", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_nesw", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_uphill_w", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_uphill_n", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_uphill_e", "Rail", 1, 1, Category.RAIL, 25],
	[&"rail_uphill_s", "Rail", 1, 1, Category.RAIL, 25],
	[&"tunnel_w", "Tunnel Entrance", 1, 1, Category.TUNNEL, 150],
	[&"tunnel_n", "Tunnel Entrance", 1, 1, Category.TUNNEL, 150],
	[&"tunnel_e", "Tunnel Entrance", 1, 1, Category.TUNNEL, 150],
	[&"tunnel_s", "Tunnel Entrance", 1, 1, Category.TUNNEL, 150],
	[&"cross_road_ns_power_ew", "Road under Power Line", 1, 1, Category.ROAD, 10],
	[&"cross_road_ew_power_ns", "Road under Power Line", 1, 1, Category.ROAD, 10],
	[&"cross_road_ns_rail_ew", "Level Crossing", 1, 1, Category.ROAD, 10],
	[&"cross_road_ew_rail_ns", "Level Crossing", 1, 1, Category.ROAD, 10],
	[&"cross_rail_ns_power_ew", "Rail under Power Line", 1, 1, Category.POWER_LINE, 25],
	[&"cross_rail_ew_power_ns", "Rail under Power Line", 1, 1, Category.POWER_LINE, 25],
	[&"highway_ns", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ew", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ns_road_ew", "Highway over Road", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ew_road_ns", "Highway over Road", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ns_rail_ew", "Highway over Rail", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ew_rail_ns", "Highway over Rail", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ns_power_ew", "Highway under Power Line", 1, 1, Category.HIGHWAY, 100],
	[&"highway_ew_power_ns", "Highway under Power Line", 1, 1, Category.HIGHWAY, 100],
	[&"bridge_suspension_start", "Suspension Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_suspension_rise", "Suspension Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_suspension_span", "Suspension Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_suspension_fall", "Suspension Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_suspension_end", "Suspension Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_lift_tower", "Lift Bridge Tower", 1, 1, Category.BRIDGE, 25],
	[&"bridge_causeway_pylon", "Causeway", 1, 1, Category.BRIDGE, 25],
	[&"bridge_lift_lowered", "Lift Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_lift_raised", "Lift Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_rail_pylon", "Rail Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_rail_span", "Rail Bridge", 1, 1, Category.BRIDGE, 25],
	[&"power_elevated", "Elevated Power Line", 1, 1, Category.BRIDGE, 2],
	[&"onramp_1", "Highway Ramp", 1, 1, Category.HIGHWAY, 25],
	[&"onramp_2", "Highway Ramp", 1, 1, Category.HIGHWAY, 25],
	[&"onramp_3", "Highway Ramp", 1, 1, Category.HIGHWAY, 25],
	[&"onramp_4", "Highway Ramp", 1, 1, Category.HIGHWAY, 25],
	[&"highway_slope_w", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_slope_n", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_slope_e", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_slope_s", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_corner_ne", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_corner_se", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_corner_sw", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_corner_nw", "Highway", 1, 1, Category.HIGHWAY, 100],
	[&"highway_junction", "Highway Interchange", 1, 1, Category.HIGHWAY, 100],
	[&"bridge_reinforced_pylon", "Reinforced Bridge", 1, 1, Category.BRIDGE, 25],
	[&"bridge_reinforced_span", "Reinforced Bridge", 1, 1, Category.BRIDGE, 25],
	[&"subway_portal_n", "Subway Portal", 1, 1, Category.RAIL, 500],
	[&"subway_portal_e", "Subway Portal", 1, 1, Category.RAIL, 500],
	[&"subway_portal_s", "Subway Portal", 1, 1, Category.RAIL, 500],
	[&"subway_portal_w", "Subway Portal", 1, 1, Category.RAIL, 500],
	[&"res_bungalow_1", "Bungalows", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_bungalow_2", "Bungalows", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_bungalow_3", "Bungalows", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_bungalow_4", "Bungalows", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_ranch_1", "Ranch Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_ranch_2", "Ranch Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_ranch_3", "Ranch Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_ranch_4", "Ranch Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_estate_1", "Estate Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_estate_2", "Estate Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_estate_3", "Estate Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"res_estate_4", "Estate Homes", 1, 1, Category.RESIDENTIAL, 0],
	[&"com_fuel_stop_1", "Fuel Stop", 1, 1, Category.COMMERCIAL, 0],
	[&"com_motor_court", "Motor Court", 1, 1, Category.COMMERCIAL, 0],
	[&"com_corner_store", "Corner Store", 1, 1, Category.COMMERCIAL, 0],
	[&"com_fuel_stop_2", "Fuel Stop", 1, 1, Category.COMMERCIAL, 0],
	[&"com_small_office_1", "Small Office", 1, 1, Category.COMMERCIAL, 0],
	[&"com_small_office_2", "Small Office", 1, 1, Category.COMMERCIAL, 0],
	[&"com_storefront", "Storefront", 1, 1, Category.COMMERCIAL, 0],
	[&"com_souvenir_shop", "Souvenir Shop", 1, 1, Category.COMMERCIAL, 0],
	[&"ind_shed_1", "Storage Shed", 1, 1, Category.INDUSTRIAL, 0],
	[&"ind_tank_farm", "Tank Farm", 1, 1, Category.INDUSTRIAL, 0],
	[&"ind_shed_2", "Storage Shed", 1, 1, Category.INDUSTRIAL, 0],
	[&"ind_substation", "Substation", 1, 1, Category.INDUSTRIAL, 0],
	[&"construction_1x1_a", "Construction Site", 1, 1, Category.CONSTRUCTION, 0],
	[&"construction_1x1_b", "Construction Site", 1, 1, Category.CONSTRUCTION, 0],
	[&"abandoned_1x1_a", "Abandoned Building", 1, 1, Category.ABANDONED, 0],
	[&"abandoned_1x1_b", "Abandoned Building", 1, 1, Category.ABANDONED, 0],
	[&"res_courtyard_1", "Courtyard Apartments", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_courtyard_2", "Courtyard Apartments", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_courtyard_3", "Courtyard Apartments", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_midrise_1", "Mid-rise Apartments", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_midrise_2", "Mid-rise Apartments", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_condo_1", "Condominiums", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_condo_2", "Condominiums", 2, 2, Category.RESIDENTIAL, 0],
	[&"res_condo_3", "Condominiums", 2, 2, Category.RESIDENTIAL, 0],
	[&"com_plaza", "Shopping Plaza", 2, 2, Category.COMMERCIAL, 0],
	[&"com_market", "Supermarket", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_1", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_casino_hotel", "Casino Hotel", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_2", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_mixed_use", "Mixed-use Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_3", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_4", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_5", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"com_office_6", "Office Block", 2, 2, Category.COMMERCIAL, 0],
	[&"ind_warehouse", "Warehouse", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_chemical_works", "Chemical Works", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_1", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_2", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_3", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_4", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_5", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"ind_workshop_6", "Workshop", 2, 2, Category.INDUSTRIAL, 0],
	[&"construction_2x2_a", "Construction Site", 2, 2, Category.CONSTRUCTION, 0],
	[&"construction_2x2_b", "Construction Site", 2, 2, Category.CONSTRUCTION, 0],
	[&"construction_2x2_c", "Construction Site", 2, 2, Category.CONSTRUCTION, 0],
	[&"construction_2x2_d", "Construction Site", 2, 2, Category.CONSTRUCTION, 0],
	[&"abandoned_2x2_a", "Abandoned Building", 2, 2, Category.ABANDONED, 0],
	[&"abandoned_2x2_b", "Abandoned Building", 2, 2, Category.ABANDONED, 0],
	[&"abandoned_2x2_c", "Abandoned Building", 2, 2, Category.ABANDONED, 0],
	[&"abandoned_2x2_d", "Abandoned Building", 2, 2, Category.ABANDONED, 0],
	[&"res_tower_1", "Apartment Tower", 3, 3, Category.RESIDENTIAL, 0],
	[&"res_tower_2", "Apartment Tower", 3, 3, Category.RESIDENTIAL, 0],
	[&"res_highrise_1", "Luxury High-rise", 3, 3, Category.RESIDENTIAL, 0],
	[&"res_highrise_2", "Luxury High-rise", 3, 3, Category.RESIDENTIAL, 0],
	[&"com_office_park", "Office Park", 3, 3, Category.COMMERCIAL, 0],
	[&"com_tower_1", "Office Tower", 3, 3, Category.COMMERCIAL, 0],
	[&"com_mall", "Shopping Mall", 3, 3, Category.COMMERCIAL, 0],
	[&"com_showroom", "Showroom Theater", 3, 3, Category.COMMERCIAL, 0],
	[&"com_drive_in", "Drive-in", 3, 3, Category.COMMERCIAL, 0],
	[&"com_tower_2", "Office Tower", 3, 3, Category.COMMERCIAL, 0],
	[&"com_tower_3", "Office Tower", 3, 3, Category.COMMERCIAL, 0],
	[&"com_parking", "Parking Structure", 3, 3, Category.COMMERCIAL, 0],
	[&"com_courthouse_offices", "Courthouse Offices", 3, 3, Category.COMMERCIAL, 0],
	[&"com_headquarters", "Corporate Headquarters", 3, 3, Category.COMMERCIAL, 0],
	[&"ind_refinery", "Refinery", 3, 3, Category.INDUSTRIAL, 0],
	[&"ind_plant_large", "Assembly Plant", 3, 3, Category.INDUSTRIAL, 0],
	[&"ind_cracking_tower", "Cracking Tower", 3, 3, Category.INDUSTRIAL, 0],
	[&"ind_plant_medium", "Fabrication Plant", 3, 3, Category.INDUSTRIAL, 0],
	[&"ind_distribution_1", "Distribution Center", 3, 3, Category.INDUSTRIAL, 0],
	[&"ind_distribution_2", "Distribution Center", 3, 3, Category.INDUSTRIAL, 0],
	[&"construction_3x3_a", "Construction Site", 3, 3, Category.CONSTRUCTION, 0],
	[&"construction_3x3_b", "Construction Site", 3, 3, Category.CONSTRUCTION, 0],
	[&"abandoned_3x3_a", "Abandoned Building", 3, 3, Category.ABANDONED, 0],
	[&"abandoned_3x3_b", "Abandoned Building", 3, 3, Category.ABANDONED, 0],
	[&"plant_hydro_a", "Hydroelectric Dam", 1, 1, Category.PLANT, 400],
	[&"plant_hydro_b", "Hydroelectric Dam", 1, 1, Category.PLANT, 400],
	[&"plant_wind", "Wind Turbine", 1, 1, Category.PLANT, 100],
	[&"plant_gas", "Gas Power Plant", 4, 4, Category.PLANT, 2000],
	[&"plant_oil", "Oil Power Plant", 4, 4, Category.PLANT, 6600],
	[&"plant_nuclear", "Nuclear Power Plant", 4, 4, Category.PLANT, 15000],
	[&"plant_solar", "Solar Farm", 4, 4, Category.PLANT, 1300],
	[&"plant_microwave", "Microwave Receiver", 4, 4, Category.PLANT, 28000],
	[&"plant_fusion", "Fusion Power Plant", 4, 4, Category.PLANT, 40000],
	[&"plant_coal", "Coal Power Plant", 4, 4, Category.PLANT, 4000],
	[&"city_hall", "City Hall", 3, 3, Category.REWARD, 0],
	[&"hospital", "Hospital", 3, 3, Category.CIVIC, 500],
	[&"police_station", "Police Station", 3, 3, Category.CIVIC, 500],
	[&"fire_station", "Fire Station", 3, 3, Category.CIVIC, 500],
	[&"museum", "Museum", 3, 3, Category.CIVIC, 100],
	[&"large_park", "City Park", 3, 3, Category.CIVIC, 150],
	[&"school", "School", 3, 3, Category.CIVIC, 250],
	[&"stadium", "Stadium", 4, 4, Category.CIVIC, 3000],
	[&"prison", "Prison", 4, 4, Category.CIVIC, 3000],
	[&"college", "College", 4, 4, Category.CIVIC, 1000],
	[&"zoo", "Zoo", 4, 4, Category.CIVIC, 3000],
	[&"monument", "Monument", 1, 1, Category.REWARD, 0],
	[&"water_pump", "Water Pump", 1, 1, Category.UTILITY, 100],
	[&"runway", "Runway", 1, 1, Category.PORT, 0],
	[&"runway_cross", "Runway Crossing", 1, 1, Category.PORT, 0],
	[&"pier", "Pier", 1, 1, Category.PORT, 0],
	[&"crane", "Container Crane", 1, 1, Category.PORT, 0],
	[&"control_tower", "Control Tower", 1, 1, Category.PORT, 0],
	[&"military_tower", "Military Control Tower", 1, 1, Category.MILITARY, 0],
	[&"port_warehouse", "Freight Warehouse", 1, 1, Category.PORT, 0],
	[&"port_building_a", "Terminal", 1, 1, Category.PORT, 0],
	[&"port_building_b", "Terminal", 1, 1, Category.PORT, 0],
	[&"tarmac", "Tarmac", 1, 1, Category.PORT, 0],
	[&"fighter_jet", "Parked Jet", 1, 1, Category.MILITARY, 0],
	[&"hangar_small", "Hangar", 1, 1, Category.PORT, 0],
	[&"subway_station", "Subway Station", 1, 1, Category.TRANSIT, 250],
	[&"radar", "Radar Dome", 1, 1, Category.PORT, 0],
	[&"water_tower", "Water Tower", 2, 2, Category.UTILITY, 250],
	[&"bus_depot", "Bus Depot", 2, 2, Category.TRANSIT, 250],
	[&"rail_station", "Rail Station", 2, 2, Category.TRANSIT, 500],
	[&"parking_civil", "Parking Lot", 2, 2, Category.PORT, 0],
	[&"parking_military", "Motor Pool", 2, 2, Category.MILITARY, 0],
	[&"loading_bay", "Loading Bay", 2, 2, Category.PORT, 0],
	[&"restricted_facility", "Restricted Facility", 2, 2, Category.MILITARY, 0],
	[&"cargo_yard", "Cargo Yard", 2, 2, Category.PORT, 0],
	[&"mayors_residence", "Mayor's Residence", 2, 2, Category.REWARD, 0],
	[&"water_treatment", "Water Treatment Plant", 2, 2, Category.UTILITY, 500],
	[&"library", "Library", 2, 2, Category.CIVIC, 500],
	[&"hangar_large", "Large Hangar", 2, 2, Category.PORT, 0],
	[&"chapel", "Wedding Chapel", 2, 2, Category.CIVIC, 0],
	[&"marina", "Marina", 3, 3, Category.CIVIC, 1000],
	[&"missile_silo", "Missile Silo", 3, 3, Category.MILITARY, 0],
	[&"desalination", "Desalination Plant", 3, 3, Category.UTILITY, 1000],
	[&"arcology_comstock", "Comstock Grand", 4, 4, Category.ARCOLOGY, 100000],
	[&"arcology_junction", "Silver Junction", 4, 4, Category.ARCOLOGY, 120000],
	[&"arcology_boulder", "Boulder Crown", 4, 4, Category.ARCOLOGY, 150000],
	[&"arcology_orbit", "Desert Orbit", 4, 4, Category.ARCOLOGY, 200000],
	[&"neon_dome", "Neon Dome", 4, 4, Category.REWARD, 0],
]

static var _by_key: Dictionary = {}


static func _ensure_index() -> void:
	if _by_key.is_empty():
		for id in _ROSTER.size():
			_by_key[_ROSTER[id][0]] = id


static func key(id: int) -> StringName:
	if id < 0 or id >= _ROSTER.size():
		return &"nothing"
	return _ROSTER[id][0]


static func id_of(building_key: StringName) -> int:
	_ensure_index()
	return _by_key.get(building_key, NONE)


static func display_name(id: int) -> String:
	if id < 0 or id >= _ROSTER.size():
		return "Unknown"
	return _ROSTER[id][1]


static func size(id: int) -> Vector2i:
	if id < 0 or id >= _ROSTER.size():
		return Vector2i.ONE
	return Vector2i(_ROSTER[id][2], _ROSTER[id][3])


static func category(id: int) -> int:
	if id < 0 or id >= _ROSTER.size():
		return Category.NONE
	return _ROSTER[id][4]


static func cost(id: int) -> int:
	if id < 0 or id >= _ROSTER.size():
		return 0
	return _ROSTER[id][5]


static func is_multi_tile(id: int) -> bool:
	var s := size(id)
	return s.x > 1 or s.y > 1


static func is_zone_building(id: int) -> bool:
	var c := category(id)
	return c == Category.RESIDENTIAL or c == Category.COMMERCIAL or c == Category.INDUSTRIAL


static func is_developed(id: int) -> bool:
	return is_zone_building(id) or category(id) in [Category.PLANT, Category.CIVIC,
		Category.UTILITY, Category.TRANSIT, Category.PORT, Category.MILITARY,
		Category.REWARD, Category.ARCOLOGY]


static func is_network(id: int) -> bool:
	return category(id) in [Category.POWER_LINE, Category.ROAD, Category.RAIL,
		Category.HIGHWAY, Category.BRIDGE, Category.TUNNEL]


static func is_road_like(id: int) -> bool:
	if id >= ROAD_FIRST and id <= ROAD_LAST: return true
	if id >= TUNNEL_FIRST and id <= TUNNEL_LAST: return true
	if id >= CROSSING_FIRST and id <= CROSSING_LAST: return id != 71 and id != 72
	if id >= HIGHWAY_FIRST and id <= HIGHWAY_LAST: return true
	if id >= BRIDGE_FIRST and id <= 89: return true
	if id >= ONRAMP_FIRST and id <= HIGHWAY_PIECE_LAST: return true
	if id == REINFORCED_PYLON or id == REINFORCED_BRIDGE: return true
	return false


static func is_rail_like(id: int) -> bool:
	if id >= RAIL_FIRST and id <= RAIL_LAST: return true
	if id == 69 or id == 70 or id == 71 or id == 72: return true
	if id == 90 or id == 91: return true
	if id >= SUBWAY_PORTAL_FIRST and id <= SUBWAY_PORTAL_LAST: return true
	return false


static func carries_power(id: int) -> bool:
	if id >= POWER_LINE_FIRST and id <= POWER_LINE_LAST: return true
	if id == 67 or id == 68 or id == 71 or id == 72: return true
	if id == 79 or id == 80: return true      # highway under power
	if category(id) == Category.BRIDGE: return true # bridge decks carry utility service
	return is_developed(id)


static func is_tree(id: int) -> bool:
	return id >= TREES_1 and id <= TREES_7


static func is_rubble(id: int) -> bool:
	return id >= RUBBLE_1 and id <= CONTAMINATION


static func is_construction(id: int) -> bool:
	return category(id) == Category.CONSTRUCTION


static func is_abandoned(id: int) -> bool:
	return category(id) == Category.ABANDONED


static func is_power_plant(id: int) -> bool:
	return category(id) == Category.PLANT


static func is_arcology(id: int) -> bool:
	return category(id) == Category.ARCOLOGY


## Ids that develop inside a zone kind, grouped by footprint size.
static func zone_stage_ids(zone_kind: int, footprint: int) -> Array[int]:
	var out: Array[int] = []
	var first := 0
	var last := 0
	match [zone_kind, footprint]:
		[Zones.RES_LOW, 1], [Zones.RES_HIGH, 1]: first = RES_1X1_FIRST; last = RES_1X1_LAST
		[Zones.RES_HIGH, 2]: first = RES_2X2_FIRST; last = RES_2X2_LAST
		[Zones.RES_HIGH, 3]: first = RES_3X3_FIRST; last = RES_3X3_LAST
		[Zones.COM_LOW, 1], [Zones.COM_HIGH, 1]: first = COM_1X1_FIRST; last = COM_1X1_LAST
		[Zones.COM_HIGH, 2]: first = COM_2X2_FIRST; last = COM_2X2_LAST
		[Zones.COM_HIGH, 3]: first = COM_3X3_FIRST; last = COM_3X3_LAST
		[Zones.IND_LOW, 1], [Zones.IND_HIGH, 1]: first = IND_1X1_FIRST; last = IND_1X1_LAST
		[Zones.IND_HIGH, 2]: first = IND_2X2_FIRST; last = IND_2X2_LAST
		[Zones.IND_HIGH, 3]: first = IND_3X3_FIRST; last = IND_3X3_LAST
		_: return out
	for id in range(first, last + 1):
		out.append(id)
	return out


static func all_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _ROSTER.size():
		out.append(id)
	return out
