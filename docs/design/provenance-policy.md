# Content and code provenance

This repository is public. Everything in it has to be ours to publish.
`tools/check_provenance.py` checks the rules below; run it before every commit.

## What is not allowed in this repository

- Art, audio, text, palettes, cursors, icons or fonts extracted or converted
  from any commercial game, including tile sheets, sprite sheets, rendered
  music, sound effects, notice pictures and help text.
- City files, scenario files or maps shipped with a commercial game.
- Newspaper articles, advisor messages, notices, building names or city names
  copied from a commercial game.
- Disassembly, memory dumps, executable addresses, resource ids or tables
  copied out of a binary. Comments that cite executable offsets are treated the
  same as the code they annotate.
- Tooling whose purpose is extracting resources from, or executing code from,
  a commercial game.

## What is allowed

- Game rules and mechanics expressed in our own code: a city is a 128×128 grid,
  a month has 25 days, a coal plant costs $4,000 and serves a fixed number of
  tiles, dense residential zones grow through several building stages, and so
  on. Rules are not expression. Where a rule needs numbers, we author the
  numbers as named parameters under `game/scripts/sim/data/` with a comment
  explaining what they tune.
- File-format interoperability. `io/sc2_import.gd` reads the `.sc2` container
  so players can bring in their own cities. The chunk layout is public and
  documented by the community; the importer contains no game content.
- Our own art under `game/assets/`, modeled, generated or hand-corrected for
  this project. Provenance records beside the assets and under `docs/art/`
  describe where each model, texture and image came from; most of these
  records also give a source file and hash. The traffic and exploration
  models, the tool icons and the station terrazzo image are described by their
  catalog, README or generator script without hashes.
- Our own writing under `game/scripts/content/`.
- Custom cities supplied for inclusion by the project owner. The eight
  classic cities under `game/assets/cities/` were added on October 5, 2026,
  and the owner's own city Adaven on October 6, 2026. Every included city
  ships as a fully imported `.sc2d`. The provenance manifest in that folder
  records each shipped save, its source file and hashes; the classic source
  files are not exported. None of them is a map or scenario from a commercial
  game. The included cities are licensed under CC BY-NC-SA 4.0, not the GPL;
  see [Licensing scope](../../LICENSING.md).

## Writing simulation code

Write the behavior, not the binary. Each system starts from a short spec in
`docs/simulation/` written in plain language: what the system reads, what it
writes, when it runs, and the rules it applies. The implementation follows the
spec. If a rule needs a lookup table, it is a table we author (a handful of
rows keyed by category or stage), not a byte dump.

Avoid these in code and comments:

- hexadecimal offsets, addresses or resource numbers used as identifiers
- references to "the original", a platform, a disassembly or an extractor
- state keys named after addresses
- tables longer than a screen that are not obviously authored

Name things for what they mean in this game. A power plant record is a
`facility`; a residential development stage is a `stage`; the map layers are
`terrain`, `building`, `zone`, `flags`.

## Checking

```
python3 tools/check_provenance.py
```

The check scans `game/`, `docs/`, `tools/`, `README.md` and `CONTRIBUTING.md`
for banned tokens, large numeric literals and known file names. It exits
non-zero on any hit and prints the file and line. Add exemptions sparingly,
with a reason, in `tools/provenance_allow.txt`.
