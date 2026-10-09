# Gaming resort casino floors

Runtime models for the walkable casino floors of the four gaming resorts
(building codes 251–254), used only by Explore mode.

- `hall_251.glb` … `hall_254.glb`: the architecture of each hall (floor,
  walls, ceiling, vestibule and street doors, cashier cage, bar and back bar,
  signature dais, columns, cornices and coves, sign plates and themed
  centrepieces).
- The shared prop kit: slot cabinet and stool, blackjack, roulette, money
  wheel, video poker, faro, chuck-a-luck cage, baccarat, trajectory console,
  four chandeliers, banquette, bar stool and the table-name standard.

Models are authored in metres with the door toward Godot +Z; the game applies
the 1/16 tile scale. Materials are named `resort_<finish>`; the game maps each
onto `scripts/exploration/resorts/resort_finish.gdshader` with the resort's
palette, so one prop kit serves all four resorts. Objects whose names end in
`-colonly` are simplified collision shells. `catalog.json` records triangle
counts, bounds, materials, shell counts and content hashes; `provenance.json`
describes the generator.

Each hall also carries three framed 2D prints. The west-wall heritage painting
is unique to its casino: Comstock's mining headframe, Junction's railroad wheel
and station, Boulder's dam turbine, and Orbit's rocket engine. These replace
the initial dimensional wall exhibits, sit above walking height and add no
collision shells. Original chandeliers, ceilings and signature floor decor
remain in the hall and prop models. The generated
paintings and slot inserts are supplied separately by
`assets/desert-dreams-casino-art/` and batched at runtime.

Regenerate with Blender from the repository root:

```sh
Blender --background --python tools/blender_exploration/build_resort_interiors.py -- --skip-render
python3 tools/check_resort_assets.py
```

These models are licensed under CC BY-NC-SA 4.0, not the GPL; see
[LICENSING.md](../../../LICENSING.md).
