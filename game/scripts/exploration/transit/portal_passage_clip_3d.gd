# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Subtract a finite tunnel opening from portal triangles. The remaining
## polygons keep their winding; the source meshes are never modified.
extends RefCounted

static func triangle(a: Vector3, b: Vector3, c: Vector3, passage: Dictionary) -> PackedVector3Array:
	var inverse: Transform3D = passage.inverse
	var remaining: Array[Vector3] = [inverse*a,inverse*b,inverse*c]
	var bounds: AABB = passage.bounds
	var planes: Array[Plane] = [Plane(Vector3.RIGHT,bounds.end.x),Plane(Vector3.LEFT,-bounds.position.x),
		Plane(Vector3.UP,bounds.end.y),Plane(Vector3.DOWN,-bounds.position.y),
		Plane(Vector3.BACK,bounds.end.z),Plane(Vector3.FORWARD,-bounds.position.z)]
	var outside: Array = []
	for plane: Plane in planes:
		if remaining.is_empty(): break
		var keep := _half(remaining,plane,false)
		if keep.size()>=3: outside.append(keep)
		remaining = _half(remaining,plane,true)
	var result := PackedVector3Array()
	var at: Transform3D = passage.at
	for polygon: Array in outside:
		for i: int in range(1,polygon.size()-1):
			var x: Vector3 = at*polygon[0]
			var y: Vector3 = at*polygon[i]
			var z: Vector3 = at*polygon[i+1]
			if (y-x).cross(z-x).length_squared()>1e-14: result.append_array(PackedVector3Array([x,y,z]))
	return result

static func _half(polygon: Array[Vector3], plane: Plane, inside: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i: int in polygon.size():
		var a: Vector3 = polygon[i]
		var b: Vector3 = polygon[(i+1)%polygon.size()]
		var da := plane.distance_to(a)
		var db := plane.distance_to(b)
		var take_a := da<=0.0 if inside else da>=0.0
		var take_b := db<=0.0 if inside else db>=0.0
		if take_a: result.append(a)
		if take_a!=take_b: result.append(a.lerp(b,da/(da-db)))
	return result
