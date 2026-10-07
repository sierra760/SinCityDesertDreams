# Construction

## Purpose

Every player edit of the map goes through one object, `Builder`. It takes a
tool, a drag (a start and an end tile), and answers two questions: what would
this do and what would it cost (`preview`), and then does it (`apply`). The
toolbar and the cursor never write to the city layers themselves.

Three classes share the work:

- `Tools` (`core/tools.gd`): the catalog of player tools. Each entry names the
  tool, its price, the building id or zone kind it places, its footprint, the
  toolbar icon and how the pointer drives it (a point, a line, a rectangle, a
  line of 2×2 blocks, or a whole-map action).
- `NetworkShapes` (`core/network_shapes.gd`): the geometry of roads, rail,
  power lines, highways, pipes and subways. It turns a set of connected
  neighbors into a building id, produces crossing ids where two networks
  meet, and repairs the shapes of a tile and its neighbors after a change.
- `Builder` (`core/builder.gd`): validation, pricing, the write to the city,
  the funds debit, facility records and the notification of the simulation.

## Inputs

- `City` layers: `terrain`, `altitude`, `building`, `zone`, `flags`,
  `underground`, plus `funds`, `day`, `sea_level`, `signs`, `facilities`.
- `CityStats`: `inventions` (technology key → first year available),
  `rewards_offered`, `rewards_built`, `ordinances` (the Nuclear Free Zone).
- An optional `Simulation`, used for the random rubble pattern and to announce
  map changes.

## Outputs

- Writes to `building`, `zone`, `flags` (conductivity bits), `underground`,
  `terrain`, `altitude`, `signs`, `funds` and `facilities`. It reads
  `sea_level` but never changes it (rule 27).
- `stats.rewards_built[key] = true` when a reward is placed.
- `Simulation.networks_changed(rect)` after every successful `apply`, with the
  rectangle that covers every changed tile.
- Dispatch tools hand the target tile to the disaster system through
  `Simulation.get_system(&"disasters").dispatch(kind, tile)` when that method
  exists; otherwise they only validate the tile.

## Timing

Construction is synchronous and happens between simulated days. `preview`
never changes the city. `apply` is atomic: it either changes nothing and
reports why, or applies the whole priced change.

## Result shape

Both `preview(tool, from, to, options)` and `apply(tool, from, to, options)`
return a Dictionary. `options` is optional (default `{}`) and answers the
questions a plan can raise: `choice` (a bridge or tunnel style key),
`connect` (carry the last tile across the city limit) and `proceed` (build
despite an objection).

| key | meaning |
|---|---|
| `ok` | the change is legal and affordable |
| `cost` | total price in dollars |
| `tiles` | `Array[Vector2i]` of the tiles that would change |
| `rect` | `Rect2i` covering `tiles` |
| `reason` | empty when `ok`, otherwise a short player-facing sentence |
| `applied` | `apply` only: true when the city was changed |
| `needs_confirmation` | the drag raises a question for the player; see `choice_kind` |
| `choice_kind` | `&"bridge"`, `&"tunnel"`, `&"neighbor"` or `&"opposition"` |
| `choices` | bridge and tunnel plans: `[{key, cost}]`, the total price of the whole drag under each style |
| `choice` | the style the plan is priced with (the caller's, or the default) |
| `span` | water tiles crossed, or tunnel tiles bored including portals |
| `neighbor` | `{edge, tile, kind, cost, name}` when the drag ends on the city limit and no `connect` answer was given |
| `neighbor_link` | `{edge, kind}` when an accepted connection is part of the plan |
| `opposition_exposure` | residential zone tiles counted around a building the neighbors may object to |
| `trees_cleared` | tree tiles a bulldoze drag fells |
| `stopped` | line and block-line drags that still build something: why the walk ended before `to` (the same wording as `reason`) |
| `clears_underground` | bulldoze drags over bare ground: `["water pipe", "subway track"]` (those present) that rule 24 removes from underground |
| `notices` | `apply` only: `[{kind, payload}]` the host should show (the tree protest) |

What each question means for `apply`:

- **bridge / tunnel**: `apply` without a `choice` builds the default style
  (the first entry of `choices`), so callers that never ask still work. The
  host asks first and passes the player's `choice`.
- **neighbor**: `apply` builds the drag up to the city limit and leaves the
  border tile alone; `neighbor` describes the link on offer. The host asks,
  and on Connect applies the border tile with `{"connect": true}`.
- **opposition**: `apply` changes nothing and charges nothing until it is
  called again with `{"proceed": true}`.

## Rules

### Drags

1. Point tools use `from` only. Line tools walk from `from` to `to` in an
   L shape: the longer axis first, then the shorter. Rectangle tools cover the
   whole rectangle between the two corners. Block-line tools (the highway)
   walk the same L shape in steps of two tiles over 2×2 blocks aligned to even
   coordinates. Global tools ignore the tiles entirely.
2. A line tool prices and places tiles one by one along the walk. A tile that
   cannot accept the tool stops the walk there; tiles already placed before it
   remain in the plan. If the walk places nothing, the result is not `ok`.
3. Rectangle tools price only the eligible tiles inside the rectangle;
   ineligible tiles are skipped and cost nothing. If no tile is eligible the
   result is not `ok`.
4. The drag is refused entirely when `city.funds` is below the total cost
   (`reason` = "insufficient funds"). Nothing is charged for tiles that are
   skipped.

### Availability

5. A tool locked by year is available from `stats.inventions[key]` when that
   key is present, otherwise from the year in the `Tools` table. Before that
   year every preview and apply fails with "not available until <year>".
6. Reward tools are available only after `stats.rewards_offered[key]` is true
   and until `stats.rewards_built[key]` is set. The military base has no
   ordinary tool; it is offered as a reward and zones military land.
6a. While the Nuclear Free Zone ordinance is enacted
   (`stats.ordinances[&"nuclear_free_zone"]`), the nuclear power plant is
   locked: every preview and apply fails with "the Nuclear Free Zone ordinance
   forbids nuclear plants" and charges nothing, and the toolbar shows that
   reason. Plants already built are unaffected.

### Roads, rail and power lines (line tools)

7. A tile takes a road, rail or power line when it is dry and either empty,
   rubble, trees, or already carries the same network (free, unchanged). Roads
   and rail clear the zone kind under them; power lines keep it, so a line may
   cross zoned but undeveloped land.
8. A straight slope (`SLOPE_N/E/S/W`) takes a network only when the walk runs
   along the slope axis, and receives the matching slope piece. Corner and
   valley shapes refuse the tool.
9. Crossings: a road over a straight power line or rail, a rail over a
   straight road or power line, and a power line over a straight road or rail
   produce the crossing id for that pair. The drag must meet the straight
   line at a right angle on flat ground: a tile where the walk turns never
   becomes a crossing, and a drag running along the existing line is
   blocked by it rather than merged into it. A one-tile click has no
   direction of its own and may cross either way (on the map border it takes
   the axis across the edge). Bends, junctions and slopes cannot be crossed.
   A power line may not enter a developed building unless that building
   already carries power (it does, so the walk simply stops there and the
   line connects to it).
10. Water: when the walk reaches open water it becomes a bridge for the rest
    of the straight run until the far bank, which must be dry land within the
    map at the same ground height as the near bank. No span may exceed
    `BRIDGE_MAX_SPAN` (24) water tiles. The plan then needs a style: a road
    offers a causeway when every span is at most `CAUSEWAY_MAX_SPAN` (6)
    tiles, and always a suspension bridge; rail offers its rail bridge; a
    power line its elevated line. The result carries `needs_confirmation`,
    `choice_kind` `bridge`, the `choices` with the total drag price of each,
    and `span`. A `choice` the spans do not allow is refused ("the water is
    too wide for a causeway"). Bridge tiles are priced per water tile:
    causeway 25, suspension 75, rail 75, elevated power line 10. A drag that
    ends in the water is extended to the far bank. The landing on the far
    bank must accept the network as the walk would: protected land, the city
    limit, a building in the way or a slope running across the span refuse
    it. A bridge whose landing is refused is not built: the plan keeps only
    the tiles before the water, and fails with the landing's reason when
    there are none.
11. Prices per tile: road 10, rail 25, power line 2. After placement the tile
    and its four neighbors are reshaped so bends, junctions and crossings
    match their connections.

### Highways, ramps and tunnels

12. A highway block is a 2×2 footprint aligned to even coordinates, priced at
    100 per new block. Every tile of the block must be dry and either empty,
    rubble, trees, an existing highway (free) or a straight road, rail or
    power line running across the highway (which becomes the highway crossing
    id). A block whose four tiles all share one straight slope along the
    travel axis receives the slope piece. So does a hillside block climbing
    one level along the axis: one row across the axis holds two matching
    straight slopes on one base height, and the other row is level ground,
    either the hilltop (one level above that base, on the slope's raised
    side) or the foot (at the base, on its low side). The hilltop row is
    stored as a plateau on the slope's base height; the ground itself does
    not move. Every sloped block carries one corner flag per tile so the map
    draws it as one 2×2 picture. Slopes running across the axis, turns and
    crossings on a hillside, and any other shape refuse the block.
    After placement each block and its four block neighbors are reshaped:
    two opposite connections give a straight piece, two adjacent ones a
    corner, three or four an interchange.
13. A ramp (`ONRAMP`, 25) is a single flat, dry, empty tile touching at least
    one highway tile and a road on another side; without the road it is
    refused ("a ramp must touch a road"). The road is the ramp's approach and
    is reshaped to meet it. The ramp id faces the highway.
14. A tunnel starts on a straight slope tile that is empty and dry. It bores
    into the hill along the slope axis until the ground comes back down to
    the entrance height; that tile must be the opposite slope and equally
    empty. Every bored tile must be free of an existing tunnel. Price is 150
    per tile including both portals; the bore may not exceed
    `TUNNEL_MAX_LENGTH` (30). Portals get the tunnel ids facing their hill,
    interior tiles get tunnel bits in the altitude layer (1 north–south,
    2 east–west). The plan is a quote: `needs_confirmation` with
    `choice_kind` `tunnel`, one choice (`tunnel`) priced at the whole bore,
    and `span` set to the bored length.

### Links to the neighboring towns

14a. A road, rail, power line or pipe drag whose **last** tile lies on the
    map border (x or y equal to 0 or 127) is an offer to connect to the town
    beyond that edge. The walk builds every tile up to the limit as usual;
    the border tile itself is built only with `{"connect": true}`, at the
    link price from `NEIGHBOR_LINK_COST` (road 100, rail 250, power line 50,
    pipe 50) instead of the tile price. Without that answer the plan reports
    `neighbor` (edge, tile, kind, cost and the neighbor's name from the
    neighbor system) and `needs_confirmation` with `choice_kind` `neighbor`.
    A border tile that already carries the network is simply a continuation.
14b. Any other border tile stops the walk ("reaches the city limit"), so a
    network cannot run along the edge: the only network tiles on the border
    are accepted links, which is what the neighbor system's edge scan counts.
    Accepting also calls `NeighborSystem.record_connection(edge, kind)`, which
    sets the flag at once and tells the newspaper. Subways never connect.
    Corners belong to the north or south edge.

### Pipes, subways, portals and stations

15. Pipes (3 per tile) and subways (100 per tile) are line tools that write
    the `underground` layer, whose numbering is shared with the utility
    systems: a pipe's code is its connection mask (N = 1, E = 2, S = 4,
    W = 8, so 1–15), a subway's code is its mask plus 15 (16–30), codes
    31–34 are a pipe and a subway crossing on one tile, and 35 links a
    subway station to tunnels on every side. A tile takes a pipe or subway
    when it is not open water and the layer is empty, already the same
    network (free) or a straight run of the other network across the walk
    (which becomes a crossing). A tile with no connections yet is written as
    a straight run along the drag. Pipe tiles set the "conducts water" flag.
16. A subway portal (500) is a single flat, dry, empty tile beside a surface
    rail tile or an underground subway tile; it faces the rail, writes the
    surface portal id and a subway run below it along the same axis.
17. A subway station (250) is a single flat, dry tile that is empty or
    carries a standalone power line, which it replaces; it writes the
    station building above and the station link code below, which connects
    to subway on all four sides.

### Zoning

18. The six zone tools and the two port zones are rectangle tools. A tile is
    eligible when it is flat, dry, not military, carries no building beyond
    rubble, trees or a standalone power line (contaminated ground and pocket
    parks refuse), and its zone kind would change. Eligible tiles are marked
    with the zone kind; trees and power lines on them remain. Prices per
    eligible tile: light zones 5, dense zones 10, airport 250, seaport 150. A
    seaport rectangle must contain at least one eligible tile that touches
    water.
19. Remove zone (internally Dezone, 1 per tile) clears the zone kind of every zoned, undeveloped tile
    in the rectangle and sweeps rubble off them; standalone power lines stay.
20. The military base reward zones military land at no charge, with the same
    eligibility.

### Buildings

21. A building needs a footprint of dry, flat tiles at one ground height, each
    empty, rubble, trees or a standalone power line (all are cleared free of
    charge; crossings and bridges still block).
    Footprints that would leave the map are refused. The footprint takes the
    building id, corner marks and zone kind none; the anchor gets a facility
    record `{ "key", "built_day" }` for plants, civic, utility, transit,
    reward and arcology buildings. Buildings set "conducts power"; water
    buildings also set "conducts water".
22. Special sites: a water pump needs a single dry flat tile. A marina's 3×3
    footprint must contain both dry land and water. A hydroelectric plant sits
    on a waterfall tile that is empty or carries a standalone power line;
    marina footprints may replace standalone power lines too. A desalination
    plant must touch water on at least one edge of its footprint. Wind
    turbines are ordinary 1×1 buildings.
23. Rewards cost nothing and mark `stats.rewards_built`.
23a. **Objections.** The buildings in `OPPOSITION_BUILDINGS` (the nuclear,
    coal, oil and gas plants, the prison and the water treatment plant) are
    counted against the homes around them: every residential zone tile
    within `OPPOSITION_RADIUS` (8) of the footprint is one point of
    `opposition_exposure`. `apply` draws a threshold from
    `0 .. OPPOSITION_THRESHOLD_RANGE-1` (200) out of the simulation's random
    stream; when the exposure exceeds it the citizens object: nothing is
    placed or charged and the result says `needs_confirmation` with
    `choice_kind` `opposition`. `apply` with `{"proceed": true}` skips the
    draw and builds. A site with no homes nearby never objects; a site with
    more than 200 residential tiles around it always does. `preview` never
    draws. `forced_opposition` makes every candidate object.
23b. **Facility names.** `rename_facility(at, text)` stores `text` (trimmed
    to `FACILITY_NAME_MAX`, 24 characters) as `"name"` in the facility record
    of the building at `at`; empty text removes it. It fails with a reason
    on tiles without a facility record.

### Bulldozer

24. Bulldoze is a line tool priced at 1 per cleared tile. On a building it
    clears the whole footprint, charging per footprint tile, and leaves rubble
    on every tile of a developed building (zone buildings, plants, civic,
    utility, transit, port, military, reward and arcology). Trees, parks,
    rubble, network tiles, bridges and crossings clear to open ground. A
    tunnel portal removes the whole bore. A highway tile removes its block.
    An empty tile that carries pipes or subway has that cleared instead. Tiles
    marked as landmarks and military land refuse the bulldozer. Facility
    records and conductivity flags of removed tiles are dropped.
24a. **Tree protest.** The plan counts the tree tiles it fells
    (`trees_cleared`). When one drag fells more than `TREE_PROTEST_THRESHOLD`
    (5), `apply` attaches a `tree_protest` notice with the count, at most
    once per calendar year. It changes nothing on the map and costs nothing
    beyond the bulldozing. The host shows it on the status line rather than
    as a pausing dialog.

### Trees, parks and terrain tools

25. Trees (3) is a line tool and Forest (3) an area tool, each placing a
    tree tile on every dry, empty tile of the drag; the tree density grows
    with the number of neighboring tree tiles. Tree (3) is a point tool: on
    dry open ground it plants a single tree (density 1), and on a tile that
    already holds trees it adds one step of density, refusing at full
    density (7). Pocket park (10) is a 1×1 building placed on dry flat ground.
26. Raise (25) and Lower (25) change one tile's ground height by one level.
    Neighboring tiles are pulled along so that no two adjacent tiles differ
    by more than one level, and the slope shapes of every touched tile are
    recomputed from the heights around it. Level (25 per changed tile) sets
    every tile of the dragged rectangle, rows walked outward from the first
    tile, to that first tile's height with the same propagation. After founding these tools never damage the city: an edit
    is refused, free of charge, when the reshaped area including its cascade
    holds a building (trees excepted) or protected land, or when it would
    move a shoreline or the ground over a tunnel. The target tile itself must
    be dry, open or wooded and unprotected. Raise refuses at height 31, Lower
    at 0. Level skips the refused tiles of a drag and charges only for the
    tiles it changes; it fails only when no tile changes. A city with a
    ground lattice (generated and native cities) runs each step through
    `TerrainEditor` on a scratch copy and then on the city, so the 3D ground
    and saved vertices follow; a city kept as imported per-tile terrain
    edits its heights directly.
27. Water (100) turns one dry, empty, level tile into open water at its own
    height. Raise Sea and Lower Sea belong to shaping the land before the
    city is founded: each press of their toolbar button (set apart under
    "Sea level") moves the sea one level through `TerrainEditor`, free and
    with no map click, and the selected map tool stays. Once the city is
    founded their buttons are hidden and the Builder refuses them ("the sea
    level is set before the city is founded"), charging nothing.

### Signs

28. `place_sign(at, text)` writes `city.signs[at]`. Text is trimmed to
    `SIGN_TEXT_MAX` (24) characters; empty text removes the sign. At most
    `SIGN_LIMIT` (50) signs exist at once; replacing a sign on its own tile
    does not count against the limit.

## Parameters

| name | value | tunes |
|---|---|---|
| `Tools` price column | see table | price per tile, block or building |
| `Builder.CAUSEWAY_MAX_SPAN` | 6 | longest water gap a causeway may cross |
| `Builder.BRIDGE_MAX_SPAN` | 24 | longest span of any bridge |
| `Builder.BRIDGE_COST_CAUSEWAY` | 25 | price per water tile |
| `Builder.BRIDGE_COST_SUSPENSION` | 75 | price per water tile |
| `Builder.BRIDGE_COST_RAIL` | 75 | price per water tile |
| `Builder.BRIDGE_COST_POWER` | 10 | price per water tile |
| `Builder.TUNNEL_MAX_LENGTH` | 30 | longest bore including portals |
| `Builder.NEIGHBOR_LINK_COST` | road 100, rail 250, power 50, pipe 50 | price of the border tile that links to a neighbor |
| `Builder.OPPOSITION_BUILDINGS` | 6 ids | buildings the neighbors may object to |
| `Builder.OPPOSITION_RADIUS` | 8 | how far around a footprint homes are counted |
| `Builder.OPPOSITION_THRESHOLD_RANGE` | 200 | objection threshold is drawn below this |
| `Builder.TREE_PROTEST_THRESHOLD` | 5 | trees felled in one drag before a protest |
| `Builder.FACILITY_NAME_MAX` | 24 | characters in a facility name |
| `Builder.SIGN_LIMIT` | 50 | signs per city |
| `Builder.SIGN_TEXT_MAX` | 24 | characters per sign |
| `Builder.MAX_GROUND_HEIGHT` | 31 | ceiling for Raise |

Prices of tools that place a roster building come from `Buildings.cost`.

## Save state

Everything `Builder` changes lives in the `City` layers and metadata
(facility names are part of the facility records), which the save format
already persists. The only state the Builder keeps for itself is the year of
the last tree protest; a Builder is created afresh when a city is loaded, so
a reload allows one more protest that year.
