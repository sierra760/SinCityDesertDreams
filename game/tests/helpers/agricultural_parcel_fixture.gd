# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted


static func mask(points: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for p in points:
		result.append(int(p[1]) * 128 + int(p[0]))
	result.sort()
	return result


static func zone(city: City, members: PackedInt32Array) -> void:
	for i in members:
		city.zone.put(i % 128, i / 128, Zones.AGR_LOW)


static func record(id: int, members: PackedInt32Array, key: StringName = &"grain", state: StringName = &"prepared") -> Dictionary:
	var stock := {}
	var remaining := 108
	var rate := 8 if key == &"cattle_range" else (10 if key == &"sheep_pasture" else 0)
	for i in members:
		if rate > 0:
			stock[i] = mini(rate, remaining)
			remaining -= stock[i]
	var result := {"id": id, "members": members.duplicate(), "identity_index": members[0],
		"origin_index": members[0], "phase": 0 if members[0] % 128 < 64 else 1,
		"archetype": key, "state": state, "mode": &"generated", "legacy_code": 0,
		"layout_seed": id, "target_area": 16, "height": 4, "modules": [],
		"stock_units": stock, "failed_months": 0, "last_month": -1, "revision": 1}

	if state == &"active": result.modules = AgriculturalParcelGeometry.plan(result).modules
	return result


static func l_shape() -> PackedInt32Array:
	return mask([[20,20],[21,20],[20,21]])

static func u_shape() -> PackedInt32Array:
	return mask([[20,20],[22,20],[20,21],[22,21],[20,22],[21,22],[22,22]])

static func ring() -> PackedInt32Array:
	return mask([[20,20],[21,20],[22,20],[20,21],[22,21],[20,22],[21,22],[22,22]])

static func dumbbell() -> PackedInt32Array:
	return mask([[20,20],[21,20],[23,20],[24,20],[20,21],[21,21],[22,21],[23,21],[24,21],[20,22],[21,22],[23,22],[24,22]])

static func square(side: int = 3, origin: Vector2i = Vector2i(20,20)) -> PackedInt32Array:
	var members := PackedInt32Array()
	for z in range(origin.y,origin.y+side):
		for x in range(origin.x,origin.x+side): members.append(z*128+x)
	return members


static func source(city: City) -> Dictionary:
	var ctx := preload("res://tests/test_case.gd").make_context(city,7)
	var ag := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	return {"ctx":ctx,"ag":ag}


static func active_system(city: City, members: PackedInt32Array, key: StringName = &"grain") -> Dictionary:
	zone(city,members)
	var value := record(city.agricultural_parcels.available_id(),members,key,&"active")
	assert(city.agricultural_parcels.put(city,value) == OK)
	return source(city)


static func install_pair(city: City) -> City:
	for id in [1,2]:
		var members := square(2,Vector2i(20+(id-1)*2,20))
		zone(city,members)
		assert(city.agricultural_parcels.put(city,record(id,members,&"cattle_range",&"active")) == OK)
	return city


## Read the actual retained hierarchy, including transformed physics shapes.
## No production diagnostic counters or test-only getters are involved.
static func rendered_records(view: Node3D) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for retained: Dictionary in view.get("_nodes").values():
		var item := retained.duplicate(true)
		item["physical_fences"] = []
		var node: Node3D = item.node
		for shape: CollisionShape3D in node.find_children("*","CollisionShape3D",true,false):
			if shape.get_parent().name != &"OwnedFences": continue
			var box := shape.shape as BoxShape3D
			var a := shape.global_transform*Vector3(-box.size.x*.5,0,0)
			var b := shape.global_transform*Vector3(box.size.x*.5,0,0)
			item.physical_fences.append({"a":Vector2(a.x,a.z),"b":Vector2(b.x,b.z),"height":a.y})
		records.append(item)
	records.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.parcel_id < b.parcel_id)
	return records


static func all_logical_fences_have_one_physical_owner(records: Array[Dictionary]) -> bool:
	for item: Dictionary in records:
		if item.layout.profile.is_empty(): continue # Unsafe prepared remnants have no fence domain.
		var at: Transform3D = item.transform
		for edge: Dictionary in AgriculturalParcelGeometry.boundary(item.record.members):
			var a := Vector2(edge.a);var b := Vector2(edge.b)
			# Interior samples avoid legitimate shared post/corner intersections.
			for fraction: float in [.125,.375,.625,.875]:
				var sample := a.lerp(b,fraction)
				var owners := 0
				for other: Dictionary in records:
					for physical: Dictionary in other.physical_fences:
						if absf(physical.height-(at.origin.y+.965/16)) > .0001: continue
						if sample.distance_to(Geometry2D.get_closest_point_to_segment(sample,physical.a,physical.b)) < .0001: owners += 1
				if owners != 1: return false
	return true


static func rigs(node: Node) -> int:
	var count := 1 if node is Skeleton3D else 0
	for child: Node in node.get_children(): count += rigs(child)
	return count


static func herd_snapshot(herds: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in herds.get("_herds"):
		var live: Dictionary = herds.get("_herds")[key]
		var item := {}
		for field in live:
			if field not in ["root","motion"]: item[field] = live[field]
		item = item.duplicate(true)
		item.source_key = str(key)
		item.parcel_id = live.get("parcel_id",0)
		item.revision = live.get("revision",0)
		item.states = live.motion.states() if live.motion != null else []
		item.root_id = live.root.get_instance_id() if is_instance_valid(live.root) else 0
		item.root_transform = live.root.transform if is_instance_valid(live.root) else Transform3D.IDENTITY
		item.children = live.root.get_child_count() if is_instance_valid(live.root) else 0
		item.has_motion = live.motion != null
		item.poses = []
		if is_instance_valid(live.root):
			for skeleton: Skeleton3D in live.root.find_children("*","Skeleton3D",true,false):
				var poses := []
				for bone in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(bone))
				item.poses.append(poses)
		result.append(item)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.source_key < b.source_key)
	return result


static func herd_at(herds: Node3D, key: String) -> Dictionary:
	for item in herd_snapshot(herds):
		if item.source_key == key: return item
	return {}


static func all_live_herds_match_store(city: City, herds: Node3D) -> bool:
	var snapshots := herd_snapshot(herds)
	if snapshots.is_empty(): return false
	for item in snapshots:
		if not item.source_key.begins_with("parcel:"): continue
		var record := city.agricultural_parcels.record(int(item.source_key.trim_prefix("parcel:")))
		if record.is_empty() or record.state != &"active" or item.revision != record.revision: return false
		if item.transform != CityAgriculture3D.parcel_transform(city,record): return false
		if item.root_id != 0 and item.root_transform != item.transform: return false
		for pen: Dictionary in item.profile.pens:
			for spawn: Array in pen.spawns:
				if not AgricultureAssetCatalog.new().navigation_clear(Vector2(spawn[0],spawn[1]),pen,item.profile.body_radius+item.profile.turn_margin): return false
		for state: Dictionary in item.states:
			var p: Vector3 = state.position
			if not AgricultureAssetCatalog.new().navigation_clear(Vector2(p.x,p.z),item.profile.pens[state.pen_index],item.profile.body_radius+item.profile.turn_margin): return false
	return true


static func expanded(members: PackedInt32Array) -> PackedInt32Array:
	var points := []
	for index in members:
		var at := AgriculturalParcels.tile(index)-Vector2i(20,20)
		for dz in 2:
			for dx in 2: points.append([20+at.x*2+dx,20+at.y*2+dz])
	return mask(points)
