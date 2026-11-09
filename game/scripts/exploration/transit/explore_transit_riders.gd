# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Presentation-only passengers for the local Explore train service. They
## wait on each prepared platform, sit in the carriage, and at every stop
## some step off and leave while waiting riders board. They have no collision,
## never consume city or game RNG and are never saved. Explore supplies all time.
class_name ExploreTransitRiders
extends Node3D

const Visual := preload("res://scripts/exploration/transit/transit_rider_visual.gd")
const SPEED := .08
## Riders give way when the player stands this close to their next step.
const YIELD := .045
## A rider kept from the doorway this long stops holding the doors.
const GIVE_UP := 3.0
const LIMIT := 18
const DRAW_RANGE := 2.5
const WAITING := 3
## Carriage seats: longitudinal benches along both walls (train-local tiles).
const SEAT_X := .0906
const SEAT_TOP := .0481
const SEAT_Z := [.1225,.1725,.2225,.2725]
const SEATS := 16
## Standing places in the station frame (x toward the platform, z along it).
const SUBWAY_SPOTS := [Vector2(.21,.16),Vector2(.27,.27),Vector2(.20,-.40),Vector2(.295,.12)]
const RAIL_SPOTS := [Vector2(.22,-.30),Vector2(.28,-.19),Vector2(.21,.22),Vector2(.27,.31),Vector2(.24,-.41)]
const STAND_SPOTS := [Vector3(.036,ExploreTransitTrain.FLOOR_Y,.118),Vector3(-.036,ExploreTransitTrain.FLOOR_Y,-.118)]

var _rng := RandomNumberGenerator.new()
var _people: Array[Dictionary] = []
var _stations: Dictionary = {}
var _station_signature: Array = []
var _train: ExploreTransitTrain
var _serial := 0
var _variant_base := 0
var _service_state := ""
var _stop_key := ""
var _exchange_clock := 0.0
var _spawn_clock := 0.0

func setup(seed_value: int) -> void:
	_rng.seed = seed_value
	_variant_base = _rng.randi_range(0,15)

## Platform crowds follow the stations the transit world actually built.
## Survivors keep their places when a route change keeps their platform.
func sync_stations(stations: Array[Dictionary]) -> void:
	var signature: Array = []
	for station: Dictionary in stations: signature.append(_key(station))
	if signature == _station_signature: return
	_station_signature = signature
	var wanted := {}
	for station: Dictionary in stations: wanted[_key(station)] = station
	for key: String in _stations.keys():
		if not wanted.has(key):
			for person: Dictionary in _people.duplicate():
				if person.get("station","")==key and not person.in_train: _remove(person)
			_stations.erase(key)
	for key: String in wanted:
		if _stations.has(key): continue
		var station: Dictionary = wanted[key]
		_stations[key] = _layout(station)
		var layout: Dictionary = _stations[key]
		var count := _rng.randi_range(2,WAITING)
		for i: int in count: _seat_waiting(layout,_rng.randf()<.5)

## A new carriage starts with a few riders already seated.
func populate_train(train: ExploreTransitTrain) -> void:
	clear_train()
	_train = train
	var count := _rng.randi_range(3,6)
	for i: int in count:
		var spot := _free_cabin_spot(_rng.randf()<.15)
		if spot<0: break
		var person := _spawn(Vector3.ZERO,true)
		if person.is_empty(): break
		_settle_cabin(person,spot)

func clear_train() -> void:
	for person: Dictionary in _people.duplicate():
		if person.in_train: _remove(person)
	# Anyone still walking up to the vanished carriage goes back to wait.
	_resolve_departure()
	_train = null
	_stop_key = ""

func clear() -> void:
	for person: Dictionary in _people: (person.visual as Node3D).free()
	_people.clear()
	_stations.clear()
	_station_signature.clear()
	_train = null
	_stop_key = ""

func count() -> int:
	return _people.size()

## True while a rider is on the way through the doors in either direction:
## a boarder not yet past the door line, or a rider leaving still aboard.
func doorway_busy() -> bool:
	if not is_instance_valid(_train): return false
	for person: Dictionary in _people:
		if person.path.is_empty() or float(person.blocked)>=GIVE_UP: continue
		if person.goal=="board" and (not person.in_train or absf(Vector3(person.local).x)>.10): return true
		if person.goal=="leave" and person.in_train: return true
	return false

func step(delta: float, walker: Node3D, train: ExploreTransitTrain, state: String, station: Dictionary, camera: Camera3D) -> void:
	if not is_finite(delta) or delta<=0.0: return
	if train != _train:
		if is_instance_valid(train): populate_train(train)
		else: clear_train()
	var stopped := state=="boarding" and is_instance_valid(_train) and not station.is_empty()
	if stopped:
		var key := _key(station)+":"+str(_train.global_position.snappedf(.001))
		if key != _stop_key and _stations.has(_key(station)):
			_stop_key = key
			_exchange_clock = 0.0
			_plan_exchange(_stations[_key(station)])
		_exchange_clock += delta
	elif state in ["departing","approaching","braking"] and _service_state=="closing":
		_resolve_departure()
	if state in ["approaching","braking"]: _stop_key = ""
	_service_state = state
	_spawn_clock += delta
	if _spawn_clock>=2.0:
		_spawn_clock = 0.0
		_replenish(camera)
	var feet: Vector3 = walker.global_position if is_instance_valid(walker) and walker.visible else Vector3.INF
	for person: Dictionary in _people.duplicate(): _advance(person,delta,feet,camera)

func states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for person: Dictionary in _people:
		out.append({"id":person.id,"position":(person.visual as Node3D).global_position,"in_train":person.in_train,
			"goal":person.goal,"seated":person.seat>=0.0,"station":person.get("station",""),
			"cabin":person.get("cabin",-1),"moving":not person.path.is_empty(),"visible":(person.visual as Node3D).visible})
	return out

static func _key(station: Dictionary) -> String:
	return str(station.get("anchor",Vector2i(-1,-1)))+"/"+str(station.get("node",Vector3i.ZERO))+"/"+str(Vector3(station.get("normal",Vector3.ZERO)).snappedf(.01))

## Waiting places in the station frame (x toward the platform side, -z along
## the track forward). They avoid the boarding aperture, the street steps or
## lift lane, the bench solid and the name-board totem.
func _layout(station: Dictionary) -> Dictionary:
	var pose := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position)
	var s := float(station.side)
	var floor_y := .025
	var spots: Array[Dictionary] = []
	var subway := bool(station.subway)
	var stand: Array = SUBWAY_SPOTS if subway else RAIL_SPOTS
	for point: Vector2 in stand:
		var z := point.y*s if subway else point.y
		var span: Vector2 = station.get("platform_span",Vector2(-.45,.45))
		if not subway and (z<span.x+.025 or z>span.y-.025): continue
		var at := pose*Vector3(s*point.x,floor_y,z)
		spots.append({"at":at,"front":at,"yaw":_yaw(pose.basis*Vector3(-s,0,-z*.6)),"seat":-1.0,"taken":false})
	if subway:
		# The brass-and-teal bench against the platform wall.
		for z: float in [.35,.40]:
			# Riders stand up and sit down clear of the bench's front edge.
			spots.append({"at":pose*Vector3(s*.305,floor_y,s*z),"front":pose*Vector3(s*.262,floor_y,s*z),"yaw":_yaw(pose.basis*Vector3(-s,0,0)),"seat":.0535-floor_y,"taken":false})
	var aperture := pose*Vector3(s*.20,floor_y,0)
	var exit: Array[Vector3] = []
	if subway:
		var lift := ExploreTransitWorld3D.Elevator.pose_for(station)
		exit = [pose*Vector3(s*.24,floor_y,-s*.30),station.platform+Vector3(station.normal)*.11-lift.basis.z*.30+Vector3.UP*.002,lift*Vector3(.415,.027,-.30)]
	else:
		# Up the street steps to the entrance the player uses.
		var base := float(station.surface)-Vector3(station.position).y
		exit = [pose*Vector3(s*.34,floor_y,0),pose*Vector3(s*.49,base+.0115,0),pose*Vector3(s*.62,base+.002,0)]
	return {"station":station,"key":_key(station),"spots":spots,"aperture":aperture,"exit":exit,"subway":subway}

static func _yaw(direction: Vector3) -> float:
	return atan2(-direction.x,-direction.z)

func _seat_waiting(layout: Dictionary, bench: bool) -> void:
	var spot := _free_spot(layout,bench)
	if spot<0: return
	var data: Dictionary = layout.spots[spot]
	var person := _spawn(data.at,false)
	if person.is_empty(): return
	data.taken = true
	person.station = layout.key
	person.spot = spot
	person.yaw = float(data.yaw)
	person.seat = float(data.seat)
	person.rise = data.front

func _free_spot(layout: Dictionary, prefer_bench: bool) -> int:
	var free: Array[int] = []
	for i: int in layout.spots.size():
		var data: Dictionary = layout.spots[i]
		if data.taken: continue
		if prefer_bench and float(data.seat)>=0.0: return i
		free.append(i)
	if free.is_empty(): return -1
	return free[_rng.randi_range(0,free.size()-1)]

func _spawn(at: Vector3, in_train: bool) -> Dictionary:
	if _people.size()>=LIMIT: return {}
	var visual := Visual.new()
	visual.name = "TransitRider_%02d"%_serial
	# Step through the whole roster so neighbours rarely share an outfit.
	var variant := posmod(_variant_base+_serial*5,16)
	visual.configure(variant)
	add_child(visual)
	var person := {"id":_serial,"visual":visual,"variant":variant,"local":at,"in_train":in_train,"yaw":0.0,"seat":-1.0,
		"path":[],"goal":"","spot":-1,"cabin":-1,"station":"","blocked":0.0,"delay":0.0,"linger":0.0,"rise":at}
	_serial += 1
	_people.append(person)
	return person

func _remove(person: Dictionary) -> void:
	if _stations.has(person.get("station","")) and int(person.spot)>=0:
		_stations[person.station].spots[int(person.spot)].taken = false
	(person.visual as Node3D).free()
	_people.erase(person)

func _free_cabin_spot(standing: bool) -> int:
	var taken := {}
	for person: Dictionary in _people: if int(person.cabin)>=0: taken[int(person.cabin)] = true
	var free: Array[int] = []
	var first := SEATS if standing else 0
	var last := SEATS+STAND_SPOTS.size() if standing else SEATS
	for i: int in range(first,last): if not taken.has(i): free.append(i)
	if free.is_empty() and standing: return _free_cabin_spot(false)
	if free.is_empty(): return -1
	return free[_rng.randi_range(0,free.size()-1)]

## Train-local position, facing and cushion height of carriage place `index`.
static func cabin_place(index: int) -> Dictionary:
	if index>=SEATS:
		var at: Vector3 = STAND_SPOTS[index-SEATS]
		return {"at":at,"yaw":_yaw(Vector3(-signf(at.x),0,0)),"seat":-1.0,"front":at}
	# Sixteen places: two four-seat benches on each wall.
	var side := 1.0 if index<SEATS/2 else -1.0
	var j := index%(SEATS/2)
	var z: float = float(SEAT_Z[j%4])*(1.0 if j<4 else -1.0)
	var at := Vector3(side*SEAT_X,ExploreTransitTrain.FLOOR_Y,z)
	return {"at":at,"yaw":_yaw(Vector3(-side,0,0)),"seat":SEAT_TOP-ExploreTransitTrain.FLOOR_Y,"front":Vector3(side*.05,ExploreTransitTrain.FLOOR_Y,z)}

func _settle_cabin(person: Dictionary, spot: int) -> void:
	var place := cabin_place(spot)
	person.cabin = spot
	person.in_train = true
	person.local = place.at
	person.yaw = float(place.yaw)
	person.seat = float(place.seat)
	person.rise = place.front
	person.station = ""
	person.spot = -1
	person.goal = ""

## Up to three riders step off, then up to three waiting riders board.
func _plan_exchange(layout: Dictionary) -> void:
	if not is_instance_valid(_train): return
	var door := _train.door_side
	var threshold := Vector3(door*.135,ExploreTransitTrain.FLOOR_Y,0)
	var entry := Vector3(door*.085,ExploreTransitTrain.FLOOR_Y,0)
	var riding: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for person: Dictionary in _people:
		if person.in_train and person.path.is_empty() and int(person.cabin)>=0: riding.append(person)
		elif person.get("station","")==layout.key and person.path.is_empty() and not person.in_train: waiting.append(person)
	var leaving := mini(riding.size(),_rng.randi_range(1 if riding.size()>4 else 0,3))
	for i: int in leaving:
		var person: Dictionary = riding.pop_at(_rng.randi_range(0,riding.size()-1))
		var place := cabin_place(int(person.cabin))
		var front: Vector3 = place.front
		var path: Array = [{"p":front,"train":true},{"p":Vector3(entry.x*.4,front.y,clampf(front.z,-.05,.05)),"train":true},
			{"p":entry,"train":true},{"p":threshold,"train":true},{"p":layout.aperture,"train":false}]
		for point: Vector3 in layout.exit: path.append({"p":point,"train":false})
		person.cabin = -1
		person.goal = "leave"
		person.path = path
		person.delay = float(i)*.7
	var boarding := mini(waiting.size(),_rng.randi_range(1,3))
	for i: int in boarding:
		var spot := _free_cabin_spot(_rng.randf()<.2)
		if spot<0: break
		var person: Dictionary = waiting.pop_at(_rng.randi_range(0,waiting.size()-1))
		var place := cabin_place(spot)
		var front: Vector3 = layout.spots[int(person.spot)].front if int(person.spot)>=0 else person.local
		_release_spot(person)
		person.cabin = spot
		person.goal = "board"
		# A bench sitter stays seated until its turn comes to stand up.
		person.path = [{"p":front,"train":false},{"p":layout.aperture,"train":false},{"p":threshold,"train":true},{"p":entry,"train":true},
			{"p":Vector3(entry.x*.4,entry.y,clampf(Vector3(place.front).z,-.05,.05)),"train":true},{"p":place.front,"train":true}]
		person.delay = 1.4+float(leaving)*.7+float(i)*.9

func _release_spot(person: Dictionary) -> void:
	if _stations.has(person.get("station","")) and int(person.spot)>=0:
		_stations[person.station].spots[int(person.spot)].taken = false
	person.spot = -1

## Doors have closed: a rider still on the wrong side of them goes back.
func _resolve_departure() -> void:
	for person: Dictionary in _people.duplicate():
		if person.goal=="board" and not person.in_train:
			person.cabin = -1
			var layout: Dictionary = _stations.get(person.get("station",""),{})
			var spot := _free_spot(layout,false) if not layout.is_empty() else -1
			if spot<0:
				_remove(person)
				continue
			layout.spots[spot].taken = true
			person.spot = spot
			person.goal = "wait"
			person.path = [{"p":layout.spots[spot].front,"train":false}]
			person.blocked = 0.0
		elif person.goal=="leave" and person.in_train:
			var spot := _free_cabin_spot(false)
			if spot<0:
				_remove(person)
				continue
			person.cabin = spot
			person.goal = "sit"
			person.path = [{"p":cabin_place(spot).front,"train":true}]
			person.blocked = 0.0

## New riders arrive from the street or lift lobby, out of the player's view.
func _replenish(camera: Camera3D) -> void:
	for key: String in _stations:
		var layout: Dictionary = _stations[key]
		var present := 0
		for person: Dictionary in _people:
			if person.get("station","")==key and person.goal not in ["leave","gone"]: present += 1
		if present>=WAITING or _rng.randf()<.45: continue
		var origin: Vector3 = layout.exit[layout.exit.size()-1]
		if is_instance_valid(camera) and camera.is_inside_tree() and camera.is_position_in_frustum(origin+Vector3.UP*.05): continue
		var spot := _free_spot(layout,false)
		if spot<0: continue
		var person := _spawn(origin,false)
		if person.is_empty(): return
		layout.spots[spot].taken = true
		person.station = key
		person.spot = spot
		person.goal = "wait"
		var path: Array = []
		for i: int in range(layout.exit.size()-2,-1,-1): path.append({"p":layout.exit[i],"train":false})
		path.append({"p":layout.spots[spot].front,"train":false})
		person.path = path

func _world(person: Dictionary) -> Vector3:
	if person.in_train and is_instance_valid(_train): return _train.global_transform*Vector3(person.local)
	return person.local

func _advance(person: Dictionary, delta: float, feet: Vector3, camera: Camera3D) -> void:
	var visual: Node3D = person.visual
	if person.in_train and not is_instance_valid(_train):
		_remove(person)
		return
	var speed := 0.0
	if person.goal=="gone":
		person.linger = float(person.linger)+delta
		var seen := is_instance_valid(camera) and camera.is_inside_tree() and camera.is_position_in_frustum(_world(person)+Vector3.UP*.05) \
			and camera.global_position.distance_squared_to(_world(person))<=DRAW_RANGE*DRAW_RANGE
		if not seen or float(person.linger)>=20.0:
			_remove(person)
			return
	if not person.path.is_empty():
		person.delay = maxf(0.0,float(person.delay)-delta)
		if float(person.delay)<=0.0: speed = _walk(person,delta,feet)
		if person.path.is_empty(): _arrive(person)
		if not _people.has(person): return
	var at := _world(person)
	var basis := Basis(Vector3.UP,float(person.yaw))
	if person.in_train and is_instance_valid(_train): basis = _train.global_basis*basis
	visual.global_transform = Transform3D(basis.orthonormalized(),at)
	var near := not is_instance_valid(camera) or not camera.is_inside_tree() or camera.global_position.distance_squared_to(at)<=DRAW_RANGE*DRAW_RANGE
	visual.visible = near
	var seat := float(person.seat)
	visual.advance(delta,speed,seat,near)

func _walk(person: Dictionary, delta: float, feet: Vector3) -> float:
	var target: Dictionary = person.path[0]
	if bool(target.train) != bool(person.in_train):
		if not is_instance_valid(_train): return 0.0
		var world := _world(person)
		person.in_train = bool(target.train)
		person.local = _train.global_transform.affine_inverse()*world if person.in_train else world
	if float(person.seat)>=0.0:
		# Standing up from a seat happens in place at its front edge.
		person.seat = -1.0
		person.local = person.rise
		return 0.0
	var goal: Vector3 = target.p
	var here: Vector3 = person.local
	var offset := goal-here
	var flat := Vector2(offset.x,offset.z)
	var step := minf(offset.length(),SPEED*delta)
	var next := here+offset.normalized()*step if offset.length()>.00001 else goal
	var next_world: Vector3 = _train.global_transform*next if person.in_train and is_instance_valid(_train) else next
	var gap := Vector2(feet.x-next_world.x,feet.z-next_world.z).length() if feet.is_finite() else INF
	if gap<YIELD and absf(feet.y-next_world.y)<.12:
		person.blocked = float(person.blocked)+delta
		return 0.0
	person.blocked = 0.0
	if flat.length()>.001:
		var facing := Vector3(flat.x,0,flat.y)
		person.yaw = _yaw(facing)
	person.local = next
	if next.distance_to(goal)<=.0005: person.path.pop_front()
	return SPEED

func _arrive(person: Dictionary) -> void:
	match String(person.goal):
		"leave":
			# Leave out of sight: in the lift lobby or the station entrance a
			# rider simply waits a moment while the player is looking.
			person.goal = "gone"
			person.linger = 0.0
		"board", "sit":
			_settle_cabin(person,int(person.cabin))
		"wait":
			var layout: Dictionary = _stations.get(person.get("station",""),{})
			if not layout.is_empty() and int(person.spot)>=0:
				var data: Dictionary = layout.spots[int(person.spot)]
				person.yaw = float(data.yaw)
				person.seat = float(data.seat)
				person.local = data.at
				person.rise = data.front
			person.goal = ""
