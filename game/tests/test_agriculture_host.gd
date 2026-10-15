# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
const ParcelFixture := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self, "agriculture-host")
	host.sim.set_process(false)
	host.sim.stats.disasters_enabled = false
	host.sim.city.funds = 1000000

func after_each() -> void:
	host.free()
	await process_frame

func paint(tool: int, at: Vector2i, end := Vector2i(-1,-1)) -> void:
	host.select_tool(tool)
	if end.x < 0: end = at
	var result := host.handle_drag(at,end)
	check(result.get("applied", false), "actual host tool %d at %s: %s" % [tool,at,result])

func services() -> void:
	paint(Tools.Kind.COAL_PLANT,Vector2i(32,36))
	paint(Tools.Kind.POWER_LINE,Vector2i(36,37),Vector2i(54,37))
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	paint(Tools.Kind.WATER_PIPE,Vector2i(38,39),Vector2i(54,39))
	for x in [40,44,48,52]:
		paint(Tools.Kind.POWER_LINE,Vector2i(x,38),Vector2i(x,39))
	paint(Tools.Kind.ROAD,Vector2i(39,43),Vector2i(55,43))

func test_tool_zoning_services_growth_tax_save_loss_recovery_demolition() -> void:
	services()
	for x in [40,44,48,52]:
		paint(Tools.Kind.ZONE_AGR_LOW if x < 48 else Tools.Kind.ZONE_AGR_HIGH,Vector2i(x,40),Vector2i(x+2,42))
	var ag := host.sim.get_system(&"agriculture")
	host.sim.advance_days(5)
	var prepared := 0
	for lot in ag.current_lots():
		if lot.state == &"prepared": prepared += 1
	check_gt(prepared,0,"normal day-five development prepares farm lots")
	var path := "user://agriculture-host-day-five.sc2d"
	check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok)
	var restored := Simulation.new()
	root.add_child(restored)
	restored.setup(loaded.city,-1,null,loaded.snapshot)
	restored.restore(loaded.snapshot)
	var sizes := {}
	for day in 56:
		host.sim.advance_day()
		restored.advance_day()
		for lot in ag.current_lots():
			if lot.state == &"active": sizes[lot.rect.size.x] = true
		check_eq(restored.city.building.data,host.sim.city.building.data)
		check_eq(restored.city.zone.data,host.sim.city.zone.data)
		check_eq(restored.rng.state(),host.sim.rng.state())
		check_eq(restored.get_system(&"agriculture").save(),ag.save())
		check_eq(restored.city.funds,host.sim.city.funds)
	restored.free()
	var active: Array[Dictionary] = []
	for lot in ag.current_lots():
		if lot.state != &"active": continue
		active.append(lot)
		sizes[lot.rect.size.x] = true
		for y in range(lot.rect.position.y,lot.rect.end.y):
			for x in range(lot.rect.position.x,lot.rect.end.x):
				check(host.sim.city.is_watered(x,y),"real pump serves every active tile")
				if AgricultureParams.power_load(lot.building_id)>0: check(host.sim.city.is_powered(x,y))
	print("HOST ACTIVE ",active)
	check_gt(active.size(),0)
	check(sizes.has(2),"actual host grows a two-tile farm")
	check(sizes.has(3),"actual host grows a three-tile farm")
	check_gt(host.sim.stats.ledger.get(&"taxes_agricultural",0),0,"real scheduled settlement taxes active jobs")
	paint(Tools.Kind.ROAD,Vector2i(56,43))
	paint(Tools.Kind.BULLDOZE,Vector2i(38,38))
	host.sim.advance_days(90)
	var dormant := 0
	for lot in ag.current_lots():
		if lot.state == &"dormant": dormant += 1
	check_gt(dormant,0,"three service failures cause dormancy")
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	host.sim.advance_days(30)
	var recovered := 0
	for lot in ag.current_lots():
		if lot.state == &"active": recovered += 1
	check_gt(recovered,0,"real pump restoration reactivates lots")
	host.sim.advance_days(GameClock.DAYS_PER_YEAR-host.sim.clock.day)
	check_gt(host.sim.stats.last_year_ledger.get(&"taxes_agricultural",0),0,"actual annual settlement retains agricultural tax income")
	for lot in ag.current_lots():
		if lot.parcel_id != 0 and lot.mode != &"legacy":
			for i in lot.members: paint(Tools.Kind.BULLDOZE,AgriculturalParcels.tile(i))
		else: paint(Tools.Kind.BULLDOZE,lot.anchor)
	check_eq(ag.current_lots().size(),0,"host demolition invalidates all lots")

func test_canonical_ranch_rotations_paused_explore_removal_detail_and_city_replacement() -> void:
	var city := flat_city()
	for record in [[Vector2i(40,40),&"feedlot",Zones.AGR_HIGH],[Vector2i(44,40),&"cattle_range",Zones.AGR_LOW],[Vector2i(48,40),&"sheep_pasture",Zones.AGR_LOW]]:
		city.stamp_building(record[0].x,record[0].y,AgricultureParams.building_id(record[1]),record[2])
	for x in range(38,53): city.building.put(x,44,Buildings.ROAD_FIRST)
	host.begin_city(city,{},123,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	var view := host.city_view_3d
	var ag := host.sim.get_system(&"agriculture")
	view.set_camera_state(Vector3(43,4*CityGeometry3D.HEIGHT,41.5),0,10)
	await Fixture.settle(self,3)
	var layer := view.livestock
	layer.sync_source(ag)
	layer.advance(.05,view.camera,true)
	check_eq(ParcelFixture.herd_snapshot(layer).size(),3,"host presents cattle, sheep and feedlot lots")
	check_gt(layer.detailed_animal_count(),0)
	var herd := ParcelFixture.herd_at(layer,"legacy:40:40")
	check(not herd.is_empty())
	if herd.is_empty(): return
	var initial: Transform3D = herd.root_transform
	var root_id: int = herd.root_id
	var saved: Dictionary = ag.save()
	for turn in 4:
		view.set_camera_state(Vector3(43,4*CityGeometry3D.HEIGHT,41.5),turn,10)
		await Fixture.settle(self,2)
		check_eq(ag.save(),saved,"view rotation leaves canonical records unchanged")
		herd = ParcelFixture.herd_at(layer,"legacy:40:40")
		check_eq(herd.root_transform,initial)
		check_eq(herd.root_id,root_id)
		check_eq(saved.lots[0].x,40)
		check_eq(saved.lots[0].y,40)
	view.set_camera_state(Vector3(41.5,4*CityGeometry3D.HEIGHT,44),0,10)
	await physics_frame
	check(host.enter_explore())
	host.exploration.set_physics_process(false)
	host.exploration.pause()
	await Fixture.settle(self,3)
	var result := host.builder.apply(Tools.Kind.BULLDOZE,Vector2i(40,40))
	check(result.applied,"builder demolition while Explore paused")
	await Fixture.settle(self,3)
	check(ParcelFixture.herd_at(layer,"legacy:40:40").is_empty(),"paused host removes demolished feedlot")
	view.set_render_options("low",50)
	await Fixture.settle(self,3)
	check(ParcelFixture.herd_at(layer,"legacy:40:40").is_empty(),"detail change cannot resurrect herd")
	host.begin_city(flat_city(),{},456,null)
	await Fixture.settle(self,3)
	check_eq(layer.get_child_count(),0,"city replacement frees every old animal root")
	check_eq(layer.detailed_animal_count(),0)
