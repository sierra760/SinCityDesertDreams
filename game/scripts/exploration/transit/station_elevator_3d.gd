# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Two physical landings, interlocked doors and a continuously moving cabin.
## Local +X is the station's platform side; all lengths are tile units.
extends Node3D

const CENTER := Vector3(.415,0,-.07)
## Shaft walls in lift space: the west wall faces the platform, the east wall
## and rear wall sit inside the pavilion's own walls at street level.
const SHAFT_WEST_FACE := .331
const SHAFT_EAST_FACE := .4945
const SHAFT_FRONT := -.18
const SHAFT_REAR := .0305
const WALL := .010
const CABIN_HALF_WIDTH := .070
const CABIN_REAR := .090
var cabin: Node3D
var floor := 1
var state := "open"
var heights := PackedFloat32Array()
var station: Dictionary
var _destination := 0
var _from := 0.0
var _time := 0.0
var _duration := 0.0
var _door_fraction := 1.0
var _cabin_door: AnimatableBody3D
var _gates: Array[AnimatableBody3D] = []
var _gate_open := [false,false]
var _materials := {}
static var _lift_materials := {}
static var _finish_material: ShaderMaterial
var _floor_label: TextMesh
var _control_label: MeshInstance3D
var _door_obstructed := false

static func pose_for(stop: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,float(stop.yaw)+(PI if int(stop.side)<0 else 0.0)),stop.get("access_position",stop.position))

## The clear column inside the shaft walls, as a shell clip volume.
static func shaft_column(lift: Transform3D, top: float) -> Dictionary:
	return {"at":lift,"inverse":lift.affine_inverse(),
		"bounds":AABB(Vector3(SHAFT_WEST_FACE+WALL,-.12,SHAFT_FRONT+.008),Vector3(SHAFT_EAST_FACE-SHAFT_WEST_FACE-2*WALL,top+.12,SHAFT_REAR-WALL-SHAFT_FRONT-.008))}

## The shaft including its walls; station shells stop at this envelope.
static func shaft_envelope(lift: Transform3D, top: float) -> Dictionary:
	return {"at":lift,"inverse":lift.affine_inverse(),
		"bounds":AABB(Vector3(.318,-.12,SHAFT_FRONT-.005),Vector3(SHAFT_EAST_FACE-.318,top+.12,SHAFT_REAR-SHAFT_FRONT+.005))}

func configure(stop: Dictionary) -> void:
	station=stop
	transform=pose_for(stop)
	heights=PackedFloat32Array([.025,float(stop.surface)-global_position.y+.005])
	cabin=Node3D.new()
	cabin.name="ElevatorCabin"
	cabin.position=CENTER+Vector3.UP*heights[1]
	add_child(cabin)
	var body := AnimatableBody3D.new()
	body.sync_to_physics=false
	body.collision_layer=ExploreActorProfile.FLOOR|ExploreActorProfile.OBSTACLE
	body.collision_mask=0
	cabin.add_child(body)
	# The cabin is narrower than the shaft and the pavilion niche, so its
	# finishes never share a plane with the station or street walls.
	var inner := CABIN_HALF_WIDTH-.006
	_piece(body,Vector3(0,-.008,0),Vector3(.154,.016,.20),Color(.11,.15,.145))
	_piece(body,Vector3(0,.226,0),Vector3(.15,.012,.21),Color(.36,.49,.51))
	# Walls and skirtings seat a little into the floor at distinct depths, so
	# no two bottoms share the street floor plane with the pavilion walls.
	for x: float in [-CABIN_HALF_WIDTH,CABIN_HALF_WIDTH]:
		_piece(body,Vector3(x,.10875,0),Vector3(.012,.2225,.196),Color(.64,.68,.66))
		_piece(body,Vector3(signf(x)*(inner-.001),.03425,0),Vector3(.002,.0715,.166),Color(.31,.18,.079),false)
	_piece(body,Vector3(0,.10825,CABIN_REAR),Vector3(2*(CABIN_HALF_WIDTH-.006),.2235,.012),Color(.64,.68,.66))
	var rear_face := CABIN_REAR-.006
	_piece(body,Vector3(0,.03475,rear_face-.001),Vector3(.122,.0705,.002),Color(.31,.18,.079),false)
	_piece(body,Vector3(0,.21,rear_face-.0025),Vector3(.12,.003,.003),Color(.98,.87,.67),false)
	# One readable destination control faces the passenger as they enter.
	var label := ExploreStationInterior.add_plaque(cabin,Transform3D(Basis(Vector3.UP,PI),Vector3(0,.174,rear_face-.0015)),"PLATFORM",.00029,Color(.025,.24,.23),Vector2(.12,.024))
	_floor_label=label.mesh
	_floor_label.text="STREET"
	_control_label=ExploreStationInterior.add_plaque(cabin,Transform3D(Basis(Vector3.UP,PI),Vector3(0,.123,rear_face-.0015)),"PRESS F\nTO PLATFORM",.00027,Color(.025,.24,.23),Vector2(.12,.036))
	_button(cabin,Vector3(0,.083,rear_face-.0012))
	# Recessed bronze skirting and a horizontal grab rail stay clear of signs.
	_piece(body,Vector3(0,.057,rear_face-.0025),Vector3(.12,.003,.003),Color(.67,.47,.19),false)
	_cabin_door=_door(cabin,Vector3(0,.10,-.098))
	var shaft := StaticBody3D.new()
	shaft.collision_layer=ExploreActorProfile.FLOOR|ExploreActorProfile.OBSTACLE
	shaft.collision_mask=0
	add_child(shaft)
	var rise: float=heights[1]-heights[0]
	# Walls run from the pit floor to the pavilion ceiling backing; at street
	# level they sit inside the pavilion's own east and rear walls. The station
	# room wall is clipped away for the whole shaft envelope, so the pit floor
	# and the walls must close it below the platform slab's top as well.
	var wall_bottom := heights[0]-.045
	var wall_top := heights[1]+.2275
	var wall_mid := (wall_bottom+wall_top)*.5
	var shaft_length := SHAFT_REAR-SHAFT_FRONT
	var shaft_mid := (SHAFT_REAR+SHAFT_FRONT)*.5
	for x: float in [SHAFT_WEST_FACE+WALL*.5,SHAFT_EAST_FACE-WALL*.5]:
		_piece(shaft,Vector3(x,wall_mid,shaft_mid),Vector3(WALL,wall_top-wall_bottom,shaft_length),Color(.36,.49,.51))
	# The rear and front closures sit between the side walls, never sharing
	# their outer planes.
	var inner_width := SHAFT_EAST_FACE-SHAFT_WEST_FACE-2*WALL
	_piece(shaft,Vector3((SHAFT_WEST_FACE+SHAFT_EAST_FACE)*.5,wall_mid,SHAFT_REAR-WALL*.5-.001),Vector3(inner_width,wall_top-wall_bottom,WALL),Color(.36,.49,.51))
	# A solid pit floor under the platform-level cabin. It reaches west under
	# the clipped room wall to the platform slab and tucks its other ends into
	# the east wall, rear closure and lobby floor, so no face shares a plane.
	var pit_west := .319
	var pit_east := SHAFT_EAST_FACE-.003
	var pit_front := SHAFT_FRONT-.003
	var pit_rear := SHAFT_REAR-.003
	_piece(shaft,Vector3((pit_west+pit_east)*.5,heights[0]-.0385,(pit_front+pit_rear)*.5),Vector3(pit_east-pit_west,.023,pit_rear-pit_front),Color(.36,.49,.51))
	if rise>.235:
		# The front closes from the lower landing's header to just under the
		# street floor, so the lobby never looks up into the open column.
		var front_bottom := heights[0]+.228
		var front_top := heights[1]-.0055
		_piece(shaft,Vector3((SHAFT_WEST_FACE+SHAFT_EAST_FACE)*.5,(front_bottom+front_top)*.5,SHAFT_FRONT+WALL*.5+.001),Vector3(inner_width,front_top-front_bottom,WALL),Color(.36,.49,.51))
	for level: int in 2:
		_gates.append(_door(self,CENTER+Vector3(0,heights[level]+.10,-.112)))
		# Complete portal: wide landing name, lit call control, and a flush sill.
		if level==1: _piece(shaft,CENTER+Vector3(-.117,heights[level]+.0975,-.108),Vector3(.066,.206,.020),Color(.64,.68,.66))
		_piece(shaft,Vector3((SHAFT_WEST_FACE+SHAFT_EAST_FACE)*.5,heights[level]+.215,CENTER.z-.112),Vector3(inner_width-.002,.028,.018),Color(.36,.49,.51))
		ExploreStationInterior.add_plaque(self,Transform3D(Basis(Vector3.UP,PI),CENTER+Vector3(0,heights[level]+.215,-.1225)),"PLATFORM LEVEL" if level==0 else "STREET LEVEL",.00023,Color(.025,.24,.23),Vector2(.145,.024))
		for x: float in [-.083,.083]:
			_piece(shaft,CENTER+Vector3(x,heights[level]+.09775,-.113),Vector3(.014,.2045,.018),Color(.67,.47,.19))
		# The sill rises only 1.6 cm; the lift's bridge support holds the
		# passenger at floor level, so a taller threshold would trap them.
		_piece(shaft,CENTER+Vector3(0,heights[level]-.0015,-.125),Vector3(.16,.005,.032),Color(.50,.55,.54))
		if level==1:
			ExploreStationInterior.add_plaque(self,Transform3D(Basis(Vector3.UP,PI),CENTER+Vector3(-.117,heights[level]+.108,-.1195)),"PRESS F\nCALL LIFT",.00018,Color(.025,.24,.23),Vector2(.055,.030))
			_button(self,CENTER+Vector3(-.117,heights[level]+.078,-.1195))
		else:
			# The lobby's back wall is always outside the clipped diagonal
			# access passage. A pier beside this landing could obstruct ascent.
			ExploreStationInterior.add_plaque(self,Transform3D(Basis.IDENTITY,Vector3(.415,heights[level]+.100,-.4305)),"PRESS F\nCALL LIFT",.00023,Color(.025,.24,.23),Vector2(.090,.036))
			_button(self,Vector3(.415,heights[level]+.066,-.43075),1)

	_set_doors(1.0)
	_update_control()

func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color=color
		mat.roughness=.72
		mat.emission_enabled=true
		mat.emission=color
		mat.emission_energy_multiplier=.20
		_materials[color]=mat
	return _materials[color]

func _lift_material(kind: int, door := false) -> ShaderMaterial:
	var key := kind+10 if door else kind
	if not _lift_materials.has(key):
		var material := ShaderMaterial.new()
		material.resource_name="elevator_finish_"+str(key)
		material.shader=preload("res://scripts/exploration/transit/elevator_finish.gdshader")
		material.set_shader_parameter("finish",kind)
		material.set_shader_parameter("door_panel",door)
		_lift_materials[key]=material
	return _lift_materials[key]

func _piece(parent: CollisionObject3D, center: Vector3, size: Vector3, color: Color, physical := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size=size
	# Match the station's quiet terrazzo, glazed base and ivory/slate finishes.
	# Door panels retain brushed-metal material; every finish has metre UVs.
	var finish_kind := -.1
	if color==Color(.70,.66,.56): finish_kind=0.0

	elif color==Color(.36,.49,.51): finish_kind=.26
	elif color==Color(.035,.25,.24): finish_kind=.4
	elif color==Color(.98,.87,.67): finish_kind=.8
	var lift_kind := -1
	if color==Color(.64,.68,.66) or color==Color(.50,.55,.54): lift_kind=0
	elif color==Color(.67,.47,.19): lift_kind=1
	elif color==Color(.31,.18,.079): lift_kind=2
	elif color==Color(.11,.15,.145): lift_kind=3
	if finish_kind<0 and lift_kind<0: mesh.material=_material(color)
	var visual := MeshInstance3D.new()
	if finish_kind>=0 or lift_kind>=0:
		if _finish_material==null:
			_finish_material=ShaderMaterial.new()
			_finish_material.shader=preload("res://scripts/exploration/transit/stairwell_finish.gdshader")
			_finish_material.set_shader_parameter("terrazzo",load(ExploreStationInterior.ROOT+"warm-terrazzo.png"))
		var finish := SurfaceTool.new()
		finish.begin(Mesh.PRIMITIVE_TRIANGLES)
		finish.set_material(_lift_material(lift_kind) if lift_kind>=0 else _finish_material)
		var faces := mesh.get_faces()
		for i: int in range(0,faces.size(),3):
			var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
			for n: int in 3:
				var point := faces[i+n]
				var local := point+center
				var uv := Vector2(local.z,local.y) if absf(normal.x)>.7 else Vector2(local.x,local.z) if absf(normal.y)>.7 else Vector2(local.x,local.y)
				finish.set_normal(normal)
				finish.set_uv(uv*16.0)
				finish.set_color(Color(color,finish_kind))
				finish.add_vertex(point)
		visual.mesh=finish.commit()
	else: visual.mesh=mesh
	visual.position=center
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	if physical:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size=size
		shape.shape=box
		shape.position=center
		parent.add_child(shape)

func _button(parent: Node3D, at: Vector3, facing := -1) -> void:
	for face: int in 2:
		var visual := MeshInstance3D.new()
		visual.name="CallButtonBezel" if face==0 else "IlluminatedCallButton"
		var mesh := CylinderMesh.new()
		mesh.top_radius=.006 if face==0 else .0042
		mesh.bottom_radius=mesh.top_radius
		mesh.height=.0025 if face==0 else .001
		mesh.radial_segments=24
		mesh.material=_material(Color(.67,.47,.19) if face==0 else Color(.98,.87,.67))
		visual.mesh=mesh
		visual.position=at+Vector3(0,0,facing*face*.0025)
		visual.rotation.x=PI*.5
		parent.add_child(visual)

func _door(parent: Node3D, at: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics=false
	body.collision_layer=ExploreActorProfile.OBSTACLE
	body.collision_mask=0
	body.position=at
	body.set_meta("closed_at",at)
	parent.add_child(body)
	# The visible portions are clipped at the jambs as the two leaves retract
	# into their pockets. Neither their meshes nor blockers sweep into the lobby.
	for side: int in [-1,1]:
		var visual := MeshInstance3D.new()
		visual.name="LeftDoorLeaf" if side<0 else "RightDoorLeaf"
		visual.mesh=BoxMesh.new()
		visual.mesh.size=Vector3(.076,.20,.008)
		visual.mesh.material=_lift_material(1,true)
		visual.set_meta("side",side)
		body.add_child(visual)
		# One dark meeting seal, riding on the right leaf's edge, covers the
		# leaves' shared line on both faces; the leaves meet without overlap.
		for face: float in ([-1.0,1.0] if side>0 else []):
			var gasket := MeshInstance3D.new()
			gasket.name="DoorEdgeSeal"
			gasket.mesh=BoxMesh.new()
			gasket.mesh.size=Vector3(.0016,.20,.001)
			gasket.mesh.material=_material(Color(.075,.09,.085))
			gasket.position.z=face*.0045
			gasket.set_meta("side",side)
			gasket.set_meta("edge_seal",true)
			body.add_child(gasket)
		var collision := CollisionShape3D.new()
		collision.shape=BoxShape3D.new()
		collision.shape.size=Vector3(.076,.20,.008)
		collision.set_meta("side",side)
		body.add_child(collision)
	return body

func _set_doors(amount: float) -> void:
	_door_fraction=amount
	_set_panel(_cabin_door,amount)
	for level: int in 2:
		_gate_open[level]=level==floor and state in ["open","opening","closing"] and amount>.999
		var fraction := amount if level==floor and state!="moving" else 0.0
		_set_panel(_gates[level],fraction)

func _set_panel(body: AnimatableBody3D, fraction: float) -> void:
	body.visible=fraction<.999
	var width := maxf(.00001,.076*(1.0-fraction))
	for child: Node in body.get_children():
		var side := int(child.get_meta("side",1))
		if child.get_meta("edge_seal",false):
			child.position.x=side*(.076-width)
			continue
		child.position.x=side*(.076-width*.5)
		# The leaves meet edge to edge; the dark gasket straddling the meeting
		# line on both faces is the solid seam that hides any float slit.
		if child is MeshInstance3D: child.mesh.size.x=width
		if child is CollisionShape3D:
			child.shape.size.x=width+.0006
			child.set_deferred("disabled",fraction>=.999)

func landing_closed(level: int) -> bool:
	return not bool(_gate_open[level])

func contains(feet: Vector3) -> bool:
	var p := cabin.global_transform.affine_inverse()*feet
	return absf(p.x)<CABIN_HALF_WIDTH-.004 and p.z>=-.092 and p.z<=CABIN_REAR-.007 and p.y>=-.015 and p.y<=.21

func support_for(feet: Vector3) -> Dictionary:
	var p := cabin.global_transform.affine_inverse()*feet
	var inside := contains(feet)
	var bridge := _door_fraction>.999 and state=="open" and absf(p.x)<.07 and p.z>=-.15 and p.z<-.09 and p.y>=-.02 and p.y<.20
	if not inside and not bridge: return {}
	var support := {"position":cabin.global_transform*Vector3(p.x,0,p.z),"normal":Vector3.UP}
	if inside: support.frame=cabin
	return support

func _near_landing(feet: Vector3) -> int:
	var local := global_transform.affine_inverse()*feet
	for level: int in 2:
		var lower_lobby := level==0 and local.x>.323 and local.x<.507 and local.z>-.44 and local.z<-.16
		var front := local.z<CENTER.z-.085 and Vector2(local.x-CENTER.x,local.z-CENTER.z+.13).length()<.20
		if absf(local.y-heights[level])<.08 and (front or lower_lobby):
			return level
	return -1

func prompt(feet: Vector3) -> String:
	var inside := contains(feet)
	var landing := _near_landing(feet)
	if not inside and landing<0: return ""
	var destination := "platform" if _destination==0 else "street"
	if state!="open":
		if _door_obstructed: return "Step fully inside or clear the elevator doorway"
		if state=="moving": return "Elevator to "+destination+" — please wait"
		return "Doors closing — to "+destination if state=="closing" else "Arrived at "+destination+" — doors opening"
	if inside: return "F to ride to platform" if floor==1 else "F to ride to street"
	return "Enter elevator, then press F to ride" if landing==floor else "F to call elevator"

func _update_control() -> void:
	var words := "PRESS F\nTO PLATFORM" if floor==1 else "PRESS F\nTO STREET"
	if state!="open": words=("TO PLATFORM" if _destination==0 else "TO STREET")+"\nPLEASE WAIT"
	_control_label.mesh.text=words
	var size: Vector3=_control_label.mesh.get_aabb().size
	var board: MeshInstance3D=_control_label.get_meta("sign_backing").get_ref()
	var space: Vector3=board.mesh.size-Vector3(.010,.006,0)
	_control_label.scale=Vector3.ONE*minf(1.0,minf(space.x/maxf(size.x,.0001),space.y/maxf(size.y,.0001)))

func interact(traveler: ExplorePedestrian) -> bool:
	var feet := traveler.global_position
	if state!="open": return not prompt(feet).is_empty()
	var requested := -1
	if contains(feet):
		requested=1-floor
		traveler._support_frame=cabin
		traveler._support_transform=cabin.global_transform
	else:
		requested=_near_landing(feet)
	if requested<0: return false
	if requested==floor: return true
	_destination=requested
	state="closing"
	_update_control()
	return true

func step(delta: float, traveler: ExplorePedestrian) -> void:
	var dt := clampf(delta,0,.1)
	_door_obstructed=false
	match state:
		"closing":
			var p := cabin.global_transform.affine_inverse()*traveler.global_position
			if absf(p.x)<.10 and absf(p.z+.105)<.035 and p.y>=-.02 and p.y<.22:
				_door_obstructed=true
				_set_doors(minf(1.0,_door_fraction+dt*1.8))
				return
			_set_doors(maxf(0.0,_door_fraction-dt*1.8))
			if _door_fraction<=0:
				state="moving"
				_from=cabin.position.y
				_time=0
				_duration=maxf(2.5,absf(heights[_destination]-_from)/.30)
				_set_doors(0)
		"moving":
			_time=minf(_duration,_time+dt)
			var t := _time/_duration
			cabin.position.y=lerpf(_from,heights[_destination],t*t*(3-2*t))
			if _time>=_duration:
				floor=_destination
				_floor_label.text="PLATFORM" if floor==0 else "STREET"
				state="opening"
		"opening":
			_set_doors(minf(1.0,_door_fraction+dt*1.8))
			if _door_fraction>=1:
				state="open"
				_update_control()
