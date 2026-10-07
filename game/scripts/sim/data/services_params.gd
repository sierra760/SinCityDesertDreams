# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the services system (coverage, prisons, facilities).
## See docs/simulation/services.md for the rules these tune.
class_name ServicesParams
extends RefCounted

# ── Coverage ─────────────────────────────────────────────────────────────
## Strength multipliers: funding × effect / 2, so 250 at full funding.
const POLICE_BASE_EFFECT := 5
const FIRE_BASE_EFFECT := 5
## Percent of station strength stamped on each ring outward from the centre.
const RING_PERCENT: Array[int] = [100, 80, 60, 40, 20]
## Rings beyond the centre reached at full funding.
const MAX_RING := 3
## Divisor applied to an unpowered station's strength.
const UNPOWERED_DIVISOR := 2
## Fire cover added to every cell while the volunteer fire ordinance is on.
const VOLUNTEER_FIRE_COVERAGE := 8

# ── Prisons ──────────────────────────────────────────────────────────────
## Guards on staff per point of police funding (300 at 100 percent).
const GUARDS_PER_FUNDING_POINT := 3
## Skeleton staff kept when funding is cut.
const MIN_GUARDS := 30
## Inmates one guard can hold before the prison is full.
const INMATES_PER_GUARD := 33
## Crime map total that yields one arrest per month.
const CRIME_PER_ARREST := 500
## Share of inmates released each month (one part in this many).
const RELEASE_DIVISOR := 48
## Hard cap on inmates held by one prison.
const MAX_INMATES := 10000
## Utilization percent above which inmates start escaping.
const ESCAPE_UTILIZATION := 90
## Mean utilization at which prisons stop helping police coverage.
const STRAINED_UTILIZATION := 80
## Crime added to blocks near a prison during an escape, and the reach.
const ESCAPE_CRIME_BUMP := 32
const ESCAPE_CRIME_RADIUS := 6
