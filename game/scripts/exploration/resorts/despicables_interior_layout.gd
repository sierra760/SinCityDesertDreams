# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## A 12 x 10 m store, split evenly: groceries west, six machines east.
extends RefCounted

const METRES := 16.0
const FIXTURES := [
	{"name":"grocery aisle west", "at":Vector2(-4.3,-.7), "half":Vector2(.35,2.1)},
	{"name":"grocery aisle east", "at":Vector2(-2.2,-.7), "half":Vector2(.35,2.1)},
	{"name":"drink coolers", "at":Vector2(-3.0,-4.6), "half":Vector2(2.5,.35)},
	{"name":"checkout", "at":Vector2(-3.4,3.4), "half":Vector2(1.35,.6)},
	{"name":"coffee counter", "at":Vector2(-5.55,2.0), "half":Vector2(.35,.6)},
]

static func layout() -> Dictionary:
	var key := ResortThemes.STORE_KEY
	var tables: Array[Dictionary] = []
	var obstacles: Array[Dictionary] = []
	var decor: Array[Dictionary] = []
	var basis := Basis(Vector3.UP,-PI*.5)
	for index: int in 6:
		var kind := &"slots" if index < 4 else &"video_poker"
		var at := Vector3(5.25,0,-3.5+index*1.4)/METRES
		var seat := at+basis*Vector3(0,0,1.05)/METRES
		var eye := seat+basis*Vector3(0,0,.8)/METRES+Vector3.UP*2.2/METRES
		var focus := at+Vector3.UP*1.25/METRES
		tables.append({"index":index, "game":kind,
			"prop":"slot_cabinet" if kind == &"slots" else "video_poker_terminal",
			"name":ResortThemes.game_name(key,kind), "pose":Transform3D(basis,at),
			"seat":seat, "camera":Transform3D(Basis.looking_at(focus-eye,Vector3.UP),eye),
			"count":1, "row":index+1 if kind == &"slots" else 0,
			"half":Vector2(.4,.35)/METRES, "signature":false})
		obstacles.append({"name":"machine %d" % index, "center":Vector2(at.x,at.z),
			"half":Vector2(.35,.4)/METRES, "kind":"prop"})
		if kind == &"video_poker":
			decor.append({"prop":"slot_stool", "pose":Transform3D(basis,seat), "solid":false})
	for row: Dictionary in FIXTURES:
		obstacles.append({"name":row.name, "center":row.at/METRES, "half":row.half/METRES, "kind":"architecture"})
	var signs: Array[Dictionary] = []
	for row: Array in [
		["store","DESPICABLE'S",Vector3(-3,2.8,-4.8),Vector2(4.8,.5)],
		["groceries","LOW-DOWN PRICES",Vector3(-3,2.25,-4.18),Vector2(4.0,.3)],
		["games","SLOTS & VIDEO POKER",Vector3(3,2.8,-4.8),Vector2(4.5,.42)],
		["limits","$1 MINIMUM / $1,000 MAXIMUM",Vector3(3,2.25,-4.8),Vector2(4.5,.32)],
	]:
		signs.append({"role":row[0], "text":row[1], "at":Transform3D(Basis.IDENTITY,row[2]/METRES), "size":row[3]/METRES})
	var art: Array[Dictionary] = []
	for row: Array in [
		["mural-history",Vector3(-3,2.08,4.78),Vector2(1.8,1.8)],
		["mural-industry",Vector3(-5.775,2.08,-2),Vector2(1.5,1.5)],
		["mural-heritage",Vector3(2.1,2.08,4.78),Vector2(1.8,1.8)],
	]:
		var yaw := PI*.5 if row[0] == "mural-industry" else PI
		art.append({"asset":row[0], "pose":Transform3D(Basis(Vector3.UP,yaw),row[1]), "size":row[2]})
	return {"key":key, "name":ResortThemes.resort_name(key), "floor":ResortThemes.floor_name(key),
		"pocket_y":-2.5, "bounds":AABB(Vector3(-6,-.32,-5)/METRES,Vector3(12,3.52,10)/METRES),
		"entrance":{"mat":Transform3D(Basis.IDENTITY,Vector3(0,0,4.15)/METRES), "facing":0.0},
		"door":Vector3(0,0,5)/METRES, "tables":tables, "obstacles":obstacles,
		"decor":decor, "chandeliers":[], "lights":[
			{"position":Vector3(-3,2.8,0)/METRES,"range":8.0/METRES,"energy":1.6,"role":"store"},
			{"position":Vector3(3,2.8,0)/METRES,"range":8.0/METRES,"energy":1.2,"role":"games"}],
		"signs":signs, "standards":[], "art":art,
		"slot_badge":{"position":Vector3(0,1.715,.204),"size":Vector2(.12,.12)}}
