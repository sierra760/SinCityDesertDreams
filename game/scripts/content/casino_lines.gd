# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Dealer patter, prompts and refusals for the casino floors.
##
## Each resort has a dealer voice (see ResortThemes). Every voice has at least
## four lines for every event kind in EVENTS. Lines carry no placeholders, so
## the table view can show them as they are.
class_name CasinoLines
extends RefCounted

## Event kinds the table view asks for a line about.
const EVENTS: Array[StringName] = [&"deal", &"win", &"lose", &"push", &"blackjack", &"bust",
	&"jackpot", &"spin", &"crash", &"debut"]

# ── Refusals and reasons ─────────────────────────────────────────────────

const NO_CREDIT := "The cage doesn't extend credit to the city."
const UNKNOWN_RESORT := "This floor isn't open."
const UNKNOWN_GAME := "That game isn't played on this floor."
const BETS_CLOSED := "Bets are closed until the round settles."
const UNKNOWN_SPOT := "That bet isn't on this table."
const BET_TOO_SMALL := "A bet has to be at least a dollar."
const OVER_MAXIMUM := "That's over the table maximum."
const NO_BETS := "Place a bet first."
const ACTION_UNAVAILABLE := "That isn't open right now."
const FARO_BOTH_WAYS := "A rank can't be backed and coppered at once."
const BAD_TARGET := "Set the cash-out between 1.01x and 1,000x."
const BAD_MULTIPLIER := "That multiplier isn't on the board."
const MULTIPLIER_FALLS := "The multiplier only climbs."
const ROUND_OPEN := "Finish the round before leaving the table."
const QUIT_SEATED := "Finish the round and leave the table first."
const EJECTED := "The resort closed around you."

# ── Prompts ──────────────────────────────────────────────────────────────

const ENTER_PROMPT := "F to enter %s"
const ENTER_PROMPT_TOUCH := "Interact to enter %s"
const PLAY_PROMPT := "F to play %s · %s minimum"
const PLAY_PROMPT_TOUCH := "Interact to play %s · %s minimum"
const EXIT_PROMPT := "F to step outside"
const EXIT_PROMPT_TOUCH := "Interact to step outside"
const LEAVE_TABLE := "Leave table"

## voice -> event kind -> lines
const LINES: Dictionary = {
	&"assayer": {
		&"deal": [
			"Fresh ore on the scales. Let's see what it weighs.",
			"Cards out of the shoe and onto the felt. Assay begins.",
			"Sample's drawn. Read it slow.",
			"Every claim gets a fair weighing. Here's yours.",
		],
		&"win": [
			"Assays rich. The office pays in full.",
			"That's a paying vein, Mayor. Mark it on the map.",
			"Pure silver, no slag. Collect at the scale.",
			"The numbers hold up. Pay the claim.",
		],
		&"lose": [
			"Fool's ore. The office keeps the sample.",
			"Assays at nothing. Better luck at the next seam.",
			"Mostly rock, I'm afraid. The house takes it.",
			"Low grade. The mine stays open; the claim doesn't.",
		],
		&"push": [
			"Weighs the same going out as coming in. Even.",
			"No gain, no loss. The scale sits level.",
			"A standoff at the assay table. Stakes return.",
			"Balanced to the grain. Take it back.",
		],
		&"blackjack": [
			"Ore's assayed at twenty-one. Pays three to two.",
			"Two cards, twenty-one. That's a bonanza.",
			"Richest sample of the day. Three to two.",
			"Blackjack on the scales. Highest grade we pay.",
		],
		&"bust": [
			"Over twenty-one. The tunnel caved in.",
			"Dug too deep. That claim's gone under.",
			"Too heavy for the scale. Bust.",
			"The seam ran out past twenty-one.",
		],
		&"jackpot": [
			"Mother lode! Ring the bell on the hoist.",
			"That's the Comstock itself. Wagons for the silver.",
			"Biggest strike this office has weighed in a year.",
			"Stop the presses at the Dispatch. Mother lode.",
		],
		&"spin": [
			"Wheel's turning. Ore goes where it falls.",
			"Round she goes, like the hoist on the main shaft.",
			"Let it settle. The scale doesn't hurry.",
			"Spinning. Hands off the felt.",
		],
		&"crash": [
			"The timbers gave way. Claim's lost.",
			"Cave-in. The house keeps what's down there.",
			"Shaft collapsed before you got out.",
			"Pressure was too much for the props.",
		],
		&"debut": [
			"Welcome to the Assay Office, Mayor. Everything gets weighed here.",
			"A new face at the scales. Bring your ore.",
			"Mayor on the floor. Mind the copper rails.",
			"First claim of the night is the mayor's. Let's assay it.",
		],
	},
	&"conductor": {
		&"deal": [
			"All aboard. Cards are leaving the station.",
			"On time, on the felt. Here's your hand.",
			"Tickets punched. Dealing now.",
			"Next departure, track one. Cards coming down.",
		],
		&"win": [
			"Arriving on time. Collect your winnings at the window.",
			"Express service. You win.",
			"Right on schedule. Pay the passenger.",
			"First-class result. Step down and collect.",
		],
		&"lose": [
			"Missed the connection. The house takes the fare.",
			"That train has left the station.",
			"Wrong platform tonight. Fare's forfeit.",
			"Delayed indefinitely. The house collects.",
		],
		&"push": [
			"Round trip. You end where you started.",
			"Same station, same fare. A push.",
			"Even exchange at the ticket window.",
			"No charge for this ride. Stakes back.",
		],
		&"blackjack": [
			"Twenty-one on the board. Express pays three to two.",
			"Blackjack, track one. Through service, no stops.",
			"Two cards to the end of the line. Three to two.",
			"Golden spike! Blackjack pays.",
		],
		&"bust": [
			"Off the rails past twenty-one.",
			"Overbooked. That hand busts.",
			"Too many cars on the train. Bust.",
			"Ran the signal. That's a bust.",
		],
		&"jackpot": [
			"Golden spike! The whole roundhouse heard that.",
			"Jackpot on the departure board.",
			"The special has arrived, and it's carrying silver.",
			"Every bell in the station. That's the big one.",
		],
		&"spin": [
			"Turntable's turning. Stand clear.",
			"Wheels in motion. Hold your tickets.",
			"Signal's green. Here we go.",
			"Rolling now. No boarding while the train moves.",
		],
		&"crash": [
			"Derailed. The house clears the track.",
			"Boiler blew. That ride's over.",
			"End of the line, sooner than planned.",
			"Signal failure. The run is lost.",
		],
		&"debut": [
			"Welcome to the Roundhouse, Mayor. Tables run on time here.",
			"The mayor's car has arrived. Find a seat.",
			"First passenger of the evening. Tickets, please.",
			"All aboard, Mayor. The cage is to your left.",
		],
	},
	&"foreman": {
		&"deal": [
			"Pour's starting. Cards in the forms.",
			"Shift's on. Dealing the first lift.",
			"Hard hats on. Cards coming down.",
			"Concrete's mixed. Here's the hand.",
		],
		&"win": [
			"Load holds. You win.",
			"Turbines are humming. Pay the man.",
			"Solid footing. That's a winner.",
			"Passed inspection. Collect.",
		],
		&"lose": [
			"Spillway's open. Banker takes it.",
			"Didn't hold the pressure. The house wins.",
			"Cracked in the form. Lost.",
			"Shift's over for that bet.",
		],
		&"push": [
			"Level water both sides. Even.",
			"Pressure's equal. Stakes back.",
			"A dead heat at the gauge.",
			"Nothing gained, nothing lost. Reset the forms.",
		],
		&"blackjack": [
			"Twenty-one on the gauge. Three to two.",
			"Blackjack. That's a clean pour.",
			"Built to spec, two cards. Pays three to two.",
			"Top of the dam. Blackjack.",
		],
		&"bust": [
			"Over capacity. Bust.",
			"Too much water behind it. That hand broke.",
			"Past the rated load. Bust.",
			"Gauge went red. Bust.",
		],
		&"jackpot": [
			"Full power! Every turbine on the line.",
			"That's the whole river coming through. Jackpot.",
			"Lights on across three states. Big win.",
			"Crown of the dam. Jackpot.",
		],
		&"spin": [
			"Turbine's spinning up.",
			"Gates open. Watch it run.",
			"Here comes the flow.",
			"Steady now. Let the wheel do the work.",
		],
		&"crash": [
			"Penstock burst. The run is over.",
			"Overload. Breakers tripped.",
			"Structure failed. The house keeps it.",
			"Spillway took it all.",
		],
		&"debut": [
			"Welcome to the Powerhouse, Mayor. Hard hats are optional.",
			"New hand on the crew. Glad to have you.",
			"The mayor's inspecting the floor. Look sharp.",
			"First shift for the mayor. Pick a table.",
		],
	},
	&"flight_director": {
		&"deal": [
			"Countdown is go. Dealing.",
			"Systems nominal. Cards on the pad.",
			"T-minus five. Here's your hand.",
			"Payload loaded. Dealing now.",
		],
		&"win": [
			"We have payout. Mission success.",
			"Stable orbit. You win.",
			"Telemetry confirms a win.",
			"Splashdown on target. Collect.",
		],
		&"lose": [
			"Mission scrubbed. The house recovers the stake.",
			"Lost signal. That bet's gone.",
			"Trajectory's off. The house wins.",
			"Abort, abort. Stake lost.",
		],
		&"push": [
			"Holding at T-minus zero. Even.",
			"Back on the pad. Stakes return.",
			"No lift, no loss. A push.",
			"Orbit decayed to where we started.",
		],
		&"blackjack": [
			"T-minus nothing. Twenty-one, we have payout.",
			"Blackjack. Clean ignition, three to two.",
			"Two-card orbit. Pays three to two.",
			"Twenty-one on the board. Go for payout.",
		],
		&"bust": [
			"Over twenty-one. We've lost the vehicle.",
			"Overburn. Bust.",
			"Past the limit. Mission lost.",
			"Too much thrust. That hand busts.",
		],
		&"jackpot": [
			"Escape velocity! Jackpot.",
			"We're in deep space now. Big win.",
			"Every light on the console. Jackpot.",
			"That's one for the history books, Mayor.",
		],
		&"spin": [
			"Ignition. We have liftoff.",
			"Gimbals free. Here we go.",
			"Spinning up the gyros.",
			"All stations, stand by.",
		],
		&"crash": [
			"Engine cutoff. We've lost the vehicle.",
			"Burn-out. The stake goes with it.",
			"Range safety called it. Lost.",
			"Static fire ends early. Stake lost.",
		],
		&"debut": [
			"Welcome to Mission Control, Mayor. You're go for play.",
			"New flight crew on the floor. Strap in.",
			"The mayor's in the building. All consoles, look sharp.",
			"First mission for the mayor. Pick a station.",
		],
	},
}


## Every line a voice has for an event kind; [] for unknown pairs.
static func lines(voice: StringName, event: StringName) -> Array:
	var by_event: Dictionary = LINES.get(voice, {})
	return by_event.get(event, [])


## One line for a voice and event. Picks with `rng` when given, otherwise by
## `index` (wrapped), so tests and the table view can choose deterministically.
static func line(voice: StringName, event: StringName, rng: CasinoRng = null, index: int = 0) -> String:
	var options := lines(voice, event)
	if options.is_empty():
		return ""
	var i := rng.below(options.size()) if rng != null else posmod(index, options.size())
	return String(options[i])


## The voice event for a settled outcome's reaction.
static func reaction_event(reaction: String) -> StringName:
	var event := StringName(reaction)
	return event if event in EVENTS else &"lose"


## Whole dollars with thousands separators: 25000 -> "$25,000".
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-$" if amount < 0 else "$") + digits + grouped


static func below_minimum(minimum: int) -> String:
	return "The table minimum is %s." % money(minimum)


static func enter_prompt(resort_name: String, touch: bool = false) -> String:
	return (ENTER_PROMPT_TOUCH if touch else ENTER_PROMPT) % resort_name


static func play_prompt(game_name: String, minimum: int, touch: bool = false) -> String:
	return (PLAY_PROMPT_TOUCH if touch else PLAY_PROMPT) % [game_name, money(minimum)]


static func exit_prompt(touch: bool = false) -> String:
	return EXIT_PROMPT_TOUCH if touch else EXIT_PROMPT
