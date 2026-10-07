# Subtle tile grid

The 3D game view shows faint warm-gray tile boundaries by default. They follow
the dry terrain and horizontal water surfaces in Build and Explore.
Buildings and network meshes naturally cover the ground beneath them; their
authored surfaces are unchanged. Vertical cliffs and waterfall walls have no
grid tint.

**City → Settings… → Graphics → Show tile grid** applies immediately and is
remembered between sessions. It is on by default. Turning the grid off shows
the plain surface colors.

The editable shader is `game/shaders/city_tile_grid_3d.gdshaderinc`. World-space
integer boundaries agree with the city tiles. Pixel derivatives soften line
edges and fade unresolved cells with distance, including perspective views.
The tint is part of the shared terrain material; it adds no meshes, collision
shapes, simulation state or city save fields.
