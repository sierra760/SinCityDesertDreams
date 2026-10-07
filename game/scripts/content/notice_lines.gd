# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Text for the modal notices and construction prompts the host shows.
##
## Every notice kind the simulation raises, and every prompt construction can
## raise, has a title and a body here. Bodies use the placeholders {city},
## {mayor}, {year}, {name}, {count}, {amount}, {approval}, {neighbor}, {cost}
## and {kind}; `render` fills them from the payload and the city.
class_name NoticeLines
extends RefCounted

## kind -> {title, body}
const NOTICES: Dictionary = {
	&"disaster": {
		"title": "Emergency: {kind}",
		"body": "Reports are coming in of {phrase} near {place}. Crews will answer where stations stand; where they do not, the map is yours to work with the emergency tools.",
	},
	&"national_guard": {
		"title": "The Guard Arrives",
		"body": "{city} has no fire or police stations to answer this emergency, so the National Guard has been sent in. Use the emergency tools to place its crews where they are needed most.",
	},
	&"plant_retired": {
		"title": "Power Plant Retired",
		"body": "The {name} near {place} has worn out after a lifetime of service and has been taken down. Its customers are without power until a new plant is built. Clear the rubble and rebuild before the lights go out across {city}.",
	},
	&"fiscal_crisis": {
		"title": "Fiscal Crisis",
		"body": "The books closed {year} with the treasury at {amount}. Automatic budgeting is now off, so you will review the budget each January. Raise taxes, trim funding or issue a bond before the next January, or the banks will step in.",
	},
	&"bankruptcy": {
		"title": "Bankruptcy",
		"body": "{city} can no longer meet its obligations. The treasury stands at {amount} against {count} of debt, and the council has declared the city bankrupt. The mayor's office remains open, but nobody is sure for how long.\n\nTo lift the bankruptcy, bring the treasury back up to at least {limit}: raise taxes, trim funding or repay bonds in Reports → Budget.",
	},
	&"exodus": {
		"title": "The Gaming Resorts Leave",
		"body": "The gaming resorts of {city} have sealed their doors, lifted from their foundations and departed for the stars, taking {count} residents with them. Rubble and a refund are all they left behind.",
	},
	&"approval_milestone": {
		"title": "A Popular Mayor",
		"body": "The March vote gives Mayor {mayor} an approval rating of {approval} percent. The courthouse bench is unanimous: things are going well in {city}.",
	},
	&"opposition": {
		"title": "Citizens Object",
		"body": "A crowd has gathered at the site of the proposed {name}. Families from the nearby streets say it does not belong beside their homes, and your citizens urge you to reconsider. Build it anyway, or find another site?",
	},
	&"tree_protest": {
		"title": "Save Our Trees",
		"body": "Clearing {count} tree tiles in one sweep has drawn a small protest outside city hall. The banners are hand-painted and the speeches are long. Nobody expects the trees back, but they wanted it noted.",
	},
	&"newspaper": {
		"title": "Extra! {kind}",
		"body": "{name}",
	},
}

## Gift and base offers, keyed by the reward key the simulation offers.
const REWARDS: Dictionary = {
	&"mayors_residence": {
		"title": "A Home for the Mayor",
		"body": "With {city} past two thousand residents, the council has voted to build Mayor {mayor} a proper residence. Choose a quiet site; the neighbors will appreciate it.",
	},
	&"city_hall": {
		"title": "A Hall for the City",
		"body": "Ten thousand people now call {city} home, and the council has outgrown the back room of the diner. A city hall may be built at no charge wherever you see fit.",
	},
	&"monument": {
		"title": "A Monument Is Offered",
		"body": "Thirty thousand residents strong, {city} has earned a monument to its founders. The sculptor is ready; only the site remains to be chosen.",
	},
	&"military_base": {
		"title": "A Base for {city}",
		"body": "The armed forces have taken notice of {city} and propose {phrase} base on the outskirts. It brings jobs and protection, and a little noise. The council leaves the decision to you.",
	},
	&"neon_dome": {
		"title": "The Neon Dome",
		"body": "At one hundred and twenty thousand residents, {city} is the talk of the desert. An anonymous benefactor offers the Neon Dome, a landmark to be seen from the highway for miles.",
	},
}

## Construction prompts: bridges, tunnels and neighbor connections.
const PROMPTS: Dictionary = {
	&"bridge": {
		"title": "Build a Bridge",
		"body": "The route crosses {count} tiles of open water. Choose how to span it.",
	},
	&"tunnel": {
		"title": "Bore a Tunnel",
		"body": "The route bores {count} tiles through the hill, portals included. Build it?",
	},
	&"neighbor": {
		"title": "Connect to {neighbor}",
		"body": "Carry this {kind} across the city limit to {neighbor}? The link costs {cost} and opens trade and travel between the two towns.",
	},
}

## Labels for the bridge and tunnel options a plan can offer.
const OPTION_LABELS: Dictionary = {
	&"causeway": "Causeway",
	&"suspension": "Suspension bridge",
	&"rail": "Rail bridge",
	&"elevated": "Elevated line",
	&"tunnel": "Tunnel",
	&"connect": "Connect",
}

## How a notice body names each disaster after "Reports are coming in of".
const DISASTER_PHRASES: Dictionary = {
	&"fire": "a fire",
	&"flood": "flash flooding",
	&"riot": "a riot",
	&"hazard": "toxic contamination",
	&"earthquake": "an earthquake",
	&"tornado": "a tornado",
	&"monster": "Tsawhawbitts",
	&"meltdown": "a nuclear meltdown",
	&"microwave": "a stray microwave beam",
	&"volcano": "a volcanic eruption",
	&"firestorm": "a firestorm",
	&"mass_riots": "riots",
	&"major_flood": "major flooding",
	&"chemical_spill": "a chemical spill",
	&"hurricane": "a hurricane",
	&"plane_crash": "a plane crash",
}

## How the base offer names each kind of base before "base".
const MILITARY_PHRASES: Dictionary = {
	&"air": "an air force",
	&"army": "an army",
	&"naval": "a naval",
	&"missile": "a missile",
}

const PLACEHOLDERS: Array[String] = ["city", "mayor", "year", "name", "count", "amount", "approval",
	"neighbor", "cost", "kind", "place", "phrase", "limit"]


## Whether a notice, reward or prompt of this kind has text.
static func has(kind: StringName) -> bool:
	return NOTICES.has(kind) or PROMPTS.has(kind) or REWARDS.has(kind)


## Title and body for a notice, filled from `payload` and the city.
static func render(kind: StringName, payload: Dictionary, city_name: String, mayor: String, year: int) -> Dictionary:
	var lines: Dictionary = {}
	if kind == &"reward_offered":
		var key := StringName(String(payload.get("key", "")))
		lines = REWARDS.get(key, {"title": "A Gift for {city}", "body": "The council offers {city} a new landmark at no charge. Choose its site when you are ready."})
	elif NOTICES.has(kind):
		lines = NOTICES[kind]
	elif PROMPTS.has(kind):
		lines = PROMPTS[kind]
	else:
		lines = {"title": NewsStories.kind_label(kind), "body": "{name}"}
	var values := values_for(kind, payload, city_name, mayor, year)
	return {"title": fill(String(lines["title"]), values), "body": fill(String(lines["body"]), values)}


## Placeholder values for a payload.
static func values_for(kind: StringName, payload: Dictionary, city_name: String, mayor: String, year: int) -> Dictionary:
	var kind_text := ""
	if payload.has("kind"):
		kind_text = NewsStories.kind_label(StringName(String(payload["kind"])))
	elif payload.has("key"):
		kind_text = NewsStories.reward_name(StringName(String(payload["key"])))
	else:
		kind_text = NewsStories.kind_label(kind)
	if kind == &"newspaper":
		kind_text = String(payload.get("date", ""))
	elif PROMPTS.has(kind):
		kind_text = kind_text.to_lower()
	var name_text := String(payload.get("name", ""))
	if kind == &"newspaper":
		name_text = _lead_story(payload)
	return {
		"city": city_name,
		"mayor": mayor,
		"year": str(int(payload.get("year", year))),
		"name": name_text if not name_text.is_empty() else kind_text,
		"count": _count_text(payload),
		"amount": money(int(payload.get("funds", payload.get("amount", 0)))),
		"approval": str(int(payload.get("approval", 0))),
		"neighbor": String(payload.get("neighbor", "the next town")),
		"cost": money(int(payload.get("cost", 0))),
		"kind": kind_text,
		"place": NewsStories.place_text(payload),
		"phrase": phrase_for(kind, payload),
		"limit": money(BudgetParams.BANKRUPTCY_FUNDS),
	}


## The article-and-noun phrase a disaster or base offer is written with.
static func phrase_for(kind: StringName, payload: Dictionary) -> String:
	var subject := StringName(String(payload.get("kind", "")))
	if kind == &"disaster":
		if DISASTER_PHRASES.has(subject):
			return String(DISASTER_PHRASES[subject])
		return "a " + NewsStories.kind_label(subject).to_lower()
	if MILITARY_PHRASES.has(subject):
		return String(MILITARY_PHRASES[subject])
	return "a " + NewsStories.kind_label(subject).to_lower()


static func _count_text(payload: Dictionary) -> String:
	for key in ["count", "residents", "debt", "tiles", "length"]:
		if payload.has(key):
			var v: Variant = payload[key]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				return grouped(int(v)) if key != "debt" else money(int(v))
			return String(v)
	return "several"


static func _lead_story(payload: Dictionary) -> String:
	var stories: Array = payload.get("stories", [])
	if stories.is_empty():
		return "The presses are running."
	var lead: Dictionary = stories[0]
	return "%s\n\n%s" % [String(lead.get("headline", "")), String(lead.get("body", ""))]


## Replace every known placeholder.
static func fill(text: String, values: Dictionary) -> String:
	var out := text
	if values.has("mayor") and NewsStories.is_unnamed_mayor(String(values["mayor"])):
		out = NewsStories.without_mayor_name(out, false)
	for key in PLACEHOLDERS:
		if values.has(key):
			out = out.replace("{" + key + "}", String(values[key]))
	return out


## Label for a construction option key.
static func option_label(key: StringName) -> String:
	return String(OPTION_LABELS.get(key, NewsStories.kind_label(key)))


## Digits grouped in threes: 12345 -> "12,345".
static func grouped(n: int) -> String:
	var negative := n < 0
	var digits := str(absi(n))
	var out := ""
	var i := digits.length()
	while i > 3:
		out = "," + digits.substr(i - 3, 3) + out
		i -= 3
	out = digits.substr(0, i) + out
	return ("-" + out) if negative else out


## A dollar amount with the sign in front: -1200 -> "-$1,200".
static func money(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + grouped(absi(amount))
