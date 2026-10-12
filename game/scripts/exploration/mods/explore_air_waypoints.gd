# SPDX-License-Identifier: GPL-3.0-or-later
## Host-only direct flight admission. Coordinates already use the engine's tile
## scale; catalogue dimensions perform the sole metres-to-tiles conversion.
class_name ExploreAirWaypoints
extends RefCounted
const MAX_DISTANCE := 64.0
const SEGMENT_LENGTH := .25

static func volume(kind: StringName) -> SphereShape3D:
	var size := CityTrafficCatalog.dimensions(kind)
	if kind == &"helicopter": size = size.max(ExploreActorProfile.geometry(ExploreActorProfile.Mode.FLY).size)
	var shape := SphereShape3D.new()
	# Enclose the entire root-relative model at any yaw, including its height.
	shape.radius = Vector3(size.x*.5,size.y,size.z*.5).length()+.002
	return shape

static func clear_segment(world: CityTraversalWorld3D, kind: StringName, from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(world) or not world.is_inside_tree() or not from.is_finite() or not to.is_finite() or kind not in [&"plane",&"helicopter"]: return false
	if from.distance_to(to) > MAX_DISTANCE: return false
	var shape := volume(kind)
	for point in [from,to]:
		if point.y-shape.radius < 0 or point.y+shape.radius > world.max_flight_y() or world.touches_water(point-Vector3.UP*shape.radius): return false
		if not world.has_clearance(Transform3D(Basis.IDENTITY,point),shape,[]): return false
	# Water is a non-solid column, so the solid sweep alone cannot exclude it.
	# Expand the short segment footprint conservatively, including bank edges.
	var low := from.min(to)-Vector3.ONE*shape.radius
	var high := from.max(to)+Vector3.ONE*shape.radius
	var minimum := Vector2i(floori(low.x),floori(low.z))
	var maximum := Vector2i(floori(high.x),floori(high.z))
	if (maximum.x-minimum.x+1)*(maximum.y-minimum.y+1) > 64: return false
	for z in range(minimum.y,maximum.y+1):
		for x in range(minimum.x,maximum.x+1):
			for region: Dictionary in world._water.get(Vector2i(x,z),[]):
				if low.y <= float(region.top)+CityTraversalWorld3D.SKIN: return false
	if from.is_equal_approx(to): return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,from)
	query.motion = to-from
	query.margin = .001
	query.collision_mask = ExploreActorProfile.WORLD | ExploreActorProfile.ACTOR
	var fractions := world.get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 1.0

static func step(record: Dictionary, delta: float, traffic: CityTraffic3D) -> void:
	if record.get("mod_hold",true) or record.get("mod_failed",false):
		record["stopped"] = true
		return
	var world: CityTraversalWorld3D = record.get("air_world")
	if not is_instance_valid(world) or world.revision != record.air_revision:
		_fail(record)
		return
	var from: Vector3 = record.air_position
	var target: Vector3 = record.air_destination
	var remaining := target-from
	var horizontal := Vector2(remaining.x,remaining.z).length()
	var limits := ExploreActorProfile.geometry(ExploreActorProfile.Mode.FLY)
	var duration := maxf(horizontal/float(limits.flight_speed),absf(remaining.y)/float(limits.vertical_speed))
	var to := from.lerp(target,minf(1.0,delta/maxf(.000001,duration)))
	if not clear_segment(world,record.kind,from,to) or not separated(traffic,record.kind,record.id,from,to):
		_fail(record)
		return
	record["air_position"] = to
	if horizontal > .00001: record["air_yaw"] = atan2(-remaining.x,-remaining.z)
	record["cell"] = Vector2i(floori(to.x),floori(to.z))
	record["speed"] = from.distance_to(to)/maxf(delta,.000001)
	record["mod_phase"] += delta*float(record.speed)*16.0
	record["stopped"] = to.is_equal_approx(target)
	if record.stopped:
		record["mod_hold"] = true
		record["mod_arrived"] = true

static func _fail(record: Dictionary) -> void:
	record["mod_hold"] = true
	record["mod_failed"] = true
	record["stopped"] = true

## Existing air records have presentation poses, not physical bodies. Conservatively
## sweep their bounding spheres too; this is bounded by shared actor/external caps.
static func separated(traffic: CityTraffic3D, kind: StringName, id: int, from: Vector3, to: Vector3) -> bool:
	var radius := volume(kind).radius
	for other: Dictionary in traffic.actors:
		if other.id == id or other.domain != &"air": continue
		var closest := Geometry3D.get_closest_point_to_segment(traffic.actor_pose(other).origin,from,to)
		if closest.distance_to(traffic.actor_pose(other).origin) <= radius+volume(other.kind).radius: return false
	for other: Dictionary in traffic._external:
		if CityTrafficCatalog.domain(other.kind) != &"air": continue
		var closest := Geometry3D.get_closest_point_to_segment(other.presentation_position,from,to)
		if closest.distance_to(other.presentation_position) <= radius+volume(other.kind).radius: return false
	return true
