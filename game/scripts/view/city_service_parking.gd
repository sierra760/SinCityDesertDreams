# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Static lot occupants. No clocks, traffic records or driven actors until entry.
class_name CityServiceParking
extends RefCounted

# Model metres, +Z frontage. Parking grade is the authored collision slab top.
const LAYOUTS := {
	209: {"kind":&"ambulance","grade":.31,"slots":[Vector2(-4.5,14.5)],"apron":Rect2(-11.9,8.1,14.8,15.92)},
	210: {"kind":&"police","grade":.20,"slots":[Vector2(-9,15.2),Vector2(10,15.2)],"apron":Rect2(-13,8.5,29,15.52)},
	211: {"kind":&"fire_engine","grade":.32,"slots":[Vector2(.4,15),Vector2(11.5,15)],"apron":Rect2(-10.9,7.4,26.8,16.62)},
}

static func add_to(model: Node3D, city: City, rect: Rect2i, code: int) -> void:
	if not LAYOUTS.has(code): return
	var layout: Dictionary = LAYOUTS[code]
	var parking := Node3D.new()
	parking.name = "ServiceParking"
	model.add_child(parking)
	var size := CityTrafficCatalog.dimensions(layout.kind)
	var shape := BoxShape3D.new()
	shape.size = size
	for index in layout.slots.size():
		var p: Vector2 = layout.slots[index]
		var slot := Node3D.new()
		slot.name = "ServiceSlot%d" % index
		slot.position = Vector3(p.x,float(layout.grade)+.032,p.y)/16.0
		slot.rotation.y = PI
		slot.set_meta("kind",layout.kind)
		slot.set_meta("index",index)
		parking.add_child(slot)
		var mesh := MeshInstance3D.new()
		mesh.name = "Vehicle"
		mesh.mesh = CityTrafficCatalog.mesh_for(layout.kind)
		slot.add_child(mesh)
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = CityModelCatalog.SHELL_LAYER
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = size.y*.5
		body.add_child(collider)
		slot.add_child(body)
	parking.set_meta("driveway",{"city":city,"anchor":rect.position,"code":code,"transform":model.transform,
		"apron":Rect2(layout.apron.position/16.0,layout.apron.size/16.0),"grade":(float(layout.grade)+.032)/16.0})

## Join/leave the lot projection's cell index only when a lot changes.
static func index_lot(lot: Node, cells: Dictionary, add: bool) -> void:
	if not LAYOUTS.has(lot.get_meta("code",-1)): return
	var parking := lot.get_node_or_null("ServiceParking")
	if parking == null: return
	for slot: Node3D in parking.get_children():
		var cell := Vector2i(floori(slot.global_position.x),floori(slot.global_position.z))
		if add:
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(slot)
		else:
			var entries: Array = cells.get(cell,[])
			entries.erase(slot)
			if entries.is_empty(): cells.erase(cell)

## Longest half-body plus reach is under one tile. Exactly nine cell lookups,
## independent of city size, service population and neighboring ordinary lots.
static func nearest(buildings: CityBuildings3D, feet: Vector3, reach: float) -> Dictionary:
	return nearest_in(buildings._parking_cells,feet,reach)

## The same search over any slot index with this layout (Vehicle, Body).
static func nearest_in(cells: Dictionary, feet: Vector3, reach: float) -> Dictionary:
	var cell := Vector2i(floori(feet.x),floori(feet.z))
	var best: Dictionary = {}
	if cells.is_empty(): return best
	for y in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			for slot: Node3D in cells.get(Vector2i(x,y),[]):
				if slot.get_meta("claimed",false) or not slot.is_visible_in_tree(): continue
				var collider := slot.get_node("Body").get_child(0) as CollisionShape3D
				var size: Vector3 = (collider.shape as BoxShape3D).size
				var gap := ExploreActorProfile.reach_gap(feet,collider.global_transform,AABB(-size*.5,size))
				if gap > reach: continue
				reach = gap
				best = {"service":slot,"gap":gap}
	return best

static func set_claimed(slot: Node3D, batcher: Node, claimed: bool) -> void:
	if not is_instance_valid(slot): return
	slot.set_meta("claimed",claimed)
	(slot.get_node("Body") as StaticBody3D).collision_layer = 0 if claimed else CityModelCatalog.SHELL_LAYER
	batcher.set_source_visible(slot.get_node("Vehicle"),not claimed)

static func claim(slot: Node3D, actor: ExploreCar, batcher: Node) -> Dictionary:
	set_claimed(slot,batcher,true)
	var driveway: Dictionary = slot.get_parent().get_meta("driveway")
	actor.service_driveway = driveway
	return {"slot":weakref(slot),"actor":weakref(actor),"anchor":driveway.anchor,"code":driveway.code,"index":slot.get_meta("index")}

## A projected lot can be replaced during a geometry refresh. Transfer its
## occupied slot, without creating another actor or returning the driven car.
static func rebind(claims: Array[Dictionary], buildings: CityBuildings3D, batcher: Node) -> void:
	for record: Dictionary in claims:
		var actor := record.actor.get_ref() as ExploreCar
		if actor == null: continue
		actor.service_driveway = {}
		for lot: Node3D in buildings._lots_meeting([Rect2i(record.anchor,Vector2i.ONE)]):
			if lot.get_meta("cell",Vector2i(-1,-1)) != record.anchor or lot.get_meta("code",-1) != record.code: continue
			var slot := lot.get_node_or_null("ServiceParking/ServiceSlot%d" % record.index) as Node3D
			if slot == null: continue
			record.slot = weakref(slot)
			set_claimed(slot,batcher,true)
			actor.service_driveway = slot.get_parent().get_meta("driveway")

static func release(claims: Array[Dictionary], batcher: Node) -> void:
	for record: Dictionary in claims:
		set_claimed(record.slot.get_ref(),batcher,false)
	claims.clear()

## Full-footprint, ground-level forecourt permission; only actual adjoining
## road is admitted beyond its open front. Building walls still collide.
static func allows(driveway: Dictionary, at: Transform3D, size: Vector3) -> bool:
	if driveway.is_empty(): return false
	var city: City = driveway.city
	if city.building.atv(driveway.anchor) != int(driveway.code): return false
	var local: Transform3D = (driveway.transform as Transform3D).affine_inverse()*at
	if absf(local.origin.y-float(driveway.grade)) > .045: return false
	var apron: Rect2 = driveway.apron
	for x: float in [-size.x*.5,size.x*.5]:
		for z: float in [-size.z*.5,size.z*.5]:
			var corner := local*Vector3(x,0,z)
			if apron.has_point(Vector2(corner.x,corner.z)): continue
			if corner.z < 1.49: return false
			var world: Vector3 = (driveway.transform as Transform3D)*corner
			var cell := Vector2i(floori(world.x),floori(world.z))
			if not city.in_bounds(cell.x,cell.y): return false
			var code := city.building.atv(cell)
			if not NetworkShapes.in_road_family(code) or NetworkShapes.is_tunnel(code) or NetworkShapes.is_road_bridge(code): return false
	return true
