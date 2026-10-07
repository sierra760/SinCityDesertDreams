# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

class CountedGrid extends Grid8:
	var reads := 0
	func at(x: int, y: int) -> int:
		reads += 1
		return super.at(x,y)

class LotProjection extends CityBuildings3D:
	var added: Array[Dictionary] = []
	func _add_record(_city: City, _catalog: CityModelCatalog, record: Dictionary) -> void:
		added.append(record)

func _expected(city: City, regions: Array[Rect2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in CityBuildings3D.collect(city):
		if CityBuildings3D._touches(record.footprint,regions): result.append(record)
	return result

func test_small_edit_does_not_scan_distant_lots() -> void:
	var city := flat_city()
	var counted := CountedGrid.new()
	city.building = counted
	for y: int in range(0,128,3):
		for x: int in range(0,128,3): city.building.put(x,y,112)
	var regions: Array[Rect2i] = [Rect2i(63,63,1,1)]
	var expected := _expected(city,regions)
	counted.reads = 0
	var projection := LotProjection.new()
	projection.update_regions(city,null,regions)
	check_eq(projection.added,expected,"same local lots and ordering")
	check(counted.reads < 2000,"one-cell change performs bounded local discovery; reads="+str(counted.reads))
	projection.free()

func test_regional_discovery_matches_full_scan_for_every_included_city() -> void:
	for name: String in ["La Presa","Foothills Ranch","Aliso Niguel","Oro Canyon","Valle del Mar","Lawndale","Salton Shores","Grant Pass - Soledad"]:
		var path := "res://assets/cities/"+name+".sc2"
		check(FileAccess.file_exists(path),"included city exists "+name)
		var imported := Sc2Import.load(path)
		check(imported.ok,"city import "+name)
		if not imported.ok: continue
		var city: City = imported.city
		var original := SaveFormat.encode_city(city)
		for values: Array in [[Rect2i(0,0,1,1)],[Rect2i(126,126,2,2)],[Rect2i(63,63,1,1),Rect2i(64,62,3,3)],[Rect2i(20,30,50,30)],[Rect2i(0,0,128,128)]]:
			var regions: Array[Rect2i] = []
			regions.assign(values)
			var projection := LotProjection.new()
			projection.update_regions(city,null,regions)
			check_eq(projection.added,_expected(city,regions),"full-scan equivalence "+name+str(regions))
			projection.free()
		check_eq(SaveFormat.encode_city(city),original,"read-only city "+name)

func test_malformed_corner_flags_and_adjacent_multi_lots_keep_order() -> void:
	var city := flat_city()
	for y: int in range(22,40):
		for x: int in range(22,40):
			city.building.put(x,y,Buildings.MARINA)
			city.zone.put(x,y,((x+y)%5)*16)
	for y: int in range(18,44):
		var regions: Array[Rect2i] = [Rect2i(21,y,1,1),Rect2i(35,y,1,1)]
		var projection := LotProjection.new()
		projection.update_regions(city,null,regions)
		check_eq(projection.added,_expected(city,regions),"canonical malformed discovery "+str(y))
		projection.free()
