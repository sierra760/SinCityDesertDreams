# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## What the advisors say when the city is short of something.
##
## Each need kind has a few variants in the advisors' plain, slightly weary
## voice. Text uses the same placeholders as the newspaper.
class_name AdvisorLines
extends RefCounted

## kind -> {title: String, lines: [String]}
const LINES: Dictionary = {
	&"power_shortage": {
		"title": "Power",
		"lines": [
			"The plants are running flat out and it still isn't enough. {city} needs more generating capacity, and soon.",
			"Half the town is sitting in the dark with a warm beer. Build a power plant or watch the lights go out for good.",
			"Demand has caught up with the grid. Another plant, or a bigger one, before the summer.",
		],
	},
	&"water_shortage": {
		"title": "Water",
		"lines": [
			"The pumps can't keep up. More pumps, more pipe, or a tower to carry the town through the dry months.",
			"Taps are running dry across {city}. Water is the one thing out here nobody forgives you for running out of.",
			"Pumping falls short of demand. Find fresh water and put a pump on it.",
		],
	},
	&"fire_protection": {
		"title": "Fire",
		"lines": [
			"Everything here is dry and half of it is wood. {city} needs fire stations within reach of every block.",
			"The volunteers do their best, but a bucket brigade is not a fire department. Build a station.",
			"Coverage has gaps. One spark in the wrong district and there won't be a district.",
		],
	},
	&"police": {
		"title": "Police",
		"lines": [
			"Crime is climbing and the sheriff is one man with a hat. {city} needs a police station where the trouble is.",
			"Residents are locking doors that never had locks. More patrols, which means more stations.",
			"The east side wants a deputy and the west side wants two. Fund the police and build where crime runs highest.",
		],
	},
	&"schools": {
		"title": "Education",
		"lines": [
			"The children of {city} are learning their letters from cereal boxes. Build a school.",
			"Classrooms are full and the teacher is tired. Another school, and fund the one you have.",
			"An educated town earns more and complains better. Both are worth a school.",
		],
	},
	&"hospitals": {
		"title": "Health",
		"lines": [
			"The nearest doctor is a long drive and a prayer. {city} needs a hospital.",
			"People are living shorter lives than they should. A hospital, funded, would change that.",
			"The clinic is a bench under a tree. Build a hospital before the next heat wave.",
		],
	},
	&"traffic": {
		"title": "Traffic",
		"lines": [
			"Traffic is backed up from one end of town to the other. More roads, or rail and buses to get people off them.",
			"Commuters are spending their lives at intersections. Give them another way through.",
			"The roads are full. Build around the jam, not into it.",
		],
	},
	&"road_and_rail": {
		"title": "Transport",
		"lines": [
			"Residents want to get around and there's no way to do it. Roads and rail, connected, to every district.",
			"A town with no way through it is just houses. Lay some road.",
			"Rail would carry the workers the roads can't. Consider a line and a station or two.",
		],
	},
	&"pollution": {
		"title": "Pollution",
		"lines": [
			"The air over {city} has a color. Move heavy industry downwind, plant trees, and consider cleaner power.",
			"Pollution drives down land value and drives out residents. Parks and the Pollution Controls ordinance would help.",
			"The haze is worst near the plants. Cleaner plants cost more and pay it back in residents who stay.",
		],
	},
	&"unemployment": {
		"title": "Jobs",
		"lines": [
			"Too many hands and not enough work. Zone for commerce and industry so people have somewhere to go in the morning.",
			"Unemployment is up. Jobs come from shops and factories; zone some and connect them.",
			"Idle workers make for a restless town. More commercial and industrial land, with road to reach it.",
		],
	},
	&"taxes": {
		"title": "Taxes",
		"lines": [
			"Taxes are high enough that people are doing sums at the kitchen table. Bring the rate down before they finish.",
			"Businesses are eyeing the town down the road with the lower rate. Ease off.",
			"High taxes fill the treasury this year and empty the town next year. Find a rate people will live with.",
		],
	},
	&"approval": {
		"title": "Approval",
		"lines": [
			"Mayor {mayor}, the town is not happy with you. Look at the top complaint and fix it before the next poll.",
			"Approval is low. Residents remember what they asked for and notice what they got instead.",
			"The council is hearing it at the diner every morning. Address the biggest complaint first.",
		],
	},
	&"seaport": {
		"title": "Industry",
		"lines": [
			"Industry wants to ship by water. A seaport on the shore would open new markets.",
			"Factories are asking for a port. Zone one along the water and connect it.",
		],
	},
	&"airport": {
		"title": "Commerce",
		"lines": [
			"Commerce wants an airport. Businesses that can fly in customers grow faster.",
			"Shops and offices are asking for air service. Zone an airport with room to grow.",
		],
	},
	&"recreation": {
		"title": "Recreation",
		"lines": [
			"Residents want somewhere to spend a Sunday. A park, a zoo, a stadium or a marina would do.",
			"All work and no play. Give {city} a place to sit in the shade and watch something.",
		],
	},
	&"connections": {
		"title": "Connections",
		"lines": [
			"Industry and commerce want links to the neighbors. Run road or rail to the edge of the map.",
			"Trade needs a way out of town. Connect the network to the border.",
		],
	},
}

## Need kinds other systems use, mapped onto the kinds that have lines.
const ALIASES: Dictionary = {
	&"needs_power": &"power_shortage",
	&"needs_water": &"water_shortage",
	&"needs_fire_protection": &"fire_protection",
	&"needs_police": &"police",
	&"needs_school": &"schools",
	&"needs_hospital": &"hospitals",
	&"needs_seaport": &"seaport",
	&"needs_airport": &"airport",
	&"needs_recreation": &"recreation",
	&"needs_transit": &"road_and_rail",
	&"needs_industry_connections": &"connections",
	&"needs_connections": &"connections",
	&"power": &"power_shortage",
	&"water": &"water_shortage",
	&"fire": &"fire_protection",
	&"school": &"schools",
	&"hospital": &"hospitals",
	&"transit": &"road_and_rail",
	&"crime": &"police",
	&"jobs": &"unemployment",
}


static func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in LINES:
		out.append(k)
	return out


static func has(kind: StringName) -> bool:
	return LINES.has(normalize(kind))


## The kind that has lines for a need reported under any accepted name.
static func normalize(kind: StringName) -> StringName:
	if LINES.has(kind):
		return kind
	if ALIASES.has(kind):
		return ALIASES[kind]
	if String(kind).begins_with("needs_"):
		var bare := StringName(String(kind).substr(6))
		if LINES.has(bare):
			return bare
		if ALIASES.has(bare):
			return ALIASES[bare]
	return kind


static func title(kind: StringName) -> String:
	var k := normalize(kind)
	if not LINES.has(k):
		return kind_label(kind)
	return String(LINES[k]["title"])


static func variants(kind: StringName) -> Array:
	var k := normalize(kind)
	if not LINES.has(k):
		return []
	return LINES[k]["lines"]


## One filled line for the need, picked at random among its variants.
static func line(kind: StringName, values: Dictionary, rng: SimRng) -> String:
	var v := variants(kind)
	if v.is_empty():
		return ""
	var text := String(v[rng.below(v.size())])
	# Addressing a mayor with no name of their own: "Mayor, the town...".
	if values.has("mayor") and NewsStories.is_unnamed_mayor(String(values["mayor"])):
		text = text.replace("Mayor {mayor}, ", "Mayor, ")
	return NewsStories.fill(text, values)


static func kind_label(kind: StringName) -> String:
	return String(kind).replace("_", " ").capitalize()
