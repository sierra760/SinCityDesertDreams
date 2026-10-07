# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the environment system (pollution, land value, crime).
## See docs/simulation/environment.md for the rules these tune.
class_name EnvironmentParams
extends RefCounted

# ── Pollution emission per tile ──────────────────────────────────────────
## Industrial emission per tile, keyed by footprint width (1, 2 or 3 tiles).
const INDUSTRIAL_EMISSION := {1: 6, 2: 14, 3: 24}
## Commercial emission per tile by footprint width; corner stores emit nothing.
const COMMERCIAL_EMISSION := {1: 0, 2: 3, 3: 5}
## Power plant emission per tile by building key. Plants not listed emit nothing.
const PLANT_EMISSION := {
	&"plant_coal": 50, &"plant_oil": 25, &"plant_gas": 10,
	&"plant_nuclear": 2, &"plant_fusion": 2,
}
## Flat per-tile emission for whole categories.
const CATEGORY_EMISSION := {
	Buildings.Category.PORT: 6, Buildings.Category.MILITARY: 4,
	Buildings.Category.ARCOLOGY: 15, Buildings.Category.TRANSIT: 4,
}
## Named civic and utility emitters that are otherwise clean categories.
const SPECIAL_EMISSION := {
	&"prison": 10, &"stadium": 4, &"water_pump": 2, &"water_treatment": 10,
}
## Emission of one contaminated ground tile.
const CONTAMINATION_EMISSION := 200
## Traffic map value divided by this is added to each block.
const TRAFFIC_POLLUTION_DIVISOR := 5
## Percent of industrial emission removed by the pollution controls ordinance.
const POLLUTION_CONTROLS_PERCENT := 25
## Pollution removed per tree tile and per park tile each month.
const TREE_ABSORPTION := 4
const PARK_ABSORPTION := 6

# ── Diffusion ────────────────────────────────────────────────────────────
## Base divisor of the weighted neighbour average; larger means faster decay.
const DIFFUSION_DIVISOR := 4
## Extra divisor per powered water treatment plant in reach, and its cap.
const TREATMENT_DIVISOR_BONUS := 1
const TREATMENT_MAX_BONUS := 3
## Reach of a treatment plant in blocks (Manhattan distance).
const TREATMENT_RADIUS := 8

# ── Land value amenity score per tile ────────────────────────────────────
const AMENITY_WATER := 12         ## open water tile
const AMENITY_OPEN_GROUND := 4    ## empty dry ground
const AMENITY_TREE := 20          ## tree tile
const AMENITY_PARK := 20          ## pocket park tile
const AMENITY_LARGE_PARK := 40    ## city park tile
const AMENITY_CIVIC := 20         ## library, museum, marina, zoo, city hall, monument, residence
const AMENITY_RUBBLE := -20       ## rubble or contamination tile
const AMENITY_WATERED := 4        ## tile with water service
const AMENITY_SLOPE := 12         ## sloped dry ground
## Height above sea level counts one point per this many levels, up to the cap.
const ALTITUDE_DIVISOR := 8
const ALTITUDE_CAP := 16

# ── Land value zone terms ────────────────────────────────────────────────
## Distance in blocks at which the city-centre bonus fades to nothing.
const CENTRE_REACH := 64
const INDUSTRIAL_DENSE_BONUS := 21
## Residential blocks below this density get the quiet-neighbourhood bonus.
const QUIET_DENSITY := 64
const QUIET_BONUS := 21
const IND_POLLUTION_DIVISOR := 16
const IND_CRIME_DIVISOR := 4
const COM_POLLUTION_DIVISOR := 4
const COM_CRIME_DIVISOR := 3
const COM_DENSITY_DIVISOR := 3
const RES_POLLUTION_DIVISOR := 5
const RES_CRIME_DIVISOR := 3
const RES_TRAFFIC_DIVISOR := 8

# ── Crime ────────────────────────────────────────────────────────────────
## Police coverage divided by this is subtracted from a block's crime.
const POLICE_CRIME_DIVISOR := 2
## Land value divided by this is subtracted from a block's crime.
const VALUE_CRIME_DIVISOR := 4
## Crime added to every developed block under legalized gambling.
const GAMBLING_CRIME := 16
## Crime removed from every developed block under the neighborhood watch.
const WATCH_CRIME_RELIEF := 8

# ── News thresholds ──────────────────────────────────────────────────────
const POLLUTION_ALERT_LEVEL := 100
const CRIME_WAVE_LEVEL := 80
