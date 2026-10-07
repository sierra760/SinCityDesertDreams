# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared setup for tests that drive the whole game through Main.
extends RefCounted

const MainScene := preload("res://scenes/main.tscn")
const TestCase := preload("res://tests/test_case.gd")


## Main with private preferences at user://<preferences_name>.cfg, 100% UI
## scale and a paused flat city, attached to the tree root.
static func make_host(tree: SceneTree, preferences_name: String) -> GameHost:
	var host: GameHost = MainScene.instantiate()
	host.preferences_path = "user://%s.cfg" % preferences_name
	tree.root.add_child(host)
	host.display_layout.set_ui_scale(100)
	host.begin_city(TestCase.flat_city(), {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	return host


## Let layout, deferred calls and redraws run for `frames` process frames.
static func settle(tree: SceneTree, frames: int) -> void:
	for frame in frames:
		await tree.process_frame
