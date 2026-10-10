# File formats

Two formats touch the disk: our own `.sc2d` saves, written and read by
`io/save_format.gd` (`SaveFormat`), and classic `.sc2` city files, read only,
by `io/sc2_import.gd` (`Sc2Import`). Export to `.sc2` is not supported.

## `.sc2d` saves

A save is a single JSON document. Layers are stored as base64 text of the
deflate-compressed bytes so the file stays a plain text document that any
tool can open, while the map itself stays small.

```
{
  "format": "sc2d",
  "version": 2,
  "stage": "play",
  "header": {
    "name": "Saltwash", "mayor": "...", "year": 1904, "day": 1234,
    "population": 5400, "funds": 987, "stage": "play", "saved_at": 1790000000
  },
  "city": {
    "name": "...", "mayor": "...", "founded_year": 1900, "day": 1234,
    "funds": 987, "difficulty": 1, "rotation": 2, "sea_level": 5, "status": 3,
    "layers": {
      "terrain": "<base64>", "altitude": "<base64>", "building": "<base64>",
      "zone": "<base64>", "flags": "<base64>", "underground": "<base64>",
      "traffic": "<base64>", "pollution": "<base64>",
      "land_value": "<base64>", "crime": "<base64>",
      "police": "<base64>", "fire_cover": "<base64>",
      "density": "<base64>", "growth": "<base64>"
    },
    "facilities": { "40,40": { "key": "plant_coal", "built_day": 12, ... } },
    "signs": { "12,13": "Old Mine Road" },
    "street_naming": { "schema": 1, "next_street_id": "1", "streets": {},
                       "links": {}, "station_auto": {} },
    "terrain_vertices": "<base64>"
  },
  "snapshot": { ... }
}
```

- `header` repeats what the load dialog shows. `population` is ordinary plus
  arcology population taken from `snapshot.stats`; `mayor` is the city's mayor
  credit; `stage` repeats the document's stage; `saved_at` is Unix time.
- `layers`: byte grids use their natural size (`128²`, `64²` or `32²`
  bytes). In version 2, `altitude` and `building` each use two bytes per tile,
  little-endian, as `Grid16` packs them. Building IDs 0–255 retain their
  identities; new IDs append above 255. Version 1 saves remain readable: their
  one-byte building layer widens on load. A missing layer loads as zeros; a
  layer of the wrong size or an unknown building ID fails the load.
- `facilities` and `signs` are keyed by `"x,y"` (`SimSystem.tile_key`).
  Facility records are stored as plain JSON: `StringName` values become
  strings and are restored to `StringName` for the `key` field; whole
  numbers come back as integers.
- `terrain_vertices` is the 129×129 lattice (`TerrainSurface.vertices`, one
  byte each). On load the per-tile water, salt and stream/waterfall data are
  rebuilt from the layers and the saved vertices replace the derived ones.
  Every city carries either `terrain_vertices` or, for imported cities with
  independent tiles, `"terrain_model": "per_tile"` (below); a save with
  neither, or with a vertex blob of the wrong size, fails to load.
- `street_naming` holds the street and station name registry and is required.
  Street IDs and automatic station suffixes are decimal strings.
- `imported_power_links` (optional) maps a row-major tile index to
  `[building id, zone kind]` for conductive links from imported classic cities
  that the building id alone cannot express. A link is kept only while its tile
  still has that building and zone kind; a malformed entry fails the load.
- `terrain_origin` (optional) is the bounded manifest of a real-world terrain
  import: the selected area, import controls, data sources, acquisition time
  and diagnostics. An invalid record is dropped rather than saved.
- `snapshot` is `Simulation.snapshot()` stored as given; `load()` hands it
  back untouched for `Simulation.restore()`. Before that, `load()` checks its
  shape (`validate_snapshot`): every known field must hold the kind of value
  the game stores there (a number, a list, a table, and for lists of records a
  table per entry), checked against a fresh system's `save()`. A damaged
  snapshot fails the load with the damaged-file message, before the open city
  is replaced. Unknown fields are ignored and missing ones take defaults.
- A city decoded from a save in play records the layers it read in
  `City.restored_layers` (not saved). Systems keep those layers as saved when
  the simulation is set up (the zone system's density and growth maps, the
  water system's service flags and tower contents) instead of deriving them
  again, so a reloaded city continues exactly like one that kept running.
- `stage` is required: `"play"` for a founded city or
  `"editing"` for a map saved while the land was still being shaped. An
  editing save has no snapshot and carries `generator`, the New City
  settings, so the map can be regenerated or founded later.

Version 1 loading changes only the building layer's in-memory width; saved
simulation technology records and casino histories retain their existing keys
and values. New resorts use the stored Comstock invention year rather than
adding random technology draws. `load()` supplies the document version to the
city decoder; callers decoding a version 1 city object directly must pass 1.


### API

```
SaveFormat.default_dir() -> String                      # user://saves
SaveFormat.save(path, city, sim_snapshot := {}, stage := STAGE_PLAY, generator := {}) -> Error
SaveFormat.load(path) -> {ok, city, snapshot, stage, generator, error, version, topology}
SaveFormat.list_saves(dir := default_dir()) -> Array[Dictionary]
    # [{path, mayor, name, date_text, population, year, day, funds, stage, saved_at}], newest first
SaveFormat.read_header(path) -> Dictionary               # {} when not a save
SaveFormat.encode_city(city) -> Dictionary               # the "city" object
SaveFormat.decode_city(doc, version := SaveFormat.VERSION) -> {city, error, topology}
```

`load()` rejects documents whose `format` is not `sc2d`, versions above
`SaveFormat.VERSION`, damaged layers and damaged snapshots, returning a
readable `error`.
`topology` is the street topology built while validating `street_naming`;
the caller may reuse it instead of rebuilding it from the same layers.
`list_saves` only parses the header; unrelated files and other documents in
the directory are skipped.

## `.sc2` import

Classic city files are an IFF container: a 12-byte header (`FORM`, a
big-endian length, `SCDH`) followed by chunks packed back to back with **no**
alignment padding. Each chunk is a four-character tag, a big-endian 32-bit
length and the data. All integers are big-endian.

Most chunks are run-length packed. A chunk whose stored length differs from
its known unpacked length is unpacked with this scheme: a control byte of
`0..127` copies that many literal bytes; `128..255` repeats the next byte
`control - 127` times. `Sc2Import.rle_encode` writes the same scheme, which
the tests use to build fixtures.

### What is read

| Tag | Size | Used for |
|---|---|---|
| `CNAM` | 32 | city name: a length byte, then text to the first zero byte; the file name is the fallback. A stored DOS file name (`OROCANYON.SC2`) loses its extension and becomes the file's own name when that is the same letters, otherwise it is title-cased |
| `MISC` | 4800 | 1200 32-bit integers; index 2 rotation, 3 founding year, 4 days elapsed, 5 funds, 7 difficulty (1 easy, 2 medium, 3 hard), 8 status (clamped to the six classes; the population system lowers it to what the imported residents support), 480/507/534 residential, commercial and industrial tax rates |
| `ALTM` | 32768 | one 16-bit word per tile: ground height in bits 0–4, water height in bits 5–9, tunnel bits above; repacked into the `altitude` layer |
| `XTER` | 16384 | slope and water codes, identical to `Terrain` codes |
| `XBLD` | 16384 | building ids; the roster in `Buildings` uses the same numbering |
| `XZON` | 16384 | zone kind in the low nibble, footprint corner flags in the high nibble, identical to `Zones` |
| `XBIT` | 16384 | per-tile flags: `0x01` salt, `0x10` watered, `0x20` conducts water, `0x40` powered, `0x80` conducts power, mapped to `TileFlags` |
| `XUND` | 16384 | underground codes, remapped (see below) |
| `XTXT`, `XLAB` | 16384, 6400 | player signs: each tile's text slot (`1..50` are signs) names one of 256 `XLAB` slots of a length byte and 24 characters; non-empty sign text goes to `city.signs` at that tile, and facility/moving-thing slots are skipped |
| `XTRF`, `XPLT`, `XVAL`, `XCRM` | 4096 | 64×64 traffic, pollution, land value, crime |
| `XPLC`, `XFIR`, `XPOP`, `XROG` | 1024 | 32×32 police, fire cover, density, growth |

`ALTM`, `XTER` and `XBLD` are required. Facility labels, graph history,
moving things and the rest of the metadata are ignored.

Underground codes in the file put subways first (`1..15`), then pipes
(`16..30`), crossings (`31..34`) and the station link (`35`). This game
numbers pipes first (`UtilityParams`), so the two bands are swapped on
import; crossings and the link keep their values and anything else becomes
`UNDERGROUND_NONE`.

After the layers are filled the importer:

- keeps the stored terrain and altitude words unchanged, including independent
  tile slopes and water levels; `city.sea_level` remains `-1` and the editing
  lattice remains absent until a terrain edit requires it;
- records a facility (`{key, built_day: city.day, imported: true}`) for every
  civic building anchor: plants, services, utilities, transit, ports,
  military, rewards and arcologies. Zone lots are not facilities.

### API

```
Sc2Import.load(path) -> {ok, city, error, tax_rates, warnings}
Sc2Import.load_bytes(raw, fallback_name) -> same
Sc2Import.parse_container(raw) -> {ok, chunks, error}     # tag -> unpacked bytes
Sc2Import.rle_decode(bytes) / rle_encode(bytes)
Sc2Import.map_underground(file_code) -> int
```

`tax_rates` is `{residential, commercial, industrial}` for the caller to
apply to `CityStats`; the city model itself carries no tax fields.
`warnings` lists repairs and missing chunks in plain language.

### Rail tile identities

Rail codes follow the classic city format: 44–45 are straights, 46–49 are
west/north/east/south grades, 50–53 are bends, 54–58 are junctions, and 59–62
are straight uphill transitions. Road/rail crossings are 69–70; power/rail
crossings are 71–72. Imported rail codes and footprint flags are kept as they are.

### Imported terrain through native saves

A city with independent terrain tiles and no editing lattice is saved with the
optional city field `terrain_model: "per_tile"`. Loading it preserves that model
and its imported bank/water geometry instead of reconstructing shared vertices.
Generated or edited cities continue to save their `terrain_vertices` lattice.
Unknown or non-string terrain model values, and a per-tile marker combined with
any `terrain_vertices` field, are rejected as contradictory or unsupported.

Imported waterfall codes `0x2e` and `0x3e` locate the lower baseline of a full
water block. Their 3D top is one altitude level higher. Valid projected native
waterfalls already store their upper level above their ground. Unprojected legacy
waterfall words at or below ground keep the imported interpretation even when
a saved city has reconstructed vertices. Other ambiguous surface-attached legacy
waterfall encodings are not migrated automatically.
