# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The optimized ambient-traffic tick, pose cache and draw path reproduce an
## unoptimized reference exactly on a real city: every actor field (logic state,
## sampled/cached/rendered poses, cadence history) and every batch row count,
## through live play, cadence switches, pause, claims, raw record mutation,
## releases and route rebuilds after road edits.
extends "res://tests/exploration/async_test_case.gd"

## Unoptimized reference versions of _step, _record_render_state, actor_pose
## and _render, kept unchanged so the optimized ones have something to match.
## _step follows the October 8 junction/interchange flow rules with direct
## graph queries in place of the per-revision route caches.
class FrozenTraffic:
	extends CityTraffic3D
	var _paused_render_hash := 0

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
			var ramp := graph.is_ramp(cell)
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
			if a.domain == &"highway" and graph.is_ramp(a.previous):
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
			if a.domain == &"road" and a.type != &"pedestrian" and graph.degree(cell,&"road") > 2:
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
		for junction: int in waiting:
			grants[junction] = _junction_grant(waiting[junction],int(boxes.get(junction,0)),entries,box_exits,{})
		var leaving: Dictionary = {}
		for a: Dictionary in actors:
			if _claims.has(a.id): continue
			if a.domain == &"rail" and _reserved_rail.has(a.next):
				a.stopped = true
				continue
			a.stopped = false
			var speed := float(a.speed)
			if a.type == &"road" or a.type == &"highway": speed *= 1.0 - float(graph.demand(a.cell).congestion) * .6
			var occupants: Variant = occupied.get(_lane_key(a.type,a.domain,a.cell,a.next,int(a.get(&"lane",0)) if a.domain == &"highway" and not graph.is_ramp(a.cell) else 0))
			if occupants != null:
				for other: Dictionary in occupants:
					# Different approaches to one exit only share a lane past the stop line.
					if other.previous != a.previous and (float(a.t) < STOP_LINE or float(other.t) < STOP_LINE): continue
					if other.id != a.id and float(other.t) > float(a.t) and float(other.t)-float(a.t) < _following_gap(a,other): speed = 0
			var degree := graph.degree(a.cell,a.domain)
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
				elif granted != bit or not _exit_ready(a,entries,box_exits): limit = STOP_LINE-.001
			if a.domain == &"highway" and int(a.get(&"lane",0)) == 1 and merging.has(a.next) and float(a.t) < .5: limit = .5
			if float(a.t) > .1:
				var entrants: Variant = entries.get(_lane_key(a.type,a.domain,a.next,a.cell,int(a.get(&"lane",0)) if a.domain == &"highway" and not graph.is_ramp(a.next) else 0))
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
			if float(a.t) >= 1 and a.domain == &"highway" and not graph.neighbors(a.cell,&"highway").has(a.next):
				# Reached the end of a carriageway that leaves the map: drive off.
				leaving[a.id] = true
				continue
			if float(a.t) >= 1:
				var next_domain := graph.continuation_domain(a.cell,a.next,a.domain)
				var next_lane := 1 if graph.is_ramp(a.cell) and next_domain==&"highway" else int(a.get(&"lane",0))
				if graph.is_ramp(a.cell) and next_domain==&"highway" and graph.highways.routes.has(a.next):
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
				if graph.is_ramp(a.next):
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
						if ramps.has(choice) and graph.is_ramp(choice): busy = true; break
					if busy:
						var open := choices.filter(func(cell: Vector2i) -> bool: return not (ramps.has(cell) and graph.is_ramp(cell)))
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

	func _record_render_state(a: Dictionary) -> void:
		var previous: Dictionary = a.get("_render_previous",{})
		previous.cell = a.cell
		previous.previous = a.previous
		previous.next = a.next
		previous.t = a.t
		previous.type = a.type
		previous.domain = a.domain
		previous.lane = a.get("lane",0)
		previous.side = a.side
		previous.reversed = a.get("reversed",false)
		# Reuse the already sampled current pose when it belongs to this state.
		# Offscreen/catch-up states still sample lazily when they next become visible.
		var style := hash([a.type,a.domain,a.get("lane",0),a.side,a.get("reversed",false)])
		if a.get("_pose_t",-1.0) == a.t and a.get("_pose_revision",-1) == graph.revision and a.get("_pose_cell") == a.cell and a.get("_pose_previous") == a.previous and a.get("_pose_next") == a.next and a.get("_pose_style") == style:
			previous._cached_pose = a._pose
		else: previous.erase("_cached_pose")
		previous._recorded_revision = graph.revision
		a._render_previous = previous

	func actor_pose(a: Dictionary) -> Transform3D:
		var style := hash([a.type,a.domain,a.get("lane",0),a.side,a.get("reversed",false)])
		if a.get("_pose_t",-1.0) == a.t and a.get("_pose_revision",-1) == graph.revision and a.get("_pose_cell") == a.cell and a.get("_pose_previous") == a.previous and a.get("_pose_next") == a.next and a.get("_pose_style") == style:
			return a._pose
		var segment := graph.highway_segment(a.cell,a.previous,a.next,int(a.get("lane",0))) if a.domain==&"highway" else {}
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
		if a.domain==&"highway" and graph.highways.routes.has(a.cell): lane = -.22 if int(a.get("lane",0))==0 else .22
		if graph.is_ramp(a.cell): lane = 0.0
		var side := float(a.side)
		if a.previous == a.next and a.type != &"pedestrian" and not graph.is_ramp(a.cell):
			var angle := PI * clampf(float(a.t),0,1)
			var entry := Vector2(.5,.5)-incoming*.5
			var perpendicular := Vector2(-incoming.y,incoming.x)*side
			var offset: Vector2
			var direction: Vector2
			if a.domain == &"rail":
				# A locomotive backs out without rotating its body at a terminal.
				offset = entry+incoming*(.35*sin(angle))
				direction = incoming * (-1.0 if a.get("reversed",false) else 1.0)
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
		if graph.is_ramp(a.previous): start = Vector2(.5,.5)-incoming*.5
		if graph.is_ramp(a.next): end = Vector2(.5,.5)+outgoing*.5
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
		if a.domain == &"rail" and a.get("reversed",false): basis = basis.rotated(basis.y,PI)
		return _cache_pose(a,Transform3D(basis,position),style)

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
				var state := _render_state(camera)
				# Public records may change without notification; equality follows the
				# hash so collisions cannot preserve stale presentation.
				if hash(state) == _paused_render_hash and state == _paused_render_state:
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
		for a: Dictionary in actors:
			if _claims.has(a.id): continue
			if _coarse_culled(graph.center(a.cell,a.domain),camera): continue
			var target := actor_pose(a)
			var previous: Dictionary = a.get("_render_previous",{})
			var prior := target
			if previous.get("_recorded_revision",-1) == graph.revision:
				if not previous.has("_cached_pose"): previous._cached_pose = actor_pose(previous)
				prior = previous._cached_pose
			a._render_from = prior if prior.origin.distance_squared_to(target.origin)<2.25 else target
			a._render_target = target
			var pose: Transform3D = a._render_from.interpolate_with(a._render_target,clampf(_accumulator/_step_interval,0,1))
			# Different tick durations have different presentation latency. Catch up
			# from the displayed pose at a bounded rate rather than dropping that lag
			# in one frame. Pausing also pauses this brief handoff.
			if a.has("_cadence_pose") and a.get("_cadence_revision",-1) == graph.revision and a.get("_render_serial",-1) >= _render_serial-1 and previous.get("_recorded_revision",-1) == graph.revision:
				var displayed: Transform3D = a._cadence_pose
				var forward := -displayed.basis.z * (-1.0 if a.domain == &"rail" and a.get("reversed",false) else 1.0)
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
					a.erase("_cadence_pose")
				else: pose = a._cadence_pose
			else: a.erase("_cadence_pose")
			a._render_pose = pose
			a._render_serial = _render_serial
			a._render_revision = graph.revision
			if _culled(pose.origin,camera): continue
			var low := camera != null and (_camera_size > 16.0 if _camera_orthographic else _camera_position.distance_squared_to(pose.origin) > 400.0)
			var variant := int(a.variant) if a.type == &"pedestrian" else 0
			if low: variant %= 4
			var group_key := Vector3i(_name_id(a.kind),variant,1 if low else 0)
			var group: Dictionary = groups.get(group_key,{})
			if group.is_empty():
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
			var group: Dictionary = groups.get(group_key,{})
			if group.is_empty():
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
				var state := _render_state(camera)
				_paused_render_hash = hash(state)
				_paused_render_state = state.duplicate(true)


func _pair(city: City) -> Array:
	var actual := CityTraffic3D.new()
	var frozen := FrozenTraffic.new()
	root.add_child(actual)
	root.add_child(frozen)
	actual.bind_city(city)
	frozen.bind_city(city)
	return [actual, frozen]

func _compare(actual: CityTraffic3D, frozen: CityTraffic3D, label: String) -> bool:
	var ok: bool = actual.actors == frozen.actors
	check(ok, label + ": every actor field matches the reference")
	check_eq(actual.statistics.get("visible"), frozen.statistics.get("visible"), label + ": same visible count")
	check_eq(actual._batches.keys(), frozen._batches.keys(), label + ": same batches")
	for key: String in frozen._batches:
		if not actual._batches.has(key): continue
		check_eq(actual._batches[key].multimesh.visible_instance_count, frozen._batches[key].multimesh.visible_instance_count, label + ": same rows in " + key)
	check_eq(actual._next_id, frozen._next_id, label + ": same admissions")
	return ok

func _camera(orthographic: bool, size: float, at: Vector3, focus: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = at
	camera.look_at(focus)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = size
	camera.far = 4000
	return camera

func _run_frames(actual: CityTraffic3D, frozen: CityTraffic3D, frames: int, camera: Camera3D, paused: bool, label: String, delta: float = 1.0/60) -> void:
	var mismatches := 0
	for frame: int in frames:
		actual.advance(delta, paused, [], camera)
		frozen.advance(delta, paused, [], camera)
		if actual.actors != frozen.actors: mismatches += 1
	check_eq(mismatches, 0, label + ": no frame diverges")
	_compare(actual, frozen, label)

func test_real_city_tick_pose_and_draw_match_reference() -> void:
	for path: String in ["res://assets/cities/La Presa.sc2", "res://assets/cities/Foothills Ranch.sc2"]:
		var loaded := Sc2Import.load(path)
		check(loaded.ok, "bundled city imports")
		if not loaded.ok: continue
		var city: City = loaded.city
		var pair := _pair(city)
		var actual: CityTraffic3D = pair[0]
		var frozen: CityTraffic3D = pair[1]
		var overview := _camera(true, 150.0, Vector3(64+110, 130, 64+110), Vector3(64, 2, 64))
		_run_frames(actual, frozen, 90, overview, false, path + " overview 10 Hz")
		check_gt(actual.actors.size(), 100, path + ": real demand admits a large population")
		check_gt(int(actual.statistics.get("visible", 0)), 100, path + ": overview draws the population")
		var street := _camera(false, 12.0, Vector3(60, 6, 72), Vector3(64, 1, 64))
		_run_frames(actual, frozen, 120, street, false, path + " street 30 Hz")
		_run_frames(actual, frozen, 30, overview, false, path + " cadence back to overview")
		_run_frames(actual, frozen, 20, street, true, path + " paused street")
		# Raw public-record mutation while paused and while running.
		for traffic: CityTraffic3D in [actual, frozen]:
			traffic.actors[0].t = .85
			traffic.actors[3].cell = traffic.actors[3].next
		_run_frames(actual, frozen, 5, street, true, path + " raw mutation paused")
		_run_frames(actual, frozen, 30, street, false, path + " raw mutation live")
		# Diagonal raw jumps put rendered history near the 1.5-tile handoff bound.
		for traffic: CityTraffic3D in [actual, frozen]:
			for i: int in range(10, 60):
				# Stay on the map: an off-map cell has no ground to pose on.
				if traffic.actors[i].cell.x < City.WIDTH-1 and traffic.actors[i].cell.y < City.HEIGHT-1:
					traffic.actors[i].cell = traffic.actors[i].cell + Vector2i(1, 1)
		_run_frames(actual, frozen, 4, overview, false, path + " diagonal raw jumps")
		# Claims and a release back into traffic.
		var claimed: Dictionary = actual.claim_nearby_vehicle(actual.actor_pose(actual.actors[5]).origin, 3.0)
		frozen.claim_nearby_vehicle(frozen.actor_pose(frozen.actors[5]).origin, 3.0)
		_run_frames(actual, frozen, 30, street, false, path + " claimed vehicle")
		if not claimed.is_empty():
			actual.release_vehicle(claimed, claimed.position)
			frozen.release_vehicle(claimed, claimed.position)
		_run_frames(actual, frozen, 30, street, false, path + " released vehicle")
		# A road edit rebuilds routes (new revision): caches must follow it.
		var cells: Array = actual.graph.cells(&"road")
		var revision := actual.graph.revision
		for i: int in mini(12, cells.size()):
			var cell: Vector2i = cells[(i * 97) % cells.size()]
			city.building.put(cell.x, cell.y, 0)
		actual.invalidate()
		frozen.invalidate()
		_run_frames(actual, frozen, 90, overview, false, path + " after road removals")
		check_gt(actual.graph.revision, revision, path + ": road edits produced a new route revision")
		_run_frames(actual, frozen, 60, street, false, path + " street after road removals")
		overview.queue_free()
		street.queue_free()
		actual.queue_free()
		frozen.queue_free()
		await process_frame


## Every cached route/cull answer equals the graph's own answer, for every cell
## and domain, across route revisions and camera/display changes.
func _check_caches(traffic: CityTraffic3D, camera: Camera3D, label: String) -> void:
	var ramp_errors := 0
	var degree_errors := 0
	var cull_errors := 0
	traffic._render_camera = camera
	traffic._camera_scope = true
	traffic._camera_position = camera.global_position
	traffic._camera_size = camera.size
	traffic._camera_orthographic = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	traffic._camera_viewport_size = camera.get_viewport().get_visible_rect().size
	traffic._camera_bounds = Rect2(Vector2(-24,-24),traffic._camera_viewport_size+Vector2(48,48))
	traffic._prepare_coarse_cull(traffic._camera_state(camera))
	for pass_index: int in 2:
		for y: int in City.HEIGHT:
			for x: int in City.WIDTH:
				var cell := Vector2i(x, y)
				if traffic._ramp(cell) != traffic.graph.is_ramp(cell): ramp_errors += 1
				for domain: StringName in [&"road", &"highway", &"rail", &"water"]:
					if traffic._route_degree(cell, domain) != traffic.graph.degree(cell, domain): degree_errors += 1
					if (x + y) % 3 == 0 and traffic._coarse_culled_cell(cell, domain, camera) != traffic._coarse_culled(traffic.graph.center(cell, domain), camera): cull_errors += 1
	traffic._camera_scope = false
	traffic._render_camera = null
	check_eq(ramp_errors, 0, label + ": cached ramp answers equal the graph")
	check_eq(degree_errors, 0, label + ": cached degrees equal the graph")
	check_eq(cull_errors, 0, label + ": cached coarse culling equals the predicate")

func test_route_and_cull_caches_follow_revisions_and_cameras() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	check(loaded.ok, "bundled city imports")
	if not loaded.ok: return
	var city: City = loaded.city
	var traffic := CityTraffic3D.new()
	root.add_child(traffic)
	traffic.bind_city(city)
	var camera := _camera(false, 12.0, Vector3(60, 6, 72), Vector3(64, 1, 64))
	_check_caches(traffic, camera, "initial")
	_check_caches(traffic, camera, "warm")
	camera.position += Vector3(7, 2, -5)
	camera.look_at(Vector3(70, 1, 60))
	_check_caches(traffic, camera, "moved camera")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40
	_check_caches(traffic, camera, "orthographic camera")
	# Remove junction arms and whole runs, then add new road: degrees, ramps and
	# centers change under a new revision.
	var revision := traffic.graph.revision
	var roads: Array = traffic.graph.cells(&"road")
	for i: int in mini(40, roads.size()):
		var cell: Vector2i = roads[(i * 53) % roads.size()]
		if traffic.graph.degree(cell, &"road") > 2: city.building.put(cell.x, cell.y, 0)
	for i: int in mini(20, roads.size()):
		var cell: Vector2i = roads[(i * 31 + 7) % roads.size()]
		city.building.put(cell.x, cell.y, 0)
	traffic.graph.refresh()
	check_gt(traffic.graph.revision, revision, "edits rebuilt routes")
	_check_caches(traffic, camera, "after road removals")
	city.altitude.data.fill(city.altitude.data[0])
	traffic.graph.refresh()
	_check_caches(traffic, camera, "after terrain change")
	camera.queue_free()
	traffic.queue_free()
	await process_frame
