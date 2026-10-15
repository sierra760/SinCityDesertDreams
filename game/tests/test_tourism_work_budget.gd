# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Operation counts are assertions; microseconds/allocation peaks are observations.
extends "res://tests/test_case.gd"

class CountCity extends City:
	var reads := 0
	func building_at(x: int,y: int) -> int:
		reads += 1
		return super.building_at(x,y)

class CountState extends TourismState:
	var discoveries := 0
	func _refresh_anchors(city: City) -> void:
		if _city != city or city.building.data != _buildings or city.zone.data != _zones:
			discoveries += 1
		super._refresh_anchors(city)

func fixture(count: int, served: bool = false) -> Dictionary:
	var city := CountCity.new()
	# Stores are 1x1: every map tile can hold a venue. A road-bearing fixture
	# below instead reserves each fourth row; both exercise actual discovery.
	if served:
		for y in range(0,City.HEIGHT,4):
			for x in City.WIDTH: city.stamp_building(x,y,Buildings.ROAD_FIRST)
	for i in count:
		var a := Vector2i(i%City.WIDTH, (i/City.WIDTH)/3*4+1+(i/City.WIDTH)%3 if served else i/City.WIDTH)
		TourismFixture.venue(city,&"com_corner_store",a)
		if served: TourismFixture.set_served(city,a,true,true)
	var ctx := TourismFixture.context(city)
	var state := CountState.new()
	var tourism := TourismSystem.new()
	tourism._state = state
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	return {"city":city,"ctx":ctx,"state":state,"tourism":tourism}

func test_cached_forecast_does_not_rescan_unchanged_city() -> void:
	var f := fixture(100)
	var t: TourismSystem = f.tourism
	var state: CountState = f.state
	check_eq(state.discoveries,1)
	# Actual discovery calls _standing for each candidate footprint, which
	# reads building_at. Exercise the real cache entry repeatedly: a removed
	# cache guard would produce 100 footprint reads per call, not zero.
	f.city.reads = 0
	for i in 30: state._refresh_anchors(f.city)
	check_eq(f.city.reads,0,"unchanged discovery entry performs zero footprint reads")
	var before := t.save()
	for i in 30:
		t.forecast(i%21,(i*3)%21)
		t.report()
	check_eq(state.discoveries,1,"forecast/report never discover map again")
	check_eq(t.save(),before,"reads never advance attendance or money")
	for i in 30: t.reconcile_now()
	check_eq(state.discoveries,1,"native layer equality reuses anchor cache")
	f.city.stamp_building(0,2,Buildings.id_of(&"com_corner_store"))
	f.city.reads = 0
	state._refresh_anchors(f.city)
	check_eq(f.city.reads,101,"one changed discovery verifies exactly101 standing single-tile venues")
	t.reconcile_now()
	check_eq(state.discoveries,2,"map change invalidates discovery once")
	t.reconcile_now()
	check_eq(state.discoveries,2)

func test_dense_venue_monthly_work_is_bounded() -> void:
	var measurements: Array = []
	for count in [0,100,City.WIDTH*City.HEIGHT,City.WIDTH*City.HEIGHT*3/4]:
		var served: bool = count == City.WIDTH*City.HEIGHT*3/4
		var f := fixture(count,served)
		var city: CountCity = f.city
		var t: TourismSystem = f.tourism
		var state: CountState = f.state
		check_eq(t.report().size(),count,"maximum map fit has no overlapping footprints")
		city.reads = 0
		var memory := OS.get_static_memory_usage()
		var started := Time.get_ticks_usec()
		var projected := t.forecast()
		var forecast_us := Time.get_ticks_usec()-started
		var forecast_reads := city.reads
		check(forecast_reads <= 64*count,"forecast tile work bounded per venue")
		city.reads = 0
		started = Time.get_ticks_usec()
		t.monthly(f.ctx)
		var monthly_us := Time.get_ticks_usec()-started
		check(city.reads <= 128*count,"monthly tile work bounded per venue")
		check_eq(state.discoveries,1,"unchanged monthly work does not rediscover")
		check_eq(t.save().activity.rows.size(),count,"one activity record per venue, never per tourist")
		if served:
			check_gt(projected.day_visitors,0,"dense serviced layout admits visitors")
			check_between(projected.day_visitors,0,int(projected.day_pool))
		else:
			check_eq(projected.guests+projected.day_visitors,0,"unserved dense venues cannot generate attendance")
		measurements.append({"venues":count,"served":served,"forecast_us":forecast_us,"monthly_us":monthly_us,"forecast_building_reads":forecast_reads,"monthly_building_reads":city.reads,"discoveries":state.discoveries,"retained_allocation_bytes_delta":OS.get_static_memory_usage()-memory,"process_peak_bytes":OS.get_static_memory_peak_usage()})
	print("WORK_BUDGET ",JSON.stringify(measurements))
	var path := OS.get_environment("TOURISM_WORK_OUTPUT")
	if not path.is_empty():
		var file := FileAccess.open(path,FileAccess.WRITE)
		check(file != null)
		if file != null: file.store_string(JSON.stringify(measurements,"  "))
