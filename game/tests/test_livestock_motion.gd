# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const MOTION := "res://scripts/view/livestock_motion.gd"
var catalog := AgricultureAssetCatalog.new()
func before_all() -> void: check_eq(catalog.load_manifest("res://assets/agriculture/enclosures.json"),OK)
func motion(key: StringName = &"feedlot") -> RefCounted:
	check(ResourceLoader.exists(MOTION),"missing deterministic livestock motion")
	if not ResourceLoader.exists(MOTION): return null
	var result: RefCounted = load(MOTION).new()
	result.configure(catalog.profile(key),42)
	return result
func test_invalid_delta_and_seed_reconstruction() -> void:
	var m:=motion()
	if m==null:return
	var before: Array = m.states().duplicate(true)
	for delta: float in [NAN,INF,-INF,-1.0,0.0]:
		m.advance(delta)
		check_eq(m.states(),before)
	var other:=motion()
	for i:int in 100:m.advance(.05)
	m.configure(catalog.profile(&"feedlot"),42)
	check_eq(m.states(),other.states())
	var exposed: Array=m.states();exposed[0]["position"]=Vector3.INF
	check_eq(m.states(),other.states(),"state copies cannot corrupt controller")
func test_fixed_step_residual_and_bounded_five_second_delta() -> void:
	var a:=motion();var b:=motion()
	if a==null or b==null:return
	for i:int in 200:a.advance(.025)
	for i:int in 100:b.advance(.05)
	check_eq(a.states(),b.states(),"fixed updates reconstruct independent of render interval")
	a.configure(catalog.profile(&"feedlot"),42);b.configure(catalog.profile(&"feedlot"),42)
	a.advance(5.0)
	for i:int in 5:b.advance(.05)
	check_eq(a.states(),b.states(),"five seconds executes only five steps and drops backlog")
	a.advance(.01);b.advance(.01);check_eq(a.states(),b.states())
func test_swept_whole_body_pens_obstacles_and_pair_separation() -> void:
	for key:StringName in [&"cattle_range",&"sheep_pasture",&"dairy",&"feedlot"]:
		var m:=motion(key)
		if m==null:return
		var p:Dictionary=catalog.profile(key)
		var radius:float=p["body_radius"]+p["turn_margin"]
		var previous:Array=m.states()
		for tick:int in 1200:
			m.advance(5.0 if tick%40==0 else .05)
			var now:Array=m.states()
			for i:int in now.size():
				var state:Dictionary=now[i];var pos:Vector3=state["position"];var old:Vector3=previous[i]["position"]
				check_eq(state["pen_index"],previous[i]["pen_index"])
				check(pos.is_finite() and is_finite(state["heading"]))
				check(catalog.navigation_segment(Vector2(old.x,old.z),Vector2(pos.x,pos.z),p["pens"][state["pen_index"]],radius),"entire swept body stays clear: "+String(key))
				check_le_distance(old,pos,1.5*.25+.001)
				for j:int in i:
					for blend:float in [0.0,.25,.5,.75,1.0]:
						var q:Vector3=(previous[j]["position"] as Vector3).lerp(now[j]["position"],blend)
						check_ge(old.lerp(pos,blend).distance_to(q),2.0*p["body_radius"]-.001,"whole articulated bodies stay separate")
			previous=now
func check_le_distance(a:Vector3,b:Vector3,limit:float)->void:check(a.distance_to(b)<=limit,"bounded catchup displacement")
func test_independent_activities_phases_and_rng_isolation() -> void:
	var m:=motion(&"cattle_range")
	if m==null:return
	seed(991);var expected:=randi();seed(991)
	var city:=flat_city();var funds:=city.funds;var ctx:=make_context(city,17);var rng_before:Variant=ctx.rng.state()
	var seen:Dictionary={};var phases:Dictionary={}
	for state:Dictionary in m.states():phases[state["gait_phase"]]=true
	check_gt(phases.size(),1)
	for i:int in 5000:
		m.advance(.05)
		for state:Dictionary in m.states():seen[state["activity"]]=true
	for activity:String in ["idle","walk","graze","drink"]:check(seen.has(activity),"activity reachable: "+activity)
	check_eq(randi(),expected,"private cosmetic RNG only");check_eq(city.funds,funds);check_eq(ctx.rng.state(),rng_before)
func test_nearby_player_causes_yield_without_approach() -> void:
	var m:=motion(&"sheep_pasture")
	if m==null:return
	for i:int in 100:m.advance(.05)
	var state:Dictionary=m.states()[0];var player:Vector3=state["position"]+Vector3(.8,0,.8)
	var before:float=(state["position"] as Vector3).distance_to(player)
	for i:int in 10:m.advance(.05,player)
	check_ge((m.states()[0]["position"] as Vector3).distance_to(player),before-.001,"overlapping player pushes away, never deeper")
func test_catalog_adapters_are_pure_and_reject_divider_sweep() -> void:
	check(catalog.has_method("navigation_segment") and catalog.has_method("animal_profile"),"missing reviewed contract adapters")
	if not catalog.has_method("navigation_segment"):return
	var pen:Dictionary={"bounds":[-10,-10,10,10],"obstacles":[{"bounds":[-10,-.1,10,.1]}]}
	check(catalog.navigation_clear(Vector2(0,-5),pen,1.0))
	check(catalog.navigation_clear(Vector2(0,5),pen,1.0))
	check(not catalog.navigation_segment(Vector2(0,-5),Vector2(0,5),pen,1.0),"clear endpoints cannot teleport through divider")
	var p:Dictionary=catalog.animal_profile(&"sheep");p["pose_limits_degrees"].clear()
	check(not catalog.animal_profile(&"sheep")["pose_limits_degrees"].is_empty())

func test_individual_preferred_speeds_drive_displacement_and_distance_gait() -> void:
	seed(771);var expected_global:=randi();seed(771)
	var city:=flat_city();var ctx:=make_context(city,19);var shared:Variant=ctx.rng.state()
	var m:=motion();var twin:=motion()
	check_eq(m.states(),twin.states(),"same cosmetic seed reconstructs individual speeds")
	var preferred:Dictionary={};var observed:Dictionary={}
	for state:Dictionary in m.states():
		check(state.has("preferred_speed"),"missing stable per-animal preferred speed")
		if not state.has("preferred_speed"): continue
		check_ge(state.preferred_speed,.84);check(state.preferred_speed<=1.2)
		preferred[state.preferred_speed]=true
	check_gt(preferred.size(),1,"a herd must have different walking speeds")
	for tick:int in 200:
		var before:Array=m.get("_animals").duplicate(true)
		m.advance(.05);twin.advance(.05)
		var after:Array=m.get("_animals")
		for i:int in after.size():
			var moved:float=(after[i].position as Vector3).distance_to(before[i].position)
			check(moved<=1.2*.05+.00001)
			if not after[i].has("preferred_speed"): continue
			check_eq(after[i].preferred_speed,before[i].preferred_speed,"speed never jitters per frame")
			if moved>.001:
				check(after[i].speed<=after[i].preferred_speed+.0001,"single-precision displacement stays within preferred pace")
				if is_equal_approx(after[i].speed,after[i].preferred_speed):observed[after[i].preferred_speed]=true
			var gait_delta:float=fposmod(after[i].gait_phase-before[i].gait_phase,TAU)
			check(is_equal_approx(gait_delta,4.8*moved+.18*.05),"gait follows real displacement")
	check_gt(observed.size(),1,"multiple individual preferred speeds actually drive walking")
	check_eq(m.states(),twin.states());check_eq(randi(),expected_global);check_eq(ctx.rng.state(),shared)
