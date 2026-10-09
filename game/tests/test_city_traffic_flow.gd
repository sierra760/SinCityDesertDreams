# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ambient traffic keeps moving through junctions, ring roads and highway
## interchanges instead of locking into clusters of stopped vehicles.
extends "res://tests/test_case.gd"

const TICK := 1.0 / 30.0

func _road(mask: int) -> int:
	return NetworkShapes.shape_id(NetworkShapes.Family.ROAD, mask)

## A four-way junction at (20,20) with arms of five cells.
func _crossroads() -> City:
	var city := flat_city()
	for i: int in range(15, 26):
		city.building.put(i, 20, _road(10))
		city.building.put(20, i, _road(5))
	city.building.put(20, 20, _road(15))
	return city

func _traffic(city: City, actors: Array) -> CityTraffic3D:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	traffic.actors.assign(actors)
	traffic._dirty = false
	traffic._refresh_left = 1000
	return traffic

func _car(id: int, cell: Vector2i, previous: Vector2i, next: Vector2i, t: float, type: StringName = &"road") -> Dictionary:
	return {"id":id,"kind":&"pedestrian" if type == &"pedestrian" else &"car","type":type,"domain":&"highway" if type == &"highway" else &"road",
		"cell":cell,"previous":previous,"next":next,"lane":0,"side":1.0,"t":t,"speed":.09 if type == &"pedestrian" else 1.05,
		"turns":0,"stopped":false,"variant":0,"length":.3}

func test_pedestrians_never_hold_the_junction_for_vehicles() -> void:
	var car := _car(1, Vector2i(20,20), Vector2i(19,20), Vector2i(21,20), .1)
	var walker := _car(2, Vector2i(20,20), Vector2i(20,19), Vector2i(20,21), .5, &"pedestrian")
	var traffic := _traffic(_crossroads(), [car, walker])
	for i: int in 10: traffic._step(TICK)
	check_gt(float(car.t), CityTraffic3D.STOP_LINE, "a pedestrian crossing beside the box does not stop the car")
	traffic.free()

func test_approaches_sharing_an_exit_do_not_queue_behind_each_other() -> void:
	# Both turn into the south arm. The car from the north, entering the cell,
	# must not queue behind the west arrival waiting at its own stop line: that
	# shared exit key held the north car while the junction was granted to it.
	var waiting := _car(1, Vector2i(20,20), Vector2i(19,20), Vector2i(20,21), .219)
	waiting.wait = 1.0
	waiting.stopped = true
	var arriving := _car(2, Vector2i(20,20), Vector2i(20,19), Vector2i(20,21), .02)
	arriving.wait = 5.0
	arriving.stopped = true
	var traffic := _traffic(_crossroads(), [waiting, arriving])
	traffic._step(TICK)
	check_gt(float(arriving.t), .02, "a different approach is not a vehicle ahead in this lane")
	var left: Dictionary = {}
	var together := 0
	for i: int in 240:
		traffic._step(TICK)
		var inside := 0
		for a: Dictionary in traffic.actors:
			if a.cell != Vector2i(20,20): left[a.id] = true
			elif float(a.t) >= CityTraffic3D.STOP_LINE and float(a.t) < CityTraffic3D.BOX_CLEAR: inside += 1
		if inside > 1: together += 1
	check_eq(together, 0, "crossing approaches take the box one at a time")
	check(left.has(1) and left.has(2), "both vehicles clear the junction")
	traffic.free()

func test_vehicle_waits_outside_the_box_until_its_exit_has_room() -> void:
	var queue := _car(1, Vector2i(21,20), Vector2i(20,20), Vector2i(22,20), .1)
	queue.speed = 0.0
	var arriving := _car(2, Vector2i(20,20), Vector2i(19,20), Vector2i(21,20), .05)
	var traffic := _traffic(_crossroads(), [queue, arriving])
	for i: int in 60: traffic._step(TICK)
	check_lt(float(arriving.t), CityTraffic3D.STOP_LINE, "a full exit keeps the junction clear")
	check(arriving.stopped)
	queue.speed = 1.05
	for i: int in 60: traffic._step(TICK)
	check(arriving.cell != Vector2i(20,20) or float(arriving.t) > CityTraffic3D.STOP_LINE, "enters once the exit moves")
	traffic.free()

func test_box_passes_to_a_waiting_crossing_axis() -> void:
	var traffic := _traffic(_crossroads(), [])
	var platoon := _car(1, Vector2i(20,20), Vector2i(19,20), Vector2i(21,20), .5)
	var follower := _car(2, Vector2i(20,20), Vector2i(21,20), Vector2i(19,20), .1)
	var crossing := _car(3, Vector2i(20,20), Vector2i(20,19), Vector2i(20,21), .1)
	var none: Dictionary = {}
	crossing.wait = 1.0
	check_eq(traffic._junction_grant([follower, crossing], 2, none, none), 2, "a platoon keeps the box while the crossing wait is short")
	crossing.wait = CityTraffic3D.AXIS_HOLD
	check_eq(traffic._junction_grant([follower, crossing], 2, none, none), 0, "a long crossing wait stops new entries so the box clears")
	check_eq(traffic._junction_grant([follower, crossing], 0, none, none), 1, "an empty box goes to the longest wait")
	check_eq(traffic._junction_grant([platoon, crossing], 3, none, none), 0)
	traffic.free()

func test_highway_traffic_drives_off_the_map_edge_instead_of_waiting() -> void:
	var city := flat_city()
	for y: int in range(0, 20):
		for x: int in [20, 21]: city.building.put(x, y, NetworkShapes.HIGHWAY_NS)
	var north := _car(1, Vector2i(21,2), Vector2i(21,3), Vector2i(21,1), .5, &"highway")
	var traffic := _traffic(city, [north])
	var reached := false
	for i: int in 120:
		traffic._step(TICK)
		for a: Dictionary in traffic.actors:
			check(not a.stopped or float(a.get("wait",0.0)) < 1.0, "never waits at the edge")
			if a.cell == Vector2i(21,0): reached = true
	check(reached, "drives into the edge cell")
	check_eq(traffic.actors.size(), 0, "leaves the city at the map edge")
	# An exiting vehicle is still a legal route through periodic reconciliation.
	var edge := _car(2, Vector2i(21,0), Vector2i(21,1), Vector2i(21,-1), .3, &"highway")
	traffic.actors.assign([edge])
	traffic._claims[2] = true # an empty test city admits no demand of its own
	traffic._reconcile()
	check(traffic.actors.has(edge), "reconcile keeps a vehicle leaving the map")
	traffic.free()

func test_vehicles_turn_at_most_once_through_a_highway_crossing() -> void:
	var city := flat_city()
	for dy: int in 2:
		for dx: int in 2: city.building.put(30+dx, 30+dy, NetworkShapes.HIGHWAY_JUNCTION)
	for d: int in range(1, 9):
		for across: int in 2:
			city.building.put(30+across, 30-d, NetworkShapes.HIGHWAY_NS)
			city.building.put(30+across, 31+d, NetworkShapes.HIGHWAY_NS)
			city.building.put(30-d, 30+across, NetworkShapes.HIGHWAY_EW)
			city.building.put(31+d, 30+across, NetworkShapes.HIGHWAY_EW)
	var traffic := _traffic(city, [])
	var block := Rect2i(30, 30, 2, 2)
	var tested := 0
	for start: Vector2i in [Vector2i(30,28), Vector2i(31,33), Vector2i(28,31), Vector2i(33,30)]:
		var choices := traffic.graph.neighbors(start, &"highway")
		for id: int in range(1, 25):
			for next: Vector2i in choices:
				var previous := start-(next-start)
				if not traffic.graph.traffic_choices(start, &"highway", previous, id % 2).has(next): continue
				var a := _car(id, start, previous, next, .5, &"highway")
				a.lane = id % 2
				traffic.actors.assign([a])
				var visits := 0
				for i: int in 300:
					var before: Vector2i = a.cell
					traffic._step(TICK)
					if traffic.actors.is_empty(): break
					if a.cell != before and block.has_point(a.cell): visits += 1
					if visits > 0 and not block.has_point(a.cell): break
				tested += 1
				check(visits <= 3, "a left turn crosses three cells; never circling the 2x2 block")
				check(traffic.actors.is_empty() or not block.has_point(a.cell), "leaves the crossing")
	check_gt(tested, 20)
	traffic.free()

func test_ramp_up_and_down_traffic_cannot_deadlock() -> void:
	var city := flat_city()
	for y: int in range(10, 40):
		for x: int in [20, 21]: city.building.put(x, y, NetworkShapes.HIGHWAY_NS)
	var ramp := Vector2i(19,20)
	city.building.putv(ramp, Buildings.ONRAMP_FIRST+2)
	city.flags.putv(ramp, RotationMapper.AXIS_FLAG)
	for y: int in range(12, 20): city.building.put(19, y, _road(5))
	var up := _car(1, ramp, Vector2i(19,19), Vector2i(20,20), .99)
	var down := _car(2, Vector2i(20,20), Vector2i(20,19), ramp, .99, &"highway")
	down.lane = 1
	var queued := _car(3, Vector2i(20,19), Vector2i(20,18), Vector2i(20,20), .8, &"highway")
	queued.lane = 1
	queued.stopped = true
	var traffic := _traffic(city, [up, down, queued])
	for i: int in 240: traffic._step(TICK)
	check_eq(up.domain, &"highway", "the ramp vehicle merges past stopped traffic")
	check(down.cell == ramp or down.domain == &"road", "the exiting vehicle takes the ramp")
	check_eq(traffic.actors.size(), 3, "nothing had to be removed")
	traffic.free()

func test_real_city_traffic_keeps_flowing() -> void:
	for name: String in ["La Presa", "Foothills Ranch"]:
		var loaded := SaveFormat.load("res://assets/cities/%s.sc2d" % name)
		check(bool(loaded.ok), name + " loads")
		if not bool(loaded.ok): continue
		var traffic := CityTraffic3D.new()
		traffic.bind_city(loaded.city)
		traffic.advance(0, true)
		var stopped := 0
		var samples := 0
		var longest := 0.0
		for i: int in 30*90:
			traffic._elapsed += TICK
			traffic._step(TICK)
			if i % 90 == 0: traffic._reconcile()
			if i < 30*30 or i % 15 != 0: continue
			for a: Dictionary in traffic.actors:
				if a.type != &"road" and a.type != &"highway": continue
				samples += 1
				if a.stopped: stopped += 1
				longest = maxf(longest, float(a.get("wait",0.0)))
		check_gt(samples, 1000, name + ": real demand fills the streets")
		var share := float(stopped)/maxf(1,samples)
		check_lt(share, .2, name + ": most vehicles are moving (stopped share %.3f)" % share)
		check_lt(longest, CityTraffic3D.STUCK_LIMIT+TICK, name + ": no vehicle waits beyond the release limit")
		traffic.free()
