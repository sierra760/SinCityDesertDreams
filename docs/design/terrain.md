# Terrain

How the ground is stored, generated and edited. Code lives in
`game/scripts/terrain/`: `TerrainSurface` (the lattice), `TerrainGenerator`
(new maps) and `TerrainEditor` (the player's terrain tools).

## The lattice

A map is 128×128 tiles, but the ground is described by a 129×129 grid of
**vertex heights** (0..31). Each tile owns the four vertices at its corners
and shares them with its neighbors. This is the editable truth; the city's
`terrain` and `altitude` layers are derived from it by `TerrainSurface.project`.

Per tile the surface also stores a **water height** (or none), a **salt**
flag and a **feature**: none, stream or waterfall.

### Representability

Two rules make every tile drawable with the fourteen slope shapes in `Terrain`:

1. Adjacent vertices differ by at most one level (no cliffs).
2. No tile has exactly two opposite corners raised (no saddles).

`TerrainSurface.normalize()` enforces both:

- Cliffs are relaxed from both sides. Each visit moves a vertex halfway into
  the band its neighbors allow, so a spike comes down while the ground
  around it comes up, spreading a repair evenly. Vertices in the `pinned`
  set never move; their neighbors adapt instead, and every free vertex is
  clamped into the band the pins allow (a pin at height `h` forces a vertex
  `d` steps away into `h-d .. h+d`). A final raise-only pass closes any gap
  left, which always terminates.
- Saddles are split by lifting one low corner, turning the tile into a valley.

`normalize(rect, pinned)` starts from the vertices of `rect` and lets the
repair ripple outward as far as it needs. It returns `{changed, cliffs,
saddles, converged, rect}`; `rect` bounds every tile touched by a changed
vertex and is what the caller re-projects.

### Projection

For each tile: `base` is the lowest corner, the raised corners (one level
above the base) give the slope shape through `Terrain.shape_from_corners`,
and the water kind follows from the water height `w`:

| Condition | Code |
|---|---|
| no water, or `w <= base` | dry shape |
| feature waterfall | `Terrain.WATERFALL` |
| feature stream | a stream table code (see below) |
| `w > top`, tile flat and `w == base + 1` | `SURFACE` (open water you see the surface of) |
| `w > top` otherwise | `SUBMERGED` + shape (deeper, or a slope fully under) |
| `base < w <= top` | `SHORE` + shape (the water line crosses the tile) |

The altitude layer gets `base` as ground height and `w` as water height (0
when dry); tunnel bits are preserved. `TileFlags.SALT_WATER` is set on
brackish water tiles and cleared elsewhere. Other flags are untouched.

Stream codes come from a 16-entry table (`STREAM_CODES`) indexed by which of
the north, east, south and west neighbors carry water. `0x40` is a straight
north–south channel and `0x41` east–west. One wet neighbor gives an end cap:
`0x45` north, `0x42` east, `0x43` south, `0x44` west. Bends, junctions and a
lone tile reuse codes from the surface band: bends `0x35..0x38`, three- and
four-way junctions `0x30..0x34`, a lone tile `0x3d`.

A **waterfall** is a stream tile on a slope: its upstream edge is one level
above its downstream edge and the stream drops through it. A **stream** is
flat with the water one level above its bed, so a river runs one level below
its banks, which slope down to it through shared vertices.

The stored stream level only marks the tile as wet. The 3D view draws stream
and waterfall water as a thin film on the bed, so a waterfall is water running
down its sloped tile. Every one-tile stream tile, whether straight, a bend, a
junction or a waterfall, draws the same 0.32-tile-wide channel from its center
toward each neighboring water tile. A stream tile beside lake, sea or estuary
water fuses with that body as full water, and shoreline sand shelves appear
only at corners that touch land. Each connected standing-water patch at the
same stored level draws one flat plane, capped by its lowest dry bank or stream
bed. This cap applies to the whole patch, including its interior, so shallow
water cannot bulge into an elevated hill. Diagonal tiles sharing a corner join
the same patch. Where neighboring water stands at different
heights, the higher water pours over their shared edge. Generated lakes and
seas are level because their banks never lie below the water. Imported
per-tile cities and temporary floods keep their own presentation.

### Rebuilding from layers

`TerrainSurface.from_city(city, saved_vertices)` reads the terrain and
altitude layers back into a lattice. Loading a native save passes its saved
vertices, which replace the heights read from the layers; water, salt and
features still come from the layers. `TerrainEditor.attach` calls it without
vertices for a city that has no lattice: where tiles disagree about a shared
vertex the higher reading wins, then the editor runs `normalize()` and
re-projects the repaired rect. Classic imports keep their per-tile terrain
and have no lattice.

## Generation

`TerrainGenerator.generate(params, rng)` returns a `City` with a bound surface.
All randomness comes from the `SimRng`, so a seed reproduces a map.

| Parameter | Default | Meaning |
|---|---|---|
| `hills` 0..100 | 40 | relief: amplitude `HILL_FLOOR + (hills/100)^HILL_CURVE * HILL_AMPLITUDE` levels, fine roughness that grows with the setting, one dome per 20 points and one wash per 34 |
| `water` 0..100 | 40 | one lake per 34 points (larger with the setting) and a wider estuary; the sea band itself is a constant `COAST_BAND` tiles plus wobble and bay |
| `trees` 0..100 | 40 | share of open land under trees: `TREE_COVER_MAX * smoothstep(trees/100)^TREE_COVER_CURVE` |
| `coast` | `"none"` | `none`, `north`, `south`, `east`, `west`: which edge is sea |
| `river` | `true` | carve a river |
| `sea_level` 1..16 | 5 | height of standing water; land starts one above it |
| `name`, `difficulty`, `founded_year` | | city metadata; funds follow `City.STARTING_FUNDS` |

The map is shaped as a continuous field first and only then made
representable, so the result is rolling ground rather than plains with a few
sharp steps. Steps, in order:

1. **Relief.** Four octaves of value noise (cells 40, 20, 10, 5 vertices,
   the middle octaves weighted most), a ridged octave (cell 26, the noise
   folded so it forms ridge lines and valley floors) and, when hills are up,
   a fine roughness octave (cell 3) whose weight grows with the setting. A
   few rounded domes (radius 8..20) add higher hills. With a coast the relief
   fades over the 20 tiles nearest the sea edge, down to 35 %, so the shore
   is a lowland. The field is scaled by the amplitude and quantized to whole
   levels at or above sea level.
2. **Coast.** Along the chosen edge, vertices inside a wavy band 17 tiles
   deep (wobble ±4) are sunk below sea level, one level per four tiles of
   distance from the shore, with one bay (a parabolic notch 14..26 tiles in
   half-width and 0.8..1.6 bands deep). Tiles whose base is below sea level
   form the sea region; a distance-to-sea map is kept for the river.
3. **Slope limit.** Every unpinned vertex is brought down to within one
   level of its lower neighbors (two sweeps over the lattice). This removes
   all cliffs by lowering, never raising, so steep noise becomes even slopes
   and every sunk feature gets sloping sides. It runs again after each
   carving step below.
4. **Washes.** One dry meandering channel plus one per 34 points of hills,
   each one level below the land it crosses (never below sea level).
5. **Lakes.** One plus one per 34 points of water. For each, the lowest of
   eight random interior spots is sunk into an oval basin (radius 2..4, plus
   one per 50 water points): two levels below sea in the middle, one below
   outside it. The slope limit then shapes the land around into a bowl.
6. **River.** From the highest interior tile at least 56 tiles from the sea
   (or the highest tile when there is no coast) a 4-connected path meanders
   toward the coast, or toward the farthest edge without one. It never runs
   alongside itself, never enters a lake, and keeps straight while the land
   ahead or beside it falls, meandering only on level ground. Its bed never
   rises and drops one level only on straight tiles; a look-ahead bound makes
   it drop as soon as the land it will cross requires it, so it stays a level
   below its banks, and it reaches sea level before the estuary when enough
   straight tiles remain, so its water meets the sea flush. Each drop is a
   waterfall. The river's vertices are pinned; the slope limit then cuts a
   valley down to them. When the river reaches the sea its last 28 tiles (at most half the
   path) are an estuary: the tiles across the channel are sunk to just below
   sea level, widening from one tile to 2 (3 at water 100) each side, and
   flood as open water.
7. **Saddles.** Tiles with two opposite corners raised on their own have one
   raised corner lowered to the tile's base, then the slope limit runs again;
   repeated until none remain. Normalization is then called with the river
   pinned and normally finds nothing to do; if a pin blocks it, one unpinned
   pass follows.
8. **Standing water.** Every non-river tile below sea level holds water at
   sea level: brackish in the sea region and anything connected to it (the
   estuary), fresh elsewhere (lakes).
9. Project.
10. **Trees.** Each open tile gets a score: cover noise (cells 12, 6, 3
    tiles) plus `TREE_MOIST_BONUS * moisture²` (moisture from distance to
    water, up to 6 tiles), `TREE_SLOPE_BONUS` on sloped tiles,
    `TREE_WASH_BONUS` on washes and a random jitter of up to `TREE_JITTER`.
    The trees control fixes the share of open tiles that get trees
    (`tree_cover_share()`: 0 at 0, about 3 % at 17, 32 % at 50, 78 % at 100)
    and the highest scores win, so trees gather in clusters on slopes, along
    water and in washes, with lone trees scattered by the jitter. Density is
    the count of chosen tiles in the 3×3 around a tile, mapped to
    `Buildings.TREES_1..TREES_7`. Trees are written straight into the
    building layer; the zone layer stays clear.

A full map with everything turned up generates in about 350 ms.

## Editing

`TerrainEditor` works on a `City`; `attach()` builds a lattice from the layers
if the city has none. Every tool returns `{ok, cost, rect, reason}`. The
editor never touches funds: `cost` is what the caller debits. Before the
city is founded the host drives the editor directly and charges nothing
(see `ui.md`, editing stage); after founding the same tools go through the
Builder at their prices.

| Tool | Cost | Rule |
|---|---|---|
| `raise(x, y)` | 25 | the tile's lowest corners rise to `base + 1`: a slope becomes flat ground one level up, flat ground rises whole |
| `lower(x, y)` | 25 | the tile's highest corners fall to `top - 1` |
| `level(x, y, h)` | 25 | all four corners set to `h` |
| `place_water(x, y, fill_basin := false)` | 100 | water at `base + 1`: a pond on flat ground, a shore on a slope; brackish when a neighbor is brackish. With `fill_basin` the water spreads through the enclosed hollow around the tile: every connected dry, unbuilt tile whose ground lies below the water, bounded by higher ground, standing water and the map edge, up to `BASIN_LIMIT` (64) tiles; a wider hollow gets the single tile |
| `remove_water(x, y)` | 100 | drains the tile, including a stream or waterfall segment |
| `plant_trees(x, y, density)` | 3 | `TREES_1 + density - 1` on dry, empty ground; re-planting at a new density replaces |
| `raise_sea_level()` | 25 | standing water rises one level and floods onto neighboring dry ground below the new level (not built tiles); `city.sea_level + 1` |
| `lower_sea_level()` | 25 | standing water at the old level drops one; tiles left with nothing above their ground dry out |

Ground tools pin the tile's four corners at the new height, normalize from
there and re-project the ring of tiles that share those corners plus every
tile the ripple touched. They refuse when the target tile, or any tile that
would change shape, holds anything but trees; trees on the target tile are
cleared as part of the work. A refused edit leaves the lattice untouched.

After founding, the Water tool also drains an empty water tile at its usual
price. Surface Bulldoze drains bare water at its demolition price; when a
structure stands over water, the first demolition removes that structure and
leaves the water beneath it. Deletion preserves the ground height and buried
utilities, clears the water and salt flag, and persists through save/load.
Protected land and funds checks apply. Temporary disaster floodwater is not
drained by these tools.

After ground moves, water settles: a tile whose water is no longer above its
ground drains; a dry tile that dropped below neighboring standing water
floods to that level and inherits its salt flag.

The sea-level tools need `city.sea_level >= 0` (generated cities and
real-world imports with sea water have it; `-1` means the map only has
per-tile water, as in classic imports) and stay within 1..30.

### Tool dispatch

`apply_tool(tool, from, to)` runs a `Tools.Kind` terrain tool over a drag and
returns `{ok, cost, rect, reason, tiles}`, where `cost` sums the prices of
the tiles that changed and `rect` bounds everything to redraw:

| Tool | Does |
|---|---|
| Raise Land, Lower Land | `raise` / `lower` on `from` |
| Level Land | `level_area`: every tile of the dragged rectangle (`drag_area`, rows walked outward from `from`) is leveled to the first tile's base; tiles already flat there are skipped |
| Water | `place_water(from, fill_basin = true)`; on a tile that already holds water, `remove_water` instead |
| Forest | `plant_area`: trees over the dragged rectangle, each tile at `natural_density` (one plus the tree tiles around it, 1..7) |
| Tree | `add_tree` on `from`: one tree on open ground, or one step denser on a wooded tile; refused at density 7 |
| Raise Sea Level, Lower Sea Level | the whole-map sea tools, applied once per toolbar press; only before the city is founded |

`preview_tool(tool, from, to)` returns the same tiles and whether the first
tile may be edited (`can_edit`, the refusal reason or an empty string)
without changing anything, for the map cursor.

## Save state

The lattice is saved as the 129×129 vertex bytes (`terrain_vertices` in the
`.sc2d` document); per-tile water, salt and features are recovered from the
layers on load through `from_city`. A city kept as imported per-tile terrain
has no lattice and saves `terrain_model: "per_tile"` instead. See
`file-formats.md`. A map saved before founding is marked `stage: "editing"`
and keeps its generator settings; loading it reopens the editing stage on the
saved lattice.
