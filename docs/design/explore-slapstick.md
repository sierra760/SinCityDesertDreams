# Explore slapstick weapons

On foot in Explore, the player can carry one of three toy weapons and bop the
ambient crowd. Nobody is hurt: a struck pedestrian pops apart at the joints,
its pieces bounce and twitch on the ground, and about fifteen seconds later
they hop back together with a boing and the person walks on from the same spot.
This works outdoors and on the floor of every gaming establishment (the casino
resorts and Despicable's), where the visitors can be popped too.

## Weapons

| Weapon | How it works |
| --- | --- |
| Rubber Chicken | Close swing across the front. Catches up to three people within about 2 m inside the swing. |
| Custard Pie | Thrown overhand on an arc (about 9 m on flat ground). Pops the first person it reaches, splats on anything else. |
| Foam Mallet | Slow overhead slam. Pops everyone within about 3 m of where it lands and launches the pieces high. |

Switching cycles Rubber Chicken → Custard Pie → Foam Mallet → empty hands.
Explore starts empty-handed. A swing aims along the camera heading and turns
the walker to face it.

Controls: **X** swings and **Z** switches (both rebindable under Options →
Controls; older saved key layouts get free keys instead of being reset). With
the mouse captured, a left click swings and the wheel switches. Touch walking
adds **Attack** (right above Interact) and **Weapon** buttons. Weapons are put
away while driving or flying.

## Holding and swinging

Every player character is rigged: Woman and Man, and the sixteen crowd
characters, which use the same animated model the street crowd shows up close.
The weapon is placed in the right hand bone every tick, after the walk animation, and the right arm holds a
carry pose while the rest of the body keeps walking: the chicken dangles by
its feet, the pie is held out level like a tray, the mallet rests over the
shoulder with its barrel behind. Each swing is a short keyframed arm motion
(`ExploreWeapons.SWINGS`: shoulder raise, sweep, elbow and wrist), so the arm
does the work: a flat swat across the front, a pull-back and shove for the
pie with the arm following through after release, and an overhead slam. The
body stays turned toward the aim for the whole swing, even while walking.

A model without that rig (a crowd variant missing its detail model) falls back
to its single crowd mesh: the weapon stays at the right hand, sways with the
stride its gait shader draws, and turns about the hand during a swing.

## Vehicles

The player's car, other selected vehicles and a low helicopter pop any ambient
pedestrian they run into at 0.15 tiles per second (about 9 km/h) or faster,
throwing the pieces ahead along the direction of travel. Explore checks this
before it places the traffic bodies for the tick, looking one and a half ticks
of travel ahead, so the pedestrian loses their body before contact and the
vehicle carries straight on. Slower, a pedestrian is just a solid body that
stops the vehicle, as before. Walking into someone never pops them.

## Pieces and reassembly

`ExploreLimbKit` splits each crowd variant's authored detail model once into
head, torso, two arms and two legs, by the bone with the most influence on each
triangle, in the standing rest pose. Variants without a detail model split the
low crowd mesh by height and width. Pieces are shared per variant.

A struck pedestrian is held out of the crowd by `CityTraffic3D.knock_pedestrian`:
it stops where it stands, is not drawn whole and has no collision body. Its
pieces fly with a push away from the hit, tumble, bounce off city surfaces and
come to rest; resting pieces wriggle now and then. After 15–17 seconds of
active Explore time the pieces fly home over about a second, the body squashes
and stretches, and `restore_pedestrian` returns the record to the crowd at the
same cell and progress.

## Casino floors

Inside a gaming establishment the weapons also reach the hall's visitors.
The occupied hall's patron crowd (`casino_patron_crowd.gd`) answers the same
calls as the street crowd (`pedestrian_targets`, `knock_pedestrian`,
`is_knocked`, `knocked_pose`, `restore_pedestrian`), and Explore hands it to
`ExploreMayhem.indoor` each tick (`ExploreResortService.patrons_inside`, null
outdoors and while a door fades). A popped visitor is hidden and stands still,
keeping its game and seat; other visitors walk past its spot. Its pieces land
on the hall floor and furniture and are drawn on the hall's light layer. When
the walker leaves the hall, anyone still in pieces there is put back at once.
A visitor who leaves because attendance falls simply takes its pieces with it.
Pies and pieces stop only after falling a tile below where they started, since
halls lie below ground.

At most ten people are in pieces at once; striking an eleventh reassembles the
oldest early. Leaving Explore puts everyone back immediately. Pedestrians
scripted by an Explore mod are never struck. Street pedestrians and casino
visitors share the ten-person limit.

## Boundaries

Everything here is presentation. City simulation, traffic routes and admission,
saves and the city RNG are untouched; the pieces use their own random stream.
Clocks advance only on active Explore physics ticks, so pausing Explore pauses
the mayhem. The pop, squawk, splat, bonk, boing and swing sounds are synthesized
at first use (`ExploreMayhemSounds`) and play through `GameAudio.play_stream` on
the Effects bus, so the player's sound settings apply.

Code: `game/scripts/exploration/mayhem/`. Tests: `game/tests/test_explore_mayhem.gd`,
and the casino floor in `game/tests/test_resort_interiors.gd`.
