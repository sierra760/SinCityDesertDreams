# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name StreetSignage3D
extends Node3D

const Placement := preload("res://scripts/view/street_sign_placement_3d.gd")
const Lettering := preload("res://scripts/view/street_sign_text_3d.gd")
const Gantries := preload("res://scripts/view/highway_gantry_placement_3d.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
const BASE := "res://assets/street-name-signs/"
static var _scenes: Dictionary = {}
static var _contract: Dictionary = {}
var diagnostics: Array[Dictionary] = []
var _view: CityView3D
var _topology: StreetTopology
var _names: StreetNamingService
var _explore := false
var _labels := true
var _sources: Node3D
var _batches: Batcher
var _signature: Array = []
## Hidden aerial signage defers its rebuild until Explore shows it again.
var _deferred := false
## The junction list of the last refresh and what it was computed from: the
## topology, its projection snapshot and graph (both replaced whenever the
## topology reprojects, fully or incrementally), its revision and the link
## assignments. junctions() reads only those:
## nodes, links and bores are rebuilt with a new projection snapshot, and graph
## points come from tables and ground facets the graph caches on first use.
var _junction_inputs: Array = []
var _junction_list: Array[Dictionary] = []
## Tests may disable reuse to compare with a fresh junction list.
static var junction_reuse := true

func bind(view: CityView3D, topology: StreetTopology, names: StreetNamingService) -> void:
	if _names!=null and _names.changed.is_connected(_names_changed): _names.changed.disconnect(_names_changed)
	if is_instance_valid(_view) and _view.geometry_rebuilt.is_connected(_geometry_changed): _view.geometry_rebuilt.disconnect(_geometry_changed)
	_view=view;_topology=topology;_names=names
	if _names!=null: _names.changed.connect(_names_changed)
	if _view!=null: _view.geometry_rebuilt.connect(_geometry_changed)
	if _sources==null:
		_sources=Node3D.new()
		_sources.name="Assemblies"
		_sources.set_meta("batch_domain",&"street_signs")
		add_child(_sources)
		_batches=Batcher.new()
		_batches.name="StreetSignBatches"
		add_child(_batches)
	refresh()

func _names_changed(_revision: int, affected: Dictionary) -> void:
	refresh(affected)

func _geometry_changed(_revision: int) -> void:
	refresh()

func set_explore_active(on: bool) -> void:
	_explore=on
	visible=_explore and _labels
	if _explore and _deferred: refresh()

func set_labels_visible(on: bool) -> void:
	_labels=on
	visible=_explore and _labels

func clear() -> void:
	if _batches!=null: _batches.clear()
	if _sources!=null:
		for node: Node in _sources.get_children():
			_sources.remove_child(node)
			node.free()
	diagnostics.clear()
	_signature=[]
	_deferred=false
	_junction_inputs=[]
	_junction_list=[]

func refresh(_affected: Dictionary = {}) -> void:
	if _sources==null: return
	if not is_instance_valid(_view) or _view.city==null or _topology==null:
		clear()
		return
	if not _explore:
		# Signs are only drawn in Explore; entering it performs this refresh.
		_deferred=true
		return
	_deferred=false
	var city:=_view.city
	# Event-driven snapshots, never a process callback. Naming-only changes
	# retain all city/network/transit batches and all unchanged sign instances.
	var geometry: Array=[city.get_instance_id(),city.building.data.duplicate(),city.altitude.data.duplicate(),city.terrain.data.duplicate(),city.flags.data.duplicate(),city.underground.data.duplicate(),city.terrain_surface.vertices.duplicate() if city.terrain_surface is TerrainSurface else PackedByteArray()]
	var signature: Array=[geometry,city.street_naming.duplicate(true),_view.geometry_revision()]
	if signature==_signature: return
	if not _topology.is_bound_to(city):
		clear()
		return
	if _signature.is_empty() or geometry!=_signature[0]: _topology.rebuild(city)
	if _contract.is_empty(): _contract=JSON.parse_string(FileAccess.get_file_as_string(BASE+"templates.json"))
	var desired: Dictionary={}
	diagnostics.clear()
	var metadata: Dictionary=city.street_naming
	# Rendered support is read only by junctions whose ground corners all fail.
	var support_state: Dictionary={}
	for junction: Dictionary in _junctions(metadata.links):
		var faces: Array[Dictionary]=[]
		var seen: Dictionary={}
		for approach: Dictionary in junction.approaches:
			var id:=int(approach.street_id)
			if id==0 or seen.has(id) or not metadata.streets.has(id): continue
			seen[id]=true
			faces.append({"id":id,"text":metadata.streets[id],"direction":approach.direction})
		if faces.is_empty(): continue
		junction["rendered_support_source"]=_lazy_support.bind(junction.position,support_state)
		var placed:=Placement.intersection(city,junction,faces,_topology.traffic_graph())
		var key: String="junction:"+junction.key
		if not placed.ok:
			diagnostics.append({"key":key,"reason":placed.reason})
			continue
		desired[key]={"kind":"intersection","faces":faces,"placed":placed}
	# Exit and distance gantries stand on the highway's own carriageway tiles.
	var exits: Array[Dictionary]=[]
	for approach: Dictionary in _topology.exit_approaches():
		var ids:=_topology.exit_destination(approach,metadata.links)
		var texts: Array[String]=[]
		for id: int in ids: texts.append(metadata.streets[id])
		approach["ids"]=ids
		approach["text"]=" & ".join(texts)
		exits.append(approach)
	var gantries: Dictionary=Gantries.plan(city,_topology.traffic_graph(),exits)
	diagnostics.append_array(gantries.diagnostics)
	for key: String in gantries.gantries: desired[key]=gantries.gantries[key]
	var retained: Dictionary={}
	var changed:=false
	for child: Node in _sources.get_children():
		var key: String=child.get_meta("sign_key")
		if desired.has(key) and child.get_meta("record")==desired[key]: retained[key]=true
		else:
			_sources.remove_child(child)
			child.free()
			changed=true
	for key: String in desired:
		if not retained.has(key):
			_make(key,desired[key])
			changed=true
	_signature=signature
	# Identical assemblies produce identical batches; keep the uploaded ones.
	if not changed and (_batches.get_child_count()>0 or _sources.get_child_count()==0): return
	_batches.clear()
	# Temporarily expose sources for the batcher's visibility filter; final
	# Explore/preference visibility is restored without rebuilding buffers.
	visible=true
	_batches.rebuild([_sources],32)
	visible=_explore and _labels

## Shallow copies of the current junction records; refresh() annotates them.
func _junctions(links: Dictionary) -> Array[Dictionary]:
	var inputs: Array = [_topology] + _topology.junction_sources()
	if not junction_reuse or _junction_inputs.size() != 5 or not is_same(_junction_inputs[0], inputs[0]) or not is_same(_junction_inputs[1], inputs[1]) \
			or not is_same(_junction_inputs[2], inputs[2]) or _junction_inputs[3] != inputs[3] or _junction_inputs[4] != links:
		_junction_list = _topology.junctions(links)
		inputs.append(links.duplicate(true))
		_junction_inputs = inputs
	var result: Array[Dictionary] = []
	for junction: Dictionary in _junction_list: result.append(junction.duplicate())
	return result

func _make(key: String, record: Dictionary) -> void:
	var assembly:=Node3D.new()
	assembly.name="StreetSign"
	assembly.transform=record.placed.transform
	assembly.set_meta("sign_key",key)
	assembly.set_meta("sign_kind",record.kind)
	assembly.set_meta("record",record.duplicate(true))
	assembly.set_meta("support",record.placed.support.duplicate(true))
	var art:=Node3D.new()
	art.scale=Vector3.ONE/16.0
	assembly.add_child(art)
	if record.kind=="intersection":
		var post:=_scene("street-post")
		for node: Node in post.find_children("*","MeshInstance3D",true,false):
			var part:=node as MeshInstance3D
			part.transform=Placement.fitted_post_part(String(part.name),part.transform,part.mesh.get_aabb(),record.faces.size())
		art.add_child(post)
		var texts: Array[String]=[]
		var ids: Array[int]=[]
		var directions: Array[Vector2i]=[]
		for i: int in record.faces.size():
			var face: Dictionary=record.faces[i]
			texts.append(face.text);ids.append(face.id);directions.append(face.direction)
			var blade:=_scene("street-blade")
			var corner: Array=record.placed.support.get("blades",[])
			var shift: Vector2=corner[i].shift if i<corner.size() else Vector2.ZERO
			blade.position=Vector3(shift.x*16.0,Placement.BLADE_TOP_CENTRE_M-i*Placement.BLADE_PITCH_M,shift.y*16.0)
			blade.rotation.y=atan2(float(face.direction.y),float(face.direction.x))
			art.add_child(blade)
			_letter(blade,"street-blade",face.text,"",corner[i].scale_x if i<corner.size() else -1.0)
		assembly.set_meta("display_texts",texts)
		assembly.set_meta("street_ids",ids)
		assembly.set_meta("blade_directions",directions)
	else:
		_make_gantry(art,record)
		assembly.set_meta("structure","gantry")
		assembly.set_meta("street_ids",record.ids)
		assembly.set_meta("travel_direction",record.direction)
		if record.kind=="exit":
			assembly.set_meta("display_text",record.text)
			assembly.set_meta("arrow",record.arrow)
		else:
			assembly.set_meta("display_rows",record.rows.duplicate(true))
	# Intersections carry their checked envelope; gantries measure their parts.
	var bounds: AABB=record.placed.bounds if record.kind=="intersection" else _measured_bounds(assembly)
	assembly.set_meta("world_bounds",bounds)
	var low:=Vector2i(floori(bounds.position.x),floori(bounds.position.z))
	var high:=Vector2i(ceili(bounds.end.x),ceili(bounds.end.z))
	assembly.set_meta("batch_region",Rect2i(low,high-low))
	_sources.add_child(assembly)

## Rigid truss above the lanes; each post stretches down to its own shoulder.
func _make_gantry(art: Node3D, record: Dictionary) -> void:
	var template: Dictionary=Gantries.contract().templates["highway-gantry"]
	var gantry:=_scene("highway-gantry")
	art.add_child(gantry)
	var feet: Dictionary=record.placed.support.feet_m
	for side: String in ["L","R"]:
		var floor_m: float=float(feet[side])
		var post:=gantry.find_child("GantryPost"+side,true,false) as MeshInstance3D
		var box:=post.mesh.get_aabb()
		var top: float=(post.transform*box).end.y
		var local:=post.transform
		local.basis=Basis.from_scale(Vector3(1,(top-floor_m)/box.size.y,1))
		local.origin.y=floor_m-box.position.y*local.basis.y.y
		post.transform=local
		var shoe:=gantry.find_child("GantryShoe"+side,true,false) as MeshInstance3D
		shoe.position.y=floor_m-shoe.mesh.get_aabb().position.y
	var mount: Array=template.board_top_m
	if record.kind=="exit":
		var board:=_scene("highway-exit")
		for node: Node in board.get_children():
			if String(node.name).begins_with("Shoulder"):
				board.remove_child(node)
				node.free()
		_letter(board,"highway-exit",record.text,record.arrow)
		var face: Dictionary=_contract.templates["highway-exit"]
		var top_m: float=float(face.board_pivot_m[1])+float(face.base_board_size_m[1])*.5*float(face.maximum_board_scale[1])
		var half_width: float=float(face.base_board_size_m[0])*.5*float(face.maximum_board_scale[0])
		# Over the lanes on the exit side, inside the truss.
		board.position=Vector3(float(record.side)*(half_width+.52),float(mount[1])-top_m,float(mount[2]))
		art.add_child(board)
	else:
		var board:=_scene("gantry-distance")
		var face: Dictionary=Gantries.contract().templates["gantry-distance"]
		var rows: Array=record.rows
		var inset: float=face.row_top_inset_m
		var pitch: float=face.row_pitch_m
		var scale_y: float=(2*inset+pitch*rows.size())/float(face.base_board_size_m[1])
		var body:=board.find_child("Board",true,false) as Node3D
		body.transform=Transform3D(Basis.from_scale(Vector3(1,scale_y,1)),Vector3.ZERO)
		for i: int in range(1,int(face.rows)):
			var rule:=board.find_child("RowRule%d"%i,true,false) as Node3D
			if rule==null: continue
			if i>=rows.size():
				rule.get_parent().remove_child(rule)
				rule.free()
				continue
			# Rules keep their unscaled position and thickness between rows.
			var at:=rule.position
			rule.transform=Transform3D(Basis.from_scale(Vector3(1,1/scale_y,1)),Vector3(at.x,-(inset+pitch*i)/scale_y,at.z))
		var front: float=(board.find_child("TextMountFront",true,false) as Node3D).position.z
		var layout: Dictionary=face.layout
		var name_safe: Array=layout.name_safe_m
		var distance_safe: Array=layout.distance_safe_m
		var name_left: float=float(layout.name_left_m)
		var distance_right: float=float(layout.distance_right_m)
		var fitted: Array[Dictionary]=[]
		var common:=INF
		for i: int in rows.size():
			for column: int in 2:
				var safe: Array=name_safe if column==0 else distance_safe
				var center: float=name_left+float(safe[0])*.5 if column==0 else distance_right-float(safe[0])*.5
				var fit:=Lettering.layout(String(rows[i][column]),_row_face(safe,center,float(layout.name_em_m if column==0 else layout.distance_em_m),"left" if column==0 else "right"))
				fitted.append({"row":i,"column":column,"layout":fit})
				common=minf(common,(fit.meshes[0].transform as Transform3D).basis.x.x)
		# One letter height for the whole board, as on a real guide sign: every
		# row shrinks to the tightest fit, keeping its column's alignment edge.
		for entry: Dictionary in fitted:
			var row_mount:=Transform3D(Basis.IDENTITY,Vector3(0,-(inset+pitch*(int(entry.row)+.5)),front))
			var edge: float=name_left+float(name_safe[0])*.02 if entry.column==0 else distance_right-float(distance_safe[0])*.02
			_add_text(board,row_mount,_rescaled(entry.layout,common,edge,entry.column==0))
		board.position=Vector3(0,float(mount[1]),float(mount[2]))
		art.add_child(board)

## A single-line layout redrawn at `scale`, its left (or right) glyph edge at
## `edge` and its glyph box centred on the row.
static func _rescaled(layout: Dictionary, scale: float, edge: float, left: bool) -> Dictionary:
	var record: Dictionary=layout.meshes[0]
	var box: AABB=(record.mesh as Mesh).get_aabb()
	var x: float=edge-box.position.x*scale if left else edge-box.end.x*scale
	var transform:=Transform3D(Basis.from_scale(Vector3(scale,scale,1)),Vector3(x,-box.get_center().y*scale,-box.get_center().z))
	return {"meshes":[{"mesh":record.mesh,"transform":transform,"text":record.text}]}

func _row_face(safe: Array, center_x: float, em: float, align: String) -> Dictionary:
	return {"font":_contract.font,"layout":{"destination_safe_m":safe.duplicate(),"destination_center_m":[center_x,0.0],"destination_em_m":em,
		"line_gap_m":.04,"max_destination_lines":1,"align":align}}

## Complete envelope of every emitted mesh, in the assembly's parent space.
static func _measured_bounds(assembly: Node3D) -> AABB:
	var result:=AABB()
	var begun:=false
	for node: Node in assembly.find_children("*","MeshInstance3D",true,false):
		var mesh_node:=node as MeshInstance3D
		var transform:=Transform3D.IDENTITY
		var at: Node=mesh_node
		while at!=assembly:
			transform=(at as Node3D).transform*transform
			at=at.get_parent()
		var box: AABB=assembly.transform*transform*mesh_node.mesh.get_aabb()
		result=result.merge(box) if begun else box
		begun=true
	return result.grow(.002/16.0)

static func _scene(id: String) -> Node3D:
	if not _scenes.has(id): _scenes[id]=load(BASE+id+".glb")
	return _scenes[id].instantiate()

func _letter(scene: Node3D, id: String, text: String, arrow: String = "", scale_x: float = -1.0) -> void:
	var face: Dictionary=_contract.templates[id].duplicate(true)
	face.font=_contract.font
	if id=="street-blade":
		face.maximum_board_scale[1]=1.0
		face.layout.destination_safe_m[1]=.36
		if scale_x>0:
			# Corner blades are sized to their verge; keep the authored border inset.
			face.maximum_board_scale[0]=scale_x
			face.layout.destination_safe_m[0]=float(face.base_board_size_m[0])*scale_x-.34
	var scale_m:=Vector3(face.maximum_board_scale[0],face.maximum_board_scale[1],face.maximum_board_scale[2])
	var pivot:=Vector3(face.board_pivot_m[0],face.board_pivot_m[1],face.board_pivot_m[2])
	var board:=scene.get_node(NodePath(face.board_node)) as Node3D
	board.transform=Transform3D(Basis.from_scale(scale_m),pivot-pivot*scale_m)
	var layout:=Lettering.layout(text,face)
	for side: String in face.operational_faces:
		var mount:=scene.get_node(NodePath(face.mounts[side])) as Node3D
		# Mount position follows expanded board, glyph size is independently fit.
		var mount_transform: Transform3D=board.transform*mount.transform
		mount_transform.basis=mount_transform.basis.orthonormalized()
		_add_text(scene,mount_transform,layout)
		if id=="highway-exit":
			for kind: String in ["header","arrow"]:
				var label_face:=face.duplicate(true)
				label_face.layout.destination_safe_m=face.layout[kind+"_safe_m"]
				label_face.layout.destination_center_m=face.layout[kind+"_center_m"]
				label_face.layout.destination_em_m=face.layout[kind+"_em_m"]
				_add_text(scene,mount_transform,Lettering.layout("EXIT" if kind=="header" else arrow,label_face))

static func _add_text(parent: Node3D, mount: Transform3D, layout: Dictionary) -> void:
	for record: Dictionary in layout.meshes:
		var instance:=MeshInstance3D.new()
		instance.mesh=record.mesh
		instance.transform=mount*record.transform
		# The raised legend lies inside its board's silhouette, so the board
		# already casts its shadow. Lettering is about 16 million triangles
		# city-wide; drawing it into every shadow cascade cost several ms.
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_meta("complete_text",record.text)
		parent.add_child(instance)

## Current emitted support for one junction, or {} while the rendered geometry
## lags the City. The currency check runs once per refresh, on first use.
func _lazy_support(position: Vector3, state: Dictionary) -> Dictionary:
	if not state.has("current"):
		state["current"]=is_instance_valid(_view.networks) and _view.is_geometry_current()
	return _rendered_support(position) if state.current else {}

## Detached, bounded reads of already emitted geometry. An early naming signal
## cannot publish old surfaces; the subsequent geometry revision refreshes again.
func _rendered_support(position: Vector3) -> Dictionary:
	var cell:=Vector2i(floori(position.x),floori(position.z))
	var region:=Rect2i(cell-Vector2i(2,2),Vector2i(5,5))
	var parts: Array[CityNetworks3D]=[]
	if _view.networks._regions.is_empty(): parts.append(_view.networks)
	else:
		for part: CityNetworks3D in _view.networks._regions.values():
			if region.intersects(part.get_meta("batch_region")): parts.append(part)
	var patches: Array[Dictionary]=[]
	var boxes: Array[Dictionary]=[]
	var obstacles:=PackedVector3Array()
	for part: CityNetworks3D in parts:
		patches.append_array(part.physical_patches_in(region))
		for box: Dictionary in part._physical_boxes:
			var bounds: AABB=box.transform*AABB(-Vector3(box.size)*.5,box.size)
			if Rect2(region).intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))): boxes.append(box.duplicate(true))
		for i: int in range(0,part._physical_obstacles.size(),3):
			var bounds:=AABB(part._physical_obstacles[i],Vector3.ZERO).expand(part._physical_obstacles[i+1]).expand(part._physical_obstacles[i+2])
			if Rect2(region).intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))): obstacles.append_array(part._physical_obstacles.slice(i,i+3))
	return {"patches":patches,"boxes":boxes,"obstacles":obstacles,"geometry_revision":_view.geometry_revision()}
