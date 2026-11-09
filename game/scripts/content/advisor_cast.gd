# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

## Six departments, one recognizable person each. All state is transient UI data.
const ORDER := ["finance", "utilities", "transport", "safety", "community", "planning"]
const MOODS := ["delighted", "pleased", "neutral", "concerned", "critical"]
const CAST := {
	"finance": ["Dana Mercer", "Finance", "Treasury · taxes"],
	"utilities": ["Ray Navarro", "Utilities", "Power · water · treatment"],
	"transport": ["Marcus Reed", "Transport", "Roads · transit · ports"],
	"safety": ["Denise Holt", "Public Safety", "Police · fire · emergencies"],
	"community": ["Dr. Elaine Park", "Community Services", "Health · schools · parks"],
	"planning": ["Tony Delgado", "Planning & Tourism", "Jobs · growth · environment · visitors"],
}
const DEPARTMENTS := {
	"treasury":"finance", "taxes":"finance",
	"power_shortage":"utilities", "water_shortage":"utilities", "water_treatment":"utilities",
	"traffic":"transport", "road_and_rail":"transport", "airport":"transport", "seaport":"transport",
	"police":"safety", "fire_protection":"safety", "emergency":"safety",
	"schools":"community", "hospitals":"community", "recreation":"community",
	"unemployment":"planning", "connections":"planning", "commerce":"planning",
	"tourism":"planning", "pollution":"planning", "approval":"planning",
}

## Mood and month choose authored dialogue without touching a random stream.
const REMARKS := {
	"finance": {
		"delighted":["I may have to authorize a celebratory paperclip.", "These figures are almost suspiciously presentable. Keep it up."],
		"pleased":["No alarms in these figures. Please don't celebrate by buying a stadium.", "A pleasantly dull set of numbers. That's a compliment."],
		"neutral":["Bring the plans. I'll bring the spreadsheet.", "Before the grand gesture, a small look at the books."],
		"concerned":["I can balance a spreadsheet. I can't balance a wish list.", "Let's have the budget meeting before the ribbon cutting."],
		"critical":["Mayor, put down the brochure and open the books.", "The red column is winning. That's not a contest we want to lose."],
	},
	"utilities": {
		"delighted":["Reliable service. Not glamorous, until you've lived without it.", "Good readings. I might even leave work with a clean shirt."],
		"pleased":["The readings look respectable. Let's keep them that way.", "I'll take dependable over spectacular every time."],
		"neutral":["Let's get the readings before we make promises.", "I brought the plans with the pipes marked. Radical idea, I know."],
		"concerned":["A little attention now beats a very memorable meeting later.", "Let's sort this out while it still fits on a clipboard."],
		"critical":["The ribbon cutting can wait. The service cannot.", "Mayor, this needs more than an optimistic progress report."],
	},
	"transport": {
		"delighted":["Movement! Actual movement! This is why I came to work.", "I could frame a transport report like this. Don't tempt me."],
		"pleased":["Respectable numbers. I'll save the dramatic speech for another meeting.", "A useful route is its own reward. Funding helps too."],
		"neutral":["The lines on the map are the easy part.", "Let's see what the routes actually do before we applaud the map."],
		"concerned":["A traffic jam is not the kind of standing ovation I wanted.", "I'd like this department to involve slightly more getting somewhere."],
		"critical":["Mayor, this is a transport department. People need to move.", "I've used up the polite version of this briefing."],
	},
	"safety": {
		"delighted":["A good report. Let's keep the emergency binder boring.", "I'll accept the good numbers. I am still checking the plan."],
		"pleased":["I'll take an uneventful briefing. I've earned a few.", "Keep checking the basics. That's how a quiet day stays quiet."],
		"neutral":["I'm reviewing the situation. Confetti can wait.", "The emergency plan has tabs. Please don't rearrange the tabs."],
		"concerned":["I'd rather discuss this now than explain it afterward.", "Prepared is cheaper than surprised. Usually less paperwork too."],
		"critical":["Mayor, the emergency comes first.", "We need a response, Mayor. The speech can follow."],
	},
	"community": {
		"delighted":["Now this is a report I'd put on the staff-room wall.", "Good results. I promise not to assign extra homework."],
		"pleased":["A decent report. Let's keep looking after the basics.", "Progress doesn't always need a parade. A little follow-through works."],
		"neutral":["Let's see what the reports say before grading our own work.", "Schools, health and parks. Yes, I brought three folders."],
		"concerned":["We're marking this one 'needs attention,' Mayor.", "Another committee isn't the same thing as getting it done."],
		"critical":["People aren't a line item. This needs attention now.", "Mayor, let's trade the reassuring speech for a workable plan."],
	},
	"planning": {
		"delighted":["Finally, something I can put in the brochure without clearing my throat.", "This is the part where I try very hard not to say 'visionary.'"],
		"pleased":["The pitch is getting easier. Let's keep the substance behind it.", "Promising figures. I'll order the modest-sized presentation board."],
		"neutral":["I can sell the vision. We still have to build the city.", "I brought a plan. The glossy cover was optional, apparently."],
		"concerned":["A good brochure won't fix what's underneath it.", "Let's get this sorted before I use the word 'thriving.'"],
		"critical":["I can't put a positive spin on this. We need to fix it.", "The grand opening speech is going back in the drawer."],
	},
}

static func department_of(kind: String) -> String:
	return DEPARTMENTS.get(kind, "planning")

static func speaker(id: String, mood: String, month: int, emergency: bool = false) -> Dictionary:
	if not CAST.has(id): id = "planning"
	if not MOODS.has(mood): mood = "neutral"
	var identity: Array = CAST[id]
	var lines: Array = REMARKS[id][mood]
	var quip := String(lines[posmod(month, lines.size())])
	if emergency: quip = "Mayor, the emergency comes first."
	return {"id":id, "name":identity[0], "role":identity[1], "scope":identity[2],
		"mood":mood, "status":mood.capitalize(), "quip":quip,
		"portrait":"res://assets/advisors/%s-%s.png" % [id,mood]}
