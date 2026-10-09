# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## License and Credits carries the GPL, the engine's MIT license and the
## notices of the libraries Godot bundles, on every platform, from the engine.
extends "res://tests/test_case.gd"


func test_engine_licenses_come_from_the_running_engine() -> void:
	var text := LicenseWindow.third_party_notices()
	check(text.contains("Godot Engine"), "Godot's own license is shown")
	check(text.contains(Engine.get_license_text().strip_edges().substr(0, 60)), "the engine's license text itself")
	check(text.contains("FreeType"), "bundled engine libraries are credited")
	check(text.contains("LICENSE: FTL"), "the FreeType license text is included")
	check(text.contains("LICENSE: Apache-2.0"), "Mbed TLS's license text is included")
	check(text.contains("FONT: BioRhyme"), "font license notices are listed")
	check(text.contains("SIL OPEN FONT LICENSE"), "the OFL text itself is included")
	check(text.contains("GODOT-CPP"), "native extensions' godot-cpp license is listed where bundled")


func test_window_shows_engine_licenses_on_request() -> void:
	var window := LicenseWindow.new()
	root.add_child(window)
	window.open()
	check(window.license_text.text.contains("GNU GENERAL PUBLIC LICENSE"))
	check(not window.engine_text.visible, "the long engine notices are built only when asked for")
	check(window.engine_text.text.is_empty())
	window.engine_button.pressed.emit()
	check(window.engine_text.visible)
	check(window.engine_text.text.contains("Godot Engine") and window.engine_text.text.contains("FreeType"))
	var titles := window.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	check(titles.has("License and Credits"), "the window title is in Title Case")
	window.close()
	check(not window.visible)
	window.free()
