# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The native geometry kernel must reproduce the GDScript resolver byte for byte.
## On platforms without the library the comparisons report that and pass; on
## macOS the kernel must load and run.
extends "res://tests/test_case.gd"
const Native := preload("res://scripts/view/city_network_physics_native.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")
const REAL_CITIES: Array[String] = ["res://assets/cities/La Presa.sc2","res://assets/cities/Valle del Mar.sc2"]


func after_all() -> void:
	Native.force_fallback = false


func _native_ready(label: String) -> bool:
	Native.force_fallback = false
	if Native.available(): return true
	print("    native geometry kernel unavailable on %s; %s checked the fallback path only" % [OS.get_name(),label])
	return false


func _first_difference(actual: PackedVector3Array, expected: PackedVector3Array, label: String) -> void:
	if actual == expected: return
	print("    %s differs: actual=%d expected=%d points" % [label,actual.size(),expected.size()])
	for i: int in mini(actual.size(),expected.size()):
		if actual[i] != expected[i]:
			print("    first difference at %d: actual=%s expected=%s" % [i,var_to_str(actual[i]),var_to_str(expected[i])])
			return


## Reference, dispatcher fallback, native, packed native and input retention.
func _compare(label: String, patches: Array[Dictionary], boxes: Array[Dictionary], obstacles: PackedVector3Array) -> void:
	var inputs := var_to_bytes([patches,boxes,obstacles])
	var start := Time.get_ticks_usec()
	var expected: Dictionary = Resolver.resolve(patches,boxes,obstacles)
	var reference_us := Time.get_ticks_usec()-start
	var expected_bytes := var_to_bytes(expected)
	check_gt(expected.physical_floor_faces.size(),0,label+" fixture produces floors")
	Native.force_fallback = true
	check(not Native.available(),label+" forced fallback reports unavailable")
	var fallback: Dictionary = Native.resolve(patches,boxes,obstacles)
	check(var_to_bytes(fallback)==expected_bytes,label+" dispatcher fallback is byte-identical")
	var packed := Native.pack_patches(patches)
	var fallback_packed: Dictionary = Native.resolve_packed(packed[0],packed[1],packed[2],packed[3],packed[4],boxes,obstacles)
	check(var_to_bytes(fallback_packed)==expected_bytes,label+" packed fallback is byte-identical")
	check(var_to_bytes(Native.unpack_patches(packed[0],packed[1],packed[2],packed[3],packed[4]))==var_to_bytes(patches),label+" packing round-trips")
	if not _native_ready(label): return
	start = Time.get_ticks_usec()
	var actual: Dictionary = Native.resolve(patches,boxes,obstacles)
	var native_us := Time.get_ticks_usec()-start
	var actual_bytes := var_to_bytes(actual)
	check(actual_bytes==expected_bytes,label+" native resolve is byte-identical to the GDScript resolver")
	_first_difference(actual.physical_floor_faces,expected.physical_floor_faces,label+" floors")
	_first_difference(actual.physical_obstacle_faces,expected.physical_obstacle_faces,label+" obstacles")
	check(actual==expected,label+" native dictionary equals the reference")
	start = Time.get_ticks_usec()
	var native_packed: Dictionary = Native.resolve_packed(packed[0],packed[1],packed[2],packed[3],packed[4],boxes,obstacles)
	var packed_us := Time.get_ticks_usec()-start
	check(var_to_bytes(native_packed)==expected_bytes,label+" packed native entry is byte-identical")
	check(var_to_bytes([patches,boxes,obstacles])==inputs,label+" caller-owned inputs unchanged")
	print("    %s reference_us=%d native_us=%d native_packed_us=%d floor_triangles=%d obstacle_triangles=%d" % [label,reference_us,native_us,packed_us,expected.physical_floor_faces.size()/3,expected.physical_obstacle_faces.size()/3])


func test_native_kernel_loads_on_apple_platforms() -> void:
	Native.force_fallback = false
	if OS.get_name() in ["macOS","iOS"]:
		check(Native.available(),"native kernel loads on Apple platforms")
		check(ClassDB.class_exists(&"SCDDNetworkPhysics"),"native class is registered")
		check(bool(ClassDB.class_call_static(&"SCDDNetworkPhysics",&"available")),"native kernel reports availability")
	else:
		check(not Native.available(),"other platforms never attempt the native library")
		print("    native geometry kernel unavailable on %s; skipping" % OS.get_name())


func test_multigroup_projection_fixture() -> void:
	var patches: Array[Dictionary] = []
	for cell: Vector2i in [Vector2i(126,126),Vector2i(3,4),Vector2i(127,126)]:
		for i: int in 3:
			var origin := Vector3(cell.x,4.0+i*.015,cell.y)
			var triangle := PackedVector3Array([origin+Vector3(.1,0,.1),origin+Vector3(.9,.03,.1),origin+Vector3(.5,.01,.9)])
			patches.append({"cell":cell,"group":1 if i%2==0 else 4,"role":i,"triangle":triangle,"depth":.09500000000000003 if i%2==0 else .12500000000000003})
	var obstacles := PackedVector3Array([Vector3(126,4,126),Vector3(126,5,126),Vector3(126,4,127)])
	var boxes: Array[Dictionary] = [{"size":Vector3(.2,1,.3),"transform":Transform3D(Basis.IDENTITY,Vector3(127,4,127))}]
	_compare("multigroup",patches,boxes,obstacles)


## T junctions, lips, degenerate and more-than-two-contributor edges reach the
## boundary stage through full resolve inputs: one group per triangle keeps
## every contributor instead of partitioning it away.
func test_boundary_contributors_through_full_resolve() -> void:
	var triangles: Array[PackedVector3Array] = [
		PackedVector3Array([Vector3(126,4,126),Vector3(127,4,126),Vector3(127,4.02,127)]),
		PackedVector3Array([Vector3(126,4,126),Vector3(127,4.02,127),Vector3(126,4.02,127)]),
		PackedVector3Array([Vector3(127,4,126),Vector3(128,4.01,126),Vector3(127,4.02,126.5)]),
		PackedVector3Array([Vector3(128,4,127),Vector3(128,4,127),Vector3(128,4,128)]),
		PackedVector3Array([Vector3(127,4,127),Vector3(127.5,4,127),Vector3(127.25,4,127.00002)])]
	triangles.append(triangles[4]);triangles.append(triangles[4])
	var patches: Array[Dictionary] = []
	for index: int in triangles.size():
		var triangle := triangles[index]
		patches.append({"cell":Vector2i(floori(triangle[0].x),floori(triangle[0].z)),"group":index,"role":index%3,"triangle":triangle,"depth":.09500000000000003+index*.00700000000000001})
	_compare("boundary-contributors",patches,[],PackedVector3Array())
	# Fine-bin boundaries and microscopic T junctions at several offsets.
	patches = []
	var group := 0
	for offset: Vector2 in [Vector2.ZERO,Vector2(0.249999,0.499999),Vector2(126.99999,127.25)]:
		for drift: float in [0.0,0.0000002,0.000005,-0.000005]:
			var shape: Array[Vector2] = [Vector2(0,0),Vector2(.6,0),Vector2(0,.6),Vector2(.6,0),Vector2(.6,.6),Vector2(0,.6),
				Vector2(.6+drift,0),Vector2(.9,0),Vector2(.6+drift,.3),Vector2(.6+drift,.3),Vector2(.9,0),Vector2(.9,.6),
				Vector2(.6+drift,.3),Vector2(.9,.6),Vector2(.6+drift,.6)]
			for height: float in [1.0,3.0]:
				for i: int in range(0,shape.size(),3):
					var triangle := PackedVector3Array()
					for j: int in 3:
						var point := shape[i+j]+offset
						triangle.append(Vector3(point.x,height,point.y))
					group += 1
					patches.append({"cell":Vector2i(floori(offset.x),floori(offset.y)),"group":group,"role":0,"triangle":triangle,"depth":0.12})
	_compare("microscopic-junctions",patches,[],PackedVector3Array())


func _compare_city(city: City, label: String) -> void:
	var before := SaveFormat.encode_city(city)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	_compare(label,layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT)),layer._physical_boxes,layer._physical_obstacles)
	check(SaveFormat.encode_city(city)==before,label+" city bytes unchanged")
	layer.free()


func test_far_city_multigroup_networks() -> void:
	var city := City.new()
	city.altitude.data.fill(4)
	for code: int in range(29,109):
		var index := code-29
		var cell := Vector2i(3+(index%10)*3,80+(index/10)*3)
		city.building.putv(cell,code)
		city.flags.putv(cell,2 if code%2 == 0 else 0)
		if code in range(63,67): city.terrain.putv(cell,code-62)
	for x: int in range(60,65):
		city.building.put(x,20,87)
		city.flags.put(x,20,2)
	_compare_city(city,"mixed-far-city-networks")


func test_real_bundled_cities() -> void:
	for path: String in REAL_CITIES:
		var loaded := Sc2Import.load(path)
		check(loaded.ok,path+" imports")
		if loaded.ok: _compare_city(loaded.city,path.get_file())
