# Gaming resort casino floors

Each of the four gaming resorts (building codes 251–254) has a walkable casino
floor in Explore mode. The floor is a closed hall in its own pocket under the
resort's lot (floor at world height −2.5 tiles, centred under the lot), built
the first time the resort is entered and kept for the rest of the session.

## Shared program

Every hall shares one floor plan, in metres: a 44 × 44 m floor with an 11 m
ceiling; a 10 m wide vestibule with the street doors and the door mat at the
front (the street side, Godot +Z). The pit is a ring under the main chandelier:
three blackjack tables, roulette on a low round dais that doubles as the floor
medallion, and the money wheel at the ring's back edge, inside brass stanchions
and rope. The signature game stands on a 0.3 m dais before the cashier cage on
the back wall. Four double-sided slot rows of six (48 cabinets) form aisles in
the west half under their own chandelier and floor medallion; two video-poker
banks of four face the bar, which has eight stools; a lounge of four banquettes
and two lamp-lit cocktail tables fills the front-east corner; a bandstand with
a grand piano and drum riser fills the front-west corner; potted palms stand by
the entrance, the cage and the bar. Walls have a wainscot, pilasters between
6 m bays, a sconce in each bay and a cornice with a cove light; flat ceilings
carry coffers and a medallion around each chandelier. Walking lanes between
obstacles are at least 2.4 m (lounge furniture and the two faces of a slot row
stand together). The plan lives in
`game/scripts/exploration/resorts/resort_interior_layouts.gd`; the hall
architecture in the GLBs uses the same numbers.

## The four floors

| Resort | Floor | Hall | Chandelier | Signage font |
|---|---|---|---|---|
| Comstock Grand | The Assay Office | Sandstone ashlar with copper banding, walnut wainscot, a teal glass clerestory band, a coffered pressed-tin ceiling, cast copper columns, gas-lamp sconces, assay scales on the cage and a giant copper winding wheel (13 m rim, spokes, lit brass hub) suspended over the pit; ore carts on brass rails crown the slot rows; oxblood carpet with copper medallions | Brass gas-lamp tiers | Fontdiner Swanky |
| Silver Junction | The Roundhouse | A vaulted green-glass train shed on brass ribs and limestone piers, checkered ivory and charcoal terrazzo, a station clock over the cage, a split-flap departure board, brass luggage racks over the slot banks and a teal pinstriped lounge carpet | Station lanterns | BioRhyme |
| Boulder Crown | The Powerhouse | Close-set sandstone pylons with stepped Deco capitals over black lacquer bases, stepped cornices with cool spillway coves, turquoise terrazzo inlaid with brass sunbursts, and the cage as a stepped intake tower | Copper turbine ring | BioRhyme Expanded |
| Desert Orbit | Mission Control | Ivory walls with teal panelling and copper trim, a navy planetarium dome with star points and orbit ribs, copper nose cones crowning the back bar, a countdown display over the cage and an orbit ring around roulette; navy carpet with ivory orbit rings | Atomic starburst | Atomic Age (signs keep title case) |

## Assets

`game/assets/desert-dreams-resorts/` holds `hall_251.glb` … `hall_254.glb`
and the shared prop kit; see its README, `catalog.json` and `provenance.json`.
The generator is `tools/blender_exploration/build_resort_interiors.py`
(Blender, procedural). `assets/resort-interiors/` holds the editable source
of every exported model (`hall_251.blend` … and one `.blend` per prop) and
four review scenes, `review_251.blend` … `review_254.blend`: each hall fully
furnished from the floor plan with its lettering, lamps and review cameras.
The generator rewrites the model sources on every run and the review scenes whenever it renders reviews (not with `--skip-render`); the review scenes are only
for looking at a furnished hall in Blender and are never exported. Its
`--review-dir` renders front, pit, winding wheel or ceiling, seated, dais,
slots, lounge, bar and cage views of each resort. Materials are named `resort_<finish>`; at runtime
`resort_prop_dresser.gd` maps each onto `resort_finish.gdshader` (finish
indices 0 hard floor, 1 carpet, 2 wall, 3 ceiling, 4 stone, 5 wood, 6 metal,
7 glass, 8 felt, 9 lamp, 10 sign plate, 11 screen, 12 rubber, 13 cove light,
14 foliage), projected in
hall metres with the resort's palette. Sign lettering is set at runtime with
TextMesh in the resort's bundled font; every rendered character is in that
font.

Budgets: hall ≤ 40,000 triangles; slot cabinet ≤ 1,500; other props ≤ 4,000;
a populated hall ≤ 150,000 triangles and ≤ 40 draw surfaces. All placed
surfaces merge into one mesh per finish; slot cabinets and their stools are
multimeshes. The hall renders on layer 21 only; the Explore sun excludes that
layer. One warm directional fill on layer 21, owned by the Explore resort
service, is on only while the walker is inside a hall; each hall has six lamps
(OmniLights) on layer 21. Only the occupied hall is visible, so only its lamps
light; none cast shadows.

Run `python3 tools/check_resort_assets.py` to verify hashes, budgets,
collision shells, material names, import settings and export inclusion of the
catalog. These models are licensed under CC BY-NC-SA 4.0; see the
[licensing scope](../../LICENSING.md).
