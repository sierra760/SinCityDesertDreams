# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Station furnishings built from the shared Desert Transit finish system:
## mounted enamel name boards, DT roundels, brass-and-teal benches, warm
## ceiling fixtures and BioRhyme wayfinding. Every placement leaves the lift
## doorway, the platform walk lane and the boarding aperture clear.
class_name ExploreStationInterior
extends RefCounted

const ROOT := "res://assets/station-interiors/"
const FURNISHING_LAYER := 1 << 19
const TRANSIT_FONT := preload("res://assets/fonts/biorhyme/BioRhyme-Medium.ttf")
const IVORY := Color(.96,.87,.66)
const INK := Color(.025,.24,.23)
const TITLE_ROOM := Vector2(.150,.052)
static var _materials: Dictionary = {}

static func _material(key: String) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.resource_name = key
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		match key:
			"station_sign_brass": material.albedo_color = Color(.67,.47,.19)
			"station_sign_ivory": material.albedo_color = Color(.89,.87,.80)
			"station_sign_teal": material.albedo_color = Color(.025,.24,.23)
			_: material.albedo_color = Color.WHITE
		_materials[key] = material
	return _materials[key]

## Append the collision triangles of a box to `faces`.
static func add_solid_box(faces: PackedVector3Array, at: Transform3D, center: Vector3, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	for vertex: Vector3 in box.get_faces(): faces.append(at*(center+vertex))

## Add flat unshaded station lettering under `parent` and record its text in
## the parent's "station_signs" metadata.
static func add_lettering(parent: Node3D, at: Transform3D, text: String, pixel: float, color: Color) -> MeshInstance3D:
	var label := MeshInstance3D.new()
	label.name = "StationWayfinding"
	var letters := TextMesh.new()
	letters.font = TRANSIT_FONT
	letters.text = text
	letters.font_size = 32
	letters.pixel_size = pixel
	letters.depth = 0.0
	letters.curve_step = 2.0
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var material := StandardMaterial3D.new()
	material.resource_name = "station_lettering_"+color.to_html()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	letters.material = material
	label.mesh = letters
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.transform = at
	parent.add_child(label)
	var signs: Array = parent.get_meta("station_signs",[])
	label.set_meta("station_sign_index",signs.size())
	signs.append(text)
	parent.set_meta("station_signs",signs)
	return label

## A mounted board: brass backing plate behind a slightly smaller face. The
## face is a separate solid so lettering never shares a plane with the plate.
static func _board(parent: Node3D, at: Transform3D, size: Vector2, face_key: String, name := "MountedTransitSign") -> MeshInstance3D:
	var backing: MeshInstance3D
	for face: int in 2:
		var board := MeshInstance3D.new()
		board.name = name if face==0 else "TransitSignFace"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x-(.003 if face==1 else 0.0),size.y-(.003 if face==1 else 0.0),.003 if face==0 else .001)
		mesh.material = _material("station_sign_brass" if face==0 else face_key)
		board.mesh = mesh
		board.transform = at*Transform3D(Basis.IDENTITY,Vector3(0,0,-.0015 if face==0 else .0004))
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(board)
		if face==0: backing = board
	return backing

## Minor wayfinding is a shallow mounted plaque, with an opaque face and
## brass surround. The label remains editable until final material batching.
static func add_plaque(parent: Node3D, at: Transform3D, text: String, pixel := .00017, color := INK, max_size := Vector2(.145,.026)) -> MeshInstance3D:
	# BioRhyme has no arrow glyphs. Draw the directional mark on the plate
	# as geometry, keeping every rendered character in the requested font.
	var direction := -1 if text.contains("←") else 1 if text.contains("→") else 0
	var words := text.replace("←","").replace("→","").strip_edges()
	var label := add_lettering(parent,at*Transform3D(Basis.IDENTITY,Vector3(-direction*.006,0,.0015)),words,pixel,color)
	var bounds := label.mesh.get_aabb().size
	var margin := .024 if direction!=0 else .010
	var scale := minf(1.0,minf((max_size.x-margin)/maxf(bounds.x,.0001),(max_size.y-.006)/maxf(bounds.y,.0001)))
	label.scale=Vector3.ONE*scale
	var size := Vector2(clampf(bounds.x*scale+margin+.002,.030,max_size.x),clampf(bounds.y*scale+.009,.014,max_size.y))
	var backing := _board(parent,at,size,"station_sign_ivory")
	label.set_meta("sign_backing",weakref(backing))
	if direction!=0:
		var arrow := MeshInstance3D.new()
		arrow.name="TransitDirectionArrow"
		var d := float(direction)
		var tip := PackedVector3Array([Vector3(d*.004,0,0),Vector3(-d*.0015,-d*.003,0),Vector3(-d*.0015,d*.003,0)])
		arrow.mesh=CityGeometry3D.mesh_from_faces(tip,PackedColorArray([color,color,color]))
		arrow.material_override=label.mesh.material
		arrow.transform=at*Transform3D(Basis.IDENTITY,Vector3(d*(size.x*.5-.009),0,.0017))
		arrow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(arrow)
		var stem := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size=Vector3(.005,.0017,.0003)
		box.material=label.mesh.material
		stem.mesh=box
		stem.transform=arrow.transform*Transform3D(Basis.IDENTITY,Vector3(-d*.003,0,0))
		parent.add_child(stem)
	return label

## The station's name board: teal enamel in a brass surround with the route
## picker title in ivory BioRhyme. The title stays editable for renaming.
static func add_title_board(parent: Node3D, at: Transform3D, title: String) -> MeshInstance3D:
	_board(parent,at,TITLE_ROOM+Vector2(.010,.010),"station_sign_teal","StationNameBoard")
	var letters := add_lettering(parent,at*Transform3D(Basis.IDENTITY,Vector3(0,0,.0015)),"DESERT TRANSIT\n"+title,.00016,IVORY)
	letters.layers = FURNISHING_LAYER
	letters.set_meta("mutable_station_name",true)
	_fit_title(letters)
	return letters

static func _fit_title(label: MeshInstance3D) -> void:
	var size := label.mesh.get_aabb().size
	label.scale = Vector3.ONE*minf(TITLE_ROOM.x/maxf(size.x,.0001),TITLE_ROOM.y/maxf(size.y,.0001))

static func refresh_title(label: MeshInstance3D, title: String) -> void:
	label.mesh.text = "DESERT TRANSIT\n"+title
	_fit_title(label)
	var parent := label.get_parent()
	var signs: Array = parent.get_meta("station_signs",[])
	var index := int(label.get_meta("station_sign_index",-1))
	if index>=0 and index<signs.size(): signs[index] = label.mesh.text

## A brass DT roundel: ring, teal disc and the monogram, mounted flat on a
## wall or post. Local +Z faces the reader.
static func add_roundel(parent: Node3D, at: Transform3D, radius := .022) -> void:
	for layer: Array in [["station_sign_brass",radius,.003,-.0015],["station_sign_teal",radius-.003,.001,.0004]]:
		var disc := MeshInstance3D.new()
		disc.name = "TransitRoundel"
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(layer[1])
		mesh.bottom_radius = float(layer[1])
		mesh.height = float(layer[2])
		mesh.radial_segments = 32
		mesh.rings = 1
		mesh.material = _material(String(layer[0]))
		disc.mesh = mesh
		disc.transform = at*Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3(0,0,float(layer[3])))
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(disc)
	var monogram := add_lettering(parent,at*Transform3D(Basis.IDENTITY,Vector3(0,0,.0015)),"DT",.00055,IVORY)
	var size := monogram.mesh.get_aabb().size
	monogram.scale = Vector3.ONE*minf(1.0,(radius*1.3)/maxf(size.x,.0001))

## A brass-and-teal bench against a wall. `pose` is the station frame; the
## bench runs along local Z with its back toward +X when `side` is positive.
static func add_bench(world: Node3D, pose: Transform3D, center: Vector3, side: float, length: float, faces: PackedVector3Array) -> void:
	var start: int = world.shell_face_count()
	for z: float in [-length*.5+.012,length*.5-.012]:
		world.add_box(pose,center+Vector3(0,.012,z),Vector3(.030,.024,.006),ExploreTransitWorld3D.ShellFinish.BRASS,false)
	for offset: float in [-.010,0.0,.010]:
		world.add_box(pose,center+Vector3(offset,.0265,0),Vector3(.0085,.004,length),ExploreTransitWorld3D.ShellFinish.ENAMEL,false)
	world.add_box(pose,center+Vector3(side*.019,.044,0),Vector3(.004,.022,length),ExploreTransitWorld3D.ShellFinish.ENAMEL,false)
	ExploreTransitWorld3D.ShellFinish.finish_passage(world,pose,start)
	add_solid_box(faces,pose,center+Vector3(side*.004,.028,0),Vector3(.042,.056,length))

static func populate(parent: Node3D, station: Dictionary) -> Dictionary:
	var supports: Array[Dictionary] = []
	var faces := PackedVector3Array()
	var pose := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position)
	var side := float(station.side)
	var facing := Basis(Vector3.UP,-side*PI*.5)
	var title := String(station.get("name","Station"))
	var anchor: Vector2i = station.get("anchor",Vector2i(-1,-1))
	if bool(station.subway):
		# Furnishings keep to the long wall run beyond the lift shaft; the
		# doorway and the central boarding aperture stay clear.
		var wall := side*ExploreTransitWorld3D.PLATFORM_WALL_FACE
		var mount := wall-side*.0015
		var board := add_title_board(parent,pose*Transform3D(facing,Vector3(mount,.170,side*.255)),title)
		board.set_meta("station_name_anchor",anchor)
		add_roundel(parent,pose*Transform3D(facing,Vector3(mount,.185,side*.115)))
		add_bench(parent,pose,Vector3(wall-side*.021,.025,side*.375),side,.13,faces)
		# Boarding guidance and the lift direction sit on the wall in front of
		# the shaft, facing the boarding aperture: the platform wall beside an
		# ordinary lift, or the shaft's own wall where the lift is displaced.
		var lift := ExploreTransitWorld3D.Elevator.pose_for(station)
		var displaced := Vector3(station.get("access_position",station.position)).distance_to(station.position)>.001
		var face_x: float = ExploreTransitWorld3D.Elevator.SHAFT_WEST_FACE if displaced else ExploreTransitWorld3D.PLATFORM_WALL_FACE
		var shaft_face: Vector3 = lift*Vector3(face_x-.0015,0,-.07)
		var shaft_mount := Transform3D(pose.basis*facing,Vector3(shaft_face.x,station.position.y,shaft_face.z))
		add_plaque(parent,shaft_mount*Transform3D(Basis.IDENTITY,Vector3(0,.182,0)),"BOARD AT OPEN DOORS",.00023,INK,Vector2(.140,.016))
		var doorway: Vector3 = lift*Vector3(.415,.025,-.30)
		var toward_door := (doorway-shaft_face).dot(pose.basis*facing*Vector3.RIGHT)>0
		add_plaque(parent,shaft_mount*Transform3D(Basis.IDENTITY,Vector3(0,.155,0)),"ELEVATOR  →" if toward_door else "←  ELEVATOR",.00030,INK)
		# Warm ceiling fixtures over the platform, seated inside the soffit.
		var fixture_start: int = parent.shell_face_count()
		var high: float = parent.station_ceiling_rise(station)
		for z: float in [-.33,0.0,.33]:
			parent.add_box(pose,Vector3(side*.232,high+.2575,z),Vector3(.09,.003,.17),ExploreTransitWorld3D.ShellFinish.LIGHT,false)
		ExploreTransitWorld3D.ShellFinish.finish_passage(parent,pose,fixture_start)
	else:
		# Surface platform: a brass totem carries the name board, roundel and
		# boarding guidance at the platform end beyond the balustrade.
		var post := Vector3(side*.33,0,.40)
		var start: int = parent.shell_face_count()
		parent.add_box(pose,post+Vector3(0,.128,0),Vector3(.010,.206,.010),ExploreTransitWorld3D.ShellFinish.BRASS,false)
		parent.add_box(pose,post+Vector3(0,.027,0),Vector3(.030,.004,.030),ExploreTransitWorld3D.ShellFinish.BRASS,false)
		ExploreTransitWorld3D.ShellFinish.finish_passage(parent,pose,start)
		add_solid_box(faces,pose,post+Vector3(0,.128,0),Vector3(.012,.206,.012))
		var reader := Basis(Vector3.UP,PI)
		var board := add_title_board(parent,pose*Transform3D(reader,post+Vector3(0,.195,-.0065)),title)
		board.set_meta("station_name_anchor",anchor)
		add_roundel(parent,pose*Transform3D(reader,post+Vector3(0,.145,-.0065)),.018)
		add_plaque(parent,pose*Transform3D(reader,post+Vector3(0,.112,-.0065)),"BOARD AT OPEN DOORS",.00023,INK,Vector2(.120,.016))
		add_plaque(parent,pose*Transform3D(reader,post+Vector3(0,.088,-.0065)),"EXIT TO STREET  →" if side>0 else "←  EXIT TO STREET",.00023,INK,Vector2(.120,.016))
	return {"faces":faces,"supports":supports}

## One compiled furnishing mesh per prepared world, shared material groups.
## Static wayfinding becomes triangles; station titles keep their editable TextMesh.
static func finish_world(parent: Node3D) -> void:
	var groups := {}
	var originals: Array[Node] = []
	for child: Node in parent.get_children():
		if not child is MeshInstance3D or child.mesh == null or child.get_meta("mutable_station_name",false): continue
		originals.append(child)
		for index: int in child.mesh.get_surface_count():
			var material: Material = child.get_active_material(index)
			var key := material.resource_name if material!=null else "none"
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool":tool,"material":material}
			groups[key].tool.append_from(child.mesh,index,child.transform)
	if originals.is_empty(): return
	var mesh := ArrayMesh.new()
	for group: Dictionary in groups.values():
		group.tool.set_material(group.material)
		group.tool.commit(mesh)
	for child: Node in originals: child.free()
	var batch := MeshInstance3D.new()
	batch.name = "StationInteriorBatch"
	batch.mesh = mesh
	batch.layers = FURNISHING_LAYER
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(batch)
	# One fill for the whole prepared world; it affects only furnishing layer 20.
	var fill := DirectionalLight3D.new()
	fill.name = "StationInteriorFill"
	fill.light_cull_mask = FURNISHING_LAYER
	fill.shadow_enabled = false
	fill.light_color = Color(1.0,.92,.79)
	fill.light_energy = .62
	fill.rotation_degrees = Vector3(-48,-28,0)
	parent.add_child(fill)
	var triangles := 0
	for surface: int in mesh.get_surface_count():
		var count := mesh.surface_get_array_index_len(surface)
		triangles += (count if count > 0 else mesh.surface_get_array_len(surface))/3
	parent.set_meta("station_interior_stats",{"source_nodes":originals.size(),"draw_surfaces":mesh.get_surface_count(),"triangles":triangles})
