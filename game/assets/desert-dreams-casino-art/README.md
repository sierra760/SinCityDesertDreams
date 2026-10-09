# Resort illustrations

Four original illustration sets: Comstock Grand (silver mining), Silver Junction
(railroads), Boulder Crown (dam construction and Art Deco), and Desert Orbit
(Nevada rocket-engine research). Each set has six reel symbols, three fictional
court portraits, a card back, three paintings and six transparent payout cutouts. Ranks and suits are rendered by
the game; the pictures do not encode card identities or alter casino outcomes.

Created with the built-in image_gen tool. Complete generation prompts and
unaltered masters are retained locally outside the public package.
The reproducible packaging
script `tools/build_casino_art.py` extracts the regular 4 × 3 atlas cells without
painting, resampling or substituting content. `catalog.json` retains content
hashes, source paths and dimensions. All illustrations are project-owned art
under CC BY-NC-SA 4.0; see LICENSING.md. Fonts retain their own licenses.

`scripts/casino/resort_artwork.gd` shares the sprites between the animated slots,
card tables and Explore's batched cabinet inserts and framed wall paintings.
Blender authors three print frames per hall. The four dimensional wall exhibits
were replaced by new resort-specific paintings. Bitmap images remain separate
runtime materials. Cabinet faces are baked from the actual three-drum table
renderer by `tools/qa/bake_slot_cabinets.gd`, showing multiple symbol rows.
Measured visible-content bounds center portraits, card backs and paintings;
transparent payout illustrations retain the alpha created by image_gen.
The local source records retain the additional prompts.
There are 100 runtime images across the four resorts and Despicable's, plus four shared suit SVGs.
The suits are original continuous silhouettes with clean joins; ranks and suit
marks remain separate from the generated portraits. Face cards leave paper
between the portrait and both suit marks. Whole-card flip transforms keep all
art and lettering inside the turning card.

Historical sources inform fictional interpretations, rather than replicas:

- [Virginia City historic district, NPS](https://www.nps.gov/places/virginia-city-historic-district.htm)
- [Nevada rail history, Nevada DOT](https://www.dot.nv.gov/mobility/rail-planning/history)
- [Hoover Dam design, Bureau of Reclamation](https://www.usbr.gov/lc/hooverdam/history/articles/rhinehart1.html)
- [Rocket research, NASA](https://www.nasa.gov/rocket-systems-area-nuclear-rockets/)


Despicable's adds its own convenience-store/outlaw set under `despicables/`:
six reel images, six transparent payout icons, three transparent court
portraits, card back, three store paintings and a complete three-reel cabinet
face. `tools/build_despicables_art.py` losslessly extracts inspected source
regions; the common packager invokes it when local store sources are present.
The original resort images remain unchanged. Sources and exact generation
records stay local in `assets/casino-art/despicables/`, outside the game package.
