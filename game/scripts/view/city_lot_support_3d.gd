# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Fill only the authored ground-contact footprint above falling terrain.
## Rigid architecture keeps its authored transform; floating marine structures stay open.
## Prepared Explore stations hide this complete shell, including its support.
extends RefCounted
static var _bases: Dictionary = {}
static var _material: Material

static func add_to(model: Node3D, city: City, code: int, source_key: String) -> void:
	if code in [Buildings.MARINA,Buildings.PIER]: return
	# Ordinary level lots need no mesh scan, allocation or extra draw surface.
	var size := Buildings.size(code)
	var start := Vector2i(roundi(model.position.x-size.x*.5),roundi(model.position.z-size.y*.5))
	var needs_support := false
	for y: int in range(start.y,start.y+size.y):
		for x: int in range(start.x,start.x+size.x):
			if not city.in_bounds(x,y) or city.is_water(x,y): continue
			for point: Vector3 in CityGeometry3D.ground_corners(city,Vector2i(x,y)):
				if point.y<model.position.y-.0001: needs_support=true
	if not needs_support: return
	if not _bases.has(source_key):
		var base := PackedVector3Array()
		for child: Node in model.get_children(): _collect(child,Transform3D.IDENTITY,base)
		_bases[source_key]=base
	var base: PackedVector3Array = _bases[source_key]
	if base.is_empty(): return
	var faces := PackedVector3Array()
	var inverse := model.transform.affine_inverse()
	for index: int in range(0,base.size(),3):
		var polygon: Array[Vector2] = []
		for j: int in 3:
			var world := model.transform*base[index+j]
			polygon.append(Vector2(world.x,world.z))
		var bounds := Rect2(polygon[0],Vector2.ZERO)
		for p: Vector2 in polygon: bounds=bounds.expand(p)
		for y: int in range(maxi(0,floori(bounds.position.y)),mini(City.HEIGHT,ceili(bounds.end.y))):
			for x: int in range(maxi(0,floori(bounds.position.x)),mini(City.WIDTH,ceili(bounds.end.x))):
				var cell := Vector2i(x,y)
				if city.is_water(x,y): continue
				var local: Array[Vector2] = []
				for p: Vector2 in polygon: local.append(p-Vector2(cell))
				for axis: int in 2:
					local=CityNetworks3D.clip_axis(local,axis,0,true)
					local=CityNetworks3D.clip_axis(local,axis,1,false)
				var diagonal := CityGeometry3D.uses_nw_se_diagonal(CityGeometry3D.ground_corners(city,cell))
				for positive: bool in [false,true]:
					var clipped := CityNetworks3D._clip_facet(local,diagonal,positive)
					clipped=_below_base(clipped,city,cell,model.position.y)
					if clipped.size()<3: continue
					var top: Array[Vector3] = [];var bottom: Array[Vector3] = []
					for p: Vector2 in clipped:
						var ground := CityGeometry3D.point_on_ground(city,cell,p)
						top.append(inverse*Vector3(ground.x,model.position.y,ground.z))
						bottom.append(inverse*(ground-Vector3.UP*.002))
					for j: int in range(1,top.size()-1):
						_triangle(faces,top[0],top[j],top[j+1],true)
					for j: int in top.size():
						var k := (j+1)%top.size()
						_triangle(faces,top[j],top[k],bottom[j])
						_triangle(faces,top[k],bottom[k],bottom[j])
	if faces.is_empty(): return
	var colors := PackedColorArray();colors.resize(faces.size());colors.fill(Color(.63,.54,.41))
	var support := MeshInstance3D.new();support.name="TerrainSupport"
	support.mesh=CityGeometry3D.mesh_from_faces(faces,colors,.025,CityGeometry3D.SurfaceKind.TERRAIN)
	if _material==null: _material=support.mesh.surface_get_material(0)
	support.material_override=_material
	model.add_child(support)
	var body := StaticBody3D.new();body.collision_layer=CityModelCatalog.SHELL_LAYER;body.collision_mask=0
	var shape := CollisionShape3D.new()
	var shell := ConcavePolygonShape3D.new();shell.set_faces(faces);shell.backface_collision=true
	shape.shape=shell;body.add_child(shape);support.add_child(body)

static func _collect(node: Node, parent: Transform3D, faces: PackedVector3Array) -> void:
	var transform := parent
	if node is Node3D: transform*=node.transform
	if node is MeshInstance3D and node.mesh!=null and node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		var vertices: PackedVector3Array=node.mesh.get_faces()
		for i: int in range(0,vertices.size(),3):
			var a := transform*vertices[i];var b := transform*vertices[i+1];var c := transform*vertices[i+2]
			# Only real horizontal undersides touching the author's zero plane.
			# No rectangular bounding-box fill across pools, courtyards or doors.
			if maxf(absf(a.y),maxf(absf(b.y),absf(c.y)))>.00005: continue
			if (c-a).cross(b-a).y>=-.00000001: continue
			faces.append_array(PackedVector3Array([a,b,c]))
	for child: Node in node.get_children(): _collect(child,transform,faces)

static func _below_base(polygon: Array[Vector2], city: City, cell: Vector2i, height: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var before := height-CityGeometry3D.point_on_ground(city,cell,previous).y-.0001
	for current: Vector2 in polygon:
		var distance := height-CityGeometry3D.point_on_ground(city,cell,current).y-.0001
		if (before>=0)!=(distance>=0): result.append(previous.lerp(current,before/(before-distance)))
		if distance>=0: result.append(current)
		previous=current;before=distance
	return result

static func _triangle(faces: PackedVector3Array,a: Vector3,b: Vector3,c: Vector3,up := false) -> void:
	if (c-a).cross(b-a).length_squared()<.000000000001: return
	faces.append_array(PackedVector3Array([a,c,b] if up and (c-a).cross(b-a).y<0 else [a,b,c]))
