# Silver State Spheroid at night

Each of the dome's 220 authored triangular cells is one light panel. Cells
slowly alternate through a three-colour seasonal palette, selected from the
simulation month. The beams radiate steady silver-white neon using the existing night bloom. The pattern is regular and horizontal.

A cell's centre height assigns its fixed phase, identical at all three corners.
Cells at the same height change together. Two repetitions of the seasonal
A/B/C sequence span the dome, moving slowly upward as shader time advances.
Each cell stays one flat colour as it holds, then softly changes to the next
palette colour. There are no random, diagonal or spatial-noise offsets.
A complete A→B→C→A cycle takes 48 seconds; the dissolve occupies the last
3.52 seconds of each 16-second colour interval. Shader time drives this visual
cycle independently of simulation speed or pause. The simulation date chooses
the palette and never changes from presentation animation.

In Explore, colour advances upward one actual cell-grid level each second.
Face-centre heights are sorted and merged within a 1.6 cm import tolerance,
then their consecutive level indices are encoded in the existing vertex-colour
channel. Three levels form a colour band. At every integer shader second,
row r receives the colour previously held by row r−1. Between ticks, cells
hold their exact colour. The nine-second palette repetition fits shader-time
rollover without a discontinuity. Camera entry/exit updates one mode uniform;
Build retains its slow 48-second sweep. New construction and entering night
while already exploring start in the correct mode.

| Simulation month | Seasonal palette |
| --- | --- |
| January | Winter blue, pale ice, silver |
| February | Rose red, blush, ivory |
| March | Emerald, soft green, gold |
| April | Lilac, mint, pale yellow |
| May | Leaf green, blossom pink, cream |
| June | Sunshine gold, turquoise, sand |
| July | Red, blue, warm white |
| August | Terracotta, dusk blue, summer gold |
| September | Copper, woodland green, autumn gold |
| October | Pumpkin orange, midnight, violet |
| November | Rust, wheat gold, harvest cream |
| December | Red, evergreen, ivory |

## Cost and lifecycle

The display retains two mesh submissions per landmark: 220 screen triangles
and 5,144 rib/joint triangles. It adds no per-cell nodes, textures, texture
sampling or lights. Phase calculation and palette interpolation run only in
the vertex shader; fragments simply output the flat cell colour and night fade.
There is no per-frame CPU callback, one-second timer, mesh rebuild or uniform animation upload. Silver HDR seams use the existing bloom pass and add no light nodes.

The existing daily/analytics presentation refresh coalesces one deferred date
check. Deferral is necessary because `day_advanced` is emitted before the
simulation advances its saved day. An unchanged month writes nothing; a new
month changes three palette uniforms per display, without rebuilding geometry.
One-time cell-height calculations occur during show geometry construction,
and shader animation has a small per-vertex cost.

Source meshes, materials, collisions and compiled cache entries remain
unchanged. Night fade, exact day restoration, elevation and facing, construction,
demolition, data overlays and Underground visibility retain their existing
behavior. Hidden displays skip calendar notifications and catch up when shown.
No city state, save format or game random stream is modified.

`test_spheroid_night_show.gd` covers all twelve month selections and exact
boundaries, year wrap, pre-advance notifications, unchanged meshes across
months, consistent phases at every cell corner, lack of CPU frame processing,
source/compiled/cached models, facings and elevation, analytical visibility,
construction/demolition and byte-identical save data. Native views cover every
month and multiple stages of palette alternation. A controlled shader-clock
fixture checks actual row-colour pixels at 0, 0.9, 1, 1.9 and 2 seconds,
including both exact upward steps and the hold between them.
