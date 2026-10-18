# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Continuous flight for the port aircraft the 3D view draws.
##
## The port simulation moves a plane a few tiles once a day along eight
## headings. This flies a path through those daily points instead: a plane
## rolls down the runway and climbs out, banks through its turns, swings round
## at the map edge, and on its return flies a circuit onto the runway's
## extended centre line, touches down and rolls out to a stop. The helicopter
## lifts off its pad, leans into its travel and sets down when it has nowhere
## left to go. Distances are tiles and time is simulated days, so a flight
## keeps the same shape at every game speed.
##
## Presentation only: it reads the city and the simulation's records and never
## changes either, nor uses the simulation's random stream.
class_name CityAirFlights
extends RefCounted

const KINDS: Array[StringName] = [&"plane", &"helicopter"]
## Integration step, in days; frame time is split into steps no longer than it.
const STEP_DAYS := 0.02
const MAX_STEPS := 256
## How far (tiles) a record may move in one day and still be the same aircraft.
const DAILY_REACH := 4.8

## Airliner speeds in tiles a day. The simulation flies three steps a day, so
## between 3 (straight) and 4.24 (diagonal) tiles.
const PLANE_MIN_AIR := 2.2
const PLANE_MAX := 5.2
const PLANE_ACCEL := 3.0
## About a plane and a half of runway before it lifts off.
const PLANE_TAKEOFF_ACCEL := 2.6
const PLANE_ROTATE := 2.4
const PLANE_LEAVE := 3.4
## Turn rate (radians a day) and how quickly it can change.
const PLANE_TURN := 2.4
const PLANE_TURN_ACCEL := 10.0
const PLANE_TURN_GAIN := 2.6
const PLANE_GROUND_TURN := 0.8
## Steepest climb and descent, as rise over distance flown.
const PLANE_CLIMB := 0.32
const PLANE_DESCENT := 0.42
const PLANE_MAX_BANK := 0.56
const PLANE_MAX_PITCH := 0.26
## Bank angle is atan(speed × turn rate / BANK_GRAVITY): a coordinated turn.
const BANK_GRAVITY := 14.0
## The plane follows the path through its daily points and the next two days
## the simulation will fly, aiming LOOKAHEAD tiles ahead of its own place on
## it and keeping about FOLLOW_GAP tiles behind the day's point.
const LOOKAHEAD := 1.3
## Heading home the simulation zigzags between two neighbouring headings day
## by day; a longer look ahead flies the line between them instead of weaving.
const RETURN_LOOKAHEAD := 3.2
const FOLLOW_GAP := 0.3
## Lowest a flying plane goes over the ground away from the runway.
const CLEARANCE := 0.5

## Landing circuit: the straight final before the threshold, the point the
## circuit aims for further out, the glide path and the approach speeds.
const FINAL := 4.0
const CIRCUIT := 6.5
const GLIDE := 0.28
const LINE_LOOKAHEAD := 1.6
const APPROACH_SPEED := 2.9
const TOUCHDOWN_SPEED := 2.3
## Touchdown needs the wheels near the centre line and the nose along it; a
## plane still high at the threshold, or not lined up, goes round again.
const GO_AROUND_HEIGHT := 0.35
const TOUCHDOWN_LATERAL := 0.3
const TOUCHDOWN_FACING := 0.985
const MIN_BRAKE := 1.2
## Days a plane waits on the runway once stopped, before it leaves the view.
const PARK_DAYS := 0.5
## A plane with no airport left flies on and leaves after this long.
const LEAVE_DAYS := 6.0
const RUNWAY_SEARCH := 3
## A circuit that has not ended in a landing after this long is abandoned.
const APPROACH_DAYS := 20.0
## The simulation's headings 0..7, clockwise from north, as tile steps.
const HEADING_STEP: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

const HELI_MAX := 3.2
const HELI_ACCEL := 4.0
const HELI_TURN := 3.5
const HELI_CLIMB := 1.6
const HELI_MAX_TILT := 0.3

const MODE_ROLL := &"roll"
const MODE_AIR := &"air"
const MODE_APPROACH := &"approach"
const MODE_ROLLOUT := &"rollout"
const MODE_PARKED := &"parked"
const MODE_LEAVE := &"leave"
const MODE_DESCEND := &"descend"


class Flight:
	var serial := 0
	var kind: StringName = &"plane"
	var position := Vector3.ZERO
	## Godot yaw of the nose: 0 faces north (-Z), increasing turns left.
	var yaw := 0.0
	var yaw_rate := 0.0
	## Planes: forward speed. Helicopters use `velocity`.
	var speed := 0.0
	var velocity := Vector2.ZERO
	var vertical := 0.0
	var bank := 0.0
	var pitch := 0.0
	var mode: StringName = &"air"
	## The simulation record this flight follows.
	var source := Vector2i(-1, -1)
	var altitude := 0
	var frame := -1
	var heading := 0
	var phase: StringName = &""
	var live := true
	var matched := false
	## The daily point is approached over one day, from where it was drawn.
	var carrot_from := Vector3.ZERO
	var carrot_to := Vector3.ZERO
	var carrot_t := 1.0
	var runway: Dictionary = {}
	var established := false
	var timer := 0.0


var flights: Array[Flight] = []
var _next_serial := 0


func clear() -> void:
	flights.clear()


## Follow this frame's records and advance every flight by `delta_days`.
## Records are CityEntityRecords.normalize() output of KINDS.
func update(city: City, records: Array[Dictionary], delta_days: float) -> void:
	if city == null:
		flights.clear()
		return
	_match(city, records)
	if not is_finite(delta_days) or delta_days <= 0.0:
		return
	var steps := mini(MAX_STEPS, ceili(delta_days / STEP_DAYS))
	var h := delta_days / float(steps)
	for _i: int in steps:
		for i: int in range(flights.size() - 1, -1, -1):
			if not _advance(city, flights[i], h):
				flights.remove_at(i)


## The rendered orientation: heading, then nose pitch, then bank.
static func basis_of(flight: Flight) -> Basis:
	return Basis(Vector3.UP, flight.yaw) * Basis(Vector3.RIGHT, flight.pitch) * Basis(Vector3.BACK, flight.bank)


# ── Records ──────────────────────────────────────────────────────────────

func _match(city: City, records: Array[Dictionary]) -> void:
	for flight: Flight in flights:
		flight.matched = false
	var pending: Array[Dictionary] = []
	for record: Dictionary in records:
		if record.kind in KINDS:
			pending.append(record)
	# Pair each record with the flight it most plausibly continues. Without
	# stable ids, a flight's last tile and day counter identify it; the closest
	# plausible pair is taken first, so two aircraft never trade places.
	while not pending.is_empty():
		var best_cost := INF
		var best_record := -1
		var best_flight: Flight = null
		for r: int in pending.size():
			var record: Dictionary = pending[r]
			for flight: Flight in flights:
				if flight.matched or not flight.live or flight.kind != record.kind:
					continue
				var cost := _match_cost(flight, record)
				if cost < best_cost:
					best_cost = cost
					best_record = r
					best_flight = flight
		if best_flight == null:
			break
		_follow(city, best_flight, pending[best_record])
		pending.remove_at(best_record)
	for record: Dictionary in pending:
		flights.append(_spawn(city, record))
	for flight: Flight in flights:
		if flight.matched or not flight.live:
			continue
		flight.live = false
		_source_gone(city, flight)


static func _match_cost(flight: Flight, record: Dictionary) -> float:
	var days := 1
	var frame := int(record.frame)
	if frame >= 0 and flight.frame >= 0:
		if frame < flight.frame:
			return INF
		days = maxi(1, frame - flight.frame)
	var distance := Vector2(record.pos).distance_to(Vector2(flight.source))
	if distance > 0.5 + DAILY_REACH * float(days):
		return INF
	return distance + 0.01 * float(days)


func _follow(city: City, flight: Flight, record: Dictionary) -> void:
	flight.matched = true
	var tile := Vector2i(record.pos)
	var altitude := int(record.altitude)
	var phase: StringName = record.get("phase", &"")
	var moved := tile != flight.source or altitude != flight.altitude
	var landing := phase == &"land" or (phase == &"" and tile == flight.source and altitude < flight.altitude)
	flight.frame = int(record.frame)
	flight.heading = int(record.heading)
	if moved:
		flight.carrot_from = _carrot(flight)
		flight.carrot_to = point(city, tile, altitude)
		flight.carrot_t = 0.0
	flight.source = tile
	flight.altitude = altitude
	flight.phase = phase
	if flight.kind == &"plane" and landing and flight.mode in [MODE_AIR, MODE_ROLL]:
		_begin_landing(city, flight)


func _spawn(city: City, record: Dictionary) -> Flight:
	var flight := Flight.new()
	flight.serial = _next_serial
	_next_serial += 1
	flight.kind = record.kind
	flight.source = Vector2i(record.pos)
	flight.altitude = int(record.altitude)
	flight.frame = int(record.frame)
	flight.heading = int(record.heading)
	flight.phase = record.get("phase", &"")
	flight.matched = true
	flight.yaw = -float(flight.heading) * PI / 4.0
	var at := point(city, flight.source, flight.altitude)
	flight.carrot_from = at
	flight.carrot_to = at
	flight.position = at
	# The simulation flies a new aircraft its first day before anything sees
	# it, so a fresh record is already a day out from where it started.
	var fresh := flight.frame <= 1 and (flight.kind == &"helicopter" or flight.phase in [&"climb", &""])
	if flight.kind == &"plane":
		if flight.altitude <= 0 or fresh:
			# A new departure: on the runway, standing still. The first day's
			# flight was straight along the runway heading.
			var start := flight.source
			if flight.altitude > 0:
				start -= HEADING_STEP[posmod(flight.heading, 8)] * PortParams.PLANE_SPEED
				start = Vector2i(clampi(start.x, 0, City.WIDTH - 1), clampi(start.y, 0, City.HEIGHT - 1))
			var runway_start := point(city, start, 0)
			runway_start.y = _ground(city, runway_start)
			flight.carrot_from = runway_start
			flight.carrot_t = 0.0
			flight.position = runway_start
			flight.mode = MODE_ROLL
		else:
			flight.mode = MODE_AIR
			flight.speed = PLANE_LEAVE
			if flight.phase == &"land":
				_begin_landing(city, flight)
	elif fresh:
		# A helicopter that has just been sent out starts on its pad.
		flight.position.y = _ground(city, at)
	return flight


func _source_gone(city: City, flight: Flight) -> void:
	if flight.kind == &"helicopter":
		flight.mode = MODE_DESCEND
	elif flight.mode in [MODE_AIR, MODE_ROLL]:
		# The simulation removes a plane once its landing ends; one still
		# cruising had no airport left and flies away.
		if flight.phase == &"land":
			_begin_landing(city, flight)
		else:
			flight.mode = MODE_LEAVE
			flight.timer = 0.0


## A record's place in the view: the tile centre, its altitude over the
## surface below it.
static func point(city: City, tile: Vector2i, altitude: int) -> Vector3:
	var cell := Vector2i(clampi(tile.x, 0, City.WIDTH - 1), clampi(tile.y, 0, City.HEIGHT - 1))
	return Vector3(tile.x + 0.5, CityGeometry3D.surface_height(city, cell) + maxf(0.03, float(altitude) * CityGeometry3D.HEIGHT), tile.y + 0.5)


# ── Flying ───────────────────────────────────────────────────────────────

func _advance(city: City, flight: Flight, h: float) -> bool:
	flight.carrot_t = minf(1.0, flight.carrot_t + h)
	if flight.kind == &"helicopter":
		return _helicopter(city, flight, h)
	match flight.mode:
		MODE_ROLL:
			_takeoff_roll(city, flight, h)
		MODE_AIR:
			_cruise(city, flight, h)
		MODE_APPROACH:
			_approach(city, flight, h)
		MODE_ROLLOUT:
			_rollout(city, flight, h)
		MODE_PARKED:
			flight.speed = 0.0
			flight.timer += h
			_settle_attitude(flight, 0.0, 0.0, h)
			return flight.live or flight.timer < PARK_DAYS
		MODE_LEAVE:
			flight.timer += h
			var ahead := Vector2(flight.position.x, flight.position.z) + _forward(flight.yaw) * 4.0
			_steer(flight, ahead, PLANE_TURN, h)
			flight.speed = move_toward(flight.speed, PLANE_LEAVE, PLANE_ACCEL * h)
			_move(flight, h)
			_climb_to(city, flight, flight.position.y + 0.2, 0.3, h)
			_settle_attitude(flight, _coordinated_bank(flight), _flight_pitch(flight), h)
			return flight.timer < LEAVE_DAYS and _near_map(flight.position, 8.0)
	return true


func _takeoff_roll(city: City, flight: Flight, h: float) -> void:
	var path := _path(city, flight)
	_steer(flight, _along(path, _project(path, _here(flight)) + LOOKAHEAD), PLANE_GROUND_TURN, h)
	flight.speed = move_toward(flight.speed, PLANE_MAX, PLANE_TAKEOFF_ACCEL * h)
	_move(flight, h)
	flight.position.y = _ground(city, flight.position)
	flight.vertical = 0.0
	_settle_attitude(flight, 0.0, 0.0, h)
	if flight.speed >= PLANE_ROTATE:
		flight.mode = MODE_AIR


func _cruise(city: City, flight: Flight, h: float) -> void:
	var path := _path(city, flight)
	var travelled := _project(path, _here(flight))
	var lookahead := RETURN_LOOKAHEAD if flight.phase == &"return" else LOOKAHEAD
	_steer(flight, _along(path, travelled + lookahead), PLANE_TURN, h)
	# Hold FOLLOW_GAP behind the day's point, measured along the path, so a
	# plane that has got ahead slows rather than turning back for it.
	var today := path[0].distance_to(path[1])
	var behind := flight.carrot_t * today - travelled
	var want := clampf((today if flight.carrot_t < 1.0 else 0.0) + (behind - FOLLOW_GAP) * 1.2, PLANE_MIN_AIR, PLANE_MAX)
	flight.speed = move_toward(flight.speed, want, PLANE_ACCEL * h)
	_move(flight, h)
	_climb_to(city, flight, _carrot(flight).y, _carrot_velocity(flight).y, h)
	_settle_attitude(flight, _coordinated_bank(flight), _flight_pitch(flight), h)


## Today's glide toward the latest daily point, then the next two days as the
## simulation will fly them if the plane keeps its heading. The simulation
## turns a plane round the moment its next step would leave the map, so this
## sees that turn coming and the plane swings round before the edge. It turns
## toward its city centre; the map centre stands in until the real point
## arrives.
static func _path(city: City, flight: Flight) -> PackedVector2Array:
	var path := PackedVector2Array([Vector2(flight.carrot_from.x, flight.carrot_from.z), Vector2(flight.carrot_to.x, flight.carrot_to.z)])
	if not flight.live or flight.phase == &"land":
		return path
	var day := [flight.source, posmod(flight.heading, 8)]
	for _i: int in 2:
		day = _fly_day(city, day[0], day[1])
		var tile: Vector2i = day[0]
		path.append(Vector2(tile) + Vector2(0.5, 0.5))
	return path


## Distance along the path to its point closest to `at`.
static func _project(path: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	for i: int in path.size() - 1:
		var a := path[i]
		var segment := path[i + 1] - a
		var length := segment.length()
		var u := 0.0 if length < 0.0001 else clampf((at - a).dot(segment) / (length * length), 0.0, 1.0)
		var distance := at.distance_squared_to(a + segment * u)
		if distance < best - 0.0001:
			best = distance
			best_s = s + u * length
		s += length
	return best_s


## The point `s` tiles along the path, continuing straight past its end.
static func _along(path: PackedVector2Array, s: float) -> Vector2:
	var direction := Vector2.ZERO
	for i: int in path.size() - 1:
		var segment := path[i + 1] - path[i]
		var length := segment.length()
		if length < 0.0001:
			continue
		direction = segment / length
		if s <= length:
			return path[i] + direction * s
		s -= length
	return path[path.size() - 1] + direction * s


static func _here(flight: Flight) -> Vector2:
	return Vector2(flight.position.x, flight.position.z)


## One simulated day of steps from a tile: [tile, heading, turned back].
static func _fly_day(city: City, at: Vector2i, heading: int) -> Array:
	var turned := false
	for _i: int in PortParams.PLANE_SPEED:
		var next := at + HEADING_STEP[heading]
		if city.in_bounds(next.x, next.y):
			at = next
		else:
			heading = _heading_to(at, Vector2i(City.HALF, City.HALF))
			turned = true
	return [at, heading, turned]


## The simulation's heading 0..7 from one tile toward another.
static func _heading_to(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	return posmod(roundi((atan2(float(to.y - from.y), float(to.x - from.x)) + PI / 2.0) / (PI / 4.0)), 8)


func _begin_landing(city: City, flight: Flight) -> void:
	var plan := _runway_plan(city, flight)
	if plan.is_empty():
		if not flight.live:
			flight.mode = MODE_LEAVE
			flight.timer = 0.0
		return
	flight.runway = plan
	flight.established = false
	flight.mode = MODE_APPROACH
	flight.timer = 0.0


## Fly the circuit: out to a point on the extended centre line, then down the
## glide path along it to the threshold.
func _approach(city: City, flight: Flight, h: float) -> void:
	var plan := flight.runway
	var direction: Vector2 = plan.direction
	var threshold: Vector2 = plan.threshold
	var here := Vector2(flight.position.x, flight.position.z)
	var before := -(here - threshold).dot(direction)
	var lateral := (here - threshold).dot(Vector2(-direction.y, direction.x))
	var facing := _forward(flight.yaw).dot(direction)
	var runway_height := float(plan.height)
	var aim: Vector2
	var height: float
	var rate := 0.0
	var want_speed: float
	flight.timer += h
	if flight.timer > APPROACH_DAYS:
		flight.mode = MODE_LEAVE
		flight.timer = 0.0
		return
	if not flight.established:
		var entry := threshold - direction * CIRCUIT
		aim = entry
		height = runway_height + CIRCUIT * GLIDE
		want_speed = APPROACH_SPEED
		if (before > FINAL and absf(lateral) < 1.0 and facing > 0.85) or here.distance_to(entry) < 1.4:
			flight.established = true
	else:
		# The aim slides along the centre line ahead of the plane.
		aim = threshold - direction * (before - LINE_LOOKAHEAD)
		height = runway_height + maxf(0.0, before) * GLIDE
		if before > 0.0:
			rate = -GLIDE * flight.speed * maxf(facing, 0.0)
		want_speed = lerpf(TOUCHDOWN_SPEED, APPROACH_SPEED, clampf(before / FINAL, 0.0, 1.0))
		var low := flight.position.y - runway_height
		var lined_up := absf(lateral) <= TOUCHDOWN_LATERAL and facing >= TOUCHDOWN_FACING
		if before <= 0.1:
			if lined_up and low <= 0.08:
				flight.mode = MODE_ROLLOUT
				flight.position.y = runway_height
				flight.vertical = 0.0
				return
			if not lined_up or low > GO_AROUND_HEIGHT or before < -0.5 * float(plan.length):
				flight.established = false
	_steer(flight, aim, PLANE_TURN, h)
	flight.speed = move_toward(flight.speed, want_speed, PLANE_ACCEL * h)
	_move(flight, h)
	var near_runway := flight.established and before < FINAL + 1.0
	_climb_to(city, flight, height, rate, h, not near_runway)
	_settle_attitude(flight, _coordinated_bank(flight), _flight_pitch(flight), h)


func _rollout(city: City, flight: Flight, h: float) -> void:
	var plan := flight.runway
	var direction: Vector2 = plan.direction
	var threshold: Vector2 = plan.threshold
	var stop: Vector2 = plan.stop
	var here := Vector2(flight.position.x, flight.position.z)
	var gone := -(here - threshold).dot(direction)
	_steer(flight, threshold - direction * (gone - 0.8), PLANE_GROUND_TURN, h)
	var remaining := maxf(0.05, (stop - here).dot(direction))
	var brake := maxf(MIN_BRAKE, flight.speed * flight.speed / (2.0 * remaining))
	flight.speed = move_toward(flight.speed, 0.0, brake * h)
	_move(flight, h)
	flight.position.y = _ground(city, flight.position)
	flight.vertical = 0.0
	_settle_attitude(flight, 0.0, 0.0, h)
	if flight.speed <= 0.01:
		flight.speed = 0.0
		flight.mode = MODE_PARKED
		flight.timer = 0.0


func _helicopter(city: City, flight: Flight, h: float) -> bool:
	var here := Vector2(flight.position.x, flight.position.z)
	var before := flight.velocity
	var height: float
	if flight.mode == MODE_DESCEND:
		flight.velocity = flight.velocity.move_toward(Vector2.ZERO, HELI_ACCEL * h)
		height = _ground(city, flight.position)
	else:
		var target := _carrot(flight)
		var carrot_velocity := _carrot_velocity(flight)
		var want := (Vector2(carrot_velocity.x, carrot_velocity.z) + (Vector2(target.x, target.z) - here) * 1.6).limit_length(HELI_MAX)
		flight.velocity = flight.velocity.move_toward(want, HELI_ACCEL * h)
		height = target.y
	var accel := (flight.velocity - before) / h
	flight.position.x += flight.velocity.x * h
	flight.position.z += flight.velocity.y * h
	if flight.velocity.length() > 0.4:
		_steer(flight, here + flight.velocity, HELI_TURN, h)
	else:
		flight.yaw_rate = move_toward(flight.yaw_rate, 0.0, PLANE_TURN_ACCEL * h)
		flight.yaw = wrapf(flight.yaw + flight.yaw_rate * h, -PI, PI)
	var ground := _ground(city, flight.position)
	var rise := clampf((height - flight.position.y) * 2.0, -HELI_CLIMB, HELI_CLIMB)
	flight.vertical = move_toward(flight.vertical, rise, 3.0 * h)
	flight.position.y = maxf(ground, flight.position.y + flight.vertical * h)
	# Lean forward into travel and acceleration, and sideways into a turn.
	var forward := _forward(flight.yaw)
	var right := Vector2(-forward.y, forward.x)
	var tilt := -clampf(flight.velocity.dot(forward) * 0.06 + accel.dot(forward) * 0.03, -HELI_MAX_TILT, HELI_MAX_TILT)
	var lean := -clampf(accel.dot(right) * 0.04, -HELI_MAX_TILT, HELI_MAX_TILT)
	if flight.position.y - ground <= 0.01:
		tilt = 0.0
		lean = 0.0
	_settle_attitude(flight, lean, tilt, h)
	if flight.mode == MODE_DESCEND and flight.position.y - ground <= 0.005 and flight.velocity.length() < 0.05:
		return false
	return true


# ── Shared motion ────────────────────────────────────────────────────────

## Turn toward a point, with a limited turn rate that itself changes smoothly.
static func _steer(flight: Flight, aim: Vector2, max_rate: float, h: float) -> void:
	var to := aim - Vector2(flight.position.x, flight.position.z)
	var want := 0.0
	if to.length_squared() > 0.0025:
		want = clampf(angle_difference(flight.yaw, yaw_toward(to)) * PLANE_TURN_GAIN, -max_rate, max_rate)
	flight.yaw_rate = move_toward(flight.yaw_rate, want, PLANE_TURN_ACCEL * h)
	flight.yaw = wrapf(flight.yaw + flight.yaw_rate * h, -PI, PI)


static func _move(flight: Flight, h: float) -> void:
	var forward := _forward(flight.yaw)
	flight.position.x += forward.x * flight.speed * h
	flight.position.z += forward.y * flight.speed * h


## Ease toward a height that is itself changing at `rate` tiles a day, at a
## climb or descent gradient a plane can fly. Away from the runway the plane
## keeps CLEARANCE over the ground below it.
static func _climb_to(city: City, flight: Flight, height: float, rate: float, h: float, keep_clear: bool = true) -> void:
	var ground := _ground(city, flight.position)
	if keep_clear:
		height = maxf(height, ground + CLEARANCE)
	var fastest := maxf(flight.speed, 0.5)
	var want := clampf(rate + (height - flight.position.y) * 3.0, -fastest * PLANE_DESCENT, fastest * PLANE_CLIMB)
	flight.vertical = move_toward(flight.vertical, want, 4.0 * h)
	flight.position.y += flight.vertical * h
	if flight.position.y < ground:
		flight.position.y = ground
		flight.vertical = maxf(flight.vertical, 0.0)


static func _coordinated_bank(flight: Flight) -> float:
	return clampf(atan(flight.speed * flight.yaw_rate / BANK_GRAVITY), -PLANE_MAX_BANK, PLANE_MAX_BANK)


static func _flight_pitch(flight: Flight) -> float:
	return clampf(atan2(flight.vertical, maxf(flight.speed, 0.5)), -PLANE_MAX_PITCH, PLANE_MAX_PITCH)


static func _settle_attitude(flight: Flight, bank: float, pitch: float, h: float) -> void:
	var blend := 1.0 - exp(-h / 0.08)
	flight.bank = lerpf(flight.bank, bank, blend)
	flight.pitch = lerpf(flight.pitch, pitch, blend)


static func _carrot(flight: Flight) -> Vector3:
	return flight.carrot_from.lerp(flight.carrot_to, flight.carrot_t)


## Tiles a day the daily point is moving now.
static func _carrot_velocity(flight: Flight) -> Vector3:
	return flight.carrot_to - flight.carrot_from if flight.carrot_t < 1.0 else Vector3.ZERO


## Horizontal direction (x, z) of a Godot yaw.
static func _forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func yaw_toward(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)


static func _ground(city: City, at: Vector3) -> float:
	var cell := Vector2i(clampi(floori(at.x), 0, City.WIDTH - 1), clampi(floori(at.z), 0, City.HEIGHT - 1))
	return CityGeometry3D.surface_height(city, cell)


static func _near_map(at: Vector3, margin: float) -> bool:
	return at.x > -margin and at.z > -margin and at.x < City.WIDTH + margin and at.z < City.HEIGHT + margin


# ── Runways ──────────────────────────────────────────────────────────────

static func _is_runway(city: City, tile: Vector2i) -> bool:
	if not city.in_bounds(tile.x, tile.y):
		return false
	var id := city.building_at(tile.x, tile.y)
	return id == Buildings.RUNWAY or id == Buildings.RUNWAY_CROSS


## The runway nearest the landing point, landed on in the direction closer to
## the plane's heading: {direction, threshold, stop, height}, or {} without one.
static func _runway_plan(city: City, flight: Flight) -> Dictionary:
	var origin := flight.source
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for dy: int in range(-RUNWAY_SEARCH, RUNWAY_SEARCH + 1):
		for dx: int in range(-RUNWAY_SEARCH, RUNWAY_SEARCH + 1):
			var tile := origin + Vector2i(dx, dy)
			var distance := Vector2(dx, dy).length()
			if distance < best_distance and _is_runway(city, tile):
				best_distance = distance
				best = tile
	if best.x < 0:
		return {}
	var along_x := _runway_run(city, best, Vector2i(1, 0))
	var along_y := _runway_run(city, best, Vector2i(0, 1))
	var run: Array[Vector2i] = along_x if along_x[1].x - along_x[0].x >= along_y[1].y - along_y[0].y else along_y
	var first: Vector2i = run[0]
	var last: Vector2i = run[1]
	var axis := Vector2(last - first).normalized() if last != first else Vector2(1, 0)
	var direction := axis if _forward(flight.yaw).dot(axis) >= 0.0 else -axis
	var start := Vector2(first) + Vector2(0.5, 0.5)
	var end := Vector2(last) + Vector2(0.5, 0.5)
	if direction.dot(end - start) < 0.0:
		var swap := start
		start = end
		end = swap
	return {"direction": direction, "threshold": start - direction * 0.3, "stop": end,
		"length": start.distance_to(end) + 1.0, "height": CityGeometry3D.surface_height(city, first)}


## The two ends of the straight runway through `tile` along `step`.
static func _runway_run(city: City, tile: Vector2i, step: Vector2i) -> Array[Vector2i]:
	var first := tile
	while _is_runway(city, first - step):
		first -= step
	var last := tile
	while _is_runway(city, last + step):
		last += step
	return [first, last]
