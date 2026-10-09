# User interface

Main (`game/scripts/ui/main.gd`, class `GameHost`) owns the player workflow.
The interface reads `Simulation`, `CityStats` and `City`; construction writes
through `Builder`, and unfounded terrain editing through `TerrainEditor`.
Changing interface size, zoom, analytical views or fullscreen does not advance
simulation time or rewrite a city save.

Main itself handles input, menu dispatch, modal state and the loading screen,
and hands the rest to helpers in `game/scripts/ui/`, each holding a reference
back to the host: `shell_layout.gd` (`GameShellLayout`) places the in-game
chrome inside the safe area and runs the phone Tools drawer;
`city_file_flow.gd` (`CityFileFlow`) runs the New, Load, Save, Import and
Share dialogs, the save-before-leaving prompt, quitting and backups;
`city_session.gd` (`CitySession`) generates, founds, loads and imports cities
and binds them to the simulation and views; `construction_flow.gd`
(`ConstructionFlow`) applies the selected tool, its drag preview and the
construction prompts; `explore_mode_switch.gd` (`ExploreModeSwitch`) enters
and leaves Explore; `preferences_controller.gd` (`PreferencesController`)
applies options and writes them to the preference file; `window_manager.gd`
(`WindowManager`) creates and stacks the report and settings windows; and
`notice_queue.gd` (`NoticeQueue`) shows notices one at a time. Street naming
has its own `street_names_session.gd` (`StreetNamesSession`).

## City workflow

The main menu credits Sierra Burkhart (sierra760) and displays
© 2026 Bristlecone Artists LLC. Its License button opens a scrollable offline
GPLv3-or-later notice and the full GPL text.
The credit footer stays outside the city-action scroll area.

The title screen offers New City, Load City, Import Classic City, Settings and Quit.
On iOS, Quit is hidden because iOS apps do not quit themselves. City → Close
City offers Cancel, Don't Save and Save, then returns to a fresh title after a
successful save or Don't Save, releasing the city and Explore session.
Settings opens above the title screen and contains the Controls tab; closing it
returns keyboard focus to the title.
Settings → General starts with the player's Mayor name. It persists with player
preferences and personalizes the title greeting. New and classic-imported cities
use it; native saves keep the mayor credited in that file. Deliberately changing
the name while a city is open updates the city's credit and marks it unsaved.

City → Share City creates a separate current `.sc2d` snapshot. Load City → Share
copies the selected native save exactly, with its mayor credit shown in details.
The Share City dialog reviews the ready copy before system sharing. Apple builds
use Messages/Mail/AirDrop and other OS services where available. Other desktop
builds reveal the attachment with Show File. iOS also exposes `shared-cities/`
through Files; recipients copy attachments into the game folder, then Browse.
Sharing leaves the city's save path, unsaved-changes state and simulation
untouched. Included cities can't be shared from Load City; open one and save a
personal copy first.

New City's generation controls and minimap-style preview describe the same land
that opens in the editing stage. Terrain tools are free there, the clock stays
paused, and Regenerate and Found City remain reachable. Saving an unfounded map
keeps its stage and generation settings. Founding establishes starting funds
and the simulation; founded saves and imported cities enter play directly.

Play uses one aerial 3D city, menu bar above, construction palette at left,
status strip below and minimap inside the remaining map area. The inspector
opens beside the city; information windows are draggable. There is no playable
2D mode toggle. Eleven data layers and underground pipes/subways stay in 3D.

## Layout and display

The interface uses a mid-century desert palette: warm ivory surfaces, deep teal
headers and selected actions, brass rules, and BioRhyme display headings. The
title uses a full-width BioRhyme “SIN CITY” heading, a quieter tracked “DESERT
DREAMS” edition line, and a desert-modern city illustration below.
The uncropped artwork and grouped actions share one grid; portrait windows stack
the artwork above the actions. Narrow safe areas or a keyboard reserve the whole
column for scrolling actions. Reflow keeps the focused action inside the scroll
viewport.
Supporting copy gives the menu a restrained welcome: “Big plans. Room to grow.”
and “Welcome, Mayor.” Setup prompts explain previewing and free terrain editing;
included-city guidance asks the player to save a personal copy. Button labels
remain direct, and recovery/save consequences stay explicit.
Reports, dialogs, loading feedback and Explore controls share the same theme.
Compact Explore temporarily hides the minimap so it cannot cover actions;
roomy windows and returning to Build restore the saved visibility choice.
Tool icons keep their own colors. Selection text stays light on
teal, and two-color focus outlines remain visible on both light and dark controls.

`DisplayLayout` owns logical coordinates, backing scale, window fitting and
focus guards. Body text is 16 logical pixels, supporting text 14, section
headings 18 and window titles 22. Primary and close controls use 44-pixel targets;
dense table controls may use 40. Ivory and teal colors, 8/12/16 spacing and
visible hover, pressed, focus, disabled and selected states are shared by widgets.
Disabled controls and menu items use their own light warm gray
(`UITheme.TEXT_DISABLED`, about 3:1 on menus), well apart from enabled text, so
an unavailable choice never reads like an available one.

Settings offers Auto, 100%, 125%, 150%, 175% and 200% interface sizes. Backing scale
is applied once. The effective selection is capped to preserve a 640×400 logical
compact layout; Settings reports the cap. The labeled toolbar has two columns
at both sizes: 224 logical pixels wide normally and 196 in compact mode, with
scrolling groups. A Find tools selector
jumps directly to a category and moves keyboard focus into it. The selected tool label
stays visible. The status bar wraps metrics and alerts, shows the current speed,
and offers **Go to emergency** while an incident is active. The same action is
in Disasters; it follows the live hazard and returns Explore to Build. Speed
controls remain in the Speed menu.
The 3D render texture remains at drawable resolution as the UI scale changes.

Window bodies scroll, while titles and actions remain fixed. Dragged windows,
popup menus and captions fit the available logical area after resizing.
New City's form and preview stack in compact mode. Tables may scroll horizontally.
Display settings persist in `user://display.cfg`, separately from city saves;
fullscreen does not overwrite the saved windowed size.

## Input and construction

Load City lists personal saves and recovery copies first, followed by nine
included cities marked **Included city**. Included entries are fully imported
native `.sc2d` saves opened by the native loader; they are credited to the
player's Mayor name and begin paused with no native save path, so Save creates
a personal `.sc2d` copy. A personal save with the same name remains a separate
native entry. `tools/build_bundled_cities.py` regenerates them.

`CityPresentationController` emits map click, hover and drag signals. Preview
shows allowed tiles and the cost or refusal; a completed drag reaches Main's
construction owner. Captions read as sentences: a drag that builds only part
of its length adds "· stops: <reason>" (also kept after "Spent $X"), short
funds read "Costs $1,250 — treasury $830" (a negative treasury keeps its
sign), and bare-ground bulldozing in the surface view notes the buried water
pipe or subway track it also removes. A drag keeps the tool it started with;
holding B during a drag makes it a Bulldoze drag, and releasing B before the
mouse button keeps it one. Right-click inspects a site. Selecting pipes or subway tools
opens underground automatically and restores surface when appropriate; manual
underground choice is preserved. Utilities can be inspected without surface
building pick proxies obstructing them.

Bridge/tunnel choices, neighbor links and citizen objections keep their prices,
Build/Connect and Cancel semantics. Cancel charges nothing; declining a
neighbor link keeps the already-built run to the border ("Built up to the city
limit; no link made."). Inspector Demolish asks first for developed and
multi-tile buildings, naming the building and price (Cancel is the default).
Tree protests and approval milestones are flavor and appear on the status
line without pausing. Modal dialogs and
notices pause the simulation and preserve its speed restoration rules. Focused
text, controls, popups, window dragging or an inactive window block city keyboard
input; a valid map click gives keyboard input back to the city.

| Control | Action |
| --- | --- |
| WASD / arrows / middle drag / two-finger trackpad scroll | Pan |
| Wheel (toward the pointer) / trackpad pinch / 1–5 | Zoom, kept between ¾ of the closest and 1½ times the farthest named level |
| R | Rotate |
| Q / right-click | Inspect tool / inspect site |
| U | Surface / underground |
| B held | Temporary bulldoze |
| P / + / − | Pause or resume at the previous speed / speed |
| Ctrl+Cmd+F (macOS) / F11 (other desktops) | Fullscreen |
| Cmd/Ctrl+N / O / S / Shift+S / , | New City / Load City / Save City / Save City As / Settings |
| Escape | Close front dialog/window, cancel a drag, drop the tool, then exit fullscreen; in Explore it opens and closes the Explore menu |

The inspector scrolls long names and site/service/facility details while keeping
Rename and Demolish actions reachable. **City → Settings…** controls interface
size, fullscreen, 3D quality/resolution, the tile grid and Animate water. View →
Show toggles signs and labels, traffic and pedestrians, and the minimap.

## Tests

Tests cover display formulas and preferences, widget layout and focus,
3D gesture/preview/entity behavior, the eleven data layers, underground codes,
construction confirmations, editor/founding and save/load/import. Pointer routing
and drawable resolution are checked in rendered runs, since a screenshot alone
cannot show them.

## Release UI safeguards

Player actions that replace a city or leave the game offer Cancel, Don't Save
and Save when gameplay differs from the last manual save/load checkpoint. Escape
and the close button cancel that decision. Saving must succeed before the
requested action continues. Native window-close uses the same path; an existing
modal decision cannot open a second copy of Save As.

The checkpoint deeply copies city/runtime content when saved or loaded. Dirty
comparison happens only when leaving, not each frame. Pause/speed and fractional
scheduling time alone do not count as discarded city work. Automatic backups do
not replace the manual checkpoint.

Save As shows the normalized filename and asks before replacing an existing
file, including names that normalize to the same path. Failed saves keep the city
state and the attempted filename. Native and classic file pickers pause the city
and restore its prior speed on cancellation. Autosave failure is reported.

Transient feedback stays visible for seven seconds, independent of simulation
speed. An open inspector refreshes after coalesced simulation updates, keeping
its scroll position for the same tile. Reopening an information window makes it
the next Escape target. Toolbar keyboard focus follows scrolling; selected speed
and tool cost remain visible. Modal keyboard focus stays inside the active dialog.

Shared fields, lists, scrollbars, popups and tooltips use the same ivory/teal
palette and readable focus/hover states. Action rows can wrap, while window bodies
scroll. Settings groups Mayor, Explore (Pedestrian character and, on desktop,
Pause while in the background), Display and Graphics on its General
tab, with keyboard and camera settings on Controls and a fixed Done button; changes
apply immediately. Budget and disaster settings live in their own reports/menus.
Help includes starting a city, construction, backup recovery and exploration.

Load City keeps concise rows and a wrapping selected-save summary containing
filename, saved date, stage, year and population. Identically named cities can
be distinguished before loading. Browse opens native `.sc2d` saves outside the
default save directory; an empty list disables Load and explains the next step.

## Tool identity

All 71 tools use distinct SVG pictograms in
`game/assets/ui/tool-icons`, authored by `tools/build_ui_icons.py`. A 64-unit
stroke grid and light badge preserve shape contrast when selected or disabled;
128px source dimensions support the 32px icon at doubled display scale.
Visible 14px captions occupy two lines below each icon. Full names, prices,
shortcuts and lock reasons remain in tooltips and the selected-tool identity.
Roads, ramps, tunnels, railway/subway tools, all six zone densities, power sources
and emergency dispatch each have separate symbols. Color supplements shape.

The four large resort developments are called **Gaming Resorts** in the toolbar,
population window, technology announcements, notices and Controls. Internal
simulation and save identifiers still say "arcology". Each resort keeps its individual
name and a mining, railway, dam/crown or rocket silhouette.

## Gaming-resort tables

`CasinoTableOverlay` (`game/scripts/ui/casino/`) is the table a seat on a
resort floor opens. Main's `open_casino_table` refuses before founding, over
another dialog, for an unknown resort or game, and with a treasury below the
table minimum (the reason appears as a notice). An open table is a modal:
the city pauses, Explore suspends, the Explore HUD and its paused panel hide
behind the table, and the Explore camera holds the table's seated view. The
overlay shows the resort header in the resort's sign lettering, the floor and
game, the live treasury with this sitting's net, the drawn and animated game,
the dealer's line and a bet bar with chips, −/+ and the game's actions.
Escape or Leave table closes it between rounds only; closing pops the modal,
restores the previous speed, releases the camera and lets Explore resume by
itself. Closing or replacing the city mid-round refunds the stake first;
backgrounding the app plays the round out as it stands (blackjack stands,
video poker draws, a launch cashes out) and closes the table. A launch's
climb holds while the desktop window is unfocused. A quit requested while
seated waits and the table explains why. Enter plays the table's main action
unless the player has moved focus to another button (Leave table, Rules, a
chip), which Enter then activates.

The header, the floor · game line and the dealer's line wrap rather than
cut off. Narrow layouts move the treasury, Rules and Leave table to a second
header row; short layouts stack the game's actions beside the table. Every
target stays 44 units or larger, keyboard focus stays inside the table, and
every control is reachable by keyboard. The Explore controls hint names F as
"interact", which covers resort doors and seats; the prompt itself names the
door or the table. See [Gaming resorts](gaming-resorts.md).

## Shortcuts, backups and saving

Terrain editing disables clock controls and explains the Found City prerequisite;
founding or loading a running city restores them. Ctrl/Command/Alt combinations
do not invoke plain Build shortcuts. Temporary bulldozing restores the prior tool
even when none was selected, on key release, focus loss, menu or modal entry.
Explicit tool choices and city/Explore transitions clear stale held state.

Automatic backups use `user://autosaves/autosave.sc2d`, separate from named saves.
Load lists the managed backup with recovery guidance; recovery leaves the manual
save target unset so Save asks for a name. Legacy `saves/autosave.sc2d` remains a
normal save. Save As accepts a pasted .sc2d suffix once and shows the actual save
folder. Load City shows saved dates in local time without seconds. File
pickers keep their task title.

Saving writes the whole document to a staging file and verifies it before
replacing the old save. Write and flush failures are reported, and a partial
file never replaces a good one. On Windows a verified
previous-save copy guards the engine's non-atomic replacement path. If restoration
fails, `previous.sc2d` remains in a `.sc2d-save-*` sibling directory for recovery.
This does not protect against power loss, and it has not yet been tested on
Windows hardware.
