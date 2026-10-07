# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A reference draw path and native MultiMesh readbacks check that packed uploads
## produce the same instances as per-instance setters.
extends "res://tests/exploration/async_test_case.gd"

class ReferenceTraffic:
	extends CityTraffic3D
	var _reference_groups: Dictionary = {}
	func _render(camera: Camera3D) -> void:
		var groups: Dictionary = {}
		var visible_count := 0
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
			var low := camera != null and (camera.size > 16.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position.distance_squared_to(pose.origin) > 400.0)
			var variant := int(a.variant) if a.type == &"pedestrian" else 0
			if low: variant %= 4
			var key := str(a.kind)+":"+str(variant)+":"+str(low)
			if not groups.has(key): groups[key] = {"kind":a.kind,"variant":variant,"low":low,"poses":[],"custom":[]}
			groups[key].poses.append(pose)
			groups[key].custom.append(Color(_elapsed*float(a.speed)*16.0+float(a.id)*.173,0.0 if a.stopped else 1.0,0,0))
			visible_count += 1
		for record: Dictionary in _external:
			if _claims.has(record.presentation_id): continue
			var position: Vector3 = record.presentation_position
			if _culled(position,camera): continue
			var low := camera != null and (camera.size > 16.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position.distance_squared_to(position) > 400)
			var key := str(record.kind)+":0:"+str(low)
			if not groups.has(key): groups[key] = {"kind":record.kind,"variant":0,"low":low,"poses":[],"custom":[]}
			groups[key].poses.append(Transform3D(Basis(Vector3.UP,record.presentation_yaw),position))
			groups[key].custom.append(Color(0,0,0,0))
			visible_count += 1
		for key: String in _batches:
			if not groups.has(key): _batches[key].multimesh.visible_instance_count = 0
		for key: String in groups:
			var group: Dictionary = groups[key]
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
			if batch.instance_count < group.poses.size(): batch.instance_count = maxi(16,ceili(float(group.poses.size())/16)*16)
			batch.visible_instance_count = group.poses.size()
			for i: int in group.poses.size():
				batch.set_instance_transform(i,group.poses[i])
				batch.set_instance_custom_data(i,group.custom[i])
		statistics["visible"] = visible_count
		_reference_groups = groups
	
	func _coarse_culled(point: Vector3, camera: Camera3D) -> bool:
		if camera == null: return false
		var distance := point.distance_to(camera.global_position)
		if distance<1.5: return false
		if camera.is_position_behind(point): return true
		var size := camera.get_viewport().get_visible_rect().size
		var radius := size.y*1.5/(camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else distance)
		var margin := Vector2.ONE*maxf(24,radius)
		return not Rect2(-margin,size+margin*2).has_point(camera.unproject_position(point))
	
	func _culled(point: Vector3, camera: Camera3D) -> bool:
		if camera == null: return false
		if camera.is_position_behind(point): return true
		var size := camera.get_viewport().get_visible_rect().size
		var screen := camera.unproject_position(point)
		return not Rect2(Vector2(-24,-24),size+Vector2(48,48)).has_point(screen)

func _city() -> City:
	var city := flat_city()
	for y: int in [20,24,28]:
		for x: int in range(10,52):
			city.building.put(x,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	for x: int in range(20,28): city.terrain.put(x,40,Terrain.SURFACE)
	return city

func _actors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in 54:
		var pedestrian := i%3 == 0
		result.append({"id":i+1,"kind":&"pedestrian" if pedestrian else [&"car",&"bus",&"train",&"sailboat"][i%4],
			"type":&"pedestrian" if pedestrian else &"road","domain":&"road","cell":Vector2i(11+i%38,20+(i%3)*4),
			"previous":Vector2i(10+i%38,20+(i%3)*4),"next":Vector2i(12+i%38,20+(i%3)*4),
			"lane":0,"side":1.0,"t":float(i%7)/9,"speed":.075 if pedestrian else 1.05,"turns":0,
			"stopped":false,"variant":i%16})
	return result

func _compare(actual: CityTraffic3D, reference: ReferenceTraffic) -> void:
	check_eq(actual.actors,reference.actors,"logic history and sampled/rendered poses remain exact")
	check_eq(actual.statistics.visible,reference.statistics.visible,"same actors survive culling and claims")
	check_eq(actual._batches.keys(),reference._batches.keys(),"same near/far/style batches")
	for key: String in reference._batches:
		var a: MultiMesh = actual._batches[key].multimesh
		var b: MultiMesh = reference._batches[key].multimesh
		check_eq(a.visible_instance_count,b.visible_instance_count,"same active instance count")
		if not reference._reference_groups.has(key): continue
		var group: Dictionary = reference._reference_groups[key]
		if DisplayServer.get_name() != "headless":
			for i: int in group.poses.size():
				check_eq(a.get_instance_transform(i),b.get_instance_transform(i),"native transform readback matches per-instance setters")
				check_eq(a.get_instance_custom_data(i),b.get_instance_custom_data(i),"native custom Color readback matches per-instance setters")

func test_buffers_match_reference_through_camera_claim_pause_cadence_and_visibility_changes() -> void:
	var city := _city()
	var actual := CityTraffic3D.new()
	var reference := ReferenceTraffic.new()
	root.add_child(actual); root.add_child(reference)
	actual.bind_city(city); reference.bind_city(city)
	actual.actors.assign(_actors()); reference.actors.assign(_actors())
	actual._dirty=false; reference._dirty=false
	actual._refresh_left=1000; reference._refresh_left=1000
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(30,35,48); camera.look_at(Vector3(30,2.5,24))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=80
	var records := [{"kind":&"fire_crew","pos":Vector2(25,20),"heading":3},
		{"kind":&"ship","pos":Vector2(24,40),"heading":2}]
	for phase: int in 12:
		if phase == 2: camera.size=8
		if phase == 3: camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		if phase == 4: camera.position=Vector3(500,35,510);camera.look_at(Vector3(500,2.5,500))
		if phase == 5: camera.position=Vector3(24,18,32);camera.look_at(Vector3(24,2.5,24))
		if phase == 6:
			actual._claims[2]=true;reference._claims[2]=true
			actual._claims[-1-CityTrafficCatalog.vehicle_kinds().find(&"fire_engine")*64]=true
			reference._claims[-1-CityTrafficCatalog.vehicle_kinds().find(&"fire_engine")*64]=true
		if phase == 7: actual._claims.clear();reference._claims.clear()
		if phase == 9: records.clear()
		if phase == 10: actual.actors.resize(9);reference.actors.resize(9)
		var paused := phase in [1,7,11]
		var enabled := phase != 8
		actual.advance(.15 if phase == 5 else 1.0/60,paused,records,camera if phase>0 else null,enabled)
		reference.advance(.15 if phase == 5 else 1.0/60,paused,records,camera if phase>0 else null,enabled)
		_compare(actual,reference)
	actual.bind_city(_city());reference.bind_city(actual.graph.city)
	for batch: MultiMeshInstance3D in actual._batches.values(): check_eq(batch.multimesh.visible_instance_count,0,"city replacement hides retained buffer rows")
	camera.free();actual.free();reference.free()
	await process_frame

func test_catalog_direct_kind_queries_preserve_indices_and_detached_public_list() -> void:
	var kinds := CityTrafficCatalog.vehicle_kinds()
	for i: int in kinds.size():
		check(CityTrafficCatalog.is_vehicle_kind(kinds[i]),"catalog retains vehicle membership")
		check_eq(CityTrafficCatalog.vehicle_kind_index(kinds[i]),i,"stable external record index")
	check(not CityTrafficCatalog.is_vehicle_kind(&"pedestrian"),"pedestrian is not a vehicle")
	check_eq(CityTrafficCatalog.vehicle_kind_index(&"unknown"),-1,"unknown vehicle has no stable index")
	kinds.clear()
	check_eq(CityTrafficCatalog.vehicle_kinds().size(),18,"public caller still owns a detached list")

func test_paused_cache_observes_raw_actor_claim_camera_and_viewport_changes() -> void:
	var original_viewport_size := root.size
	var actual := CityTraffic3D.new()
	var reference := ReferenceTraffic.new()
	root.add_child(actual);root.add_child(reference)
	actual.bind_city(_city());reference.bind_city(actual.graph.city)
	actual.actors.assign(_actors());reference.actors.assign(_actors())
	actual._dirty=false;reference._dirty=false
	actual._refresh_left=1000;reference._refresh_left=1000
	var camera := Camera3D.new();root.add_child(camera)
	camera.position=Vector3(30,35,48);camera.look_at(Vector3(30,2.5,24))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	actual.advance(.1,true,[],camera);reference.advance(.1,true,[],camera)
	check_gt(int(actual.statistics.get("render_cache_hits",0)),0,"unchanged paused presentation avoids another upload")
	_compare(actual,reference)
	var previous_hits := int(actual.statistics.get("render_cache_hits",0))
	actual.actors[0].t=.85;reference.actors[0].t=.85
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	check_eq(int(actual.statistics.get("render_cache_hits",0)),previous_hits,"raw actor mutation cannot reuse cached output")
	_compare(actual,reference)
	actual._claims[1]=true;reference._claims[1]=true
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	check_eq(int(actual.statistics.get("render_cache_hits",0)),previous_hits,"claim mutation cannot reuse cached output")
	_compare(actual,reference)
	for change: int in 8:
		if change == 0: camera.size=8
		if change == 1: camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		if change == 2: camera.fov=40
		if change == 3: camera.keep_aspect=Camera3D.KEEP_WIDTH
		if change == 4: camera.h_offset=.4;camera.v_offset=.7
		if change == 5: camera.projection=Camera3D.PROJECTION_FRUSTUM;camera.frustum_offset=Vector2(.25,-.1)
		if change == 6: camera.position=Vector3(32,25,36);camera.look_at(Vector3(30,2.5,24))
		if change == 7: root.size+=Vector2i(61,37)
		actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
		check_eq(int(actual.statistics.get("render_cache_hits",0)),previous_hits,"projection/display changes cannot reuse cached output")
		_compare(actual,reference)
	actual.advance(0,true,[],camera,false);reference.advance(0,true,[],camera,false)
	actual.advance(0,true,[],camera,true);reference.advance(0,true,[],camera,true)
	_compare(actual,reference)
	check_eq(int(actual.statistics.get("render_cache_hits",0)),previous_hits,"hidden interval invalidates cached output")
	var release_position := actual.actor_pose(actual.actors[1]).origin
	actual.release_vehicle({"id":2},release_position)
	reference.release_vehicle({"id":2},release_position)
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	_compare(actual,reference)
	check_eq(int(actual.statistics.get("render_cache_hits",0)),previous_hits,"release immediately updates the rendered actor")
	actual.set_reserved_rail_cells([Vector2i(20,20)])
	reference.set_reserved_rail_cells([Vector2i(20,20)])
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	_compare(actual,reference)
	actual.graph.city.building.put(20,20,0)
	actual.invalidate();reference.invalidate()
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	_compare(actual,reference)
	root.size=original_viewport_size
	camera.free();actual.free();reference.free()
	await process_frame

class CountedTraffic extends CityTraffic3D:
	var state_samples := 0
	func _render_state(camera: Camera3D) -> Array:
		state_samples += 1
		return super._render_state(camera)

func test_paused_pan_avoids_full_cache_snapshots_then_resumes_exact_stationary_cache() -> void:
	var actual := CountedTraffic.new()
	var reference := ReferenceTraffic.new()
	root.add_child(actual);root.add_child(reference)
	actual.bind_city(_city());reference.bind_city(actual.graph.city)
	actual.actors.assign(_actors());reference.actors.assign(_actors())
	actual._dirty=false;reference._dirty=false
	actual._refresh_left=1000;reference._refresh_left=1000
	var camera := Camera3D.new();root.add_child(camera)
	camera.position=Vector3(30,35,48);camera.look_at(Vector3(30,2.5,24))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	var before_samples := actual.state_samples
	for frame: int in 48:
		camera.position.x += .1
		if frame == 24: camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		if frame >= 24: camera.position.z -= .05
		if frame == 30: camera.position.x += 500
		if frame == 34: camera.position.x -= 500
		if frame == 40: camera.fov=55
		if frame == 4: actual.actors[0].t=.85;reference.actors[0].t=.85
		if frame == 8: actual._claims[2]=true;reference._claims[2]=true
		if frame == 12: actual._claims.clear();reference._claims.clear()
		if frame == 16: camera.size=16
		actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
		_compare(actual,reference)
	check_eq(actual.state_samples,before_samples,"each changing paused camera renders without hashing/deep-copying full actor state")
	var hits := int(actual.statistics.get("render_cache_hits",0))
	for frame: int in 3:
		actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
		_compare(actual,reference)
	check_gt(int(actual.statistics.get("render_cache_hits",0)),hits,"settled camera seeds then hits exact cache")
	actual.actors[1].t=.9;reference.actors[1].t=.9
	actual.advance(0,true,[],camera);reference.advance(0,true,[],camera)
	_compare(actual,reference)
	for frame: int in 5:
		actual.advance(1.0/60,false,[],camera);reference.advance(1.0/60,false,[],camera)
		_compare(actual,reference)
	camera.free();actual.free();reference.free()
	await process_frame
