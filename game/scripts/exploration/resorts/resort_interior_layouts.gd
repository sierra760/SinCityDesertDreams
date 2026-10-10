# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Floor plans of the ten gaming resort casino floors.
##
## Every hall shares one program (a 44 m square floor, an 11 m ceiling, a
## vestibule at the front, the cage on the back wall, the bar on the east wall
## and the signature game on a dais) and differs in architecture, finishes,
## chandeliers and lettering. Plans are authored in hall metres and returned
## in tile units (1 tile = 16 m), local to the hall's floor centre: +X east,
## +Y up, +Z toward the door, which faces the street (world +Z). The hall
## architecture in the resort GLBs uses the same numbers; the props, lights,
## signs and seats come from here. Names, fonts and palettes come from
## ResortThemes.
class_name ResortInteriorLayouts
extends RefCounted

const METRES_PER_TILE := 16.0
## World height of every hall floor, in tile units: below any city terrain.
const POCKET_Y := -2.5
## Half the clear hall floor (22 m) and the main ceiling height (11 m).
const HALF := 22.0/METRES_PER_TILE
const CEILING := 11.0/METRES_PER_TILE
## The vestibule: 10 m wide, 8 m deep, beyond the hall's front wall.
const VESTIBULE_HALF_WIDTH := 5.0/METRES_PER_TILE
const VESTIBULE_END := 30.0/METRES_PER_TILE
const VESTIBULE_CEILING := 4.5/METRES_PER_TILE
const DAIS_HEIGHT := .3/METRES_PER_TILE
## Interior volume used for containment, slightly inside the walls.
const POCKET_BOUNDS := AABB(Vector3(-HALF,-.02,-HALF),Vector3(HALF*2.0,CEILING+.02,HALF+VESTIBULE_END))
## Distances, in tile units, at which the door and a seat offer their prompt.
const DOOR_REACH := .16
const SEAT_REACH := .14

const BUILDINGS := {126: &"com_corner_store", 251: &"arcology_comstock", 252: &"arcology_junction", 253: &"arcology_boulder", 254: &"arcology_orbit", 256: &"arcology_fix", 257: &"arcology_alibi", 258: &"arcology_velvet", 259: &"arcology_afterglow", 260: &"arcology_last", 261: &"arcology_dust"}
const SIGNATURE_PROPS := {&"faro": "faro_table", &"chuck_a_luck": "chuck_a_luck_cage",
	&"baccarat": "baccarat_table", &"trajectory": "trajectory_console",
	&"vault_circuit": "vault_table", &"alibi_route": "route_table", &"velvet_encore": "encore_table", &"afterglow_forecast": "forecast_console", &"last_bank": "contract_table", &"dust_pool": "common_pot_table"}
const GAME_PROPS := {&"blackjack": "blackjack_table", &"roulette": "roulette_table",
	&"slots": "slot_cabinet", &"money_wheel": "money_wheel", &"video_poker": "video_poker_terminal"}
## Font files for each theme font key; every sign character is in its font.
const FONTS := {"fontdiner": "res://assets/fonts/fontdiner-swanky/FontdinerSwanky-Regular.ttf",
	"biorhyme": "res://assets/fonts/biorhyme/BioRhyme-Medium.ttf",
	"biorhyme_expanded": "res://assets/fonts/biorhyme-expanded/BioRhymeExpanded-Regular.ttf",
	"atomic_age": "res://assets/fonts/atomic-age/AtomicAge-Regular.ttf"}

const CHANDELIERS := {&"arcology_comstock": "chandelier_gaslamp", &"arcology_junction": "chandelier_lantern",
	&"arcology_boulder": "chandelier_turbine", &"arcology_orbit": "chandelier_starburst", &"arcology_fix": "chandelier_turbine", &"arcology_alibi": "chandelier_gaslamp", &"arcology_velvet": "chandelier_gaslamp", &"arcology_afterglow": "chandelier_starburst", &"arcology_last": "chandelier_lantern", &"arcology_dust": "chandelier_starburst"}

## Pit and bank placements in hall metres: game, table centre, yaw (the
## direction the seated player faces is the prop's -Z turned by yaw), seat
## distance in front of the table, count for banks, half footprint and, for
## the two faces of one double-sided slot row, the row number.
## The pit is a ring around the roulette dais under the main chandelier.
const PIT := Vector2(0,2)
const SLOT_ROWS := [Vector2(-19,-5),Vector2(-14,-5),Vector2(-19,6),Vector2(-14,6)]
const _PIT_TABLES := [
	{"game": &"blackjack", "at": Vector3(-8,0,2), "yaw": -PI*.5, "seat": 1.5, "count": 1, "half": Vector2(1.3,.75)},
	{"game": &"blackjack", "at": Vector3(8,0,2), "yaw": PI*.5, "seat": 1.5, "count": 1, "half": Vector2(1.3,.75)},
	{"game": &"blackjack", "at": Vector3(0,0,10), "yaw": 0.0, "seat": 1.5, "count": 1, "half": Vector2(1.3,.75)},
	{"game": &"roulette", "at": Vector3(0,.15,2), "yaw": 0.0, "seat": 1.45, "count": 1, "half": Vector2(1.6,.8)},
	{"game": &"money_wheel", "at": Vector3(0,0,-6), "yaw": PI, "seat": 1.6, "count": 1, "half": Vector2(1.5,.55)},
	{"game": &"video_poker", "at": Vector3(12,0,-4), "yaw": PI*.5, "seat": 1.05, "count": 4, "half": Vector2(1.6,.35)},
	{"game": &"video_poker", "at": Vector3(12,0,4), "yaw": PI*.5, "seat": 1.05, "count": 4, "half": Vector2(1.6,.35)},
]
const _SIGNATURE := {"game": &"signature", "at": Vector3(0,.3,-11.5), "yaw": 0.0, "seat": 1.75, "count": 1, "half": Vector2(1.5,.8)}
## Architecture that blocks walking, in hall metres (centre, half size,
## height); the hall GLBs carry matching collision shells.
const ARCHITECTURE := [
	{"name": "cage", "at": Vector3(0,0,-20.25), "half": Vector2(6,1.75), "height": 3.6},
	{"name": "bar counter", "at": Vector3(17.6,0,-3), "half": Vector2(.6,9), "height": 1.1},
	{"name": "back bar", "at": Vector3(21.6,0,-3), "half": Vector2(.4,9), "height": 3.2},
	{"name": "column", "at": Vector3(-11,0,-10), "half": Vector2(.6,.6), "height": 11.0},
	{"name": "column", "at": Vector3(11,0,-10), "half": Vector2(.6,.6), "height": 11.0},
	{"name": "column", "at": Vector3(-11,0,12), "half": Vector2(.6,.6), "height": 11.0},
	{"name": "column", "at": Vector3(11,0,12), "half": Vector2(.6,.6), "height": 11.0},
	{"name": "bandstand", "at": Vector3(-18.5,0,18), "half": Vector2(3,3), "height": 1.7},
	{"name": "planter", "at": Vector3(-7.5,0,20.3), "half": Vector2(.6,.6), "height": .9},
	{"name": "planter", "at": Vector3(7.5,0,20.3), "half": Vector2(.6,.6), "height": .9},
	{"name": "planter", "at": Vector3(-10,0,-20.3), "half": Vector2(.6,.6), "height": .9},
	{"name": "planter", "at": Vector3(10,0,-20.3), "half": Vector2(.6,.6), "height": .9},
	{"name": "planter", "at": Vector3(20.3,0,-16), "half": Vector2(.6,.6), "height": .9},
	{"name": "planter", "at": Vector3(-20.3,0,-16), "half": Vector2(.6,.6), "height": .9},
	{"name": "lounge", "at": Vector3(17.2,0,18.3), "half": Vector2(.42,.42), "height": .8},
	{"name": "lounge", "at": Vector3(18.6,0,15.0), "half": Vector2(.42,.42), "height": .8},
]
## Lounge banquettes, in hall metres: an L of four in the front-east corner.
const LOUNGE := [
	{"prop": "banquette", "at": Vector3(16.0,0,21.45), "yaw": PI, "half": Vector2(1.8,.55)},
	{"prop": "banquette", "at": Vector3(19.7,0,21.45), "yaw": PI, "half": Vector2(1.8,.55)},
	{"prop": "banquette", "at": Vector3(21.45,0,17.6), "yaw": -PI*.5, "half": Vector2(1.8,.55)},
	{"prop": "banquette", "at": Vector3(21.45,0,13.9), "yaw": -PI*.5, "half": Vector2(1.8,.55)},
]
const BAR_STOOLS := [-10.0,-8.0,-6.0,-4.0,-2.0,0.0,2.0,4.0]
## Dais of the signature game, in hall metres (walkable, 0.3 m high).
const DAIS := {"at": Vector3(0,0,-11.5), "half": Vector2(6,3.5)}
## Chandeliers (hall metres, x and z): the pit, the dais, the slot aisle and the lounge.
const CHANDELIER_SPOTS := [Vector2(0,2),Vector2(0,-11.5),Vector2(-16.5,.5),Vector2(17.6,16.7)]
## Omni lights (hall metres): warm pools under the chandeliers carry the pit.
const LIGHTS := [
	{"at": Vector3(0,7.5,2), "range": 16.0, "energy": 2.6, "role": "pit"},
	{"at": Vector3(0,6.5,-12), "range": 12.0, "energy": 1.8, "role": "dais"},
	{"at": Vector3(17,4.5,-3), "range": 12.0, "energy": 1.4, "role": "bar"},
	{"at": Vector3(-16.5,6.5,.5), "range": 15.0, "energy": 1.8, "role": "slots"},
	{"at": Vector3(17.6,4.0,16.7), "range": 9.0, "energy": 1.3, "role": "lounge"},
	{"at": Vector3(0,4.2,17), "range": 11.0, "energy": 1.3, "role": "front"},
]

## Every table row: the pit, both faces of each double-sided slot row, then
## the signature game last.
static func _table_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in _PIT_TABLES: rows.append(row)
	for index: int in SLOT_ROWS.size():
		var at: Vector2 = SLOT_ROWS[index]
		for side: float in [-1.0,1.0]:
			rows.append({"game": &"slots", "at": Vector3(at.x+side*.35,0,at.y), "yaw": side*PI*.5, "seat": 1.05,
				"count": 6, "half": Vector2(2.4,.35), "row": index+1})
	rows.append(_SIGNATURE)
	return rows

static var _cache: Dictionary = {}

## Resort keys in building order.
static func keys() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: StringName in ResortThemes.keys(): result.append(key)
	return result

static func key_for_building(code: int) -> StringName:
	return BUILDINGS.get(code,&"")

## Theme record for `key` from ResortThemes (names, font, signature, games
## and palette as Colors) plus the hall's chandelier; {} for an unknown key.
static func theme(key: StringName) -> Dictionary:
	var source := ResortThemes.theme(key)
	if key == ResortThemes.STORE_KEY: return source
	if source.is_empty() or not CHANDELIERS.has(key): return {}
	var result := source.duplicate(true)
	result.chandelier = CHANDELIERS[key]
	return result

static func game_name(key: StringName, game: StringName) -> String:
	var games: Dictionary = theme(key).get("games",{})
	return String(games.get(game,String(game).capitalize()))

static func font_path(key: StringName) -> String:
	return String(FONTS.get(String(theme(key).get("font","biorhyme")),FONTS.biorhyme))

## Table minimum for the resort, from the casino limits.
static func minimum(key: StringName) -> int:
	var limits: Dictionary = CasinoParams.TABLE_LIMITS.get(key,{})
	return int(limits.get("minimum",0))

## Sign lettering case: capitals, except in Atomic Age, whose capital I
## reads poorly at a distance; those signs keep the authored title case.
static func lettering(key: StringName, text: String) -> String:
	return text if String(theme(key).get("font","")) == "atomic_age" else text.to_upper()

static func _tiles(metres: Vector3) -> Vector3:
	return metres/METRES_PER_TILE

## The complete plan for one resort, in tile units local to the hall floor
## centre. Cached; callers must not modify it.
static func layout(key: StringName) -> Dictionary:
	if _cache.has(key): return _cache[key]
	if key == ResortThemes.STORE_KEY:
		var store := preload("res://scripts/exploration/resorts/despicables_interior_layout.gd").layout()
		_cache[key] = store
		return store
	var look := theme(key)
	if look.is_empty(): return {}
	var signature: StringName = look.signature
	var tables: Array[Dictionary] = []
	var table_rows := _table_rows()
	for index: int in table_rows.size():
		var row: Dictionary = table_rows[index]
		var game: StringName = row.game
		if game == &"signature": game = signature
		var basis := Basis(Vector3.UP,float(row.yaw))
		var at := _tiles(row.at)
		var floor_y := at.y
		var facing := basis*Vector3.FORWARD
		var seat := at-facing*float(row.seat)/METRES_PER_TILE
		seat.y = floor_y
		var bank := int(row.count)>1
		# Seated view: behind and above the seat, looking at the play surface.
		# Banks stand in narrow aisles: their view stays closer to the seat.
		var eye := seat-facing*((.8 if bank else 1.7)/METRES_PER_TILE)+Vector3.UP*((2.2 if bank else 2.5)/METRES_PER_TILE)
		var focus := at+Vector3.UP*((1.25 if bank else .85)/METRES_PER_TILE)
		var camera := Transform3D(Basis.looking_at(focus-eye,Vector3.UP),eye)
		tables.append({"index": index, "game": game,
			"prop": String(SIGNATURE_PROPS.get(game,GAME_PROPS.get(game,""))),
			"name": game_name(key,game), "pose": Transform3D(basis,at), "seat": seat,
			"camera": camera, "count": int(row.count), "row": int(row.get("row",0)),
			"half": Vector2(row.half)/METRES_PER_TILE, "signature": game == signature})
	var obstacles: Array[Dictionary] = []
	for table: Dictionary in tables:
		obstacles.append({"name": String(table.game) if int(table.row)==0 else "slots row %d" % int(table.row), "center": Vector2(table.pose.origin.x,table.pose.origin.z),
			"half": _turned(table.half,table.pose.basis), "kind": "prop"})
	for row: Dictionary in ARCHITECTURE:
		obstacles.append({"name": String(row.name), "center": Vector2(row.at.x,row.at.z)/METRES_PER_TILE,
			"half": Vector2(row.half)/METRES_PER_TILE, "kind": "architecture"})
	var decor: Array[Dictionary] = []
	for row: Dictionary in LOUNGE:
		var basis := Basis(Vector3.UP,float(row.yaw))
		decor.append({"prop": String(row.prop), "pose": Transform3D(basis,_tiles(row.at)), "solid": true})
		obstacles.append({"name": "lounge", "center": Vector2(row.at.x,row.at.z)/METRES_PER_TILE,
			"half": _turned(Vector2(row.half)/METRES_PER_TILE,basis), "kind": "lounge"})
	# Bar stools along the counter and stools before every slot cabinet.
	for z: float in BAR_STOOLS:
		decor.append({"prop": "bar_stool", "pose": Transform3D(Basis(Vector3.UP,PI*.5),_tiles(Vector3(16.35,0,z))), "solid": false})
	var chandelier := String(look.chandelier)
	var lamps: Array[Dictionary] = []
	for spot: Vector2 in CHANDELIER_SPOTS:
		lamps.append({"prop": chandelier, "pose": Transform3D(Basis.IDENTITY,_tiles(Vector3(spot.x,CEILING*METRES_PER_TILE,spot.y)))})
	var lights: Array[Dictionary] = []
	for row: Dictionary in LIGHTS:
		lights.append({"position": _tiles(row.at), "range": float(row.range)/METRES_PER_TILE,
			"energy": float(row.energy), "role": String(row.role)})
	var signs: Array[Dictionary] = []
	# Floor name over the vestibule opening, facing the arriving player.
	signs.append({"role": "floor", "text": lettering(key,String(look.floor)),
		"at": Transform3D(Basis.IDENTITY,_tiles(Vector3(0,4.05,22.62))), "size": Vector2(9.0,.75)/METRES_PER_TILE})
	# Resort name inside the hall above the opening, facing the floor.
	signs.append({"role": "resort", "text": lettering(key,String(look.name)),
		"at": Transform3D(Basis(Vector3.UP,PI),_tiles(Vector3(0,6.2,21.97))), "size": Vector2(14.0,1.6)/METRES_PER_TILE})
	signs.append({"role": "cage", "text": lettering(key,"Cashier"),
		"at": Transform3D(Basis.IDENTITY,_tiles(Vector3(0,4.3,-18.45))), "size": Vector2(6.0,.9)/METRES_PER_TILE})
	signs.append({"role": "bar", "text": lettering(key,"Bar & Lounge"),
		"at": Transform3D(Basis(Vector3.UP,-PI*.5),_tiles(Vector3(21.18,3.75,-3))), "size": Vector2(8.0,.8)/METRES_PER_TILE})
	# A table-name standard beside every pit game, turned toward its seat.
	var standards: Array[Dictionary] = []
	for table: Dictionary in tables:
		if int(table.count)>6 or table.game == &"slots": continue
		var side := Vector3.RIGHT*(float(table.half.x)+.55/METRES_PER_TILE)
		var front := Vector3.BACK*(float(table.half.y)*.2)
		var origin: Vector3 = table.pose*(side+front)
		standards.append({"pose": Transform3D(table.pose.basis,origin), "text": String(table.name),
			"minimum": minimum(key), "game": table.game, "minimum_word": lettering(key,"minimum")})
	var mat := Transform3D(Basis.IDENTITY,_tiles(Vector3(0,0,26.5)))
	var plan := {"key": key, "name": String(look.name), "floor": String(look.floor),
		"pocket_y": POCKET_Y, "bounds": POCKET_BOUNDS, "entrance": {"mat": mat, "facing": 0.0},
		"door": _tiles(Vector3(0,0,30.0)), "tables": tables, "obstacles": obstacles,
		"decor": decor, "chandeliers": lamps, "lights": lights, "signs": signs, "standards": standards,
		"dais": {"center": Vector2(DAIS.at.x,DAIS.at.z)/METRES_PER_TILE, "half": Vector2(DAIS.half)/METRES_PER_TILE,
			"height": DAIS_HEIGHT}}
	if ResortThemes.building(key)>=256:
		plan["slot_badge"] = {"position":Vector3(0,1.715,.204),"size":Vector2(.12,.12)}
	_cache[key] = plan
	return plan

static func _turned(half: Vector2, basis: Basis) -> Vector2:
	var x := basis*Vector3(half.x,0,0)
	var z := basis*Vector3(0,0,half.y)
	return Vector2(absf(x.x)+absf(z.x),absf(x.z)+absf(z.z))

## Lot centre (hall origin) in world tile units for a resort anchor.
static func hall_origin(anchor: Vector2i, code: int = 251) -> Vector3:
	var half := Vector2(Buildings.size(code))*.5
	return Vector3(anchor.x+half.x,POCKET_Y,anchor.y+half.y)

static func clear_cache() -> void:
	_cache.clear()
