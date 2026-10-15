# Agricultural model and parcel rendering

The original farm palette and metre scale apply to both complete lots and generated parcels. Generated crop beds and irrigation pipes repeat their surface texture along clipped member spans. Plant canopies keep the finite source triangles and repeat as discrete groups; deterministic row and group spacing accounts for every visible copy within the 20,000-triangle parcel limit. Holes and equipment clearance clip both beds and plants.

Sheep boundaries use seven horizontal woven wires with vertical infill. A shared cattle/sheep boundary uses woven infill regardless of the physical owner's ID. Coplanar ownership, closed collision, livestock clearance and navigation remain independent of that visual style. Extreme concave perimeters use a deterministically wider infill pitch to retain the complete fence within budget. Sparse dry sage/grain tufts use the original pasture materials and only the remaining triangle allowance; they add no collision.

Shed details fit below the wall eave at every helper height, retaining the default shed proportions. Each front door has one diagonal brace. Coincident fence end timbers/caps are emitted once per authored lot, while the closed segment colliders remain complete. The closed 3m service gate has two end posts and a braced leaf with a central latch.

Selective source-model exports preserve all other model bytes and catalog records:

```sh
Blender --background --factory-startup --python tools/blender_exploration/build_agriculture.py -- --lots --only 268 279 280 281
Blender --background --factory-startup --python tools/blender_exploration/build_agriculture.py -- --parcel-kit --only farm_shed fence_gate
```

The lot exporter updates affected catalog/provenance and existing enclosure/resource identity hashes. Source masters remain local. `tools/check_agriculture_assets.py` and `tools/check_agriculture_parcels.py` inspect decoded geometry, embedded materials, supported shed details, coincident triangles and complete collision envelopes.
