# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared direct-system fixture; host integration tests use Builder separately.
extends RefCounted

const TestCase := preload("res://tests/test_case.gd")


static func road_access(city: City, rect: Rect2i) -> void:
	var y := rect.position.y - 1
	if y < 0:
		y = rect.end.y
	for x in range(rect.position.x, rect.end.x):
		if city.in_bounds(x, y):
			city.building.put(x, y, Buildings.ROAD_FIRST)


static func zone(city: City, rect: Rect2i, kind: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			city.zone.put(x, y, Zones.make(kind))


static func context(city: City) -> SimContext:
	return TestCase.make_context(city)
