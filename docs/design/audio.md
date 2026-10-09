# Audio

Status: ten songs, 30 interface sounds and about 75 effects play in the game through
`game/scripts/audio/game_audio.gd`. Effects are not yet positional.

## Direction

The score sounds like the rest of the game looks: mid-century Las Vegas and
the Nevada desert. Lounge swing, exotica, surf guitar and light jazz, played
on a small band of vibraphone, electric piano, upright bass, surf guitar,
combo organ, flute, marimba, strings, muted trumpet, brushes and hand drums.
Songs are written as MIDI and rendered through our own synthesized instrument
bank, so the whole score shares one recognizable sound and stays editable in
any sequencer.

Interface sounds come from the same palette (the notice chime is the
vibraphone), are short, and never compete with the music. Disaster, vehicle
and crowd sounds are realistic, generated from plain-language prompts that
describe the event.

## Pipeline

| Step | Tool | Output |
| --- | --- | --- |
| Songs | MIDI masters in `assets/audio/music/<slug>.mid`, rendered with `tools/audio/instruments.py` | `game/assets/audio/music/<slug>.ogg` |
| Interface | `tools/build_ui_sounds.py` | `game/assets/audio/ui/*.ogg` |
| Effects | `tools/generate_sfx.py` with `tools/audio/sfx_prompts.json` | masters in `assets/audio/sfx/`, game files in `game/assets/audio/sfx/` |

Songs are rendered from their MIDI files alone: program changes choose
instruments (General MIDI numbers, with program 40 on channel 10 selecting
brushes), and controllers 7, 10 and 91 set volume, pan and reverb.

Prompts describe what happens in this game ("Building explosion: deep boom,
debris crashing down"). Never upload another game's audio to a generator,
use it as a reference clip, or name another game in a prompt.

## Event map

Interface (`ui/`):

| Event | Sound |
| --- | --- |
| Button, menu item | `click` |
| Checkbox, option toggle | `toggle` |
| Choose a tool | `tool_select` |
| Zone or building placed | `place_zone` |
| Road, rail, pipe or power line laid | `build_network` |
| Action refused (no money, bad site) | `error` |
| Income, gift money, cheat cash | `cash` |
| Newspaper, advisor or ordinance notice | `notice` |
| Disaster or emergency notice | `alert` |
| Milestone, reward offered | `reward` |
| Window open / close | `window_open`, `window_close` |

City and disasters (`sfx/`):

| Event | Sound |
| --- | --- |
| Bulldoze | `bulldoze`; `bulldozer_loop` while dragging |
| Fire | `fire_loop` at burning tiles; `fire_engine` on dispatch |
| Flood | `flood_loop` |
| Tornado, hurricane | `tornado_loop`, `windstorm_loop` |
| Earthquake | `earthquake` |
| Tsawhawbitts | `giant_roar` |
| Orbital beam strike | `beam_strike` |
| Riot | `riot_loop`, occasional `gunshot`; `police_siren` on dispatch |
| Aircraft crash | `mayday`, `explosion` |
| Helicopter hit | `pilot_hit` |
| General emergency, military dispatch | `civil_siren` |
| Prison escape | `prison_alarm` |
| Ordinance or approval vote results | `crowd_cheer`, `crowd_boo` |
| Airport, seaport, rail traffic | `jet_takeoff`, `jet_landing`, `ship_horn`, `train_pass` |
| Traffic jam | `car_horns` |
| School built or opened | `school_bell` |
| Gaming resort opens | `resort_jackpot` |
| Nuclear meltdown | `meltdown_alarm` |
| Volcano | `volcano_eruption`, then `lava_loop` |
| Firestorm | `firestorm_loop` |
| Hurricane, storms, rainy weather | `rain_loop`, `thunder` (hurricanes add `windstorm_loop`) |
| Aircraft going down | `plane_dive` before `explosion` |
| Building destroyed by a disaster | `building_collapse` |
| Tsawhawbitts walking | `giant_footsteps` |
| Newspaper opened | `newspaper` |
| City growing (quiet bed) | `construction_loop` under `city_day_loop`; `desert_loop` at the edges |

Casino floor and games (`sfx/`, stingers in `ui/`):

| Event | Sound |
| --- | --- |
| On the floor | `casino_floor_loop` |
| Bet placed / chips taken | `chips_bet`, `chips_collect` |
| Cards (blackjack, baccarat, faro) | `card_shuffle`, `card_deal` |
| Slots | `slot_spin`, `slot_reel_stop` per reel, `coins_payout` |
| Roulette | `roulette_spin` |
| Money wheel | `money_wheel_spin` |
| Chuck-a-luck | `dice_cage`, `dice_roll` |
| Video poker | `poker_deal`, `poker_hold` |
| Trajectory | `rocket_launch`, `trajectory_tick` (pitch rises with the multiplier), `rocket_burnout` |
| Win / loss / big win | `casino_win`, `casino_lose`, `casino_big_win`; jackpots add `resort_jackpot` |

Explore (`sfx/`, positional):

| Event | Sound |
| --- | --- |
| Walking | `footsteps_pavement_loop` or `footsteps_sand_loop`, rate follows speed |
| Car | `car_idle_loop`, `car_drive_loop` (pitch follows speed), `car_door`, `car_horn`, `tire_skid` |
| Helicopter | `helicopter_loop` |
| Boats | `boat_motor_loop`, `sailing_loop`; harbor ships `ship_horn` |
| Trains and subway | `train_ride_loop` aboard, `train_doors`, `subway_arrive`, `station_chime` |
| Station elevator | `elevator_loop`, `elevator_ding` |
| Station fountain | `fountain_loop` |

## Songs

| Song | Style | Where it plays |
| --- | --- | --- |
| Glitter Gulch | Big-band swing, B-flat | Title screen theme |
| Swizzle Stick | Medium-swing lounge, F | City playlist |
| Tonopah Turnoff | Surf exotica, D Phrygian dominant | City playlist |
| Cabana Number Nine | Bossa nova, D minor | City playlist |
| Cashier's Cage Cha-Cha | Cha-cha, G minor | City playlist |
| Keno at Three A.M. | Late-night ballad, D-flat (3:30) | City playlist |
| Amargosa Lope | Cowboy trail song, G | City playlist |
| Tip Jar Waltz | Jazz waltz in 3/4, F | City playlist |
| Yucca Flat Luau | Atomic-age exotica, C minor | City playlist |
| Pawn Shop Boogie | Jump-blues shuffle, B-flat | City playlist |

## Playback

`GameAudio` is a node owned by `GameHost`. It plays the title theme while the
title screen is up, then shuffles the city songs (each once per round, never
the title theme) with 30 to 90 seconds of quiet between them. Notices duck the
music 6 dB; a casino table or the casino floor ducks it 10 dB.

It listens to the toolbar, simulation signals (disasters, newspaper stories),
the Explore status, the casino table's `event_played` signal and every button
in the tree; construction results and notices call it directly. Each quarter
second it polls active disasters, the weather and the city size for loops.
Under the Dummy audio driver (headless tests) it records cues without starting
players.

Settings → General → Sound holds Music and Sound effects switches with volume
sliders (`music_enabled`, `effects_enabled`, `music_volume`, `effects_volume`
in the view preferences). Three buses carry them: Music, Effects, Interface;
Interface follows the effects settings.

## Still to make

- Positional effects: Explore and the city view play every effect at the
  listener today; fires, crews and traffic could use 3D players.
- Per-step footsteps synced to the walk cycle (the `footsteps_sand_step_*`
  one-shots exist for this), a casino-floor song, Explore driving music.
- Possibly separate music for the casino floor and for Explore driving, and
  per-step footstep one-shots if looping steps drift from the walk cycle.
