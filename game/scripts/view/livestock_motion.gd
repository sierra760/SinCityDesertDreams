# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name LivestockMotion
extends RefCounted
## Cosmetic metre-space controller. Never reads the city or its random streams.
## Interpolation is between two collision-checked snapshots, never extrapolation.
const STEP := .05
const MAX_SUBSTEPS := 5
const WALK_SPEED := 1.2
# Stable individual pace, 70–100% of the existing maximum (metres/second).
const MIN_WALK_SPEED := WALK_SPEED * .7
const PLAYER_RADIUS := .4
var _catalog := AgricultureAssetCatalog.new()
var _rng := RandomNumberGenerator.new()
var _profile: Dictionary = {}
var _animals: Array[Dictionary] = []
var _previous: Array[Dictionary] = []
var _graphs: Array[AStar2D] = []
var _residual := 0.0
var _radius := 0.0

func configure(profile: Dictionary, seed_value: int) -> void:
	_profile=profile.duplicate(true)
	_animals.clear();_previous.clear();_graphs.clear();_residual=0.0
	_rng.seed=seed_value
	if profile.is_empty():return
	_radius=float(profile["body_radius"])+float(profile["turn_margin"])
	for pen_index:int in _profile["pens"].size():
		var pen:Dictionary=_profile["pens"][pen_index]
		_graphs.append(_graph(pen))
		for spawn:Array in pen["spawns"]:
			_animals.append({"position":Vector3(spawn[0],pen["ground_y"],spawn[1]),"heading":_rng.randf_range(-PI,PI),"speed":0.0,"preferred_speed":_rng.randf_range(MIN_WALK_SPEED,WALK_SPEED),"activity":"idle","gait_phase":_rng.randf()*TAU,"species":profile["species"],"pen_index":pen_index,"timer":_rng.randf_range(.2,4.0),"stage":0,"route":PackedVector2Array(),"blocked":0.0})
	_previous=_animals.duplicate(true)

func advance(delta: float, player_local: Vector3 = Vector3.INF) -> void:
	if not is_finite(delta) or delta<=0.0 or _animals.is_empty():return
	# Drop excess wall time before adding it: even a finite DBL_MAX cannot overflow.
	_residual+=minf(delta,STEP*MAX_SUBSTEPS)
	var steps:=mini(int(floor((_residual+.000000001)/STEP)),MAX_SUBSTEPS)
	_residual=maxf(0.0,_residual-steps*STEP)
	if _residual>=STEP:_residual=fmod(_residual,STEP)
	for tick:int in steps:
		_previous=_animals.duplicate(true)
		for i:int in _animals.size():_tick(i,player_local)

func states() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var alpha:=clampf(_residual/STEP,0.0,1.0)
	for i:int in _animals.size():
		var state:Dictionary=_animals[i].duplicate(true)
		state["position"]=(_previous[i]["position"] as Vector3).lerp(state["position"],alpha)
		state["heading"]=lerp_angle(_previous[i]["heading"],state["heading"],alpha)
		state["gait_phase"]=lerp_angle(_previous[i]["gait_phase"],state["gait_phase"],alpha)
		for field:String in ["timer","stage","route","blocked"]:state.erase(field)
		result.append(state)
	return result

func _graph(pen:Dictionary)->AStar2D:
	var graph:=AStar2D.new();var cells:Dictionary={};var b:Array=pen["navigation_bounds"]
	for z:int in range(ceili(b[1]),floori(b[3])+1):
		for x:int in range(ceili(b[0]),floori(b[2])+1):
			var point:=Vector2(x,z)
			if _catalog.navigation_clear(point,pen,_radius):
				var id:=graph.get_point_count();graph.add_point(id,point);cells[Vector2i(x,z)]=id
	for cell:Vector2i in cells:
		for offset:Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
			if cells.has(cell+offset) and _catalog.navigation_segment(Vector2(cell),Vector2(cell+offset),pen,_radius):graph.connect_points(cells[cell],cells[cell+offset])
	return graph

func _route(from:Vector2,to:Vector2,pen_index:int)->PackedVector2Array:
	var pen:Dictionary=_profile["pens"][pen_index]
	if _catalog.navigation_segment(from,to,pen,_radius):return PackedVector2Array([to])
	var graph:=_graphs[pen_index];var a:=-1;var b:=-1;var da:=INF;var db:=INF
	for id:int in graph.get_point_ids():
		var p:=graph.get_point_position(id)
		var d:=from.distance_squared_to(p)
		if d<da and _catalog.navigation_segment(from,p,pen,_radius):a=id;da=d
		d=to.distance_squared_to(p)
		if d<db and _catalog.navigation_segment(to,p,pen,_radius):b=id;db=d
	if a<0 or b<0:return PackedVector2Array()
	var path:=graph.get_point_path(a,b)
	if not path.is_empty():path.append(to)
	return path

func _choose_route(a:Dictionary)->void:
	var pen_index:int=a["pen_index"];var pen:Dictionary=_profile["pens"][pen_index]
	var stage:int=a["stage"]%3;var target:=Vector2.ZERO
	if stage<2:
		var targets:Array=pen["feed_targets" if stage==0 else "drink_targets"]
		var t:Array=targets[_rng.randi_range(0,targets.size()-1)];target=Vector2(t[0],t[1])
	else:
		var graph:=_graphs[pen_index]
		if graph.get_point_count()==0:return
		target=graph.get_point_position(_rng.randi_range(0,graph.get_point_count()-1))
	a["route"]=_route(_xz(a["position"]),target,pen_index)
	a["activity"]="walk";a["blocked"]=0.0

func _tick(index:int,player:Vector3)->void:
	var a:Dictionary=_animals[index];var old:=_xz(a["position"])
	a["speed"]=0.0;a["timer"]-=STEP
	var nearby:=player.is_finite() and old.distance_to(_xz(player))<_radius+PLAYER_RADIUS+1.3
	if a["activity"]!="walk" and a["timer"]<=0.0:_choose_route(a)
	var desired:=Vector2.ZERO
	var path:PackedVector2Array=a["route"]
	if nearby:
		desired=(old-_xz(player)).normalized()
		if desired==Vector2.ZERO:desired=Vector2(sin(a["heading"]),cos(a["heading"]))
	elif a["activity"]=="walk":
		while not path.is_empty() and old.distance_to(path[0])<.08:path.remove_at(0)
		a["route"]=path
		if path.is_empty():
			a["activity"]=["graze","drink","idle"][a["stage"]%3];a["stage"]+=1;a["timer"]=_rng.randf_range(2.0,5.0)
		else:desired=(path[0]-old).normalized()
	if desired!=Vector2.ZERO:
		var accepted:=old
		# Side-steer when another animal occupies the route, then retry the target.
		for angle:float in [0.0,.6,-.6,1.2,-1.2]:
			var distance:float=a["preferred_speed"]*STEP
			if not nearby and not path.is_empty():distance=minf(distance,old.distance_to(path[0]))
			var candidate:=old+desired.rotated(angle)*distance
			if _safe(index,old,candidate,player):accepted=candidate;break
		if accepted!=old:
			var direction:=accepted-old;a["position"]=Vector3(accepted.x,a["position"].y,accepted.y)
			a["heading"]=lerp_angle(a["heading"],atan2(direction.x,direction.y),.18)
			a["speed"]=direction.length()/STEP;a["activity"]="walk";a["blocked"]=0.0
		else:
			a["blocked"]+=STEP
			if a["blocked"]>2.0:
				# A temporarily occupied target is retried after a private wandering route.
				a["stage"]=2;_choose_route(a)
	a["gait_phase"]=fposmod(a["gait_phase"]+STEP*(4.8*a["speed"]+.18),TAU)

func _safe(index:int,from:Vector2,to:Vector2,player:Vector3)->bool:
	var a:Dictionary=_animals[index]
	if not _catalog.navigation_segment(from,to,_profile["pens"][a["pen_index"]],_radius):return false
	for j:int in _animals.size():
		if j==index:continue
		# Compare complete swept capsules. This also protects residual interpolation.
		var other_from:=_xz(_previous[j]["position"]);var other_to:=_xz(_animals[j]["position"])
		var closest:=Geometry2D.get_closest_points_between_segments(from,to,other_from,other_to)
		if closest[0].distance_to(closest[1])<2.0*float(_profile["body_radius"])+.04:return false
	if player.is_finite():
		var p:=_xz(player);var distance:=from.distance_to(p);var clearance:=_radius+PLAYER_RADIUS
		if distance<clearance:
			if to.distance_to(p)<distance+.00001:return false
		elif Geometry2D.get_closest_point_to_segment(p,from,to).distance_to(p)<clearance:return false
	return true

func _xz(point:Vector3)->Vector2:return Vector2(point.x,point.z)
