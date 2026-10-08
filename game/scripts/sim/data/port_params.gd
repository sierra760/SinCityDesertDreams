# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for airport, seaport and military-base development and the
## vehicles they send out.
##
## See docs/simulation/ports.md for the rules these tune.
class_name PortParams
extends RefCounted

## One in this many visited port tiles tries to develop each month.
const DEVELOP_CHANCE_DENOMINATOR := 30

## Tiles per runway and pier tiles beyond a crane.
const RUNWAY_LENGTH := 5
const PIER_LENGTH := 4
## Water height above ground required at the berth beyond the pier.
const MIN_BERTH_DEPTH := 2

## Smallest zones that can operate.
const AIRPORT_MIN_TILES := 20
const SEAPORT_MIN_TILES := 4

## Demand added each month by operating ports: a flat amount per port plus an
## amount per developed tile, capped per demand component. The zone system adds
## it to the month's demand change, beside a tax point's 25 to 50.
const AIRPORT_COMMERCIAL_BONUS := 40
const SEAPORT_INDUSTRIAL_BONUS := 40
const BONUS_PER_DEVELOPED_TILE := 1
const DEMAND_BONUS_CAP := 100

## Jobs, pollution and crime per developed tile, keyed by zone kind. The
## environment system adds the pollution to each port or military piece's
## emission and the crime to its block's base crime.
const JOBS_PER_TILE: Dictionary = {Zones.AIRPORT: 10, Zones.SEAPORT: 12, Zones.MILITARY: 8}
const POLLUTION_PER_TILE: Dictionary = {Zones.AIRPORT: 8, Zones.SEAPORT: 6, Zones.MILITARY: 4}
const CRIME_PER_TILE: Dictionary = {Zones.AIRPORT: 0, Zones.SEAPORT: 2, Zones.MILITARY: 6}

## Planes: how many may fly at once, spawn odds per operating airport per day,
## tiles per day, days spent climbing and cruising, cruise altitude, odds of a
## heading change per cruising day and how far ahead obstacles are noticed.
## A plane reaching the map edge turns back toward the city centre.
const MAX_PLANES := 2
const PLANE_SPAWN_DENOMINATOR := 12
const PLANE_SPEED := 3
const PLANE_CLIMB_DAYS := 4
const PLANE_CRUISE_DAYS := 12
const PLANE_CRUISE_ALTITUDE := 8
const PLANE_TURN_DENOMINATOR := 5
const AIR_LOOKAHEAD := 3

## Helicopter: spawn odds per operating airport per day, tiles per day and how
## far from the city centre it roams.
const HELICOPTER_SPAWN_DENOMINATOR := 20
const HELICOPTER_SPEED := 2
const HELICOPTER_RANGE := 32

## Ships: spawn odds per operating seaport per day, tiles per day and days
## spent at the berth.
const SHIP_SPAWN_DENOMINATOR := 15
const SHIP_SPEED := 1
const SHIP_DOCK_DAYS := 6
