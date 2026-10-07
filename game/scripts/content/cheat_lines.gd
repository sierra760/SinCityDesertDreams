# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Codes and casino patter for the deliberately entered cheat codes.
extends RefCounted

## Typed code (lowercase) to the effect it redeems. One code per effect.
const CODES := {
	"doubledown": &"bet",
	"highroller": &"jackpot",
	"marker": &"marker",
	"chapel": &"chapel",
}
const PROMPT := "Place your bets.\nDOUBLEDOWN wagers a tenth of the treasury.\nMARKER borrows $25,000 at 20% a year."

const CHAPEL := "Do you, Mayor, take this Budget, for richer or (mostly) poorer, through tax hikes and bond issues, until bankruptcy do you part?\n\nThe Elvis impersonator now pronounces you city and treasury. The rings are on a payment plan."

static func result(ok: bool, title: String, body: String) -> Dictionary:
	return {"ok": ok, "title": title, "body": body}


## Whole dollars with thousands separators: 25000 -> "$25,000".
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-$" if amount < 0 else "$") + digits + grouped
