# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Everything a system needs for one call.
class_name SimContext
extends RefCounted

var city: City
var stats: CityStats
var rng: SimRng
var clock: GameClock
var events: CityEvents
## Set by the Simulation before each call so systems can look each other up.
var systems: Dictionary = {}


func system(key: StringName) -> SimSystem:
	return systems.get(key, null)


func year() -> int:
	return clock.year()


func month() -> int:
	return clock.month()
