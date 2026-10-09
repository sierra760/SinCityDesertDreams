# 3D traffic and passenger transit

The city simulation is the source of truth. Traffic is a read-only presentation
of local development, congestion, transit ridership and live port/emergency
records. It uses its own deterministic admission state and does not consume the
simulation RNG or add actor positions to city saves.

## Playing

Use **View → Explore City** to start walking on the safe outdoor road nearest
the aerial camera's focus; with no such road, Explore is refused with a notice
and Build stays open. WASD or the arrow keys move, Shift runs and Space jumps.
With a keyboard, a short controls hint appears on entering and whenever you
switch between walking, driving, flying and riding. **F** enters a nearby
drivable vehicle. **Escape** opens the Explore menu, including the vehicle
selector, Resume, Recover and Return to Build. All 17 non-airplane catalog types
are available when their route and clearance requirements are met. Road
vehicles steer freely on safe support; trains follow connected tracks; boats
remain on navigable water; the helicopter flies and must land before exit. Boat
exits require clear dry shore.

To ride as a passenger, approach a usable rail or subway station. Platforms
align with adjacent reciprocal tracks. The station's placed facing does not
restrict service: its model and platform rotate toward a usable connection,
including a track terminus. Routes choose among valid connections when a station
adjoins more than one line. Subway stations have a solid street plaza and a
small entrance pavilion; a freestanding Desert Transit (DT) pylon stands on
both subway and rail station lots. Walk inside the elevator and press **F** to
descend; press **F** at an empty landing to call it, or inside the cabin to
return to the street. Interlocked gates close the shaft while the cabin
travels. Nearby diagonal track is reached by an enclosed pedestrian passage.
Wait behind the yellow edge and **walk through an open door**; no interaction
key or attachment prompt is needed. Walk inside the cabin while
it moves, then walk through an open door at a stop to leave. Doors stay fully
open for eight seconds and reopen if occupied. Connected branch destinations
are selectable in the Explore menu. A station with unusable track/access
reports why service is unavailable.

Passenger travel is local Explore presentation: one prepared service runs the
selected connected route, reserves it against ambient trains, and reverses at
its terminus. Its clock continues during exploration even when the city is
paused, so pausing the economy does not strand a passenger. Explore suspension
from menus, lost focus or its panel freezes the entire local journey. Geometry
edits invalidate routes before further movement. Returning to Build, loading or
leaving the city restores station/terrain presentation and destroys local actors.

**View → Show → Traffic and Pedestrians** controls ambient traffic. It does not
hide incident markers or disable an occupied vehicle/passenger journey.

## Rendering and movement

The ambient population is bounded at 384 vehicles, 512 pedestrians and 64 live
external records. A 30 Hz near/Explore step drops to 10 Hz with interpolated poses at overview.
Shared near/far meshes, materials, reusable
MultiMeshes and camera culling keep draw work bounded. Walking gait uses instance
data rather than individual animated scene nodes. Reciprocal network masks,
model-length headway, traffic-light phases, train priority at crossings and
separate upper/lower overpass routes keep movement coherent. Ramps use the same
height curves as the visible network. No new numerical congestion model is
written back into the city.

Paired four-lane highways have two lanes in each direction, with white dividers
between same-direction lanes. Traffic follows the actual curved pavement and
uses the shoulder lane for ramp merges and exits. Unpaired incomplete highway
fragments fall back to two-way traffic. Routine changes to power, demand and
congestion refresh traffic without rebuilding unchanged routes.

Complete 2×2 highway curves and junctions recognize all four corner-flag
orientations, independently of the current view rotation. Native saves and
classic-city imports keep those flags unchanged. Partial, mixed and mirrored
footprints are rejected. Curve pillars sit beneath the pavement, including the
quadrant outside the outer bend's radius.

Transit geometry uses finite walkable platforms, physical cabin walls and
sliding doors, bounded physical elevator access and connected tunnel corridors. The
pedestrian applies the carriage transform exactly once each physics frame;
ordinary engine platform carry is disabled to avoid double movement. Cabin
camera collision stays active. Stations, running tunnels and occupied passenger
cabins use a stable eye view that still allows mouse orbit. The camera remains inside
the moving cabin even at open doors; ordinary outdoor follow returns after leaving
the interior. Unusable grades, missing reciprocal links,
misaligned platforms and depths beyond the bounded access geometry are rejected
rather than advertised as reachable rides. Underground heights follow local
terrain with bounded grades. Surface rail ballast has solid sloping shoulders
down to terrain; bridge spans keep their bridge geometry. Subway overlays use
the same railway berm, sleepers, steel rails and curved network masks. Explore
tunnels use a solid ballast profile scaled to the passenger carriage.
Continuous textured walls and cooler soffits enclose the running tubes and turns;
warm light strips run along both sides. Solid chamber bases close the spaces between
branching ballast beds. Short unprepared branch approaches end in matching walls;
choosing a route rebuilds the prepared space with its real through connections.

## Art and menus

`tools/build_traffic_models.py` reproducibly builds editable Blender
masters and GLBs: 18 vehicle types, 16 pedestrian variants, near/far meshes and
five transit parts. Source models live in `assets/traffic-models`; runtime
models live in `game/assets/desert-dreams-traffic`. Authoring units are meters;
the catalog converts once to the game's 16-meter tile scale.

Station furnishings are built at runtime from the shared Desert Transit finish
system (`game/scripts/exploration/transit/explore_station_interior.gd`): mounted
enamel name boards, DT roundels, brass-and-teal benches, warm ceiling fixtures
and BioRhyme wayfinding. Subway platforms keep their furnishings on the long
wall run beyond the lift shaft; rail platforms carry a brass totem with the
station name, roundel and boarding guidance beside the hall the city shows.
Furnishings batch by material; one shadowless fill light affects only their
render layer. Ivory walls, blue-gray ceilings, terrazzo and glazed teal bases
separate adjoining surfaces. The rider's carriage replaces its authored flat
colors with procedural cabin finishes (`carriage_finish.gdshader`): ribbed
floor, ivory enamel panels, teal glazed headers, woven seats, brass fittings,
brushed stainless poles and a lit perforated ceiling.
Lift landings, platform lanes and doorways stay walkable.
Desert Transit text uses the bundled BioRhyme Medium font in the station 233 and
rail station 237 Blender masters, their shared DT pylon and runtime signs.
Runtime plaques such as BOARD AT OPEN DOORS, ELEVATOR, EXIT TO STREET, PLATFORM
LEVEL and STREET LEVEL, and the carriage's DESERT TRANSIT headers, have opaque
ivory plates in brass surrounds, mounted on the actual wall or equipment.
Wayfinding arrows are drawn on their plates as geometry because the font does
not supply arrow glyphs. Font source and notices are recorded in
[station typography](../art/station-typography.md).

## Stations

Subway stations have a butterfly-roof Vegas pavilion with fluted limestone piers
and brass framing, and a freestanding DT pylon on the forecourt. Station 233 is an
editable Blender master; its static display cabin is swapped for the working
elevator only inside prepared Explore stations. Rail station 237 is the Desert
Transit rail hall: a glazed ticket hall with fluted sandstone piers under a
butterfly roof, a teal platform canopy on slender brass columns, a RAIL STATION
and DESERT TRANSIT name fascia and the same DT pylon. The underground room is
one continuous shell with hollow cuts where tubes enter; each tube's side walls
start at the room's inner wall face and line the cut, and its roof starts past
the room's soffit, so the two never overlap or share a plane. Elevator access
passages overlap the rooms and are clipped to their interiors, so straight,
graded and diagonal joins all close cleanly. Platforms have slender brass
balustrades with a continuous collision barrier and an open boarding gap.
Running track has procedural crushed stone and timber finishes, fastening plates
and shaped rails, all sharing one material along the prepared route.

Trains have windowed sliding doors. The rider's view turns with the cabin while
still allowing mouse orbit. Passenger status shows the current and next stop, the
door state and the departure countdown, and asks a passenger standing in the
doorway to move. Destination changes take effect immediately while the Explore
panel is open; an occupied train or elevator keeps its destination control
disabled.

## Menus

The menu bar is City, Speed, View, Reports, Disasters and Help. **City →
Settings…** holds display and graphics preferences. View groups Zoom, Data
Overlays and Show. Automatic budgeting is in Reports → Budget. Disasters keeps
the on/off switch separate from the submenu that starts an event.

## Performance

Traffic has a real rendering and CPU cost, and the population limits above keep
it bounded rather than free. The first entry into Explore on a large city still
takes a few seconds. See the [performance notes](performance.md).
