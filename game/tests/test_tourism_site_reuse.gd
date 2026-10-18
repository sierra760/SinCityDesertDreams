# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

## Frozen full scan is the independent oracle for candidate filtering/order.
class FullScan extends TourismDistricts:
	func _discover(city: City) -> void:
		_event_hosts = {"stadium":false,"city_hall":false}
		_attractions.clear()
		_shops.clear()
		_served_tiles.clear()
		var fire_set := {}
		for at: Vector2i in _fires: fire_set[at] = true
		# One dirty-layer walk, then bounded bin lookups per venue. Canonical
		# anchors and complete rectangles work without facility metadata.
		var interest := _interest_table()
		for index in _buildings.size():
			var code := _buildings[index]
			# Table equals the non-vacant part of the predicate below; NONE always
			# takes the full test because vacancy also depends on its zone.
			if code != Buildings.NONE and code >= 0 and code < interest.size() and interest[code] == 0: continue
			var key := Buildings.key(code)
			var category: StringName = CATEGORIES.get(key,&"")
			var kind := Zones.kind(_zones[index])
			var commercial := Buildings.category(code) == Buildings.Category.COMMERCIAL and not RewardParams.ARCOLOGIES.has(key)
			var vacant := code == Buildings.NONE and kind in [Zones.COM_LOW,Zones.COM_HIGH]
			if category == &"" and key != &"city_hall" and not commercial and not vacant: continue
			@warning_ignore("integer_division")
			var at := Vector2i(index % City.WIDTH,index / City.WIDTH)
			if not UtilityParams.is_anchor_tile(_buildings,_zones,index): continue
			var size := Buildings.size(code)
			var rect := Rect2i(at,size)
			if not _complete(city,rect,code): continue
			# Every served bit _operating may read for this complete footprint.
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x): _served_tiles.append(y*City.WIDTH+x)
			if String(key) in _event_hosts and _operating(city,rect,key,fire_set): _event_hosts[String(key)] = true
			if category != &"":
				if _operating(city,rect,key,fire_set): _bin_add(_attractions,at,{"rect":rect,"category":category})
			elif commercial or vacant:
				if _operating(city,rect,&"shop",fire_set): _bin_add(_shops,at,{"rect":rect,"anchor":at})
		_served_bits = _served(city)

class CountedDistricts extends TourismDistricts:
	var completions := 0
	func _complete(city: City, rect: Rect2i, code: int) -> bool:
		completions += 1
		return super._complete(city,rect,code)

func test_service_changes_reuse_complete_static_sites() -> void:
	var city := flat_city()
	TourismFixture.venue(city,&"museum",Vector2i(20,20))
	TourismFixture.set_served(city,Vector2i(20,20),true,true)
	city.building.put(19,20,Buildings.ROAD_FIRST)
	var ctx := TourismFixture.context(city)
	var d := CountedDistricts.new()
	d.refresh(ctx,[])
	var before := d.completions
	check_gt(before,0,"museum completeness was established")
	city.flags.data[20*128+20] ^= TileFlags.POWERED
	d.refresh(ctx,[])
	check_eq(d.completions,before,"service-only changes reuse complete static sites")
	city.building.data[20*128+20] = Buildings.NONE
	d.refresh(ctx,[])
	check_gt(d.completions,before,"raw geometry changes recheck completeness")
	ctx.systems.clear()

func _equal_discovery(d: TourismDistricts, full: TourismDistricts, label: String) -> void:
	check(d._attractions == full._attractions,label+" attractions")
	check(d._shops == full._shops,label+" shops and insertion order")
	check_eq(d._served_tiles,full._served_tiles,label+" served footprint order")
	check_eq(d._served_bits,full._served_bits,label+" served bits")
	check(d.event_hosts()==full.event_hosts(),label+" hosts")
	check(d._inputs==full._inputs,label+" district inputs")
	check(d.spending_distribution()==full.spending_distribution(),label+" spending")
	check(d.report()==full.report(),label+" report")

func test_native_candidates_equal_full_scan_on_real_cities_and_raw_edits() -> void:
	for name in ["La Presa","Foothills Ranch","Adaven","Oro Canyon"]:
		var loaded := SaveFormat.load("res://assets/cities/"+name+".sc2d")
		check(loaded.ok,name)
		if not loaded.ok: continue
		var city: City = loaded.city
		var ctx := TourismFixture.context(city)
		var d := TourismDistricts.new()
		var full := FullScan.new()
		for edit in 7:
			match edit:
				1:
					# Vacant commerce with every corner encoding, both zone kinds.
					for corner in 16:
						for kind: int in [Zones.COM_LOW,Zones.COM_HIGH]:
							var x := 30+corner
							var y := 30+kind
							city.building.data[y*128+x] = Buildings.NONE
							city.zone.data[y*128+x] = (corner<<4)|kind
				2:
					city.stamp_building(30,30,Buildings.id_of(&"museum"))
					city.stamp_building(40,40,Buildings.id_of(&"small_park"))
				3:
					city.flags.data[30*128+30] ^= TileFlags.POWERED
					city.flags.data[40*128+40] ^= TileFlags.WATERED
				4: city.flood_overlay[Vector2i(40,40)] = 1
				5:
					city.flood_overlay.clear()
					city.terrain.data[40*128+40] = Terrain.SURFACE
					city.building.data[31*128+31] = Buildings.NONE
				6: city.zone.data[33*128+31] = Zones.make(Zones.RES_LOW)
			d.refresh(ctx,[])
			full.refresh(ctx,[])
			_equal_discovery(d,full,name+" edit "+str(edit))
		ctx.systems.clear()

func _served_district() -> City:
	var city := flat_city()
	for entry: Array in [[&"arcology_boddy",Vector2i(10,20)],
		[&"com_corner_store",Vector2i(20,20)],[&"museum",Vector2i(20,14)]]:
		TourismFixture.venue(city,entry[0],entry[1])
		TourismFixture.set_served(city,entry[1],true,true)
		city.building.put(entry[1].x-1,entry[1].y,Buildings.ROAD_FIRST)
	TourismFixture.connect_roads(city)
	return city

func test_attended_district_and_same_geometry_city_rebind_equal_full_scan() -> void:
	var d := TourismDistricts.new()
	var full := FullScan.new()
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,20),"key":&"arcology_boddy",
		"code":Buildings.id_of(&"arcology_boddy"),"instance":1,
		"guests":100,"day_visitors":0,"operating":true}]
	var cities: Array[City] = [_served_district(),_served_district()]
	check_eq(cities[0].building.data,cities[1].building.data,"rebind has identical buildings")
	check_eq(cities[0].zone.data,cities[1].zone.data,"rebind has identical zones")
	cities[1].flags.data[14*128+20] &= ~TileFlags.POWERED
	cities[1].flood_overlay[Vector2i(20,20)] = 1
	for i in cities.size():
		var ctx := TourismFixture.context(cities[i])
		d.refresh(ctx,rows)
		full.refresh(ctx,rows)
		_equal_discovery(d,full,"attended rebind "+str(i))
		if i == 0:
			check_gt(d.report().allocated_spending_cents,0,"spending comparison is exercised")
			check_gt(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,0,"attraction input is exercised")
		else:
			check_eq(d.report().allocated_spending_cents,0,"flooded retail closes in rebound city")
			check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,0,"unpowered museum closes in rebound city")
		ctx.systems.clear()
