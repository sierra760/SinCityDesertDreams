# Zone colors

Zoning uses traditional U.S. planning land-use color families. Residential land
is yellow through ochre/brown, commercial land is salmon through deep red, and
industrial land is lavender through purple. Military land is muted pink;
airports and seaports use distinct transportation grays. The exact shades are
authored for the game's desert ground and ivory interface, rather than copied
from a particular jurisdiction's map.

| Zone | Color | Hex |
| --- | --- | --- |
| Light Residential | Yellow | `#f2cf57` |
| Dense Residential | Ochre/brown | `#b78538` |
| Light Commercial | Salmon red | `#e68a80` |
| Dense Commercial | Deep red | `#ba4548` |
| Light Industrial | Lavender | `#b99bd8` |
| Dense Industrial | Purple | `#8054a6` |
| Military | Muted pink | `#d99bae` |
| Airport | Light gray | `#acb2b8` |
| Seaport | Slate gray | `#747c84` |

`Zones` owns the palette. Bare zoned ground (including ground beneath standalone
power lines), the zoning overlay and legend, and both Build and Explore maps
derive their colors from it. Developed residential, commercial and industrial
map tiles retain their zone's density shade; buildings without matching zoning
fall back to the corresponding light shade. Transport symbols retain their
existing map colors, including roads through military land.

The SVG icon authoring tool reads the same literal hex constants from
`game/scripts/core/zones.gd`. Run `python3 tools/build_ui_icons.py` after changing
the palette. Icon shapes, outlines and text labels continue to identify the
tools alongside their colors. Demand meters use residential yellow, commercial
red and industrial purple. Residential/commercial/industrial graph series and
their demand histories use the darker family shades for legible lines against
the ivory plot; their colors remain stable when other series are selected.

The colors are a visual convention; zone IDs, city bytes, growth rules, costs,
and saved cities do not change.

References:

- [Traditional Color Coding for Land Uses, American Planning Association
  (1997 survey, archived copy)](https://gismanual.com/style/ColorConventions.pdf)
- [Maine comprehensive planning manual, land-use map table, printed page
  131](https://www.maine.gov/dacf/municipalplanning/docs/2005manual_highres.pdf)

These sources document conventions and local variations, not one universal
mandatory palette.
