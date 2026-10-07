# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Per-building lookup tables shared by the monthly scans. They depend only on
## the building roster; city layers are still read fresh on every pass.
extends RefCounted

static var _categories := PackedByteArray()

static func categories() -> PackedByteArray:
	if _categories.is_empty():
		_categories.resize(Buildings.COUNT)
		for id: int in Buildings.COUNT:
			_categories[id] = Buildings.category(id)
	return _categories


static var _fallback_capacity := PackedInt32Array()
static var _zone_capacity := PackedInt32Array()

## The built-in zone system uses a residential capacity taken from the building
## roster. Other zone systems are queried per lot through PopulationParams.
static func capacities(use_native_zones: bool) -> PackedInt32Array:
	if _fallback_capacity.is_empty():
		_fallback_capacity.resize(Buildings.COUNT)
		_zone_capacity.resize(Buildings.COUNT)
		for id: int in Buildings.COUNT:
			_fallback_capacity[id] = PopulationParams.lot_capacity(id)
			var capacity := ZoneParams.population_of(id)
			_zone_capacity[id] = capacity if capacity > 0 else _fallback_capacity[id]
	return _zone_capacity if use_native_zones else _fallback_capacity
