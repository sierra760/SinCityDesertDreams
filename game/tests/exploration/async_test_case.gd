# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Test case whose test methods may await physics frames; reporting matches test_case.gd.
extends "res://tests/test_case.gd"

func _run_all() -> void:
	await before_all()
	for method: Dictionary in get_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("test_"): continue
		_current = method_name
		await before_each()
		var failures_before := _failed
		await call(method_name)
		await after_each()
		if _failed == failures_before:
			_passed += 1
		else:
			print("  FAIL %s" % method_name)
	await after_all()
	await process_frame
	print("Results: %d passed, %d failed" % [_passed,_failed])
	quit(0 if _failed == 0 else 1)
