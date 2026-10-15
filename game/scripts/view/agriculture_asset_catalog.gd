# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name AgricultureAssetCatalog
extends RefCounted
## Validates metre-space navigation before exposing any livestock profiles.
## Renderer applies scale once; make_animal returns native metre-space geometry.

const IDENTITIES = preload("res://scripts/view/agriculture_asset_hashes.gd")
const MODELS := {
	&"beef_cattle": preload("res://assets/agriculture/beef_cattle.glb"),
	&"dairy_cattle": preload("res://assets/agriculture/dairy_cattle.glb"),
	&"sheep": preload("res://assets/agriculture/sheep.glb"),
}
const COUNTS := {"cattle_range":8,"sheep_pasture":10,"dairy":8,"feedlot":12}
const SPECIES := {"cattle_range":"beef_cattle","sheep_pasture":"sheep","dairy":"dairy_cattle","feedlot":"beef_cattle"}
const LOT_MODELS := {"cattle_range":"res://assets/desert-dreams-3d/269-blender.glb","sheep_pasture":"res://assets/desert-dreams-3d/270-blender.glb","dairy":"res://assets/desert-dreams-3d/273-blender.glb","feedlot":"res://assets/desert-dreams-3d/274-blender.glb"}
var _profiles: Dictionary = {}
var _species: Dictionary = {}

func load_manifest(path: String) -> Error:
	_profiles.clear()
	_species.clear()
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return ERR_PARSE_ERROR
	var data: Variant = parser.data
	if not _validate(data): return ERR_INVALID_DATA
	_profiles = data["profiles"].duplicate(true)
	_species = data["species"].duplicate(true)
	return OK

func profile(archetype: StringName) -> Dictionary:
	var result: Dictionary = _profiles.get(String(archetype),{}).duplicate(true)
	if not result.is_empty(): result["animal_profile"]=_species[result["species"]].duplicate(true)
	return result

func make_animal(species: StringName) -> Node3D:
	if not _species.has(String(species)) or not MODELS.has(species): return null
	return MODELS[species].instantiate() as Node3D

func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=low and value<=high

func _array(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size()!=count: return false
	for item: Variant in value:
		if not _number(item,low,high): return false
	return true

func _bounds(value: Variant) -> bool:
	return _array(value,4,-24,24) and value[0]<value[2] and value[1]<value[3]

func _model(data: Dictionary, expected: String) -> bool:
	if not _same(data.get("model"),expected) or not _same(data.get("model_sha256"),IDENTITIES.HASHES.get(expected)): return false
	# Exported PackedScenes are remapped: source GLB bytes need not be shipped.
	# Pinned identities always reject stale manifests; authoring builds also hash
	# actual source bytes. Offline package checker verifies pin/source agreement.
	if FileAccess.file_exists(expected) and FileAccess.get_sha256(expected)!=data["model_sha256"]: return false
	return ResourceLoader.exists(expected)

func _validate(data: Variant) -> bool:
	if not data is Dictionary or not _same(data.get("schema_version"),1) or not _same(data.get("units"),"metres") or not _same(data.get("meters_per_tile"),16): return false
	var species: Variant = data.get("species")
	var profiles: Variant = data.get("profiles")
	if not species is Dictionary or species.size()!=3 or not profiles is Dictionary or profiles.size()!=4: return false
	for key: StringName in MODELS:
		var s: Variant = species.get(String(key))
		if not s is Dictionary or not _model(s,"res://assets/agriculture/%s.glb" % key): return false
		if not _same(s,IDENTITIES.SPECIES_METADATA[String(key)]): return false
		if not _number(s.get("body_radius"),.1,5) or s["body_radius"]!=IDENTITIES.RADII[String(key)] or s.get("scale")!=.0625 or s.get("turn_margin")!=.2: return false
		if not s.get("bounds_metres") is Array or s["bounds_metres"].size()!=2: return false
		if not _array(s["bounds_metres"][0],3,-5,5) or not _array(s["bounds_metres"][1],3,-5,5): return false
		if s["bounds_metres"][0][1]!=0 or s.get("ground_y")!=0 or s.get("forward")!="+Z" or s.get("up")!="+Y": return false
	for key: String in COUNTS:
		var p: Variant = profiles.get(key)
		if not p is Dictionary or not _same(p.get("animal_count"),COUNTS[key]) or not _same(p.get("species"),SPECIES[key]) or not _model(p,LOT_MODELS[key]): return false
		var s: Dictionary = species[p["species"]]
		if not _same(p.get("body_radius"),s["body_radius"]) or not _same(p.get("turn_margin"),.2) or not _same(p.get("scale"),.0625) or not _same(p.get("ground_y"),.14) or not _same(p.get("units"),"metres"): return false
		var pens: Variant = p.get("pens")
		if not pens is Array or pens.size()!=(2 if key=="feedlot" else 1): return false
		var count := 0
		for pen_index: int in pens.size():
			var pen: Variant = pens[pen_index]
			if not pen is Dictionary: return false
			for field: String in IDENTITIES.GEOMETRY[key][pen_index]:
				if not _same(pen.get(field),IDENTITIES.GEOMETRY[key][pen_index][field]): return false
			if not _pen(pen,float(s["body_radius"])+.2): return false
			count += int(pen["count"])
			if key=="feedlot" and pen["count"]!=6: return false
		if count!=COUNTS[key]: return false
		if pens.size()==2:
			var a: Array = pens[0]["bounds"]
			var b: Array = pens[1]["bounds"]
			if not (a[2]<b[0] or b[2]<a[0] or a[3]<b[1] or b[3]<a[1]): return false
	return true

func _pen(pen: Variant, radius: float) -> bool:
	if not pen is Dictionary or not _bounds(pen.get("bounds")) or pen.get("ground_y")!=.14 or not _number(pen.get("count"),1,12) or int(pen["count"])!=pen["count"]: return false
	var b: Array = pen["bounds"]
	var fences: Variant = pen.get("fences")
	if not fences is Array or fences.size()!=6: return false
	var gate_count := 0
	var perimeter := 0.0
	for i: int in fences.size():
		var f: Variant = fences[i]
		var next: Variant = fences[(i+1)%fences.size()]
		if not f is Dictionary or not next is Dictionary or not _array(f.get("a"),2,-24,24) or not _array(f.get("b"),2,-24,24): return false
		if f.get("thickness")!=.16 or f.get("height")!=1.65 or not f.get("gate") is bool: return false
		if f["b"]!=next.get("a"): return false
		var a := Vector2(f["a"][0],f["a"][1])
		var c := Vector2(f["b"][0],f["b"][1])
		if a==c: return false
		if not ((a.x==c.x and (a.x==b[0] or a.x==b[2])) or (a.y==c.y and (a.y==b[1] or a.y==b[3]))): return false
		for point: Vector2 in [a,c]:
			if point.x<b[0] or point.x>b[2] or point.y<b[1] or point.y>b[3]: return false
		gate_count += int(f["gate"])
		perimeter += a.distance_to(c)
	if gate_count!=1 or not is_equal_approx(perimeter,2*(b[2]-b[0]+b[3]-b[1])): return false
	var nav := [b[0]+radius+.08,b[1]+radius+.08,b[2]-radius-.08,b[3]-radius-.08]
	if not _bounds(pen.get("navigation_bounds")): return false
	for i: int in 4:
		if not is_equal_approx(pen["navigation_bounds"][i],nav[i]): return false
	var obstacles: Variant = pen.get("obstacles")
	if not obstacles is Array or obstacles.size()<2 or obstacles.size()>16: return false
	var kinds: Array = []
	for o: Variant in obstacles:
		if not o is Dictionary or not _bounds(o.get("bounds")) or not _array(o.get("size"),3,.01,48) or not _array(o.get("center"),3,-24,24) or o.get("kind") not in ["shelter","trough","feed_bunk"]: return false
		var ob: Array = o["bounds"]
		if ob[0]<b[0] or ob[1]<b[1] or ob[2]>b[2] or ob[3]>b[3]: return false
		if not is_equal_approx(o["size"][0],ob[2]-ob[0]) or not is_equal_approx(o["size"][2],ob[3]-ob[1]) or not is_equal_approx(o["center"][0],(ob[0]+ob[2])/2) or not is_equal_approx(o["center"][2],(ob[1]+ob[3])/2): return false
		kinds.append(o["kind"])
	if "shelter" not in kinds or "trough" not in kinds: return false
	var all_points: Array[Vector2] = []
	for list_name: String in ["spawns","feed_targets","drink_targets"]:
		var points: Variant = pen.get(list_name)
		if not points is Array or points.is_empty() or points.size()>12: return false
		if list_name=="spawns" and points.size()!=pen["count"]: return false
		for point: Variant in points:
			if not _array(point,2,-24,24): return false
			var p := Vector2(point[0],point[1])
			if not _clear(p,pen,radius): return false
			if list_name=="spawns":
				for previous: Vector2 in all_points:
					if previous.distance_to(p)<2*radius: return false
			all_points.append(p)
	return _connected(all_points,pen,radius)

func _clear(p: Vector2, pen: Dictionary, radius: float) -> bool:
	var b: Array = pen["bounds"]
	if p.x<b[0]+radius+.08 or p.x>b[2]-radius-.08 or p.y<b[1]+radius+.08 or p.y>b[3]-radius-.08: return false
	for o: Dictionary in pen["obstacles"]:
		var r: Array = o["bounds"]
		var nearest := Vector2(clampf(p.x,r[0],r[2]),clampf(p.y,r[1],r[3]))
		if absf(p.x-nearest.x)<=radius and absf(p.y-nearest.y)<=radius: return false
	return true

func _segment(a: Vector2, b: Vector2, pen: Dictionary, radius: float) -> bool:
	# Distance from an axis-aligned rectangle to a segment. Expand the box
	# conservatively by radius; reject intersection using the slab method.
	if not _clear(a,pen,radius) or not _clear(b,pen,radius): return false
	for o: Dictionary in pen["obstacles"]:
		var r: Array = o["bounds"]
		var lo := Vector2(r[0]-radius,r[1]-radius)
		var hi := Vector2(r[2]+radius,r[3]+radius)
		var delta := b-a
		var enter := 0.0
		var leave := 1.0
		for axis: int in 2:
			if absf(delta[axis])<.00001:
				if a[axis]<lo[axis] or a[axis]>hi[axis]: enter=2.0
			else:
				var t0 := (lo[axis]-a[axis])/delta[axis]
				var t1 := (hi[axis]-a[axis])/delta[axis]
				enter=maxf(enter,minf(t0,t1))
				leave=minf(leave,maxf(t0,t1))
		if enter<=leave: return false
	return true

func _connected(points: Array[Vector2],pen: Dictionary,radius: float) -> bool:
	var cells: Dictionary = {}
	var b: Array = pen["navigation_bounds"]
	for z: int in range(ceili(b[1]),floori(b[3])+1):
		for x: int in range(ceili(b[0]),floori(b[2])+1):
			var p := Vector2(x,z)
			if _clear(p,pen,radius): cells[Vector2i(x,z)]=true
	if cells.is_empty(): return false
	var anchors: Array[Vector2i] = []
	for p: Vector2 in points:
		var nearest := Vector2i(1000,1000)
		var best := 3.0
		for cell: Vector2i in cells:
			var d := p.distance_to(Vector2(cell))
			if d<best and _segment(p,Vector2(cell),pen,radius): best=d;nearest=cell
		if best>=3: return false
		anchors.append(nearest)
	var queue: Array[Vector2i] = [anchors[0]]
	var seen := {anchors[0]:true}
	var index := 0
	while index<queue.size():
		var cell := queue[index]
		index+=1
		for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next := cell+direction
			if cells.has(next) and not seen.has(next) and _segment(Vector2(cell),Vector2(next),pen,radius):
				seen[next]=true
				queue.append(next)
	for anchor: Vector2i in anchors:
		if not seen.has(anchor): return false
	return true

func _same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_finite(float(a)) and is_equal_approx(float(a),float(b))
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i: int in a.size():
			if not _same(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in b:
			if not a.has(key) or not _same(a[key],b[key]): return false
		return true
	if typeof(a)!=typeof(b): return false
	return a==b

## Pure shared clearance contract, in authored metres, for cosmetic navigation.
func navigation_clear(point: Vector2, pen: Dictionary, radius: float) -> bool:
	return _clear(point, pen, radius)

func navigation_segment(from: Vector2, to: Vector2, pen: Dictionary, radius: float) -> bool:
	return _segment(from, to, pen, radius)

func animal_profile(species: StringName) -> Dictionary:
	return _species.get(String(species), {}).duplicate(true)
