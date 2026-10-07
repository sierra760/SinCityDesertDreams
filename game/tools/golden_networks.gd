# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Prints the chunked network-layer output hashes and build time of each city
## path argument: visible faces/colors/cells, tunnel surfaces, packed physical
## patches, boxes and obstacles. Use its output to refresh
## tests/test_network_layer_golden.gd after a deliberate geometry change.
extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var golden := load("res://tests/test_network_layer_golden.gd")
	for path: String in OS.get_cmdline_user_args():
		var loaded := Sc2Import.load(path)
		if not loaded.ok:
			print("FAIL import ", path)
			continue
		var start := Time.get_ticks_usec()
		var hashes: Array = golden.hashes(loaded.city)
		print("GOLDEN %s visible=%s tunnels=%s physical=%s boxes=%s obstacles=%s ms=%.1f" % [path.get_file(), hashes[0], hashes[1], hashes[2], hashes[3], hashes[4], (Time.get_ticks_usec()-start)/1000.0])
		await process_frame
	quit(0)
