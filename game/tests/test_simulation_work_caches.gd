# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const PortSystem := preload("res://scripts/sim/port_system.gd")

## Simulation work skipped or shared by caches must equal the full computation:
## agriculture trial projections, merged admission budgets, the tourism
## gateways' navigable-sea flood and district discovery.

const CITIES := ["res://assets/cities/La Presa.sc2d", "res://assets/cities/Adaven.sc2d",
	"res://assets/cities/Foothills Ranch.sc2d", "res://assets/cities/Oro Canyon.sc2d"]
var contexts: Array[SimContext] = []

func after_each() -> void:
	AgricultureSystem.verify_projection_cache = false
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func _load(path: String) -> City:
	var loaded := SaveFormat.load(path)
	check(loaded.ok, path)
	return loaded.city if loaded.ok else null

# ── Agriculture trial projections ─────────────────────────────────────────

## Three farm bands with road frontage, limited power and water: some trials
## fit, others do not, and active farms later extend.
func farm_fixture() -> Dictionary:
	var c := flat_city(1000000)
	for band in 3:
		var top := 10 + band * 11
		for y in range(top - 1, top + 10):
			for x in range(14, 60):
				if y >= top: c.zone.put(x, y, Zones.make(Zones.AGR_LOW))
				c.underground.put(x, y, NetworkShapes.PIPE_FIRST)
		for x in range(10, 64): c.building.put(x, top - 1, Buildings.ROAD_FIRST)
	c.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	c.stamp_building(9, 10, Buildings.WIND_PLANT)
	for x in range(15, 21): c.stamp_building(x, 10, Buildings.WATER_PUMP)
	c.sea_level = 30
	var ctx := make_context(c, 11)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems = {&"power": power, &"water": water, &"agriculture": ag}
	power.setup(ctx)
	water.setup(ctx)
	ag.setup(ctx)
	contexts.append(ctx)
	return {"city": c, "ctx": ctx, "ag": ag, "power": power, "water": water}

func test_trial_projections_share_one_base_and_equal_full_projections() -> void:
	var f := farm_fixture()
	AgricultureSystem.verify_projection_cache = true
	AgricultureSystem.projection_cache_checks = 0
	AgricultureSystem.projection_cache_mismatches.clear()
	var trials := 0
	var bases := 0
	var reused := 0
	for month in 14:
		if month == 2:
			# Finish preparation: later phases only activate and extend, so an
			# accepted final trial can meet an unchanged city at validation.
			for i in f.city.zone.data.size():
				if f.city.building.data[i] == Buildings.NONE and Zones.kind(f.city.zone.data[i]) == Zones.AGR_LOW:
					f.city.zone.data[i] = 0
		f.power.monthly(f.ctx)
		f.water.monthly(f.ctx)
		for phase in 2:
			f.ag.monthly(f.ctx, phase)
			var work: Dictionary = f.ag.projection_work()
			trials += int(work.trials)
			bases += int(work.bases)
			reused += int(work.reused)
		f.ctx.clock.day += GameClock.DAYS_PER_MONTH
	AgricultureSystem.verify_projection_cache = false
	check_eq(AgricultureSystem.projection_cache_mismatches, [] as Array[String], "cached projections equal full projections")
	check_gt(AgricultureSystem.projection_cache_checks, 12, "verification compared many projections")
	check_gt(f.ag.current_parcels().size(), 3, "farms formed and activated")
	check_gt(trials, bases, "trials in one phase share their detached base")
	check_gt(reused, 0, "an accepted final trial serves the first validation pass")

## A live change between trials (the recovery put path) or before validation
## must rebuild the base and refuse the stale projection.
func test_live_changes_rebuild_the_trial_base_and_refuse_reuse() -> void:
	var f := farm_fixture()
	for phase in 2: f.ag.monthly(f.ctx, phase)
	var waiting: Array[Dictionary] = []
	for lot: Dictionary in f.ag.current_lots():
		if lot.state != &"active": waiting.append(f.ag._activation(lot))
	waiting = waiting.filter(func(v: Dictionary) -> bool: return not v.is_empty())
	check_gt(waiting.size(), 1, "two waiting activations")
	if waiting.size() < 2: return
	var a: Dictionary = waiting[0]
	var b: Dictionary = waiting[1]
	var c: City = f.city
	f.ag._clear_trials()
	f.ag._trials_open = true
	var proposals: Array[Dictionary] = []
	var first: City = f.ag._project_values([a] as Array[Dictionary])
	check(first != null)
	f.ag._accept_trial(proposals, a, first)
	# Live edit: a pipe and a lost power bit change the projection inputs.
	c.underground.put(13, 12, 1)
	c.flags.set_bits(12, 12, TileFlags.POWERED, false)
	var second: City = f.ag._project_values([a, b] as Array[Dictionary])
	var expected := AgriculturalParcelService.project(f.ctx, {}, [a, b] as Array[Dictionary])
	check_eq(SaveFormat.encode_city(second), SaveFormat.encode_city(expected), "rebuilt base equals a fresh projection")
	check_eq(f.ag.projection_work().bases, 2, "the live edit rebuilt the base")
	f.ag._trials_open = false
	c.building.put(40, 9, Buildings.NONE)
	var validation: City = f.ag._project_values(proposals)
	check(validation != first, "a changed city refuses the accepted trial's projection")
	check_eq(SaveFormat.encode_city(validation), SaveFormat.encode_city(AgriculturalParcelService.project(f.ctx, {}, proposals)))
	check_eq(f.ag.projection_work().reused, 0)

# ── Merged admission budgets ──────────────────────────────────────────────

func _separate(city: City, conservation: bool) -> Dictionary:
	return {"power": UtilityParams.admission_budget(city, false, conservation), "water": UtilityParams.admission_budget(city, true)}

func test_merged_admission_budgets_equal_separate_passes() -> void:
	for path in CITIES:
		var city := _load(path)
		if city == null: continue
		for conservation in [false, true]:
			check(UtilityParams.admission_budgets(city, conservation) == _separate(city, conservation), "%s conservation %s" % [path, conservation])
	# Imported power links: a matching link conducts, a stale one does not.
	var city := flat_city()
	city.stamp_building(10, 10, Buildings.COAL_PLANT)
	city.add_facility(Vector2i(10, 10), {"key": Buildings.key(Buildings.COAL_PLANT), "capacity": 300})
	for x in range(14, 30): city.building.put(x, 11, Buildings.POWER_LINE_FIRST)
	city.stamp_building(31, 11, Buildings.WATER_PUMP)
	city.add_facility(Vector2i(31, 11), {"key": Buildings.key(Buildings.WATER_PUMP), "output": 40})
	city.stamp_building(31, 14, Buildings.WATER_TOWER)
	city.flags.set_bits(31, 14, TileFlags.WATERED, true)
	city.building.put(30, 11, Buildings.NONE)
	city.imported_power_links[11 * City.WIDTH + 30] = Vector2i(Buildings.NONE, 0)
	city.imported_power_links[11 * City.WIDTH + 50] = Vector2i(Buildings.ROAD_FIRST, 0)
	var power := PowerSystem.new()
	var ctx := make_context(city)
	ctx.systems = {&"power": power}
	power.reallocate_established(ctx, Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	var links := city.imported_power_links.duplicate()
	check(UtilityParams.admission_budgets(city) == _separate(city, false), "links, towers and pumps")
	check_eq(city.imported_power_links, links, "budgets never prune links")
	ctx.systems.clear()

# ── Tourism gateways ──────────────────────────────────────────────────────

func _port_city(kind: int) -> City:
	var city := flat_city()
	for y in range(20, 25):
		for x in range(30, 35):
			city.zone.put(x, y, Zones.make(kind))
			city.set_flag(x, y, TileFlags.POWERED, true)
	if kind == Zones.AIRPORT:
		for x in range(30, 35): city.building.put(x, 20, Buildings.RUNWAY)
	else:
		city.building.put(34, 20, Buildings.CRANE)
		for x in range(35, 128):
			city.terrain.put(x, 20, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			city.set_heights(x, 20, 2, 4)
		for x in range(35, 35 + PortParams.PIER_LENGTH): city.building.put(x, 20, Buildings.PIER)
	city.building.put(29, 24, Buildings.ROAD_FIRST)
	return city

func test_navigable_sea_is_flooded_only_for_operating_seaports() -> void:
	for kind in [Zones.AIRPORT, Zones.SEAPORT]:
		var city := _port_city(kind)
		var ctx := make_context(city)
		var ports := PortSystem.new()
		ports.setup(ctx)
		for i in 4:
			city.building.put(5 + i, 5, Buildings.ROAD_FIRST)
			check_eq(ports.tourism_gateways().size(), 1)
		check_eq(ports.tourism_sea_floods, 0 if kind == Zones.AIRPORT else 4, "sea flood only for a harbor's berths")
		ports.tourism_gateways()
		check_eq(ports.tourism_sea_floods, 0 if kind == Zones.AIRPORT else 4, "unchanged layers reuse the gateways")
		if kind == Zones.SEAPORT:
			city.terrain.put(80, 20, Terrain.FLAT)
			check_eq(ports.tourism_gateways().size(), 0, "sealed water still invalidates the harbor")

# ── Tourism districts ─────────────────────────────────────────────────────

class CountDistricts extends TourismDistricts:
	var discoveries := 0
	func _discover(city: City) -> void:
		discoveries += 1
		super._discover(city)

func _district_outputs(d: TourismDistricts, rows: Array[Dictionary]) -> Array:
	var inputs: Array = []
	for row in rows: inputs.append(d.venue_inputs(row.anchor))
	return [inputs, d.report(), d.event_hosts(), d.spending_distribution(), d.get("_attractions"), d.get("_shops")]

func _visitor(at: Vector2i, guests: int) -> Dictionary:
	return {"anchor": at, "key": &"arcology_boddy", "code": Buildings.id_of(&"arcology_boddy"),
		"instance": at.y * City.WIDTH + at.x + 1, "operating": true, "guests": guests, "day_visitors": 0}

## Canonical discovery of the current layers, computed from scratch.
func _fresh_discovery(city: City, fires: Array) -> Array:
	var d := TourismDistricts.new()
	d.set("_buildings", city.building.data.duplicate())
	d.set("_zones", city.zone.data.duplicate())
	d.set("_fires", fires.duplicate())
	d._discover(city)
	return [d.get("_attractions"), d.get("_shops"), d.event_hosts()]

func test_discovery_reruns_only_for_inputs_it_reads() -> void:
	var city := flat_city()
	TourismFixture.venue(city, &"arcology_boddy", Vector2i(17, 20))
	TourismFixture.venue(city, &"museum", Vector2i(24, 20))
	TourismFixture.venue(city, &"com_corner_store", Vector2i(20, 24))
	for x in range(15, 31):
		city.building.put(x, 19, Buildings.ROAD_FIRST)
		city.building.put(x, 23, Buildings.ROAD_FIRST)
	city.building.put(15, 20, Buildings.ROAD_FIRST)
	city.building.put(15, 21, Buildings.ROAD_FIRST)
	city.building.put(15, 22, Buildings.ROAD_FIRST)
	for at in [Vector2i(24, 20), Vector2i(20, 24)]: TourismFixture.set_served(city, at, true, true)
	var ctx := TourismFixture.context(city)
	contexts.append(ctx)
	var rows: Array[Dictionary] = [_visitor(Vector2i(17, 20), 80)]
	var d := CountDistricts.new()
	d.refresh(ctx, rows)
	check_eq(d.discoveries, 1)
	check_gt(d.venue_inputs(Vector2i(17, 20)).district_appeal_bonus, 0, "the museum is a connected attraction")
	check_gt(d.report().allocated_spending_cents, 0, "the store receives spending")
	var edits: Array = [
		["unrelated flag bit", func() -> void: city.flags.set_bits(60, 60, TileFlags.CONDUCTS_WATER, true), false],
		["unrelated powered tile", func() -> void: city.flags.set_bits(70, 70, TileFlags.POWERED, true), false],
		["altitude", func() -> void: city.altitude.put(90, 90, city.altitude.at(90, 90) + 1), false],
		["shop power lost", func() -> void: city.flags.set_bits(20, 24, TileFlags.POWERED, false), true],
		["museum water lost", func() -> void: city.flags.set_bits(25, 21, TileFlags.WATERED, false), true],
		["attendance", func() -> void: rows[0].guests = 10, false],
		["served bits restored", func() -> void:
			city.flags.set_bits(20, 24, TileFlags.POWERED, true)
			city.flags.set_bits(25, 21, TileFlags.WATERED, true), true],
	]
	var expected := 1
	for edit: Array in edits:
		edit[1].call()
		d.refresh(ctx, rows)
		if edit[2]: expected += 1
		check_eq(d.discoveries, expected, edit[0])
		var fresh := TourismDistricts.new()
		fresh.refresh(ctx, rows)
		check_eq(_district_outputs(d, rows), _district_outputs(fresh, rows), "%s equals a fresh discovery" % edit[0])

func test_discovery_cache_matches_fresh_discovery_through_a_city_year() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Adaven.sc2d")
	check(loaded.ok)
	if not loaded.ok: return
	var sim := Simulation.new()
	sim.setup(loaded.city, 31, null, loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot), OK)
	var tourism := sim.tourism()
	var compared := 0
	for day in 120:
		if sim.budget_review_pending: sim.finish_budget_review()
		sim.advance_day()
		if day % 10 != 9: continue
		tourism.reconcile_now()
		var districts: TourismDistricts = tourism._districts
		var fires: Array = sim.get_system(&"disasters").call("fires")
		check_eq([districts.get("_attractions"), districts.get("_shops"), districts.event_hosts()],
			_fresh_discovery(sim.city, fires), "day %d" % day)
		compared += 1
	check_eq(compared, 12)
	sim.free()

# ── Transport components ──────────────────────────────────────────────────

## The original dictionary formulation of TourismAccess._components().
static func _reference_components(graph: Dictionary) -> Array:
	var reverse := {}
	var visited := {}
	var order := PackedInt32Array()
	for state: int in graph:
		if not reverse.has(state): reverse[state] = PackedInt32Array()
		for next: int in graph[state]:
			if not reverse.has(next): reverse[next] = PackedInt32Array()
			reverse[next].append(state)
	for state: int in graph:
		if visited.has(state): continue
		var stack: Array = [[state,0]]
		visited[state] = true
		while not stack.is_empty():
			var frame: Array = stack[-1]
			var neighbors: PackedInt32Array = graph.get(frame[0],PackedInt32Array())
			if frame[1] == neighbors.size():
				order.append(frame[0])
				stack.pop_back()
				continue
			var next := neighbors[frame[1]]
			frame[1] += 1
			if not visited.has(next):
				visited[next] = true
				stack.append([next,0])
	var component := {}
	var dag: Array[PackedInt32Array] = []
	order.reverse()
	for state in order:
		if component.has(state): continue
		var id := dag.size()
		dag.append(PackedInt32Array())
		var stack := PackedInt32Array([state])
		component[state] = id
		while not stack.is_empty():
			var node := stack[-1]
			stack.resize(stack.size()-1)
			for previous: int in reverse.get(node,PackedInt32Array()):
				if not component.has(previous):
					component[previous] = id
					stack.append(previous)
	for state: int in graph:
		var a: int = component[state]
		for next: int in graph[state]:
			var b: int = component[next]
			if a != b and not dag[a].has(b): dag[a].append(b)
	return [component.keys(), component.values(), dag]

func test_dense_components_equal_the_dictionary_passes() -> void:
	for path in CITIES:
		var city := _load(path)
		if city == null: continue
		var access := TourismAccess.new()
		access.refresh(TourismFixture.context(city))
		check_gt(access._dag.size(), 1, path)
		check_eq([access._component.keys(), access._component.values(), access._dag], _reference_components(access._graph), path)
	# Cycles, a shared target that is never a key, and duplicate edges.
	var access := TourismAccess.new()
	access._graph = {5: PackedInt32Array([6, 9]), 6: PackedInt32Array([5, 7, 7]), 7: PackedInt32Array([8]),
		8: PackedInt32Array([7, 9]), 1: PackedInt32Array([5, 9])}
	access._components()
	check_eq([access._component.keys(), access._component.values(), access._dag], _reference_components(access._graph))
