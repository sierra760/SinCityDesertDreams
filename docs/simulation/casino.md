# Casino play at the gaming resorts

System key: `casino` (`game/scripts/sim/casino_system.gd`).
Parameters: `game/scripts/sim/data/casino_params.gd` (`CasinoParams`).
Game logic: `game/scripts/casino/` (`CasinoGame` and the nine games).
Resort themes: `game/scripts/casino/resort_themes.gd` (`ResortThemes`).
Dealer patter and prompts: `game/scripts/content/casino_lines.gd` (`CasinoLines`).

## Purpose

Each of the four gaming resorts has a casino floor the mayor can walk into from
Explore and play at. The mayor plays with the city treasury: a committed stake
leaves `city.funds`, and whatever the round returns comes back into it. The
casino system is the only code that moves that money. It keeps a ledger per
resort, and the Desert Dispatch reports the mayor's first visit and any month
of large winnings or losses. Play is not a budget line and does not touch
demand, approval or any map, and the games never draw from the simulation's
random stream; its effects reach the rest of the city only through the
treasury and the newspaper (see rule 7).

## Inputs

- `city.funds` – the treasury. Table limits and refusals are computed from it.
- `clock.day` – stamped on the ledger when a round settles.
- The resort key (`arcology_comstock`, `arcology_junction`, `arcology_boulder`,
  `arcology_orbit`) and the game kind of each transaction, passed in by the
  caller through the `Simulation` facade.

## Outputs

- `city.funds` – debited by a commit, credited by a settle or a refund.
- A private ledger per resort: `rounds`, `staked`, `returned`, `best_win`,
  `worst_loss`, `month_net`, `year_net`, `last_day`.
- A private flag recording that the debut story has been reported.

Events:

| Call | Kind | Args |
|---|---|---|
| `report` | `casino_debut` | `{place, amount}`: the resort name and the first round's net |
| `report` | `casino_windfall` | `{place, amount}`: the resort name and the month's net winnings |
| `report` | `casino_losses` | `{place, amount}`: the resort name and the month's net losses, as a positive number |

`amount` is printed as money in the story (`{count}`), `place` as the resort
name (`{place}`).

## Timing

- **On demand**, from the `Simulation` facade, while the city is paused or
  running: `casino_commit`, `casino_settle`, `casino_refund`. Each call is
  followed by the facade publishing the treasury (`funds_changed`) and the
  day's reports, so a paused city still shows the new balance and queues the
  story.
- **Monthly, day 22**, before the newspaper prints: month stories, then every
  resort's `month_net` returns to zero. A "month" of play is therefore the
  stretch between two day-22 issues.
- **Yearly** (last day of December): every resort's `year_net` returns to zero.
- `daily` does nothing.

## Rules

1. **Limits.** `limits(resort, funds)` is `{minimum, maximum}` where `minimum`
   is the resort's table minimum and `maximum` is the smaller of the table
   maximum and the treasury. A game enforces `maximum` on everything a round
   can put at risk, including blackjack doubles and splits, so a round can
   never stake more than the treasury held when it began. An unknown resort
   has limits `{0, 0}`.
2. **Who may play.** `can_play(resort, funds)` refuses an unknown resort and a
   treasury below the table minimum ("The cage doesn't extend credit to the
   city. Tables here start at $250; the treasury has $180.", built by
   `CasinoLines.no_credit`). The treasury never goes negative because of
   play. The table view also asks for a second confirmation before an
   opening stake of more than half of the treasury; that is presentation
   only and changes nothing here.
3. **Commit.** `commit_round(ctx, resort, game, staked)` debits `staked` from
   the treasury and returns true. It refuses (returns false, no change) an
   unknown resort, a game the resort does not offer, a stake of zero or less,
   and a stake larger than the treasury. A round may commit more than once:
   the opening stake when the committing action is accepted, then once for
   each double or split.
4. **Settle.** `settle_round(ctx, resort, game, staked, returned)` credits
   `returned` (never negative) and records the round: `rounds` + 1, `staked`
   and `returned` accumulate, the round's net (`returned − staked`) is added
   to `month_net` and `year_net`, `best_win` keeps the largest net and
   `worst_loss` the smallest, `last_day` is the current day. `staked` is the
   round total, including doubles and splits. The first round the city ever
   settles reports `casino_debut` once.
5. **Refund.** `refund_round(ctx, resort, game, staked)` credits `staked` back
   without a ledger entry. It is used when a city closes in the middle of a
   committed round.
6. **Month stories.** On day 22, for each resort in `ResortThemes` order, a
   `month_net` of at least `STORY_NET` reports `casino_windfall` and one of at
   most `−STORY_NET` reports `casino_losses`. Then `month_net` is reset for all.
7. **Randomness.** Games draw only from their own `CasinoRng`; dealing,
   spinning and rolling never read or advance the simulation random stream
   (`sim.rng`). Play is still not invisible to the simulation: settled rounds
   change `city.funds`, which the budget and bonds read, and the three casino
   stories enter the newspaper queue, whose formatting draws from `sim.rng`.
   A city with play and the same city without it therefore diverge from the
   next newspaper issue on.

## Games

Every resort offers blackjack, roulette, slots, a money wheel and video poker,
plus one signature game: faro (Comstock Grand), chuck-a-luck (Silver Junction),
baccarat (Boulder Crown) and a launch game called trajectory (Desert Orbit).
"Returned" includes the stake.

- **Blackjack.** Six-deck shoe, reshuffled before a round when fewer than
  `BLACKJACK_RESHUFFLE` cards remain. Dealer stands on every 17. A two-card 21
  returns 2½ times the stake (rounded down); a dealer two-card 21 beats every
  other hand; both is a push. Double on any first two cards (one more card).
  Split once, on two cards of the same rank; split aces receive one card each.
  A 21 after a split is not a two-card 21. No insurance, no surrender. A win
  returns twice the hand's stake, a push returns it.
- **Roulette.** Single zero, pockets 0–36. Straight up returns 36×; red,
  black, odd, even, low (1–18) and high (19–36) return 2×; dozens and columns
  return 3×. Zero loses every outside bet. Any number of spots; the maximum
  applies to the total.
- **Slots.** Three reels of 20 authored stops, one line through the middle.
  Three bonus symbols return 200×, three of the fifth symbol 60×, fourth 30×,
  third 15×, second 10×, first 5×; otherwise two bonus symbols anywhere return
  5× and one returns 2×. The strips give a long-run return of about 91%.
- **Money wheel.** 54 segments: 24 × "1", 15 × "2", 7 × "5", 4 × "10",
  2 × "20" and one each of the resort's two emblems. A segment pays its number
  to one (emblems 40 to 1); bets on other segments lose.
- **Video poker.** Jacks or better from one fresh 52-card deck per hand. Deal
  five, hold any, draw replacements. Returns as multiples of the bet: royal
  flush 800, straight flush 50, four of a kind 25, full house 9, flush 6,
  straight 4, three of a kind 3, two pair 2, a pair of jacks or better 1.
- **Faro.** One 52-card deck. Bets go on ranks. Each turn shows the banker's
  card (bets on its rank lose) and then the player's card (bets on its rank
  win even money). The same rank on both cards is a split and the house takes
  half the bet. A coppered bet backs the rank to lose, with the outcomes
  inverted. A bet whose rank does not show is returned. The deck is
  reshuffled before a turn when fewer than four cards remain.
- **Chuck-a-luck.** Three dice. A bet on a number returns the stake plus even
  money for each die showing it. The any-triple bet pays 30 to 1.
- **Baccarat.** Eight decks. Player and banker each get two cards; totals are
  the last digit of the sum (tens and court cards count zero). An 8 or 9 on
  two cards stands for both. Otherwise the player draws on 0–5; the banker
  draws on 0–5 when the player stood, and when the player drew a third card
  the banker draws on 0–2, on 3 unless that card was an 8, on 4 against 2–7,
  on 5 against 4–7 and on 6 against 6–7, and stands on 7. Player bets win even
  money; banker bets win even money less a 5% commission (rounded down); tie
  pays 8 to 1, and player and banker bets are returned on a tie.
- **Trajectory.** At launch a hidden burn-out multiplier M is drawn: one time
  in 33 the engine fails at 1.00×; otherwise M = max(1.00, ⌊100 × 0.97 /
  (1 − u)⌋ / 100) for uniform u, capped at `TRAJECTORY_MAX_MULTIPLIER`. The
  displayed multiplier climbs as e^(0.12 t). Cashing out at m < M returns
  ⌊stake × m⌋; reaching M first loses the stake. Multipliers are kept to
  hundredths. An optional automatic cash-out target can be set at launch.

## Parameters

| Name | Meaning |
|---|---|
| `TABLE_LIMITS` | per resort: table minimum and table maximum |
| `STORY_NET` | month net, won or lost, that makes the Dispatch |
| `CHIP_STEPS` | multiples of the minimum offered as chips |
| `BLACKJACK_DECKS`, `BLACKJACK_RESHUFFLE` | shoe size and the cards left that force a reshuffle |
| `BLACKJACK_NATURAL_NUMERATOR`, `BLACKJACK_NATURAL_DENOMINATOR` | the two-card 21 payout ratio |
| `ROULETTE_POCKETS`, `ROULETTE_RED`, `ROULETTE_RETURNS` | wheel size, red pockets and returns per bet group |
| `SLOT_STRIPS`, `SLOT_TRIPLE_RETURNS`, `SLOT_BONUS_RETURNS` | reel strips and the paytable |
| `WHEEL_LAYOUT`, `WHEEL_RETURNS` | the 54 segments in order and the return per segment |
| `POKER_RETURNS` | video poker paytable |
| `FARO_RESHUFFLE` | cards left that force a reshuffle |
| `CHUCK_TRIPLE_RETURN` | any-triple return |
| `BACCARAT_DECKS`, `BACCARAT_RESHUFFLE`, `BACCARAT_COMMISSION_PERCENT`, `BACCARAT_TIE_RETURN` | shoe, reshuffle point, banker commission, tie return |
| `TRAJECTORY_FAIL_ONE_IN`, `TRAJECTORY_EDGE`, `TRAJECTORY_RATE`, `TRAJECTORY_MAX_MULTIPLIER` | engine-failure chance, house edge, climb rate and multiplier cap |

## Save state

`save()` returns `ledgers` (resort key → ledger) and `debut` (bool). `load()`
fills missing resorts and fields with zeros, so saves made before the casino
existed load with empty ledgers. Nothing about a round in progress is saved:
a city that closes during a committed round refunds the stake first.

## Public interface

```
limits(resort: StringName, funds: int) -> Dictionary      # {minimum, maximum}
can_play(resort: StringName, funds: int) -> Dictionary    # {ok, reason}
commit_round(ctx, resort, game, staked: int) -> bool
settle_round(ctx, resort, game, staked: int, returned: int) -> void
refund_round(ctx, resort, game, staked: int) -> void
ledger(resort: StringName) -> Dictionary
total_ledger() -> Dictionary
```

`Simulation` wraps the three transactions as `casino_commit`, `casino_settle`
and `casino_refund`, and `casino()` returns the system.
