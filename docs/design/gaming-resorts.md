# Gaming resorts

Each of the ten Gaming Resorts has a casino floor you can walk into from
Explore. The mayor plays at its tables with the city treasury: a bet leaves
the treasury, a win comes back to it, and the Desert Dispatch keeps an eye on
the mayor's nights out. Play reaches the rest of the city only through the
treasury and the newspaper.

## Building the six additional resorts

The six additional designs occupy 4 × 4 lots and append native building IDs
256–261. All six unlock with the existing Comstock technology, including its
invention year stored in an older city; they add no random invention draws.
The original four keep their identities and Desert Orbit keeps its launch
behavior. Their themes, named games and palettes are recorded in
`tools/resort_expansion.json`; construction costs and resident capacities are
provided by the building/tools and reward parameter tables.

| ID | Resort | Saved key | Cost | Resident capacity |
|---|---|---|---:|---:|
| 256 | The Fix | `arcology_fix` | $320,000 | 35,000 |
| 257 | Six-Week Alibi | `arcology_alibi` | $140,000 | 30,000 |
| 258 | Velvet Wardrobe | `arcology_velvet` | $220,000 | 30,000 |
| 259 | The Afterglow | `arcology_afterglow` | $500,000 | 45,000 |
| 260 | Last Resort | `arcology_last` | $60,000 | 35,000 |
| 261 | Dust Republic | `arcology_dust` | $95,000 | 40,000 |

New native saves use version 2 and store building IDs in 16 bits. Existing
version 1 cities remain readable, and classic imports keep their original
IDs. See [File formats](file-formats.md).

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
| The Fix | The Back Room | Obsidian, brass and emerald | the foreman |
| Six-Week Alibi | The Fresh Start | Blush pink, mint and warm brass | the conductor |
| Velvet Wardrobe | The Scarlet Salon | Oxblood, black wood and amber | the assayer |
| The Afterglow | The Observation Lounge | Ivory, copper, acid mint and orange | the flight director |
| Last Resort | The Last Bank | Weathered sandstone, bottle glass and turquoise | the assayer |
| Dust Republic | The Common Ground | Rust, bone and ultraviolet | the conductor |

## Playing a table

Walk up to a table or machine; the prompt names it and its minimum, for
example **F to play Assay Twenty-One · $100 minimum**. Pressing F sits you
down: the city pauses, Explore holds still, the camera settles on the table
and the table overlay opens with the resort's name, the treasury, the game
and a bet bar. The resort's dealer comments on every deal and result.

| Key | Action |
| --- | --- |
| `1`–`5` | Place a chip on the selected spot: 1, 2, 5 or 10 times the table minimum, or Max (the rest of what you can bet). The digit row works by key position, so AZERTY players need no Shift |
| `+` / `−` | Add or take back another of the selected chip (hold to repeat; no other table key repeats while held) |
| Arrow keys | Choose a betting spot (roulette, money wheel, faro, chuck-a-luck, baccarat) |
| `Enter` | The table's main action: deal, spin, pull, turn, roll, launch; stand in blackjack (Enter never hits); draw in video poker; cash out a launch; then next round. Enter on a chip or `+`/`−` also plays the main action instead of betting again |
| `H` / `S` / `D` / `P` | Blackjack hit, stand, double, split; `D` also draws in video poker |
| `1`–`5` (video poker, after the deal) | Hold or release a card |
| `Space` | Cash out a launch (Static Fire) |
| `A` | Choose an automatic cash-out target before a launch |
| `R` | Repeat the last bet (after a result it starts the next round with it) |
| `Backspace` | Clear the bets |
| `Escape` | Finish a result's animation; a second Escape leaves the table |

On touch, tap a chip, tap a spot to place it, and tap the action buttons;
the same buttons work with a mouse. **Rules** shows how the game plays and
pays. **Leave table** (or Escape) returns you to the floor, restores the
city's previous speed and resumes Explore where you stood. Bets you have not
played yet are simply returned. A round that has started must finish first,
so Leave table is unavailable until the hand, spin or launch is settled.

The first chip goes on the table's plainest bet: Red in roulette and the 1
segment on the money wheel. The bet bar says where the next chip goes
("Chips go on Red · pays 1 to 1"). After a result, **Same bet** (or `R`)
starts the next round with the same bets on the felt.

A round that would stake more than half of the treasury asks first: the
dealer says, for example, "Bet $8,000 of the city's $8,000? Press Enter or
Deal again to confirm." Pressing Enter or the button again plays it; changing
the bets cancels the question.

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

The six additional resorts offer the shared games and six original signature games:

| Resort | Blackjack | Roulette | Slots | Money wheel | Video poker | Signature |
|---|---|---|---|---|---|---|
| The Fix | House Twenty-One | Inside Track Roulette | The Skim | Silent Partner Wheel | Clean Slate Draw | Vault Circuit |
| Six-Week Alibi | Second Chance Twenty-One | Separate Ways Roulette | Six-Week Streak | Turning Point Wheel | Fresh Start Draw | Separate Ways |
| Velvet Wardrobe | Encore Twenty-One | Scarlet Roulette | After Hours | Curtain Call Wheel | Backstage Draw | Encore |
| The Afterglow | Daybreak Twenty-One | Fallout Roulette | Radiant Fortune | Sunset Wheel | Bright Side Draw | Afterglow Forecast |
| Last Resort | Still Standing Twenty-One | Boomtown Roulette | House Remains | Prosperity Wheel | Ghost Town Draw | Last Bank Contracts |
| Dust Republic | Open Road Twenty-One | Playa Roulette | Dust Dividend | Free State Wheel | Common Ground Draw | Common Pot |

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

## The six original signature games

- **Vault Circuit:** open up to three locks. Quiet offers80% success and ×1.20 gross; Force55% and ×1.70. Each failure loses the accumulated bank. Collect after a success or risk another lock.
- **Separate Ways:** choose Direct (96%, ×1 gross), Night (48%, ×2) or Express (24%, ×4), then travel bare or covered. Coverage reduces a successful return to80% and returns25% of the stake on failure; no extra debit.
- **Encore:** a theatrical rose/fan/spotlight duel with visible crowd weights. Rose beats fan, fan beats spotlight, spotlight beats rose. Ties hold the purse, wins multiply it by1.30, losses end the show. Bow out or continue for up to three encores. The opening purse is96% of the stake.
- **Afterglow Forecast:** allocate bets to Steady, Pulse and Surge using the visible forecast probabilities. One common observation resolves all three, so a surge also produces pulse and steady. Exact gross multipliers appear before betting.
- **Last Bank Contracts:** draft one of three face-up offers and choose Rise, Fall or Match against the remaining49-card bank. Aces are low; exact card counts and gross returns appear before choosing.
- **Common Pot:** inspect three fictional crew pledges, then claim one, two or three virtual shares of a house-sponsored pot. A larger claim offers a larger payout with a lower chance of agreement. The game shows the fraction, probability and gross return.

Every game rounds returns down to whole dollars and commits the stake once.
The action buttons support mouse, touch and keyboard focus. If backgrounded,
Vault attempts its first lock quietly then banks; Separate Ways takes Direct
without cover; Encore bows; Last Bank drafts the first offer and takes the
more likely Rise/Fall contract; Common Pot claims one share. Afterglow resolves
its observation immediately. These choices settle the committed risk.

## Despicable's: groceries and low-stakes games

Every Despicable's corner store (building 126) can be entered from its front
door in Explore. Its 12 × 10 m interior splits evenly between stocked grocery
shelves, drink coolers, coffee and checkout on the left, and four slot machines
plus two video poker terminals on the right. Walk up to any machine and use the
same interaction as at a resort. Return to the door mat to step outside.

The Low-Down Lounge offers **Low-Down Luck** slots and **Five-Finger Draw** video
poker, with its own coral-and-teal illustrations and playing cards. It is
available as soon as a corner store exists, without a gaming-resort unlock or
purchase. Limits are **$1–$1,000 per round**, further limited by the treasury.
The store uses the same round settlement, backgrounding, ledger and save rules
as the resorts; all stores in a city share the Despicable's play history.

## Limits and the treasury

| Resort | Minimum | Maximum |
| --- | --- | --- |
| Despicable's | $1 | $1,000 |
| Comstock Grand | $100 | $10,000 |
| Silver Junction | $250 | $25,000 |
| Boulder Crown | $500 | $50,000 |
| Desert Orbit | $1,000 | $100,000 |
| The Fix | $2,200 | $220,000 |
| Six-Week Alibi | $400 | $40,000 |
| Velvet Wardrobe | $1,200 | $120,000 |
| The Afterglow | $4,000 | $400,000 |
| Last Resort | $50 | $5,000 |
| Dust Republic | $100 | $10,000 |

The six additions follow the original four's cost progression and 100×
maximum-to-minimum spread. Above Desert Orbit, each additional $1,000 of
construction cost adds $10 to the minimum; Alibi fits between Junction and
Boulder, and the two lower-cost resorts use accessible rounded stakes.

Every bet comes from the city treasury, and the table's maximum is never more
than the treasury holds, including blackjack doubles and splits. The treasury
therefore never goes below zero because of play. With less than the table
minimum the resort refuses to seat you: "The cage doesn't extend credit to the
city. Tables here start at $250; the treasury has $180." The same line
explains why the chips grey out when the treasury falls below the minimum
between rounds. When the treasury caps the maximum below the table's own,
the welcome line says how far it covers. The stake leaves the treasury when the round starts and the return
arrives when it settles; the status bar follows both while the city is paused.

Play is not a budget line: it never appears in the budget report, and it
changes nothing but the treasury itself. If the city closes or another city
is loaded in the middle of a round, the stake is returned first. If the app
goes to the background (on iPhone and iPad, leaving the app or opening the
Control Center), the round is played out as it stands instead: blackjack
stands, video poker draws with the cards you hold, and a launch cashes out at
the multiplier shown. Leaving the app never takes back a bad hand. When you
come back, the status line says what happened, for example "Your Assay
Twenty-One hand was played out while you were away: -$1,000." On the
desktop, a launch stops climbing while the window is in the background and
continues where it left off. A round in progress is never saved. Quitting
while seated waits until you finish the round and leave the table, and the
table says so.

## Ledger, Inspect and the news

All ten resort designs have separate persisted play histories. The city keeps
a ledger for each resort: rounds played, totals staked and
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
