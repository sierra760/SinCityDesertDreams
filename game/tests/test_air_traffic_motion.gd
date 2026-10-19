# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Port aircraft as the 3D view draws them. A real operating airport sends out
## planes and its helicopter; every frame at three game speeds is watched
## through CityTraffic3D, the same path Main uses.

const PortSystem := preload("res://scripts/sim/port_system.gd")
const AIR_KINDS: Array[StringName] = [&"plane", &"helicopter"]
## Clear of the ground (tiles), above which an airliner must be flying.
const AIRBORNE := 0.35
const ON_GROUND := 0.03

var _contexts: Array[SimContext] = []


func after_each() -> void:
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func _airport(seed_value: int = 11) -> Array:
	var c := flat_city()
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	var rect := Rect2i(20, 20, 12, 12)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			c.zone.put(x, y, Zones.make(Zones.AIRPORT))
			c.set_flag(x, y, TileFlags.POWERED, true)
	var ports: PortSystem = PortSystem.new()
	ports.setup(ctx)
	ctx.systems[ports.key] = ports
	for _i in 24 * GameClock.DAYS_PER_MONTH:
		_day(ctx, ports)
	return [c, ctx, ports, rect]


func _day(ctx: SimContext, ports: PortSystem) -> void:
	ctx.events.clear()
	ports.daily(ctx)
	if ctx.clock.day_of_month() == GameClock.DAYS_PER_MONTH:
		ports.monthly(ctx, 0)
	if ctx.clock.is_year_end():
		ports.yearly(ctx)
	ctx.clock.advance()
	ctx.city.day = ctx.clock.day


static func _records(ports: PortSystem) -> Array:
	var out: Array = []
	for v: Dictionary in ports.vehicles():
		var record := v.duplicate()
		record["source"] = &"ports"
		out.append(record)
	return out


static func _is_runway(c: City, p: Vector3) -> bool:
	var id := c.building_at(clampi(floori(p.x), 0, City.WIDTH - 1), clampi(floori(p.z), 0, City.HEIGHT - 1))
	return id == Buildings.RUNWAY or id == Buildings.RUNWAY_CROSS


## Every frame of `days` days at `day_seconds` real seconds a day.
func _watch(day_seconds: float, days: int, airport_lost_after: int = -1, airport_back_after: int = -1) -> Dictionary:
	var parts := _airport()
	var c: City = parts[0]
	var ctx: SimContext = parts[1]
	var ports: PortSystem = parts[2]
	var rect: Rect2i = parts[3]
	check(ports.port_report()[0].operating, "fixture airport operates")
	var traffic := CityTraffic3D.new()
	traffic.bind_city(c)
	traffic.set("day_seconds", day_seconds)
	var frames := maxi(1, roundi(day_seconds * 60.0))
	var delta := day_seconds / float(frames)
	var dt_days := delta / day_seconds
	var last: Dictionary = {}
	var first_frame := true
	var stats := {"plane_max_speed": 0.0, "plane_min_air_speed": INF, "plane_frames": 0,
		"plane_max_roll": 0.0, "plane_max_turn": 0.0, "vanish_heights": [], "vanish_speeds": [],
		"touchdowns": 0, "misaligned": 0, "off_runway": 0, "takeoff_rolls": [],
		"helicopter_max_speed": 0.0, "helicopter_vanish_heights": [], "helicopter_first_heights": [],
		"end_of_day": [], "wrong_roll": 0}
	for day: int in days:
		if day == airport_lost_after or day == airport_back_after:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					c.set_flag(x, y, TileFlags.POWERED, day == airport_back_after)
			ports.networks_changed(ctx, rect)
		_day(ctx, ports)
		var records := _records(ports)
		for _f: int in frames:
			traffic.advance(delta, false, records, null, true)
			var now: Dictionary = {}
			for record: Dictionary in traffic._external:
				if not record.kind in AIR_KINDS: continue
				var id := int(record.presentation_id)
				var p: Vector3 = record.presentation_position
				var basis: Basis = record.get("presentation_basis", Basis(Vector3.UP, float(record.presentation_yaw)))
				var height := p.y - CityGeometry3D.surface_height(c, Vector2i(clampi(floori(p.x), 0, City.WIDTH - 1), clampi(floori(p.z), 0, City.HEIGHT - 1)))
				var forward := -basis.z
				var yaw := atan2(-forward.x, -forward.z)
				# Positive when the left wing is down (the right wing tip raised).
				var roll := asin(clampf(basis.x.y, -1.0, 1.0))
				var entry := {"p": p, "height": height, "yaw": yaw, "roll": roll, "kind": record.kind, "speed": 0.0,
					"airborne": height > AIRBORNE, "lifted": height > 0.1, "rolled": 0.0, "start": p}
				if last.has(id):
					var before: Dictionary = last[id]
					var speed := Vector2(p.x - before.p.x, p.z - before.p.z).length() / dt_days
					var turn := absf(angle_difference(float(before.yaw), yaw)) / dt_days
					entry.speed = speed
					entry.airborne = bool(before.airborne) or height > AIRBORNE
					entry.start = before.start
					entry.rolled = float(before.rolled)
					entry.lifted = bool(before.lifted) or height > 0.1
					if record.kind == &"plane":
						stats.plane_frames += 1
						stats.plane_max_speed = maxf(stats.plane_max_speed, speed)
						stats.plane_max_turn = maxf(stats.plane_max_turn, turn)
						stats.plane_max_roll = maxf(stats.plane_max_roll, absf(roll))
						if height > AIRBORNE and float(before.height) > AIRBORNE:
							stats.plane_min_air_speed = minf(stats.plane_min_air_speed, speed)
						# A left turn (yaw increasing) banks the left wing down.
						var turn_signed := angle_difference(float(before.yaw), yaw) / dt_days
						if absf(turn_signed) > 1.2 and height > AIRBORNE and signf(roll) != signf(turn_signed): stats.wrong_roll += 1
						if not bool(before.lifted) and height <= ON_GROUND:
							entry.rolled = Vector2(p.x - before.start.x, p.z - before.start.z).length()
						if bool(before.airborne) and float(before.height) > ON_GROUND and height <= ON_GROUND:
							stats.touchdowns += 1
							if not _is_runway(c, p): stats.off_runway += 1
							var axis := fposmod(yaw, PI / 2.0)
							if minf(axis, PI / 2.0 - axis) > deg_to_rad(12.0): stats.misaligned += 1
						if not bool(before.lifted) and height > 0.1:
							stats.takeoff_rolls.append(float(before.rolled))
					else:
						stats.helicopter_max_speed = maxf(stats.helicopter_max_speed, speed)
				elif not first_frame and record.kind == &"helicopter":
					stats.helicopter_first_heights.append(height)
				now[id] = entry
			for id: int in last:
				if now.has(id): continue
				var gone: Dictionary = last[id]
				if gone.kind == &"plane":
					stats.vanish_heights.append(float(gone.height))
					stats.vanish_speeds.append(float(gone.speed))
				else:
					stats.helicopter_vanish_heights.append(float(gone.height))
			last = now
			first_frame = false
		var snapshot: Dictionary = {}
		for id: int in last: snapshot[id] = last[id].p
		stats.end_of_day.append(snapshot)
	traffic.free()
	return stats


func _at_most(actual: float, limit: float, message: String) -> void:
	check(actual <= limit, "%s (%.4f > %.4f)" % [message, actual, limit])


func _check_flight(stats: Dictionary, label: String) -> void:
	check_gt(int(stats.plane_frames), 0, label + ": planes were watched")
	_at_most(float(stats.plane_max_speed), 5.6, label + ": planes never jump ahead of their flying speed")
	check_ge(float(stats.plane_min_air_speed), 2.0, label + ": an airliner never stops in the air")
	_at_most(float(stats.plane_max_turn), 2.6, label + ": planes turn at a flying rate, never snapping to a heading")
	check_gt(float(stats.plane_max_roll), deg_to_rad(10.0), label + ": planes bank into their turns")
	check_eq(int(stats.wrong_roll), 0, label + ": every bank leans into its turn")
	check_gt((stats.vanish_heights as Array).size(), 0, label + ": a flight was seen to its end")
	for height: float in stats.vanish_heights:
		_at_most(height, ON_GROUND, label + ": a plane leaves only from the ground")
	for speed: float in stats.vanish_speeds:
		_at_most(speed, 0.4, label + ": after rolling out to a stop")
	check_gt(int(stats.touchdowns), 0, label + ": a plane touched down")
	check_eq(int(stats.off_runway), 0, label + ": touchdowns are on the runway")
	check_eq(int(stats.misaligned), 0, label + ": touchdowns follow the runway")
	check_gt((stats.takeoff_rolls as Array).size(), 0, label + ": a plane took off")
	for distance: float in stats.takeoff_rolls:
		check_ge(distance, 0.6, label + ": takeoff starts with a roll down the runway")


func test_planes_fly_continuously_at_medium_speed() -> void:
	_check_flight(_watch(0.8, 160), "medium")


func test_planes_fly_continuously_at_slow_and_fastest_speeds() -> void:
	_check_flight(_watch(1.6, 160), "slow")
	_check_flight(_watch(0.08, 160), "fastest")


func test_flight_path_shape_does_not_depend_on_game_speed() -> void:
	var medium := _watch(0.8, 90)
	var fastest := _watch(0.08, 90)
	var compared := 0
	var worst := 0.0
	for day: int in mini((medium.end_of_day as Array).size(), (fastest.end_of_day as Array).size()):
		var a: Dictionary = medium.end_of_day[day]
		var b: Dictionary = fastest.end_of_day[day]
		for id: int in a:
			if not b.has(id): continue
			worst = maxf(worst, (a[id] as Vector3).distance_to(b[id]))
			compared += 1
	check_gt(compared, 20, "the same flights are compared")
	_at_most(worst, 0.3, "a flight follows the same path at every game speed")


func test_helicopter_lifts_off_and_sets_down() -> void:
	# The airport closes, so its helicopter leaves, then reopens and sends out
	# a new one.
	var stats := _watch(0.8, 160, 10, 40)
	check_gt((stats.helicopter_first_heights as Array).size(), 0, "a helicopter flew")
	for height: float in stats.helicopter_first_heights:
		_at_most(height, ON_GROUND, "the helicopter lifts off from its pad")
	_at_most(float(stats.helicopter_max_speed), 3.6, "the helicopter never jumps")
	for height: float in stats.helicopter_vanish_heights:
		_at_most(height, ON_GROUND, "the helicopter sets down before leaving")
	check_gt((stats.helicopter_vanish_heights as Array).size(), 0, "the helicopter left once its airport closed")


func test_saved_circling_plane_returns_and_touches_down() -> void:
	var c := flat_city()
	for x: int in range(60, 65):
		c.stamp_building(x, 60, Buildings.RUNWAY, Zones.AIRPORT)
	var ctx := make_context(c, 11)
	_contexts.append(ctx)
	var ports: PortSystem = PortSystem.new()
	ports.setup(ctx)
	ctx.systems[ports.key] = ports
	# This saved position used to repeat every eight days without landing.
	ports.load({"vehicles": [{"kind": "plane", "x": 64, "y": 60, "heading": 0, "frame": 20,
		"altitude": 8, "phase": "return", "days": 0, "target": [60, 60], "port": [60, 60]}]})
	var traffic := CityTraffic3D.new()
	traffic.bind_city(c)
	traffic.day_seconds = 0.32
	var landed := false
	for day: int in 30:
		ports.daily(ctx)
		var records := _records(ports)
		for frame: int in 20:
			traffic.advance(0.016, false, records, null, true)
			for record: Dictionary in traffic._external:
				if record.kind != &"plane": continue
				var p: Vector3 = record.presentation_position
				if p.y - CityGeometry3D.surface_height(c, Vector2i(p.x, p.z)) <= ON_GROUND:
					landed = true
					check(_is_runway(c, p), "saved returning plane touches down on the runway")
	check(landed, "saved circling plane completes its return and rendered landing")
	check_eq(traffic._external.size(), 0, "completed flight leaves after rollout")
	traffic.free()
