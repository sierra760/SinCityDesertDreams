# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ambient vehicles and pedestrians moving through the 3D city, up to fixed
## caps. They are presentation only: they read the city and never change its
## state or the simulation's random stream.
class_name CityTraffic3D
extends Node3D

const MAX_VEHICLES := 384
const MAX_PEDESTRIANS := 512
const MAX_EXTERNAL := 64
const FOLLOW_GAP := .48
const STEP := 1.0 / 30.0
## Junction control. Vehicles wait before STOP_LINE; past it they are in the
## box until BOX_CLEAR, after which crossing traffic may follow them in. Both
## directions of one axis share the box; it passes to the crossing axis once
## that axis has waited AXIS_HOLD seconds (or at once when the box is empty).
const STOP_LINE := .22
const BOX_CLEAR := .75
const AXIS_HOLD := 2.5
## A vehicle stopped this long is in a queue nothing will release (a saturated
## loop of junctions); it leaves and admission replaces it elsewhere.
const STUCK_LIMIT := 20.0
## An on-ramp vehicle waiting this long gets a gap: outer-lane traffic bound
## for its merge cell holds at mid-cell until it has joined.
const MERGE_PATIENCE := 2.0
var graph := CityTrafficGraph.new()
var actors: Array[Dictionary] = []
var statistics: Dictionary = {}
var riders: Dictionary = {}
var _next_id := 1
var _elapsed := 0.0
var _accumulator := 0.0
var _step_interval := STEP
var _render_delta := 0.0
var _render_serial := 0
var _refresh_left := 0.0
var _batches: Dictionary = {}
## Camera sampling is scoped to one synchronous render, never across frames.
var _camera_scope := false
var _render_camera: Camera3D
var _camera_position := Vector3.ZERO
var _camera_size := 0.0
var _camera_orthographic := false
var _camera_viewport_size := Vector2.ZERO
var _camera_bounds := Rect2()
var _render_paused := false
var _paused_render_state: Array = []
var _paused_camera_state: Array = []
var _paused_camera_ready := false
const _CULL_DOMAINS := {&"road": 0, &"highway": 1, &"rail": 2, &"water": 3}
var _cull_results := PackedByteArray()
var _cull_graph: CityTrafficGraph
var _cull_revision := -1
var _cull_camera_state: Array = []
var _route_graph: CityTrafficGraph
var _route_revision := -1
var _route_ramps := PackedByteArray()
var _route_degrees := PackedInt32Array()
var _route_neighbors: Array = []
var _claims: Dictionary = {}
var _external: Array[Dictionary] = []
var _external_states: Dictionary = {}
var _targets: Dictionary = {}
var _dirty := true
var _reserved_rail: Dictionary = {}
## Small stable integer ids for StringNames used in per-frame/per-tick keys.
static var _name_ids: Dictionary = {}

func bind_city(city: City) -> void:
	if graph.city == city: return
	_paused_render_state.clear()
	_paused_camera_ready = false
	_paused_camera_state.clear()
	graph.bind_city(city)
	actors.clear()
	_claims.clear()
	_external.clear()
	_external_states.clear()
	_elapsed = 0
	_accumulator = 0
	_next_id = 1
	_dirty = true
	for batch: MultiMeshInstance3D in _batches.values(): batch.multimesh.visible_instance_count = 0

func set_reserved_rail_cells(cells: Array[Vector2i]) -> void:
	var reserved: Dictionary = {}
	for cell: Vector2i in cells: reserved[cell] = true
	if reserved == _reserved_rail: return
	_reserved_rail = reserved
	_dirty = true

func invalidate() -> void:
	_dirty = true
	_paused_render_state.clear()
	_paused_camera_ready = false
	_paused_camera_state.clear()

## Call once from Main, including in Explore. Pause freezes all ambient motion.
func advance(delta: float, paused: bool, records: Array = [], camera: Camera3D = null, enabled: bool = true) -> void:
	var started := Time.get_ticks_usec()
	_render_delta = clampf(delta,0,.2) if not paused and enabled else 0.0
	_render_paused = paused
	if not paused or not enabled:
		_paused_render_state.clear()
		_paused_camera_ready = false
		_paused_camera_state.clear()
	visible = enabled
	if graph.city == null: return
	_refresh_left -= maxf(0, delta)
	if _dirty or _refresh_left <= 0:
		graph.refresh()
		_reconcile()
		_refresh_left = .75
		_dirty = false
	_external.clear()
	var external_indices: Dictionary = {}
	var live_external: Dictionary = {}
	for raw: Variant in records:
		if _external.size() >= MAX_EXTERNAL: break
		var record := CityEntityRecords.normalize(raw, &"car")
		if record.is_empty(): continue
		var kind: StringName = record.kind
		if kind == &"fire_crew": kind = &"fire_engine"
		elif kind == &"police_crew": kind = &"police"
		elif kind == &"military_crew": kind = &"military"
		if not CityTrafficCatalog.is_vehicle_kind(kind): continue
		record.kind = kind
		var p: Vector2 = record.pos
		if not p.is_finite() or not graph.city.in_bounds(int(p.x),int(p.y)): continue
		var ordinal := int(external_indices.get(kind,0))
		external_indices[kind] = ordinal+1
		var key := str(kind)+":"+str(ordinal)
		var domain := CityTrafficCatalog.domain(kind)
		var cell := Vector2i(p)
		var target := graph.point(cell,domain if domain != &"air" else &"road")
		if domain == &"air":
			var altitude: float = record.altitude
			if not is_finite(altitude): altitude = 0
			target.y = CityGeometry3D.surface_height(graph.city,cell) + maxf(.03,altitude*CityGeometry3D.HEIGHT)
		var yaw := -float(record.heading)*PI/4.0
		var state: Dictionary = _external_states.get(key,{"position":target,"yaw":yaw})
		if not paused:
			# Local interpolation only; reappearing/reordered source records snap.
			if state.position.distance_squared_to(target) > 36.0: state.position = target
			else: state.position = state.position.move_toward(target,clampf(delta,0,.2)*(2.0 if domain == &"air" else .8))
			state.yaw = lerp_angle(state.yaw,yaw,minf(1,delta*6))
		_external_states[key] = state
		live_external[key] = true
		record.presentation_position = state.position
		record.presentation_yaw = state.yaw
		record.presentation_id = -1 - CityTrafficCatalog.vehicle_kind_index(kind)*MAX_EXTERNAL-ordinal
		_external.append(record)
	for key: String in _external_states.keys():
		if not live_external.has(key): _external_states.erase(key)
	var interval := .1 if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL and camera.size >= 32.0 else STEP
	# Keep the displayed interpolation phase when switching Build/Explore cadence.
	if interval != _step_interval:
		for a: Dictionary in actors:
			if a.has("_render_pose") and a.get("_render_serial",-1) == _render_serial and a.get("_render_revision",-1) == graph.revision:
				a._cadence_pose = a._render_pose
				a._cadence_left = .2
				a._cadence_revision = graph.revision
		_accumulator *= interval / _step_interval
	_step_interval = interval
	if not paused and enabled:
		_accumulator += clampf(delta, 0, .2)
		var steps := 0
		while _accumulator+.000001 >= _step_interval and steps < 6:
			_elapsed += _step_interval
			_step(_step_interval)
			_accumulator = maxf(0,_accumulator-_step_interval)
			steps += 1
	if enabled:
		if not paused: _render_serial += 1
		_render(camera)
	statistics["simulation_hz"] = roundi(1.0/_step_interval)
	statistics["actors"] = actors.size()
	statistics["external"] = _external.size()
	statistics["batches"] = _batches.size()
	statistics["graph_revision"] = graph.revision
	statistics["last_update_ms"] = float(Time.get_ticks_usec() - started) / 1000.0

func _reconcile() -> void:
	for i: int in range(actors.size()-1,-1,-1):
		var a: Dictionary = actors[i]
		if not (_choice_continues(a.cell,a.domain,a.previous,int(a.get(&"lane",0)),a.next) or _exit_choice(a.cell,a.domain,a.previous,int(a.get(&"lane",0))) == a.next) or not (_route_has(a.previous,a.domain) or (a.domain in [&"road",&"highway"] and _route_has(a.previous,&"road"))) or (a.domain == &"rail" and (_reserved_rail.has(a.cell) or _reserved_rail.has(a.next))): actors.remove_at(i)
	var cars := 0.0
	var people := 0.0
	var highway_cars := 0.0
	for cell: Vector2i in graph.cells(&"road"):
		var demand := graph.demand(cell)
		if not _upper_road(cell): cars += float(demand.cars) * .5
		people += float(demand.people) * .7
	for cell: Vector2i in graph.cells(&"highway"): highway_cars += float(graph.demand(cell).cars)*.5
	var road_budget := mini(MAX_VEHICLES-24,ceili(cars+highway_cars))
	var road_target := clampi(roundi(road_budget*cars/maxf(.001,cars+highway_cars)),0,road_budget)
	_targets = {&"road": road_target, &"highway":road_budget-road_target, &"pedestrian": mini(MAX_PEDESTRIANS, ceili(people)),
		&"rail": mini(12, ceili(float(riders.get(&"rail",0)) / 80.0)),
		&"water": mini(8, int(graph.facilities.get(Buildings.MARINA,0)))}
	# Each type's pass removes and admits only its own type, so every type's
	# count at the start of its pass equals its count before the first pass.
	var counts: Dictionary = {}
	for a: Dictionary in actors: counts[a.type] = int(counts.get(a.type,0))+1
	# Bounded, deterministic admission weighted by local development/congestion.
	for type: StringName in [&"road", &"highway", &"pedestrian", &"rail", &"water"]:
		var count := int(counts.get(type,0))
		var target: int = _targets[type]
		if count > target:
			for i: int in range(actors.size()-1,-1,-1):
				if count <= target: break
				if actors[i].type == type and not _claims.has(actors[i].id):
					actors.remove_at(i)
					count -= 1
		if count >= target: continue
		var domain: StringName = &"road" if type == &"pedestrian" else type
		var choices := graph.cells(domain)
		if choices.is_empty(): continue
		var admission: Dictionary = {}
		for other: Dictionary in actors: admission[_admission_key(other.type,other.cell,other.next,other.get("lane",0))] = true
		var attempts := mini(2048, choices.size()*4)
		for attempt: int in attempts:
			if count >= target: break
			var cell: Vector2i = choices[posmod(_next_id*37 + attempt*17, choices.size())]
			if type == &"road" and _upper_road(cell): continue
			# Same predicate as graph.allows_pedestrians(cell).
			if type == &"pedestrian" and not (_route_has(cell,&"road") and not _upper_road(cell) and not _ramp(cell)): continue
			if domain == &"rail" and _reserved_rail.has(cell): continue
			var demand := graph.demand(cell)
			if type in [&"road", &"highway", &"pedestrian"] and float(demand.people if type == &"pedestrian" else demand.cars) <= 0: continue
			var adjacent := graph.neighbors(cell,domain)
			if adjacent.is_empty(): continue
			var lane := (_next_id >> 2) & 1 if type == &"highway" else 0
			var next: Vector2i = adjacent[posmod(_next_id,adjacent.size())]
			var previous: Vector2i = adjacent[posmod(_next_id+1,adjacent.size())]
			if domain == &"highway" and graph.highways.routes.has(cell):
				var segments: Array = graph.highways.segments(cell,CityTrafficGraph.INVALID,lane)
				if segments.is_empty(): continue
				var segment: Dictionary = segments[posmod(_next_id,segments.size())]
				next = segment.next
				previous = segment.previous
				if not adjacent.has(next) or not adjacent.has(previous): continue
			if domain == &"rail" and _reserved_rail.has(next): continue
			var admission_key: Variant = _admission_key(type,cell,next,lane)
			if admission.has(admission_key): continue
			admission[admission_key] = true
			var kind: StringName = _choose_kind(type,cell,_next_id)
			actors.append({"id":_next_id,"type":type,"kind":kind,"domain":domain,"cell":cell,"previous":previous,
				"next":next,"lane":lane,"t":float(_next_id%7)/9.0,"variant":_next_id%16,"turns":0,"side":1.0,
				"speed": (.075+float(_next_id%7)*.005) if type == &"pedestrian" else .6 if type == &"water" else 1.2 if type == &"rail" else 1.5 if type == &"highway" else 1.05,
				"length":CityTrafficCatalog.dimensions(kind).z,"stopped":false})
			_next_id += 1
			count += 1

## One admission slot per ramp cell, otherwise per type/cell/next/lane. Common
## values use an integer key; anything else keeps the equivalent string key.
func _admission_key(type: Variant, cell: Vector2i, next: Vector2i, lane: Variant) -> Variant:
	if _ramp(cell): return "ramp"+str(cell)
	if type is StringName and typeof(lane) == TYPE_INT and lane >= 0 and lane < 4 and graph.city.in_bounds(cell.x,cell.y) and graph.city.in_bounds(next.x,next.y):
		return ((_name_id(type)*City.WIDTH*City.HEIGHT+cell.y*City.WIDTH+cell.x)*City.WIDTH*City.HEIGHT+next.y*City.WIDTH+next.x)*4+int(lane)
	return str(type)+str(cell)+str(next)+str(lane)

func _choose_kind(type: StringName, cell: Vector2i, id: int) -> StringName:
	if type == &"pedestrian": return &"pedestrian"
	if type == &"water": return &"sailboat"
	if type == &"rail": return &"train"
	if id%19 == 0 and graph.facilities.has(Buildings.FIRE_STATION): return &"fire_engine"
	if id%17 == 0 and graph.facilities.has(Buildings.POLICE_STATION): return &"police"
	if id%23 == 0 and graph.facilities.has(Buildings.HOSPITAL): return &"ambulance"
	if id%29 == 0 and graph.facilities.has(Buildings.MILITARY_TOWER): return &"military"
	if id%7 == 0 and int(riders.get(&"bus",0)) > 0: return &"bus"
	var demand := graph.demand(cell)
	if int(demand.industrial) > 0 and id%3 == 0: return &"truck"
	if int(demand.commercial) > 0 and id%4 == 0: return &"taxi"
	return [&"car",&"compact",&"sedan",&"pickup",&"van"][id%5]

func _step(delta: float) -> void:
	for i: int in range(actors.size()-1,-1,-1):
		var waiting_actor: Dictionary = actors[i]
		if _claims.has(waiting_actor.id): continue
		waiting_actor.wait = float(waiting_actor.get(&"wait",0.0))+delta if waiting_actor.stopped else 0.0
		if float(waiting_actor.wait) > STUCK_LIMIT and (waiting_actor.type == &"road" or waiting_actor.type == &"highway"): actors.remove_at(i)
	var occupied: Dictionary = {}
	var entries: Dictionary = {}
	var rail_crossings: Dictionary = {}
	var ramps: Dictionary = {}
	var boxes: Dictionary = {}
	var box_exits: Dictionary = {}
	var waiting: Dictionary = {}
	var merging: Dictionary = {}
	for a: Dictionary in actors:
		if _claims.has(a.id): continue
		_record_render_state(a)
		var cell: Vector2i = a.cell
		var ramp := _ramp(cell)
		if ramp: ramps[cell] = a.id
		if a.domain == &"rail":
			rail_crossings[cell] = true
			rail_crossings[a.next] = true
		var lane := int(a.get(&"lane",0)) if a.domain == &"highway" and not ramp else 0
		var key := _lane_key(a.type,a.domain,cell,a.next,lane)
		var occupants: Variant = occupied.get(key)
		if occupants == null: occupied[key] = [a]
		else: occupants.append(a)
		var entry_key := _lane_key(a.type,a.domain,cell,a.previous,lane)
		var entrants: Variant = entries.get(entry_key)
		if entrants == null: entries[entry_key] = [a]
		else: entrants.append(a)
		if a.domain == &"highway" and _ramp(a.previous):
			# A vehicle that merged from a ramp leads the carriageway behind it.
			var joined := graph.highway_segment(cell,a.previous,a.next,lane)
			if joined.has("previous") and joined.previous != a.previous:
				var behind := _lane_key(a.type,a.domain,cell,joined.previous,lane)
				var carriageway: Variant = entries.get(behind)
				if carriageway == null: entries[behind] = [a]
				else: carriageway.append(a)
		if ramp and a.domain == &"road" and float(a.get(&"wait",0.0)) >= MERGE_PATIENCE and graph.continuation_domain(cell,a.next,&"road") == &"highway":
			merging[a.next] = true
		# Pedestrians cross beside the box and never hold it for vehicles.
		if a.domain == &"road" and a.type != &"pedestrian" and _route_degree(cell,&"road") > 2:
			var junction := cell.y*City.WIDTH+cell.x
			if float(a.t) < STOP_LINE:
				var queue: Variant = waiting.get(junction)
				if queue == null: waiting[junction] = [a]
				else: queue.append(a)
			else:
				if float(a.t) < BOX_CLEAR: boxes[junction] = int(boxes.get(junction,0)) | _axis_bit(a)
				var exit := _lane_key(&"road",&"road",cell,a.next)
				box_exits[exit] = int(box_exits.get(exit,0))+1
	var grants: Dictionary = {}
	var ready: Dictionary = {}
	for junction: int in waiting:
		grants[junction] = _junction_grant(waiting[junction],int(boxes.get(junction,0)),entries,box_exits,ready)
	var leaving: Dictionary = {}
	for a: Dictionary in actors:
		if _claims.has(a.id): continue
		if a.domain == &"rail" and _reserved_rail.has(a.next):
			a.stopped = true
			continue
		a.stopped = false
		var speed := float(a.speed)
		if a.type == &"road" or a.type == &"highway": speed *= 1.0 - float(graph.demand(a.cell).congestion) * .6
		var occupants: Variant = occupied.get(_lane_key(a.type,a.domain,a.cell,a.next,int(a.get(&"lane",0)) if a.domain == &"highway" and not _ramp(a.cell) else 0))
		if occupants != null:
			for other: Dictionary in occupants:
				# Different approaches to one exit only share a lane past the stop line.
				if other.previous != a.previous and (float(a.t) < STOP_LINE or float(other.t) < STOP_LINE): continue
				if other.id != a.id and float(other.t) > float(a.t) and float(other.t)-float(a.t) < _following_gap(a,other): speed = 0
		var degree := _route_degree(a.cell,a.domain)
		if a.domain == &"road" and rail_crossings.has(a.cell) and float(a.t)<.22: speed = 0
		# Unpermitted arrivals creep up to the stop line and wait there.
		var limit := INF
		var junction := -1
		if degree > 2 and a.domain == &"road" and float(a.t) < STOP_LINE:
			junction = int(a.cell.y)*City.WIDTH+int(a.cell.x)
			var bit := _axis_bit(a)
			var granted := int(grants.get(junction,0))
			if a.type == &"pedestrian":
				if int(boxes.get(junction,0)) & (3^bit) or granted == 3^bit: limit = STOP_LINE-.001
			elif granted != bit or not _ready_now(a,entries,box_exits,ready): limit = STOP_LINE-.001
		if a.domain == &"highway" and int(a.get(&"lane",0)) == 1 and merging.has(a.next) and float(a.t) < .5: limit = .5
		if float(a.t) > .1:
			var entrants: Variant = entries.get(_lane_key(a.type,a.domain,a.next,a.cell,int(a.get(&"lane",0)) if a.domain == &"highway" and not _ramp(a.next) else 0))
			if entrants != null:
				for other: Dictionary in entrants:
					if other.id != a.id and 1.0-float(a.t)+float(other.t) < _following_gap(a,other): speed = 0; break
		# Slow terminal turns rather than advancing a narrow reversal at street speed.
		if a.previous == a.next and a.type != &"pedestrian": speed = minf(speed,.25)
		var prior_t := float(a.t)
		var segment := graph.highway_segment(a.cell,a.previous,a.next,int(a.get(&"lane",0))) if a.domain==&"highway" else {}
		a.t = maxf(prior_t,minf(prior_t + speed*delta / maxf(.12,float(segment.get("length",1.0))),limit))
		a.stopped = float(a.t) == prior_t
		if junction >= 0 and a.type != &"pedestrian" and float(a.t) >= STOP_LINE:
			boxes[junction] = int(boxes.get(junction,0)) | _axis_bit(a)
			var exit := _lane_key(&"road",&"road",a.cell,a.next)
			box_exits[exit] = int(box_exits.get(exit,0))+1
		if float(a.t) >= 1 and a.domain == &"highway" and not _neighbor_list(a.cell,&"highway").has(a.next):
			# Reached the end of a carriageway that leaves the map: drive off.
			leaving[a.id] = true
			continue
		if float(a.t) >= 1:
			var next_domain := graph.continuation_domain(a.cell,a.next,a.domain)
			var next_lane := 1 if _ramp(a.cell) and next_domain==&"highway" else int(a.get(&"lane",0))
			if _ramp(a.cell) and next_domain==&"highway" and graph.highways.routes.has(a.next):
				var blocked := false
				for merge: Dictionary in graph.highways.segments(a.next,CityTrafficGraph.INVALID,1):
					for ahead: Dictionary in occupied.get(_lane_key(&"highway",&"highway",a.next,merge.next,1),[]):
						if float(ahead.t) < _following_gap(a,ahead): blocked = true
					# Stopped traffic is not about to arrive; it follows the merged vehicle.
					for approaching: Dictionary in occupied.get(_lane_key(&"highway",&"highway",merge.previous,a.next,1),[]):
						if float(approaching.t)>.5 and not approaching.stopped: blocked = true
				if blocked:
					a.t=prior_t; a.stopped=true
					continue
			if next_domain==&"highway" and graph.highways.routes.has(a.next) and graph.traffic_choices(a.next,next_domain,a.cell,next_lane).is_empty() and _exit_choice(a.next,next_domain,a.cell,next_lane) == CityTrafficGraph.INVALID:
				a.t = prior_t
				a.stopped = true
				continue
			if _ramp(a.next):
				if ramps.has(a.next) and int(ramps[a.next]) != int(a.id):
					a.t = prior_t
					a.stopped = true
					continue
				ramps[a.next] = a.id
			var prior: Vector2i = a.cell
			var choices := graph.traffic_choices(a.next,next_domain,prior,next_lane)
			if a.type == &"pedestrian":
				choices = choices.filter(func(cell: Vector2i) -> bool: return graph.allows_pedestrians(cell))
			if next_domain == &"rail":
				choices = choices.filter(func(cell: Vector2i) -> bool: return not _reserved_rail.has(cell))
			if choices.size() > 1: choices.erase(prior)
			if choices.size() > 1 and next_domain == &"highway" and a.next-a.cell != a.cell-a.previous:
				# One turn per interchange: a vehicle that just turned continues
				# straight instead of circling the crossing's four cells.
				var straight: Vector2i = a.next+(a.next-a.cell)
				if choices.has(straight): choices.assign([straight])
			if choices.size() > 1 and not ramps.is_empty():
				# Leave a ramp that is in use for the vehicle already on it.
				var busy := false
				for choice: Vector2i in choices:
					if ramps.has(choice) and _ramp(choice): busy = true; break
				if busy:
					var open := choices.filter(func(cell: Vector2i) -> bool: return not (ramps.has(cell) and _ramp(cell)))
					if not open.is_empty(): choices.assign(open)
			if choices.is_empty() and next_domain == &"highway":
				var exit := _exit_choice(a.next,next_domain,prior,next_lane)
				if exit != CityTrafficGraph.INVALID: choices.append(exit)
			if choices.is_empty():
				a.t = prior_t
				a.stopped = true
				continue
			if a.domain == &"rail" and a.previous == a.next:
				a.reversed = not bool(a.get("reversed",false))
			a.previous = prior
			a.lane = next_lane
			a.domain = next_domain
			if a.type in [&"road",&"highway"]: a.type = a.domain
			a.cell = a.next
			a.turns = int(a.turns)+1
			a.next = choices[posmod(int(a.id)*11+int(a.turns)*7,choices.size())]
			var following_segment := graph.highway_segment(a.cell,a.previous,a.next,int(a.get(&"lane",0))) if a.domain==&"highway" else {}
			a.t = (float(a.t)-1)*maxf(.12,float(segment.get("length",1.0)))/maxf(.12,float(following_segment.get("length",1.0)))
	if not leaving.is_empty():
		for i: int in range(actors.size()-1,-1,-1):
			if leaving.has(actors[i].id): actors.remove_at(i)

## 1 for travel along y, 2 along x: the approach's axis through a junction.
static func _axis_bit(a: Dictionary) -> int:
	return 1 if int(a.cell.x) == int(a.previous.x) else 2

## Don't block the box: a vehicle enters only when its exit lane can take it,
## counting vehicles already in the box bound for the same exit. One standard
## space for every vehicle keeps first-come order fair to buses and trucks.
func _exit_ready(a: Dictionary, entries: Dictionary, box_exits: Dictionary) -> bool:
	var gap := .6
	var room := 2.0
	var ahead: Variant = entries.get(_lane_key(&"road",&"road",a.next,a.cell))
	if ahead != null:
		for other: Dictionary in ahead:
			if other.id != a.id: room = minf(room,float(other.t)+(0.0 if other.stopped else .25))
	room -= float(box_exits.get(_lane_key(&"road",&"road",a.cell,a.next),0))*gap
	return room >= gap

## _exit_ready for a waiting vehicle, reusing the answer `ready` recorded for
## it this tick unless another vehicle has since entered the box for its exit.
func _ready_now(a: Dictionary, entries: Dictionary, box_exits: Dictionary, ready: Dictionary) -> bool:
	var count := int(box_exits.get(_lane_key(&"road",&"road",a.cell,a.next),0))
	var known: Variant = ready.get(a.id)
	if known != null and int(known.x) == count: return known.y != 0
	var result := _exit_ready(a,entries,box_exits)
	ready[a.id] = Vector2i(count,1 if result else 0)
	return result

## The axis bit allowed to enter this junction now, or 0 for none. Only
## arrivals whose exit has room compete; the longest wait wins an empty box.
func _junction_grant(queue: Array, occupied: int, entries: Dictionary, box_exits: Dictionary, ready: Dictionary = {}) -> int:
	if occupied == 3: return 0
	var best := 0
	var best_wait := -1.0
	var best_id := 0
	for a: Dictionary in queue:
		if not _ready_now(a,entries,box_exits,ready): continue
		var bit := _axis_bit(a)
		var wait := float(a.get(&"wait",0.0))
		if occupied != 0 and bit != occupied and wait >= AXIS_HOLD: return 0
		if wait > best_wait or (wait == best_wait and int(a.id) < best_id):
			best = bit
			best_wait = wait
			best_id = int(a.id)
	return occupied if occupied != 0 else best

## A carriageway segment out of `cell` that leads nowhere on the map (its edge
## or an unfinished end). Vehicles follow it to the edge of the cell and leave.
func _exit_choice(cell: Vector2i, domain: StringName, previous: Vector2i, lane: int) -> Vector2i:
	if domain != &"highway" or not graph.highways.routes.has(cell): return CityTrafficGraph.INVALID
	var connected := graph.neighbors(cell,domain)
	for segment: Dictionary in graph.highways.segments(cell,previous,lane):
		if not segment.has("radius") and not connected.has(segment.next): return segment.next
	return CityTrafficGraph.INVALID

## Capture every logic tick, including stopped/offscreen actors. Geometry is
## evaluated lazily for visible actors; multiple ticks retain only the last pair.
func _record_render_state(a: Dictionary) -> void:
	var previous: Variant = a.get(&"_render_previous")
	if previous == null: previous = {}
	previous.cell = a.cell
	previous.previous = a.previous
	previous.next = a.next
	previous.t = a.t
	previous.type = a.type
	previous.domain = a.domain
	previous.lane = a.get(&"lane",0)
	previous.side = a.side
	previous.reversed = a.get(&"reversed",false)
	# Reuse the already sampled current pose when it belongs to this state.
	# Offscreen/catch-up states still sample lazily when they next become visible.
	if _pose_cached(a):
		previous._cached_pose = a._pose
	else: previous.erase(&"_cached_pose")
	previous._recorded_revision = graph.revision
	a._render_previous = previous

func _lane_key(type: StringName, domain: StringName, from: Vector2i, to: Vector2i, lane: int = 0) -> int:
	return (((from.y*City.WIDTH+from.x)*City.WIDTH*City.HEIGHT+to.y*City.WIDTH+to.x)*5+(1 if type == &"pedestrian" else 2 if domain == &"rail" else 3 if domain == &"water" else 4 if domain == &"highway" else 0))*2+lane

func _following_gap(a: Dictionary, b: Dictionary) -> float:
	# Curves are shorter than the straight one-cell parameter. Include both
	# authored lengths and a buffer so buses/trucks cannot overlap compact cars.
	var length := .7
	if a.domain==&"highway":
		var segment := graph.highway_segment(a.cell,a.previous,a.next,int(a.get("lane",0)))
		length = minf(length,float(segment.get("length",length)))
	return maxf(FOLLOW_GAP,((float(a.get("length",.3))+float(b.get("length",.3)))*.5+.10)/maxf(.12,length))

## Pose-cache key for the presentation fields.
func _pose_style(a: Dictionary) -> int:
	return hash([a.type,a.domain,a.get(&"lane",0),a.side,a.get(&"reversed",false)])

func _pose_cached(a: Dictionary) -> bool:
	return a.get(&"_pose_t",-1.0) == a.t and a.get(&"_pose_revision",-1) == graph.revision and a.get(&"_pose_cell") == a.cell and a.get(&"_pose_previous") == a.previous and a.get(&"_pose_next") == a.next and a.get(&"_pose_style") == _pose_style(a)

func actor_pose(a: Dictionary) -> Transform3D:
	var style := hash([a.type,a.domain,a.get(&"lane",0),a.side,a.get(&"reversed",false)])
	if a.get(&"_pose_t",-1.0) == a.t and a.get(&"_pose_revision",-1) == graph.revision and a.get(&"_pose_cell") == a.cell and a.get(&"_pose_previous") == a.previous and a.get(&"_pose_next") == a.next and a.get(&"_pose_style") == style:
		return a._pose
	var segment := graph.highway_segment(a.cell,a.previous,a.next,int(a.get(&"lane",0))) if a.domain==&"highway" else {}
	if segment.has("radius"):
		var angle := lerpf(segment.start,segment.end,float(a.t))
		var p: Vector2 = graph.highways.curve_point(segment.anchor,segment.quarter,segment.radius,angle)
		var ahead: Vector2 = graph.highways.curve_point(segment.anchor,segment.quarter,segment.radius,angle+(.001 if segment.end>segment.start else -.001))
		var position := graph.point(a.cell,a.domain,p-Vector2(a.cell))
		var direction := graph.point(a.cell,a.domain,ahead-Vector2(a.cell))-position
		return _cache_pose(a,Transform3D(Basis.looking_at(direction.normalized(),Vector3.UP),position),style)
	var incoming := Vector2(a.cell-a.previous).normalized()
	var outgoing := Vector2(a.next-a.cell).normalized()
	var lane := .40 if a.type == &"pedestrian" else .13 if a.type in [&"road",&"highway"] else 0.0
	if a.domain==&"highway" and graph.highways.routes.has(a.cell): lane = -.22 if int(a.get(&"lane",0))==0 else .22
	if _ramp(a.cell): lane = 0.0
	var side := float(a.side)
	if a.previous == a.next and a.type != &"pedestrian" and not _ramp(a.cell):
		var angle := PI * clampf(float(a.t),0,1)
		var entry := Vector2(.5,.5)-incoming*.5
		var perpendicular := Vector2(-incoming.y,incoming.x)*side
		var offset: Vector2
		var direction: Vector2
		if a.domain == &"rail":
			# A locomotive backs out without rotating its body at a terminal.
			offset = entry+incoming*(.35*sin(angle))
			direction = incoming * (-1.0 if a.get(&"reversed",false) else 1.0)
		elif a.domain == &"water":
			# A loop with distinct sides avoids the zero-tangent out-and-back cusp.
			offset = entry+incoming*(.4*sin(angle))+perpendicular*(.16*sin(2*angle)*sin(angle))
			direction = incoming*(.4*cos(angle))+perpendicular*(.16*(2*cos(2*angle)*sin(angle)+sin(2*angle)*cos(angle)))
		else:
			offset = entry+incoming*(.4*sin(angle))+perpendicular*(lane*cos(angle))
			direction = incoming*(.4*cos(angle))-perpendicular*(lane*sin(angle))
		var position := graph.point(a.cell,a.domain,offset)
		var tangent := graph.point(a.cell,a.domain,offset+direction.normalized()*.015)-position
		return _cache_pose(a,Transform3D(Basis.looking_at(tangent.normalized(),Vector3.UP),position),style)
	var start := Vector2(.5,.5)-incoming*.5 + Vector2(-incoming.y,incoming.x)*lane*side
	var end := Vector2(.5,.5)+outgoing*.5 + Vector2(-outgoing.y,outgoing.x)*lane*side
	if _ramp(a.previous): start = Vector2(.5,.5)-incoming*.5
	if _ramp(a.next): end = Vector2(.5,.5)+outgoing*.5
	var pivot := Vector2(.5,.5)+(Vector2(-incoming.y,incoming.x)+Vector2(-outgoing.y,outgoing.x))*lane*side*.5
	var t := float(a.t)
	var offset := start.lerp(pivot,t).lerp(pivot.lerp(end,t),t)
	var direction := (pivot-start).lerp(end-pivot,t)
	if direction.length_squared() < .0001: direction = outgoing
	var position := graph.walk_point(a.cell,offset) if a.type==&"pedestrian" else graph.point(a.cell,a.domain,offset)
	var basis := Basis(Vector3.UP,atan2(-direction.x,-direction.y))
	if a.type != &"pedestrian":
		var sample_t := clampf(t+.015,0,1) if t<.985 else t-.015
		var sample_offset := start.lerp(pivot,sample_t).lerp(pivot.lerp(end,sample_t),sample_t)
		var tangent := graph.point(a.cell,a.domain,sample_offset) - position
		if sample_t<t: tangent = -tangent
		if tangent.length_squared()>.000001: basis = Basis.looking_at(tangent.normalized(),Vector3.UP)
	if a.domain == &"rail" and a.get(&"reversed",false): basis = basis.rotated(basis.y,PI)
	return _cache_pose(a,Transform3D(basis,position),style)

func _cache_pose(a: Dictionary, pose: Transform3D, style: int) -> Transform3D:
	a._pose = pose
	a._pose_t = a.t
	a._pose_cell = a.cell
	a._pose_previous = a.previous
	a._pose_next = a.next
	a._pose_revision = graph.revision
	a._pose_style = style
	return pose

func _render(camera: Camera3D) -> void:
	var camera_state: Array = []
	var cache_allowed := false
	if _render_paused:
		camera_state = _camera_state(camera)
		cache_allowed = not _paused_camera_ready or camera_state == _paused_camera_state
		if not cache_allowed:
			# Panning already requires new uploads. Skip actor hashing/snapshotting
			# until a consecutive frame observes the same exact camera/display key.
			_paused_render_state.clear()
		elif not _paused_render_state.is_empty():
			# Public records may change without notification. Full equality is the
			# reuse criterion; it stops at the first difference on a change.
			if _render_state(camera) == _paused_render_state:
				statistics["render_cache_hits"] = int(statistics.get("render_cache_hits",0))+1
				return
	var groups: Dictionary = {}
	var visible_count := 0
	# Camera/display ownership may change between renders. Capture only for this
	# invocation; never retain projection or viewport data across input/resize.
	_render_camera = camera
	_camera_scope = camera != null
	if _camera_scope:
		_camera_position = camera.global_position
		_camera_size = camera.size
		_camera_orthographic = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		_camera_viewport_size = camera.get_viewport().get_visible_rect().size
		_camera_bounds = Rect2(Vector2(-24,-24),_camera_viewport_size+Vector2(48,48))
		_prepare_coarse_cull(camera_state if not camera_state.is_empty() else _camera_state(camera))
	var revision := graph.revision
	var weight := clampf(_accumulator/_step_interval,0,1)
	for a: Dictionary in actors:
		if _claims.has(a.id): continue
		if _camera_scope and _coarse_culled_cell(a.cell,a.domain,camera): continue
		var target := actor_pose(a)
		var previous: Variant = a.get(&"_render_previous")
		var previous_current: bool = previous != null and previous.get(&"_recorded_revision",-1) == revision
		var prior := target
		if previous_current:
			if not previous.has(&"_cached_pose"): previous._cached_pose = actor_pose(previous)
			prior = previous._cached_pose
		var from := prior if prior.origin.distance_squared_to(target.origin)<2.25 else target
		a._render_from = from
		a._render_target = target
		var pose: Transform3D = from.interpolate_with(target,weight)
		# Different tick durations have different presentation latency. Catch up
		# from the displayed pose at a bounded rate rather than dropping that lag
		# in one frame. Pausing also pauses this brief handoff.
		var cadence: Variant = a.get(&"_cadence_pose")
		if cadence != null:
			if a.get(&"_cadence_revision",-1) == revision and a.get(&"_render_serial",-1) >= _render_serial-1 and previous_current:
				var displayed: Transform3D = cadence
				var forward := -displayed.basis.z * (-1.0 if a.domain == &"rail" and a.get(&"reversed",false) else 1.0)
				if a.domain == &"rail" and a.previous == a.next and float(a.t) > .5: forward = -forward
				var position := displayed.origin
				if (pose.origin-position).dot(forward) >= -.00001:
					position = position.move_toward(pose.origin,_render_delta*maxf(.05,float(a.speed)*1.5))
				var rotation := displayed.basis.get_rotation_quaternion()
				var target_rotation := pose.basis.get_rotation_quaternion()
				var angle := rotation.angle_to(target_rotation)
				var basis := Basis(rotation.slerp(target_rotation,minf(1.0,_render_delta*PI/maxf(.000001,angle))))
				a._cadence_pose = Transform3D(basis,position)
				a._cadence_left = maxf(0,float(a._cadence_left)-_render_delta)
				if a._cadence_left == 0 and position.distance_to(pose.origin)<.00001 and angle<.00001:
					a.erase(&"_cadence_pose")
				else: pose = a._cadence_pose
			else: a.erase(&"_cadence_pose")
		a._render_pose = pose
		a._render_serial = _render_serial
		a._render_revision = revision
		# Same predicate as _culled() inside this camera scope.
		if _camera_scope and (camera.is_position_behind(pose.origin) or not _camera_bounds.has_point(camera.unproject_position(pose.origin))): continue
		var low := _camera_scope and (_camera_size > 16.0 if _camera_orthographic else _camera_position.distance_squared_to(pose.origin) > 400.0)
		var variant := int(a.variant) if a.type == &"pedestrian" else 0
		if low: variant %= 4
		var group_key := Vector3i(_name_id(a.kind),variant,1 if low else 0)
		var group: Variant = groups.get(group_key)
		if group == null:
			group = {"name":str(a.kind)+":"+str(variant)+":"+str(low),"kind":a.kind,"variant":variant,"low":low,"poses":[],"custom":[]}
			groups[group_key] = group
		group.poses.append(pose)
		group.custom.append(Color(_elapsed*float(a.speed)*16.0+float(a.id)*.173,0.0 if a.stopped else 1.0,0,0))
		visible_count += 1
	for record: Dictionary in _external:
		if _claims.has(record.presentation_id): continue
		var position: Vector3 = record.presentation_position
		if _culled(position,camera): continue
		var low := camera != null and (_camera_size > 16.0 if _camera_orthographic else _camera_position.distance_squared_to(position) > 400)
		var group_key := Vector3i(_name_id(record.kind),0,1 if low else 0)
		var group: Variant = groups.get(group_key)
		if group == null:
			group = {"name":str(record.kind)+":0:"+str(low),"kind":record.kind,"variant":0,"low":low,"poses":[],"custom":[]}
			groups[group_key] = group
		group.poses.append(Transform3D(Basis(Vector3.UP,record.presentation_yaw),position))
		group.custom.append(Color(0,0,0,0))
		visible_count += 1
	var drawn: Dictionary = {}
	for group: Dictionary in groups.values(): drawn[group.name] = true
	for key: String in _batches:
		if not drawn.has(key): _batches[key].multimesh.visible_instance_count = 0
	for group: Dictionary in groups.values():
		var key: String = group.name
		var instance: MultiMeshInstance3D = _batches.get(key)
		if instance == null:
			var mesh := CityTrafficCatalog.mesh_for(group.kind,group.variant,group.low)
			if mesh == null: continue
			instance = MultiMeshInstance3D.new()
			instance.name = "Traffic_"+key.replace(":","_")
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.use_custom_data = true
			batch.mesh = mesh
			instance.multimesh = batch
			add_child(instance)
			_batches[key] = instance
		var batch := instance.multimesh
		var poses: Array = group.poses
		var custom: Array = group.custom
		if batch.instance_count < poses.size(): batch.instance_count = maxi(16,ceili(float(poses.size())/16)*16)
		batch.visible_instance_count = poses.size()
		for i: int in poses.size():
			batch.set_instance_transform(i,poses[i])
			batch.set_instance_custom_data(i,custom[i])
	_camera_scope = false
	_render_camera = null
	statistics["visible"] = visible_count
	if _render_paused:
		_paused_camera_ready = true
		_paused_camera_state = camera_state
		if cache_allowed:
			# Render mutates metadata/history: detach only its completed state.
			_paused_render_state = _render_state(camera).duplicate(true)

## Coarse culling depends only on a cell's constant route center for this graph
## revision and on the exact camera/display key, so each (domain, cell) verdict
## is evaluated once per key: 0 unknown, 1 kept, 2 culled.
func _prepare_coarse_cull(camera_state: Array) -> void:
	var size := _CULL_DOMAINS.size()*City.WIDTH*City.HEIGHT
	if _cull_results.size() == size and _cull_graph == graph and _cull_revision == graph.revision and camera_state == _cull_camera_state: return
	_cull_results.resize(size)
	_cull_results.fill(0)
	_cull_graph = graph
	_cull_revision = graph.revision
	_cull_camera_state = camera_state

func _coarse_culled_cell(cell: Vector2i, domain: Variant, camera: Camera3D) -> bool:
	var index: Variant = _CULL_DOMAINS.get(domain)
	if index == null or cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT:
		return _coarse_culled(graph.center(cell,domain),camera)
	var slot: int = (int(index)*City.HEIGHT+cell.y)*City.WIDTH+cell.x
	var verdict := _cull_results[slot]
	if verdict == 0:
		verdict = 2 if _coarse_culled(graph.center(cell,domain),camera) else 1
		_cull_results[slot] = verdict
	return verdict == 2

## Route-structure answers are constant for one graph revision: nodes, ramps
## and neighbor lists change only together with a revision increment.
func _sync_route_cache() -> void:
	if _route_graph == graph and _route_revision == graph.revision and _route_ramps.size() == City.WIDTH*City.HEIGHT: return
	_route_graph = graph
	_route_revision = graph.revision
	_route_ramps.resize(City.WIDTH*City.HEIGHT)
	_route_ramps.fill(0)
	_route_degrees.resize(_CULL_DOMAINS.size()*City.WIDTH*City.HEIGHT)
	_route_degrees.fill(0)
	_route_neighbors.resize(_CULL_DOMAINS.size()*City.WIDTH*City.HEIGHT)
	_route_neighbors.fill(null)

## Per-cell road facts: bit 0 known, bit 1 ramp, bit 2 upper road.
func _road_facts(cell: Vector2i) -> int:
	_sync_route_cache()
	var slot := cell.y*City.WIDTH+cell.x
	var known := _route_ramps[slot]
	if known == 0:
		known = 1 | (2 if graph.is_ramp(cell) else 0) | (4 if graph.is_upper_road(cell) else 0)
		_route_ramps[slot] = known
	return known

func _ramp(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT: return graph.is_ramp(cell)
	return _road_facts(cell) & 2 != 0

func _upper_road(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT: return graph.is_upper_road(cell)
	return _road_facts(cell) & 4 != 0

## Per (domain, cell): 0 unknown, 1 absent, otherwise 2 + node degree.
func _route_node(cell: Vector2i, domain: Variant) -> int:
	var index: Variant = _CULL_DOMAINS.get(domain)
	if index == null or cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT: return -1
	_sync_route_cache()
	var slot: int = (int(index)*City.HEIGHT+cell.y)*City.WIDTH+cell.x
	var known := _route_degrees[slot]
	if known == 0:
		known = 2+graph.degree(cell,domain) if graph.has_cell(cell,domain) else 1
		_route_degrees[slot] = known
	return known

func _route_degree(cell: Vector2i, domain: Variant) -> int:
	var node := _route_node(cell,domain)
	if node < 0: return graph.degree(cell,domain)
	return node-2 if node >= 2 else 0

func _route_has(cell: Vector2i, domain: Variant) -> bool:
	var node := _route_node(cell,domain)
	if node < 0: return graph.has_cell(cell,domain)
	return node >= 2

## Read-only membership test equal to traffic_choices(...).has(next). Ordinary
## cells reuse their revision's neighbor list instead of copying it per call.
func _choice_continues(cell: Vector2i, domain: Variant, previous: Vector2i, lane: int, next: Variant) -> bool:
	var index: Variant = _CULL_DOMAINS.get(domain)
	if index == null or domain == &"highway" or cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT:
		return graph.traffic_choices(cell,domain,previous,lane).has(next)
	return _neighbor_list(cell,domain).has(next)

## graph.neighbors(cell, domain), shared for this revision. Read only.
func _neighbor_list(cell: Vector2i, domain: Variant) -> Array:
	var index: Variant = _CULL_DOMAINS.get(domain)
	if index == null or cell.x < 0 or cell.y < 0 or cell.x >= City.WIDTH or cell.y >= City.HEIGHT:
		return graph.neighbors(cell,domain)
	_sync_route_cache()
	var slot: int = (int(index)*City.HEIGHT+cell.y)*City.WIDTH+cell.x
	var list: Variant = _route_neighbors[slot]
	if list == null:
		list = graph.neighbors(cell,domain)
		_route_neighbors[slot] = list
	return list

## Stable small integer for a StringName, used in allocation-free group keys.
static func _name_id(value: StringName) -> int:
	var id: Variant = _name_ids.get(value)
	if id == null:
		id = _name_ids.size()
		_name_ids[value] = id
	return id

func _camera_state(camera: Camera3D) -> Array:
	if camera == null: return []
	return [camera.global_transform,camera.get_camera_transform(),camera.projection,
		camera.size,camera.fov,camera.near,camera.far,camera.keep_aspect,camera.frustum_offset,
		camera.h_offset,camera.v_offset,camera.get_viewport().get_instance_id(),
		camera.get_viewport().get_visible_rect()]

func _render_state(camera: Camera3D) -> Array:
	return [actors,_external,_claims,graph.revision,_elapsed,_accumulator,_step_interval,
		_render_delta,_render_serial,_camera_state(camera)]

func _coarse_culled(point: Vector3, camera: Camera3D) -> bool:
	if camera == null: return false
	var distance := point.distance_to(_camera_position if _camera_scope and camera == _render_camera else camera.global_position)
	if distance<1.5: return false
	if camera.is_position_behind(point): return true
	var size: Vector2 = _camera_viewport_size if _camera_scope and camera == _render_camera else camera.get_viewport().get_visible_rect().size
	var orthographic: bool = _camera_orthographic if _camera_scope and camera == _render_camera else camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var radius := size.y*1.5/((_camera_size if _camera_scope and camera == _render_camera else camera.size) if orthographic else distance)
	var margin := Vector2.ONE*maxf(24,radius)
	return not Rect2(-margin,size+margin*2).has_point(camera.unproject_position(point))

func _culled(point: Vector3, camera: Camera3D) -> bool:
	if camera == null: return false
	if camera.is_position_behind(point): return true
	var screen := camera.unproject_position(point)
	var bounds: Rect2 = _camera_bounds if _camera_scope and camera == _render_camera else Rect2(Vector2(-24,-24),camera.get_viewport().get_visible_rect().size+Vector2(48,48))
	return not bounds.has_point(screen)

func claim_nearby_vehicle(position: Vector3, max_distance: float = 2.0) -> Dictionary:
	var best := nearest_drivable_vehicle(position,max_distance)
	if not best.is_empty(): _claims[best.id] = true
	return best

func nearest_drivable_vehicle(position: Vector3, max_distance: float = .65) -> Dictionary:
	var best: Dictionary = {}
	var distance := max_distance*max_distance
	for a: Dictionary in actors:
		if _claims.has(a.id) or not CityTrafficCatalog.is_drivable(a.kind): continue
		var pose := actor_pose(a)
		var d := pose.origin.distance_squared_to(position)
		if d <= distance:
			distance = d
			best = {"id":a.id,"kind":a.kind,"position":pose.origin,"yaw":pose.basis.get_euler().y}
	for record: Dictionary in _external:
		if _claims.has(record.presentation_id) or not CityTrafficCatalog.is_drivable(record.kind): continue
		var d: float = record.presentation_position.distance_squared_to(position)
		if d <= distance:
			distance = d
			best = {"id":record.presentation_id,"kind":record.kind,"position":record.presentation_position,"yaw":record.presentation_yaw}
	return best

func release_vehicle(claim: Dictionary, position: Vector3) -> void:
	var id := int(claim.get("id",-1))
	_claims.erase(id)
	for i: int in actors.size():
		if actors[i].id != id: continue
		var a: Dictionary = actors[i]
		var cell := graph.nearest_cell(position,a.domain,1.5)
		if cell == CityTrafficGraph.INVALID: actors.remove_at(i); return
		var choices := graph.neighbors(cell,a.domain)
		if choices.is_empty(): actors.remove_at(i); return
		a.cell = cell
		a.previous = choices[0]
		a.next = choices.back()
		if a.domain==&"highway" and graph.highways.routes.has(cell):
			var segments: Array = graph.highways.segments(cell,CityTrafficGraph.INVALID,int(a.get("lane",0)))
			var found := false
			for segment: Dictionary in segments:
				if choices.has(segment.previous) and choices.has(segment.next):
					a.previous = segment.previous
					a.next = segment.next
					found = true
					break
			if not found: actors.remove_at(i); return
		a.t = .5
		a.erase("_render_previous")
		a.erase("_cadence_pose")
		a.erase("_render_pose")
		return

func get_drive_route(kind: StringName, near_position: Vector3) -> Dictionary:
	graph.refresh()
	var domain := CityTrafficCatalog.domain(kind)
	var cell := graph.nearest_cell(near_position,domain,8)
	if domain == &"road":
		var upper := graph.nearest_cell(near_position,&"highway",8)
		if upper != CityTrafficGraph.INVALID and (cell == CityTrafficGraph.INVALID or graph.point(upper,&"highway").distance_squared_to(near_position)<graph.point(cell,&"road").distance_squared_to(near_position)):
			domain = &"highway"
			cell = upper
	if cell == CityTrafficGraph.INVALID: return {}
	var points: Array[Vector3] = []
	var cells: Array[Vector2i] = []
	var previous := CityTrafficGraph.INVALID
	for i: int in 128:
		if cells.has(cell): break
		cells.append(cell)
		points.append(graph.point(cell,domain))
		var choices := graph.traffic_choices(cell,domain,previous,1 if graph.is_ramp(previous) else 0)
		choices.erase(previous)
		if choices.is_empty(): break
		previous = cell
		cell = choices[0]
	return {"points":points,"cells":cells,"domain":domain,"revision":graph.revision}
