# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_imported_underground_codes_map_to_connection_masks() -> void:
	# Expected masks are written out so the test shares no table with the
	# renderer's art order or the importer.
	var masks: Array[int] = [5,10,10,5,10,5,3,6,12,9,11,7,14,13,15]
	for i: int in 15:
		check_eq(Sc2Import.map_underground(i+1),15+masks[i],"imported subway shape %d"%(i+1))
		check_eq(Sc2Import.map_underground(i+16),masks[i],"imported pipe shape %d"%(i+16))
	check_eq(Sc2Import.map_underground(31),Underground.PIPE_EW_UNDER_SUBWAY_NS)
	check_eq(Sc2Import.map_underground(32),Underground.PIPE_NS_UNDER_SUBWAY_EW)
	check_eq(Sc2Import.map_underground(34),Underground.STATION_LINK,"subway transition is not a pipe crossing")
	check_eq(Sc2Import.map_underground(35),Underground.STATION_LINK)
	check_eq(Sc2Import.map_underground(33),Underground.NONE,"water display tile does not create a subway crossing")
	check_eq(Underground.from_art_code(1),25,"art-code mapping is separate from import codes")

func test_imported_rectangular_subway_is_reciprocal() -> void:
	var city := flat_city()
	# Imported subway codes: corners NE7, SE8, SW9, NW10; straights NS1 and EW2.
	var cells := {Vector2i(10,10):8,Vector2i(11,10):2,Vector2i(12,10):9,Vector2i(12,11):1,Vector2i(12,12):10,Vector2i(11,12):2,Vector2i(10,12):7,Vector2i(10,11):1}
	for cell: Vector2i in cells: city.underground.putv(cell,Sc2Import.map_underground(cells[cell]))
	for cell: Vector2i in cells:
		var mask := NetworkShapes.underground_mask(city.underground.atv(cell),NetworkShapes.Family.SUBWAY)
		var count := 0
		for d: int in 4:
			if not mask & (1<<d): continue
			var neighbor := cell+NetworkShapes.DIRECTIONS[d]
			var other := NetworkShapes.underground_mask(city.underground.atv(neighbor),NetworkShapes.Family.SUBWAY)
			check(other & (1<<((d+2)%4)) != 0,"each literal source edge has its reciprocal neighbor")
			count += 1
		check_eq(count,2)

func test_portal_chooses_reciprocal_surface_rail_over_code_label() -> void:
	for direction: int in 4:
		var city := flat_city()
		var cell := Vector2i(20,20)
		city.building.putv(cell,Buildings.SUBWAY_PORTAL_FIRST+((direction+3)%4))
		var outward: Vector2i = NetworkShapes.DIRECTIONS[direction]
		city.building.putv(cell+outward,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5 if direction%2==0 else 10))
		city.underground.putv(cell,Underground.STATION_LINK)
		city.underground.putv(cell-outward,Underground.subway_code(5 if direction%2==0 else 10))
		var profile := CityPortal3D.profile(city,cell,CityGeometry3D.HEIGHT)
		check_eq(profile.inward,-Vector2(outward),"mouth faces the connected approach")

func test_bounds_and_portal_fallback_do_not_invent_connections() -> void:
	for code: int in [-1,0,36,255,256]: check_eq(Sc2Import.map_underground(code),Underground.NONE)
	var city := flat_city()
	var cell := Vector2i(0,0)
	city.building.putv(cell,Buildings.SUBWAY_PORTAL_FIRST+1)
	city.building.put(1,0,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	city.underground.put(0,1,Underground.subway_code(10))
	var profile := CityPortal3D.profile(city,cell,CityGeometry3D.HEIGHT)
	check_eq(profile.inward,Vector2.LEFT,"isolated native portal retains code fallback")
	check(profile.subway_cells.is_empty(),"perpendicular subway neighbor does not connect")
	city.building.put(1,0,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	city.underground.put(0,1,Underground.subway_code(5))
	profile=CityPortal3D.profile(city,cell,CityGeometry3D.HEIGHT)
	check_eq(profile.rail_cell,Vector2i(1,0))
	check_eq(profile.subway_cells,[Vector2i(0,1)],"portal supports a reciprocal underground elbow")
	var snapshot := hash([city.building.data,city.flags.data,city.underground.data,city.terrain.data,city.altitude.data])
	CityPortal3D.profile(city,cell,CityGeometry3D.HEIGHT)
	check_eq(hash([city.building.data,city.flags.data,city.underground.data,city.terrain.data,city.altitude.data]),snapshot,"profile only reads city")
