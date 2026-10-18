# Altitude vegetation zones

Natural tree tiles (`TREES_1`..`TREES_7`) keep their saved codes: the code is
the grove's density, from a lone tree to a closed woodland. A tile's ground
level chooses which kind of tree grows there:

| Zone | Trees | Model |
| --- | --- | --- |
| Desert palms | Arched palms, as before | `game/scripts/view/city_palm_3d.gd` |
| Piñon and juniper | Low, rounded junipers and denser piñons, scattered open woodland | `game/scripts/view/city_conifer_3d.gd` |
| Pines | Tiered ponderosa pines and narrower white firs, closing into forest | `game/scripts/view/city_conifer_3d.gd` |

Each zone has its own seven grove layouts, one per density. Upland groves turn
and mirror per tile and each tree faces its own way, so neighboring tiles of
one density do not repeat. Trees are procedural and original; identical
species/variant pairs share their meshes and their crowns join the static
batches with the palm crowns. Every crown has two coarser automatic LODs. Each
tree has a physical body on the building layer: tall trees by their trunk,
shrubby junipers and piñons by their low bulk.

## Choosing the zones

**View → Vegetation Zones…** opens the city's elevation histogram. One bar per
ground level shows how much dry ground lies at that height and its colored foot
how many of those tiles have trees, both square-root scaled so small hills stay
visible.
Background bands show each level's zone. Drag a brass line, or select the chart
and use Left/Right to move a line and Up/Down to pick the other. Pointing at a
bar shows its elevation, ground and tree tiles and zone.

Each zone can be switched off, but one always stays on; the remaining zones
share the whole range. **Automatic** returns to zones that follow the terrain.

While a line is dragged, the chart, ranges and tree counts follow it live; the
city's trees are replanted once when the line is let go. Arrow-key steps apply
0.35 s after the last key. Replanting rebuilds every map chunk holding a tree
whose zone changed (on a heavily wooded city, roughly 20 chunks per level moved),
so it is done per gesture rather than per pointer movement. Switches and
Automatic apply at once.

Elevations are real metres for real-world cities (source minimum plus
`(level - 2) ×` metres per level). Other cities show height above level 0 at
about 9.8 m per level.

## Automatic zones

- Real-world cities: palms below 1,500 m, piñon-juniper to 2,100 m, pines above,
  approximating Mojave desert, Great Basin woodland and mountain forest.
- Other cities follow their own relief between the lowest and highest dry
  ground, ignoring the lowest and highest 1% of it: under 6 levels of relief
  all palms; under 12 levels palms and woodland from 60% of the relief;
  otherwise woodland from 50% and pines from 78%.

Automatic zones follow terrain edits while the city is open. Trimming the
extremes means a small edit (one raised peak or dug pit) cannot move every
boundary and replant trees across the city.

## Data

`City.vegetation` is `{}` while automatic. A player choice is
`{"version": 1, "enabled": [palms, piñon-juniper, pines], "cutoffs": [a, b]}`:
`a` ends the palms and `b` ends the woodland (`0 <= a <= b <= 32`). With a zone
off, the boundary after a lower enabled zone is that zone's cutoff. The record is
saved with the city (see [file-formats.md](file-formats.md)) and kept when the
land is regenerated before founding.

The zones are presentation only. Tree placement, growth, land value, the
simulation, its randomness and every map layer are unchanged. Inspect names a
tree tile by its zone (for example *Lone Juniper* or *Pine Forest*).

The network layer resolves the zones once per update into a per-level table
and includes each tree tile's zone in its region inputs, so moving a boundary
rebuilds only the chunks holding a tree whose zone changed. Loading or fully
redrawing a city costs the same as with palms alone.
