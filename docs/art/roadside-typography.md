# Atomic Vegas roadside identities

Six local businesses have their own mid-century and Western sign geometry,
authored in editable Blender masters.

| Model | Identity | Main lettering | Geometry |
| --- | --- | --- | --- |
| 125 | Lost Wages Lodge | BioRhyme Medium | Brass-edged plaque, lucky horseshoe, separate illuminated ROOMS plate |
| 126 | Despicable's | BioRhyme Medium | Coral fascia, scheming black-hat mascot on storefront and roadside pole, LOW-DOWN PRICES slogan |
| 127 | Jackpot Fuel | Atomic Age Regular | Wider swept pylon cabinet with inset lettering, three diamond reels, matching pump lettering |
| 131 | Atomic Toy Co. | Atomic Age Regular | Tin rocket, porthole, fins, amber exhaust and tilted orbit |
| 148 | Cactus Cactus | Fontdiner Swanky Regular | Stacked lettering, twin cactus emblems, tapered fin and canopy zigzag |
| 182 | Starbust Drive-In | Atomic Age Regular | Swept cabinet, tilted orbit and asymmetric starburst |

The cinema keeps its NOVA identity. Warm sandstone, teal, ivory, coral and amber
are the palette. The building structures, doors, physical shells and landscaping
stay editable in the masters. Names on signs are decorative; model codes,
footprints and gameplay identifiers do not depend on them.

## Font sources and notices

[BioRhyme](https://fonts.google.com/specimen/BioRhyme) is by Aoife Mooney. The
unmodified Medium font and its SIL Open Font License 1.1 notice are in
`game/assets/fonts/biorhyme/`; see [station typography](station-typography.md).

[Atomic Age](https://fonts.google.com/specimen/Atomic+Age) is by James Grieshaber,
distributed by Sorkin Type under SIL OFL 1.1. The unmodified Regular font,
`OFL.txt`, Google Fonts metadata and pinned provenance are bundled in
`game/assets/fonts/atomic-age/`.

[Fontdiner Swanky](https://fonts.google.com/specimen/Fontdiner+Swanky) is by Font
Diner, distributed under Apache License 2.0. The unmodified Regular font,
`LICENSE.txt`, Google Fonts metadata and pinned provenance are bundled in
`game/assets/fonts/fontdiner-swanky/`. Its license is distinct from the OFL fonts.

Atomic Age and Fontdiner Swanky were downloaded from the official `google/fonts` repository
at commit `9710da1eacb3be272583c3224dcb70f9da6eadbb`. The per-family provenance
JSON records every source URL, byte length and SHA-256. Every export preset
includes these notices and provenance. Sign lettering is converted to editable
mesh in the masters and batched in the game exports; no external font service is
needed at runtime.

The badges, rocket, cacti, diamond reels and sign shapes are geometry authored
for this project. No generated art or third-party logo pixels were used.
