# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
func test_retained_detail_does_not_toggle_visibility_while_camera_moves() -> void:
 var host := Node3D.new()
 root.add_child(host)
 var camera := Camera3D.new()
 host.add_child(camera)
 var manager := ExploreActorDetailManager.new()
 manager.bind(host)
 var states: Array[Dictionary]=[{"id":"car","kind":"car","variant":0,"position":Vector3(0,0,-4),"yaw":0.0,"speed":.2,"steering":0.0,"airborne":false,"phase":0.0,"visual_time":0.0,"distance":0.0}]
 var selected := manager.update(states,camera)
 check(selected.has("car"),"car starts selected")
 var visual: ExploreActorVisual=selected.car
 var changes: Array[bool]=[]
 visual.visibility_changed.connect(func(): changes.append(visual.visible))
 for frame in 60:
  camera.position.x=sin(float(frame)*.01)*.1
  states[0].position.x=float(frame)*.001
  states[0].distance=float(frame)*.01
  states[0].visual_time=float(frame)/60.0
  check_eq(manager.update(states,camera).get("car"),visual,"moving view retains its authored instance")
  check_eq(visual.position,states[0].position,"retained model still samples the current pose")
 check_eq(changes.size(),0,"retained detail does not recursively hide and show its scene each frame")
 manager.update([],camera)
 check_eq(changes,[false],"leaving view hides the allocation exactly once")
 manager.update(states,camera)
 check_eq(changes,[false,true],"reentering view shows the reused allocation")
 manager.clear()
 host.free()
 await process_frame
