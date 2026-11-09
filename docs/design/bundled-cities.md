# Included cities

The twelve included cities have 1,033 street identities covering every one of
28,444 nameable road connections. Existing names in Adaven, Bonanza Gap and
Juniper Basin are kept where distinctive; suffix-only repeats are renamed. Other street names draw on each city's setting:

| City | Setting and naming character | Examples | Streets |
| --- | --- | --- | ---: |
| Adaven | Rural Nevada mining and ranching | School Canyon Road, Federal Camp Road, Adaven Road | 16 |
| Aliso Niguel | Southern Orange County coast, canyons and coastal scrub | Pacific Coast Boulevard, Aliso Creek Road, Monarch Beach Drive | 85 |
| Bonanza Gap | Rural Nevada casino and railroad town | Bonanza Boulevard, Washoe Avenue, Federal Station Road | 29 |
| Foothills Ranch | Colorado Front Range and San Gabriel Valley | Front Range Parkway, San Gabriel Canyon Road, Citrus Valley Road | 75 |
| Grant Pass - Soledad | Arizona east of the dam border, Sonora west | Santa Cruz Road, Arizona Avenue; Avenida Sonora, Calzada de la Frontera | 163 |
| Harbor Palms | Long Beach and the South Bay, working harbor and aerospace | Ocean Boulevard, Shoreline Drive, Aviation Boulevard | 79 |
| Juniper Basin | Nevada basin city beside pine-and-juniper uplands | Humboldt Road, Great Basin Avenue, White Pine Boulevard | 103 |
| La Presa | California coast beneath a major reservoir and dam | La Presa Boulevard, Reservoir Parkway, Aqueduct Boulevard | 102 |
| Oro Canyon | Colorado River mining city and scenic desert metropolis | Colorado River Boulevard, Prospector Boulevard, Canyon Rim Drive | 109 |
| Salton Shores | Salton Sea, Imperial Valley and Coachella desert basin | Salton Sea Boulevard, Imperial Valley Road, Dos Palmas Road | 36 |
| Silver Ridge | Hillside mining settlements, ridge roads and mine railways | Silver Ridge Road, Mine Grade Road, Magnolia Canyon Road | 43 |
| Valle del Mar | Coastal California with a L’Enfant-style civic plan | California Avenue, county avenues, numbered and lettered streets | 193 |

Old Bottle becomes **Juniper Basin**, Lawndale becomes **Harbor Palms**, and
Magnolia Township becomes **Silver Ridge**. Valle del Mar and Oro Canyon retain
their geographically fitting names. The classic source filenames remain intact
for provenance and import fixtures; personal saves are unaffected.

Street names follow connected road geometry through bends, bridges and complete
tunnels. Straight arms continue through intersections. Authored street boundaries
in the three native cities are preserved, and unnamed continuations inherit their
nearest existing name. Each city uses a base name only once across street types:
for example, an Aliso Drive rules out a separate Aliso Avenue. English suffixes,
Spanish prefixes, abbreviations and accent variants share this check. The main
road keeps a repeated name; other identities receive unused locally themed names. Arizona/Sonora crossings deliberately change name at the
international border. In Valle del Mar, numbered streets progress west to east,
lettered streets north to south, and county avenues name diagonal or winding axes.
The naming schema covers ordinary road connections; highway signs use named exit
destinations through the existing street-sign system.

All 58 classic labels have been removed from the bundled native saves. Players
can still add their own signs. Nineteen existing 4×4 resort lots receive different
4×4 designs, keeping their original geometry, orientation and service flags. All
ten available designs appear before a repeat is retained; surplus repeats are
spread between designs. The [repeat inventory](../art/bundled-city-casino-repeats.md)
lists every repeated gaming-resort design, including pre-existing neighborhood
resorts, with lot anchors and nearby streets.

The curation preserves raw simulation history, RNG states, treasury, dates,
terrain, service layers and lot boundaries. Resort facility keys and capacities
and their legacy reward records change together. Station names are reconciled
from the new streets before the final native-load check.

`tools/build_bundled_cities.py` imports classic sources and then runs
`tools/curate_bundled_cities.py`. The curation tool can also run alone to apply
`tools/bundled_city_themes.json` to existing native bundles. It works in a private
project copy, validates all candidates before publication, updates provenance,
and writes `docs/art/bundled-city-curation.json` and the repeat inventory. Add
new words to the theme bank if it runs out; there is no generic numbered-name
fallback. It never accesses personal saves or cloud data.
