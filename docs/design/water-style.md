# 3D water presentation

Water uses continuous teal ripples, turquoise shallows, a darker offshore color,
soft sun highlights and a view-dependent sky sheen. Shore foam follows the
visible banks, and waterfall streaks move down toward a soft foam band. The
map's elevation steps stay visible.

City → Settings… → **Animate water** (in the Graphics section) pauses or
resumes the visual clock and is remembered across launches. Pausing the
simulation does not stop decorative water motion. High and Balanced include fine ripples; Performance keeps the broad ripples
and bank colors with simpler highlights. The 3D resolution setting applies as
usual.

The water material shares world coordinates across terrain chunks. A reusable
128×128 floating-point texture records visible water levels, seabed heights,
bank shelves (only at corners that touch land; one-tile channels have none) and
waterfall bottoms. Bank masks use nearest sampling;
depth uses linear sampling. Terrain or flood changes refresh the metadata;
building-only and utility-only changes leave it alone. Fine detail fades with pixel
size, and foam smoothing uses the pixel footprint rather than derivatives of
the bounded bank search.

Only the terrain material's water palette receives this styling. Surface
triangles, heights, picking, traversal, simulation, random streams and save
formats are unaffected. The sheen uses a procedural sky gradient. It does not reflect buildings or add refraction,
displaced waves, particles or extra water geometry.

The tests are in `game/tests/test_water_style_3d.gd`.
