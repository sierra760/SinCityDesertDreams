# Explore road tunnels

Road tunnels are continuous enclosed roads in Explore. Walk through either portal,
choose a road vehicle outside and drive through, or stop and leave the vehicle
inside where physical clearance permits. Underground travel uses an eye camera;
the ordinary third-person view and vehicle model return outside.

The asphalt, width, shoulders, aggregate texture and yellow dashed centers use the
same procedural road drawing code as outdoor roads. Concrete sidewalls, a blue-gray
roof and a shared shadowless interior fill enclose the road. Walls and ceilings
use procedural concrete grain, small pores, mild mottling and quiet formwork joints.
The texture follows world coordinates at the Explore scale, continuing across
cells and region boundaries; fine detail fades at distance. The warm wall and
blue-gray ceiling colors stay distinct. The fill affects only tunnel surfaces
and does not contribute to the desert sky.

A read-only projection checks for matching mouths at both ends and an unbroken
run of buried road, in both imported `.sc2` cities and native cities. It includes the smallest two-cell bore.
The deck joins the actual outer road heights, interpolating between them. Invalid
or broken spans keep closed entrance recesses. City edits rebuild every affected
bore region, including distant mouths and terrain cutouts.

Finite terrain cutouts preserve construction picking, the hill above the tunnel,
surface roads above it and water above a covered bore. Inside the physical shell,
a road beneath water stays dry. Tunnels do not change ambient traffic routing,
the city simulation, random numbers or save files.
