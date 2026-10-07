# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_scattered_growth_retains_lots_outside_actual_dependency_reach() -> void:
	var city := flat_city()
	for y: int in range(8,128,16):
		for x: int in range(8,128,16):
			city.stamp_building(x,y,112)
			city.stamp_building(x+6,y,112)
	city.stamp_building(0,0,112)
	var view := CityView3D.new()
	view.city = city
	view._geometry_state = view._geometry_inputs(city)
	var changed: Array[Rect2i] = [Rect2i(0,0,1,1)]
	for y: int in range(8,128,16):
		for x: int in range(8,128,16):
			city.building.put(x,y,113)
			changed.append(Rect2i(x,y,1,1))
	city.building.put(0,0,113)
	var terrain := view._changed_regions(false)
	check_eq(terrain.size(),64,"terrain retains conservative chunk invalidation")
	for record: Dictionary in CityBuildings3D.collect(city):
		check_eq(CityBuildings3D._touches(record.footprint,view._lot_regions),CityBuildings3D._touches(record.footprint,changed),"large edit admission preserves exact lot dependency reach "+str(record.anchor))
	view.free()

func test_coalesced_cells_preserve_holes_gaps_and_vertex_borders() -> void:
	for pattern: int in range(12):
		var cells: Dictionary = {}
		for y: int in range(-1,130):
			for x: int in range(-1,130):
				if (x*17+y*31+pattern*7)%23 < pattern or x==128 and y%7==0:
					cells[Vector2i(x,y)] = true
		var covered: Dictionary = {}
		for region: Rect2i in CityView3D._coalesced_lot_cells(cells):
			for y: int in range(region.position.y,region.end.y):
				for x: int in range(region.position.x,region.end.x):
					var cell := Vector2i(x,y)
					check(not covered.has(cell),"coalesced rectangles never overlap")
					covered[cell] = true
		check_eq(covered,cells,"coalescing preserves exact changed cells including border vertices")

func test_contiguous_growth_coalesces_without_adding_clean_cells() -> void:
	var city := flat_city()
	var view := CityView3D.new()
	view.city = city
	view._geometry_state = view._geometry_inputs(city)
	for y: int in range(30,40):
		for x: int in range(40,50): city.building.put(x,y,112)
	view._changed_regions(false)
	check_eq(view._lot_regions,[Rect2i(40,30,10,10)],"a solid edit is one exact rectangle")
	view.free()
