# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore's three slapstick weapons: what each one does and the small toy-like
## model the walker holds. Models are built from primitive shapes in tile
## units (one tile is sixteen metres), with the grip at the origin and the
## weapon extending along +Y, so a swing is a rotation of the holder.
class_name ExploreWeapons
extends RefCounted

enum Kind { NONE, CHICKEN, PIE, MALLET }
## Cycling order. NONE puts the weapon away.
const ORDER: Array[int] = [Kind.NONE, Kind.CHICKEN, Kind.PIE, Kind.MALLET]
const NAMES := {Kind.NONE: "Empty hands", Kind.CHICKEN: "Rubber Chicken", Kind.PIE: "Custard Pie", Kind.MALLET: "Foam Mallet"}
## Per weapon: swing length, when in the swing it strikes or releases, the
## wait before the next swing, its reach and arc (cosine of the half angle),
## how many people one strike can catch, and how hard the pieces fly.
const SPECS := {
	Kind.CHICKEN: {"swing":.32,"strike":.14,"cooldown":.42,"reach":.12,"arc":.35,"targets":3,"launch":.30,"lift":.26,"cue":&"squawk"},
	Kind.PIE: {"swing":.30,"strike":.16,"cooldown":.55,"reach":0.0,"arc":-1.0,"targets":1,"launch":.24,"lift":.22,"cue":&"splat"},
	Kind.MALLET: {"swing":.55,"strike":.38,"cooldown":1.0,"reach":.19,"arc":-1.0,"targets":8,"launch":.18,"lift":.48,"cue":&"bonk"},
}
## Thrown pies: launch speed forward and up (tiles per second), the radius
## that catches a pedestrian, and how long one stays in the air at most.
const PIE_SPEED := .95
const PIE_LIFT := .22
const PIE_RADIUS := .03
const PIE_LIFETIME := 3.0

static func display_name(kind: int) -> String:
	return NAMES.get(kind,"Empty hands")

static func next(kind: int) -> int:
	return ORDER[(ORDER.find(kind)+1)%ORDER.size()]

static func _material(color: Color, roughness: float = .6) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

static func _part(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, rotation: Vector3 = Vector3.ZERO, roughness: float = .6) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(color,roughness)
	part.position = at
	part.rotation = rotation
	parent.add_child(part)
	return part

static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return mesh

static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	return mesh

## The held model for `kind`, or null for NONE.
static func make_model(kind: int) -> Node3D:
	match kind:
		Kind.CHICKEN: return _chicken()
		Kind.PIE: return make_pie()
		Kind.MALLET: return _mallet()
	return null

## A floppy rubber chicken held by its feet, head at the far end.
static func _chicken() -> Node3D:
	var root := Node3D.new()
	root.name = "RubberChicken"
	var yellow := Color(.97,.83,.22)
	var orange := Color(.95,.48,.12)
	var leg := _cylinder(.0006,.0006,.008)
	_part(root,leg,orange,Vector3(-.0012,.003,0))
	_part(root,leg,orange,Vector3(.0012,.003,0))
	var body := CapsuleMesh.new()
	body.radius = .0042
	body.height = .02
	_part(root,body,yellow,Vector3(0,.016,0),Vector3.ZERO,.45)
	var neck := _cylinder(.0016,.0022,.009)
	_part(root,neck,yellow,Vector3(0,.029,-.001),Vector3(-.35,0,0),.45)
	_part(root,_sphere(.0034),yellow,Vector3(0,.035,-.0025),Vector3.ZERO,.45)
	_part(root,_cylinder(0.0,.0014,.0045),orange,Vector3(0,.035,-.0068),Vector3(-PI*.5,0,0))
	_part(root,_sphere(.0016),Color(.86,.12,.1),Vector3(0,.0392,-.002))
	var eye := _sphere(.0006)
	_part(root,eye,Color(.05,.05,.05),Vector3(-.0024,.0357,-.0042))
	_part(root,eye,Color(.05,.05,.05),Vector3(.0024,.0357,-.0042))
	return root

## A cream pie in a crimped tin with a cherry on top.
static func make_pie() -> Node3D:
	var root := Node3D.new()
	root.name = "CustardPie"
	_part(root,_cylinder(.0098,.0082,.0028),Color(.78,.55,.27),Vector3(0,.0014,0))
	_part(root,_cylinder(.0088,.009,.0018),Color(.99,.96,.86),Vector3(0,.0032,0),Vector3.ZERO,.35)
	_part(root,_sphere(.0019),Color(.85,.08,.12),Vector3(0,.0045,0),Vector3.ZERO,.3)
	return root

## A carnival-sized foam mallet: a long handle and a big pink barrel head.
static func _mallet() -> Node3D:
	var root := Node3D.new()
	root.name = "FoamMallet"
	_part(root,_cylinder(.0013,.0015,.058),Color(.55,.35,.18),Vector3(0,.022,0))
	_part(root,_cylinder(.0125,.0125,.034),Color(.96,.42,.62),Vector3(0,.056,0),Vector3(0,0,PI*.5),.8)
	var band := _cylinder(.0129,.0129,.004)
	_part(root,band,Color(.99,.95,.98),Vector3(-.012,.056,0),Vector3(0,0,PI*.5),.8)
	_part(root,band,Color(.99,.95,.98),Vector3(.012,.056,0),Vector3(0,0,PI*.5),.8)
	return root

## Where a weapon sits in the right hand. The hand frame follows the rig's
## RightHand bone at rest: +X out to the right, +Y along the fingers (down a
## hanging arm), +Z where the thumb points (forward). PALM is the grip centre.
const PALM := Vector3(0,.0045,0)

## The weapon's placement in the hand frame. The chicken hangs by its feet
## with its beak forward; the mallet handle runs through the fist along the
## thumb with the barrel's striking face toward the fingers; the pie rests
## level on the palm (its tilt is cancelled where it is held).
static func grip(kind: int) -> Transform3D:
	match kind:
		Kind.CHICKEN:
			var hang := Basis(Vector3.UP,PI)
			return Transform3D(hang,PALM-hang*Vector3(0,.003,0))
		Kind.MALLET:
			var held := Basis(Vector3(0,1,0),Vector3(0,0,1),Vector3(1,0,0))
			return Transform3D(held,PALM-held*Vector3(0,.012,0))
		Kind.PIE:
			return Transform3D(Basis.IDENTITY,PALM)
	return Transform3D.IDENTITY

## Right-arm poses as Vector4(raise, sweep, elbow, wrist), in radians, applied
## to the arm hanging at rest: raise lifts the whole arm forward about the
## shoulder, sweep then turns it toward the left (negative: out to the right),
## elbow bends the forearm forward and wrist tips the weapon about the hand's
## +X axis (positive toward the back).
const CARRY := {
	Kind.CHICKEN: Vector4(.15,0,.35,0),
	# Over the shoulder, the barrel behind it, clear of the face.
	Kind.MALLET: Vector4(.45,0,2.2,0),
	# Forearm out in front like a waiter's tray.
	Kind.PIE: Vector4(.2,0,1.4,0),
}
## Swing keyframes between the carry pose at 0 and 1: [progress, pose].
const SWINGS := {
	# Out to the right, then a flat swat across the front and through.
	Kind.CHICKEN: [[.28,Vector4(1.1,-1.1,.25,0)],[.46,Vector4(1.4,.5,.15,0)],[.68,Vector4(1.0,1.1,.35,0)]],
	# Pull the pie back by the shoulder, then shove it forward and let go.
	Kind.PIE: [[.31,Vector4(-.45,0,2.35,.4)],[.53,Vector4(1.55,0,.05,0)],[.78,Vector4(1.35,0,.25,0)]],
	# Raise it overhead so the barrel drops behind the back, then slam it down
	# in front with a snap of the wrist, hold, and lift it back to the shoulder.
	Kind.MALLET: [[.45,Vector4(2.6,0,1.2,.3)],[.69,Vector4(1.15,0,.1,-1.9)],[.82,Vector4(1.0,0,.15,-1.9)]],
}

## The arm pose for `kind`: its carry pose, or `u` (0..1) through a swing.
static func arm_pose(kind: int, u: float = -1.0) -> Vector4:
	var carry: Vector4 = CARRY.get(kind,Vector4.ZERO)
	if u < 0.0 or u >= 1.0 or not SWINGS.has(kind): return carry
	var previous_u := 0.0
	var previous := carry
	for key: Array in SWINGS[kind]+[[1.0,carry]]:
		var key_u: float = key[0]
		var pose: Vector4 = key[1]
		if u <= key_u:
			var t := clampf((u-previous_u)/maxf(key_u-previous_u,.0001),0.0,1.0)
			return previous.lerp(pose,t*t*(3.0-2.0*t))
		previous_u = key_u
		previous = pose
	return carry
