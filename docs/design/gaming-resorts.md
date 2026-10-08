# Gaming resorts

Each of the four Gaming Resorts has a casino floor you can walk into from
Explore. The mayor plays at its tables with the city treasury: a bet leaves
the treasury, a win comes back to it, and the Desert Dispatch keeps an eye on
the mayor's nights out. Play reaches the rest of the city only through the
treasury and the newspaper.

## Entering a resort

Build a Gaming Resort, then choose **View → Explore City** and walk up to the
resort's front doors. A resort faces the larger map row unless that side has
no street; then it turns its front to the side with the most adjacent road
(east, west, then north on ties). The facing is worked out when the city is
loaded and again when a nearby road changes; it is never saved. A resort with
no adjacent road keeps the original facing. Near
the doors the prompt reads **F to enter Comstock Grand** (on touch, **Interact
to enter …**). Pressing F fades to the entrance mat inside a fully enclosed
hall; the usual third-person camera follows you. The mat by the door offers
**F to step outside** and returns you to the resort's front step, facing the
street. Return to Build works from inside as it does anywhere else.

Inside, marinas and vehicles do not answer F. If the resort is demolished or
replaced while you are inside, you are put back outside with a message.

| Resort | Floor | Theme | Dealer |
| --- | --- | --- | --- |
| Comstock Grand | The Assay Office | Silver-boom sandstone, copper and walnut, gas-lamp chandeliers | the assayer |
| Silver Junction | The Roundhouse | Railroad terminal: green-glass train shed, brass trusses, station clock | the conductor |
| Boulder Crown | The Powerhouse | 1930s dam-construction Deco: sandstone pylons, turquoise terrazzo, turbine ring | the foreman |
| Desert Orbit | Mission Control | Atomic-age rocket base: planetarium ceiling, starburst chandeliers, countdown clock | the flight director |

## Playing a table

Walk up to a table or machine; the prompt names it and its minimum, for
example **F to play Assay Twenty-One · $100 minimum**. Pressing F sits you
down: the city pauses, Explore holds still, the camera settles on the table
and the table overlay opens with the resort's name, the treasury, the game
and a bet bar. The resort's dealer comments on every deal and result.

| Key | Action |
| --- | --- |
| `1`–`5` | Place a chip on the selected spot: 1, 2, 5 or 10 times the table minimum, or Max (the rest of what you can bet) |
| `+` / `−` | Add or take back another of the selected chip |
| Arrow keys | Choose a betting spot (roulette, money wheel, faro, chuck-a-luck, baccarat) |
| `Enter` | The table's main action: deal, spin, pull, turn, roll, launch, then next round |
| `H` / `S` / `D` / `P` | Blackjack hit, stand, double, split; `D` also draws in video poker |
| `1`–`5` (video poker, after the deal) | Hold or release a card |
| `Space` | Cash out a launch (Static Fire) |
| `A` | Choose an automatic cash-out target before a launch |
| `R` | Repeat the last bet |
| `Backspace` | Clear the bets |
| `Escape` | Leave the table |

On touch, tap a chip, tap a spot to place it, and tap the action buttons;
the same buttons work with a mouse. **Rules** shows how the game plays and
pays. **Leave table** (or Escape) returns you to the floor, restores the
city's previous speed and resumes Explore where you stood. Bets you have not
played yet are simply returned. A round that has started must finish first,
so Leave table is unavailable until the hand, spin or launch is settled.

## The games

Every resort offers five shared games under its own names, plus one signature
game. Returns include the stake.

| Game | Comstock Grand | Silver Junction | Boulder Crown | Desert Orbit |
| --- | --- | --- | --- | --- |
| Blackjack | Assay Twenty-One | Dining Car Twenty-One | Intake Twenty-One | Countdown Twenty-One |
| Roulette | Winding Wheel Roulette | Turntable Roulette | Turbine Roulette | Orbital Roulette |
| Slots | Silver Strike | Timetable | Powerhouse | Launch Pad |
| Money wheel | Prospector's Wheel | Roundhouse Wheel | Penstock Wheel | Gravity Wheel |
| Video poker | Bonanza Draw | Sleeper Car Draw | High Scaler Draw | Mission Draw |
| Signature | Faro at the Assay Office | Birdcage (chuck-a-luck) | Spillway Baccarat | Static Fire (trajectory) |

- **Blackjack:** six decks; the dealer stands on all 17s; a two-card 21 pays
  3 to 2; double on any first two cards; split once (split aces get one card
  each); no insurance or surrender.
- **Roulette:** single zero. A number pays 35 to 1; red/black, odd/even and
  low/high pay even money; dozens and columns pay 2 to 1. Bet on as many spots
  as you like; the table maximum applies to the total.
- **Slots:** three reels, one line, five themed symbols and the resort's bonus
  symbol. Three bonus symbols pay 200 times the bet.
- **Money wheel:** a 54-segment wheel. A segment pays its number to one; the
  resort's two emblems pay 40 to 1.
- **Video poker:** jacks or better. Deal five cards, hold any, draw once. A
  royal flush returns 800 times the bet.
- **Faro:** bet on ranks. Each turn shows the banker's card (bets on it lose)
  then the player's card (bets on it win even money); a pair is a split and
  the house takes half. A coppered bet backs a rank to lose.
- **Chuck-a-luck:** three dice in a cage. A number pays even money for each
  die showing it; any triple pays 30 to 1.
- **Baccarat:** eight decks and the standard drawing rules. Player pays even
  money, banker even money less 5%, tie 8 to 1.
- **Trajectory:** launch, watch the multiplier climb, and cash out before the
  engine burns out. Cashing out returns the bet times the multiplier; burning
  out loses it. You may set an automatic cash-out target before launch.

## Limits and the treasury

| Resort | Minimum | Maximum |
| --- | --- | --- |
| Comstock Grand | $100 | $10,000 |
| Silver Junction | $250 | $25,000 |
| Boulder Crown | $500 | $50,000 |
| Desert Orbit | $1,000 | $100,000 |

Every bet comes from the city treasury, and the table's maximum is never more
than the treasury holds, including blackjack doubles and splits. The treasury
therefore never goes below zero because of play. With less than the table
minimum the resort refuses to seat you: "The cage doesn't extend credit to the
city." The stake leaves the treasury when the round starts and the return
arrives when it settles; the status bar follows both while the city is paused.

Play is not a budget line: it never appears in the budget report, and it
changes nothing but the treasury itself. If the city closes or another city
is loaded in the middle of a round, the stake is returned first. If the app
goes to the background (on iPhone and iPad, leaving the app or opening the
Control Center), the round is played out as it stands instead: blackjack
stands, video poker draws with the cards you hold, and a launch cashes out at
the multiplier shown. Leaving the app never takes back a bad hand. On the
desktop, a launch stops climbing while the window is in the background and
continues where it left off. A round in progress is never saved. Quitting
while seated waits until you finish the round and leave the table, and the
table says so.

## Ledger, Inspect and the news

The city keeps a ledger for each resort: rounds played, totals staked and
returned, the best win and worst loss, and the net for the month and the
year. It is saved with the city. **Inspect** on a resort lot shows its
**Casino floor** and the **Mayor's play this year** (for example "+$1,200" or
"-$500"). The ledger belongs to the resort design, not to one lot: with two
Comstock Grands standing, both show the same figure, written as "+$1,200
across 2 floors". The Desert Dispatch runs a story the first time the mayor plays,
and in any month the mayor wins or loses $25,000 or more at one resort.

## Determinism

The tables draw their cards, spins and rolls from their own random numbers,
never from the simulation's, and walking the casino floor changes nothing.
Settled rounds do change the treasury, though, and the budget and bonds read
the treasury; and the three casino stories join the newspaper's queue, whose
story formatting draws from the simulation's random numbers. So a city where
the mayor plays and the same city where the mayor does not diverge from the
next newspaper issue on.

Implementation: game rules live in `game/scripts/casino/`, the treasury,
ledger and stories in the `casino` simulation system (see
[Casino play](../simulation/casino.md)), the table overlay in
`game/scripts/ui/casino/`, and the halls in
`game/scripts/exploration/resorts/` (see [Resort interiors](../art/resort-interiors.md)).
