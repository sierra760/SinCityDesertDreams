# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name StreetSignPlacement3D
extends RefCounted

const METRES := 16.0

static func _failed(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"transform":Transform3D.IDENTITY,"support":{},"bounds":AABB()}

## On-tile blade corner. The post stands in the junction tile's own sand
## verge, inset from a tile corner and clear of the sidewalk walking line
## (0.10 tile from the edge). Each blade lies along its street, wholly inside
## that corner square: never over a lane and never over a neighbouring tile,
## so lots built around the junction cannot hide or clip the sign.
const POST_INSET := .145
const BLADE_OUTER := .008
const LANE_EDGE := (1.0 - CityNetworks3D.ROAD_WIDTH) * .5
const BLADE_BASE_M := 2.4
## About 42 degrees across the 0.22 m shoe; the shoe may bed into the uphill side.
const MAX_SHOE_SPREAD := .0125

static func blade_length_m() -> float:
	return (LANE_EDGE - BLADE_OUTER) * METRES

## Blade centres sit between the tile edge and the lane edge, toward the corner.
static func _corner_blades(faces: Array[Dictionary], inward: Vector2) -> Array[Dictionary]:
	var shift := (BLADE_OUTER + LANE_EDGE) * .5 - POST_INSET
	var blades: Array[Dictionary] = []
	for face: Dictionary in faces:
		var direction: Vector2i = face.direction
		var offset := Vector2(inward.x * shift, 0) if direction.x != 0 else Vector2(0, inward.y * shift)
		blades.append({"shift": offset, "scale_x": blade_length_m() / BLADE_BASE_M})
	return blades

static func intersection(city: City, junction: Dictionary, faces: Array[Dictionary], graph: CityTrafficGraph = null) -> Dictionary:
	if city==null or faces.is_empty(): return _failed("No named faces or city")
	if junction.channel!=&"open": return _failed("Underground junction has no safe open sign support")
	var cell:=Vector2i(floori(junction.position.x),floori(junction.position.z))
	var rejected: Array[String]=[]
	var verge := graph!=null and city.in_bounds(cell.x,cell.y) and graph.has_cell(cell,&"road") and not graph._decks.has(cell) \
		and NetworkShapes.in_road_family(city.building.atv(cell)) and not city.is_water(cell.x,cell.y)
	if verge:
		var diagonal := CityNetworks3D.road_diagonal_mask(city,cell,CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.ROAD))
		for corner: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
			# The filled diagonal owns this former sand corner, including its
			# sign blades and post: choose another corner of the same junction.
			if diagonal != 0 and corner == CityNetworks3D.PIVOTS[diagonal]: continue
			var inward:=Vector2.ONE-corner*2
			var uv:=corner+inward*POST_INSET
			var center:=graph.walk_point(cell,uv)
			var contacts: Array[Vector3]=[]
			var lowest:=INF
			var highest:=-INF
			for delta: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p:=graph.walk_point(cell,uv+delta*(.11/METRES))
				lowest=minf(lowest,p.y);highest=maxf(highest,p.y)
				contacts.append(p)
			# Graded junctions (hills, bridge approaches) keep their sign: the
			# upright post seats its shoe on the lowest corner, so it never floats.
			if not is_finite(lowest) or highest-lowest>MAX_SHOE_SPREAD:
				rejected.append("Verge too steep")
				continue
			center.y=lowest
			var transform:=Transform3D(Basis.IDENTITY,center)
			var blades:=_corner_blades(faces,inward)
			var components:=_street_components(transform,faces,blades)
			var square:=Rect2(Vector2(cell)+corner*(1.0-LANE_EDGE),Vector2(LANE_EDGE,LANE_EDGE)).grow(.0005)
			var bounds:=components[0]
			var inside:=true
			for component: AABB in components:
				bounds=bounds.merge(component)
				if not square.encloses(_rect_xz(component)): inside=false
			if not inside:
				rejected.append("Blade beyond verge corner")
				continue
			return {"ok":true,"reason":"","transform":transform,"bounds":bounds,"support":{"kind":"junction_verge","height":center.y,"contacts":contacts,
				"corner":corner,"blades":blades,"component_bounds":components,"clearance_checked":true}}
	var fallback:=_existing_support(city,junction,faces)
	if fallback.ok: return fallback
	return _failed("No supported verge corner: "+", ".join(rejected)+"; "+fallback.reason)

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


static var _street_parts: Dictionary={}
static var _street_scale:=1.0

## Stacked blades: the top blade is centred at 2.45 m and each further blade
## hangs 0.65 m lower; blades are 0.60 m tall at their fixed height scale.
const BLADE_TOP_CENTRE_M := 2.45
const BLADE_PITCH_M := .65
const BLADE_HALF_HEIGHT_M := .30
const CAP_GAP_M := .012
const COLLAR_GAP_M := .02

## Authored post parts fitted to a stack of `count` blades. The cap sits just
## above the top blade and the post rises into it; the collar, wider than a
## blade's face plane, clamps the post just below the lowest blade, so no part
## pokes through a blade face or its lettering.
static func fitted_post_part(name: String, local: Transform3D, box: AABB, count: int) -> Transform3D:
	var top:=BLADE_TOP_CENTRE_M+BLADE_HALF_HEIGHT_M
	var bottom:=BLADE_TOP_CENTRE_M-(maxi(count,1)-1)*BLADE_PITCH_M-BLADE_HALF_HEIGHT_M
	match name:
		"IvoryCap":
			local.origin.y=top+CAP_GAP_M-box.position.y
		"BrassCollar":
			local.origin.y=bottom-COLLAR_GAP_M-box.end.y
		"Post":
			var floor_m: float=(local*box).position.y
			var height: float=top+CAP_GAP_M+.004-floor_m
			local.basis=Basis.from_scale(Vector3(1,height/box.size.y,1))
			local.origin.y=floor_m-box.position.y*local.basis.y.y
	return local

## Imported component envelopes, with the same expansion/stack/yaw used
## by the renderer. Cache detached bounds/transforms, never scene nodes.
static func _street_components(transform: Transform3D, faces: Array[Dictionary], blades: Array[Dictionary] = []) -> Array[AABB]:
	if _street_parts.is_empty():
		var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/street-name-signs/templates.json")).templates["street-blade"]
		_street_scale=contract.maximum_board_scale[0]
		for id: String in ["street-post","street-blade"]:
			var scene:=load("res://assets/street-name-signs/"+id+".glb").instantiate() as Node3D
			var parts: Array[Dictionary]=[]
			for node: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
				parts.append({"name":String(node.name),"transform":node.transform,"bounds":node.mesh.get_aabb()})
			_street_parts[id]=parts
			scene.free()
	var result: Array[AABB]=[]
	var metres:=Transform3D(Basis.from_scale(Vector3.ONE/METRES),Vector3.ZERO)
	for part: Dictionary in _street_parts["street-post"]:
		result.append(transform*metres*fitted_post_part(part.name,part.transform,part.bounds,faces.size())*part.bounds)
	for i: int in faces.size():
		var direction: Vector2i=faces[i].direction
		var shift: Vector2=blades[i].shift if i<blades.size() else Vector2.ZERO
		var scale_x: float=blades[i].scale_x if i<blades.size() else _street_scale
		var blade:=Transform3D(Basis(Vector3.UP,atan2(float(direction.y),float(direction.x))),Vector3(shift.x*METRES,BLADE_TOP_CENTRE_M-i*BLADE_PITCH_M,shift.y*METRES))
		var expansion:=Transform3D(Basis.from_scale(Vector3(scale_x,1,1)),Vector3.ZERO)
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
	# Renderer boxes (bridge beams and guards) on the junction's own tile, for
	# a junction without a ground verge. Prefer the highest support, then X/Z.
	var bridge: Array[Dictionary]=[]
	for box: Dictionary in data.boxes:
		var bounds: AABB=box.transform*AABB(-Vector3(box.size)*.5,box.size)
		var p:=Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
		var support_cell:=Vector2i(floori(p.x),floori(p.z))
		if support_cell!=cell or not NetworkShapes.is_road_bridge(city.building.atv(support_cell)): continue
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
