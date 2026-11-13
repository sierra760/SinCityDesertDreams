# City Hall advisor cast and mood portraits

Six fictional city officials, styled as late-1990s to early-2000s PC strategy
portraits. Their grounded office wardrobes, expressive faces and restrained
camp replace the earlier mid-century caricatures and pun names.

| Advisor | Department | Topics | Voice |
| --- | --- | --- | --- |
| Dana Mercer | Finance | Treasury, taxes | Dry, exacting; keeps the mayor's wish list attached to a spreadsheet. |
| Ray Navarro | Utilities | Power, water, treatment | Practical, patient until the service stops; prefers working pipes to speeches. |
| Marcus Reed | Transport | Roads, transit, airports, seaports | Passionate and a little theatrical about getting somewhere. |
| Denise Holt | Public Safety | Police, fire, emergencies | Calm authority, meticulously prepared; direct during a crisis. |
| Dr. Elaine Park | Community Services | Health, schools, parks | Encouraging but firm; expects the city to do its homework. |
| Tony Delgado | Planning & Tourism | Jobs, commerce, industry, tourism, pollution, approval | A charming civic booster whose brochure must match the actual city. |

Each person has **five separately generated expressions**: delighted, pleased,
neutral, concerned and critical. The neutral image is the identity reference
for the other four. Faces, hair, clothing, lighting and framing remain
consistent within each set. All six identities are distinct. Names and mood
labels are rendered as accessible text by the game.

## Assets and generation

All 30 full-resolution PNGs live at `game/assets/advisors/<department>-<mood>.png`.
Six neutral originals and 24 expression edits were generated on
November 8, 2026. No external artwork or real-person
reference was supplied. Exact prompts, dimensions, SHA-256 checksums and neutral
reference checksums are recorded in [advisor-portraits.json](advisor-portraits.json).
The import sidecars cap runtime textures at 512 pixels and enable mipmaps.
Only the current moods are loaded; the game does not preload the full gallery.

Art: © 2026 Bristlecone Artists LLC, CC BY-NC-SA 4.0, under `LICENSING.md` and
`LICENSE-ASSETS`. The original first-pass portraits and records remain in local
revision evidence rather than the runtime asset bundle. Code and dialogue use
GPL-3.0-or-later.

## Mood selection

`advisor_cabinet.gd` groups the existing read-only assessment into six department
briefings. Each finding is retained once, with its complete title, evidence,
urgency and remedy. The worst supported condition determines the department's
mood. A construction opportunity alone is neutral. An ordinary warning is
concerned; urgent service loss or an active emergency is critical. Fixing the
problem changes the portrait on the next refresh, without a saved mood state.

Good and excellent outcomes require actual readings. Missing data and zero
sampled trips never earn a success portrait; a supported warning still wins. Excellent finance uses a nonnegative settled
year and a cash reserve covering half its expenses; excellent utilities need
both active supplies with at least 20% raw reserve. Excellent transport requires
all sampled trips completed and traffic at most 32/255. Public safety requires
crime at most 32/255 and full police/fire funding. Community services require
life expectancy at least 75, education at least 120 and full school/health
funding. Planning requires unemployment at most 3%, pollution at most 32/255,
positive RCI demand and, where visitor venues exist, measured occupancy at least
75% and reputation at least 80/100.

Severe measured traffic/crime/pollution (192/255), life expectancy at most 35,
education at most 50, unemployment at least 40%, negative cash or urgent
assessment findings select critical moods. Normal warning thresholds reuse
existing advisor policy. Older safety and community outcomes are not treated
as current success during a power disruption. These are presentation policies;
they do not change simulation balance, funding, saves, random streams or events.

Speech follows the department and mood, with two deterministic monthly variants.
An active emergency always receives a direct line. Published diagnoses and dated
newspaper stories are unchanged.

## Screen

Desktop uses a six-person roster beside a single selected briefing. Each roster
entry shows its current face, name, department, mood and finding count. A light
selected surface keeps the text and warning colors readable. The briefing gives
the advisor more space, a short spoken remark, recommendations and current or
latest measured readings.

Narrow screens use a department picker and a compact header. Short landscape
screens place the remark beside the portrait so the recommendation can appear
without first scrolling through a tall header. Department ordering is stable;
initial selection favors the most serious department. Refresh retains selection
and navigation focus. Changing between narrow and wide layouts moves focus to
the visible equivalent control. Existing window, scroll and focus machinery is
reused without modifying shared theme or platform files.
