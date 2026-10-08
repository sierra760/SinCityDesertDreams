# Ports: airports, seaports and military bases

System key: `ports` (`game/scripts/sim/port_system.gd`).
Parameters: `game/scripts/sim/data/port_params.gd` (`PortParams`).

## Purpose

The player zones airport and seaport land; the nation zones a military base
when the city accepts one. None of these zones is built by hand. The port
system develops each zone on its own into runways, terminals, piers, cranes,
hangars and the rest, decides when a port is large and equipped enough to
operate, and flies the planes, helicopter and ships that show the city is
connected to the outside world. Every crane also raises the city's industrial
demand cap.

## Inputs

- Layer `zone` – tiles of kind `Zones.AIRPORT`, `Zones.SEAPORT` and
  `Zones.MILITARY`. Tiles of one kind that touch (4-neighbors) form one port.
- Layer `building` – what already stands on each port tile.
- Layer `flags` – `POWERED` on a port tile or one of its 4-neighbors lets
  that tile develop.
- Layers `terrain`, `altitude` – water for piers and ship routes, ground and
  water heights for the berth depth.
- The `rewards` system's `military_kind()` – which set of pieces a military
  zone grows.
- Layer `building` again for the helicopter's idea of the city center: the
  centroid of all residential, commercial and industrial buildings.

## Outputs

- Layer `building` and `zone` corner flags: pieces are stamped with
  `City.stamp_building`, keeping the zone kind. Piers are stamped on the water
  tiles beside a crane and take the seaport zone kind.
- `ctx.events.mark_dirty` for every changed footprint.
- `vehicles()` for the renderer.
- `demand_bonus()` and `jobs()` for the zone system's monthly demand, and
  `jobs()` for the population system's job count. `port_report()` totals each
  port's jobs, pollution and crime.

Events:

| Call | Kind | Args |
|---|---|---|
| `report` | `port_opened` | `{kind, x, y}` the first time a port operates. A port that grows keeps its identity while it overlaps the tiles it had when last reported, so zoning more land does not reopen it |
| `report` | `port_closed` | `{kind, x, y}` when an operating port stops (unpowered or its runway or piers are gone) |

## Timing

- **Daily**: vehicles move one step; new vehicles may appear at operating
  ports; vehicles whose port stopped operating are removed.
- **Monthly, day 25**: ports are re-enumerated and every port tile gets a
  development chance; the city center used by the helicopter is refreshed.
- **On `networks_changed`**: the port list is rebuilt on the next query.

## Rules

1. **Ports.** A port is a connected group of zone tiles of one kind. Its
   pieces are counted from the building layer inside the group (piers on the
   water next to a crane belong to the seaport that placed them).
2. **Development chance.** On day 25 every tile of every port is visited in
   map order. A tile develops with probability `1 / DEVELOP_CHANCE_DENOMINATOR`.
   Airport and seaport tiles develop only when powered (the tile or a
   4-neighbor carries `POWERED`); military tiles never need power.
3. **Choosing a piece.** The piece to try is chosen from the port's counts so
   that support buildings appear in proportion to runways or piers:
   - *Airport*: `runways` = runway tiles (plain and crossing) / `RUNWAY_LENGTH`.
     If parking lots / 4 ≥ runways: a runway. Else the first of: control tower
     while runways > 2 × towers; radar while runways > 2 × radars; tarmac while
     runways > tarmac; terminal A while runways > terminals A / 2; terminal B
     likewise; large hangar while runways > large hangars / 4; otherwise a
     parking lot. A failed attempt falls back to a small hangar.
   - *Seaport*: `cranes` = crane tiles. If cargo yards / 4 ≥ cranes: a crane
     with its pier. Else a loading bay while cranes > loading bays / 4, a
     freight warehouse while cranes > warehouses / 3, otherwise a cargo yard. A
     failed attempt falls back to a warehouse.
   - *Air base*: like an airport with military pieces: motor pool instead of
     parking lot, military control tower instead of control tower, parked jets
     while runways > jets; terminals, radar and large hangars as the airport.
     Fallback: small hangar.
   - *Army base*: a motor pool while motor pools / 4 ≤ small hangars / 12,
     otherwise a small hangar.
   - *Naval base*: like a seaport with a restricted facility in place of the
     loading bay. Fallback: warehouse.
   - *Missile base*: a missile silo on every attempt.
4. **Placing pieces.**
   - A 1×1 piece needs an empty tile (nothing, rubble or trees).
   - A 2×2 or 3×3 piece is anchored at the visited tile; every tile of the
     footprint must be in the same port and be empty or hold a 1×1 support
     piece, which is replaced. Runways, crossings, cranes and piers are never
     replaced.
   - A runway is `RUNWAY_LENGTH` tiles in a straight line from the visited
     tile, entirely inside the port. Its direction alternates between east–west
     and north–south with each runway the port gains; the other direction is
     tried when the first does not fit. Tiles on the line must be empty,
     already runway, or support pieces, which are cleared (whole footprints at
     a time); cranes and piers are never crossed. Where the new runway meets an
     existing runway of the other direction the tile becomes a runway
     crossing; existing runway tiles do not count toward the length. Orientation is not stored: a runway tile runs
     east–west when it has a runway neighbor east or west.
   - A crane needs an empty land tile whose first 4-neighbor in south, east,
     north, west order is open water, with `PIER_LENGTH + 1` open-water tiles
     free of buildings in that direction and a berth at the far tile whose
     water is at least `MIN_BERTH_DEPTH` above its ground. The crane goes on
     the land tile and `PIER_LENGTH` pier tiles on the water.
5. **Operating.** An airport operates when it is powered, has at least
   `AIRPORT_MIN_TILES` tiles and at least one runway. A seaport operates when
   powered with at least `SEAPORT_MIN_TILES` tiles and at least one crane. A
   military base operates as soon as it has any piece.
6. **Demand.** The zone system counts every crane on the map, whether or not
   its seaport operates, toward the industrial demand cap (see zones.md).
   `demand_bonus()` adds, for each operating airport,
   `AIRPORT_COMMERCIAL_BONUS + developed tiles × BONUS_PER_DEVELOPED_TILE` to
   commercial and, for each operating seaport, `SEAPORT_INDUSTRIAL_BONUS +
   developed tiles × BONUS_PER_DEVELOPED_TILE` to industrial, each capped at
   `DEMAND_BONUS_CAP`. The zone system adds it to that month's demand change.
   Military bases add no demand bonus.
7. **Jobs.** `jobs()` is developed tiles × `JOBS_PER_TILE[zone kind]`,
   counting airports, seaports and military bases whether or not they
   operate. The population system adds it to `stats.jobs`, and the zone system
   adds `jobs() / PEOPLE_PER_UNIT` to the jobs term of the residential target,
   so ports and bases draw residents.
8. **Pollution and crime.** Every developed port or military piece emits
   `POLLUTION_PER_TILE[zone kind]` and adds `CRIME_PER_TILE[zone kind]` to its
   block's base crime; the environment system applies both in its tile pass
   (see environment.md). `port_report()` lists each port's totals
   (developed tiles × the same figures) with its bounding rectangle.
9. **Planes.** An operating airport with fewer than `MAX_PLANES` planes in the
   air spawns one with probability `1 / PLANE_SPAWN_DENOMINATOR` per day, on a
   runway tile, heading along the runway. A plane climbs for `PLANE_CLIMB_DAYS`
   (its `altitude` rises to `PLANE_CRUISE_ALTITUDE`), cruises for
   `PLANE_CRUISE_DAYS` changing heading one step with probability
   `1 / PLANE_TURN_DENOMINATOR` per day and turning away from any arcology
   within `AIR_LOOKAHEAD` tiles ahead, then flies back toward the nearest
   operating airport's runway, descends and disappears on arrival. A plane
   that reaches the map edge turns back toward the city center; one that
   finishes cruising with no operating airport left leaves the map, as the
   helicopter does. Planes move
   `PLANE_SPEED` tiles per day.
10. **Helicopter.** An operating airport spawns the city's single helicopter
    with probability `1 / HELICOPTER_SPAWN_DENOMINATOR` per day. It turns
    straight toward its target and flies `HELICOPTER_SPEED` tiles per day
    toward a random tile within `HELICOPTER_RANGE` of the city center, picks a
    new target on arrival, and never targets a tile off the map. It is removed
    when no airport operates.
11. **Ships.** An operating seaport spawns a ship with probability
    `1 / SHIP_SPAWN_DENOMINATOR` per day when no ship is present. The ship
    needs a route over open water free of buildings (bridge spans excepted)
    from a map-edge water tile to the berth beyond the port's first crane; if no
    route exists no ship comes. It sails `SHIP_SPEED` tiles per day along the
    route, waits `SHIP_DOCK_DAYS` at the berth, sails back and leaves the map.
    Ships never leave the water.
12. **Frames.** Every vehicle carries `heading` 0–7 (0 north, clockwise) and a
    `frame` counter that advances each day for the renderer's animation.

## Parameters

| Name | Meaning |
|---|---|
| `DEVELOP_CHANCE_DENOMINATOR` | one in this many visited tiles tries to develop each month |
| `RUNWAY_LENGTH` | tiles per runway |
| `PIER_LENGTH` | pier tiles beyond a crane |
| `MIN_BERTH_DEPTH` | water height above ground required at the berth |
| `AIRPORT_MIN_TILES`, `SEAPORT_MIN_TILES` | smallest zone that can operate |
| `AIRPORT_COMMERCIAL_BONUS`, `SEAPORT_INDUSTRIAL_BONUS`, `BONUS_PER_DEVELOPED_TILE`, `DEMAND_BONUS_CAP` | the monthly demand boost of operating ports |
| `JOBS_PER_TILE`, `POLLUTION_PER_TILE`, `CRIME_PER_TILE` | per developed tile, keyed by zone kind, for `jobs()` (read by zones and population) and `port_report()`; pollution and crime are applied per piece by the environment system |
| `MAX_PLANES`, `PLANE_SPAWN_DENOMINATOR`, `PLANE_SPEED`, `PLANE_CLIMB_DAYS`, `PLANE_CRUISE_DAYS`, `PLANE_CRUISE_ALTITUDE`, `PLANE_TURN_DENOMINATOR`, `AIR_LOOKAHEAD` | plane life cycle |
| `HELICOPTER_SPAWN_DENOMINATOR`, `HELICOPTER_SPEED`, `HELICOPTER_RANGE` | helicopter life cycle |
| `SHIP_SPAWN_DENOMINATOR`, `SHIP_SPEED`, `SHIP_DOCK_DAYS` | ship life cycle |

## Save state

`save()` returns the vehicle list (kind, position, heading, frame, phase,
altitude, target, route and route index, the port anchor), the set of ports
that have been reported open, and the city center. `load()` restores it; ports
themselves are re-read from the map.

## Public interface

```
vehicles() -> Array[Dictionary]     # {kind, x, y, heading, frame, altitude}
demand_bonus() -> Vector3i          # residential, commercial, industrial
jobs() -> int
port_report() -> Array[Dictionary]  # {kind, rect, tiles, developed, powered, operating, runways, cranes, jobs, pollution, crime}
```
