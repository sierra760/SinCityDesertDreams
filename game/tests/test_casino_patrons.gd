# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Casino visitors must walk, play, keep furniture/player seats clear and use
## only the occupied hall's session clock. Omitting the crowd fails this suite.
extends "res://tests/exploration/async_test_case.gd"

var hall: ResortInteriorWorld3D

func after_each() -> void:
	if is_instance_valid(hall): hall.free()

func _build(key: StringName = &"arcology_comstock", anchor: Vector2i = Vector2i(20,20)) -> Node:
	hall = ResortInteriorWorld3D.new()
	root.add_child(hall)
	hall.build(key,ResortThemes.building(key),anchor)
	hall.set_attendance(24)
	var crowd := hall.get_node_or_null("Patrons")
	check(crowd != null,"the casino floor has other patrons")
	return crowd

func test_every_casino_has_varied_visible_patrons() -> void:
	var keys := ResortInteriorLayouts.keys()
	keys.append(ResortThemes.STORE_KEY)
	for key: StringName in keys:
		var crowd := _build(key)
		if crowd == null: return
		var states: Array = crowd.call("states")
		check_eq(states.size(),int(hall.plan.get("patron_count",3 if key == ResortThemes.STORE_KEY else 16)),"full but bounded population")
		var variants := {}
		var playing := 0
		for state: Dictionary in states:
			variants[state.variant] = true
			if state.mode == "playing": playing += 1
		check_gt(variants.size(),1,"different people")
		check_gt(playing,0,"the hall starts with people at games")
		for mesh: MeshInstance3D in crowd.find_children("*","MeshInstance3D",true,false):
			check_eq(mesh.layers,1<<20,"patrons are lit on the interior layer")
		hall.free()
		hall = null

func test_visitors_walk_and_play_without_crossing_furniture_or_player_seats() -> void:
	var keys := ResortInteriorLayouts.keys()
	keys.append(ResortThemes.STORE_KEY)
	for key: StringName in keys:
		var crowd := _build(key)
		if crowd == null: return
		var before: Array = crowd.call("states")
		var games := {}
		var walked := false
		for tick: int in 900:
			crowd.call("step",.1,Vector3(100,0,100))
			var states: Array = crowd.call("states")
			for i: int in states.size():
				var state: Dictionary = states[i]
				var point := Vector2(state.position.x,state.position.z)
				check(hall.plan.bounds.has_point(state.position),"visitor stays inside")
				for obstacle: Dictionary in hall.plan.obstacles:
					var box := Rect2(Vector2(obstacle.center)-Vector2(obstacle.half),Vector2(obstacle.half)*2).grow(.018)
					check(not box.has_point(point),"visitor clears "+String(obstacle.name))
				for table: Dictionary in hall.plan.tables:
					check_ge(point.distance_to(Vector2(table.seat.x,table.seat.z)),.038,"player seats remain available")
				if state.position.distance_to(before[i].position)>.15: walked = true
				if state.mode == "playing": games[state.game] = true
		check(walked,"visitors change games, rather than remaining statues")
		check(games.has(&"slots") and games.has(&"video_poker"),"visitors use both machine games")
		if key != ResortThemes.STORE_KEY:
			check(games.has(&"blackjack"),"visitors play table games")
			check(games.has(ResortThemes.signature(key)),"visitors reach the raised signature dais")
		hall.free()
		hall = null

func test_hidden_hall_and_zero_time_freeze_every_visitor_clock() -> void:
	var crowd := _build()
	if crowd == null: return
	var before: Array = crowd.call("states")
	var skeleton := crowd.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var hand := skeleton.find_bone("RightForearm")
	var pose := skeleton.get_bone_pose_rotation(hand)
	crowd.call("step",0.0,Vector3.ZERO)
	check_eq(crowd.call("states"),before,"no time means no gait, game or route change")
	hall.visible = false
	for tick: int in 20: crowd.call("step",.1,Vector3.ZERO)
	for frame: int in 6: await process_frame
	check_eq(crowd.call("states"),before,"unoccupied halls freeze")
	check(skeleton.get_bone_pose_rotation(hand).is_equal_approx(pose),"hidden visitors have no independent animation clock")
	hall.visible = true
	crowd.call("step",.1,Vector3(100,0,100))
	check_ne(crowd.call("states"),before,"occupied hall advances")

func test_playing_moves_hands() -> void:
	var crowd := _build()
	if crowd == null: return
	var skeletons := crowd.find_children("*","Skeleton3D",true,false)
	check_gt(skeletons.size(),0,"patrons have articulated bodies")
	if skeletons.is_empty(): return
	var skeleton := skeletons[0] as Skeleton3D
	var hand := skeleton.find_bone("RightForearm")
	check_ge(hand,0)
	if hand < 0: return
	var start := skeleton.get_bone_pose_rotation(hand)
	for tick: int in 8: crowd.call("step",.1,Vector3(100,0,100))
	check(not skeleton.get_bone_pose_rotation(hand).is_equal_approx(start),"playing reaches toward the game")

func test_visitors_yield_to_the_player_and_keep_clear_afterwards() -> void:
	for key: StringName in [&"arcology_comstock",ResortThemes.STORE_KEY]:
		var crowd := _build(key)
		if crowd == null: return
		var start: Array = crowd.call("states")
		var player: Vector3 = start[0].position
		for tick: int in 200: crowd.call("step",.1,player)
		var states: Array = crowd.call("states")
		for state: Dictionary in states:
			check_ge(state.position.distance_to(player),.07,"patrons give the player space")
		hall.free()
		hall = null

func test_patron_activity_never_consumes_the_global_random_stream() -> void:
	seed(4510)
	var expected := randi()
	seed(4510)
	var crowd := _build()
	if crowd == null: return
	for tick: int in 400: crowd.call("step",.1,Vector3(100,0,100))
	check_eq(randi(),expected,"ambient play has its own random stream")

func test_rerouting_from_a_grid_junction_does_not_leave_a_visitor_stuck() -> void:
	var crowd := _build()
	if crowd == null: return
	var people: Array = crowd.get("_people")
	var person: Dictionary = people[-1]
	var path: PackedVector2Array = person.path
	check_gt(path.size(),2,"a visitor is already changing games")
	if path.size()<3: return
	# A route recalculated at a junction includes that junction as its first
	# waypoint. Reproduce that ordinary route boundary without waiting for RNG.
	person.position = Vector3(path[0].x,0,path[0].y)
	var start: Vector3 = person.position
	for tick: int in 4: crowd.call("step",.1,Vector3(100,0,100))
	check_gt(person.position.distance_to(start),.001,"a reached start waypoint is consumed")

func test_a_walking_visitor_can_escape_when_the_player_steps_into_their_route() -> void:
	var crowd := _build(&"arcology_comstock",Vector2i(12,8))
	if crowd == null: return
	# The first walking visitor is approaching this bank. The closest free
	# grid node must not force their escape connector through the player.
	var player := Vector3(.815625,0,.325)
	for tick: int in 400: crowd.call("step",.1,player)
	for state: Dictionary in crowd.call("states"):
		check_ge(state.position.distance_to(player),.07,"walking patrons escape, as stationary patrons do")

func test_play_gestures_preserve_human_upper_body_anatomy() -> void:
	var crowd := _build()
	if crowd == null: return
	var people: Array = crowd.get("_people")
	for tick: int in 24:
		crowd.call("step",.1,Vector3(100,0,100))
		for person: Dictionary in people:
			if person.mode != "playing": continue
			var visitor: Node3D = person.visual
			var skeleton := visitor.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
			var head := visitor.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin))
			var chest := visitor.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Chest")).origin))
			var hand := visitor.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin))
			# The roster includes shorter bodies; compare anatomical joints
			# instead of assuming every head joint is above 1.44 metres.
			check_gt(head.y-chest.y,.01,"head stays above the shoulders")
			check_lt(hand.y,head.y,"betting hands stay below the head")

func test_slot_bank_players_sit_on_the_authored_stools() -> void:
	var crowd := _build()
	if crowd == null: return
	var found := false
	for person: Dictionary in crowd.get("_people"):
		if person.mode != "playing" or person.game != &"slots": continue
		found = true
		var visitor: Node3D = person.visual
		var skeleton := visitor.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
		var hip := visitor.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin))
		var knee := visitor.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("RightShin")).origin))
		check_gt(knee.y-hip.y,-.008,"slot players bend their knees over the stool, rather than standing through it")
	check(found,"a slot player is present")

func test_attendance_resize_preserves_survivors_and_reuses_released_seats() -> void:
	var crowd := _build(ResortThemes.STORE_KEY)
	var survivor: Dictionary = crowd.get("_people")[0]
	var visual: Node = survivor.visual
	var initial := survivor.duplicate(true)
	seed(7821)
	var expected := randi()
	seed(7821)
	for cycle in 12:
		crowd.call("set_count",1)
		check_eq(crowd.get_child_count(),1,"removed visitor models are released immediately")
		crowd.call("set_count",3)
		check_eq(crowd.get_child(0),visual)
		check_eq(crowd.get("_people")[0],initial,"seat, route, yield and cosmetic state survive resize")
		var occupied := {}
		for person: Dictionary in crowd.get("_people"):
			check(not occupied.has(person.target),"each restored visitor owns a free seat")
			occupied[person.target] = true
			check(float(person.remaining)<=8.0,"arrival game clock keeps the existing bounded stagger")
	check_eq(randi(),expected,"resizing draws no global randomness")
