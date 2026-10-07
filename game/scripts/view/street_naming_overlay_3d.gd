# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Separate naming feedback. Never writes city surfaces, collision or Builder previews.
class_name StreetNamingOverlay3D
extends Node3D
var _view: CityView3D
var _topology: StreetTopology
var _service: StreetNamingService
var _segments: Array[Dictionary] = []
var _junctions: Array[Dictionary] = []
var _selected: Array[String] = []
var _hovered: Array[String] = []
var _content_signature := 0
var _layer_ready := false
var _link_visuals: Dictionary = {}
static var _materials: Dictionary = {}
var _segment_labels: Dictionary = {}
var _selected_set: Dictionary = {}
var _hovered_set: Dictionary = {}

func bind(view: CityView3D, topology: StreetTopology, service: StreetNamingService) -> void:
	_view = view
	_topology = topology
	_service = service
	refresh()

func refresh() -> void:
	if _view == null or _view.city == null or _topology == null: return
	_segments = _topology.segments(_view.city.street_naming.links)
	_junctions = _topology.junctions(_view.city.street_naming.links)
	var signature := hash([_segments,_view.city.street_naming.streets])
	if signature != _content_signature:
		clear()
		_content_signature = signature
	if visible: show_selection(_selected,_hovered)

func pick_segment(point: Vector2) -> Dictionary:
	if _view == null or _view.city == null: return {"error":"No city is open."}
	# An isolated tile must not borrow a nearby segment within the pick halo.
	var cell := _view.pick_cell(point,1)
	if cell.x >= 0 and NetworkShapes.in_road_family(_view.city.building.atv(cell)):
		var connected := false
		for segment: Dictionary in _segments:
			for key: String in segment.links:
				if key.begins_with("%d,%d," % [cell.x,cell.y]) or key.contains(">%d,%d," % [cell.x,cell.y]): connected = true; break
			if connected: break
		if not connected and not NetworkShapes.is_onramp(_view.city.building.atv(cell)):
			return {"error":"Connect this road before naming a segment."}
	for junction: Dictionary in _junctions:
		var center := _view.project_world(junction.position)
		var radius := minf(8,maxf(3,center.distance_to(_view.project_world(junction.position+Vector3(.15,0,0)))))
		if point.distance_to(center) <= radius:
			var choices: Array[Dictionary] = []
			for approach: Dictionary in junction.approaches:
				var keys: Array = approach.links.duplicate()
				keys.sort()
				var id := String(keys[0])
				var direction: Vector2i = approach.direction
				var title: String = {Vector2i.UP:"North",Vector2i.RIGHT:"East",Vector2i.DOWN:"South",Vector2i.LEFT:"West"}.get(direction,"Road")
				var named: String = _view.city.street_naming.streets.get(approach.street_id,"Unnamed")
				choices.append({"id":id,"label":title+" · "+named,"links":approach.links})
			return {"branches":choices}
	var best: Dictionary = {}
	var distance := INF
	for segment: Dictionary in _segments:
		var points: PackedVector3Array = segment.points
		for i: int in range(1,points.size()):
			var a := _view.project_world(points[i-1])
			var b := _view.project_world(points[i])
			var nearest := Geometry2D.get_closest_point_to_segment(point,a,b)
			var value := point.distance_to(nearest)
			var radius := clampf(a.distance_to(_view.project_world(points[i-1]+Vector3(.3,0,0))),6,18)
			if value <= radius and value < distance: best = segment; distance = value
	return {"segment":best} if not best.is_empty() else {"error":"Select an ordinary road segment."}

func segment_by_id(id: String) -> Dictionary:
	for segment: Dictionary in _segments:
		if segment.id == id: return segment
	return {}

## Pointer changes only update retained materials/visibility on affected links.
## Geometry and labels rebuild only when topology or published names change.
func show_selection(keys: Array[String], hovered: Array[String]) -> void:
	if not _layer_ready: _build_layer()
	var next_selected: Dictionary = {}
	var next_hovered: Dictionary = {}
	for key: String in keys: next_selected[key] = true
	for key: String in hovered: next_hovered[key] = true
	var changed: Dictionary = {}
	for key: String in _selected_set:
		if not next_selected.has(key): changed[key] = true
	for key: String in next_selected:
		if not _selected_set.has(key): changed[key] = true
	for key: String in _hovered_set:
		if not next_hovered.has(key): changed[key] = true
	for key: String in next_hovered:
		if not _hovered_set.has(key): changed[key] = true
	var changed_labels: Dictionary = {}
	for key: String in changed:
		if not _link_visuals.has(key): continue
		var record: Dictionary = _link_visuals[key]
		var selected := next_selected.has(key)
		if _selected_set.has(key) != selected: changed_labels[record.segment] = true
		record.outline.visible = selected
		record.base.visible = not selected
		record.selection.visible = selected
		var base: ImmediateMesh = record.base.mesh
		if base.get_surface_count() > 0:
			base.surface_set_material(0,_material(Color("dcaf61") if next_hovered.has(key) else Color("cfcab7"),121))
	for id: String in changed_labels:
		var record: Dictionary = _segment_labels[id]
		var chosen := false
		for key: String in record.links:
			if next_selected.has(key): chosen = true; break
		record.node.text = ("✓ " if chosen else "")+String(record.display_name)
	_selected = keys.duplicate()
	_hovered = hovered.duplicate()
	_selected_set = next_selected
	_hovered_set = next_hovered

func _build_layer() -> void:
	clear()
	for segment: Dictionary in _segments:
		for key: String in segment.links:
			var points := _topology.connection_points(key)
			var dashed := key.contains("bore")
			var base := _stroke(points,Color("cfcab7"),.045,dashed,121)
			var outline := _stroke(points,Color("173c3a"),.13,dashed,120)
			var selection := _stroke(points,Color("38cbb5"),.075,dashed,121)
			outline.hide()
			selection.hide()
			_link_visuals[key] = {"base":base,"outline":outline,"selection":selection,"segment":segment.id}
		var id := int(_view.city.street_naming.links.get(segment.links[0],0))
		var label := Label3D.new()
		var display_name := String(_view.city.street_naming.streets.get(id,"Unnamed"))
		label.text = display_name
		label.font = UITheme.DISPLAY_FONT
		label.font_size = 32
		label.outline_size = 8
		label.modulate = Color("fcf2d7")
		label.outline_modulate = Color("173c3a")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = .0007
		label.position = segment.points[segment.points.size()/2]+Vector3.UP*.2
		add_child(label)
		_segment_labels[segment.id] = {"node":label,"display_name":display_name,"links":segment.links}
	_layer_ready = true

## One immutable material per stroke color/priority; hover swaps materials.
static func _material(color: Color, priority: int) -> StandardMaterial3D:
	var key := [color,priority]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = priority
		_materials[key] = material
	return _materials[key]

func _stroke(points: PackedVector3Array,color: Color,width: float,dashed: bool,priority: int) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	# A surface needs vertices; a one-point link keeps an empty mesh.
	if points.size() >= 2:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,_material(color,priority))
		for i: int in range(1,points.size()):
			if dashed and i%2 == 0: continue
			var a := points[i-1]+Vector3.UP*.08
			var b := points[i]+Vector3.UP*.08
			var side := (b-a).cross(Vector3.UP).normalized()*width*.5
			for vertex: Vector3 in [a-side,a+side,b+side,a-side,b+side,b-side]: mesh.surface_add_vertex(vertex)
		mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func clear() -> void:
	_layer_ready = false
	_link_visuals.clear()
	_segment_labels.clear()
	_selected_set.clear()
	_hovered_set.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
