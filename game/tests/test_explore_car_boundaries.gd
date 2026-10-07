# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Native motion across a legal curb must depend on the actual box footprint,
## including oblique and reverse approaches, without increasing the step budget.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT
var fixture: Node3D
var reports: Array[String] = []

class Driver extends Node:
	signal completed
	var car: ExploreCar
	var backwards := false
	var ticks := 0
	var maximum_y := -INF
	var minimum_y := INF
	func _physics_process(delta: float) -> void:
		var frame := ExploreInputFrame.idle()
		frame.move.y = 1.0 if backwards else -.25
		car.step(frame,0,delta)
		maximum_y = maxf(maximum_y,car.position.y)
		minimum_y = minf(minimum_y,car.position.y)
		ticks += 1
		if ticks == 300:
			set_physics_process(false)
			completed.emit()

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	reports.clear()
	await physics_frame

func approach(angle: float, height: float, backwards := false) -> Dictionary:
	fixture = Fixture.attach(self,flat_city())
	# A solid edge at z22.5 with known top; floor geometry and box dimensions
	# are unchanged production resources, and spawn has independent clearance.
	Fixture.box(fixture,Vector3(24,GROUND+(height-1.0)*.5,19.25),Vector3(16,1.0+height,6.5),ExploreActorProfile.FLOOR)
	var car := ExploreCar.new()
	fixture.add_child(car)
	car.bind(fixture.get_node("traversal"))
	car.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	car.apply_safe_pose(Transform3D(Basis(Vector3.UP,deg_to_rad(angle)+(PI if backwards else 0.0)),Vector3(24,GROUND+.002,23)))
	await physics_frame
	check(car._world.has_clearance(car.collision_pose(),car._collider.shape,[car.get_rid()]),"initial oriented chassis is clear")
	var driver := Driver.new()
	driver.car = car
	driver.backwards = backwards
	fixture.add_child(driver)
	await driver.completed
	await process_frame
	check(reports.is_empty(),"curb contact must not trigger recovery")
	check(car.landed(),"current body still has physical support")
	check(car.global_transform.is_finite() and car.velocity.is_finite(),"finite native motion")
	return {"position":car.position,"maximum_y":driver.maximum_y,"minimum_y":driver.minimum_y}

func crosses(angle: float, backwards := false) -> void:
	var result := await approach(angle,.04,backwards)
	check_lt(result.position.z,22.4,"crossed high side of curb using native input")
	check_gt(result.position.y,GROUND+.038,"chassis rests on high side")
	check_lt(result.maximum_y,GROUND+.047,"no lift beyond existing step budget")
	check_gt(result.minimum_y,GROUND-.002,"no floor penetration")

func test_straight_curb() -> void: await crosses(0)
func test_oblique_30_curb() -> void: await crosses(30)
func test_oblique_45_curb() -> void: await crosses(45)
func test_oblique_60_curb() -> void: await crosses(60)
func test_reverse_oblique_curb() -> void: await crosses(45,true)

func test_too_high_edge_stays_solid() -> void:
	var result := await approach(45,.06)
	check_gt(result.position.z,22.63,"a step above budget remains impassable")
	check_lt(result.maximum_y,GROUND+.004,"no forbidden lift")

func test_wall_stays_solid() -> void:
	var result := await approach(30,1.0)
	check_gt(result.position.z,22.64,"a wall remains impassable")
	check_lt(result.maximum_y,GROUND+.004,"no wall teleport")
