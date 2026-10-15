# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const LEGACY_BUILDING_CONSTANTS := {"NONE": 0, "RUBBLE_1": 1, "RUBBLE_4": 4, "CONTAMINATION": 5, "TREES_1": 6, "TREES_7": 12, "SMALL_PARK": 13, "POWER_LINE_FIRST": 14, "POWER_LINE_LAST": 28, "ROAD_FIRST": 29, "ROAD_LAST": 43, "RAIL_FIRST": 44, "RAIL_LAST": 62, "TUNNEL_FIRST": 63, "TUNNEL_LAST": 66, "CROSSING_FIRST": 67, "CROSSING_LAST": 72, "HIGHWAY_FIRST": 73, "HIGHWAY_LAST": 80, "BRIDGE_FIRST": 81, "BRIDGE_LAST": 92, "ONRAMP_FIRST": 93, "ONRAMP_LAST": 96, "HIGHWAY_PIECE_FIRST": 97, "HIGHWAY_PIECE_LAST": 105, "REINFORCED_PYLON": 106, "REINFORCED_BRIDGE": 107, "SUBWAY_PORTAL_FIRST": 108, "SUBWAY_PORTAL_LAST": 111, "RES_1X1_FIRST": 112, "RES_1X1_LAST": 123, "COM_1X1_FIRST": 124, "COM_1X1_LAST": 131, "IND_1X1_FIRST": 132, "IND_1X1_LAST": 135, "CONSTRUCTION_1X1_A": 136, "CONSTRUCTION_1X1_B": 137, "ABANDONED_1X1_A": 138, "ABANDONED_1X1_B": 139, "RES_2X2_FIRST": 140, "RES_2X2_LAST": 147, "COM_2X2_FIRST": 148, "COM_2X2_LAST": 157, "IND_2X2_FIRST": 158, "IND_2X2_LAST": 165, "CONSTRUCTION_2X2_FIRST": 166, "CONSTRUCTION_2X2_LAST": 169, "ABANDONED_2X2_FIRST": 170, "ABANDONED_2X2_LAST": 173, "RES_3X3_FIRST": 174, "RES_3X3_LAST": 177, "COM_3X3_FIRST": 178, "COM_3X3_LAST": 187, "IND_3X3_FIRST": 188, "IND_3X3_LAST": 193, "CONSTRUCTION_3X3_A": 194, "CONSTRUCTION_3X3_B": 195, "ABANDONED_3X3_A": 196, "ABANDONED_3X3_B": 197, "HYDRO_PLANT_A": 198, "HYDRO_PLANT_B": 199, "WIND_PLANT": 200, "GAS_PLANT": 201, "OIL_PLANT": 202, "NUCLEAR_PLANT": 203, "SOLAR_PLANT": 204, "MICROWAVE_PLANT": 205, "FUSION_PLANT": 206, "COAL_PLANT": 207, "CITY_HALL": 208, "HOSPITAL": 209, "POLICE_STATION": 210, "FIRE_STATION": 211, "MUSEUM": 212, "LARGE_PARK": 213, "SCHOOL": 214, "STADIUM": 215, "PRISON": 216, "COLLEGE": 217, "ZOO": 218, "MONUMENT": 219, "WATER_PUMP": 220, "RUNWAY": 221, "RUNWAY_CROSS": 222, "PIER": 223, "CRANE": 224, "CONTROL_TOWER": 225, "MILITARY_TOWER": 226, "PORT_WAREHOUSE": 227, "PORT_BUILDING_A": 228, "PORT_BUILDING_B": 229, "TARMAC": 230, "FIGHTER_JET": 231, "HANGAR_SMALL": 232, "SUBWAY_STATION": 233, "RADAR": 234, "WATER_TOWER": 235, "BUS_DEPOT": 236, "RAIL_STATION": 237, "PARKING_CIVIL": 238, "PARKING_MILITARY": 239, "LOADING_BAY": 240, "RESTRICTED_FACILITY": 241, "CARGO_YARD": 242, "MAYORS_RESIDENCE": 243, "WATER_TREATMENT": 244, "LIBRARY": 245, "HANGAR_LARGE": 246, "CHAPEL": 247, "MARINA": 248, "MISSILE_SILO": 249, "DESALINATION": 250, "ARCOLOGY_COMSTOCK": 251, "ARCOLOGY_JUNCTION": 252, "ARCOLOGY_BOULDER": 253, "ARCOLOGY_ORBIT": 254, "NEON_DOME": 255, "ARCOLOGY_FIX": 256, "ARCOLOGY_ALIBI": 257, "ARCOLOGY_VELVET": 258, "ARCOLOGY_AFTERGLOW": 259, "ARCOLOGY_LAST": 260, "ARCOLOGY_DUST": 261, "ARCOLOGY_BODDY": 262, "ARCOLOGY_WOOLIER": 263, "ARCOLOGY_STOCKGROWERS": 264, "ARCOLOGY_FREMONT": 265}
const LEGACY_CATEGORIES := {"NONE": 0, "RUBBLE": 1, "TREE": 2, "POWER_LINE": 3, "ROAD": 4, "RAIL": 5, "HIGHWAY": 6, "BRIDGE": 7, "TUNNEL": 8, "RESIDENTIAL": 9, "COMMERCIAL": 10, "INDUSTRIAL": 11, "CONSTRUCTION": 12, "ABANDONED": 13, "PLANT": 14, "CIVIC": 15, "UTILITY": 16, "TRANSIT": 17, "PORT": 18, "MILITARY": 19, "REWARD": 20, "ARCOLOGY": 21}
const LEGACY_TOOL_KINDS := {"QUERY": 0, "BULLDOZE": 1, "DEZONE": 2, "SIGN": 3, "ROAD": 4, "HIGHWAY": 5, "ONRAMP": 6, "TUNNEL": 7, "RAIL": 8, "SUBWAY": 9, "SUBWAY_PORTAL": 10, "POWER_LINE": 11, "WATER_PIPE": 12, "ZONE_RES_LOW": 13, "ZONE_RES_HIGH": 14, "ZONE_COM_LOW": 15, "ZONE_COM_HIGH": 16, "ZONE_IND_LOW": 17, "ZONE_IND_HIGH": 18, "AIRPORT": 19, "SEAPORT": 20, "TREES": 21, "SMALL_PARK": 22, "LARGE_PARK": 23, "WATER_PUMP": 24, "WATER_TOWER": 25, "WATER_TREATMENT": 26, "DESALINATION": 27, "POLICE": 28, "FIRE": 29, "HOSPITAL": 30, "SCHOOL": 31, "COLLEGE": 32, "LIBRARY": 33, "MUSEUM": 34, "STADIUM": 35, "MARINA": 36, "ZOO": 37, "PRISON": 38, "BUS_DEPOT": 39, "RAIL_STATION": 40, "SUBWAY_STATION": 41, "COAL_PLANT": 42, "HYDRO_PLANT": 43, "WIND_PLANT": 44, "GAS_PLANT": 45, "OIL_PLANT": 46, "NUCLEAR_PLANT": 47, "SOLAR_PLANT": 48, "MICROWAVE_PLANT": 49, "FUSION_PLANT": 50, "ARCOLOGY_COMSTOCK": 51, "ARCOLOGY_JUNCTION": 52, "ARCOLOGY_BOULDER": 53, "ARCOLOGY_ORBIT": 54, "REWARD_MAYORS_RESIDENCE": 55, "REWARD_CITY_HALL": 56, "REWARD_MONUMENT": 57, "REWARD_MILITARY_BASE": 58, "REWARD_NEON_DOME": 59, "DISPATCH_FIRE": 60, "DISPATCH_POLICE": 61, "DISPATCH_MILITARY": 62, "RAISE_LAND": 63, "LOWER_LAND": 64, "LEVEL_LAND": 65, "PLACE_WATER": 66, "FOREST": 67, "RAISE_SEA": 68, "LOWER_SEA": 69, "PLANT_TREE": 70, "ARCOLOGY_FIX": 71, "ARCOLOGY_ALIBI": 72, "ARCOLOGY_VELVET": 73, "ARCOLOGY_AFTERGLOW": 74, "ARCOLOGY_LAST": 75, "ARCOLOGY_DUST": 76, "ARCOLOGY_BODDY": 77, "ARCOLOGY_WOOLIER": 78, "ARCOLOGY_STOCKGROWERS": 79, "ARCOLOGY_FREMONT": 80}
const LEGACY_ZONES := {"NONE": 0, "RES_LOW": 1, "RES_HIGH": 2, "COM_LOW": 3, "COM_HIGH": 4, "IND_LOW": 5, "IND_HIGH": 6, "MILITARY": 7, "AIRPORT": 8, "SEAPORT": 9, "KIND_MASK": 15, "CORNER_NW": 16, "CORNER_NE": 32, "CORNER_SE": 64, "CORNER_SW": 128, "CORNER_MASK": 240, "ALL_CORNERS": 240}
const LEGACY_ROSTER := [
	[&"nothing", "Open Ground", 1, 1, 0, 0],
	[&"rubble_1", "Rubble", 1, 1, 1, 0],
	[&"rubble_2", "Rubble", 1, 1, 1, 0],
	[&"rubble_3", "Rubble", 1, 1, 1, 0],
	[&"rubble_4", "Rubble", 1, 1, 1, 0],
	[&"contamination", "Contaminated Ground", 1, 1, 1, 0],
	[&"trees_1", "Lone Palm", 1, 1, 2, 3],
	[&"trees_2", "Palm Pair", 1, 1, 2, 3],
	[&"trees_3", "Palm Cluster", 1, 1, 2, 3],
	[&"trees_4", "Palm Grove", 1, 1, 2, 3],
	[&"trees_5", "Dense Grove", 1, 1, 2, 3],
	[&"trees_6", "Oasis Thicket", 1, 1, 2, 3],
	[&"trees_7", "Riparian Woodland", 1, 1, 2, 3],
	[&"small_park", "Pocket Park", 1, 1, 2, 10],
	[&"power_ns", "Power Line", 1, 1, 3, 2],
	[&"power_ew", "Power Line", 1, 1, 3, 2],
	[&"power_slope_w", "Power Line", 1, 1, 3, 2],
	[&"power_slope_n", "Power Line", 1, 1, 3, 2],
	[&"power_slope_e", "Power Line", 1, 1, 3, 2],
	[&"power_slope_s", "Power Line", 1, 1, 3, 2],
	[&"power_ne", "Power Line", 1, 1, 3, 2],
	[&"power_se", "Power Line", 1, 1, 3, 2],
	[&"power_sw", "Power Line", 1, 1, 3, 2],
	[&"power_nw", "Power Line", 1, 1, 3, 2],
	[&"power_new", "Power Line", 1, 1, 3, 2],
	[&"power_nes", "Power Line", 1, 1, 3, 2],
	[&"power_esw", "Power Line", 1, 1, 3, 2],
	[&"power_nsw", "Power Line", 1, 1, 3, 2],
	[&"power_nesw", "Power Line", 1, 1, 3, 2],
	[&"road_ns", "Road", 1, 1, 4, 10],
	[&"road_ew", "Road", 1, 1, 4, 10],
	[&"road_slope_w", "Road", 1, 1, 4, 10],
	[&"road_slope_n", "Road", 1, 1, 4, 10],
	[&"road_slope_e", "Road", 1, 1, 4, 10],
	[&"road_slope_s", "Road", 1, 1, 4, 10],
	[&"road_ne", "Road", 1, 1, 4, 10],
	[&"road_se", "Road", 1, 1, 4, 10],
	[&"road_sw", "Road", 1, 1, 4, 10],
	[&"road_nw", "Road", 1, 1, 4, 10],
	[&"road_new", "Road", 1, 1, 4, 10],
	[&"road_nes", "Road", 1, 1, 4, 10],
	[&"road_esw", "Road", 1, 1, 4, 10],
	[&"road_nsw", "Road", 1, 1, 4, 10],
	[&"road_nesw", "Road", 1, 1, 4, 10],
	[&"rail_ns", "Rail", 1, 1, 5, 25],
	[&"rail_ew", "Rail", 1, 1, 5, 25],
	[&"rail_slope_w", "Rail", 1, 1, 5, 25],
	[&"rail_slope_n", "Rail", 1, 1, 5, 25],
	[&"rail_slope_e", "Rail", 1, 1, 5, 25],
	[&"rail_slope_s", "Rail", 1, 1, 5, 25],
	[&"rail_ne", "Rail", 1, 1, 5, 25],
	[&"rail_se", "Rail", 1, 1, 5, 25],
	[&"rail_sw", "Rail", 1, 1, 5, 25],
	[&"rail_nw", "Rail", 1, 1, 5, 25],
	[&"rail_new", "Rail", 1, 1, 5, 25],
	[&"rail_nes", "Rail", 1, 1, 5, 25],
	[&"rail_esw", "Rail", 1, 1, 5, 25],
	[&"rail_nsw", "Rail", 1, 1, 5, 25],
	[&"rail_nesw", "Rail", 1, 1, 5, 25],
	[&"rail_uphill_w", "Rail", 1, 1, 5, 25],
	[&"rail_uphill_n", "Rail", 1, 1, 5, 25],
	[&"rail_uphill_e", "Rail", 1, 1, 5, 25],
	[&"rail_uphill_s", "Rail", 1, 1, 5, 25],
	[&"tunnel_w", "Tunnel Entrance", 1, 1, 8, 150],
	[&"tunnel_n", "Tunnel Entrance", 1, 1, 8, 150],
	[&"tunnel_e", "Tunnel Entrance", 1, 1, 8, 150],
	[&"tunnel_s", "Tunnel Entrance", 1, 1, 8, 150],
	[&"cross_road_ns_power_ew", "Road under Power Line", 1, 1, 4, 10],
	[&"cross_road_ew_power_ns", "Road under Power Line", 1, 1, 4, 10],
	[&"cross_road_ns_rail_ew", "Level Crossing", 1, 1, 4, 10],
	[&"cross_road_ew_rail_ns", "Level Crossing", 1, 1, 4, 10],
	[&"cross_rail_ns_power_ew", "Rail under Power Line", 1, 1, 3, 25],
	[&"cross_rail_ew_power_ns", "Rail under Power Line", 1, 1, 3, 25],
	[&"highway_ns", "Highway", 1, 1, 6, 100],
	[&"highway_ew", "Highway", 1, 1, 6, 100],
	[&"highway_ns_road_ew", "Highway over Road", 1, 1, 6, 100],
	[&"highway_ew_road_ns", "Highway over Road", 1, 1, 6, 100],
	[&"highway_ns_rail_ew", "Highway over Rail", 1, 1, 6, 100],
	[&"highway_ew_rail_ns", "Highway over Rail", 1, 1, 6, 100],
	[&"highway_ns_power_ew", "Highway under Power Line", 1, 1, 6, 100],
	[&"highway_ew_power_ns", "Highway under Power Line", 1, 1, 6, 100],
	[&"bridge_suspension_start", "Suspension Bridge", 1, 1, 7, 25],
	[&"bridge_suspension_rise", "Suspension Bridge", 1, 1, 7, 25],
	[&"bridge_suspension_span", "Suspension Bridge", 1, 1, 7, 25],
	[&"bridge_suspension_fall", "Suspension Bridge", 1, 1, 7, 25],
	[&"bridge_suspension_end", "Suspension Bridge", 1, 1, 7, 25],
	[&"bridge_lift_tower", "Lift Bridge Tower", 1, 1, 7, 25],
	[&"bridge_causeway_pylon", "Causeway", 1, 1, 7, 25],
	[&"bridge_lift_lowered", "Lift Bridge", 1, 1, 7, 25],
	[&"bridge_lift_raised", "Lift Bridge", 1, 1, 7, 25],
	[&"bridge_rail_pylon", "Rail Bridge", 1, 1, 7, 25],
	[&"bridge_rail_span", "Rail Bridge", 1, 1, 7, 25],
	[&"power_elevated", "Elevated Power Line", 1, 1, 7, 2],
	[&"onramp_1", "Highway Ramp", 1, 1, 6, 25],
	[&"onramp_2", "Highway Ramp", 1, 1, 6, 25],
	[&"onramp_3", "Highway Ramp", 1, 1, 6, 25],
	[&"onramp_4", "Highway Ramp", 1, 1, 6, 25],
	[&"highway_slope_w", "Highway", 1, 1, 6, 100],
	[&"highway_slope_n", "Highway", 1, 1, 6, 100],
	[&"highway_slope_e", "Highway", 1, 1, 6, 100],
	[&"highway_slope_s", "Highway", 1, 1, 6, 100],
	[&"highway_corner_ne", "Highway", 1, 1, 6, 100],
	[&"highway_corner_se", "Highway", 1, 1, 6, 100],
	[&"highway_corner_sw", "Highway", 1, 1, 6, 100],
	[&"highway_corner_nw", "Highway", 1, 1, 6, 100],
	[&"highway_junction", "Highway Interchange", 1, 1, 6, 100],
	[&"bridge_reinforced_pylon", "Reinforced Bridge", 1, 1, 7, 25],
	[&"bridge_reinforced_span", "Reinforced Bridge", 1, 1, 7, 25],
	[&"subway_portal_n", "Subway Portal", 1, 1, 5, 500],
	[&"subway_portal_e", "Subway Portal", 1, 1, 5, 500],
	[&"subway_portal_s", "Subway Portal", 1, 1, 5, 500],
	[&"subway_portal_w", "Subway Portal", 1, 1, 5, 500],
	[&"res_bungalow_1", "Bungalows", 1, 1, 9, 0],
	[&"res_bungalow_2", "Bungalows", 1, 1, 9, 0],
	[&"res_bungalow_3", "Bungalows", 1, 1, 9, 0],
	[&"res_bungalow_4", "Bungalows", 1, 1, 9, 0],
	[&"res_ranch_1", "Ranch Homes", 1, 1, 9, 0],
	[&"res_ranch_2", "Ranch Homes", 1, 1, 9, 0],
	[&"res_ranch_3", "Ranch Homes", 1, 1, 9, 0],
	[&"res_ranch_4", "Ranch Homes", 1, 1, 9, 0],
	[&"res_estate_1", "Estate Homes", 1, 1, 9, 0],
	[&"res_estate_2", "Estate Homes", 1, 1, 9, 0],
	[&"res_estate_3", "Estate Homes", 1, 1, 9, 0],
	[&"res_estate_4", "Estate Homes", 1, 1, 9, 0],
	[&"com_fuel_stop_1", "Fuel Stop", 1, 1, 10, 0],
	[&"com_motor_court", "Motor Court", 1, 1, 10, 0],
	[&"com_corner_store", "Corner Store", 1, 1, 10, 0],
	[&"com_fuel_stop_2", "Fuel Stop", 1, 1, 10, 0],
	[&"com_small_office_1", "Small Office", 1, 1, 10, 0],
	[&"com_small_office_2", "Small Office", 1, 1, 10, 0],
	[&"com_storefront", "Storefront", 1, 1, 10, 0],
	[&"com_souvenir_shop", "Souvenir Shop", 1, 1, 10, 0],
	[&"ind_shed_1", "Storage Shed", 1, 1, 11, 0],
	[&"ind_tank_farm", "Tank Farm", 1, 1, 11, 0],
	[&"ind_shed_2", "Storage Shed", 1, 1, 11, 0],
	[&"ind_substation", "Substation", 1, 1, 11, 0],
	[&"construction_1x1_a", "Construction Site", 1, 1, 12, 0],
	[&"construction_1x1_b", "Construction Site", 1, 1, 12, 0],
	[&"abandoned_1x1_a", "Abandoned Building", 1, 1, 13, 0],
	[&"abandoned_1x1_b", "Abandoned Building", 1, 1, 13, 0],
	[&"res_courtyard_1", "Courtyard Apartments", 2, 2, 9, 0],
	[&"res_courtyard_2", "Courtyard Apartments", 2, 2, 9, 0],
	[&"res_courtyard_3", "Courtyard Apartments", 2, 2, 9, 0],
	[&"res_midrise_1", "Mid-rise Apartments", 2, 2, 9, 0],
	[&"res_midrise_2", "Mid-rise Apartments", 2, 2, 9, 0],
	[&"res_condo_1", "Condominiums", 2, 2, 9, 0],
	[&"res_condo_2", "Condominiums", 2, 2, 9, 0],
	[&"res_condo_3", "Condominiums", 2, 2, 9, 0],
	[&"com_plaza", "Shopping Plaza", 2, 2, 10, 0],
	[&"com_market", "Supermarket", 2, 2, 10, 0],
	[&"com_office_1", "Office Block", 2, 2, 10, 0],
	[&"com_casino_hotel", "Casino Hotel", 2, 2, 10, 0],
	[&"com_office_2", "Office Block", 2, 2, 10, 0],
	[&"com_mixed_use", "Mixed-use Block", 2, 2, 10, 0],
	[&"com_office_3", "Office Block", 2, 2, 10, 0],
	[&"com_office_4", "Office Block", 2, 2, 10, 0],
	[&"com_office_5", "Office Block", 2, 2, 10, 0],
	[&"com_office_6", "Office Block", 2, 2, 10, 0],
	[&"ind_warehouse", "Warehouse", 2, 2, 11, 0],
	[&"ind_chemical_works", "Chemical Works", 2, 2, 11, 0],
	[&"ind_workshop_1", "Workshop", 2, 2, 11, 0],
	[&"ind_workshop_2", "Workshop", 2, 2, 11, 0],
	[&"ind_workshop_3", "Workshop", 2, 2, 11, 0],
	[&"ind_workshop_4", "Workshop", 2, 2, 11, 0],
	[&"ind_workshop_5", "Workshop", 2, 2, 11, 0],
	[&"ind_workshop_6", "Workshop", 2, 2, 11, 0],
	[&"construction_2x2_a", "Construction Site", 2, 2, 12, 0],
	[&"construction_2x2_b", "Construction Site", 2, 2, 12, 0],
	[&"construction_2x2_c", "Construction Site", 2, 2, 12, 0],
	[&"construction_2x2_d", "Construction Site", 2, 2, 12, 0],
	[&"abandoned_2x2_a", "Abandoned Building", 2, 2, 13, 0],
	[&"abandoned_2x2_b", "Abandoned Building", 2, 2, 13, 0],
	[&"abandoned_2x2_c", "Abandoned Building", 2, 2, 13, 0],
	[&"abandoned_2x2_d", "Abandoned Building", 2, 2, 13, 0],
	[&"res_tower_1", "Apartment Tower", 3, 3, 9, 0],
	[&"res_tower_2", "Apartment Tower", 3, 3, 9, 0],
	[&"res_highrise_1", "Luxury High-rise", 3, 3, 9, 0],
	[&"res_highrise_2", "Luxury High-rise", 3, 3, 9, 0],
	[&"com_office_park", "Office Park", 3, 3, 10, 0],
	[&"com_tower_1", "Office Tower", 3, 3, 10, 0],
	[&"com_mall", "Shopping Mall", 3, 3, 10, 0],
	[&"com_showroom", "Showroom Theater", 3, 3, 10, 0],
	[&"com_drive_in", "Drive-in", 3, 3, 10, 0],
	[&"com_tower_2", "Office Tower", 3, 3, 10, 0],
	[&"com_tower_3", "Office Tower", 3, 3, 10, 0],
	[&"com_parking", "Parking Structure", 3, 3, 10, 0],
	[&"com_courthouse_offices", "Courthouse Offices", 3, 3, 10, 0],
	[&"com_headquarters", "Corporate Headquarters", 3, 3, 10, 0],
	[&"ind_refinery", "Refinery", 3, 3, 11, 0],
	[&"ind_plant_large", "Assembly Plant", 3, 3, 11, 0],
	[&"ind_cracking_tower", "Cracking Tower", 3, 3, 11, 0],
	[&"ind_plant_medium", "Fabrication Plant", 3, 3, 11, 0],
	[&"ind_distribution_1", "Distribution Center", 3, 3, 11, 0],
	[&"ind_distribution_2", "Distribution Center", 3, 3, 11, 0],
	[&"construction_3x3_a", "Construction Site", 3, 3, 12, 0],
	[&"construction_3x3_b", "Construction Site", 3, 3, 12, 0],
	[&"abandoned_3x3_a", "Abandoned Building", 3, 3, 13, 0],
	[&"abandoned_3x3_b", "Abandoned Building", 3, 3, 13, 0],
	[&"plant_hydro_a", "Hydroelectric Dam", 1, 1, 14, 400],
	[&"plant_hydro_b", "Hydroelectric Dam", 1, 1, 14, 400],
	[&"plant_wind", "Wind Turbine", 1, 1, 14, 100],
	[&"plant_gas", "Gas Power Plant", 4, 4, 14, 2000],
	[&"plant_oil", "Oil Power Plant", 4, 4, 14, 6600],
	[&"plant_nuclear", "Nuclear Power Plant", 4, 4, 14, 15000],
	[&"plant_solar", "Solar Farm", 4, 4, 14, 1300],
	[&"plant_microwave", "Microwave Receiver", 4, 4, 14, 28000],
	[&"plant_fusion", "Fusion Power Plant", 4, 4, 14, 40000],
	[&"plant_coal", "Coal Power Plant", 4, 4, 14, 4000],
	[&"city_hall", "City Hall", 3, 3, 20, 0],
	[&"hospital", "Hospital", 3, 3, 15, 500],
	[&"police_station", "Police Station", 3, 3, 15, 500],
	[&"fire_station", "Fire Station", 3, 3, 15, 500],
	[&"museum", "Museum", 3, 3, 15, 100],
	[&"large_park", "City Park", 3, 3, 15, 150],
	[&"school", "School", 3, 3, 15, 250],
	[&"stadium", "Stadium", 4, 4, 15, 3000],
	[&"prison", "Prison", 4, 4, 15, 3000],
	[&"college", "College", 4, 4, 15, 1000],
	[&"zoo", "Zoo", 4, 4, 15, 3000],
	[&"monument", "Monument", 1, 1, 20, 0],
	[&"water_pump", "Water Pump", 1, 1, 16, 100],
	[&"runway", "Runway", 1, 1, 18, 0],
	[&"runway_cross", "Runway Crossing", 1, 1, 18, 0],
	[&"pier", "Pier", 1, 1, 18, 0],
	[&"crane", "Container Crane", 1, 1, 18, 0],
	[&"control_tower", "Control Tower", 1, 1, 18, 0],
	[&"military_tower", "Military Control Tower", 1, 1, 19, 0],
	[&"port_warehouse", "Freight Warehouse", 1, 1, 18, 0],
	[&"port_building_a", "Terminal", 1, 1, 18, 0],
	[&"port_building_b", "Terminal", 1, 1, 18, 0],
	[&"tarmac", "Tarmac", 1, 1, 18, 0],
	[&"fighter_jet", "Parked Jet", 1, 1, 19, 0],
	[&"hangar_small", "Hangar", 1, 1, 18, 0],
	[&"subway_station", "Subway Station", 1, 1, 17, 250],
	[&"radar", "Radar Dome", 1, 1, 18, 0],
	[&"water_tower", "Water Tower", 2, 2, 16, 250],
	[&"bus_depot", "Bus Depot", 2, 2, 17, 250],
	[&"rail_station", "Rail Station", 2, 2, 17, 500],
	[&"parking_civil", "Parking Lot", 2, 2, 18, 0],
	[&"parking_military", "Motor Pool", 2, 2, 19, 0],
	[&"loading_bay", "Loading Bay", 2, 2, 18, 0],
	[&"restricted_facility", "Restricted Facility", 2, 2, 19, 0],
	[&"cargo_yard", "Cargo Yard", 2, 2, 18, 0],
	[&"mayors_residence", "Mayor's Residence", 2, 2, 20, 0],
	[&"water_treatment", "Water Treatment Plant", 2, 2, 16, 500],
	[&"library", "Library", 2, 2, 15, 500],
	[&"hangar_large", "Large Hangar", 2, 2, 18, 0],
	[&"chapel", "Wedding Chapel", 2, 2, 15, 0],
	[&"marina", "Marina", 3, 3, 15, 1000],
	[&"missile_silo", "Missile Silo", 3, 3, 19, 0],
	[&"desalination", "Desalination Plant", 3, 3, 16, 1000],
	[&"arcology_comstock", "Comstock Grand", 4, 4, 21, 100000],
	[&"arcology_junction", "Silver Junction", 4, 4, 21, 120000],
	[&"arcology_boulder", "Boulder Crown", 4, 4, 21, 150000],
	[&"arcology_orbit", "Desert Orbit", 4, 4, 21, 200000],
	[&"neon_dome", "Neon Dome", 4, 4, 20, 0],
	[&"arcology_fix", "The Fix", 4, 4, 21, 320000],
	[&"arcology_alibi", "Six-Week Alibi", 4, 4, 21, 140000],
	[&"arcology_velvet", "Velvet Wardrobe", 4, 4, 21, 220000],
	[&"arcology_afterglow", "The Afterglow", 4, 4, 21, 500000],
	[&"arcology_last", "Last Resort", 4, 4, 21, 60000],
	[&"arcology_dust", "Dust Republic", 4, 4, 21, 95000],
	[&"arcology_boddy", "Boddy's", 2, 2, 21, 8000],
	[&"arcology_woolier", "Woolier Days", 2, 2, 21, 16000],
	[&"arcology_stockgrowers", "Stockgrowers", 3, 3, 21, 30000],
	[&"arcology_fremont", "Fremont Palace", 3, 3, 21, 45000],

]
const LEGACY_TOOLS := {
	0: ["Inspect", 0, -1, -1, Vector2i.ONE, &"query", 0, 0],
	1: ["Bulldoze", 1, -1, -1, Vector2i.ONE, &"bulldoze", 1, 1],
	2: ["Remove zone", 1, -1, 0, Vector2i.ONE, &"dezone", 2, 1],
	3: ["Sign", 0, -1, -1, Vector2i.ONE, &"sign", 0, 0],
	4: ["Road", 10, -1, -1, Vector2i.ONE, &"road", 1, 2],
	5: ["Highway", 100, -1, -1, Vector2i(2, 2), &"highway", 3, 2],
	6: ["Highway Ramp", 25, -1, -1, Vector2i.ONE, &"onramp", 0, 2],
	7: ["Tunnel", 150, -1, -1, Vector2i.ONE, &"tunnel", 0, 2],
	8: ["Rail", 25, -1, -1, Vector2i.ONE, &"rail", 1, 2],
	9: ["Subway", 100, -1, -1, Vector2i.ONE, &"subway", 1, 2],
	10: ["Subway Portal", 500, -1, -1, Vector2i.ONE, &"subway_portal", 0, 2],
	11: ["Power Line", 2, -1, -1, Vector2i.ONE, &"power_line", 1, 3],
	12: ["Water Pipe", 3, -1, -1, Vector2i.ONE, &"water_pipe", 1, 3],
	13: ["Light Residential", 5, -1, 1, Vector2i.ONE, &"zone_res_low", 2, 4],
	14: ["Dense Residential", 10, -1, 2, Vector2i.ONE, &"zone_res_high", 2, 4],
	15: ["Light Commercial", 5, -1, 3, Vector2i.ONE, &"zone_com_low", 2, 4],
	16: ["Dense Commercial", 10, -1, 4, Vector2i.ONE, &"zone_com_high", 2, 4],
	17: ["Light Industrial", 5, -1, 5, Vector2i.ONE, &"zone_ind_low", 2, 4],
	18: ["Dense Industrial", 10, -1, 6, Vector2i.ONE, &"zone_ind_high", 2, 4],
	19: ["Airport", 250, -1, 8, Vector2i.ONE, &"airport", 2, 7],
	20: ["Seaport", 150, -1, 9, Vector2i.ONE, &"seaport", 2, 7],
	21: ["Trees", 3, 6, -1, Vector2i.ONE, &"trees", 1, 5],
	22: ["Pocket Park", 10, 13, -1, Vector2i.ONE, &"small_park", 0, 5],
	23: ["City Park", 150, 213, -1, Vector2i(3, 3), &"large_park", 0, 5],
	24: ["Water Pump", 100, 220, -1, Vector2i.ONE, &"water_pump", 0, 3],
	25: ["Water Tower", 250, 235, -1, Vector2i(2, 2), &"water_tower", 0, 3],
	26: ["Water Treatment Plant", 500, 244, -1, Vector2i(2, 2), &"water_treatment", 0, 3],
	27: ["Desalination Plant", 1000, 250, -1, Vector2i(3, 3), &"desalination", 0, 3],
	28: ["Police Station", 500, 210, -1, Vector2i(3, 3), &"police", 0, 6],
	29: ["Fire Station", 500, 211, -1, Vector2i(3, 3), &"fire", 0, 6],
	30: ["Hospital", 500, 209, -1, Vector2i(3, 3), &"hospital", 0, 6],
	31: ["School", 250, 214, -1, Vector2i(3, 3), &"school", 0, 6],
	32: ["College", 1000, 217, -1, Vector2i(4, 4), &"college", 0, 6],
	33: ["Library", 500, 245, -1, Vector2i(2, 2), &"library", 0, 6],
	34: ["Museum", 100, 212, -1, Vector2i(3, 3), &"museum", 0, 6],
	35: ["Stadium", 3000, 215, -1, Vector2i(4, 4), &"stadium", 0, 6],
	36: ["Marina", 1000, 248, -1, Vector2i(3, 3), &"marina", 0, 6],
	37: ["Zoo", 3000, 218, -1, Vector2i(4, 4), &"zoo", 0, 6],
	38: ["Prison", 3000, 216, -1, Vector2i(4, 4), &"prison", 0, 6],
	39: ["Bus Depot", 250, 236, -1, Vector2i(2, 2), &"bus_depot", 0, 7],
	40: ["Rail Station", 500, 237, -1, Vector2i(2, 2), &"rail_station", 0, 7],
	41: ["Subway Station", 250, 233, -1, Vector2i.ONE, &"subway_station", 0, 7],
	42: ["Coal Power Plant", 4000, 207, -1, Vector2i(4, 4), &"coal_plant", 0, 8],
	43: ["Hydroelectric Dam", 400, 198, -1, Vector2i.ONE, &"hydro_plant", 0, 8],
	44: ["Wind Turbine", 100, 200, -1, Vector2i.ONE, &"wind_plant", 0, 8],
	45: ["Gas Power Plant", 2000, 201, -1, Vector2i(4, 4), &"gas_plant", 0, 8],
	46: ["Oil Power Plant", 6600, 202, -1, Vector2i(4, 4), &"oil_plant", 0, 8],
	47: ["Nuclear Power Plant", 15000, 203, -1, Vector2i(4, 4), &"nuclear_plant", 0, 8],
	48: ["Solar Farm", 1300, 204, -1, Vector2i(4, 4), &"solar_plant", 0, 8],
	49: ["Microwave Receiver", 28000, 205, -1, Vector2i(4, 4), &"microwave_plant", 0, 8],
	50: ["Fusion Power Plant", 40000, 206, -1, Vector2i(4, 4), &"fusion_plant", 0, 8],
	51: ["Comstock Grand", 100000, 251, -1, Vector2i(4, 4), &"arcology_comstock", 0, 9],
	52: ["Silver Junction", 120000, 252, -1, Vector2i(4, 4), &"arcology_junction", 0, 9],
	53: ["Boulder Crown", 150000, 253, -1, Vector2i(4, 4), &"arcology_boulder", 0, 9],
	71: ["The Fix", 320000, 256, -1, Vector2i(4, 4), &"arcology_fix", 0, 9],
	72: ["Six-Week Alibi", 140000, 257, -1, Vector2i(4, 4), &"arcology_alibi", 0, 9],
	73: ["Velvet Wardrobe", 220000, 258, -1, Vector2i(4, 4), &"arcology_velvet", 0, 9],
	74: ["The Afterglow", 500000, 259, -1, Vector2i(4, 4), &"arcology_afterglow", 0, 9],
	75: ["Last Resort", 60000, 260, -1, Vector2i(4, 4), &"arcology_last", 0, 9],
	76: ["Dust Republic", 95000, 261, -1, Vector2i(4, 4), &"arcology_dust", 0, 9],
	77: ["Boddy's", 8000, 262, -1, Vector2i(2, 2), &"arcology_boddy", 0, 9],
	78: ["Woolier Days", 16000, 263, -1, Vector2i(2, 2), &"arcology_woolier", 0, 9],
	79: ["Stockgrowers", 30000, 264, -1, Vector2i(3, 3), &"arcology_stockgrowers", 0, 9],
	80: ["Fremont Palace", 45000, 265, -1, Vector2i(3, 3), &"arcology_fremont", 0, 9],
	54: ["Desert Orbit", 200000, 254, -1, Vector2i(4, 4), &"arcology_orbit", 0, 9],
	55: ["Mayor's Residence", 0, 243, -1, Vector2i(2, 2), &"reward_mayors_residence", 0, 10],
	56: ["City Hall", 0, 208, -1, Vector2i(3, 3), &"reward_city_hall", 0, 10],
	57: ["Monument", 0, 219, -1, Vector2i.ONE, &"reward_monument", 0, 10],
	58: ["Military Base", 0, -1, 7, Vector2i.ONE, &"reward_military_base", 2, 10],
	59: ["Neon Dome", 0, 255, -1, Vector2i(4, 4), &"reward_neon_dome", 0, 10],
	60: ["Dispatch Firefighters", 0, -1, -1, Vector2i.ONE, &"dispatch_fire", 0, 11],
	61: ["Dispatch Police", 0, -1, -1, Vector2i.ONE, &"dispatch_police", 0, 11],
	62: ["Dispatch Military", 0, -1, -1, Vector2i.ONE, &"dispatch_military", 0, 11],
	63: ["Raise Land", 25, -1, -1, Vector2i.ONE, &"raise_land", 0, 12],
	64: ["Lower Land", 25, -1, -1, Vector2i.ONE, &"lower_land", 0, 12],
	65: ["Level Land", 25, -1, -1, Vector2i.ONE, &"level_land", 2, 12],
	66: ["Water", 100, -1, -1, Vector2i.ONE, &"place_water", 0, 12],
	70: ["Tree", 3, 6, -1, Vector2i.ONE, &"plant_tree", 0, 12],
	67: ["Forest", 3, 6, -1, Vector2i.ONE, &"forest", 2, 12],
	68: ["Raise Sea Level", 25, -1, -1, Vector2i.ONE, &"raise_sea", 4, 12],
	69: ["Lower Sea Level", 25, -1, -1, Vector2i.ONE, &"lower_sea", 4, 12],
}

func test_ids_are_append_only() -> void:
	var building_script: Script = load("res://scripts/core/buildings.gd")
	var zone_script: Script = load("res://scripts/core/zones.gd")
	for key in LEGACY_BUILDING_CONSTANTS:
		check_eq(building_script.get_script_constant_map()[key], LEGACY_BUILDING_CONSTANTS[key], key)
	for key in LEGACY_CATEGORIES:
		check_eq(Buildings.Category[key], LEGACY_CATEGORIES[key], key)
	for key in LEGACY_TOOL_KINDS:
		check_eq(Tools.Kind[key], LEGACY_TOOL_KINDS[key], key)
	for key in LEGACY_ZONES:
		check_eq(zone_script.get_script_constant_map()[key], LEGACY_ZONES[key], key)
	for id in LEGACY_ROSTER.size():
		var r: Array = LEGACY_ROSTER[id]
		check_eq([Buildings.key(id), Buildings.display_name(id), Buildings.size(id).x,
			Buildings.size(id).y, Buildings.category(id), Buildings.cost(id)], r, str(id))
	for id in LEGACY_TOOLS:
		var r: Array = LEGACY_TOOLS[id]
		check_eq([Tools.display_name(id), Tools.cost(id), Tools.building_id(id),
			Tools.zone_kind(id), Tools.footprint(id), Tools.icon(id), Tools.mode(id),
			Tools.group(id)], r, str(id))
	check_eq(Zones.AGR_LOW, 10)
	check_eq(Zones.AGR_HIGH, 11)
	check_eq(Buildings.Category.AGRICULTURAL, 22)
	check_eq(Buildings.id_of(&"ag_vegetables"), 266)
	check_eq(Buildings.COUNT, 282)
	check_eq(Tools.Kind.ZONE_AGR_LOW, 81)
	check_eq(Tools.Kind.ZONE_AGR_HIGH, 82)


func test_agricultural_tools_charge_2_and_5() -> void:
	var c := flat_city(100)
	var b := Builder.new(c, CityStats.new())
	for row in [[Tools.Kind.ZONE_AGR_LOW, 10, 2], [Tools.Kind.ZONE_AGR_HIGH, 11, 5]]:
		var tool: int = row[0]
		check(Tools.is_available(tool, c, b.stats), "available at founding")
		var p := b.preview(tool, Vector2i(20, 20), Vector2i(21, 21))
		check(p.ok, p.reason)
		check_eq(p.cost, row[2] * 4)
		var r := b.apply(tool, Vector2i(20, 20), Vector2i(21, 21))
		check(r.applied)
		check_eq(c.zone_kind_at(21, 21), row[1])
		check(not b.preview(tool, Vector2i(20, 20), Vector2i(21, 21)).ok,
			"same-density repaint is free and makes no edit")
	check_eq(c.funds, 72)


func test_density_and_corner_bits() -> void:
	check_eq(Zones.kind(Zones.make(Zones.AGR_HIGH, Zones.CORNER_NW)), 11)
	check_eq(Zones.corners(Zones.make(Zones.AGR_HIGH, Zones.CORNER_NW)), 16)
	check(Zones.is_agricultural(10))
	check(Zones.is_agricultural(11))
	check(not Zones.is_agricultural(6))
	check(not Zones.is_dense(Zones.AGR_LOW))
	check(Zones.is_dense(Zones.AGR_HIGH))
	for kind in [10, 11]:
		check(not Zones.is_residential(kind), "agriculture is not residential")
		check(not Zones.is_commercial(kind), "agriculture is not commercial")
		check(not Zones.is_industrial(kind), "agriculture is not industrial")
		check_eq(ZoneParams.family_of(kind), -1, "RCI remains three families")
		check(not Zones.is_growth_zone(kind), "old growth helper is RCI-only")
	check(Zones.is_industrial(Zones.IND_LOW))
	check(Zones.is_industrial(Zones.IND_HIGH))
	check_eq(ZoneParams.family_of(6), 2)
	check_eq(Zones.COLORS[10], Color("b7c985"))
	check_eq(Zones.COLORS[11], Color("71884a"))


func test_roster_has_ten_archetypes_and_six_state_ids() -> void:
	var keys := [&"vegetables", &"alfalfa", &"grain", &"cattle_range", &"sheep_pasture",
		&"greenhouse", &"nursery", &"dairy", &"feedlot", &"market_garden"]
	var sizes := [1, 2, 2, 3, 3, 1, 2, 3, 3, 2]
	var jobs := [4, 6, 4, 6, 5, 10, 24, 40, 32, 24]
	var water := [3, 3, 1, 1, 1, 2, 2, 3, 2, 3]
	var power := [0, 0, 0, 0, 0, 2, 1, 1, 1, 1]
	var pollution := [1, 1, 1, 0, 0, 0, 0, 4, 6, 1]
	var livestock := [0, 0, 0, 8, 10, 0, 0, 8, 12, 0]
	check_eq(AgricultureParams.archetypes(false), keys.slice(0, 5))
	check_eq(AgricultureParams.archetypes(true), keys.slice(5))
	for i in keys.size():
		var id := AgricultureParams.building_id(keys[i])
		check_eq(id, 266 + i)
		check_eq(Buildings.key(id), StringName("ag_" + String(keys[i])))
		check_eq(AgricultureParams.archetype_for_id(id), keys[i])
		check_eq(Buildings.size(id), Vector2i(sizes[i], sizes[i]))
		check_eq(AgricultureParams.jobs_of(id), jobs[i])
		check_eq(AgricultureParams.assessment_of(id), jobs[i] * 100)
		check_eq(AgricultureParams.water_load(id), water[i], "per tile")
		check_eq(AgricultureParams.power_load(id), power[i], "per tile")
		check_eq(AgricultureParams.pollution_of(id), pollution[i])
		check_eq(AgricultureParams.ROSTER[keys[i]][4], livestock[i])
		check_eq(Buildings.category(id), Buildings.Category.AGRICULTURAL)
		check(not Buildings.is_zone_building(id), "RCI-only building helper")
		check_eq(ZoneParams.jobs_of(id), 0, "no accidental RCI industrial units")
		check(Buildings.is_developed(id))
	for state in [&"prepared", &"dormant"]:
		for side in range(1, 4):
			var id := AgricultureParams.state_id(state, side)
			check_eq(Buildings.key(id), StringName("ag_%s_%dx%d" % [state, side, side]))
			check_eq(Buildings.size(id), Vector2i(side, side))
			check(Buildings.is_developed(id))
			check(Buildings.carries_power(id), "state footprints conduct utilities")
			check_eq(AgricultureParams.archetype_for_id(id), &"")
			check_eq(AgricultureParams.jobs_of(id), 0)
			check_eq(AgricultureParams.assessment_of(id), 0)
			check_eq(AgricultureParams.water_load(id), 0)
			check_eq(AgricultureParams.power_load(id), 0)
			check_eq(AgricultureParams.pollution_of(id), 0)
	check_eq(AgricultureParams.archetype_for_id(265), &"")
	check_eq(AgricultureParams.building_id(&"missing"), Buildings.NONE)
	check_eq(AgricultureParams.state_id(&"active", 1), Buildings.NONE)
	check_eq(AgricultureParams.state_id(&"prepared", 4), Buildings.NONE)


func test_old_stats_default_tax_to_7() -> void:
	var s := CityStats.new()
	s.from_dict({"demand": [12, 34, 56], "tax_industrial": 9})
	check_eq(s.tax_agricultural, 7)
	check_eq(s.demand, Vector3i(12, 34, 56))
	check_eq(s.demand_agricultural, 0)
	check_eq(s.agricultural_jobs, 0)
	check_eq(s.agricultural_lots, 0)
	s.tax_agricultural = 13
	s.demand_agricultural = 419
	s.agricultural_jobs = 24
	s.agricultural_lots = 2
	var twin := CityStats.new()
	twin.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(twin.tax_agricultural, 13)
	check_eq(twin.demand_agricultural, 419)
	check_eq(twin.agricultural_jobs, 24)
	check_eq(twin.agricultural_lots, 2)
	check_eq(twin.demand, Vector3i(12, 34, 56))


func test_occupied_agriculture_keeps_whole_footprint_until_demolition() -> void:
	var c := flat_city()
	var id := AgricultureParams.building_id(&"alfalfa")
	c.stamp_building(20, 20, id, Zones.AGR_LOW)
	c.underground.put(21, 21, NetworkShapes.PIPE_FIRST)
	var b := Builder.new(c, CityStats.new())
	for tool in [Tools.Kind.ZONE_AGR_HIGH, Tools.Kind.ZONE_RES_LOW, Tools.Kind.DEZONE]:
		check(not b.preview(tool, Vector2i(21, 21)).ok, "occupied tile cannot partially rezone")
	check_eq(c.anchor_of(21, 21), Vector2i(20, 20))
	var result := b.apply(Tools.Kind.BULLDOZE, Vector2i(21, 21))
	check(result.applied)
	check_eq(result.tiles.size(), 4)
	for y in range(20, 22):
		for x in range(20, 22):
			check(Buildings.is_rubble(c.building_at(x, y)))
			check_eq(c.zone_kind_at(x, y), 10)
	check(NetworkShapes.underground_in_family(c.underground.at(21, 21),
		NetworkShapes.Family.PIPE), "pipe survives demolition; its connection shape may refresh")
