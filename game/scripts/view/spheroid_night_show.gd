# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Seasonal whole-cell patterns on the Spheroid's actual glass and bronze ribs. Copies
## stay outside the batcher's source hierarchy; authored meshes/materials and
## compiled caches remain untouched. No city state, save data or game RNG.
extends Node3D

const SCREEN := preload("res://shaders/spheroid_screen.gdshader")
const RIBS := preload("res://shaders/spheroid_ribs.gdshader")
## Conventional seasonal colours, January through December. Each cell slowly
## alternates among the three colours, in regular ascending horizontal bands.
const PALETTES := [
	[Color("457d9cff"),Color("9fbccfff"),Color("e6ebebff")], # January: winter ice and silver.
	[Color("a93652ff"),Color("cf8293ff"),Color("ead9caff")], # February: rose and ivory.
	[Color("23704dff"),Color("66a277ff"),Color("c9aa55ff")], # March: emerald and gold.
	[Color("b5a1c9ff"),Color("a4c5b0ff"),Color("e4d5a4ff")], # April: spring pastels.
	[Color("6e9b75ff"),Color("c993a0ff"),Color("e7dcc0ff")], # May: fresh leaves and blossoms.
	[Color("d3a654ff"),Color("559eaaff"),Color("eadfbcff")], # June: sun, water and sand.
	[Color("ad3943ff"),Color("355a8aff"),Color("e6dfd1ff")], # July: red, white and blue.
	[Color("bc7850ff"),Color("577c95ff"),Color("dab965ff")], # August: late-summer warmth.
	[Color("b97842ff"),Color("566c47ff"),Color("c9a65bff")], # September: autumn leaves.
	[Color("cc752aff"),Color("211d32ff"),Color("775099ff")], # October: pumpkin, midnight and violet.
	[Color("a65c3dff"),Color("ba944cff"),Color("d9c8a3ff")], # November: harvest copper and wheat.
	[Color("ae3b42ff"),Color("24684dff"),Color("dfd5bbff")], # December: red, evergreen and ivory.
]
## Eight millimetres, enough to separate the screen from its authored facets.
const LIFT := .0005
## Model import quantization can move equivalent face centres by millimetres.
## Merge centres within 1.6 cm into the same horizontal cell-grid level.
const ROW_TOLERANCE := .001

var _view: Node
var _calendar := GameClock.new()
var _month := 0
var _screens: Array[ShaderMaterial] = []
var _calendar_queued := false

func bind(view: Node) -> void:
	_view = view
	if "buildings" in view and view.buildings != null:
		view.buildings.visibility_changed.connect(_sync_visibility)
	_sync_visibility()
	set_process(false)

func _sync_visibility() -> void:
	visible = _view != null and "buildings" in _view and _view.buildings != null and _view.buildings.visible
	if visible:
		_sync_month()
		sync_exploration()

## Camera handoffs update one uniform, never a timer or per-frame callback.
func sync_exploration() -> void:
	var exploring := _view != null and _view.has_method("exploration_camera") and is_instance_valid(_view.exploration_camera())
	for material: ShaderMaterial in _screens:
		material.set_shader_parameter("explore_steps",exploring)

func rebuild() -> void:
	clear()
	if _view == null or not ("buildings" in _view) or _view.buildings == null: return
	for lot: Node in _view.buildings.get_children():
		if lot is Node3D and int(lot.get_meta("code",-1)) == Buildings.NEON_DOME:
			_add_lot(lot)
	_sync_visibility()

func clear() -> void:
	for child: Node in get_children(): child.free()
	_screens.clear()
	_month = 0
	set_process(false)

## The city's existing daily/analytics refresh calls this, coalesced once per
## batch. Defer the read because day_advanced is emitted before clock.advance.
## No per-frame processing, geometry rebuild or texture upload is needed.
func queue_calendar_sync() -> void:
	if _calendar_queued or not visible or _screens.is_empty(): return
	_calendar_queued = true
	call_deferred("_sync_month")

## Read the simulation's calendar only. A paused city keeps its month, while
## loading/rebinding a different city and returning from an overlay catch up.
func _sync_month() -> void:
	_calendar_queued = false
	_calendar.day = maxi(_view.city.day,0) if _view != null and "city" in _view and _view.city != null else 0
	var month := _calendar.month()
	if month == _month: return
	_month = month
	var palette: Array = PALETTES[month-1]
	for material: ShaderMaterial in _screens:
		material.set_shader_parameter("palette_a",palette[0])
		material.set_shader_parameter("palette_b",palette[1])
		material.set_shader_parameter("palette_c",palette[2])

func _add_lot(lot: Node3D) -> void:
	var glass := PackedVector3Array()
	var ribs := PackedVector3Array()
	var inverse := lot.global_transform.affine_inverse()
	for child: Node in lot.find_children("*","MeshInstance3D",true,false):
		var source := child as MeshInstance3D
		# Consolidated shadow proxies contain duplicate bronze faces.
		if source.mesh == null or source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		var local := inverse*source.global_transform
		for surface: int in source.mesh.get_surface_count():
			var material := source.get_active_material(surface)
			if material == null: continue
			var name := material.resource_name.get_slice(" • ",0).get_slice(".",0)
			if name not in ["dome_glass","dome_glass_light","copper","copper_light"]: continue
			var arrays := source.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for i: int in vertices.size(): indices[i]=i
			var out := glass if name.begins_with("dome_glass") else ribs
			for i: int in range(0,indices.size(),3):
				var a := local*vertices[indices[i]]
				var b := local*vertices[indices[i+1]]
				var c := local*vertices[indices[i+2]]
				var normal := (c-a).cross(b-a).normalized()
				for point: Vector3 in [a,b,c]: out.append(point+normal*LIFT)
	if glass.is_empty() or ribs.is_empty(): return
	var wrapper := Node3D.new()
	wrapper.name = "Spheroid"
	add_child(wrapper)
	wrapper.global_transform = lot.global_transform
	var channels := PackedColorArray()
	var lower := INF
	var upper := -INF
	for point: Vector3 in glass:
		lower=minf(lower,point.y)
		upper=maxf(upper,point.y)
	var centers := PackedVector3Array()
	var heights: Array[float]=[]
	for i: int in range(0,glass.size(),3):
		var center := (glass[i]+glass[i+1]+glass[i+2])/3.0
		centers.append(center)
		heights.append(center.y)
	heights.sort()
	var levels: Array[float]=[]
	for height: float in heights:
		if levels.is_empty() or height-levels[-1]>ROW_TOLERANCE: levels.append(height)
	# An authored facet is one cell. Repeat its phase at all three corners
	# so interpolation can never paint a gradient or picture inside a cell.
	for center: Vector3 in centers:
		var phase := clampf((center.y-lower)/maxf(upper-lower,.001),0.0,1.0)
		var row := levels.bsearch(center.y-ROW_TOLERANCE)
		for corner: int in 3: channels.append(Color(phase,float(row)/255.0,0))
	var display := _mesh("Display",glass,SCREEN,wrapper,channels)
	var screen_material := display.mesh.surface_get_material(0) as ShaderMaterial
	_screens.append(screen_material)
	_mesh("Ribs",ribs,RIBS,wrapper)

func _mesh(label: String, vertices: PackedVector3Array, shader: Shader, parent: Node3D, channels := PackedColorArray()) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	if not channels.is_empty(): arrays[Mesh.ARRAY_COLOR]=channels
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader=shader
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name=label
	instance.mesh=mesh
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(instance)
	return instance
