# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Incremental minimap repaints equal a complete regeneration in every orientation.
extends "res://tests/test_case.gd"
class FixedRotationMap extends MiniMap:
	var fixed_rotation := 0
	func display_rotation() -> int: return fixed_rotation
func test_incremental_repaints_match_full_regeneration() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Lawndale.sc2")
	check(loaded.ok, "Lawndale imports")
	var city: City = loaded.city
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for rotation: int in 4:
		var live := FixedRotationMap.new()
		live.fixed_rotation = rotation
		live.city = city
		live.generate_image()
		var changed := 0
		for step: int in 6:
			for edit: int in 25:
				var x := rng.randi_range(0, City.WIDTH - 1)
				var y := rng.randi_range(0, City.HEIGHT - 1)
				match edit % 5:
					0: city.building.put(x, y, Buildings.RES_1X1_FIRST + rng.randi_range(0, 7))
					1: city.building.put(x, y, Buildings.NONE)
					2: city.zone.put(x, y, Zones.make(rng.randi_range(0, 6)))
					3: city.building.put(x, y, Buildings.ROAD_FIRST)
					4: city.terrain.put(x, y, 0x20 if step % 2 == 0 else 0)
				changed += 1
			if step == 3: city.flood_overlay[Vector2i(10 + rotation, 20)] = 1
			if step == 5: city.flood_overlay.erase(Vector2i(10 + rotation, 20))
			live.generate_image()
			var fresh := FixedRotationMap.new()
			fresh.fixed_rotation = rotation
			fresh.city = city
			fresh.generate_image()
			check(live.get_image().get_data() == fresh.get_image().get_data(), "rotation %d step %d: repainted tiles equal a full regeneration" % [rotation, step])
			fresh.free()
		live.free()
