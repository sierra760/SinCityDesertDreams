# Real-world terrain

New City can start from a square of real elevation and mapped water. Choose **Real-world terrain · Online** and wait for both source checks in New City. Fresh Ready status enables **Choose real-world terrain** to open the chooser. An expired successful check is repeated automatically while Real-world terrain is selected. After a failure, **Retry connection** in New City checks both sources again; the message identifies elevation, water, or both failures. Retry updates the status and leaves entry to your next explicit action. Ordinary procedural landscapes remain available offline.

## Choose the land

Use latitude and longitude to choose a center. The default is Las Vegas (36.1699, −115.1398) with an 8 km square. Side length ranges from 0.5 to 128 km; bearing rotates it clockwise from 0° to 359°. The entire square must remain within latitude −60° to 82.75°. Longitude wraps across the date line.

Type a place name or address in **Search for a place** and press Return or **Search**. Up to five matches appear; choosing one centers the square there, keeping its size and bearing, and frames it on the map. Search runs only when you submit it, at most once a second, and repeats a recent query from memory. A place whose square would cross latitude −60° or 82.75° is refused.

Drag the square's center to move it, or a corner to resize it. Drag the map background to pan; pinch or scroll to zoom. The arrow keys and North/South/East/West buttons pan, +/− zoom, and **Fit selection** or F frames the square. Map zoom changes the view, not the square's physical size.

The map is an OpenStreetMap street map. It does not use the elevation data and does not wait for the elevation and water source checks, so it starts loading as soon as the chooser opens and keeps loading while terrain downloads. Missing tiles are filled from coarser tiles already on screen until the sharp ones arrive. Only tiles in view are requested, up to four at a time by default. Viewed tiles are kept in the OS cache folder for at least seven days (up to 64 MB) and shown immediately next time; older ones are shown while they refresh. On Web the browser's own cache is used instead. If the map service is unreachable the square, fields and download still work.

A city has 128 × 128 tiles: an 8 km side represents 62.5 metres per tile, while 0.5 km represents about 3.91 metres per tile. Every selection keeps this horizontal scale. The geographic approximation is spherical, so it is not a survey or engineering map.

## Preview and shape

Choose **Download terrain** to fetch and convert the selected square. **Cancel** closes the chooser and invalidates unfinished work. Closing New City keeps the previous city and its saved state. A failed download stays a visible failure; retry after the connection or source problem is resolved.

Vertical exaggeration ranges from 0.001 to 20, default 1. **Fit relief** calculates an exaggeration that fits the grid's limited elevation range and rebuilds the preview. Smoothing offers 0, 1 or 3 passes. Preserve narrow water is on by default; the water type may be Automatic, Freshwater or Sea. Trees range from 0 to 100%, default 0. The preview reports clipping and adaptation rather than pretending every real elevation can fit unchanged.

**Automatic water type** is a boundary/elevation approximation. A connected mapped-water component becomes Sea only if it touches the selected square’s boundary and at least one of its wet-cell DEM samples is below −1 metre; otherwise it becomes Freshwater. This does not measure salinity. Choose **Sea** explicitly for an ocean/coast that the approximation labels fresh, or **Freshwater** for a lake that it labels sea. Sea uses a zero-metre source water surface before projection into game levels; either override changes water treatment, not the mapped wet footprint. Negative dry land remains dry.

**Freshwater shape.** Open water (cells inside a fully wet 2 × 2 block) forms a lake. A lake whose typical elevation samples (10th to 90th percentile) agree within one game level is level at their median, so a few samples on a bank, in a data void or on lake-bed bathymetry cannot pile it into mounds or pits. Shoreline cells and coves beside a lake join it. A lake meets its dry banks at its own level, and its bed lies one level down. Narrow channels and wide water that genuinely slopes follow their samples, stepping at most one level between neighbouring cells (diagonals included). Water outside a lake rests at most one level above its cell's lowest corner. A lower outlet meets the lake as a fall.

Changing the selected square requires a new download. Changing conversion controls invalidates the old preview and rebuilds from the downloaded source data while online. **Use terrain** becomes available only for a completed current preview. It returns to New City, where name, difficulty and founding year can be changed without regenerating that accepted land. **Shape City** opens that exact preview for free terrain editing and credits your preferred mayor; **Found City** starts normal play. Received native cities keep their saved mayor when loaded.

## Offline saves and reset

Completed terrain belongs to the city. Save while shaping to keep the edited land and its imported baseline, or save after founding for an ordinary playable city. Loading, playing and saving completed cities do not contact the source services. The terrain cache can be cleared in the chooser without damaging completed cities or their reset baseline.

During imported terrain editing, **Reset imported terrain** restores the original imported terrain, water and trees from the saved baseline, offline. It preserves the current city name, mayor, difficulty and founding year. It does not substitute a procedural landscape. A missing or damaged baseline disables reset and shows the reason; the otherwise valid city can still load. Once founded, normal play and existing city actions apply.

Online access is needed to enter/acquire new source terrain and to rebuild the chooser's preview; a saved city does not need its cache. Source checks expire after one minute and are repeated after returning to the app. Closing the chooser cancels its pending work. On desktop, switching to another window keeps downloads going and only an operating-system pause or suspend cancels them; on phones and tablets, leaving the app cancels them.

## Sources and limits

**Data sources** in the chooser, or Help's terrain data sources action, opens the bundled full offline credits. Elevation comes from the public Mapzen/Joerd Terrarium terrain collection and its credited providers. Water is ESA WorldCover 2021 v200, class 80, under CC BY 4.0. It represents mapped 2021 water, not current shorelines, tides, drought levels or guaranteed navigable channels. Narrow features and steep relief are adapted to the game grid; negative dry elevations remain dry.

The importer uses direct HTTPS to the two allowlisted public collections. It needs no account or API key. The chooser's street map and place search use the OpenStreetMap Foundation's public tile and Nominatim services (map data © OpenStreetMap contributors, ODbL), also without an account; the credit stays on the map. Native builds identify themselves with a `SinCityDesertDreams/<version>` User-Agent, as both usage policies require; Web builds send the browser's own. Nothing from the map or search is saved with a city.

The providers can be switched, or either service turned off, without an app update: the chooser reads a small published settings file at most hourly and uses it only when every field validates, keeping the last valid copy for offline use. Until a valid copy has been fetched, the built-in OpenStreetMap tile and Nominatim search settings apply. A provider that offers 512 px (@2x) tiles is used at that density on Retina and other high-density screens. Resource, time, coverage and format limits may reject a selection; a larger square is not guaranteed to fit them. Completed-city provenance stores validated selection/settings, dataset identity, access time and bounded source identity/hash records, not fetched URLs or source bodies.
