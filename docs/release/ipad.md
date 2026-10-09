# iPhone and iPad controls and device builds

The Godot 4.6.1 project includes touch input, iPad display and lifecycle
handling, and an **iOS** export preset. It has not yet been tested as a signed
build on a physical iPhone or iPad. See the [iPhone interface guide](iphone.md)
for the compact phone controls.

## Playing with touch

| Context | Action |
| --- | --- |
| Build | Choose a construction tool, then touch or drag the city. Its preview targets the tile under your finger. Lift to apply the highlighted action at the final contact. |
| Inspect | The pale outline follows the fingertip. Adjust your finger, then lift to inspect that tile. A stronger teal outline and faint fill mark the Inspect panel’s selected tile until you close it. With a mouse, hover shows the target and click selects it; right-click also inspects. |
| Locked tools | Tap a locked tool for its name and unlock requirement. Close details returns to the sidebar; the tool remains unavailable. |
| Pan and zoom | Put two fingers on the city. The second finger cancels a pending tool action; drag to pan and pinch to zoom. Lift both before starting another tool action. |
| Rotate and analyze | Use the View menu for rotation, zoom, underground view and data overlays. |
| Walk | Use the left movement pad; drag on the right to look. Hold Sprint or tap Jump. |
| Drive | Push the pad forward to accelerate, backward to brake/reverse and sideways to steer. Hold Brake to stop. |
| Fly | Use the movement pad for horizontal travel; hold Climb or Descend. Release controls to hover. |
| Interact | Tap Interact to call/ride a lift or enter/exit a nearby vehicle. Stop or land before exiting, and leave room to step out. Walk through open passenger-train doors. |
| Explore menu | Tap Menu for vehicle selection, destinations, Recover, Reset camera, Control settings and Return to Build. Drive selected vehicle starts driving at once; otherwise choose Resume to continue movement. |

Touch controls appear on iOS and detected touchscreens. Hardware keyboard and
mouse controls remain available. Touch Explore hides the minimap to reserve its
corner for action buttons; returning to Build restores the saved minimap choice.
Use **Settings → Controls** for camera sensitivity and invert Y. Its keyboard
assignments appear only when a hardware keyboard is attached; see the
[controls guide](controls.md) for changing keys and restoring defaults.
The Speed menu controls city time independently of walking/driving/flying. Held
actions show their pressed state; movement/look captions have contrasting backing.
Report numbers use separate minus, typed value and plus controls.

A touch that starts on a menu, toolbar or dialog stays with that control. A second
finger, interrupted gesture, modal, display change or focus loss cancels pending
construction. Held controls are cleared and must be released before reuse.
Changing orientation or the available display area suspends Explore; use Resume.

## Files, saves and leaving the app

Use **City → Close City** to leave the current city. **Don't Save** returns to
the title screen and preserves the last saved file; **Save** writes changes
before returning, and **Cancel** keeps the city open. The title screen has no
Quit button on iOS. Use the system's Home gesture to leave the application.

On iPad, the app's Documents folder is exposed through Files. Copy a `.sc2` or
`.sc2d` file you own into **Files → On My iPad → SC2D**.
Use **Import Classic City** for `.sc2`, or **Load City → Browse** for `.sc2d`.

Set your name in **Settings → General → Mayor**. It appears in the welcome and
new city saves. Loading a native city keeps its saved mayor credit; changing
your name while that city is open updates it.

Use **City → Share City** for a current copy, or **Load City → Share** for a
saved city. The Apple share sheet offers the apps available on your device,
such as Messages, Mail and AirDrop. The share copy is separate from the normal
save. If native sharing is unavailable, the copy is in the game's Files folder
under `shared-cities`. Recipients place `.sc2d` attachments in the game's Files
folder and open them with **Load City → Browse**. The arm64 sharing plugin is
bundled with iOS builds but has not yet been tried on a signed device.
Game Center's personal saved-game storage does not share city files with friends.

Godot 4.6.1 uses an app-folder picker on iOS; copying through Files supplies the
file before selection. Cloud providers remain usable through Files' copy action.
The folder label follows the installed app's display name.

Named cities live in `saves/`. Annual backups and `recovery/suspended.sc2d` are
separate. Leaving the app pauses city time and movement and attempts a verified
suspension recovery save. **Load City** lists it as **Recovery copy (saved when the app
went to the background)**. Loading it clears the manual save target; use **City → Save City
As** to keep a named copy. This does not replace a named save or the annual
backup. Unfounded maps keep their editing stage and generator settings. A
recovery-write failure is reported upon return.

Returning to the app leaves city time paused and Explore suspended. Resume city
time through Speed and movement through the Explore menu. Actor positions remain
session-only and are not added to the city save format. As with any mobile app,
a process killed before receiving its background notification cannot write a new
recovery; named saves and annual backups are the durable checkpoints.

## Display and graphics

Menu, footer, toolbar, touch controls and dialogs use the safe region. A docked
keyboard reduces the usable height and keeps dialog actions accessible. Interface
size remains adjustable in Settings. Mobile uses at least 100% point scaling,
including narrow windows, and larger content remains reachable through scrolling.
The desktop-only Fullscreen control is hidden on mobile. Both portrait and landscape rotations are
enabled. Mobile window restoration leaves sizing and window mode to the OS.

New mobile preferences start at **Balanced / 75%** 3D resolution; explicit saved
quality choices are preserved. Text is rendered at the interface resolution.
These defaults require measurement on the target iPad, especially in large cities
and during the first Explore entry.

Sound uses the iOS **Ambient** audio session with mixing on
(`audio/general/ios/mix_with_others=true` in `project.godot`): the game mixes
with the player's own music or podcast instead of stopping it, and like other
ambient game audio it is silenced by the Ring/Silent switch, music included.
Choose the Playback category instead if the soundtrack should play in silent
mode. This has not been checked on a device.

## Creating a device build

To make a device build, install matching Godot 4.6.1 export templates
and Xcode on macOS. Open `game/project.godot`, select **Project → Export → iOS**,
set your Apple Team ID, and verify the bundle identifier against that
account. The preset exports to `ios/SCDD.xcodeproj` beside `game/` and keeps
files from earlier exports there (`delete_old_export_files_unconditionally` is
off); to start clean, choose a new empty directory in the export dialog
instead. Open the Xcode project, configure development signing and select a
connected iPad. This follows the
[Godot iOS export workflow](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_ios.html).

The preset is arm64 and includes iPhone and iPad, permits all rotations and exposes Documents
through Files and sharing. Its deployment setting is iOS 17; Godot's Mobile
exporter also adds its A12 performance requirement, so that number alone is not
a supported-device promise. Verify the team and provisioning fields against your
account before exporting. The preset already includes the app icon and the
resource and license include filters. Official
[iOS export options](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformios.html)
describe the platform fields. Godot 4.6 currently does not support an iOS simulator
export; use a real device for acceptance.

Record the device model, iPadOS version and exact build hash. On that build,
verify touch construction/cancellation, simultaneous movement/look/actions,
portrait/landscape transitions, real safe insets, keyboard-open save dialogs,
Files import/export, background/relaunch recovery and hardware input. Floating
or undocked keyboards may not report an occluding rectangle through Godot's
height API and require device inspection. Measure representative city frame times,
entry stalls, memory and thermal behavior, and have people try the touch controls.
Desktop tests can't stand in for these device checks.
