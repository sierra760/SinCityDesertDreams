# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name StreetSignPlacement3D
extends RefCounted

const METRES := 16.0
const STEP := .045
const Tunnels := preload("res://scripts/view/city_road_tunnels_3d.gd")

static func _failed(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"transform":Transform3D.IDENTITY,"support":{},"bounds":AABB()}

static func intersection(city: City, junction: Dictionary, faces: Array[Dictionary]) -> Dictionary:
	if city==null or faces.is_empty(): return _failed("No named faces or city")
	if junction.channel!=&"open": return _failed("Underground junction has no safe open sign support")
	var center:=Vector2(junction.position.x,junction.position.z)
	var rejected: Array[String]=[]
	# Outside the complete road/shoulder and the central .30-tile walking paths.
	for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p:=center+corner*.68
		var cell:=Vector2i(floori(p.x),floori(p.y))
		if not city.in_bounds(cell.x,cell.y): continue
		var ground:=CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell))
		var local:=AABB(Vector3(-1.9,0,-1.9)/METRES,Vector3(3.8,2.85,3.8)/METRES)
		var transform:=Transform3D(Basis.IDENTITY,ground)
		var bounds: AABB=transform*local
		var checked:=_clear(city,bounds,false)
		if not checked.is_empty():
			rejected.append(checked)
			continue
		var feet:=_feet(city,transform,[Vector3.ZERO],.11/METRES)
		if not feet.ok:
			rejected.append("Uneven shoe support")
			continue
		return {"ok":true,"reason":"","transform":transform,"bounds":bounds,"support":{"kind":"ground_corner","height":ground.y,"contacts":feet.contacts,"clearance_checked":true}}
	var fallback:=_existing_support(city,junction,faces)
	if fallback.ok: return fallback
	return _failed("No supported corner: "+", ".join(rejected)+"; "+fallback.reason)

static func exit(city: City, approach: Dictionary, _face: Dictionary) -> Dictionary:
	if city==null: return _failed("No city")
	var direction:=Vector2(approach.direction)
	var right:=Vector2(-direction.y,direction.x)
	var front:=Vector3(-direction.x,0,-direction.y)
	var basis:=Basis(Vector3.UP.cross(front),Vector3.UP,front)
	var cells: Array=approach.upstream_cells.duplicate()
	cells.reverse()
	var graph:=CityTrafficGraph.new()
	graph.bind_city(city)
	for cell: Vector2i in cells:
		# The entire expanded board is outside the roadway, with both shoes on
		# real adjacent ground. Rigid board remains upright on longitudinal grade.
		for distance: float in [.71,.80,.90,1.71,1.80,1.90]:
			var p:=Vector2(cell)+Vector2(.5,.5)+right*distance-direction*.32
			var ground_cell:=Vector2i(floori(p.x),floori(p.y))
			if not city.in_bounds(ground_cell.x,ground_cell.y): continue
			var ground:=CityGeometry3D.point_on_ground(city,ground_cell,p-Vector2(ground_cell))
			var deck:=graph.point(cell,&"highway",Vector2(.5,.5)+right*.46-direction*.32)
			var transform:=Transform3D(basis,Vector3(ground.x,deck.y,ground.z))
			var adapted:=_exit_support(city,transform,_face)
			if not adapted.ok: continue
			var bounds: AABB=adapted.bounds
			if not _clear(city,bounds,true).is_empty(): continue
			var clear:=true
			for component: AABB in adapted.components:
				if not _walking_clear(city,component): clear=false;break
			if not clear: continue
			return {"ok":true,"reason":"","transform":transform,"bounds":bounds,"support":{"kind":"roadside_ground","height":deck.y,"contacts":adapted.contacts,"part_transforms":adapted.transforms,"highway_cell":cell,"deck_height":deck.y,"lateral_offset":distance,"component_bounds":adapted.components,"clearance_checked":true}}

	return _failed("No upstream or mouth support clear of highway lanes, passages and water")

## All post-shoe corners must contact real supported dry ground, within the
## pedestrian step tolerance; the rigid feet never bridge a cliff.
static func _feet(city: City, transform: Transform3D, centers: Array, radius: float) -> Dictionary:
	var contacts: Array[Vector3]=[]
	for center: Vector3 in centers:
		for delta: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var at:=transform*(center+Vector3(delta.x*radius,0,delta.y*radius))
			var cell:=Vector2i(floori(at.x),floori(at.z))
			if not city.in_bounds(cell.x,cell.y) or city.is_water(cell.x,cell.y): return {"ok":false}
			var floor_point:=CityGeometry3D.point_on_ground(city,cell,Vector2(at.x,at.z)-Vector2(cell))
			if absf(floor_point.y-at.y)>.002: return {"ok":false}
			contacts.append(floor_point)
	return {"ok":true,"contacts":contacts}

## Conservative maximum-envelope check, local only. Developed lots include
## their full footprints; mouth exclusion includes approach walking space.
static func _clear(city: City, bounds: AABB, highway: bool, existing_support: bool = false) -> String:
	var rect:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	for y: int in range(floori(rect.position.y)-1,ceili(rect.end.y)+1):
		for x: int in range(floori(rect.position.x)-1,ceili(rect.end.x)+1):
			var cell:=Vector2i(x,y)
			if not city.in_bounds(x,y):
				if rect.intersects(Rect2(Vector2(cell),Vector2.ONE)): return "Map edge"
				continue
			var code:=city.building.atv(cell)
			var tile:=Rect2(Vector2(cell),Vector2.ONE)
			if Buildings.is_developed(code) or code in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
				var anchor:=city.anchor_of(x,y)
				var lot:=Rect2(Vector2(anchor),Vector2(Buildings.size(city.building.atv(anchor))))
				if rect.intersects(lot): return "Building footprint"
				if code in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
					var entry:=StationStreetAccess.surface_entrance(city,anchor)
					var door: Vector3=entry.position
					if rect.intersects(Rect2(Vector2(door.x,door.z)-Vector2(.2,.2),Vector2(.4,.4))): return "Station door"
			if NetworkShapes.is_onramp(code):
				if rect.intersects(tile): return "Ramp footprint"
				# Reserve the real two mouths, not unrelated outside corners.
				var ends:=NetworkShapes.onramp_endpoints(code,bool(city.flags.atv(cell)&RotationMapper.AXIS_FLAG))
				for direction: Vector2i in ends:
					var mouth:=Vector2(cell)+Vector2(.5,.5)+Vector2(direction)*.5
					var size:=Vector2(.24,.75) if direction.x!=0 else Vector2(.75,.24)
					if rect.intersects(Rect2(mouth-size*.5,size)): return "Ramp mouth corridor"
			if NetworkShapes.is_tunnel(code):
				if rect.intersects(tile.grow(.12)): return "Bore mouth"
			if NetworkShapes.is_highway(code):
				# Highway envelope owns its entire lane footprint, including paired
				# cells and bends. Side signs may occupy only the outside ground.
				if rect.intersects(tile.grow(-.02)): return "Highway driving corridor"
			elif NetworkShapes.in_road_family(code) or NetworkShapes.in_rail_family(code):
				if not existing_support and rect.intersects(tile.grow(-.15)): return "Road/rail and walking corridor"
			elif rect.intersects(tile) and not existing_support:
				if city.is_water(x,y): return "Unsupported water"
				# Preserve crossing walking corridors. Highway supports sit next to
				# the elevated deck, outside the central roadside walking line.
				var horizontal:=Rect2(Vector2(x,y+.35),Vector2(1,.30))
				var vertical:=Rect2(Vector2(x+.35,y),Vector2(.30,1))
				if not highway and (rect.intersects(horizontal) or rect.intersects(vertical)): return "Walking corridor"
				for offset: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					var p:=rect.position+rect.size*offset
					if tile.has_point(p) and CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell)).y>bounds.position.y+.015: return "Terrain intersects assembly"
	return ""


static var _exit_parts: Dictionary={}

## Imported closed supports retain their authored top and positive orientation.
## Only their vertical length changes; each shoe lands on its own actual floor.
static func _exit_support(city: City, transform: Transform3D, face: Dictionary) -> Dictionary:
	if _exit_parts.is_empty():
		var scene:=load("res://assets/street-name-signs/highway-exit.glb").instantiate() as Node3D
		for node: Node in scene.find_children("*","MeshInstance3D",true,false):
			_exit_parts[String(node.name)]={"transform":node.transform,"bounds":node.mesh.get_aabb(),"board":node.get_parent().name=="Board"}
		scene.free()
	var changed: Dictionary={}
	var contacts: Array[Vector3]=[]
	var components: Array[AABB]=[]
	var size:=Vector3(face.maximum_board_scale[0],face.maximum_board_scale[1],face.maximum_board_scale[2])
	var pivot:=Vector3(face.board_pivot_m[0],face.board_pivot_m[1],face.board_pivot_m[2])
	var growth:=Transform3D(Basis.from_scale(size),pivot-pivot*size)
	var bounds:=AABB()
	var begun:=false
	for name: String in _exit_parts:
		var part: Dictionary=_exit_parts[name]
		var local: Transform3D=part.transform
		var box: AABB=part.bounds
		if part.board: local=growth*local
		elif name.begins_with("ShoulderPost") or name.begins_with("ShoulderShoe"):
			var foot:=transform*(Vector3(local.origin.x,0,local.origin.z)/METRES)
			var cell:=Vector2i(floori(foot.x),floori(foot.z))
			if not city.in_bounds(cell.x,cell.y) or city.is_water(cell.x,cell.y): return {"ok":false}
			var floor_point:=CityGeometry3D.point_on_ground(city,cell,Vector2(foot.x,foot.z)-Vector2(cell))
			var floor_m: float=(floor_point.y-transform.origin.y)*METRES
			if name.begins_with("ShoulderPost"):
				var top: float=(local*box).end.y
				if floor_m>=top-.1: return {"ok":false}
				local.basis=Basis.from_scale(Vector3(1,(top-floor_m)/box.size.y,1))
				local.origin.y=floor_m-box.position.y*local.basis.y.y
			else:
				local.origin.y=floor_m-box.position.y
				var foot_transform:=transform*Transform3D(Basis.IDENTITY,Vector3(local.origin.x,floor_m,local.origin.z)/METRES)
				var checked:=_feet(city,foot_transform,[Vector3.ZERO],maxf(box.size.x,box.size.z)/METRES*.5)
				if not checked.ok: return {"ok":false}
				contacts.append_array(checked.contacts)
			changed[name]=local
		var world: AABB=transform*Transform3D(Basis.from_scale(Vector3.ONE/METRES),Vector3.ZERO)*local*box
		components.append(world)
		bounds=bounds.merge(world) if begun else world
		begun=true
	# Operational text mount is just beyond enamel; reserve its millimetre depth.
	bounds=bounds.grow(.002/METRES)
	return {"ok":true,"bounds":bounds,"transforms":changed,"contacts":contacts,"components":components}


static func _walking_clear(city: City, bounds: AABB) -> bool:
	var rect:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
		for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
			var floor_y:=CityGeometry3D.ground_height(city,Vector2i(x,y))
			if bounds.position.y>=floor_y+.14: continue # overhead board clears standing actor
			if rect.intersects(Rect2(Vector2(x,y+.35),Vector2(1,.30))) or rect.intersects(Rect2(Vector2(x+.35,y),Vector2(.30,1))): return false
	return true


static var _street_parts: Dictionary={}
static var _street_scale:=1.0

## Imported component envelopes, with the same expansion/stack/yaw used
## by the renderer. Cache detached bounds/transforms, never scene nodes.
static func _street_components(transform: Transform3D, faces: Array[Dictionary]) -> Array[AABB]:
	if _street_parts.is_empty():
		var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/street-name-signs/templates.json")).templates["street-blade"]
		_street_scale=contract.maximum_board_scale[0]
		for id: String in ["street-post","street-blade"]:
			var scene:=load("res://assets/street-name-signs/"+id+".glb").instantiate() as Node3D
			var parts: Array[Dictionary]=[]
			for node: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
				parts.append({"transform":node.transform,"bounds":node.mesh.get_aabb()})
			_street_parts[id]=parts
			scene.free()
	var result: Array[AABB]=[]
	var metres:=Transform3D(Basis.from_scale(Vector3.ONE/METRES),Vector3.ZERO)
	for part: Dictionary in _street_parts["street-post"]: result.append(transform*metres*part.transform*part.bounds)
	for i: int in faces.size():
		var direction: Vector2i=faces[i].direction
		var blade:=Transform3D(Basis(Vector3.UP,atan2(float(direction.y),float(direction.x))),Vector3(0,2.45-i*.65,0))
		var expansion:=Transform3D(Basis.from_scale(Vector3(_street_scale,1,1)),Vector3.ZERO)
		for part: Dictionary in _street_parts["street-blade"]: result.append((transform*metres*blade*expansion*part.transform*part.bounds).grow(.002/METRES))
	return result

static func _rect_xz(bounds: AABB) -> Rect2:
	return Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))

static func _patch_hit(patches: Array, p: Vector2) -> Dictionary:
	var best: Dictionary={}
	for patch: Dictionary in patches:
		var t: PackedVector3Array=patch.triangle
		var hit: Variant=Geometry3D.ray_intersects_triangle(Vector3(p.x,100,p.y),Vector3.DOWN,t[0],t[1],t[2])
		if hit is Vector3 and (best.is_empty() or patch.role>best.role or (patch.role==best.role and hit.y>best.point.y)):
			best={"role":patch.role,"point":hit}
	return best

static func _existing_support(city: City, junction: Dictionary, faces: Array[Dictionary]) -> Dictionary:
	var data: Dictionary=junction.get("rendered_support",{})
	if data.is_empty() and junction.has("rendered_support_source"): data=(junction.rendered_support_source as Callable).call()
	if data.is_empty(): return _failed("No current rendered verge/bridge-side support")
	var cell:=Vector2i(floori(junction.position.x),floori(junction.position.z))
	var candidates: Array[Dictionary]=[]
	for uv: Vector2 in [Vector2(.02,.02),Vector2(.98,.02),Vector2(.98,.98),Vector2(.02,.98)]:
		var hit:=_patch_hit(data.patches,Vector2(cell)+uv)
		if not hit.is_empty() and hit.role==CityNetworks3D.PhysicalRole.VERGE:
			candidates.append({"point":hit.point,"kind":"rendered_verge"})
	# Renderer boxes (bridge beams and guards), bounded to two
	# tiles from the junction. Prefer the highest support, then stable X/Z.
	var bridge: Array[Dictionary]=[]
	for box: Dictionary in data.boxes:
		var bounds: AABB=box.transform*AABB(-Vector3(box.size)*.5,box.size)
		var p:=Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
		var support_cell:=Vector2i(floori(p.x),floori(p.z))
		if not city.in_bounds(support_cell.x,support_cell.y) or not NetworkShapes.is_road_bridge(city.building.atv(support_cell)): continue
		if Vector2(p.x-junction.position.x,p.z-junction.position.z).length()>2: continue
		# Only flat, real top faces; never the top of a slanted beam's AABB.
		var up: Vector3=box.transform.basis.inverse()*Vector3.UP
		if maxf(absf(up.x),maxf(absf(up.y),absf(up.z)))<.99999: continue
		if minf(bounds.size.x,bounds.size.z)<.22/METRES or maxf(bounds.size.x,bounds.size.z)<.2: continue
		bridge.append({"point":p,"kind":"rendered_bridge_side","source_box":box})
	bridge.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.point.y!=b.point.y: return a.point.y>b.point.y
		if a.point.z!=b.point.z: return a.point.z<b.point.z
		return a.point.x<b.point.x)
	candidates.append_array(bridge)
	var rejected: Array[String]=[]
	for candidate: Dictionary in candidates:
		var p: Vector3=candidate.point
		var contacts: Array[Vector3]=[]
		for delta: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var at:=p+Vector3(delta.x,0,delta.y)*(.11/METRES)
			if candidate.has("source_box"):
				var box: Dictionary=candidate.source_box
				var b: AABB=box.transform*AABB(-Vector3(box.size)*.5,box.size)
				if _rect_xz(b).has_point(Vector2(at.x,at.z)): contacts.append(at)
			else:
				var hit:=_patch_hit(data.patches,Vector2(at.x,at.z))
				if not hit.is_empty() and hit.role==CityNetworks3D.PhysicalRole.VERGE and absf(hit.point.y-at.y)<=.002: contacts.append(hit.point)
		if contacts.size()!=4:
			rejected.append("Uneven or incomplete existing shoe support");continue
		var transform:=Transform3D(Basis.IDENTITY,p)
		var components:=_street_components(transform,faces)
		var bounds:=components[0]
		for component: AABB in components: bounds=bounds.merge(component)
		var reason:=_clear(city,bounds,false,true)
		if reason.is_empty(): reason=_supported_clearance(city,components,data)
		if not reason.is_empty(): rejected.append(reason);continue
		var support:=candidate.duplicate(true)
		support["contacts"]=contacts;support["component_bounds"]=components
		support["geometry_revision"]=data.geometry_revision;support["clearance_checked"]=true
		return {"ok":true,"reason":"","transform":transform,"bounds":bounds,"support":support}
	return _failed("No safe existing verge/bridge-side support: "+", ".join(rejected))

static func _supported_clearance(city: City, components: Array[AABB], data: Dictionary) -> String:
	for component: AABB in components:
		var rect:=_rect_xz(component)
		for patch: Dictionary in data.patches:
			if patch.role<CityNetworks3D.PhysicalRole.SHOULDER: continue
			var t: PackedVector3Array=patch.triangle
			var bounds:=AABB(t[0],Vector3.ZERO).expand(t[1]).expand(t[2])
			# Vehicle lanes keep their entire column clear. Shoulder pedestrians
			# keep their standing height and capsule radius; a mount above a
			# guard must clear that complete volume.
			if patch.role==CityNetworks3D.PhysicalRole.SHOULDER and component.position.y>=bounds.end.y+.14: continue
			var passage:=rect.grow(.018)
			if not passage.intersects(_rect_xz(bounds)): continue
			var footprint:=PackedVector2Array([passage.position,Vector2(passage.end.x,passage.position.y),passage.end,Vector2(passage.position.x,passage.end.y)])
			var triangle:=PackedVector2Array([Vector2(t[0].x,t[0].z),Vector2(t[1].x,t[1].z),Vector2(t[2].x,t[2].z)])
			if not Geometry2D.intersect_polygons(footprint,triangle).is_empty(): return "Existing lane/shoulder walking clearance"
		for box: Dictionary in data.boxes:
			var b: AABB=box.transform*AABB(-Vector3(box.size)*.5,box.size)
			if component.grow(-.000001).intersects(b): return "Existing structure intersects assembly"
		for i: int in range(0,data.obstacles.size(),3):
			var t: PackedVector3Array=data.obstacles.slice(i,i+3)
			var bounds:=AABB(t[0],Vector3.ZERO).expand(t[1]).expand(t[2]).grow(.000001)
			if component.grow(-.000001).intersects(bounds): return "Existing wall/mouth intersects assembly"
		for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
			for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
				var cell:=Vector2i(x,y)
				if not city.in_bounds(x,y): return "Map edge"
				for uv: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,Vector2(.5,.5)]:
					var clipped:=rect.intersection(Rect2(Vector2(cell),Vector2.ONE))
					var p:=clipped.position+clipped.size*uv
					if not city.is_water(x,y) and CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell)).y>component.position.y+.002: return "Terrain intersects assembly"
				if NetworkShapes.in_road_family(city.building.atv(cell)): continue # checked actual corridor above
				var ground:=CityGeometry3D.ground_height(city,cell)
				if component.position.y>=ground+.14: continue
				if rect.intersects(Rect2(Vector2(x,y+.35),Vector2(1,.30))) or rect.intersects(Rect2(Vector2(x+.35,y),Vector2(.30,1))): return "Walking corridor"
	return ""
