# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Street Names draws each segment along the street topology's centerline.
## Diagonal roads are drawn as straight strips between edge midpoints, so the
## centerline through their bends and confirmed junctions must be straight too.
extends "res://tests/test_case.gd"

const Junctions := preload("res://tests/test_diagonal_road_junctions.gd")
const CENTER := Vector2i(31,31)

static func stamp(city: City, cell: Vector2i, mask: int) -> void:
	city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))

## A north-east staircase: west approach, alternating 9/6 bends, north exit.
static func staircase(steps: int) -> Dictionary:
	var city := flat_city()
	var start := Vector2i(20,40)
	stamp(city,start,10)
	var bends: Array[Vector2i] = []
	var cell := start+Vector2i.RIGHT
	for i: int in steps:
		stamp(city,cell,9)
		bends.append(cell)
		stamp(city,cell+Vector2i.UP,6)
		bends.append(cell+Vector2i.UP)
		cell += Vector2i(1,-1)
	stamp(city,cell,10)
	return {"city":city,"bends":bends}

func test_diagonal_staircase_centerline_is_straight() -> void:
	var f := staircase(5)
	var bends: Array[Vector2i] = f.bends
	var cells: Dictionary = {}
	for cell: Vector2i in bends: cells[cell] = true
	var topology := StreetTopology.new()
	topology.rebuild(f.city)
	# Every bend's straight diagonal lies on one x + z line.
	var line := float(bends[0].x)+float(bends[0].y)+.5
	var checked := 0
	for segment: Dictionary in topology.segments({}):
		for p: Vector3 in segment.points:
			if not cells.has(Vector2i(floori(p.x),floori(p.z))): continue
			check_lt(absf(p.x+p.z-line),.00001,"bend centerline sample %s stays on the diagonal" % p)
			checked += 1
	check_gt(checked,bends.size()*4,"every bend was sampled")
	# The overlay strokes link points; each bend-to-bend link is one straight run.
	for i: int in range(1,bends.size()):
		var key := StreetTopology.link_key(bends[i-1],&"open",bends[i],&"open")
		check(topology.has_link(key),"staircase link "+key)
		var points := topology.connection_points(key)
		for p: Vector3 in points: check_lt(absf(p.x+p.z-line),.00001,key+" stays straight")

func test_diagonal_junction_centerline_matches_the_drawn_diagonal() -> void:
	for quarter: int in 4:
		for extra: int in [4,8,12]:
			var city := Junctions.fixture(quarter,extra)
			var mask := Junctions.mask_rotated(3|extra,quarter)
			var diagonal := Junctions.mask_rotated(3,quarter)
			for direction: int in 4:
				if mask&(1<<direction) and not diagonal&(1<<direction):
					stamp(city,CENTER+NetworkShapes.DIRECTIONS[direction],5 if direction%2==0 else 10)
			check_eq(CityNetworks3D.road_diagonal_mask(city,CENTER,mask),diagonal,"fixture junction is a confirmed diagonal")
			var topology := StreetTopology.new()
			topology.rebuild(city)
			var middle := Vector2(CENTER)+Junctions.rotated(Vector2(.75,.25),quarter)
			var first := Vector2(CENTER)+Junctions.rotated(Vector2(.5,0),quarter)
			var along := (Vector2(CENTER)+Junctions.rotated(Vector2(1,.5),quarter)-first).normalized()
			for direction: int in 4:
				if not mask&(1<<direction): continue
				var other := CENTER+NetworkShapes.DIRECTIONS[direction]
				var key := StreetTopology.link_key(CENTER,&"open",other,&"open")
				check(topology.has_link(key),"junction arm "+key)
				var points := topology.connection_points(key)
				if points.is_empty(): continue
				if Vector2i(floori(points[0].x),floori(points[0].z)) != CENTER: points.reverse()
				check_lt(Vector2(points[0].x,points[0].z).distance_to(middle),.00001,"every arm starts on the diagonal's midpoint")
				if diagonal&(1<<direction):
					for p: Vector3 in points:
						if Vector2i(floori(p.x),floori(p.z)) != CENTER: continue
						var offset := Vector2(p.x,p.z)-first
						check_lt(absf(offset.cross(along)),.00001,"diagonal arm %d follows the straight diagonal" % direction)

## Removing an anchoring bend two cells away changes a junction's diagonal; a
## partial rebuild must redraw it exactly as a full projection does.
func test_partial_rebuild_follows_distant_diagonal_changes() -> void:
	var city := Junctions.fixture()
	stamp(city,CENTER+Vector2i.UP,13)
	stamp(city,CENTER+Vector2i(-1,-1),7)
	stamp(city,CENTER+Vector2i(-1,-2),12)
	var topology := StreetTopology.new()
	topology.rebuild(city)
	check_eq(int(topology.open_node(CENTER).diagonal),3,"consecutive junctions confirm the diagonal")
	for code: int in [NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5),Buildings.NONE,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,12)]:
		city.building.putv(CENTER+Vector2i(-1,-2),code)
		topology.rebuild(city)
		var fresh := StreetTopology.new()
		fresh.rebuild(city)
		check_eq(topology._nodes,fresh._nodes,"nodes equal a fresh projection")
		check_eq(topology._links,fresh._links,"centerlines equal a fresh projection")
	check_eq(int(topology.open_node(CENTER).diagonal),3,"restored anchor restores the diagonal")
