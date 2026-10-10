# Gaming resort casino floors

Runtime models for the walkable casino floors of the ten gaming resorts
(building codes 251–254 and 256–261), used only by Explore mode.

- `hall_251.glb` … `hall_254.glb` and `hall_256.glb` … `hall_261.glb`: the architecture of each hall (floor,
  walls, ceiling, vestibule and street doors, cashier cage, bar and back bar,
  signature dais, columns, cornices and coves, sign plates and themed
  centrepieces).
- The shared prop kit: slot cabinet and stool, blackjack, roulette, money
  wheel, video poker, faro, chuck-a-luck cage, baccarat, trajectory console,
  four chandeliers, banquette, bar stool and the table-name standard.

Models are authored in metres with the door toward Godot +Z; the game applies
the 1/16 tile scale. Materials are named `resort_<finish>`; the game maps each
onto `scripts/exploration/resorts/resort_finish.gdshader` with the resort's
palette, so one prop kit serves all ten resorts. Objects whose names end in
`-colonly` are simplified collision shells. `catalog.json` records triangle
counts, bounds, materials, shell counts and content hashes; `provenance.json`
describes the original generator. The six additional halls are authored by
`tools/blender_exploration/build_six_resort_halls.py` from
`tools/resort_expansion.json`, preserving the original halls and prop kit.

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

The six new halls add The Back Room (obsidian/brass/emerald vault canopy),
The Fresh Start (blush/mint wedding rings), The Scarlet Salon (oxblood cabaret
and keyhole), The Observation Lounge (ivory/mint sunburst), The Last Bank
(weathered sandstone, bottle glass and diamond) and The Common Ground
(rust/bone/ultraviolet sails and an original prismatic light canopy). Their
editable masters are retained locally outside the public package.
Each has three flat framed paintings; each venue's separate image package
contains 20 PNGs including a three-reel cabinet face.

Regenerate the additional halls separately:

```sh
Blender --background --python tools/blender_exploration/build_six_resort_halls.py
python3 tools/check_resort_assets.py
```

These models are licensed under CC BY-NC-SA 4.0, not the GPL; see
[LICENSING.md](../../../LICENSING.md).


Despicable's uses `hall_126.glb`, built by
`tools/blender_exploration/build_despicables_interior.py`, with its record in
`catalog.json` → `stores`. Its compact floor is exactly half convenience store
and half slots/video poker. It reuses the machine/stool kit and shared finishes;
its populated layout, lights and signs are supplied by the game. Together with all ten resort halls, the store and 23 props the package contains
34 models.

The six original signature games have dedicated geometry: `vault_table`,
`route_table`, `encore_table`, `forecast_console`, `contract_table` and
`common_pot_table`. Their simplified collision shells stay inside the existing
3 ×1.6m signature-table footprint. Regenerate only these props with
`tools/blender_exploration/build_original_signature_props.py` in Blender;
the original kit and all hall GLBs remain untouched.
