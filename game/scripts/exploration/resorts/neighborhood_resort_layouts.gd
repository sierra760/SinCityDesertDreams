# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Compact neighborhood floors. Geometry and illustration poses are in metres
## in the authoring contract, returned in tiles except the explicit art quads.
extends RefCounted

const METRES := 16.0
## Machine props face local +Z; wall-side banks open toward the central aisles.
const ROWS := [
	{"game":&"blackjack","at":Vector3(-5,0,2),"yaw":-PI*.5,"seat":1.5,"count":1,"half":Vector2(1.3,.75)},
	{"game":&"roulette","at":Vector3(0,0,0),"yaw":0.0,"seat":1.45,"count":1,"half":Vector2(1.6,.8)},
	{"game":&"money_wheel","at":Vector3(5,0,-6),"yaw":PI,"seat":1.6,"count":1,"half":Vector2(1.5,.55)},
	{"game":&"video_poker","at":Vector3(7,0,2),"yaw":-PI*.5,"seat":1.05,"count":3,"half":Vector2(1.2,.35)},
	{"game":&"slots","at":Vector3(-9,0,-4),"yaw":PI*.5,"seat":1.05,"count":3,"half":Vector2(1.2,.35)},
	{"game":&"slots","at":Vector3(-9,0,5),"yaw":PI*.5,"seat":1.05,"count":3,"half":Vector2(1.2,.35)},
	{"game":&"signature","at":Vector3(-1,0,-6),"yaw":0.0,"seat":1.75,"count":1,"half":Vector2(1.5,.8)},
]
const GAME_PROPS := {&"blackjack":"blackjack_table",&"roulette":"roulette_table",&"money_wheel":"money_wheel",&"video_poker":"video_poker_terminal",&"slots":"slot_cabinet",&"faro":"faro_table",&"chuck_a_luck":"chuck_a_luck_cage",&"baccarat":"baccarat_table"}
const CHANDELIERS := {&"arcology_boddy":"chandelier_gaslamp",&"arcology_woolier":"chandelier_lantern",&"arcology_stockgrowers":"chandelier_lantern",&"arcology_fremont":"chandelier_gaslamp"}

static func architecture(key: StringName) -> Array[Dictionary]:
	var small := ResortThemes.building(key)<264
	var half := 12.0 if small else 18.0
	var rows: Array[Dictionary] = [
		{"name":"cage","at":Vector3(0,0,-half+1.5),"half":Vector2(3 if small else 4,.75),"height":2.5},
		{"name":"bar counter","at":Vector3(half-2,0,-4),"half":Vector2(.5,3),"height":1.1},
		{"name":"back bar","at":Vector3(half-.45,0,-4),"half":Vector2(.35,3),"height":3.0},
	]
	if key == &"arcology_woolier": rows.append({"name":"family dining","at":Vector3(7,0,7),"half":Vector2(2.2,1.5),"height":1.0})
	if key == &"arcology_stockgrowers": rows.append({"name":"auction display","at":Vector3(13,0,10),"half":Vector2(2,2),"height":1.2})
	if key == &"arcology_fremont": rows.append({"name":"fountain","at":Vector3(12,0,10),"half":Vector2(1.4,1.4),"height":1.0})
	return rows

static func layout(key: StringName) -> Dictionary:
	if not CHANDELIERS.has(key): return {}
	var small := ResortThemes.building(key)<264
	var half := 12.0 if small else 18.0
	var ceiling := 6.0 if small else 8.0
	var signature := ResortThemes.signature(key)
	var tables: Array[Dictionary] = []
	var obstacles: Array[Dictionary] = []
	var standards: Array[Dictionary] = []
	for i: int in ROWS.size():
		var row: Dictionary = ROWS[i]
		var game: StringName = signature if row.game == &"signature" else row.game
		var basis := Basis(Vector3.UP,float(row.yaw))
		var at: Vector3 = row.at/METRES
		var facing := basis*Vector3.FORWARD
		var seat: Vector3 = at-facing*float(row.seat)/METRES
		var bank := int(row.count)>1
		var eye := seat-facing*(.8 if bank else 1.7)/METRES+Vector3.UP*(2.2 if bank else 2.5)/METRES
		var focus := at+Vector3.UP*(1.25 if bank else .85)/METRES
		var half_size: Vector2 = row.half/METRES
		tables.append({"index":i,"game":game,"prop":GAME_PROPS[game],"name":ResortThemes.game_name(key,game),
			"pose":Transform3D(basis,at),"seat":seat,"camera":Transform3D(Basis.looking_at(focus-eye,Vector3.UP),eye),
			"count":int(row.count),"row":i+1 if game == &"slots" else 0,"half":half_size,"signature":game==signature})
		var x := basis*Vector3(half_size.x,0,0)
		var z := basis*Vector3(0,0,half_size.y)
		obstacles.append({"name":String(game)+" %d"%i,"center":Vector2(at.x,at.z),"half":Vector2(absf(x.x)+absf(z.x),absf(x.z)+absf(z.z)),"kind":"prop"})
		if game != &"slots":
			standards.append({"pose":Transform3D(basis,at+basis*Vector3(half_size.x+.55/METRES,0,half_size.y*.2)),
				"text":ResortThemes.game_name(key,game),"minimum":int(CasinoParams.TABLE_LIMITS[key].minimum),"game":game,"minimum_word":"MINIMUM"})
	for row: Dictionary in architecture(key):
		obstacles.append({"name":row.name,"center":Vector2(row.at.x,row.at.z)/METRES,"half":row.half/METRES,"kind":"architecture"})
	var lights: Array[Dictionary] = []
	for pos: Vector3 in [Vector3(0,ceiling-1,0),Vector3(-7,ceiling-1,3),Vector3(7,ceiling-1,5),Vector3(0,3,half+2)]:
		lights.append({"position":pos/METRES,"range":14.0/METRES,"energy":1.6,"role":"floor"})
	var signs: Array[Dictionary] = []
	for row: Array in [["floor",ResortThemes.floor_name(key),Vector3(0,3.25,half+.08),Vector2(5.4,.6),0.0],
		["resort",ResortThemes.resort_name(key),Vector3(0,4.7,half-.03),Vector2(8,1.0),PI],
		["cage","Cashier",Vector3(0,3.0,-half+2.28),Vector2(4,.6),0.0],
		["bar","Dining & Bar" if key==&"arcology_woolier" else "Bar & Lounge",Vector3(half-.8,3.4,-4),Vector2(5,.6),-PI*.5]]:
		signs.append({"role":row[0],"text":String(row[1]).to_upper(),"at":Transform3D(Basis(Vector3.UP,row[4]),row[2]/METRES),"size":row[3]/METRES})
	var art: Array[Dictionary] = []
	for row: Array in [["mural-history",Vector3(-7,3.8,half-.12),PI],["mural-industry",Vector3(7,3.8,half-.12),PI],["mural-heritage",Vector3(-half+.12,3.8,-7),PI*.5]]:
		art.append({"asset":row[0],"pose":Transform3D(Basis(Vector3.UP,row[2]),row[1]),"size":Vector2(2.4,2.4)})
	return {"key":key,"name":ResortThemes.resort_name(key),"floor":ResortThemes.floor_name(key),"pocket_y":-2.5,
		"bounds":AABB(Vector3(-half,-.32,-half)/METRES,Vector3(half*2,ceiling+.32,half*2+5)/METRES),
		"entrance":{"mat":Transform3D(Basis.IDENTITY,Vector3(0,0,half+2.5)/METRES),"facing":0.0},
		"door":Vector3(0,0,half+5)/METRES,"floor_front":(half-.7)/METRES,"patron_count":6 if small else 8,
		"tables":tables,"obstacles":obstacles,"decor":[],"chandeliers":[{"prop":CHANDELIERS[key],"pose":Transform3D(Basis.IDENTITY,Vector3(0,ceiling,0)/METRES)}],
		"lights":lights,"signs":signs,"standards":standards,"art":art,
		"slot_badge":{"position":Vector3(0,1.715,.204),"size":Vector2(.12,.12)}}
