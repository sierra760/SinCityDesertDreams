# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Minimal test harness. A test file extends this, defines `func test_*()`
## methods, and is run headless with `godot --headless -s tests/<file>.gd`.
## The runner in tools/run_tests.py looks for the final "Results:" line.
extends SceneTree

var _passed := 0
var _failed := 0
var _current := ""


## No suite reaches the street-map, place-search or map-settings servers; suites that
## exercise them install fake backends.
class OfflineMapBackend:
	extends Node
	signal finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
	func start(_url: String, _headers: PackedStringArray) -> int: return ERR_UNAVAILABLE
	func abort() -> void: pass


func _init() -> void:
	var offline := func() -> Node: return OfflineMapBackend.new()
	TerrainBasemap.default_request_factory = offline
	TerrainPlaceSearch.default_request_factory = offline
	TerrainMapConfig.default_request_factory = offline
	call_deferred("_run_all")


## Static factories must not outlive this script at engine shutdown.
func _finalize() -> void:
	TerrainBasemap.default_request_factory = Callable()
	TerrainPlaceSearch.default_request_factory = Callable()
	TerrainMapConfig.default_request_factory = Callable()


func _run_all() -> void:
	before_all()
	for m in get_method_list():
		var n: String = m.name
		if n.begins_with("test_"):
			_current = n
			before_each()
			var before := _failed
			call(n)
			after_each()
			if _failed == before:
				_passed += 1
			else:
				print("  FAIL %s" % n)
	after_all()
	print("Results: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func before_all() -> void: pass
func after_all() -> void: pass
func before_each() -> void: pass
func after_each() -> void: pass


func check(cond: bool, message: String = "") -> void:
	if not cond:
		_failed += 1
		print("    %s: %s" % [_current, message if message != "" else "check failed"])


func check_eq(actual, expected, message: String = "") -> void:
	if actual != expected:
		_failed += 1
		print("    %s: expected %s, got %s %s" % [_current, str(expected), str(actual), message])


func check_ne(actual, unexpected, message: String = "") -> void:
	if actual == unexpected:
		_failed += 1
		print("    %s: did not expect %s %s" % [_current, str(unexpected), message])


func check_gt(actual, floor_value, message: String = "") -> void:
	if not (actual > floor_value):
		_failed += 1
		print("    %s: expected > %s, got %s %s" % [_current, str(floor_value), str(actual), message])


func check_ge(actual, floor_value, message: String = "") -> void:
	if not (actual >= floor_value):
		_failed += 1
		print("    %s: expected >= %s, got %s %s" % [_current, str(floor_value), str(actual), message])


func check_lt(actual, ceiling, message: String = "") -> void:
	if not (actual < ceiling):
		_failed += 1
		print("    %s: expected < %s, got %s %s" % [_current, str(ceiling), str(actual), message])


func check_between(actual, lo, hi, message: String = "") -> void:
	if actual < lo or actual > hi:
		_failed += 1
		print("    %s: expected %s..%s, got %s %s" % [_current, str(lo), str(hi), str(actual), message])


## A flat, dry, empty city with the given funds. Tests build on it.
static func flat_city(funds: int = 20000, height: int = 4) -> City:
	var c := City.new()
	c.funds = funds
	for y in City.HEIGHT:
		for x in City.WIDTH:
			c.terrain.put(x, y, Terrain.FLAT)
			c.set_heights(x, y, height, 0)
	return c


## A bare simulation context for driving systems directly. The clock starts at
## its defaults; tests that depend on the city's date set it themselves.
static func make_context(c: City, seed_value: int = 7) -> SimContext:
	var ctx := SimContext.new()
	ctx.city = c
	ctx.stats = CityStats.new()
	ctx.rng = SimRng.new(seed_value)
	ctx.clock = GameClock.new()
	ctx.events = CityEvents.new()
	return ctx


## A Simulation node ready to advance, attached to the tree root.
func make_simulation(c: City, seed_value: int = 12345) -> Simulation:
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(c, seed_value)
	return sim
