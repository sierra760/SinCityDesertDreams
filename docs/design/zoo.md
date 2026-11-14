# Mirage Menagerie: the walk-through Zoo

The Zoo (building 218, 4 × 4 lot) is the Mirage Menagerie, a walled desert
garden you can walk through in Explore. Its rules are unchanged: it is still
a civic recreation venue for growth limits, tourism and amenity.

## The lot

- An adobe wall with a teal tile band surrounds the lot. The open gate,
  lettered MIRAGE MENAGERIE in BioRhyme under a copper sunburst, faces the
  street. Like the resorts, the gate stays on the authored front while a
  street touches it and otherwise turns to the side with the most street.
- A terrazzo promenade runs from the gate to a snack stand at the back and
  across to benches at each side wall. A two-tier fountain stands at the
  crossing, with four cactus planters around it.
- Four railed pens fill the corners. Each has its own ground and furnishings:
  sandstone boulders, saguaros and a shade sail; a pond with reeds, a rocky
  hill and a feeding trough; a meadow with a burrow mound, log and lookout
  pole; a packed-dirt racetrack with a log tunnel and a finish flag.
- Each pen has a lettered plaque above its rail on the north–south promenade.
- Lot trees are ordinary planting rows, so they follow the city's vegetation
  zones like every other lot.

The model is original procedural Blender geometry from
`tools/blender_exploration/build_zoo.py` (about 16,700 visible triangles). Its
textured surfaces reuse the shared desert sand, stucco, limestone and terrazzo
images already in the catalog. Collision shells cover the ground slab, walls,
gate, rails, fountain, planters, benches and snack stand. The rails stand
1.5 m above the walk, higher than a step or a jump, so visitors cannot climb
into the pens. The editable masters are kept locally under `assets/zoo/`.

## The animals

Four fictional species, each in its own pen:

| Animal | Pen | What it does |
| --- | --- | --- |
| Saguaroo, a cactus kangaroo with prickly-pear ears and a flower crown | front right | Hops round its pen in strings of bounds, resting to wave its arms and look about |
| Flamingoat, a pink goat on flamingo legs | front left | Wades between four spots, through the pond if that is the way, then stands on one leg grazing |
| Periscope Tortoise, with a telescoping neck and a brass eyepiece | back left | Plods round its meadow; when a visitor comes within 14 m it stops, raises its periscope and turns to watch |
| Tumbleweasel, a weasel inside a rolling tumbleweed | back right | Rolls laps of its racetrack, through the log, and sits up now and then to look around |

The animals are separate GLBs in `game/assets/desert-dreams-zoo/`. Each part
(body, head, legs, tail, neck segments, ball) pivots at its joint and
`ZooAnimal` (`game/scripts/view/zoo_animal.gd`) poses them each frame. They
are drawn 1.25 times life size so they read from the rails.

At load each species' GLB is merged once into a single skinned mesh: every
part becomes a bone at its joint and each part colour moves into the
vertices, so an animal is one draw call and every zoo shares the four meshes.
`ZooAnimal` poses the bones each frame.

`CityZoo3D` owns them, like the livestock: outside the static batches, placed
from each zoo lot's authored transform, and following lots as they are built,
replaced or demolished through a small zoo index on the building layer.
Detail follows how tall an animal appears on screen: under 2 pixels it is not
drawn, under 3 pixels or outside the camera's view it holds still, and it
casts a shadow only from 24 pixels. They are hidden in the underground and data
views. They pause whenever livestock pause: a paused city in Build, and a
suspended or blocked Explore.

Everything is presentation only. There is no city state, save data or game
random stream: each zoo's starting phase comes from its lot cell, so a zoo
looks the same each time it is shown.

## Reading a plaque

In Explore, stand at a pen's plaque on the promenade. The prompt reads
"F to read about the …". Press `F` (Interact) and the plaque's text stays on
screen for nine seconds while its animal does a trick: the Saguaroo leaps and
spins, the Flamingoat pirouettes on one leg, the Periscope Tortoise raises its
neck and looks all the way round, and the Tumbleweasel bounces down the track.
A vehicle within reach still takes precedence, as do mod interactions.
