# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name AgriculturalParcelGeometry
extends RefCounted
## Detached metre-space layouts. Every logical edge participates in navigation,
## independently of which neighbor owns its rendered/physical fence.
const MODULE_PATH := "res://assets/agriculture/parcel_modules.json"
const ENCLOSURE_PATH := "res://assets/agriculture/enclosures.json"
const ENCLOSURE_SHA256 := "4ab15a4f03ce8855bc78c10607b643c5c012d48965e473fc45fec1375c037fb0"
const TILE := 16.0
const GROUND := .14
const GRID := 2.0
const STRUCTURES := [&"farm_shed",&"shade_shelter",&"water_trough",&"water_tank",&"grain_bin",&"hay_bale"]
static var _manifest: Dictionary = {}
static var _authored: Dictionary = {}
## Shared, bounded immutable layout proofs. Callers always receive deep copies;
## counters, identity and service availability cannot change a metre-space plan.
const LAYOUT_CACHE_LIMIT := 32
static var _layouts: Array[Dictionary] = []
static var _compilations := 0

static func layout_inputs(record: Dictionary, modules: Array = []) -> Array:
	var units := 0
	for value: int in record.stock_units.values(): units += value
	return [record.members,record.origin_index,record.mode,record.archetype,
		record.modules if modules.is_empty() else modules,units]

static func presentation_inputs(record: Dictionary) -> Array:
	return [layout_inputs(record),record.state,record.legacy_code,record.stock_units,record.layout_seed]


static func _modules() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODULE_PATH))
		if data is Dictionary: _manifest=data
	return _manifest

static func _enclosures() -> Dictionary:
	if _authored.is_empty() and FileAccess.get_sha256(ENCLOSURE_PATH)==ENCLOSURE_SHA256:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENCLOSURE_PATH))
		if data is Dictionary: _authored=data
	return _authored

static func fence_owner(id: int, neighbor_id: int) -> int:
	return id if neighbor_id<=0 else mini(id,neighbor_id)

## Clockwise in tile X/Z (interior on the right). At a diagonal vertex touch,
## the rightmost outgoing edge closes the current loop instead of crossing it.
static func boundary(members: PackedInt32Array) -> Array[Dictionary]:
	var occupied := {}
	for i in members: occupied[Vector2i(i%128,i/128)]=true
	var cells := occupied.keys()
	cells.sort_custom(_row_before)
	var pending: Array[Dictionary] = []
	for p: Vector2i in cells:
		if not occupied.has(p+Vector2i.UP): pending.append({"a":p,"b":p+Vector2i.RIGHT})
		if not occupied.has(p+Vector2i.RIGHT): pending.append({"a":p+Vector2i.RIGHT,"b":p+Vector2i.ONE})
		if not occupied.has(p+Vector2i.DOWN): pending.append({"a":p+Vector2i.ONE,"b":p+Vector2i.DOWN})
		if not occupied.has(p+Vector2i.LEFT): pending.append({"a":p+Vector2i.DOWN,"b":p})
	pending.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return _row_before(a.a,b.a) if a.a!=b.a else _row_before(a.b,b.b))
	var result: Array[Dictionary] = []
	while not pending.is_empty():
		var edge: Dictionary = pending.pop_front()
		var start: Vector2i = edge.a
		while true:
			result.append(edge)
			if edge.b==start: break
			var best := -1
			var score := -1
			var direction: Vector2i = edge.b-edge.a
			for i in pending.size():
				if pending[i].a!=edge.b: continue
				var next: Vector2i = pending[i].b-pending[i].a
				var cross := direction.x*next.y-direction.y*next.x
				var rank := 3 if cross>0 else (2 if direction==next else 1)
				if rank>score: best=i;score=rank
			if best<0: return []
			edge=pending[best]
			pending.remove_at(best)
	return result

static func _row_before(a: Vector2i,b: Vector2i) -> bool:
	return a.y<b.y or (a.y==b.y and a.x<b.x)

static func _mask(record: Dictionary) -> Dictionary:
	var origin := Vector2i(record.origin_index%128,record.origin_index/128)
	var cells := {}
	for i in record.members: cells[Vector2i(i%128,i/128)-origin]=true
	return cells

static func _pen(record: Dictionary,edges: Array,obstacles: Array) -> Dictionary:
	var origin := Vector2(record.origin_index%128,record.origin_index/128)
	var local: Array = []
	for e in edges: local.append({"a":(Vector2(e.a)-origin)*TILE,"b":(Vector2(e.b)-origin)*TILE})
	var cells := _mask(record)
	var lo := Vector2(INF,INF)
	var hi := Vector2(-INF,-INF)
	for p: Vector2i in cells:
		lo=lo.min(Vector2(p)*TILE)
		hi=hi.max(Vector2(p+Vector2i.ONE)*TILE)
	return {"kind":"parcel","name":"pasture","mask":cells,"boundary":local,
		"bounds":[lo.x,lo.y,hi.x,hi.y],"navigation_bounds":[lo.x,lo.y,hi.x,hi.y],
		"obstacles":obstacles,"ground_y":GROUND,"grid_step":GRID}

static func _inside(p: Vector2,pen: Dictionary) -> bool:
	return pen.mask.has(Vector2i(floori(p.x/TILE),floori(p.y/TILE)))

static func navigation_clear(point: Vector2,pen: Dictionary,radius: float) -> bool:
	if not point.is_finite() or not is_finite(radius) or radius<0 or not _inside(point,pen): return false
	var clearance := radius+.08
	for e: Dictionary in pen.boundary:
		if point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,e.a,e.b))<clearance*clearance-.000001: return false
	for obstacle: Dictionary in pen.obstacles:
		var b: Array = obstacle.bounds
		if point.x>=b[0]-radius and point.x<=b[2]+radius and point.y>=b[1]-radius and point.y<=b[3]+radius: return false
	return true

static func _box_intersects(a: Vector2,b: Vector2,box: Array,margin: float) -> bool:
	var low := Vector2(box[0]-margin,box[1]-margin)
	var high := Vector2(box[2]+margin,box[3]+margin)
	var delta := b-a
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if absf(delta[axis])<.0000001:
			if a[axis]<low[axis] or a[axis]>high[axis]: return false
		else:
			var t0 := (low[axis]-a[axis])/delta[axis]
			var t1 := (high[axis]-a[axis])/delta[axis]
			enter=maxf(enter,minf(t0,t1))
			leave=minf(leave,maxf(t0,t1))
	return enter<=leave

static func _segment_distance_squared(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return 0.0
	return minf(minf(a.distance_squared_to(Geometry2D.get_closest_point_to_segment(a,c,d)),
		b.distance_squared_to(Geometry2D.get_closest_point_to_segment(b,c,d))),
		minf(c.distance_squared_to(Geometry2D.get_closest_point_to_segment(c,a,b)),
		d.distance_squared_to(Geometry2D.get_closest_point_to_segment(d,a,b))))

static func navigation_segment(a: Vector2,b: Vector2,pen: Dictionary,radius: float) -> bool:
	if not navigation_clear(a,pen,radius) or not navigation_clear(b,pen,radius): return false
	for e: Dictionary in pen.boundary:
		if _segment_distance_squared(a,b,e.a,e.b)<(radius+.08)*(radius+.08)-.000001: return false
	for obstacle: Dictionary in pen.obstacles:
		if _box_intersects(a,b,obstacle.bounds,radius): return false
	return true

static func _rotate(p: Vector2,yaw: int) -> Vector2:
	match yaw:
		1: return Vector2(p.y,-p.x)
		2: return -p
		3: return Vector2(-p.y,p.x)
	return p

static func _box(module: Dictionary,field: String) -> Dictionary:
	var spec: Dictionary = _modules().modules[String(module.key)]
	var b: Array = spec[field]
	var lo := Vector2(INF,INF)
	var hi := Vector2(-INF,-INF)
	var p := Vector2(module.at.x,module.at.z)
	for point in [Vector2(b[0],b[2]),Vector2(b[3],b[2]),Vector2(b[3],b[5]),Vector2(b[0],b[5])]:
		var rotated := _rotate(point,module.yaw)+p
		lo=lo.min(rotated);hi=hi.max(rotated)
	return {"kind":String(module.key),"bounds":[lo.x,lo.y,hi.x,hi.y],
		"center":[(lo.x+hi.x)*.5,module.at.y+(b[1]+b[4])*.5,(lo.y+hi.y)*.5],
		"size":[hi.x-lo.x,b[4]-b[1],hi.y-lo.y]}

static func _valid_pose(module: Variant) -> bool:
	if not module is Dictionary or module.size()!=3: return false
	if typeof(module.get("key")) not in [TYPE_STRING,TYPE_STRING_NAME] or module.key not in STRUCTURES: return false
	if typeof(module.get("at"))!=TYPE_VECTOR3 or not module.at.is_finite(): return false
	if typeof(module.get("yaw"))!=TYPE_INT or module.yaw<0 or module.yaw>3: return false
	var p: Vector3 = module.at
	if maxf(absf(p.x),absf(p.z))>2048 or absf(p.y-GROUND)>.000001: return false
	return absf(p.x*2-roundf(p.x*2))<.000001 and absf(p.z*2-roundf(p.z*2))<.000001

static func _fits(module: Dictionary,cells: Dictionary,placed: Array) -> bool:
	var b: Array = _box(module,"placement_bounds").bounds
	# A rectangle lies in the union iff every tile its inflated area overlaps
	# is a member. This also catches holes entirely enclosed by the rectangle.
	for z in range(floori((b[1]-.2)/TILE),floori((b[3]+.2-.000001)/TILE)+1):
		for x in range(floori((b[0]-.2)/TILE),floori((b[2]+.2-.000001)/TILE)+1):
			if not cells.has(Vector2i(x,z)): return false
	for other: Dictionary in placed:
		var c: Array = _box(other,"placement_bounds").bounds
		if b[0]<c[2]+.2 and b[2]>c[0]-.2 and b[1]<c[3]+.2 and b[3]>c[1]-.2: return false
	return true

static func _required(record: Dictionary) -> Array:
	return [&"shade_shelter",&"water_trough"] if record.archetype in [&"cattle_range",&"sheep_pasture"] else [&"farm_shed"]

static func _placement(record: Dictionary,previous: Array,fill: bool) -> Dictionary:
	var cells := _mask(record)
	var placed: Array = []
	var keys := {}
	for module: Variant in previous:
		var valid := _valid_pose(module)
		if valid: valid=not keys.has(String(module.key)) and _fits(module,cells,placed)
		if not valid:
			if not fill: return {"ok":false,"modules":placed}
			continue
		placed.append(module.duplicate(true));keys[String(module.key)]=true
	for key: StringName in _required(record):
		if keys.has(String(key)): continue
		if not fill: return {"ok":false,"modules":placed}
		var found := false
		# Globally row-major half-metre lattice, then four canonical yaws.
		var box: Array = _pen(record,[],[]).bounds
		for z in range(ceili(box[1]*2),floori(box[3]*2)+1):
			if found: break
			for x in range(ceili(box[0]*2),floori(box[2]*2)+1):
				if found: break
				if not cells.has(Vector2i(floori(x*.5/TILE),floori(z*.5/TILE))): continue
				for yaw in 4:
					var candidate := {"key":key,"at":Vector3(x*.5,GROUND,z*.5),"yaw":yaw}
					if _fits(candidate,cells,placed):
						placed.append(candidate);keys[String(key)]=true;found=true
						break
		if not found: return {"ok":false,"modules":placed}
	return {"ok":true,"modules":placed}

## Validation never repairs an active record silently. Prepared/dormant records
## can lack a core, but every surviving module must still fit the current mask.
static func record_error(record: Dictionary) -> String:
	if record.mode!=&"generated":
		return "Authored templates cannot contain generated modules." if not record.modules.is_empty() else ""
	if record.state!=&"active":
		var placed: Array = []
		var keys := {}
		for module: Variant in record.modules:
			if not _valid_pose(module): return "Invalid module pose or key."
			if keys.has(String(module.key)) or not _fits(module,_mask(record),placed): return "Module does not fit."
			keys[String(module.key)]=true;placed.append(module)
		return ""
	var fixed := _placement(record,record.modules,false)
	if not fixed.ok: return "Active parcel lacks valid required modules."
	var layout := plan(record,record.modules)
	return "" if layout.ok else layout.error

## Fit surviving poses first, relocating cut-through structures as whole units.
## Active retention requires every original required pose to survive unchanged.
static func repair_layout(record: Dictionary, previous: Array) -> Dictionary:
	var result := plan(record,previous)
	var core_intact := true
	for key: StringName in _required(record):
		var found := false
		for module: Dictionary in previous:
			if module.key == key and module in result.modules: found = true;break
		if not found: core_intact = false
	result["core_intact"] = core_intact
	return result


static func max_safe_stock(record: Dictionary,layout: Dictionary) -> int:
	var units := 0
	for value: int in record.stock_units.values(): units+=value
	var profile: Dictionary = layout.get("profile",{})
	return mini(mini(units/9,12),int(profile.get("animal_count",0)))

## Mark only lattice points within a boundary capsule/obstacle envelope.
## This is the same exact predicate as navigation_clear, without testing every
## distant edge against every node. The 2m lattice and all graph caps stay fixed.
static func _graph(pen: Dictionary,radius: float) -> Dictionary:
	var blocked := {}
	var clearance := radius+.08
	for edge: Dictionary in pen.boundary:
		var a: Vector2 = edge.a;var b: Vector2 = edge.b
		var low := a.min(b)-Vector2.ONE*clearance
		var high := a.max(b)+Vector2.ONE*clearance
		for z in range(ceili(low.y/GRID),floori(high.y/GRID)+1):
			for x in range(ceili(low.x/GRID),floori(high.x/GRID)+1):
				var cell := Vector2i(x,z);var point := Vector2(cell)*GRID
				if point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,a,b))<clearance*clearance-.000001: blocked[cell]=true
	for obstacle: Dictionary in pen.obstacles:
		var b: Array = obstacle.bounds
		for z in range(ceili((b[1]-radius)/GRID),floori((b[3]+radius)/GRID)+1):
			for x in range(ceili((b[0]-radius)/GRID),floori((b[2]+radius)/GRID)+1): blocked[Vector2i(x,z)]=true
	var nodes: Array = []
	var lookup := {}
	var bounds: Array = pen.bounds
	for z in range(ceili(bounds[1]/GRID),floori(bounds[3]/GRID)+1):
		for x in range(ceili(bounds[0]/GRID),floori(bounds[2]/GRID)+1):
			var cell := Vector2i(x,z);var point := Vector2(cell)*GRID
			if not blocked.has(cell) and _inside(point,pen):
				if nodes.size()>=4096: return {}
				lookup[cell]=nodes.size();nodes.append(point)
	var adjacency: Array = []
	for i in nodes.size(): adjacency.append([])
	var edges: Array = []
	for cell: Vector2i in lookup:
		for offset in [Vector2i.RIGHT,Vector2i.DOWN]:
			if not lookup.has(cell+offset): continue
			var a: int = lookup[cell];var b: int = lookup[cell+offset]
			# Boundaries lie on the 16m tile lattice. A 2m axial graph edge
			# cannot cross or approach one more closely than both endpoints.
			# Module boxes need the full sweep: they can lie between nodes.
			var clear := true
			for obstacle: Dictionary in pen.obstacles:
				if _box_intersects(nodes[a],nodes[b],obstacle.bounds,radius): clear=false;break
			if clear:
				if edges.size()>=8192: return {}
				edges.append([a,b]);adjacency[a].append(b);adjacency[b].append(a)
	return {"nodes":nodes,"edges":edges,"adjacency":adjacency}

static func _profile(record: Dictionary,pen: Dictionary) -> Dictionary:
	var source := _enclosures()
	if source.is_empty() or record.members.size()<4: return {}
	var original: Dictionary = source.profiles[String(record.archetype)]
	var species: Dictionary = source.species[original.species]
	var limit := 0
	for units: int in record.stock_units.values(): limit+=units
	limit=mini(limit/9,12)
	if limit<1: return {}
	var radius: float = species.body_radius+species.turn_margin
	var graph := _graph(pen,radius)
	if graph.is_empty(): return {}
	var visited := {}
	var best: Array = []
	var best_spawns: Array = []
	for start in graph.nodes.size():
		if visited.has(start): continue
		var component: Array = [start]
		visited[start]=true
		var cursor := 0
		while cursor<component.size():
			for next: int in graph.adjacency[component[cursor]]:
				if not visited.has(next): visited[next]=true;component.append(next)
			cursor+=1
		component.sort()
		var spawns: Array = []
		for index: int in component:
			var point: Vector2 = graph.nodes[index]
			var separated := true
			for spawn: Vector2 in spawns:
				if point.distance_to(spawn)<2*float(species.body_radius)+.04: separated=false;break
			if separated: spawns.append(point)
			if spawns.size()>=limit: break
		if spawns.size()>best_spawns.size() or (spawns.size()==best_spawns.size() and component.size()>best.size()):
			best=component;best_spawns=spawns
	if best_spawns.is_empty(): return {}
	var selected := {}
	pen.navigation_nodes=[]
	pen.navigation_edges=[]
	for i: int in best:
		selected[i]=pen.navigation_nodes.size()
		var p: Vector2 = graph.nodes[i]
		pen.navigation_nodes.append([p.x,p.y])
	for edge: Array in graph.edges:
		if selected.has(edge[0]) and selected.has(edge[1]): pen.navigation_edges.append([selected[edge[0]],selected[edge[1]]])
	pen.spawns=[]
	for p: Vector2 in best_spawns: pen.spawns.append([p.x,p.y])
	pen.count=best_spawns.size()
	pen.feed_targets=[pen.navigation_nodes.back()]
	# Closest safe graph point to trough, hence outside its inflated obstacle.
	var target: Array = pen.navigation_nodes[0]
	var distance := INF
	for obstacle: Dictionary in pen.obstacles:
		if obstacle.kind!="water_trough": continue
		var centre := Vector2(obstacle.center[0],obstacle.center[2])
		for p: Array in pen.navigation_nodes:
			var d := Vector2(p[0],p[1]).distance_squared_to(centre)
			if d<distance: distance=d;target=p
	pen.drink_targets=[target]
	return {"species":original.species,"body_radius":species.body_radius,"turn_margin":species.turn_margin,
		"scale":species.scale,"ground_y":GROUND,"units":"metres","animal_profile":species.duplicate(true),
		"animal_count":pen.count,"pens":[pen]}

static func plan(record: Dictionary,previous_modules: Array = []) -> Dictionary:
	var inputs := layout_inputs(record,previous_modules)
	for i in range(_layouts.size()-1,-1,-1):
		var cached := _layouts[i]
		if cached.inputs == inputs or cached.fitted_inputs == inputs:
			_layouts.remove_at(i);_layouts.append(cached)
			return cached.layout.duplicate(true)
	_compilations += 1
	var result := _compile(record,previous_modules)
	var fitted := inputs.duplicate(true)
	# A successful placement is also the exact validation/presentation input.
	if result.ok: fitted[4] = result.modules.duplicate(true)
	_layouts.append({"inputs":inputs.duplicate(true),"fitted_inputs":fitted,"layout":result.duplicate(true)})
	if _layouts.size()>LAYOUT_CACHE_LIMIT: _layouts.pop_front()
	return result

static func _compile(record: Dictionary,previous_modules: Array = []) -> Dictionary:
	var edges := boundary(record.members)
	var result := {"ok":false,"modules":[],"edges":edges,"obstacles":[],"profile":{},"error":""}
	if record.mode!=&"generated":
		var side: int = AgricultureParams.ROSTER[StringName(record.archetype)][0]
		var cells := _mask(record)
		var box: Array = _pen(record,[],[]).bounds
		if cells.size()!=side*side or box[2]-box[0]!=side*TILE or box[3]-box[1]!=side*TILE:
			result.error="Authored template requires its intact square footprint."
			return result
		var source := _enclosures()
		if source.is_empty(): result.error="Pinned authored enclosure is unavailable.";return result
		if source.profiles.has(String(record.archetype)):
			result.profile=source.profiles[String(record.archetype)].duplicate(true)
			result.profile.animal_profile=source.species[result.profile.species].duplicate(true)
		result.ok=true
		return result
	var previous: Array = record.modules if previous_modules.is_empty() else previous_modules
	var placement := _placement(record,previous,true)
	result.modules=placement.modules
	if not placement.ok: result.error="Required structure does not fit.";return result
	for module: Dictionary in result.modules: result.obstacles.append(_box(module,"collision_bounds"))
	var pen := _pen(record,edges,result.obstacles)
	# One closed 3m gate splits a single logical edge; all other edges remain.
	pen.fences=[]
	for i in pen.boundary.size():
		var e: Dictionary = pen.boundary[i]
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var segments: Array = [[a,b,false]]
		if i==0:
			var mid := (a+b)*.5
			var half := (b-a).normalized()*1.5
			segments=[[a,mid-half,false],[mid-half,mid+half,true],[mid+half,b,false]]
		for segment: Array in segments:
			pen.fences.append({"a":[segment[0].x,segment[0].y],"b":[segment[1].x,segment[1].y],
				"gate":segment[2],"height":1.65,"thickness":.16,"style":"woven_wire" if record.archetype == &"sheep_pasture" else "pipe_rail"})
	if record.archetype in [&"cattle_range",&"sheep_pasture"]:
		result.profile=_profile(record,pen)
		if result.profile.is_empty(): result.error="No connected safe stocked pasture.";return result
	result.ok=true
	return result
