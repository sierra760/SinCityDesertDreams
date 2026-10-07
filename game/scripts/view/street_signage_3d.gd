# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name StreetSignage3D
extends Node3D

const Placement := preload("res://scripts/view/street_sign_placement_3d.gd")
const Lettering := preload("res://scripts/view/street_sign_text_3d.gd")
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
		var placed:=Placement.intersection(city,junction,faces)
		var key: String="junction:"+junction.key
		if not placed.ok:
			diagnostics.append({"key":key,"reason":placed.reason})
			continue
		desired[key]={"kind":"intersection","faces":faces,"placed":placed}
	var approaches: Dictionary={}
	for approach: Dictionary in _topology.exit_approaches():
		var ids:=_topology.exit_destination(approach,metadata.links)
		if ids.is_empty(): continue
		var texts: Array[String]=[]
		for id: int in ids: texts.append(metadata.streets[id])
		var key: String="exit:"+str(approach.highway)+":"+str(approach.direction)
		if approaches.has(key): continue
		approaches[key]=true
		var face: Dictionary=_contract.templates["highway-exit"]
		var placed:=Placement.exit(city,approach,face)
		if not placed.ok:
			diagnostics.append({"key":key,"reason":placed.reason})
			continue
		var direction:=Vector2(approach.direction)
		var right:=Vector2(-direction.y,direction.x)
		var arrow: String="→" if Vector2(approach.ramp-approach.highway).dot(right)>0 else "←"
		desired[key]={"kind":"exit","text":" & ".join(texts),"ids":ids,"direction":approach.direction,"arrow":arrow,"placed":placed}
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
	var bounds: AABB=record.placed.bounds
	assembly.set_meta("world_bounds",bounds)
	var low:=Vector2i(floori(bounds.position.x),floori(bounds.position.z))
	var high:=Vector2i(ceili(bounds.end.x),ceili(bounds.end.z))
	assembly.set_meta("batch_region",Rect2i(low,high-low))
	_sources.add_child(assembly)
	var art:=Node3D.new()
	art.scale=Vector3.ONE/16.0
	assembly.add_child(art)
	if record.kind=="intersection":
		art.add_child(_scene("street-post"))
		var texts: Array[String]=[]
		var ids: Array[int]=[]
		var directions: Array[Vector2i]=[]
		for i: int in record.faces.size():
			var face: Dictionary=record.faces[i]
			texts.append(face.text);ids.append(face.id);directions.append(face.direction)
			var blade:=_scene("street-blade")
			blade.position.y=2.45-i*.65
			blade.rotation.y=atan2(float(face.direction.y),float(face.direction.x))
			art.add_child(blade)
			_letter(blade,"street-blade",face.text)
		assembly.set_meta("display_texts",texts)
		assembly.set_meta("street_ids",ids)
		assembly.set_meta("blade_directions",directions)
	else:
		var board:=_scene("highway-exit")
		art.add_child(board)
		for node_name: String in record.placed.support.get("part_transforms",{}):
			(board.get_node(NodePath(node_name)) as Node3D).transform=record.placed.support.part_transforms[node_name]
		_letter(board,"highway-exit",record.text,record.arrow)
		assembly.set_meta("display_text",record.text)
		assembly.set_meta("street_ids",record.ids)
		assembly.set_meta("travel_direction",record.direction)
		assembly.set_meta("arrow",record.arrow)

static func _scene(id: String) -> Node3D:
	if not _scenes.has(id): _scenes[id]=load(BASE+id+".glb")
	return _scenes[id].instantiate()

func _letter(scene: Node3D, id: String, text: String, arrow: String = "") -> void:
	var face: Dictionary=_contract.templates[id].duplicate(true)
	face.font=_contract.font
	if id=="street-blade":
		face.maximum_board_scale[1]=1.0
		face.layout.destination_safe_m[1]=.36
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
