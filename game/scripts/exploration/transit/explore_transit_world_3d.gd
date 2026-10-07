# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Reversible Explore-only platforms, enclosed lift shafts and connected tunnel space.
class_name ExploreTransitWorld3D
extends Node3D

const PassageClip := preload("res://scripts/exploration/transit/portal_passage_clip_3d.gd")
const ShellFinish := preload("res://scripts/exploration/transit/station_shell_finish_3d.gd")
const Elevator := preload("res://scripts/exploration/transit/station_elevator_3d.gd")

var view: CityView3D
var traversal: CityTraversalWorld3D
var network: ExploreTransitNetwork
var route_data: Dictionary = {}
var supports: Array[Dictionary] = []
var _hidden: Array[Dictionary] = []
var _terrain: Array[Dictionary] = []
var _portal_openings: Dictionary = {}
var _portal_passages: Dictionary = {}
var _portal_floor_source := PackedVector3Array()
var _portal_floor_projected := PackedVector3Array()
var _station_cuts: Dictionary = {}
var _floor_projection: Dictionary = {}
var _portal_source := PackedVector3Array()
var _portal_projected := PackedVector3Array()
var _faces := PackedVector3Array()
var _colors := PackedColorArray()
var _physical := PackedVector3Array()
var active_stations: Array[Dictionary] = []
var elevators: Array[Node3D] = []
var _station_spaces: Array[Dictionary] = []
# Lookup cache over `supports`, rebuilt lazily whenever its size changes or the
# world is cleared: each support's inverse pose and, per city cell, the ordered
# indices of supports whose accepted floor window can reach that cell.
var _support_inverse: Array[Transform3D] = []
var _support_cells: Dictionary = {}
var _support_all := PackedInt32Array()
var _support_indexed := -1
const SUPPORT_CELL_MARGIN := .01
## Inner face of the platform-side station wall, which also closes the lift
## lobby. The platform slab, furnishings and the doorway all meet it here.
const PLATFORM_WALL_FACE := .3225
const PLATFORM_WALL_THICKNESS := .010
static var _track_material: ShaderMaterial
const SAND := Color(.65,.50,.33)
const TEAL := Color(.04,.35,.34)
const ROOM_HALF_LENGTH := .46
const ROOM_HALF_WIDTH := .36

func bind(value: CityView3D, physical: CityTraversalWorld3D, routes: ExploreTransitNetwork) -> void:
	view = value
	traversal = physical
	network = routes

## Names are presentation data; keep every platform, shaft and collision intact.
func refresh_names() -> void:
	if network == null: return
	network.refresh_route_names(route_data)
	for stop: Dictionary in active_stations: network.refresh_station_record(stop)
	for lift: Node3D in elevators: network.refresh_station_record(lift.station)
	for child: Node in get_children():
		if child.has_meta("station_name_anchor"):
			var anchor: Vector2i = child.get_meta("station_name_anchor")
			var subway := network.city.building.atv(anchor)==Buildings.SUBWAY_STATION
			ExploreStationInterior.refresh_title(child,StationNameResolver.display_name(network.city,anchor,subway))
		elif child.has_meta("station_entry_anchor"):
			var anchor: Vector2i = child.get_meta("station_entry_anchor")
			StationEntrySign3D.set_title(child,StationNameResolver.display_name(network.city,anchor,true))

func build(path: Dictionary) -> void:
	if path.is_empty():
		clear()
		route_data = path
		return
	# _apply_cutouts always rebuilds the view batches, and re-projects physics
	# whenever this route cuts a station or portal. Restoring either from the
	# previous route first would only be replaced again with the same result.
	var profiles := {}
	var reprojects := false
	for key: Vector3i in path.nodes:
		if key.y!=3: continue
		var cell := Vector2i(key.x,key.z)
		profiles[cell] = CityPortal3D.profile(network.city,cell,CityGeometry3D.HEIGHT)
		if not profiles[cell].is_empty() and not bool(profiles[cell].tunnel): reprojects = true
	for stop: Dictionary in path.stops:
		if bool(network.station_for_route(path,int(stop.station)).subway): reprojects = true
	clear(not reprojects,false)
	route_data = path
	var cuts := {}
	for key: Vector3i in path.nodes:
		if key.y!=3: continue
		var cell := Vector2i(key.x,key.z)
		var profile: Dictionary = profiles[cell]
		if not profile.is_empty() and not bool(profile.tunnel):
			_portal_openings[cell] = profile
			var passages: Array[Dictionary] = []
			var endpoint: Vector3 = network.nodes[key].point
			for neighbor: Vector3i in network.nodes[key].links:
				if neighbor.y!=1: continue
				var delta: Vector3 = network.nodes[neighbor].point-endpoint
				var horizontal := Vector2(delta.x,delta.z).normalized()
				if horizontal.dot(Vector2(profile.inward))>.95: continue
				# A converter may turn beside its ramp. Excavate that real tube
				# from the old ramp/side wall, which otherwise crosses the cabin.
				var at := Transform3D(Basis.looking_at(delta.normalized()),endpoint)
				passages.append({"at":at,"inverse":at.affine_inverse(),"bounds":AABB(Vector3(-.35,-.035,-delta.length()-.02),Vector3(.70,.355,delta.length()+.035))})
			if not passages.is_empty(): _portal_passages[cell] = passages
	for stop: Dictionary in path.stops:
		var station: Dictionary = network.station_for_route(path,int(stop.station))
		active_stations.append(station)
		if station.subway:
			var lift_pose := Elevator.pose_for(station)
			cuts[station.anchor]={"at":lift_pose,"inverse":lift_pose.affine_inverse(),"bounds":AABB(Vector3(.337,-.10,-.17),Vector3(.156,float(station.surface)-lift_pose.origin.y+.40,.205))}
		_platform(station)
	for id: Vector3i in path.nodes:
		if id.y not in [1,3]: continue
		var point: Vector3 = network.nodes[id].point
		var at_station := false
		for station: Dictionary in active_stations:
			if station.node == id: at_station = true
		var curve := network.corner_points(id) if not at_station else PackedVector3Array()
		if not curve.is_empty():
			_curved_track(curve)
			_curved_tunnel(curve)
			continue
		var junction: Array[Vector2i] = []
		if not at_station: junction = _junction_directions(id)
		if not junction.is_empty():
			var low := point.y
			var high := point.y
			for adjacent: Vector3i in network.nodes[id].links:
				if adjacent.y not in [1,3]: continue
				low = minf(low,network.nodes[adjacent].point.y)
				high = maxf(high,network.nodes[adjacent].point.y)
			_junction_chamber(point,junction,id.y!=3,low-point.y,high-point.y)
		for next: Vector3i in network.nodes[id].links:
			if next.y not in [1,3]: continue
			var other: Vector3 = network.nodes[next].point
			var delta := other-point
			var direction := delta.normalized()
			var right := Vector3(-direction.z,0,direction.x)
			# Each subway or converter end emits half of its actual edge.
			var fraction := .5
			var span := delta.length()*fraction
			var pose := Transform3D(Basis.looking_at(direction),point+delta*fraction*.5)
			var closed_branch: bool=not path.nodes.has(next)
			var track_span := span+(.12 if closed_branch else 0.0)
			var track_pose := Transform3D(pose.basis,point+direction*track_span*.5)
			# Neighbouring half-edges meet exactly at shared node and midpoint
			# planes; any overlap would put identical coplanar finishes in a fight.
			if curve.is_empty(): _track(track_pose,track_span)
			var trim := 0.0
			var roof_inset := 0.0
			if not at_station:
				# A bend/branch gets one open central chamber. Spoke walls begin
				# at its wall's inner face, lining the opening's hollow post zone;
				# the roof begins at the chamber roof's edge.
				if not junction.is_empty():
					trim = .3475
					roof_inset = .025
			else:
				# The room cuts the portal through its wall, and that cut is
				# hollow. The tube's side walls start at the room's inner wall
				# face so they line the cut; its roof starts past the room's
				# soffit, which already covers the wall thickness.
				var reach := _station_room_reach(id,direction)
				trim = reach.inner
				roof_inset = reach.outer-reach.inner
			var wall_span := maxf(0,span-trim+(.12 if closed_branch else 0.0))
			if wall_span>.001:
				var wall_pose := Transform3D(pose.basis,point+direction*(trim+wall_span*.5))
				_tunnel_shell(wall_pose,wall_span,minf(roof_inset,wall_span))
			if closed_branch:
				_tunnel_cap(Transform3D(pose.basis,point+direction*(span+.12)))
			# Tunnel floors are valid support only within this finite track tube.
			supports.append({"at":track_pose,"bounds":AABB(Vector3(-.30,-.073,-track_span*.5-.01),Vector3(.60,.30,track_span+.02)),"floor":-.015,"track_bed":true})
	if not _faces.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.mesh = CityGeometry3D.mesh_from_faces(_faces,_colors)
		# Tunnel interiors need readable indirect light even below opaque terrain.
		var material := StandardMaterial3D.new()
		material.resource_name="transit_running_track"
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		add_child(mesh)
	if not _physical.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = ExploreActorProfile.FLOOR | ExploreActorProfile.OBSTACLE
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_physical)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	ExploreStationInterior.finish_world(self)
	_station_cuts = cuts.duplicate()
	_apply_cutouts(cuts)

## Distances from a station node to the room wall's inner face and to the
## outer edge of its soffit along `direction`. The platform-side wall is the
## thin lobby wall, inside the soffit's edge.
func _station_room_reach(id: Vector3i, direction: Vector3) -> Dictionary:
	for station: Dictionary in active_stations:
		if station.get("node",Vector3i(-1,-1,-1))!=id: continue
		var local := Basis(Vector3.UP,float(station.yaw)).inverse()*direction
		if absf(local.z)>.5: return {"inner":ROOM_HALF_LENGTH-.0125,"outer":ROOM_HALF_LENGTH+.0125}
		if signf(local.x)==float(station.side): return {"inner":PLATFORM_WALL_FACE,"outer":ROOM_HALF_WIDTH+.0125}
		return {"inner":ROOM_HALF_WIDTH-.0125,"outer":ROOM_HALF_WIDTH+.0125}
	return {"inner":0.0,"outer":0.0}

## Grade rise of the station room's soffit above the station node.
func station_ceiling_rise(station: Dictionary) -> float:
	var envelope := _room_grade(station)
	return float(envelope.high)

## Track grades through the station set its floor and soffit envelope.
func _room_grade(station: Dictionary) -> Dictionary:
	var high := 0.0
	var low := 0.0
	var edges: Array[Vector3] = []
	if network!=null and network.nodes.has(station.get("node",Vector3i(-1,-1,-1))):
		for key: Vector3i in network.nodes[station.node].links:
			if key.y in [1,3]: edges.append(network.nodes[key].point-station.position)
	else: edges=[Vector3(station.forward),-Vector3(station.forward)]
	for delta: Vector3 in edges:
		var horizontal := Vector2(delta.x,delta.z).length()
		if horizontal<.01: continue
		high=maxf(high,delta.y*.50/horizontal)
		low=minf(low,delta.y*.50/horizontal)
	return {"high":high,"low":low,"edges":edges}

## Cardinal flat subway nodes only; sloped portal transitions use a plain
## continuous tube. Chamber dimensions fit the turning carriage.
func _junction_directions(id: Vector3i) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	var point: Vector3 = network.nodes[id].point
	var portal := id.y==3
	for next: Vector3i in network.nodes[id].links:
		if next.y==3: portal = true
	if not portal:
		for next: Vector3i in network.nodes[id].links:
			if next.y!=1: continue
			var delta: Vector3 = network.nodes[next].point-point
			if absf(delta.y)>.0001: return []
	for next: Vector3i in network.nodes[id].links:
		if next.y not in [1,2,3]: continue
		var delta: Vector3 = network.nodes[next].point-point
		for direction: Vector2i in [Vector2i(signf(delta.x),0),Vector2i(0,signf(delta.z))]:
			if direction!=Vector2i.ZERO and not directions.has(direction): directions.append(direction)
	if directions.size()<2: return []
	if not portal and directions.size()==2 and directions[0]==-directions[1]: return []
	return directions

func _junction_chamber(point: Vector3, openings: Array, roof := true, low := 0.0, high := 0.0) -> void:
	var at := Transform3D(Basis.IDENTITY,point)
	var start := _faces.size()
	# Sloped spoke floors remain continuous above this chamber's lowest floor;
	# a flat shelf must never protrude through a descending carriage corridor.
	add_box(at,Vector3(0,low-.095,0),Vector3(.745,.04,.745),Color(.20,.23,.22),true)
	if roof: add_box(at,Vector3(0,high+.27,0),Vector3(.745,.025,.745),ShellFinish.CREAM,true)
	var wall_height: float = high-low+.30
	var wall_center: float = (high+low)*.5+.115
	for direction: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var forward := Vector3(direction.x,0,direction.y)
		var wall := Transform3D(Basis.looking_at(forward),point+forward*.36)
		if not openings.has(direction):
			add_box(wall,Vector3(0,wall_center,0),Vector3(.745,wall_height,.025),ShellFinish.CREAM,true)
			add_box(wall,Vector3(0,low+.012,.014),Vector3(.72,.17,.002),ShellFinish.TEAL,false)
			add_box(wall,Vector3(0,high+.245,.015),Vector3(.72,.003,.003),ShellFinish.LIGHT,false)
		else:
			for side in [-1,1]:
				add_box(wall,Vector3(side*.34,wall_center,0),Vector3(.04,wall_height,.025),TEAL,true)
	ShellFinish.finish_passage(self,at,start)
	supports.append({"at":at,"bounds":AABB(Vector3(-.36,low-.078,-.36),Vector3(.72,high-low+.31,.72)),"floor":low-.075})

func _platform(station: Dictionary) -> void:
	var pose := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position)
	var side := float(station.side)
	var subway := bool(station.subway)
	var slab_start := _faces.size()
	if subway:
		# A solid terrazzo platform from the ballast base to the wall face; no
		# hollow under the edge and no second floor sharing its plane.
		var inner := PLATFORM_WALL_FACE
		add_box(pose,Vector3(side*(.14+inner)*.5,-.025,0),Vector3(inner-.14,.10,.895),ShellFinish.STONE,true)
	else:
		# Surface platform and its shallow approach steps share the terrazzo
		# finish of the rail hall apron; the last tread tucks under the lot slab.
		add_box(pose,Vector3(side*.245,.005,0),Vector3(.21,.04,.90),ShellFinish.STONE,true)
		var base: float = float(station.surface)-station.position.y
		# Each tread carries a brass nosing on its outer edge, as does the
		# platform edge above the first tread, so the steps read individually.
		add_box(pose,Vector3(side*.346,.0262,0),Vector3(.008,.0024,.88),ShellFinish.BRASS,false)
		for i: int in 3:
			var x := side*(.375+float(i)*.05)
			var width := .05 if i<2 else .065
			if i==2: x = side*.4825
			var y := lerpf(.025,base+.0115,float(i+1)/3.0)
			add_box(pose,Vector3(x,y-.014,0),Vector3(width,.028,.88),ShellFinish.STONE,true)
			if i<2: add_box(pose,Vector3(x+side*(width*.5-.004),y+.0012,0),Vector3(.008,.0024,.88),ShellFinish.BRASS,false)
	add_box(pose,Vector3(side*.150,.027,0),Vector3(.012,.004,.88),Color(.98,.73,.18),false)
	# Railings leave only the central boarding aperture accessible.
	for z: float in [-.27,.27]:
		# A real balustrade stands on the slab. Its continuous collision
		# barrier still prevents stepping into a moving carriage.
		ExploreStationInterior.add_solid_box(_physical,pose,Vector3(side*.147,.058,z),Vector3(.012,.07,.34))
		for post: int in 6:
			add_box(pose,Vector3(side*.147,.060,z-.170+post*.068),Vector3(.003,.068,.003),ShellFinish.BRASS,false)
		_rail(pose,Vector3(side*.147,.057,z-.170),Vector3(side*.147,.057,z+.170),.0010)
		_rail(pose,Vector3(side*.147,.094,z-.170),Vector3(side*.147,.094,z+.170),.0015)
	ShellFinish.finish_passage(self,pose,slab_start)
	supports.append({"at":pose,"bounds":AABB(Vector3(side*.245-.105,.024,-.45),Vector3(.21,.25,.9)),"floor":.025})
	if subway:
		_station_room(station)
		_elevator_access(station)
	var interior := ExploreStationInterior.populate(self,station)
	_physical.append_array(interior.faces)
	supports.append_array(interior.supports)

## Feet-height waypoints for physical walking through the actual access mesh.
## Reversing this list returns a passenger to the same surface entrance.
func access_waypoints(station: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not bool(station.subway):
		var entrance: Vector3 = station.platform+station.normal*.27
		entrance.y = float(station.surface)+.002
		out.append(entrance)
		out.append(station.platform+Vector3.UP*.002)
		return out
	var at := Elevator.pose_for(station)
	var top := float(station.surface)-at.origin.y+.007
	var mouth: Vector3=station.platform+station.normal*.11-at.basis.z*.30
	return PackedVector3Array([at*Vector3(.24,top,-.52),at*Vector3(.24,top,-.30),at*Vector3(.415,top,-.26),at*Vector3(.415,top,-.07),at*Vector3(.415,.027,-.07),at*Vector3(.415,.027,-.30),mouth+Vector3.UP*.002,station.platform-at.basis.z*.30+Vector3.UP*.002,station.platform+Vector3.UP*.002])

## One closed room with genuine portals, shared with the adjoining tube shells.
## Track grades set the floor and soffit envelope; only real openings are cut.
func _station_room(station: Dictionary) -> void:
	var at := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position)
	var side := float(station.side)
	var start := _faces.size()
	var grade := _room_grade(station)
	var high: float = grade.high
	var low: float = grade.low
	var edges: Array[Vector3] = grade.edges
	# The floor sits below the ballast base so the two never share a plane.
	add_box(at,Vector3(0,low-.095,0),Vector3(.745,.04,.945),Color(.30,.31,.29),true)
	var lift := Elevator.pose_for(station)
	var ceiling_start := _faces.size()
	var ceiling_physical := _physical.size()
	add_box(at,Vector3(0,high+.27,0),Vector3(.745,.024,.945),ShellFinish.CREAM,true)
	# The cabin travels through the soffit inside its own enclosed shaft.
	var shaft_top: float = float(station.get("surface",station.position.y+.40))-lift.origin.y+.40
	_clip_shell(ceiling_start,ceiling_physical,Elevator.shaft_column(lift,shaft_top))
	var wall_start := _faces.size()
	var physical_start := _physical.size()
	var height := high-low+.40
	var center := (high+low)*.5+.10
	# The platform-side wall is thinner and also closes the lift lobby; the
	# far wall keeps the heavier tube-width shell.
	for s: float in [-1.0,1.0]:
		var platform_side := s==side
		var x := s*(PLATFORM_WALL_FACE+PLATFORM_WALL_THICKNESS*.5) if platform_side else s*ROOM_HALF_WIDTH
		var thickness := PLATFORM_WALL_THICKNESS if platform_side else .025
		var face := x-s*thickness*.5
		# The thin platform wall stops at the end walls' inner faces; the end
		# walls fill the corner, where the tube lining also runs.
		var depth := 2*(ROOM_HALF_LENGTH-.0125) if platform_side else .945
		add_box(at,Vector3(x,center,0),Vector3(thickness,height,depth),ShellFinish.CREAM,true)
		add_box(at,Vector3(face-s*.0015,low+.012,0),Vector3(.003,.17,.935),ShellFinish.TEAL,false)
		add_box(at,Vector3(face-s*.0035,high+.238,0),Vector3(.004,.008,.925),ShellFinish.BRASS,false)
		add_box(at,Vector3(face-s*.0065,high+.238,0),Vector3(.003,.003,.920),ShellFinish.LIGHT,false)
	for z: float in [-ROOM_HALF_LENGTH,ROOM_HALF_LENGTH]:
		add_box(at,Vector3(0,center,z),Vector3(.745,height,.025),ShellFinish.CREAM,true)
		add_box(at,Vector3(0,low+.012,z-signf(z)*.014),Vector3(.735,.17,.003),ShellFinish.TEAL,false)
		add_box(at,Vector3(0,high+.238,z-signf(z)*.016),Vector3(.725,.008,.004),ShellFinish.BRASS,false)
		add_box(at,Vector3(0,high+.238,z-signf(z)*.019),Vector3(.720,.003,.003),ShellFinish.LIGHT,false)
	for delta: Vector3 in edges:
		if delta.length()<.01: continue
		var portal := Transform3D(Basis.looking_at(delta.normalized()),station.position)
		# The cut's hollow top edge must sit inside the soffit, not a hairline
		# below it where the wall's inside would show.
		_clip_shell(wall_start,physical_start,{"at":portal,"inverse":portal.affine_inverse(),
			"bounds":AABB(Vector3(-.3075,-.085,-delta.length()*.5-.14),Vector3(.615,high+.355,delta.length()*.5+.15))})
	# The doorway ends in the platform's side wall, including oblique layouts.
	var from: Vector3=lift*Vector3(.415,.025,-.30)
	var to: Vector3=station.platform+station.normal*.11-lift.basis.z*.30
	var opening := Transform3D(Basis.looking_at((to-from).normalized()),(from+to)*.5)
	_clip_shell(wall_start,physical_start,{"at":opening,"inverse":opening.affine_inverse(),
		"bounds":AABB(Vector3(-.096,0,-from.distance_to(to)*.5-.11),Vector3(.192,.235,from.distance_to(to)+.22))})
	# The platform wall stands just outside the shaft's west wall, so it stays
	# whole beside the shaft: cutting it at the shaft envelope left hollow cut
	# edges and slots past the shaft wall ends, open to the ground behind.
	# Only shell inside the clear column (unusual offset layouts) is removed.
	_clip_shell(wall_start,physical_start,Elevator.shaft_column(lift,shaft_top))
	ShellFinish.finish_passage(self,at,start)
	var inner_min := minf(-side*(ROOM_HALF_WIDTH-.0125),side*PLATFORM_WALL_FACE)
	var inner_max := maxf(-side*(ROOM_HALF_WIDTH-.0125),side*PLATFORM_WALL_FACE)
	_station_spaces.append({"at":at,"inverse":at.affine_inverse(),
		"bounds":AABB(Vector3(inner_min,low-.075,-(ROOM_HALF_LENGTH-.0125)),Vector3(inner_max-inner_min,high-low+.333,2*(ROOM_HALF_LENGTH-.0125)))})

func _elevator_access(station: Dictionary) -> void:
	var lift := Elevator.new()
	add_child(lift)
	lift.configure(station)
	elevators.append(lift)
	var at := Elevator.pose_for(station)
	# The street-view model keeps its static display cabin; only this Explore
	# copy has it stripped so the working elevator can take its place. It
	# shares the lift pose, so its shaft, jambs and doorway match the cabin.
	var facade := (load("res://assets/desert-dreams-3d/233-blender.glb") as PackedScene).instantiate() as Node3D
	_strip_display(facade)
	_set_access_collisions(facade)
	var street := Transform3D(at.basis,Vector3(at.origin.x,station.surface,at.origin.z))
	facade.transform=Transform3D(street.basis.scaled(Vector3.ONE/16.0),street.origin)
	add_child(facade)
	var entry_sign := preload("res://scripts/exploration/transit/station_entry_sign_3d.gd").add_to(self,String(station.get("name","SUBWAY")))
	entry_sign.transform=street
	entry_sign.set_meta("station_entry_anchor",station.get("anchor",Vector2i(-1,-1)))
	# Small enclosed basement lobby, fully clear of the running carriage. The
	# station's platform wall is its platform-side wall; the floor and soffit
	# stop at the cabin's front so nothing rides along with it.
	var face_start := _faces.size()
	var physical_start := _physical.size()
	add_box(at,Vector3(.415,.005,-.305),Vector3(.17,.04,.27),ShellFinish.STONE,true)
	add_box(at,Vector3(.415,.257,-.31),Vector3(.17,.016,.26),ShellFinish.CREAM,true)
	var walls_start := _faces.size()
	var walls_physical := _physical.size()
	var offset_access := Vector3(station.get("access_position",station.position)).distance_to(station.position)>.001
	# A displaced lobby is not beside the platform wall, so it closes its own
	# west side; the connecting corridor opens through it.
	if offset_access: add_box(at,Vector3(PLATFORM_WALL_FACE+PLATFORM_WALL_THICKNESS*.5,.1355,-.30),Vector3(PLATFORM_WALL_THICKNESS,.227,.28),ShellFinish.CREAM,true)
	add_box(at,Vector3(.495,.1355,-.30),Vector3(.01,.227,.28),ShellFinish.CREAM,true)
	add_box(at,Vector3(.415,.1355,-.44),Vector3(.18,.227,.01),ShellFinish.CREAM,true)
	add_box(at,Vector3(.4125,.012,-.4335),Vector3(.155,.17,.003),ShellFinish.TEAL,false)
	add_box(at,Vector3(.4125,.238,-.4335),Vector3(.155,.008,.003),ShellFinish.BRASS,false)
	supports.append({"at":at,"bounds":AABB(Vector3(.33,.022,-.44),Vector3(.17,.24,.27)),"floor":.025})
	# The corridor is subtracted from the lobby interior and the whole lift
	# column, so its overrun can never cross the gateway or the cabin.
	var room := {"at":at,"inverse":at.affine_inverse(),"bounds":AABB(Vector3(PLATFORM_WALL_FACE+PLATFORM_WALL_THICKNESS,-.1,-.435),Vector3(Elevator.SHAFT_EAST_FACE-PLATFORM_WALL_FACE-PLATFORM_WALL_THICKNESS,.50,Elevator.SHAFT_REAR+.005+.435))}
	var from: Vector3=at*Vector3(.415,.025,-.30)
	var to: Vector3=station.platform+station.normal*.11-at.basis.z*.30
	var doorway := {"at":Transform3D(Basis.looking_at((to-from).normalized()),(from+to)*.5)}
	doorway.inverse=doorway.at.affine_inverse()
	# The doorway runs from the lobby centre toward the platform only. Behind
	# the centre it would open a diagonal layout's east wall onto the back of
	# the corridor, which is not closed there.
	doorway.bounds=AABB(Vector3(-.095,.002,-from.distance_to(to)*.5-.05),Vector3(.19,.22,from.distance_to(to)+.05))
	_clip_shell(walls_start,walls_physical,doorway)
	ShellFinish.finish_passage(self,at,face_start)
	# Only a displaced entrance needs a connecting corridor; an ordinary
	# lobby opens straight through the platform wall.
	if offset_access: _access_passage(from,to,room)
	ExploreStationInterior.add_plaque(self,at*Transform3D(Basis.IDENTITY,Vector3(.415,.19,-.4335)),"EXIT · ELEVATOR",.00027,ShellFinish.INK)

func _strip_display(node: Node) -> void:
	for child: Node in node.get_children():
		if String(child.name).begins_with("Display"): child.free()
		else: _strip_display(child)

func _set_access_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer=ExploreActorProfile.FLOOR|ExploreActorProfile.OBSTACLE
		node.collision_mask=0
	for child: Node in node.get_children(): _set_access_collisions(child)

func interact(traveler: ExplorePedestrian) -> bool:
	for lift: Node3D in elevators:
		if lift.interact(traveler): return true
	return false

func step(delta: float, traveler: ExplorePedestrian) -> void:
	for lift: Node3D in elevators: lift.step(delta,traveler)

func in_elevator(feet: Vector3) -> bool:
	for lift: Node3D in elevators:
		if lift.contains(feet): return true
	return false

func _track(at: Transform3D, length: float) -> void:
	# Solid ballast profile, with the surface railway's earth/timber/steel
	# palette. Tunnel gauge is scaled to the passenger carriage.
	var start := _faces.size()
	add_box(at,Vector3(0,-.09,0),Vector3(.64,.04,length),Color(.30,.31,.29,.9),true,true)
	var v := PackedVector3Array()
	for z: float in [-length*.5,length*.5]:
		v.append_array(PackedVector3Array([Vector3(-.22,-.07,z),Vector3(.22,-.07,z),Vector3(.135,-.015,z),Vector3(-.135,-.015,z)]))
	for indices: Array in [[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]]:
		for corner: int in [0,1,2,0,2,3]:
			var p: Vector3=at*v[indices[corner]]
			_faces.append(p)
			_colors.append(Color(.51,.50,.45,0))
			_physical.append(p)
	var count := maxi(1,ceili(length/.085))
	for i: int in count:
		var z := -length*.5+(float(i)+.5)*length/count
		add_box(at,Vector3(0,-.010,z),Vector3(.235,.010,.026),Color(.40,.33,.26,.3),false)
		for x: float in [-.065,.065]:
			add_box(at,Vector3(x,-.005,z),Vector3(.024,.003,.021),Color(.34,.35,.32,.6),false)
	for x: float in [-.065,.065]:
		add_box(at,Vector3(x,-.007,0),Vector3(.017,.003,length),Color(.43,.46,.44,.6),false,true)
		add_box(at,Vector3(x,-.001,0),Vector3(.003,.010,length),Color(.47,.49,.46,.6),false,true)
		add_box(at,Vector3(x,.006,0),Vector3(.011,.004,length),Color(.72,.75,.71,.6),false,true)
	_finish_track(at,start)

## Sweep a closed profile along the same quarter-circle used by the train.
## Shared section vertices prevent seams and rail-head steps between segments.
func _sweep_track(points: PackedVector3Array, profile: Array[Vector2], color: Color, physical: bool) -> void:
	var rows: Array[PackedVector3Array]=[]
	for i: int in points.size():
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		# Exact cardinal end tangents meet the adjoining straight rail cleanly.
		if i==0 or i==points.size()-1:
			if absf(tangent.x)>absf(tangent.z): tangent=Vector3(signf(tangent.x),0,0)
			else: tangent=Vector3(0,0,signf(tangent.z))
		var right := Vector3(-tangent.z,0,tangent.x)
		var row := PackedVector3Array()
		for offset: Vector2 in profile: row.append(points[i]+right*offset.x+Vector3.UP*offset.y)
		rows.append(row)
	for i: int in range(1,rows.size()):
		for j: int in profile.size():
			var k := (j+1)%profile.size()
			for p: Vector3 in [rows[i-1][j],rows[i][k],rows[i][j],rows[i-1][j],rows[i-1][k],rows[i][k]]:
				_faces.append(p); _colors.append(color)
				if physical: _physical.append(p)
	var cap := Geometry2D.triangulate_polygon(PackedVector2Array(profile))
	for end: int in [0,rows.size()-1]:
		for j: int in range(0,cap.size(),3):
			var triangle: Array=[cap[j],cap[j+1],cap[j+2]] if end>0 else [cap[j],cap[j+2],cap[j+1]]
			for k: int in triangle:
				_faces.append(rows[end][k]); _colors.append(color)
				if physical: _physical.append(rows[end][k])

func _curved_tunnel(points: PackedVector3Array) -> void:
	var start := _faces.size()
	for side: float in [-1.0,1.0]:
		var x := side*.32
		_sweep_track(points,[Vector2(x-.0125,-.095),Vector2(x+.0125,-.095),Vector2(x+.0125,.265),Vector2(x-.0125,.265)],ShellFinish.CREAM,true)
		x=side*.306
		_sweep_track(points,[Vector2(x-.001,-.077),Vector2(x+.001,-.077),Vector2(x+.001,.093),Vector2(x-.001,.093)],ShellFinish.TEAL,false)
		x=side*.301
		_sweep_track(points,[Vector2(x-.0015,.2165),Vector2(x+.0015,.2165),Vector2(x+.0015,.2195),Vector2(x-.0015,.2195)],ShellFinish.LIGHT,false)
	_sweep_track(points,[Vector2(-.3325,.2575),Vector2(.3325,.2575),Vector2(.3325,.2825),Vector2(-.3325,.2825)],ShellFinish.CREAM,true)
	_finish_curved_tunnel(points,start)
	for i: int in range(1,points.size()):
		var span := points[i].distance_to(points[i-1])
		var at := Transform3D(Basis.looking_at((points[i]-points[i-1]).normalized()),(points[i]+points[i-1])*.5)
		supports.append({"at":at,"bounds":AABB(Vector3(-.30,-.073,-span*.5-.001),Vector3(.60,.30,span+.002)),"floor":-.015,"track_bed":true})

func _finish_curved_tunnel(points: PackedVector3Array, start: int) -> void:
	# Arc-length UVs wrap the ceramic course around the bend, without a
	# projection switch or compressed grout halfway through the corner.
	var pivot := Vector3(points[0].x,points[0].y,points[-1].z)
	if absf(points[points.size()/2].distance_to(pivot)-.5)>.01:
		pivot=Vector3(points[-1].x,points[0].y,points[0].z)
	var first := Vector2(points[0].x-pivot.x,points[0].z-pivot.z).normalized()
	var finish := ShellFinish.finish_tool()
	for index: int in range(start,_faces.size(),3):
		var normal := (_faces[index+2]-_faces[index]).cross(_faces[index+1]-_faces[index]).normalized()
		var color := _colors[index]
		var kind := .4 if color==ShellFinish.TEAL else .8 if color==ShellFinish.LIGHT else .2
		if color==ShellFinish.CREAM and normal.y<-.7:
			color=ShellFinish.CEILING; kind=.26
		for n: int in 3:
			var point := _faces[index+n]
			var radial := Vector2(point.x-pivot.x,point.z-pivot.z)
			var angle := atan2(first.cross(radial),first.dot(radial))
			var uv := Vector2(angle*radial.length(),point.y-pivot.y)
			if absf(normal.y)>.7: uv=Vector2(angle*.5,radial.length())
			finish.set_normal(normal); finish.set_color(Color(color,kind)); finish.set_uv(uv*16.0); finish.add_vertex(point)
	_faces=_faces.slice(0,start); _colors=_colors.slice(0,start)
	var mesh := MeshInstance3D.new(); mesh.name="CurvedTunnelFinishes"; mesh.mesh=finish.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _curved_track(points: PackedVector3Array) -> void:
	var start := _faces.size()
	_sweep_track(points,[Vector2(-.33,-.11),Vector2(.33,-.11),Vector2(.33,-.07),Vector2(-.33,-.07)],Color(.30,.31,.29,.9),true)
	_sweep_track(points,[Vector2(-.22,-.07),Vector2(.22,-.07),Vector2(.135,-.015),Vector2(-.135,-.015)],Color(.51,.50,.45,0),true)
	for x: float in [-.065,.065]:
		# One continuous I-shaped running rail, including its foot and head.
		var profile: Array[Vector2]=[]
		for p: Vector2 in [Vector2(-.0085,-.0085),Vector2(.0085,-.0085),Vector2(.0085,-.0055),Vector2(.0015,-.0055),Vector2(.0015,.004),Vector2(.0055,.004),Vector2(.0055,.008),Vector2(-.0055,.008),Vector2(-.0055,.004),Vector2(-.0015,.004),Vector2(-.0015,-.0055),Vector2(-.0085,-.0055)]: profile.append(p+Vector2(x,0))
		_sweep_track(points,profile,Color(.72,.75,.71,.6),false)
	for i: int in range(1,24,2):
		var at := Transform3D(Basis.looking_at((points[i+1]-points[i-1]).normalized()),points[i])
		add_box(at,Vector3(0,-.010,0),Vector3(.235,.010,.026),Color(.40,.33,.26,.3),false)
		for x: float in [-.065,.065]: add_box(at,Vector3(x,-.005,0),Vector3(.024,.003,.021),Color(.34,.35,.32,.6),false)
	_finish_track(Transform3D.IDENTITY,start)

func _finish_track(at: Transform3D, start: int) -> void:
	if _track_material==null:
		_track_material=ShaderMaterial.new()
		_track_material.resource_name="transit_textured_track"
		_track_material.shader=preload("res://scripts/exploration/transit/track_finish.gdshader")
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(_track_material)
	var inverse := at.affine_inverse()
	for n: int in range(start,_faces.size(),3):
		var normal := (_faces[n+2]-_faces[n]).cross(_faces[n+1]-_faces[n]).normalized()
		var local_normal := at.basis.inverse()*normal
		for i: int in 3:
			var local: Vector3=inverse*_faces[n+i]
			tool.set_normal(normal)
			tool.set_color(_colors[n+i])
			var uv := Vector2(local.z,local.y) if absf(local_normal.x)>.7 else Vector2(local.x,local.z) if absf(local_normal.y)>.7 else Vector2(local.x,local.y)
			tool.set_uv(uv*16.0)
			tool.add_vertex(_faces[n+i])
	_faces=_faces.slice(0,start)
	_colors=_colors.slice(0,start)
	var mesh := MeshInstance3D.new()
	mesh.name="TexturedRunningTrack"
	mesh.mesh=tool.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func elevator_prompt(feet: Vector3) -> String:
	for lift: Node3D in elevators:
		var at: Vector3=lift.global_transform.affine_inverse()*feet
		if at.x>.0 and at.x<.55 and at.z>-.52 and at.z<.07:
			var message: String=lift.prompt(feet)
			if not message.is_empty(): return message
	return ""

func indoors(feet: Vector3) -> bool:
	for lift: Node3D in elevators:
		if lift.contains(feet): return true
		var p: Vector3=lift.global_transform.affine_inverse()*feet
		if p.x>-.01 and p.x<.51 and p.z>-.48 and p.z<.03 and p.y>lift.heights[1]-.01 and p.y<lift.heights[1]+.23: return true
	var supported := -1
	for stop: Dictionary in active_stations:
		if bool(stop.subway) and feet.y<float(stop.surface)-.07:
			# Support depends only on feet; evaluate it once for all stations.
			if supported<0: supported = 1 if contains(feet) else 0
			if supported==1: return true
	for index: int in _support_candidates(feet):
		var support: Dictionary = supports[index]
		if not bool(support.get("track_bed",false)): continue
		var local: Vector3=_support_inverse[index]*feet
		var tube: AABB=support.bounds
		if local.x>=tube.position.x and local.x<=tube.end.x and local.z>=tube.position.z and local.z<=tube.end.z and local.y>=-.08 and local.y<=.25: return true
	return false

## Finished running tube: solid walls/soffit, glazed ceramic lower panels
## and continuous warm side coves, all sharing the metre-scaled shader.
## `roof_inset` leaves the roof off the inner (+Z) end, where a station
## room's soffit already spans the tube.
func _tunnel_shell(at: Transform3D, length: float, roof_inset := 0.0) -> void:
	var start := _faces.size()
	var physical_start := _physical.size()
	for side: int in [-1,1]:
		add_box(at,Vector3(side*.32,.085,0),Vector3(.025,.36,length),ShellFinish.CREAM,true,true)
		add_box(at,Vector3(side*.306,.008,0),Vector3(.002,.17,length),ShellFinish.TEAL,false,true)
		add_box(at,Vector3(side*.304,.218,0),Vector3(.004,.009,length),ShellFinish.BRASS,false,true)
		add_box(at,Vector3(side*.301,.218,0),Vector3(.003,.003,length),ShellFinish.LIGHT,false,true)
	if length-roof_inset>.001:
		# Beside a station soffit the roof keeps its end caps: its underside sits
		# a hair below the soffit's, so an open end would show its inside there.
		add_box(at,Vector3(0,.27,-roof_inset*.5),Vector3(.66,.025,length-roof_inset),ShellFinish.CREAM,true,roof_inset<=0.0)
	for room: Dictionary in _station_spaces:
		_clip_shell(start,physical_start,room)
	ShellFinish.finish_passage(self,at,start)

func _tunnel_cap(at: Transform3D) -> void:
	var start := _faces.size()
	add_box(at,Vector3(0,.085,0),Vector3(.66,.36,.025),ShellFinish.CREAM,true)
	add_box(at,Vector3(0,.008,.014),Vector3(.62,.17,.002),ShellFinish.TEAL,false)
	add_box(at,Vector3(0,.218,.015),Vector3(.60,.003,.003),ShellFinish.LIGHT,false)
	ShellFinish.finish_passage(self,at,start)

## Walkable access only: this never creates a train node or changes a city grid.
func _access_passage(from: Vector3, to: Vector3, stairwell_space: Dictionary = {}) -> void:
	var delta := to-from
	if delta.length()<.01: return
	var at := Transform3D(Basis.looking_at(delta.normalized()),(from+to)*.5)
	var length := delta.length()+.40
	var face_start := _faces.size()
	var physical_start := _physical.size()
	# Overlap both rooms, then subtract their interiors. This gives oblique
	# doorways a continuous jamb without a fixed setback exposing the void,
	# and keeps the corridor floor and soffit off the rooms' own planes.
	add_box(at,Vector3(0,-.02,0),Vector3(.20,.04,length),ShellFinish.STONE,true)
	add_box(at,Vector3(0,.24,0),Vector3(.22,.02,length),ShellFinish.CREAM,true)
	for side: int in [-1,1]:
		add_box(at,Vector3(side*.105,.105,0),Vector3(.01,.25,length),ShellFinish.CREAM,true)
		add_box(at,Vector3(side*.099,.04,0),Vector3(.002,.08,length),ShellFinish.TEAL,false)
		_rail(at,Vector3(side*.09,.067,length*.5),Vector3(side*.09,.067,-length*.5))
	if not stairwell_space.is_empty(): _clip_shell(face_start,physical_start,stairwell_space)
	for room: Dictionary in _station_spaces:
		_clip_shell(face_start,physical_start,room)
	ShellFinish.finish_passage(self,at,face_start)
	supports.append({"at":at,"bounds":AABB(Vector3(-.10,-.003,-length*.5),Vector3(.20,.25,length)),"floor":0.0})

## Add a box of `size` centered at `center` in `at` space to the flat-colored
## shell; a `solid` box also blocks movement. A running box (`open_ends`)
## omits its two Z end caps: those planes are shared with the adjoining
## half-edge, whose own geometry continues the surface.
func add_box(at: Transform3D, center: Vector3, size: Vector3, color: Color, solid: bool, open_ends := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var faces := mesh.get_faces()
	for i: int in range(0,faces.size(),3):
		if open_ends:
			var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i])
			if absf(normal.z)>absf(normal.x)+absf(normal.y): continue
		for n: int in 3:
			var p := at*(faces[i+n]+center)
			_faces.append(p)
			_colors.append(color)
			if solid: _physical.append(p)

## A brass handrail from `from` to `to` in `at` space, both visible and solid.
func _rail(at: Transform3D, from: Vector3, to: Vector3, radius := .0016) -> void:
	var delta := to-from
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=radius
	cylinder.bottom_radius=radius
	cylinder.height=delta.length()
	cylinder.radial_segments=20
	cylinder.rings=1
	var along := Basis(Quaternion(Vector3.UP,delta.normalized()))
	for point: Vector3 in cylinder.get_faces():
		var placed: Vector3=at*((from+to)*.5+along*point)
		_faces.append(placed)
		_colors.append(ShellFinish.BRASS)
		_physical.append(placed)

## Cut a passage volume out of the shell triangles added since `face_start`
## and `physical_start`, keeping each visible triangle's color.
func _clip_shell(face_start: int, physical_start: int, passage: Dictionary) -> void:
	var visible: PackedVector3Array = _faces.slice(0,face_start)
	var colors: PackedColorArray = _colors.slice(0,face_start)
	for triangle: int in range(face_start,_faces.size(),3):
		var clipped := PassageClip.triangle(_faces[triangle],_faces[triangle+1],_faces[triangle+2],passage)
		visible.append_array(clipped)
		for vertex: int in clipped.size(): colors.append(_colors[triangle])
	_faces=visible
	_colors=colors
	var physical: PackedVector3Array = _physical.slice(0,physical_start)
	for triangle: int in range(physical_start,_physical.size(),3):
		physical.append_array(PassageClip.triangle(_physical[triangle],_physical[triangle+1],_physical[triangle+2],passage))
	_physical=physical

## Number of flat-colored shell vertices so far; a start index for take_shell().
func shell_face_count() -> int:
	return _faces.size()

## Remove and return the flat-colored shell triangles added since `start`, as
## {faces, colors}, so a finish pass can rebuild them as one textured surface.
## Collision triangles are kept.
func take_shell(start: int) -> Dictionary:
	var shell := {"faces":_faces.slice(start),"colors":_colors.slice(start)}
	_faces=_faces.slice(0,start)
	_colors=_colors.slice(0,start)
	return shell

func support_for(feet: Vector3) -> Dictionary:
	for lift: Node3D in elevators:
		var moving: Dictionary=lift.support_for(feet)
		if not moving.is_empty(): return moving
	var best: Dictionary = {}
	var highest := -INF
	for index: int in _support_candidates(feet):
		var support: Dictionary = supports[index]
		var local: Vector3 = _support_inverse[index]*feet
		var box: AABB = support.bounds
		if local.x<box.position.x or local.x>box.end.x or local.z<box.position.z or local.z>box.end.z: continue
		# Admit the pedestrian's bounded step-up probe below a tread; the caller
		# still applies its requested asymmetric rise/drop window.
		var floor_y: float=support.floor
		if support.get("track_bed",false): floor_y=-.015- .055*clampf((absf(local.x)-.135)/.085,0,1)
		if local.y < floor_y-ExplorePedestrian.STEP-.002 or local.y>floor_y+.23: continue
		var position: Vector3 = support.at*Vector3(local.x,floor_y,local.z)
		if position.y>highest:
			highest = position.y
			best = {"position":position,"normal":Vector3.UP}
	return best

func contains(feet: Vector3) -> bool:
	return not support_for(feet).is_empty()

## Indices, in `supports` order, of supports that may accept feet. Each support
## is registered in every cell its world bounds touch, so this never misses one
## that support_for or indoors would accept.
func _support_candidates(feet: Vector3) -> PackedInt32Array:
	if _support_indexed!=supports.size(): _index_supports()
	if not feet.is_finite(): return _support_all
	var cell := Vector2i(floori(feet.x),floori(feet.z))
	if cell.x<-1 or cell.y<-1 or cell.x>City.WIDTH or cell.y>City.HEIGHT: return _support_all
	return _support_cells.get(cell,PackedInt32Array())

func _index_supports() -> void:
	_support_inverse.clear()
	_support_cells.clear()
	_support_all = PackedInt32Array()
	var buckets := {}
	for index: int in supports.size():
		var support: Dictionary = supports[index]
		var at: Transform3D = support.at
		_support_inverse.append(at.affine_inverse())
		_support_all.append(index)
		var box: AABB = support.bounds
		var floor_y: float = support.floor
		var low := floor_y-ExplorePedestrian.STEP-.002
		var high := floor_y+.23
		if bool(support.get("track_bed",false)):
			# Track beds slope down to -.07 at the edges; indoors uses -.08..25.
			low = minf(-.07-ExplorePedestrian.STEP-.002,-.08)
			high = .25
		var local := AABB(Vector3(box.position.x,low,box.position.z),Vector3(box.size.x,high-low,box.size.z)).abs()
		var reach: AABB = at*local
		var first := Vector2i(floori(reach.position.x-SUPPORT_CELL_MARGIN),floori(reach.position.z-SUPPORT_CELL_MARGIN))
		var last := Vector2i(floori(reach.end.x+SUPPORT_CELL_MARGIN),floori(reach.end.z+SUPPORT_CELL_MARGIN))
		first = first.clamp(Vector2i(-1,-1),Vector2i(City.WIDTH,City.HEIGHT))
		last = last.clamp(Vector2i(-1,-1),Vector2i(City.WIDTH,City.HEIGHT))
		for z: int in range(first.y,last.y+1):
			for x: int in range(first.x,last.x+1):
				var cell := Vector2i(x,z)
				if not buckets.has(cell): buckets[cell] = []
				buckets[cell].append(index)
	for cell: Vector2i in buckets: _support_cells[cell] = PackedInt32Array(buckets[cell])
	_support_indexed = supports.size()

func _apply_cutouts(cuts: Dictionary) -> void:
	# Remove physical station shells only for prepared service stations. Query
	# proxies and city layers are left untouched.
	view.mesh_batches.clear()
	for model: Node3D in view.buildings.get_children():
		for station: Dictionary in active_stations:
			# A rail hall stays exactly as the city shows it; only a subway
			# entrance is replaced so its shaft can be excavated and worked.
			if bool(station.subway) and model.get_meta("cell",Vector2i(-1,-1)) == station.anchor:
				_hidden.append({"node":weakref(model),"visible":model.visible})
				model.hide()
				_hide_shells(model)
	if not _portal_openings.is_empty(): _open_portal_meshes(view.networks)
	view.mesh_batches.rebuild([view.buildings,view.networks])
	if cuts.is_empty() and _portal_openings.is_empty(): return
	var snapshot := view.traversal_snapshot()
	var terrain_meshes := view.terrain_meshes()
	for origin: Vector2i in terrain_meshes:
		var node: MeshInstance3D = terrain_meshes[origin]
		var touch := false
		for cell: Vector2i in cuts:
			if Rect2i(origin,Vector2i.ONE*view.CHUNK_SIZE).has_point(cell): touch = true
		if not touch: continue
		_terrain.append({"node":weakref(node),"mesh":node.mesh})
		var source := node.mesh
		var faces := PackedVector3Array()
		var colors := PackedColorArray()
		for surface: int in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var paint: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i: int in range(0,count,3):
				var ids := [indices[i],indices[i+1],indices[i+2]] if not indices.is_empty() else [i,i+1,i+2]
				var midpoint := (vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3.0
				var clipped := _cut_station_triangle(vertices[ids[0]],vertices[ids[1]],vertices[ids[2]],cuts)
				for point: Vector3 in clipped:
					faces.append(point)
					colors.append(paint[ids[0]] if not paint.is_empty() else SAND)
		node.mesh = CityGeometry3D.mesh_from_faces(faces,colors,.025,CityGeometry3D.SurfaceKind.TERRAIN)
		_terrain[-1].projected = node.mesh
	var projected := apply_physical_projection(snapshot)
	traversal.rebuild(view.city,projected.chunks,projected.networks,snapshot.revision)

## The controller's incremental collision refresh must use the current station
## and portal holes. Cache only affected packed arrays, preserving all other data.
func apply_physical_projection(snapshot: Dictionary) -> Dictionary:
	if _station_cuts.is_empty() and _portal_openings.is_empty(): return snapshot
	var projected := snapshot.duplicate()
	var chunks: Array[Dictionary] = []
	for data: Dictionary in snapshot.chunks:
		var bounds: Rect2i = data.get("bounds",Rect2i(0,0,City.WIDTH,City.HEIGHT))
		var affected := false
		for cell: Vector2i in _station_cuts:
			if bounds.has_point(cell):
				affected = true
				break
		if not affected:
			chunks.append(data)
			continue
		var source: PackedVector3Array = data.physical_floor_faces
		var cached: Dictionary = _floor_projection.get(bounds,{})
		if cached.is_empty() or cached.source!=source:
			cached = {"source":source.duplicate(),"projected":_filter(source,_station_cuts)}
			_floor_projection[bounds] = cached
		var copy := data.duplicate()
		copy.physical_floor_faces = cached.projected
		chunks.append(copy)
	projected.chunks = chunks
	if not _portal_openings.is_empty():
		var source: PackedVector3Array = snapshot.networks.get("physical_obstacle_faces",PackedVector3Array())
		if _portal_source!=source or _portal_projected.is_empty():
			_portal_source = source.duplicate()
			_portal_projected = _filter_portal_faces(source)
		var physical: Dictionary = snapshot.networks.duplicate()
		physical.physical_obstacle_faces = _portal_projected
		var floors: PackedVector3Array = snapshot.networks.get("physical_floor_faces",PackedVector3Array())
		if _portal_floor_source!=floors or _portal_floor_projected.is_empty():
			_portal_floor_source = floors.duplicate()
			_portal_floor_projected = _filter_portal_faces(floors)
		physical.physical_floor_faces = _portal_floor_projected
		projected.networks = physical
	return projected

## Ordinary building changes keep every transit mesh. A changed station or
## portal-containing render region must regain its cutout before movement.
func refresh_visual_projection() -> void:
	if route_data.is_empty(): return
	for record: Dictionary in _terrain:
		var node: Variant = record.node.get_ref()
		if not is_instance_valid(node) or node.mesh!=record.get("projected"):
			build(route_data)
			return
	for record: Dictionary in _hidden:
		var node: Variant = record.node.get_ref()
		if not is_instance_valid(node):
			build(route_data)
			return

## Match only the authored recess plane, never an entire portal cell. Side
## walls, beams, travel floor and city layers stay intact.
func _is_portal_recess(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var center := (a+b+c)/3.0
	var cell := Vector2i(floori(center.x),floori(center.z))
	if not _portal_openings.has(cell): return false
	var profile: Dictionary = _portal_openings[cell]
	var origin: Vector2 = Vector2(cell)+Vector2(profile.outside)
	for point in [a,b,c]:
		var planar := Vector2(point.x,point.z)-origin
		if absf(planar.dot(profile.inward)-(float(profile.depth)+.025))>.0002: return false
		if absf(planar.dot(profile.across))>.3352: return false
		if point.y<float(profile.floor_end)-.0002 or point.y>float(profile.floor_end)+.4302: return false
	return true

func _filter_portal_faces(faces: PackedVector3Array) -> PackedVector3Array:
	if _portal_openings.is_empty(): return faces
	var out := PackedVector3Array()
	for i in range(0,faces.size(),3):
		out.append_array(_cut_portal_triangle(faces[i],faces[i+1],faces[i+2]))
	return out

func _cut_portal_triangle(a: Vector3, b: Vector3, c: Vector3) -> PackedVector3Array:
	if _is_portal_recess(a,b,c): return PackedVector3Array()
	var midpoint := (a+b+c)/3.0
	var cell := Vector2i(floori(midpoint.x),floori(midpoint.z))
	var result := PackedVector3Array([a,b,c])
	for passage: Dictionary in _portal_passages.get(cell,[]):
		var clipped := PackedVector3Array()
		for i: int in range(0,result.size(),3): clipped.append_array(PassageClip.triangle(result[i],result[i+1],result[i+2],passage))
		result = clipped
	return result

func _open_portal_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var faces := PackedVector3Array()
		var colors := PackedColorArray()
		var removed := false
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var paint: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var ids := [indices[i],indices[i+1],indices[i+2]] if not indices.is_empty() else [i,i+1,i+2]
				var original := PackedVector3Array([node.global_transform*vertices[ids[0]],node.global_transform*vertices[ids[1]],node.global_transform*vertices[ids[2]]])
				var clipped := _cut_portal_triangle(original[0],original[1],original[2])
				if clipped!=original: removed = true
				var inverse: Transform3D = node.global_transform.affine_inverse()
				for vertex: Vector3 in clipped:
					faces.append(inverse*vertex)
					colors.append(paint[ids[0]] if not paint.is_empty() else Color.WHITE)
		if removed:
			_terrain.append({"node":weakref(node),"mesh":node.mesh})
			node.mesh = CityGeometry3D.mesh_from_faces(faces,colors,.025,CityGeometry3D.SurfaceKind.NETWORK)
			_terrain[-1].projected = node.mesh
	for child in node.get_children(): _open_portal_meshes(child)

func _hide_shells(node: Node) -> void:
	if node is CollisionObject3D and node.collision_layer & 4:
		_hidden.append({"node":weakref(node),"layer":node.collision_layer})
		node.collision_layer = 0
	for child: Node in node.get_children(): _hide_shells(child)

func _filter(faces: PackedVector3Array, cuts: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in range(0,faces.size(),3):
		out.append_array(_cut_station_triangle(faces[i],faces[i+1],faces[i+2],cuts))
	return out

func _cut_station_triangle(a: Vector3, b: Vector3, c: Vector3, cuts: Dictionary) -> PackedVector3Array:
	var midpoint := (a+b+c)/3.0
	var cell := Vector2i(floori(midpoint.x),floori(midpoint.z))
	if not cuts.has(cell): return PackedVector3Array([a,b,c])
	# Only the enclosed shaft is excavated; the rest of the tile keeps its
	# rendered and physical ground surface.
	return PassageClip.triangle(a,b,c,cuts[cell])

## Visual cut-outs are always restored for Build mode. The physical restore is
## skipped only when the session ends, because the kept traversal world is
## rebuilt from the city before the next session queries it.
func clear(restore_physics: bool = true, restore_batches: bool = true) -> void:
	remove_meta("station_signs")
	remove_meta("station_interior_stats")
	for record: Dictionary in _terrain:
		var node: Variant = record.node.get_ref()
		if is_instance_valid(node): node.mesh = record.mesh
	_terrain.clear()
	_portal_openings.clear()
	_portal_passages.clear()
	_portal_floor_source.clear()
	_portal_floor_projected.clear()
	_station_cuts.clear()
	_floor_projection.clear()
	_portal_source.clear()
	_portal_projected.clear()
	for record: Dictionary in _hidden:
		var node: Variant = record.node.get_ref()
		if not is_instance_valid(node): continue
		if record.has("visible"): node.visible = record.visible
		else: node.collision_layer = record.layer
	var had_geometry := not route_data.is_empty()
	_hidden.clear()
	for node: Node in get_children(): node.free()
	_faces.clear()
	_colors.clear()
	_physical.clear()
	supports.clear()
	_support_indexed = -1
	active_stations.clear()
	_station_spaces.clear()
	elevators.clear()
	route_data = {}
	if had_geometry and is_instance_valid(view) and is_instance_valid(traversal):
		if restore_batches: view.mesh_batches.rebuild([view.buildings,view.networks])
		if restore_physics:
			var snapshot := view.traversal_snapshot()
			traversal.rebuild(view.city,snapshot.chunks,snapshot.networks,snapshot.revision)
