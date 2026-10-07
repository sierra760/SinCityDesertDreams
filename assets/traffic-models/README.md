# City traffic models

73 editable Blender masters and matching GLB runtime exports: 18 vehicle kinds
and 16 pedestrian variants, each with separately authored near and far geometry,
plus five transit pieces. Two further `.blend` files are inspection studios.

All geometry is authored by `../../tools/build_traffic_models.py`. There are no
imported meshes, external textures, fonts in runtime assets, generated image
textures, or commercial reference pixels. The only lettering is Blender's
built-in preview text in inspection studios; runtime identity uses silhouettes,
color, lamps, window arrangements and the game's captions. This is procedural
art made for the project, not any manufacturer's model or branding.

From the repository root, run Blender 5.2 in the background:

```sh
blender --background --factory-startup --python tools/build_traffic_models.py
```

Then repeat with `-- --transit-only` for the five transit pieces (passenger
carriage, passenger door, platform, stairs and tunnel, in `transit/`).
`--skip-render` skips the contact sheets. The script only writes the masters
and GLBs; it does not export a game package.

Masters preserve individually named editable parts. GLB exports join parts into
one mesh with material surfaces. Source units are meters, forward Blender +Y,
up +Z. GLB is Godot -Z forward/+Y up. `CityTrafficCatalog` compiles and caches
material groups, shares simple materials, and scales exactly once by 1/16.
Both `dimensions()` and returned meshes/nodes are in runtime tile units. Raw
GLB consumers must apply 1/16 themselves, without applying catalog scaling too.

The 16 pedestrians vary four skin palettes, four body/height combinations,
eight shirts, four trouser palettes, hats/caps/backpacks/bags and sunglasses.
The shared gait shader takes MultiMesh `INSTANCE_CUSTOM.x` in cycles and `.y`
as 0..1 movement weight. It animates feet and arms without per-person nodes.
Stationary/default instance data leaves the model still. Vehicle color variants
are not synthesized: each of the 18 kinds has its own authored identity.

The additional catalog kinds `passenger_carriage`, `passenger_door`, `platform`,
`stairs`, `tunnel` resolve to `transit/*.glb` and are not drivable kinds.
Passenger shell: outer width .24 tile, interior width .2125, length .625,
floor top .025; both central door apertures span local Z ±.075, from Y .025
through .18. Door asset is centered at X=0 and moved to X ±.12 by the transit code.
Windows are genuine openings; the transit system supplies collision, door
animation, signs and safe platform placement, and also controls roof visibility and the
cabin camera. The kit's platform top matches .025. The models carry no
collision or navigation data of their own.
