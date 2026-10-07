# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One Explore input sample; interact and jump are edges. Keyboard and analog
## touch samples both produce this shape for actor physics.
class_name ExploreInputFrame
extends RefCounted

var move := Vector2.ZERO
var vertical := 0.0
var sprint := false
var jump := false
var brake := false
var interact := false

static func idle() -> ExploreInputFrame:
	return ExploreInputFrame.new()

static func combined(keyboard: ExploreInputFrame, touch: ExploreInputFrame) -> ExploreInputFrame:
	var frame := idle()
	frame.move=(keyboard.move+touch.move).limit_length(1.0)
	frame.vertical=clampf(keyboard.vertical+touch.vertical,-1.0,1.0)
	frame.sprint=keyboard.sprint or touch.sprint
	frame.jump=keyboard.jump or touch.jump
	frame.brake=keyboard.brake or touch.brake
	frame.interact=keyboard.interact or touch.interact
	return frame

static func from_keys(keys: Dictionary, edges: Dictionary, bindings: ControlBindings = null) -> ExploreInputFrame:
	var frame := idle()
	var input := bindings if bindings != null else ControlBindings.new()
	frame.move = Vector2(int(input.held(keys,&"move_right"))-int(input.held(keys,&"move_left")),
		int(input.held(keys,&"move_back"))-int(input.held(keys,&"move_forward"))).limit_length(1.0)
	frame.vertical = float(int(input.held(keys,&"ascend"))-int(input.held(keys,&"descend")))
	frame.sprint = input.held(keys,&"sprint")
	frame.jump = input.held(edges,&"jump")
	frame.brake = input.held(keys,&"brake")
	frame.interact = input.held(edges,&"interact")
	return frame
