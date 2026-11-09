# Explore starting locations and the Mayor’s House

Explore starts on foot. Without a Mayor’s House, the player starts on safe outdoor pavement nearest the center of the active Build viewport. Moving the Build camera changes that starting point. No car or helicopter is automatically placed beside a street start.

A city with a Mayor’s House offers Current View, Mayor’s House and Cancel before loading Explore. Current View uses the same street start near the active Build viewport’s center. The house start is on the ground-level path by the motor court. Either starting location provides the same Desert Cruiser, police cruiser, fire engine and helicopter at the house; walk to a vehicle to enter it. They stay where they are driven during that visit and are released when Explore ends. They do not become simulation vehicles or change the saved city. Imported duplicate houses use the one nearest the map center, with row/column order breaking ties.

The existing two-tile-square house has a cream exterior, red roof and porch above an open motor court. Three parking bays and a painted helipad lie at lot grade. The front follows the same adjacent-street selection as casinos. Models, parking, the pedestrian start and the small permitted driving area share that facing, including after nearby road edits.

The motor court is an Explore-only exception to normal road driving, bounded to this lot and its actual front road. It creates no graph edges or traffic destinations. Ground support, water and physical collision checks still apply. Cars can leave and return through the open front; the helicopter has clear vertical takeoff space. An obstructed parking slot is omitted with feedback rather than moving its vehicle elsewhere. A blocked house walking start falls back to a street near the active Build viewport’s center. A house without an adjacent ground-level road explains the missing connection and still permits a safe house start.

Parked actors do not run driving updates. The helicopter’s rotor clock stops after wind-down, and the native renderer distance-culls the house fleet. Build mode shows the revised house, paving and painted markings without creating this vehicle fleet.

Layout coordinates live in `game/assets/desert-dreams-3d/mayors-house.json`, in model meters. `tools/build_mayors_house.py` revises only code 243 and retains its original locally. The editable Blender master is retained locally. The revised model uses the original material/texture sets, with cream stone and painted lines identified as non-emissive finishes, and stays below its former triangle budget.

The two side garden beds each hold three anchor points for the existing global vegetation system. Palms, woodland juniper/piñon and forest pine/fir follow the city’s elevation settings; no fixed shrubs or extra vegetation system are baked into the model. The editable master includes the same six named planting markers.
