# Desert Transit typography

All Desert Transit station text, on subway station 233, the rail station 237
hall and the shared DT pylon, uses **BioRhyme Medium** by Aoife Mooney. The
unchanged author-distributed static font comes from commit
`b3c0488559ad7c42e11b71e65d255344faff63b9` of
[Making BioRhyme](https://github.com/aoifemooney/makingbiorhyme/tree/b3c0488559ad7c42e11b71e65d255344faff63b9/fonts/ttf).

The runtime file is `game/assets/fonts/biorhyme/BioRhyme-Medium.ttf`; its SHA-256 is
`a09f815afc20fc15aa4921559dd7cbca841908f68f4fefdc20285c2a31bbb4bd`.
The author's copyright and the SIL Open Font License 1.1 are in
`game/assets/fonts/biorhyme/OFL.txt`, with download URLs and hashes in
`provenance.json`. Every export preset includes those notices.

The station generators load that same file before converting their lettering
to editable exportable meshes. Station 233 letters SUBWAY, DESERT TRANSIT,
STREET LEVEL, ELEVATOR and a lobby map title; the 237 hall letters its RAIL
STATION and DESERT TRANSIT fascia; the DT pylon carries a D/T monogram and a
DESERT TRANSIT band. Runtime wayfinding uses the bundled font and compiles its
glyphs with the other station furnishings. Station names sit on teal enamel
boards in brass surrounds beside brass DT roundels; minor labels have solid
opaque plates and brass surrounds fixed to walls or equipment. Directional
arrows are drawn directly on the plates, since BioRhyme does not contain those
Unicode glyphs.
