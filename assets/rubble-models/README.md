# Rubble and contaminated-ground kit

`rubble-kit.blend` is the editable master for the 3D view of rubble (building
codes 1–4) and contaminated ground (code 5). It is generated, not hand-edited:

```bash
blender --factory-startup --background --python-exit-code 1 --python tools/build_rubble_models.py
```

Add `-- --render <folder>` for review renders. The build writes the master,
`rubble-kit-metrics.json`, the runtime `game/assets/desert-dreams-rubble/rubble-kit.glb`
and its `provenance.json`. Re-import the project in Godot afterwards and
refresh `test_network_layer_golden.gd` (only the visible hashes of cities that
contain rubble should change).

## Contract

- One 16 m tile centred on the origin; Blender +Z up, +Y north. The runtime
  applies 1/16 and turns each tile by a stable quarter turn.
- Variants are empties `Rubble1`–`Rubble4` (collapsed stucco house, concrete
  commercial block, light industrial, scattered roadside lot with a toppled
  arrow sign) and `Contamination` (fenced spill with drums, puddles, a warning
  sign and dead brush).
- `Drape …` meshes are heightfields (z ≥ 0 above ground). The runtime lays each
  vertex on the terrain facets and draws them with the network surface. The
  flat skirts are one-ring 16-spoke fans centred on the tile, so every triangle
  lies on a single terrain facet.
- `Solid …` pieces get a walk-blocking box (collision layer 4, like palm trunks).
- `Debris …` groups hold the remaining loose pieces, one per quadrant. Every
  rigid piece is rested on a plane fitted under its footprint and lowered so no
  corner floats.
- Colour lives only in the `Mottle` corner colours; four shared materials
  (matte, paint, metal, gloss). Original procedural geometry only: no imported
  meshes, textures, fonts or reference art.
