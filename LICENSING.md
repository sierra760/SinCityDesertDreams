# Sin City: Desert Dreams licensing

Developed by Sierra Burkhart (sierra760).
Copyright © 2026 Bristlecone Artists LLC.

## Project-authored code — GPLv3 or later

Sin City: Desert Dreams is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.

The complete, unmodified GPLv3 text is in [LICENSE](LICENSE). The SPDX identifier
for the code's license is `GPL-3.0-or-later`.

This grant covers project-authored GDScript, shaders, Python and JavaScript,
including game implementation, tests, development tools and asset-building scripts.
It also covers authored Godot scenes, resources, project/export configuration
and simulation parameter data needed to build and run that code. Source files
carry copyright and SPDX notices; existing third-party notices take precedence
for their respective material. Contributors retain copyright in their own
contributions and contribute code under the same GPLv3-or-later terms.

## Project-owned art and assets — CC BY-NC-SA 4.0

The project's own non-code assets are licensed under the Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International License. The SPDX
identifier is `CC-BY-NC-SA-4.0`. The complete legal code is in
[LICENSE-ASSETS](LICENSE-ASSETS), and the game bundles it as
`game/legal/CC-BY-NC-SA-4.0.txt`. A summary is at
<https://creativecommons.org/licenses/by-nc-sa/4.0/>.

This license covers project-owned:

- 3D models and their editable Blender masters, including buildings, stations,
  signage, vehicles, characters, disasters and exploration models, and their
  animations;
- textures, surface and ground images, and material maps;
- illustrations, title and menu artwork, UI icons and app-icon artwork;
- preview renders and screenshots in this repository; and
- the nine included cities in `game/assets/cities/`: Adaven, Aliso Niguel,
  Foothills Ranch, Grant Pass - Soledad, La Presa, Lawndale, Oro Canyon, Salton
  Shores and Valle del Mar.

In short, you may share and adapt these assets if you:

- **give credit** (see the attribution below), link the license and say if you
  changed anything;
- **don't use them commercially**; and
- **license your adaptations under the same terms**.

The legal code governs. These terms bind licensees, not Bristlecone Artists
LLC. Commercial use of the assets requires separate written permission from
Bristlecone Artists LLC.

Suggested attribution:

> Sin City: Desert Dreams art by Sierra Burkhart (sierra760),
> © 2026 Bristlecone Artists LLC, licensed under CC BY-NC-SA 4.0
> (https://creativecommons.org/licenses/by-nc-sa/4.0/).

The license does not cover:

- fonts, Godot, real-world terrain and map data, or other third-party material,
  which keep their own licenses (see below);
- player saves, which belong to the players who make them; or
- the "Sin City: Desert Dreams" name and any trademark rights, which this
  license does not grant.

The scripts that build the assets and the asset catalog/configuration data
needed to run the game remain under the GPL as code. Assets they produce are
covered by this asset license. Contributors keep copyright in assets they
create and contribute them under the same CC BY-NC-SA 4.0 terms. Every asset
and included city has a provenance record in the repository.

### Code and assets together

The GPL code and the CC BY-NC-SA assets are separate works distributed
together, and each keeps its own license. The GPL lets anyone sell or
commercially distribute the code. The asset license does not. A commercial
build by anyone other than Bristlecone Artists LLC must replace the assets or
get separate permission for them.

## Third-party material

The Apple city-sharing and geometry-kernel libraries include official Godot C++
bindings under their MIT license, included in
`native/apple-share/GODOT-CPP-LICENSE.md` and
`native/geometry-kernel/GODOT-CPP-LICENSE.md` and bundled by their export addons
as `addons/apple_share/GODOT-CPP-LICENSE.md` and
`addons/scdd_geometry/GODOT-CPP-LICENSE.md`.
`native/geometry-kernel/scdd_sort_array.hpp` is adapted from Godot Engine's
`core/templates/sort_array.h` and remains under the MIT license stated in that
file.

Third-party material retains its existing licenses and notices. In particular,
the bundled BioRhyme, BioRhyme Expanded and Atomic Age fonts retain their SIL
Open Font License notices, and Fontdiner Swanky its Apache License 2.0 notice,
under `game/assets/fonts/`. Godot and its exported
iOS template code are not relicensed by this project; retain their notices and
those of their dependencies when distributing them.

Real-world terrain data keeps its providers' terms. Elevation comes from the
Mapzen/Joerd terrain tiles, which credit USGS, NOAA and other national
providers; water comes from ESA WorldCover 2021 under CC BY 4.0. The terrain
chooser's street map and place search use OpenStreetMap data, © OpenStreetMap
contributors, under the Open Database License (ODbL) 1.0. The game modifies the
terrain data for play; no provider endorses it. Full credits, licenses and
source links are in `game/data/real_world_terrain_notices.txt`, which every
export preset bundles and the game shows offline from its data sources buttons.

The `ios/` exported project,
engine libraries, generated editor/import caches and existing binary exports
are outside this project's code license grant.

Material outside this repository, including commercial game content, is not
covered by either license. No rights in third-party game content or trademarks
are granted.

## Distribution and notices

Distribute GPL-covered code with its notices and the GPL text, and provide
Corresponding Source as required by the GPL when distributing covered binaries.
Distribute project assets non-commercially, with attribution and the CC BY-NC-SA
4.0 terms. Third-party material needs whatever its own license requires.

The game bundles the GPL as `game/legal/COPYING.txt`, the asset license as
`game/legal/CC-BY-NC-SA-4.0.txt` and a scope notice as `game/legal/NOTICE.txt`.
The title's **License** button opens the full GPL text without a network
connection. All export presets include these notices.
