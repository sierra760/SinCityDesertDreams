# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Transient casino visitors. The hall supplies geometry; Explore supplies all
## time. This presentation never consumes city/game RNG or transacts money.
extends Node3D

const Visual := preload("res://scripts/exploration/resorts/casino_patron_visual.gd")
const GRID := .04
const RADIUS := .023
const SEAT_SPACE := .039
const PERSONAL_SPACE := .08
const SPEED := .075
var _plan: Dictionary
var _floor: Rect2
var _boxes: Array[Rect2] = []
var _seats: Array[Vector2] = []
var _grid := AStarGrid2D.new()
var _destinations: Array[Dictionary] = []
var _people: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _player := Vector2(1000,1000)
var _seed_value := 0
var _serial := 0
var _budget := 0

func build(plan: Dictionary, seed_value: int) -> void:
	_plan = plan
	_rng.seed = seed_value
	_seed_value = seed_value
	_budget = clampi(int(plan.get("patron_count",3 if plan.key == ResortThemes.STORE_KEY else 16)),0,16)
	var bounds: AABB = plan.bounds
	_floor = Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(-.035)
	# Visitors stay on the casino floor; the vestibule is kept for arrivals.
	if plan.key != ResortThemes.STORE_KEY: _floor.end.y = minf(_floor.end.y,float(plan.get("floor_front",21.3/16.0)))
	for obstacle: Dictionary in plan.obstacles:
		_boxes.append(Rect2(Vector2(obstacle.center)-Vector2(obstacle.half),Vector2(obstacle.half)*2).grow(RADIUS))
	for table: Dictionary in plan.tables: _seats.append(Vector2(table.seat.x,table.seat.z))
	_build_grid()
	_build_destinations()

## Retain every surviving model, route, seat and animation clock. Destinations
## belong only to _people, so removing the tail releases its reservations.
func set_count(count: int) -> void:
	count = clampi(count,0,_budget)
	while _people.size()>count:
		var removed: Dictionary = _people.pop_back()
		(removed.visual as Node3D).free()
	if _destinations.is_empty() or count<=_people.size(): return
	var groups: Dictionary = {}
	for i: int in _destinations.size():
		var game: StringName = _destinations[i].game
		if not groups.has(game): groups[game] = []
		groups[game].append(i)
	var games := groups.keys()
	var previous := _people.size()
	while _people.size()<count:
		var i := _serial
		var game: StringName = games[i%games.size()]
		var choices: Array = groups[game]
		var choice := int(choices[(i/games.size())%choices.size()])
		choice = _free_destination(choice)
		if choice<0: break
		_serial += 1
		var goal: Dictionary = _destinations[choice]
		var visual := Visual.new()
		visual.name = "Visitor_%02d"%i
		visual.configure(posmod(i+_seed_value,16))
		add_child(visual)
		var person := {"visual":visual,"variant":posmod(i+_seed_value,16),"position":goal.position,
			"yaw":goal.yaw,"mode":"playing","game":goal.game,"seated":goal.seated,"target":choice,
			"remaining":4.0+_people.size()*1.8,"clock":0.0,"path":PackedVector2Array(),"blocked":0.0,"visits":0}
		_people.append(person)
		_place(person,0.0,0.0)
	# Only new visitors change games on arrival; survivors are untouched.
	for i: int in range(maxi(previous,count-4),_people.size()):
		if count>3: _choose_game(_people[i])

func _clear(point: Vector2) -> bool:
	if not _floor.has_point(point): return false
	for box: Rect2 in _boxes:
		if box.has_point(point): return false
	for seat: Vector2 in _seats:
		if point.distance_squared_to(seat)<SEAT_SPACE*SEAT_SPACE: return false
	return true

func _segment_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1,ceili(a.distance_to(b)/.012))
	for i: int in range(steps+1):
		if not _clear(a.lerp(b,float(i)/steps)): return false
	return true

func _build_grid() -> void:
	var start := Vector2i(ceili(_floor.position.x/GRID),ceili(_floor.position.y/GRID))
	var end := Vector2i(floori(_floor.end.x/GRID),floori(_floor.end.y/GRID))
	_grid.region = Rect2i(start,end-start+Vector2i.ONE)
	_grid.cell_size = Vector2.ONE*GRID
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.update()
	for y: int in range(start.y,end.y+1):
		for x: int in range(start.x,end.x+1):
			var cell := Vector2i(x,y)
			var solid := not _clear(Vector2(cell)*GRID)
			_grid.set_point_solid(cell,solid)

func _nearest(point: Vector2, escaping_player: bool = false) -> Vector2i:
	var center := Vector2i(roundi(point.x/GRID),roundi(point.y/GRID))
	var best := Vector2i(10000,10000)
	var distance := INF
	# Ordinary connectors touch only the nearby cells. A player standing on
	# a visitor may require a wider ring, still bounded to 5.1 m.
	for radius: int in 9:
		for y: int in range(center.y-radius,center.y+radius+1):
			for x: int in range(center.x-radius,center.x+radius+1):
				if radius>0 and abs(x-center.x)!=radius and abs(y-center.y)!=radius: continue
				var cell := Vector2i(x,y)
				if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell): continue
				var at := Vector2(cell)*GRID
				var gap := at.distance_squared_to(point)
				if gap>=distance or not _segment_clear(point,at): continue
				if escaping_player and not _player_connector(point,at): continue
				distance = gap
				best = cell
		if distance<INF: return best
	return best

func _player_connector(from: Vector2, to: Vector2) -> bool:
	var relative := from-_player
	var motion := to-from
	if motion.length_squared()<.00000001: return true
	var t := clampf(-relative.dot(motion)/motion.length_squared(),0,1)
	var closest := (relative+motion*t).length_squared()
	if relative.length_squared()<PERSONAL_SPACE*PERSONAL_SPACE:
		# A player can step onto this nonblocking visitor. Let them sidestep
		# along a cabinet edge when a strictly radial escape is obstructed,
		# but never cross through the player or end closer than they began.
		return closest>=relative.length_squared()*.75 and to.distance_squared_to(_player)>relative.length_squared()
	return closest>=PERSONAL_SPACE*PERSONAL_SPACE

func _build_destinations() -> void:
	for table: Dictionary in _plan.tables:
		var offsets: Array[float] = []
		if int(table.count)>1:
			for i: int in int(table.count): offsets.append((i-(int(table.count)-1)*.5)*float(table.half.x)*2/int(table.count))
		else:
			var side := .043 if _plan.key == ResortThemes.STORE_KEY else .065
			offsets.append(-side)
			offsets.append(side)
		for offset: float in offsets:
			var seat: Vector3 = table.seat+table.pose.basis*Vector3(offset,0,0)
			var point := Vector2(seat.x,seat.z)
			if not _clear(point): continue
			var cell := _nearest(point)
			if not _grid.is_in_boundsv(cell): continue
			var facing: Vector3 = table.pose.origin-seat
			# A bank visitor faces their individual cabinet, not the bank centre.
			if int(table.count)>1: facing = table.pose.basis*Vector3.FORWARD
			seat.y = _height(point)
			_destinations.append({"position":seat,"game":table.game,"yaw":atan2(-facing.x,-facing.z),"cell":cell,
				"seated":table.game == &"slots" and int(table.count)>1})

func _height(point: Vector2) -> float:
	var dais: Dictionary = _plan.get("dais",{})
	if not dais.is_empty():
		var box := Rect2(Vector2(dais.center)-Vector2(dais.half),Vector2(dais.half)*2)
		if box.has_point(point): return float(dais.height)
		# The authored circular roulette platform is 3.2 m in radius, .15 m high.
		if point.distance_to(Vector2(0,2.0/16.0))<3.2/16.0: return .15/16.0
	return 0.0

func _free_destination(start: int, except: Dictionary = {}) -> int:
	for offset: int in _destinations.size():
		var index := posmod(start+offset,_destinations.size())
		var point: Vector3 = _destinations[index].position
		if Vector2(point.x,point.z).distance_to(_player)<PERSONAL_SPACE: continue
		var busy := false
		for person: Dictionary in _people:
			if person == except: continue
			var other: Vector3 = _destinations[int(person.target)].position
			if point.distance_to(other)<.04: busy = true; break
		if not busy: return index
	return -1

func _route(from: Vector2, destination: Dictionary) -> PackedVector2Array:
	var blocked: Array[Vector2i] = []
	# Temporarily route around the player. Restore the immutable floor graph
	# before the next visitor's query; the player's cell is never a saved edit.
	var center := Vector2i(roundi(_player.x/GRID),roundi(_player.y/GRID))
	for y: int in range(center.y-3,center.y+4):
		for x: int in range(center.x-3,center.x+4):
			var cell := Vector2i(x,y)
			if _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell) and (Vector2(cell)*GRID).distance_to(_player)<PERSONAL_SPACE+GRID*.5:
				_grid.set_point_solid(cell,true)
				blocked.append(cell)
	var start := _nearest(from,true)
	var end: Vector2i = destination.cell
	var path := PackedVector2Array()
	if _grid.is_in_boundsv(start) and not _grid.is_point_solid(end):
		path = _grid.get_point_path(start,end)
	for cell: Vector2i in blocked: _grid.set_point_solid(cell,false)
	if path.is_empty(): return path
	var goal: Vector3 = destination.position
	path.append(Vector2(goal.x,goal.z))
	# Every link is checked against continuous capsule-clear geometry. A grid
	# cannot silently cut across a reserved seat between two valid samples.
	var previous := from
	for at: Vector2 in path:
		if not _segment_clear(previous,at) or not _player_connector(previous,at): return PackedVector2Array()
		previous = at
	return path

func _choose_game(person: Dictionary) -> void:
	var first := _rng.randi_range(0,_destinations.size()-1)
	for attempt: int in mini(12,_destinations.size()):
		var index := _free_destination(first+attempt,person)
		if index<0 or index==int(person.target): continue
		var point: Vector3 = person.position
		var path := _route(Vector2(point.x,point.z),_destinations[index])
		if path.is_empty(): continue
		person.target = index
		person.path = path
		person.mode = "walking"
		person.blocked = 0.0
		return
	person.remaining = 1.0
	person.blocked = 0.0

## Local feet and game clocks for metrics/review; callers receive copies.
func states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for person: Dictionary in _people:
		result.append({"position":person.position,"yaw":person.yaw,"mode":person.mode,"game":person.game,
			"variant":person.variant,"clock":person.clock,"visits":person.visits})
	return result

func step(delta: float, player_feet: Vector3) -> void:
	if not is_visible_in_tree() or not is_finite(delta) or delta<=0.0: return
	var dt := minf(delta,.1)
	_player = Vector2(player_feet.x,player_feet.z)
	for person: Dictionary in _people:
		person.clock += dt
		var speed := 0.0
		var feet: Vector3 = person.position
		var point := Vector2(feet.x,feet.z)
		if person.mode == "playing":
			person.remaining -= dt
			if person.remaining<=0 or point.distance_to(_player)<PERSONAL_SPACE: _choose_game(person)
		if person.mode == "walking":
			var path: PackedVector2Array = person.path
			if not path.is_empty():
				var toward := path[0]-point
				var next := point+toward.limit_length(SPEED*dt)
				var player_gap := next.distance_to(_player)
				var blocked := player_gap<PERSONAL_SPACE and not _player_connector(point,path[0])
				for other: Dictionary in _people:
					if other == person: continue
					var at: Vector3 = other.position
					var gap := next.distance_to(Vector2(at.x,at.z))
					if gap<.034 and gap<point.distance_to(Vector2(at.x,at.z)): blocked = true
				if blocked:
					person.blocked += dt
					if person.blocked>1.0: _choose_game(person)
				else:
					person.blocked = 0.0
					var motion := next-point
					if motion.length_squared()>.00000001:
						person.yaw = lerp_angle(float(person.yaw),atan2(-motion.x,-motion.y),minf(dt*9,1.0))
						speed = motion.length()/dt
					person.position = Vector3(next.x,_height(next),next.y)
					if next.distance_to(path[0])<.00001:
						path.remove_at(0)
						person.path = path
			if (person.path as PackedVector2Array).is_empty():
				var goal: Dictionary = _destinations[int(person.target)]
				person.position = goal.position
				person.yaw = goal.yaw
				person.mode = "playing"
				person.game = goal.game
				person.seated = goal.seated
				person.remaining = _rng.randf_range(10.0,24.0)
				person.visits += 1
				speed = 0.0
		_place(person,dt,speed)

func _place(person: Dictionary, delta: float, speed: float) -> void:
	var visual: Node3D = person.visual
	visual.position = person.position
	visual.rotation.y = person.yaw
	visual.advance(delta,speed,person.game,person.mode == "playing",person.seated)
