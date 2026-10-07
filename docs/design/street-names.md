# Street names

In a founded city, return to Build and choose **View → Street Names**. Click or
tap a road segment to select it; select more segments to give them one identity,
even when they are disconnected. Bends, road bridges and complete tunnels remain
part of their connected segment. At an ambiguous junction, choose an approach
in the panel. Pan, zoom and rotate normally.

Enter a name and press **Apply** (or Return in the name field). Naming is free. Names accept up to 48 Unicode
characters; extra whitespace is normalized. Apply commits the selected connections
and keeps them selected. Existing matching names reuse their identity and spelling.
**Select entire named street** makes a whole-street rename explicit; **Remove name**
affects only the selected connections. **Clear selection** clears the draft.
**Done** applies a valid name typed for the selection but not yet applied, then
returns to the previous view and tool; if that name cannot be applied the panel
stays open with the reason. Leaving any other way discards unapplied text.
The panel counts the selection as road segments and, with nothing selected,
says "Click or tap a road to select it."
Applied names travel with native saves and recovery copies.

Explore places original teal and ivory street blades at actual named junctions
and destination boards at usable outward highway ramps. Exit destinations follow
the connected ordinary road, stopping at the first named connector or junction.
Signs require actual supported, clear space; exceptional unsafe locations may
remain unplaced. Street labels follow the existing label visibility option.

Rail and subway stations use nearby accessible street or intersection names.
Palms, rubble and small parks do not block that access; water, highways,
steep grades and buildings do. Names update when a station is placed and
whenever a nearby street is named or renamed.
Generated duplicates receive stable numeric suffixes shared by both station types.
Inspect, entrances, platforms, destination pickers and transit messages use the same
name. To customize a station, choose **Rename** in its inspector. A custom name
takes precedence; clearing it returns to automatic naming. Whole-street renames
update automatic names without moving a passenger or restarting a train or lift.

Names belong to structural road connections. Removing a connection removes its
assignment; newly built extensions start unnamed. If the city changes while an
edit is pending, retry the selection. Simulation is held while Street Names is
open, and the selected speed is restored when its hold ends.
