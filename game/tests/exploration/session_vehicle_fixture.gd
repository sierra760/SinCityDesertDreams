# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Explicit vehicles for driving/flight tests. Production entry never uses this.
extends RefCounted

static func park(session: CityExplorationController) -> void:
	var at := session.pedestrian.global_position
	var car_pose := session._parking_pose(at+Vector3(.25,0,0),1)
	if not car_pose.is_empty(): session.car = session._make_actor(1,car_pose.transform)
	var flight_pose := session._parking_pose(at+Vector3(-.5,0,0),2)
	if not flight_pose.is_empty(): session.helicopter = session._make_actor(2,flight_pose.transform)
