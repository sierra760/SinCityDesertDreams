# Explore sky

Explore uses a procedural clear daytime Nevada sky: blue overhead,
pale warm haze at the horizon, a sandstone lower hemisphere, and a small soft
sun aligned with the city's existing directional light. The horizon colors meet
without a hard equator seam. The sky has no time or simulation dependency.

The editable Godot resource is
`game/assets/environment/desert_day_sky.tres`. It uses
[ProceduralSkyMaterial](https://docs.godotengine.org/en/4.6/classes/class_proceduralskymaterial.html)
and requires no bitmap panorama, external art service or additional geometry.
The 32-pixel radiance allocation and incremental processing keep the unused
radiance resource small; the background itself renders at the selected 3D
resolution.

`CityView3D.set_exploration_camera` copies the aerial environment onto the
perspective camera and attaches the shared sky. Ambient color still comes from
the render-quality setting; sky ambient and reflection lighting are disabled
for this camera, so the scene's lights, shadows and materials look the same as
in Build. Quality changes update the camera's ambient energy along with the
world environment.

A shadowless child directional light uses
[Godot's sky-only mode](https://docs.godotengine.org/en/4.6/classes/class_directionallight3d.html#class-directionallight3d-property-sky-mode)
to provide a warm bright visible sun. Its parent keeps the normal direct
lighting energy and supplies the direction. This keeps the lower-energy
Compatibility renderer from drawing a dark sun without relighting the city.

Suspension, walking, driving, flight and interior views share that camera
environment. Solid roofs and walls naturally occlude the sky. Returning to Build
releases the camera override, and the aerial background goes back to its flat
color. The sky adds nothing to city data, random streams, save files or display
preferences.

Tests: `test_main_exploration.gd`, `test_explore_view_owner.gd`,
`test_render_quality.gd` and `test_city_3d_view.gd`.
