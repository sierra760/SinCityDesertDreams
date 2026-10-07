# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_numeric_port_kinds_produce_readable_news() -> void:
	check_eq(NewsStories.kind_text(&"port_opened",{"kind":Zones.AIRPORT}),"Airport")
	check_eq(NewsStories.kind_text(&"port_closed",{"kind":Zones.SEAPORT}),"Seaport")
	check_eq(NewsStories.kind_text(&"disaster_started",{"kind":&"fire"}),"Fire")
