# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name CityAgriculture3D
extends Node3D
## Retained exact-footprint static farms. All geometry below a parcel is metres;
## the one parcel transform supplies scale and actual-member rigid support grade.
signal changed_regions(regions: Array[Rect2i])
const G := preload("res://scripts/core/agricultural_parcel_geometry.gd")
const P := preload("res://scripts/core/agricultural_parcels.gd")
const SCALE := 1.0 / 16.0
var _city: City
var _catalog: CityModelCatalog
var _nodes: Dictionary = {}
var _pending: Dictionary = {}
var _regions: Array[Rect2i] = []
var _queued := false
var _modules: Dictionary = {}
var _sections: Dictionary = {}
var _plants: Dictionary = {}
var _wire_material: Material
var _post_mesh: Mesh
var _ground_materials: Dictionary = {}

func bind_city(city: City, catalog: CityModelCatalog) -> void:
	if city == _city and catalog == _catalog: return
	clear()
	_city = city
	_catalog = catalog
	if city == null: return
	city.agricultural_parcels.changed.connect(apply_change)
	for record: Dictionary in city.agricultural_parcels.records(): _pending[record.id] = true
	flush_changes()

func clear() -> void:
	if _city != null and _city.agricultural_parcels.changed.is_connected(apply_change):
		_city.agricultural_parcels.changed.disconnect(apply_change)
	_city = null
	_pending.clear();_regions.clear();_nodes.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()

func record_for_parcel(id: int) -> Dictionary:
	return _nodes.get(id,{}).duplicate(true)

static func parcel_transform(city: City, record: Dictionary) -> Transform3D:
	var base := -INF
	for index: int in record.members:
		for corner: Vector3 in CityGeometry3D.visible_cell_corners(city,P.tile(index)):
			base = maxf(base,corner.y)
	var origin := Vector2(P.tile(record.origin_index))
	if record.mode != &"generated":
		var rect := P.bounds(record.members)
		origin = Vector2(rect.position) + Vector2(rect.size)*.5
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*SCALE),Vector3(origin.x,base,origin.y))

func apply_change(change: Dictionary) -> Array[Rect2i]:
	var affected: Array[Rect2i] = []
	for field in ["old_bounds","new_bounds"]:
		var rect: Rect2i = change.get(field,Rect2i())
		if rect.has_area(): affected.append(rect)
	for id: int in change.get("ids",[]): _pending[id] = true
	for id: int in change.get("neighbor_ids",[]):
		_pending[id] = true
		var record := _city.agricultural_parcels.record(id)
		if not record.is_empty(): affected.append(P.bounds(record.members))
	_regions.append_array(affected)
	if not _queued:
		_queued = true
		flush_changes.call_deferred()
	return affected

## Terrain edits can affect a rigid floor far from the fixed origin. Query full
## member bounds; exact support inputs and ownership decide mesh retention.
func update_regions(regions: Array[Rect2i]) -> void:
	for id: int in _nodes:
		for region in regions:
			if _nodes[id].bounds.grow(1).intersects(region):
				_pending[id] = true
				break
	flush_changes()

func flush_changes() -> void:
	_queued = false
	if _city == null: return
	var affected := _regions.duplicate()
	_regions.clear()
	var pending := _pending.duplicate()
	_pending.clear()
	# A remote corner can change this parcel's entire rigid support plane.
	# Only its direct member neighbors can change physical fence ownership;
	# enqueue those before rebuilding, even when outside the dirty region.
	for id: int in pending.keys():
		var record := _city.agricultural_parcels.record(id)
		var previous: Dictionary = _nodes.get(id,{})
		if record.is_empty() or previous.is_empty() or previous.transform == parcel_transform(_city,record): continue
		for index: int in record.members:
			var cell := P.tile(index)
			for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var other := _city.agricultural_parcels.id_at(cell+offset)
				if other != 0 and other != id: pending[other] = true
	var layouts := {}
	for id: int in pending:
		var record := _city.agricultural_parcels.record(id)
		var previous: Dictionary = _nodes.get(id,{})
		if record.is_empty():
			if not previous.is_empty():
				affected.append(previous.bounds)
				remove_child(previous.node);previous.node.queue_free();_nodes.erase(id)
			continue
		var at := parcel_transform(_city,record)
		var layout := _layout(record,layouts)
		var support := PackedVector3Array()
		for index: int in record.members:
			support.append_array(CityGeometry3D.visible_cell_corners(_city,P.tile(index)))
		var fences := _fences(record,at.origin.y,layout,layouts)
		if not previous.is_empty() and G.presentation_inputs(previous.record) == G.presentation_inputs(record) and previous.transform == at and previous.support == support and previous.fence_segments == fences:
			previous.revision = record.revision
			previous.record = record
			continue
		if not previous.is_empty():
			affected.append(previous.bounds)
			remove_child(previous.node);previous.node.queue_free()
		var node := _build(record,at,fences)
		var rect := P.bounds(record.members)
		add_child(node)
		_nodes[id] = {"parcel_id":id,"source_key":"parcel:%d"%id,"revision":record.revision,
			"record":record,"layout":layout,"support":support,"node":node,"transform":at,"bounds":rect,"fence_segments":fences}
		affected.append(rect)
	if not affected.is_empty(): changed_regions.emit(affected)

## Cache shared geometry plans per flush and retain them with each node for
## later static updates and herd consumers; no duplicate navigation planning.
func _layout(record: Dictionary,layouts: Dictionary) -> Dictionary:
	if not layouts.has(record.id):
		var previous: Dictionary = _nodes.get(record.id,{})
		layouts[record.id] = previous.layout if not previous.is_empty() and G.layout_inputs(previous.record) == G.layout_inputs(record) else G.plan(record)
	return layouts[record.id]

func _fences(record: Dictionary,base: float,plan: Dictionary,layouts: Dictionary) -> Array:
	if record.mode != &"generated" or record.archetype not in [&"cattle_range",&"sheep_pasture"]: return []
	# Geometry owns the loops, gate, and clearance; the presenter only chooses
	# physical ownership between coplanar neighboring livestock domains.
	if plan.profile.is_empty(): return []
	var result: Array = []
	var origin := Vector2(P.tile(record.origin_index))*16
	for segment: Dictionary in plan.profile.pens[0].fences:
		var a := Vector2(segment.a[0],segment.a[1])
		var b := Vector2(segment.b[0],segment.b[1])
		var d := (b-a).normalized()
		var outside := (a+b)*.5+origin+Vector2(d.y,-d.x)*.2
		var other := _city.agricultural_parcels.id_at(Vector2i(floori(outside.x/16),floori(outside.y/16)))
		if other != 0 and other != record.id:
			var neighbor := _city.agricultural_parcels.record(other)
			if neighbor.mode != &"generated" or neighbor.archetype not in [&"cattle_range",&"sheep_pasture"] or absf(parcel_transform(_city,neighbor).origin.y-base) > .001:
				other = 0
			else:
				# Small prepared remnants have no physical fence domain. Yield
				# only to a real matching segment in the neighbor's closed profile.
				var neighbor_plan := _layout(neighbor,layouts)
				var matching := false
				if not neighbor_plan.profile.is_empty():
					var neighbor_origin := Vector2(P.tile(neighbor.origin_index))*16
					var midpoint := (a+b)*.5+origin-neighbor_origin
					for fence: Dictionary in neighbor_plan.profile.pens[0].fences:
						var start := Vector2(fence.a[0],fence.a[1])
						var end := Vector2(fence.b[0],fence.b[1])
						if midpoint.distance_to(Geometry2D.get_closest_point_to_segment(midpoint,start,end)) < .001:
							matching = true
							break
				if not matching: other = 0
		if G.fence_owner(record.id,other) == record.id:
			var owned := segment.duplicate(true)
			# A coplanar shared boundary uses sheep infill in either ID order.
			if other != 0 and _city.agricultural_parcels.record(other).archetype == &"sheep_pasture": owned.style = "woven_wire"
			result.append(owned)
	return result

func _build(record: Dictionary,at: Transform3D,fences: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "Parcel%d"%record.id
	node.transform = at
	node.set_meta("batch_region",P.bounds(record.members))
	node.set_meta("batch_immutable",true)
	node.set_meta("source_key","parcel:%d"%record.id)
	if record.mode != &"generated":
		var code: int = record.legacy_code if record.mode == &"legacy" else (record.legacy_code if record.state == &"active" else AgricultureParams.state_id(record.state,P.bounds(record.members).size.x))
		var template := _catalog.instantiate_model(code) if _catalog != null else null
		if template != null:
			template.name = "SquareTemplate"
			# Catalog wraps the original in a metre-to-tile child transform.
			# Undo only that scale; this parcel root supplies the same scale once.
			template.scale = Vector3.ONE*16
			node.add_child(template)
	else:
		_ground(node,record)
		for pose: Dictionary in record.modules:
			var module := _module(String(pose.key)).instantiate() as Node3D
			module.name = String(pose.key)
			module.position = pose.at
			module.rotation.y = pose.yaw*PI*.5
			# Authored envelope meshes import as hollow concave triangle shells.
			# The shared module contract treats the entire AABB as occupied, so
			# use its solid primitive for both boundary contact and safe placement.
			for imported: CollisionObject3D in module.find_children("*","CollisionObject3D",true,false):
				imported.get_parent().remove_child(imported)
				imported.free()
			var envelope := StaticBody3D.new()
			envelope.name = "ModuleEnvelope"
			envelope.collision_layer = CityModelCatalog.SHELL_LAYER
			envelope.collision_mask = 0
			module.add_child(envelope)
			var bounds: Array = G._modules().modules[String(pose.key)].collision_bounds
			var low := Vector3(bounds[0],bounds[1],bounds[2])
			var high := Vector3(bounds[3],bounds[4],bounds[5])
			_box(envelope,(low+high)*.5,high-low)
			node.add_child(module)
		if record.state == &"active" and record.archetype in [&"grain",&"alfalfa",&"vegetables"]: _rows(node,record)
		_fence_meshes(node,fences)
		if record.state == &"active" and record.archetype in [&"cattle_range",&"sheep_pasture"]: _pasture_cover(node,record)
	_queries(node,record)
	return node

func _module(key: String) -> PackedScene:
	if not _modules.has(key): _modules[key] = load(G._modules().modules[key].path)
	return _modules[key]

## Sparse original inland dry tufts. These are render-only, outside all module
## envelopes, and consume only the actual triangle budget left by enclosure.
func _pasture_cover(node: Node3D,record: Dictionary) -> void:
	var remaining := mini(record.members.size()*2,maxi(0,(20000-_visible_triangles(node))/8))
	var origin := P.tile(record.origin_index)
	var surfaces := {}
	for slot in 2:
		for index: int in record.members:
			if remaining <= 0: break
			var cell := P.tile(index)-origin
			var seed := index*1103515245+int(record.layout_seed)*12345+slot*7919
			var at := Vector2(cell.x*16+2+posmod(seed,1200)*.01,cell.y*16+2+posmod(seed/128,1200)*.01)
			var clear := true
			for pose: Dictionary in record.modules:
				var bounds: Array = G._box(pose,"placement_bounds").bounds
				if at.x>bounds[0]-.6 and at.x<bounds[2]+.6 and at.y>bounds[1]-.6 and at.y<bounds[3]+.6: clear = false;break
			if not clear: continue
			var material: Material = _ground_materials["farm_sage" if posmod(seed,4)==0 else "farm_grain"]
			var height := .25+posmod(seed,30)*.01
			for leaf in 4:
				var angle := leaf*PI*.5+posmod(seed,628)*.01
				var d := Vector2(cos(angle),sin(angle))
				var a := Vector3(at.x-.06*d.y,G.GROUND,at.y+.06*d.x)
				var b := Vector3(at.x+.06*d.y,G.GROUND,at.y-.06*d.x)
				var c := Vector3(at.x+d.x*.3,G.GROUND+height*.65,at.y+d.y*.3)
				var tip := Vector3(at.x+d.x*.135,G.GROUND+height,at.y+d.y*.135)
				_triangle(surfaces,material,a,b,c);_triangle(surfaces,material,a,c,tip)
			remaining -= 1
	_meshes(node,surfaces,"DryPastureTufts")

func _queries(node: Node3D,record: Dictionary) -> void:
	var inverse := node.transform.affine_inverse()
	for index: int in record.members:
		var cell := P.tile(index)
		var position := inverse*Vector3(cell.x+.5,node.position.y,cell.y+.5)
		var body := StaticBody3D.new()
		body.name = "Query%d"%index
		body.collision_layer = CityBuildings3D.QUERY_LAYER
		body.collision_mask = 0
		body.set_meta("cell",cell)
		node.add_child(body)
		_box(body,Vector3(position.x,2,position.z),Vector3(16,4,16))

func _box(parent: Node,center: Vector3,size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	parent.add_child(shape)
	return shape

func _ground_material(record: Dictionary) -> Material:
	var dry: bool = record.archetype in [&"cattle_range",&"sheep_pasture"] or record.state == &"dormant"
	var key := "farm_dry" if dry else "farm_soil"
	if _ground_materials.has(key): return _ground_materials[key]
	if not dry:
		for section: Dictionary in _cross_sections("grain_strip"):
			if section.material.resource_name == key:
				_ground_materials[key] = section.material
				return section.material
	# Original pasture swatch is packed in the accepted full farm model; load
	# its existing ID only, share the material, and release the temporary scene.
	var path := CityModelCatalog.ROOT+"%d-blender.glb"%AgricultureParams.building_id(&"cattle_range")
	var source := (load(path) as PackedScene).instantiate()
	for instance: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if material.resource_name in [key,"farm_sage","farm_grain"]: _ground_materials[material.resource_name] = material
	source.free()
	return _ground_materials.get(key)

func _ground(node: Node3D,record: Dictionary) -> void:
	var surfaces := {}
	var origin := P.tile(record.origin_index)
	var soil := _ground_material(record)
	var body := StaticBody3D.new()
	body.name = "MemberFloors"
	body.collision_layer = CityModelCatalog.SHELL_LAYER
	body.collision_mask = 0
	node.add_child(body)
	for index: int in record.members:
		var cell := P.tile(index)
		var p := Vector3((cell.x-origin.x)*16,G.GROUND,(cell.y-origin.y)*16)
		_quad(surfaces,soil,p,p+Vector3(0,0,16),p+Vector3(16,0,16),p+Vector3(16,0,0))
		var low := node.position.y
		for corner: Vector3 in CityGeometry3D.visible_cell_corners(_city,cell): low = minf(low,corner.y)
		var bottom := (low-node.position.y)*16-.02
		_box(body,p+Vector3(8,(bottom-G.GROUND)*.5,8),Vector3(16,G.GROUND-bottom,16))
	# Only the true outer/hole boundary receives a skirt; there are no internal
	# tile slab walls. Each endpoint contacts its actual member terrain corner.
	for edge: Dictionary in G.boundary(record.members):
		var delta: Vector2i = edge.b-edge.a
		var inside := (Vector2(edge.a)+Vector2(edge.b))*.5+Vector2(-delta.y,delta.x)*.1
		var cell := Vector2i(floori(inside.x),floori(inside.y))
		var corners := CityGeometry3D.visible_cell_corners(_city,cell)
		var a := Vector3((edge.a.x-origin.x)*16,G.GROUND,(edge.a.y-origin.y)*16)
		var b := Vector3((edge.b.x-origin.x)*16,G.GROUND,(edge.b.y-origin.y)*16)
		var low_a := a;var low_b := b
		for corner: Vector3 in corners:
			if Vector2(corner.x,corner.z).is_equal_approx(Vector2(edge.a)): low_a.y = (corner.y-node.position.y)*16-.02
			if Vector2(corner.x,corner.z).is_equal_approx(Vector2(edge.b)): low_b.y = (corner.y-node.position.y)*16-.02
		_quad(surfaces,soil,a,b,low_b,low_a)
	_meshes(node,surfaces,"Ground")

## Extract bed/irrigation XY cross sections from the accepted metre unit.
## Only these continuous materials are extruded, with metre-space UVs.
## Finite crop canopies retain their complete original 3D triangles below.
func _cross_sections(key: String) -> Array:
	if _sections.has(key): return _sections[key]
	var source := _module(key).instantiate()
	var result: Array = []
	for instance: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var at := instance.transform
		var parent := instance.get_parent()
		while parent != source:
			if parent is Node3D: at = parent.transform*at
			parent = parent.get_parent()
		for surface in instance.mesh.get_surface_count():
			if instance.get_active_material(surface).resource_name not in ["farm_soil","farm_dark"]: continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var groups: Array = []
			for i in range(0,indices.size(),3):
				var triangle := {}
				for j in 3:
					var p: Vector3 = at*vertices[indices[i+j]]
					triangle[Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))] = p
				var merged := triangle
				for g in range(groups.size()-1,-1,-1):
					var joins := false
					for p in triangle:
						if groups[g].has(p): joins = true;break
					if joins: merged.merge(groups[g]);groups.remove_at(g)
				groups.append(merged)
			for group: Dictionary in groups:
				var points := PackedVector2Array()
				for p: Vector3 in group.values(): points.append(Vector2(p.x,p.y))
				var hull := Geometry2D.convex_hull(points)
				if hull.size() > 3:
					hull.resize(hull.size()-1)
					result.append({"points":hull,"material":instance.get_active_material(surface)})
	source.free()
	_sections[key] = result
	return result

func _row_spans(record: Dictionary,step: float) -> Array:
	var origin := P.tile(record.origin_index)
	var bounds := P.bounds(record.members)
	var mask := {}
	for index: int in record.members: mask[P.tile(index)] = true
	var obstacles: Array = []
	for pose: Dictionary in record.modules: obstacles.append(G._box(pose,"placement_bounds").bounds)
	var spans: Array = []
	var x := (bounds.position.x-origin.x)*16+step*.5
	while x < (bounds.end.x-origin.x)*16:
		var ranges: Array[Vector2] = []
		for y in range(bounds.position.y,bounds.end.y):
			if not mask.has(Vector2i(origin.x+floori(x/16),y)): continue
			var lo := float((y-origin.y)*16)
			if not ranges.is_empty() and is_equal_approx(ranges[-1].y,lo): ranges[-1].y += 16
			else: ranges.append(Vector2(lo,lo+16))
		for obstacle: Array in obstacles:
			if x+.5 < obstacle[0]-.2 or x-.5 > obstacle[2]+.2: continue
			var clipped: Array[Vector2] = []
			for r in ranges:
				if r.y <= obstacle[1]-.2 or r.x >= obstacle[3]+.2: clipped.append(r)
				else:
					if r.x < obstacle[1]-.2: clipped.append(Vector2(r.x,obstacle[1]-.2))
					if r.y > obstacle[3]+.2: clipped.append(Vector2(obstacle[3]+.2,r.y))
			ranges = clipped
		for r in ranges:
			if r.y-r.x > .1: spans.append(Vector3(x,r.x,r.y))
		x += step
	return spans

## Keep the complete finite 3D seedling triangles; only bed and irrigation
## cross sections may be extruded. All copies contribute to the parcel cap.
func _plant_parts(key: String) -> Array:
	if _plants.has(key): return _plants[key]
	var source := _module(key).instantiate()
	var parts: Array = []
	for instance: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var at := instance.transform
		var parent := instance.get_parent()
		while parent != source:
			if parent is Node3D: at = parent.transform*at
			parent = parent.get_parent()
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if material.resource_name in ["farm_soil","farm_dark"]: continue
			var points := PackedVector3Array()
			for point: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: points.append(at*point)
			var indices: PackedInt32Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			var triangles := PackedVector3Array()
			for i in indices: triangles.append(points[i])
			parts.append({"points":triangles,"material":material})
	source.free()
	_plants[key] = parts
	return parts

func _visible_triangles(node: Node3D) -> int:
	var count := 0
	for instance: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if instance.visible and instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: count += instance.mesh.get_faces().size()/3
	return count

func _plant_offsets(spans: Array,spacing: float,low: float,high: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span: Vector3 in spans:
		var length := span.z-span.y
		var depth := high-low
		if length < depth+.08: continue
		var count := maxi(1,floori((length-depth-.08)/spacing)+1)
		# Centre each finite group inside its clipped span, never across holes
		# or a core obstacle, including the short rows beside the shed.
		var first := (span.y+span.z-(count-1)*spacing-low-high)*.5
		for i in count: result.append(Vector2(span.x,first+i*spacing))
	return result

func _rows(node: Node3D,record: Dictionary) -> void:
	var key := "vegetable_strip" if record.archetype == &"vegetables" else String(record.archetype)+"_strip"
	var sections := _cross_sections(key)
	var plants := _plant_parts(key)
	var bed_cost := 0
	for section: Dictionary in sections: bed_cost += section.points.size()*4-4
	var plant_cost := 0
	var low := INF;var high := -INF
	for part: Dictionary in plants:
		plant_cost += part.points.size()/3
		for point: Vector3 in part.points:
			low = minf(low,point.z);high = maxf(high,point.z)
	var step := 2.0
	var spacing := 1.15
	var spans := _row_spans(record,step)
	var offsets := _plant_offsets(spans,spacing,low,high)
	var budget := 20000-_visible_triangles(node)-16
	while spans.size()*bed_cost+offsets.size()*plant_cost > budget:
		# Wider row spacing and finite-group spacing trade density evenly;
		# neither shape nor metre scale of any seedling changes.
		step += .25;spacing += .125
		spans = _row_spans(record,step)
		offsets = _plant_offsets(spans,spacing,low,high)
	var surfaces := {}
	for span: Vector3 in spans:
		for section: Dictionary in sections: _extrude(surfaces,section,span.x,span.y,span.z)
	for offset: Vector2 in offsets:
		for part: Dictionary in plants:
			var delta := Vector3(offset.x,G.GROUND,offset.y)
			for i in range(0,part.points.size(),3): _triangle(surfaces,part.material,part.points[i]+delta,part.points[i+1]+delta,part.points[i+2]+delta)
	_meshes(node,surfaces,"CropRows")
	node.get_node("CropRows").set_meta("plant_spacing",spacing)
	node.get_node("CropRows").set_meta("plant_copies",offsets.size())
	node.get_node("CropRows").set_meta("row_spacing",step)

func _extrude(surfaces: Dictionary,section: Dictionary,x: float,start: float,end: float) -> void:
	var points: PackedVector2Array = section.points
	var front := PackedVector3Array();var back := PackedVector3Array()
	for p in points:
		front.append(Vector3(x+p.x,G.GROUND+p.y,start))
		back.append(Vector3(x+p.x,G.GROUND+p.y,end))
	for i in points.size():
		var next := (i+1)%points.size()
		_quad(surfaces,section.material,front[i],back[i],back[next],front[next])
	for i in range(1,points.size()-1):
		_triangle(surfaces,section.material,front[0],front[i],front[i+1])
		_triangle(surfaces,section.material,back[0],back[i+1],back[i])

func _fence_meshes(node: Node3D,segments: Array) -> void:
	var rails := _module("fence_rail").instantiate()
	var rail_material: Material
	for mesh: MeshInstance3D in rails.find_children("*","MeshInstance3D",true,false):
		for s in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(s)
			if material.resource_name == "farm_metal": rail_material = material
	rails.free()
	var surfaces := {}
	var posts := {}
	var merged: Array = []
	for segment: Dictionary in segments:
		var a := Vector2(segment.a[0],segment.a[1]);var b := Vector2(segment.b[0],segment.b[1])
		if not merged.is_empty() and not segment.gate and not merged[-1].gate and merged[-1].style == segment.style and merged[-1].b == a and (merged[-1].b-merged[-1].a).normalized().is_equal_approx((b-a).normalized()): merged[-1].b = b
		else: merged.append({"a":a,"b":b,"gate":segment.gate,"style":segment.style})
	# Count complete source post/gate copies and every emitted wire before
	# choosing a deterministic mesh pitch for extreme concave perimeters.
	var post_spacing := 2.6
	var wire_spacing := .55
	while true:
		var planned_posts := {}
		var fixed_cost := _visible_triangles(node)
		var wire_cost := 0
		for segment: Dictionary in merged:
			var length: float = segment.a.distance_to(segment.b)
			if segment.gate:
				fixed_cost += int(G._modules().modules.fence_gate.triangles)
			else:
				fixed_cost += 14 if segment.style == "woven_wire" else 36
				for i in ceili(length/post_spacing)+1: planned_posts[segment.a.lerp(segment.b,float(i)/ceili(length/post_spacing))] = true
				if segment.style == "woven_wire": wire_cost += 2*(ceili(length/wire_spacing)-1)
		fixed_cost += planned_posts.size()*_visible_post_mesh().get_faces().size()/3
		if fixed_cost+wire_cost <= 19984: break
		if fixed_cost > 19984: post_spacing += .1
		wire_spacing += .1
	node.set_meta("wire_spacing",wire_spacing)
	node.set_meta("post_spacing",post_spacing)

	var body := StaticBody3D.new()
	body.name = "OwnedFences"
	body.collision_layer = CityModelCatalog.SHELL_LAYER
	body.collision_mask = 0
	node.add_child(body)
	for segment: Dictionary in merged:
		var a: Vector2 = segment.a;var b: Vector2 = segment.b
		var length := a.distance_to(b)
		var shape := _box(body,Vector3((a.x+b.x)*.5,G.GROUND+.825,(a.y+b.y)*.5),Vector3(length,1.65,.16))
		shape.rotation.y = -atan2(b.y-a.y,b.x-a.x)
		shape.set_meta("fence_segment",segment)
		if segment.gate:
			var gate := _module("fence_gate").instantiate() as Node3D
			# The emitted shared shape already supplies the closed collision.
			for collision: CollisionObject3D in gate.find_children("*","CollisionObject3D",true,false): collision.collision_layer = 0
			gate.position = Vector3((a.x+b.x)*.5,G.GROUND,(a.y+b.y)*.5)
			gate.rotation.y = shape.rotation.y
			node.add_child(gate)
		else:
			if segment.style == "woven_wire":
				# Two-sided thin woven strips retain the original seven-wire grid
				# without cylindrical rail cost at a concave maximum perimeter.
				if _wire_material == null:
					_wire_material = rail_material.duplicate()
					_wire_material.cull_mode = BaseMaterial3D.CULL_DISABLED
				for y: float in [.25,.5,.75,1.0,1.25,1.5,1.65]:
					_quad(surfaces,_wire_material,Vector3(a.x,y-.009+G.GROUND,a.y),Vector3(b.x,y-.009+G.GROUND,b.y),Vector3(b.x,y+.009+G.GROUND,b.y),Vector3(a.x,y+.009+G.GROUND,a.y))
				var n := ceili(length/wire_spacing)
				var d := (b-a).normalized()*.009
				for i in range(1,n):
					var point := a.lerp(b,float(i)/n)
					_quad(surfaces,_wire_material,Vector3(point.x-d.x,.25+G.GROUND,point.y-d.y),Vector3(point.x+d.x,.25+G.GROUND,point.y+d.y),Vector3(point.x+d.x,1.65+G.GROUND,point.y+d.y),Vector3(point.x-d.x,1.65+G.GROUND,point.y-d.y))
			else:
				for y: float in [.46,1.0,1.53]:
					var d := (b-a).normalized();var normal := Vector2(-d.y,d.x)
					for side in 6:
						var theta := TAU*side/6;var next := TAU*(side+1)/6
						var p := Vector3(normal.x*cos(theta)*.035,y+sin(theta)*.035+G.GROUND,normal.y*cos(theta)*.035)
						var q := Vector3(normal.x*cos(next)*.035,y+sin(next)*.035+G.GROUND,normal.y*cos(next)*.035)
						_quad(surfaces,rail_material,Vector3(a.x,0,a.y)+p,Vector3(b.x,0,b.y)+p,Vector3(b.x,0,b.y)+q,Vector3(a.x,0,a.y)+q)
			for i in ceili(length/post_spacing)+1: posts[a.lerp(b,float(i)/ceili(length/post_spacing))] = true
	for point: Vector2 in posts:
		var post := MeshInstance3D.new()
		post.mesh = _visible_post_mesh()
		post.position = Vector3(point.x,G.GROUND,point.y)
		node.add_child(post)
	_meshes(node,surfaces,"FenceRails")

## The cap and timber meet at 1.59m. Their two touching faces and the buried
## post bottom cannot be visible. Remove only these six source triangles and
## share the original remaining silhouette/materials across every post copy.
func _visible_post_mesh() -> Mesh:
	if _post_mesh != null: return _post_mesh
	var source := _module("fence_post").instantiate()
	var surfaces := {}
	for instance: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var at := instance.transform
		var parent := instance.get_parent()
		while parent != source:
			if parent is Node3D: at = parent.transform*at
			parent = parent.get_parent()
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var a := at*vertices[indices[i]];var b := at*vertices[indices[i+1]];var c := at*vertices[indices[i+2]]
				var horizontal := absf(a.y-b.y)+absf(a.y-c.y)<.00001
				if horizontal and (absf(a.y)<.00001 or absf(a.y-1.59)<.00001): continue
				_triangle(surfaces,instance.get_active_material(surface),a,b,c)
	var temporary := Node3D.new()
	_meshes(temporary,surfaces,"Post")
	_post_mesh = (temporary.get_child(0) as MeshInstance3D).mesh
	temporary.free();source.free()
	return _post_mesh

func _quad(surfaces: Dictionary,material: Material,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	_triangle(surfaces,material,a,b,c);_triangle(surfaces,material,a,c,d)

func _triangle(surfaces: Dictionary,material: Material,a: Vector3,b: Vector3,c: Vector3) -> void:
	if not surfaces.has(material): surfaces[material] = {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array()}
	var normal := (b-a).cross(c-a).normalized()
	var data: Dictionary = surfaces[material]
	for p in [a,b,c]:
		data.vertices.append(p);data.normals.append(normal)
		data.uv.append(Vector2(p.z,p.y)*.5 if absf(normal.x)>.5 else Vector2(p.x,p.z if absf(normal.y)>.5 else p.y)*.5)

func _meshes(node: Node3D,surfaces: Dictionary,label: String) -> void:
	var mesh := ArrayMesh.new()
	for material: Material in surfaces:
		var data: Dictionary = surfaces[material]
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,material)
	if mesh.get_surface_count() == 0: return
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	node.add_child(instance)
