# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self,"flexible-agriculture-continuation")
	reset(123)

func after_each() -> void:
	host.free()
	await process_frame

func reset(seed_value: int) -> void:
	host.begin_city(flat_city(),{},seed_value,null)
	host.sim.set_process(false)
	host.sim.stats.disasters_enabled = false
	host.sim.city.funds = 1000000

func paint(tool: int, a: Vector2i, b := Vector2i(-1,-1)) -> void:
	host.select_tool(tool)
	var result := host.handle_drag(a,a if b.x < 0 else b)
	check(result.get("applied",false),"real toolbar tool %d: %s" % [tool,result])

func build_serviced_land() -> void:
	paint(Tools.Kind.COAL_PLANT,Vector2i(32,36))
	paint(Tools.Kind.POWER_LINE,Vector2i(36,37),Vector2i(62,37))
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	paint(Tools.Kind.WATER_PIPE,Vector2i(38,39),Vector2i(62,39))
	for x in [40,44,48,52,56,60]:
		paint(Tools.Kind.WATER_PIPE,Vector2i(x,39),Vector2i(x,50))
		paint(Tools.Kind.POWER_LINE,Vector2i(x,38),Vector2i(x,39))
	paint(Tools.Kind.ROAD,Vector2i(39,39),Vector2i(62,39))
	paint(Tools.Kind.ROAD,Vector2i(39,40),Vector2i(39,50))
	paint(Tools.Kind.ZONE_AGR_LOW,Vector2i(40,40),Vector2i(60,42))
	paint(Tools.Kind.ZONE_AGR_LOW,Vector2i(40,43),Vector2i(44,49))

func test_real_host_save_before_phase_boundary_matches_sixty_days_exactly() -> void:
	build_serviced_land()
	paint(Tools.Kind.POWER_LINE,Vector2i(63,37),Vector2i(74,37))
	paint(Tools.Kind.WATER_PIPE,Vector2i(63,39),Vector2i(74,39))
	paint(Tools.Kind.ROAD,Vector2i(63,39),Vector2i(74,39))
	for x in [64,68,72]:
		paint(Tools.Kind.WATER_PIPE,Vector2i(x,39),Vector2i(x,44))
		paint(Tools.Kind.POWER_LINE,Vector2i(x,38))
	paint(Tools.Kind.ZONE_AGR_LOW,Vector2i(61,40),Vector2i(74,42))
	host.sim.advance_days(5)
	var ag := host.sim.get_system(&"agriculture") as AgricultureSystem
	check_gt(ag.current_parcels().size(),0)
	check_eq(ag.save().phase_months,[0,-1],"save is between normal monthly phases")
	var path := "user://flexible-before-phase.sc2d"
	check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok,loaded.get("error",""))
	if not loaded.ok: return
	var restored := Simulation.new()
	root.add_child(restored)
	restored.setup(loaded.city,-1,null,loaded.snapshot)
	restored.restore(loaded.snapshot)
	restored.set_process(false)
	var other := restored.get_system(&"agriculture") as AgricultureSystem
	var seen_active := false
	var seen_phase_one := false
	for day in 61:
		check_eq(restored.city.agricultural_parcels.to_dict(),host.sim.city.agricultural_parcels.to_dict(),"day %d every member/layout/phase/stock/revision" % day)
		check_eq(other.parcel_jobs(),ag.parcel_jobs(),"assigned integer jobs")
		check_eq(other.save(),ag.save(),"private growth RNG and phase guards")
		check_eq(restored.rng.state(),host.sim.rng.state(),"shared RNG")
		check_eq(restored.city.funds,host.sim.city.funds,"treasury")
		check_eq(SaveFormat.encode_city(restored.city),SaveFormat.encode_city(host.sim.city),"every saved city field and layer")
		check_eq(restored.snapshot(),host.sim.snapshot(),"all accounts, flags and simulation systems")
		for record in ag.current_parcels():
			seen_active = seen_active or record.state == &"active"
			seen_phase_one = seen_phase_one or record.phase == 1
		if day < 60:
			host.sim.advance_day()
			restored.advance_day()
	check(seen_active,"continuation includes serviced activation")
	check(seen_phase_one,"continuation includes east-half phase ownership")
	restored.free()
