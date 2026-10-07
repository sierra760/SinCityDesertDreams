# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Independent traversal geometry preserves the construction and render contracts.
extends "res://tests/test_case.gd"

# SHA-256 of the render/query arrays built for each terrain, ramp and network case.
# After an intended geometry change, copy the new hash from the failing check here.
const BASELINES := {
	"terrain 10": "4d5254d97e34af597e1922b58a3bd3a08d10411fa68be520901e29bee539beba",
	"terrain 9": "b1cde66dbc52d47ea7a7e865f4b66dc29e116043b4f2fdfaae66be0ee7419dd2",
	"terrain 16": "e0db844147446be72071d2f74b5af7f3a1b708330ec710b026bf088e1702bedb",
	"terrain 51": "2130d337b710f74b4f3f6de94c8fc4dfa6336e9716a4c6f74a7682bd4b173897",
	"terrain 64": "a055280c5431d7f54665a3ae4052b2d9691964298c5c3fbd907fb195d9633dd4",
	"terrain 65": "0eedd18dc7d03a7d83246446ba9dd98d5bff6baddd144a2f87d0d0be7ca166c2",
	"terrain 66": "233d15ea7fe2443e97b3f32ddc9d2a46c9e865e764c976db8f25d121e93b8705",
	"terrain 67": "4706f19007ee324d0dbacb0971442304f88b2a917f5cfaa426e084c119af77bb",
	"terrain 68": "78f582cec54ca4e99f39339e86754349116d05436c3ce773dc53b663697cdd9a",
	"terrain 69": "71fdd158810e6c575ebcfc67f50827b45c9b39028f712bd8d2465b9363aed3cf",
	"ramp 0 false": "0aff7672f55ecfeaa723ffabd51e0fb4380c38d7b5fc9ab0213d0361ada59331",
	"ramp 1 false": "002bfbb36ee70ab497f824c39736c31edcf2cca86167b6d9432eb369648d46cc",
	"ramp 2 false": "78c53b85ca6687b30654b76960c4df7f2097d047bf2df8f31cac388cb728623c",
	"ramp 3 false": "7088ae07283a2d9862e32ce10c949a356de18569980cd6250c3c63a1f3a65fd9",
	"ramp 0 true": "b24a10ada4e8a121a990c450200b64301227e2defbc4127015f900d2bbcf66ba",
	"ramp 1 true": "81bfb67940350efa05ce0cb58d87013152ea248fd87ee55bc7428d93fe1a0ffa",
	"ramp 2 true": "b302d41bd405d033826696c21d932cc41753065181a85fb3d48ccf624129fd1a",
	"ramp 3 true": "5b30bea756145cdadea22e62fd775ce6ed2b2670bca4af0742a5b1fc5101096b",
	"network 87 false": "ced911f6b3fc6b273f26c08056dbfbf99ba07a518ca1868615b0da4d08c8f644",
	"network 87 true": "23abafd8843e532878c9e13103dcadc91e694ffbf28a3c22b4366272f4809c53",
	"network 89 false": "1a1f2bc5e1b90091dc205e110689555a5cd834372767d6692af41d3fcbadae87",
	"network 89 true": "92a3157357ad50a68cc434c8a289c6c31f48ae82e1070240a97b31d11cc800c7",
	"network 92 false": "57c3c358d304d7eb43660379ec77c19a6a9e9993f282b91d1427faef576e9505",
	"network 92 true": "11e24a4750ddfc812250ff78ee3b0376dabf377c6a023dadefb2dbe19d3f9533",
	"network 101 false": "4cf6e6c3c11c9c504b71aeeb8e55c31e9e70533fa005dd989ad2827469b1cf2e",
	"network 101 true": "4cf6e6c3c11c9c504b71aeeb8e55c31e9e70533fa005dd989ad2827469b1cf2e",
	"network 102 false": "390374e6355672056cbc795e0e84c60232fb8ed514be602d7fb4da60d2c59e97",
	"network 102 true": "390374e6355672056cbc795e0e84c60232fb8ed514be602d7fb4da60d2c59e97",
	"network 103 false": "9b431ae997e8badfbaf679def780398d1be78af91be8bc3d2281b1f5a66a165d",
	"network 103 true": "9b431ae997e8badfbaf679def780398d1be78af91be8bc3d2281b1f5a66a165d",
	"network 104 false": "ce2b4a91b6f4de1b04e17e43b624c621884cf29a4e14c3ae29bf24dd5f212126",
	"network 104 true": "ce2b4a91b6f4de1b04e17e43b624c621884cf29a4e14c3ae29bf24dd5f212126",
	"network 75 false": "3dfef1760482cbc2f9f1a5c33267f1c3407b07a3ae3b1407b4343be58f378d98",
	"network 75 true": "3dfef1760482cbc2f9f1a5c33267f1c3407b07a3ae3b1407b4343be58f378d98",
	"network 76 false": "2cd208579ad6b607953c6d4a84814728c3513b5c6c5e25595d00bc26b881418f",
	"network 76 true": "2cd208579ad6b607953c6d4a84814728c3513b5c6c5e25595d00bc26b881418f",
}


func terrain_data(city: City, cell: Vector2i) -> Dictionary:
	var data := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
	for key: String in ["physical_floor_faces", "physical_obstacle_faces", "water_regions", "bounds"]:
		check(data.has(key), "terrain publishes semantic " + key)
	return data

func network_data(layer: CityNetworks3D) -> Dictionary:
	return layer.physical_data()

# World-distance tolerance: one float32 coordinate ULP at the 128-tile city
# boundary, 0.000016 tile (0.256 mm at the exploration scale). Fixed barycentric
# tolerances wrongly reject points on skinny partition edges, where a point at
# zero edge distance can still have v=-0.0005636.
const SAMPLE_EDGE_EPS := 0.000016

func sample(faces: PackedVector3Array, p: Vector2, upward: bool = true) -> float:
	for i: int in range(0, faces.size(), 3):
		var a := faces[i]; var b := faces[i+1]; var c := faces[i+2]
		var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
		var area := ab.cross(ac)
		if absf(area)<0.00000001 or (area<0 if upward else area>0): continue
		var ap := p-Vector2(a.x,a.z)
		var v := ap.cross(ac)/area; var w := ab.cross(ap)/area
		if v>=-SAMPLE_EDGE_EPS*ac.length()/absf(area) and w>=-SAMPLE_EDGE_EPS*ab.length()/absf(area) and v+w<=1.0+SAMPLE_EDGE_EPS*(ac-ab).length()/absf(area): return a.y+(b.y-a.y)*v+(c.y-a.y)*w
	return NAN

func test_terrain_roles_water_streams_shore_and_diagonals() -> void:
	var city := flat_city(); var cell := Vector2i(10,10)
	for code: int in [Terrain.CORNER_NE, Terrain.CORNER_NW, Terrain.SUBMERGED, 0x33, 0x40,0x41,0x42,0x43,0x44,0x45]:
		city.terrain.putv(cell,code)
		city.set_heights(10,10,4,5 if code in [Terrain.SUBMERGED,0x33] else 4)
		var before := var_to_bytes(SaveFormat.encode_city(city))
		var data := terrain_data(city,cell)
		if city.is_water(10,10):
			check_eq(var_to_bytes([data.faces,data.face_cells,data.mesh.surface_get_arrays(0)]).hex_encode().sha256_text(), BASELINES["terrain %d" % code], "terrain render/query arrays match baseline sha256")
		else:
			check_eq(data.faces,data.physical_floor_faces,"shared dry query and support facets match")
			check_eq(data.physical_obstacle_faces.size(),0,"isolated dry slope joins its level neighbors")
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"terrain extraction is read only")
		if not data.has("physical_floor_faces"): continue
		check_eq(data.bounds,Rect2i(cell,Vector2i.ONE))
		var floor: PackedVector3Array=data.physical_floor_faces
		if city.is_water(10,10):
			check(not data.water_regions.is_empty(),"wet visible geometry has water regions")
			for region: Dictionary in data.water_regions:
				check_eq(region.cell,cell)
				check(region.polygon.size()>=3)
				check(is_equal_approx(region.top,CityGeometry3D.water_surface_height(city,cell)))
			for p: Vector3 in floor: check(not is_equal_approx(p.y,CityGeometry3D.water_surface_height(city,cell)),"water surface cannot be support")
			if code==0x33:
				var shelf:=false
				for p: Vector3 in floor: shelf=shelf or p.y>CityGeometry3D.water_surface_height(city,cell)
				check(shelf,"dry shore shelf stays physical")
				for region: Dictionary in data.water_regions:
					check(not Geometry2D.is_point_in_polygon(Vector2(10.9,10.5),region.polygon),"dry shelf is excluded from water polygons")
			if code>=0x40:
				var paths: Array=[[Vector2.UP,Vector2.DOWN],[Vector2.LEFT,Vector2.RIGHT],[Vector2.RIGHT],[Vector2.DOWN],[Vector2.LEFT],[Vector2.UP]]
				for direction: Vector2 in paths[code-0x40]:
					var covered:=false
					for region: Dictionary in data.water_regions: covered=covered or Geometry2D.is_point_in_polygon(Vector2(10.5,10.5)+direction*.4,region.polygon)
					check(covered,"independent stream endpoint belongs to its water region")
				for region: Dictionary in data.water_regions: check(not Geometry2D.is_point_in_polygon(Vector2(10.1,10.1),region.polygon),"stream keeps dry corner ground")
		else:
			for p: Vector2 in [Vector2(.2,.3),Vector2(.75,.25),Vector2(.25,.75)]:
				check(absf(sample(floor,Vector2(cell)+p)-CityGeometry3D.point_on_ground(city,cell,p).y)<0.00001,"both terrain diagonals preserve visible facets")

func test_all_ramp_orientations_have_floor_and_underside() -> void:
	var pairs := [[Vector2.RIGHT,Vector2.UP],[Vector2.LEFT,Vector2.UP],[Vector2.LEFT,Vector2.DOWN],[Vector2.RIGHT,Vector2.DOWN]]
	for axis: bool in [false,true]:
		for index: int in 4:
			var city:=flat_city(); city.building.put(10,10,93+index);city.flags.put(10,10,2 if axis else 0)
			var layer:=CityNetworks3D.new();layer.rebuild(city)
			check_eq(var_to_bytes([layer._faces,layer._colors,layer._cells]).hex_encode().sha256_text(), BASELINES["ramp %d %s" % [index,str(axis)]], "ramp render arrays match baseline sha256")
			var data:=network_data(layer)
			if not data.is_empty():
				var road: Vector2=pairs[index][0];var high: Vector2=pairs[index][1]
				if axis: road=Vector2(road.y,road.x);high=Vector2(high.y,high.x)
				var pivot:=Vector2(10.5,10.5)+(road+high)*.5
				for step: int in 65:
					var p:=pivot+(-high).rotated((-high).angle_to(-road)*step/64.0)*.5
					check(not is_nan(sample(data.physical_floor_faces,p)),"entire ramp centerline has support")
					check(not is_nan(sample(data.physical_obstacle_faces,p,false)),"entire ramp centerline has underside")
				var obstacles: PackedVector3Array=data.physical_obstacle_faces
				for i: int in range(0,obstacles.size(),3):
					var a:=obstacles[i];var b:=obstacles[i+1];var c:=obstacles[i+2]
					if absf((b-a).cross(c-a).y)>.00000001: continue
					var center: Vector3=(a+b+c)/3
					var radial:=Vector2(center.x,center.z)-pivot
					if absf(radial.length()-.5)<.13 and absf(radial.cross(-high))>.01 and absf(radial.cross(-road))>.01:
						check(maxf(a.y,maxf(b.y,c.y))-minf(a.y,minf(b.y,c.y))<.02,"ramp subdivisions cannot create internal fences")
				for entry: Array in [[road,.04],[high,.38]]:
					var p: Vector2=Vector2(10.5,10.5)+entry[0]*.5
					check(absf(sample(data.physical_floor_faces,p)-(4*CityGeometry3D.HEIGHT+entry[1]))<.00001,"ramp endpoint matches visible road/highway")
					check(not is_nan(sample(data.physical_obstacle_faces,p,false)),"ramp underside blocks upward traversal")
			layer.free()

func test_imported_highway_turns_and_bridge_axes() -> void:
	for code: int in [87,89,92,101,102,103,104,75,76]:
		for axis: bool in [false,true]:
			var city:=flat_city();var anchor:=Vector2i(35,89)
			city.building.putv(anchor,code);city.flags.putv(anchor,2 if axis else 0)
			if code>=101:
				for dy: int in 2:
					for dx: int in 2:
						city.building.put(anchor.x+dx,anchor.y+dy,code);city.zone.put(anchor.x+dx,anchor.y+dy,[[128,16],[64,32]][dy][dx])
			var before:=var_to_bytes(SaveFormat.encode_city(city))
			var layer:=CityNetworks3D.new();layer.rebuild(city)
			check_eq(var_to_bytes([layer._faces,layer._colors,layer._cells]).hex_encode().sha256_text(), BASELINES["network %d %s" % [code,str(axis)]], "network render arrays match baseline sha256")
			var data:=network_data(layer)
			if not data.is_empty():
				if code==92: check(data.physical_floor_faces.is_empty(),"power wire is not a floor")
				else: check(not data.physical_floor_faces.is_empty())
				if code in [87,89]:
					check(absf(sample(data.physical_floor_faces,Vector2(anchor)+Vector2(.5,.5))-(4*CityGeometry3D.HEIGHT+.04+(.65 if code==89 else 0.0)))<.00001,"bridge 89 lift is applied exactly once")
				if code>=101:
					var pivot: Vector2=Vector2(anchor)+[Vector2(2,0),Vector2(2,2),Vector2(0,2),Vector2.ZERO][code-101]
					var angle: float=[PI,-PI/2,0,PI/2][code-101]
					for radius: float in [.5,1.5]:
						for step: int in 65:
							var p:=pivot+Vector2(cos(angle-step*PI/128),sin(angle-step*PI/128))*radius
							check(not is_nan(sample(data.physical_floor_faces,p)),"connected turn floor code=%d axis=%s radius=%s step=%d point=%s" % [code,axis,radius,step,p])
							check(not is_nan(sample(data.physical_obstacle_faces,p,false)),"connected turn underside code=%d axis=%s radius=%s step=%d point=%s" % [code,axis,radius,step,p])
				for box: Dictionary in data.physical_boxes:
					check(box.transform.is_finite() and box.size.is_finite(),"physical boxes finite")
					if code in [75,76]:
						for t: float in [.1,.3,.5,.7,.9]:
							var p:=Vector3(anchor.x+t,4*CityGeometry3D.HEIGHT+.2,anchor.y+.5) if code==75 else Vector3(anchor.x+.5,4*CityGeometry3D.HEIGHT+.2,anchor.y+t)
							check(not AABB(-box.size/2,box.size).has_point(box.transform.affine_inverse()*p),"underpass clear")
				layer.visible=false
				check_eq(layer.physical_data(),data,"visibility cannot change physical revision")
			check_eq(var_to_bytes(SaveFormat.encode_city(city)),before)
			layer.free()

func test_portal_is_cut_physically_but_query_is_uncut() -> void:
	var city:=flat_city();city.building.put(10,10,108)
	var data:=terrain_data(city,Vector2i(10,10))
	check_eq(data.faces.size(),6,"query remains uncut")
	if data.has("physical_floor_faces"):
		check(is_nan(sample(data.physical_floor_faces,Vector2(10.5,10.5))),"physical ground opens the mouth")
	var layer:=CityNetworks3D.new();layer.rebuild(city)
	var physical:=network_data(layer)
	if not physical.is_empty(): check(not physical.physical_obstacle_faces.is_empty(),"terminal recess has physical barrier")
	layer.free()

func test_partitioned_floor_and_connected_deck_have_no_interior_fences() -> void:
	var city:=flat_city()
	city.building.put(10,10,30)
	var layer:=CityNetworks3D.new();layer.rebuild(city)
	var data:=network_data(layer)
	if not data.is_empty():
		var area:=0.0
		var floor: PackedVector3Array=data.physical_floor_faces
		for i: int in range(0,floor.size(),3): area+=absf((floor[i+1]-floor[i]).cross(floor[i+2]-floor[i]).y)*.5
		check(absf(area-1.0)<.00001,"road verge, shoulder and pavement partition one tile without duplicate support")
	layer.free()
	city.building.put(10,10,87);city.building.put(11,10,87);city.building.put(12,10,87)
	for x: int in [10,11,12]: city.flags.put(x,10,2)
	layer=CityNetworks3D.new();layer.rebuild(city)
	data=network_data(layer)
	if not data.is_empty():
		var obstacles: PackedVector3Array=data.physical_obstacle_faces
		for i: int in range(0,obstacles.size(),3):
			var a:=obstacles[i];var b:=obstacles[i+1];var c:=obstacles[i+2]
			if absf((b-a).cross(c-a).y)>.00000001: continue
			var center: Vector3=(a+b+c)/3
			if center.x>10.01 and center.x<12.99 and absf(center.z-10.5)<.299:
				check(maxf(a.y,maxf(b.y,c.y))-minf(a.y,minf(b.y,c.y))<.02,"shared deck edges never make full-depth interior fences")
		for x: float in [10.1,10.9,11.0,11.5,12.1,12.9]:
			check(not is_nan(sample(data.physical_obstacle_faces,Vector2(x,10.5),false)),"underside spans connected bridge")
		var detached: Dictionary=layer.physical_data()
		detached.physical_boxes.clear();detached.physical_floor_faces.clear()
		check_eq(layer.physical_data(),data,"returned physical revision is detached")
	layer.free()

func test_four_tunnel_mouths_have_floor_cut_and_terminal_barrier() -> void:
	for index: int in 4:
		var city:=flat_city();city.building.put(10,10,63+index);city.terrain.put(10,10,1+index)
		var ground:=terrain_data(city,Vector2i(10,10))
		if ground.has("physical_floor_faces"):
			check(is_nan(sample(ground.physical_floor_faces,Vector2(10.5,10.5))),"tunnel center is physically open")
			check(not is_nan(sample(ground.faces,Vector2(10.5,10.5))),"tunnel construction query remains closed")
		var layer:=CityNetworks3D.new();layer.rebuild(city)
		var data:=network_data(layer)
		if not data.is_empty():
			check(absf(sample(data.physical_floor_faces,Vector2(10.5,10.5))-(4*CityGeometry3D.HEIGHT+.04))<.00001,"terminal tunnel floor remains level")
			var inward: Vector2=[Vector2.LEFT,Vector2.UP,Vector2.RIGHT,Vector2.DOWN][index]
			var start:=Vector3(10.5,4*CityGeometry3D.HEIGHT+.2,10.5)
			var end:=start+Vector3(inward.x,0,inward.y)*.5
			var hit:=false
			var faces: PackedVector3Array=data.physical_obstacle_faces
			for i: int in range(0,faces.size(),3):
				hit=hit or Geometry3D.segment_intersects_triangle(start,end,faces[i],faces[i+1],faces[i+2])!=null
			check(hit,"dark recess is a terminal physical barrier")
		layer.free()
