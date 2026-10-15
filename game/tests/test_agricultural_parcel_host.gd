# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self,"flexible-agriculture-host")
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

func test_natural_nonrectangular_farms_service_tax_cuts_and_replacement() -> void:
	var seen := {}
	var irregular := false
	for seed_value in [123,1827,5821]:
		reset(seed_value)
		build_serviced_land()
		var ag := host.sim.get_system(&"agriculture") as AgricultureSystem
		host.sim.advance_days(5)
		check_gt(ag.current_parcels().size(),0,"normal day five forms parcels")
		for record in ag.current_parcels(): check_eq(record.state,&"prepared")
		host.sim.advance_day()
		check_eq(host.sim.clock.day,6,"normal day six crosses the other growth phase")
		host.sim.advance_days(60)
		var active := 0
		for record in ag.current_parcels():
			if record.state != &"active": continue
			active += 1
			seen[record.archetype] = true
			var bounds := AgriculturalParcels.bounds(record.members)
			irregular = irregular or record.members.size() < bounds.get_area()
			for i in record.members:
				var tile := AgriculturalParcels.tile(i)
				check(host.sim.city.is_watered(tile.x,tile.y),"actual pump supplies each member")
			check_eq(ag.inspect_tile(AgriculturalParcels.tile(record.members[0])).blocked_reason,"")
		check_gt(active,0,"natural serviced activation")
		check_gt(host.sim.stats.ledger.get(&"taxes_agricultural",0),0,"normal scheduled tax accrual")
		print("NATURAL_HOST seed=",seed_value," active=",active," types=",seen," records=",host.sim.city.agricultural_parcels.to_dict())
	check(seen.has(&"cattle_range"),"retained city seeds naturally produce cattle")
	check(seen.has(&"sheep_pasture"),"retained city seeds naturally produce sheep")
	check(seen.has(&"grain") or seen.has(&"alfalfa") or seen.has(&"vegetables"),"retained seeds naturally produce crops")
	check(irregular,"a natural parcel follows a nonrectangular mask")
	var ag := host.sim.get_system(&"agriculture") as AgricultureSystem
	paint(Tools.Kind.BULLDOZE,Vector2i(38,38))
	host.sim.advance_days(90)
	var dormant := 0
	for record in ag.current_parcels():
		if record.state == &"dormant": dormant += 1
	check_gt(dormant,0,"three failed real water months cause dormancy")
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	host.sim.advance_days(30)
	var recovered: Array[Dictionary] = []
	for record in ag.current_parcels():
		if record.state == &"active": recovered.append(record)
	check_gt(recovered.size(),0,"normal water recovery reactivates parcels")
	if not recovered.is_empty():
		var record := recovered[0]
		var cell: int = record.members[-1]
		var tile := AgriculturalParcels.tile(cell)
		paint(Tools.Kind.ROAD,tile)
		check_eq(host.sim.city.agricultural_parcels.id_at(tile),0,"normal road cuts only its selected member")
		check(Buildings.is_road_like(host.sim.city.building_at(tile.x,tile.y)))
		var remaining := ag.current_parcels()
		if not remaining.is_empty():
			var victim := AgriculturalParcels.tile(remaining[-1].members[-1])
			paint(Tools.Kind.BULLDOZE,victim)
			check_eq(host.sim.city.agricultural_parcels.id_at(victim),0)
	await Fixture.settle(self,3)
	host.begin_city(flat_city(),{},456,null)
	host.sim.set_process(false)
	await Fixture.settle(self,3)
	check_eq((host.sim.get_system(&"agriculture") as AgricultureSystem).current_parcels().size(),0)
	check_eq(host.city_view_3d.livestock.detailed_animal_count(),0,"replacement releases natural herds")

func test_natural_host_accrued_agricultural_tax_settles_at_year_boundary() -> void:
	reset(5821)
	build_serviced_land()
	var ag := host.sim.get_system(&"agriculture") as AgricultureSystem
	host.sim.advance_days(GameClock.DAYS_PER_YEAR - 1)
	check_eq(host.sim.clock.day,299,"normal clock reaches the final day before settlement")
	check(not host.sim.budget_review_pending,"annual review has not happened early")
	check_gt(ag.jobs(),0,"naturally formed serviced farms employ workers before settlement")
	var active := 0
	for record in ag.current_parcels():
		if record.state == &"active": active += 1
	check_gt(active,0,"annual tax comes from naturally active farms")
	var accrued_agricultural := int(host.sim.stats.ledger.get(&"taxes_agricultural",0))
	check_gt(accrued_agricultural,0,"actual monthly bookings accrued agricultural tax")
	check_eq(int(host.sim.stats.last_year_ledger.get(&"taxes_agricultural",0)),0,"no earlier annual agricultural settlement")
	var funds_before := host.sim.city.funds
	host.sim.advance_day()
	check_eq(host.sim.clock.day,GameClock.DAYS_PER_YEAR,"normal daily scheduler crosses the year boundary")
	check(host.sim.budget_review_pending,"actual year-end budget review is due")
	var settled := host.sim.stats.last_year_ledger
	check_eq(int(settled.get(&"taxes_agricultural",0)),accrued_agricultural,"accrued agricultural amount survives in the settled annual ledger")
	check_eq(int(host.sim.stats.ledger.get(&"taxes_agricultural",0)),0,"new year agricultural accrual starts empty")
	var income := 0
	var expenses := 0
	for account in settled:
		if StringName(account) in BudgetParams.EXPENSE_KEYS:
			expenses += int(settled[account])
		else:
			income += int(settled[account])
	check_gt(income,0,"settlement includes real income")
	check(income != expenses,"nonzero annual balance makes the funds transition observable")
	check_eq(host.sim.city.funds,funds_before+income-expenses,"actual annual budget balance is transferred to city funds")
	var budget := host.sim.get_system(&"budget") as BudgetSystem
	var review := budget.review_summary()
	check_eq(int(review.income),income,"host budget review reports settled income")
	check_eq(int(review.expenses),expenses,"host budget review reports settled expenses")
	check_eq(int(review.funds),host.sim.city.funds)
	print("NATURAL_HOST_SETTLEMENT day=",host.sim.clock.day," active=",active," jobs=",ag.jobs()," accrued_agricultural=",accrued_agricultural," settled_agricultural=",settled.get(&"taxes_agricultural",0)," income=",income," expenses=",expenses," funds_before=",funds_before," funds_after=",host.sim.city.funds)
