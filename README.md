# Rockhopper

A spike for a first-person game shaped like Deep Rock Galactic, but with
less combat and more automation: short missions on asteroids, where the
dark is the enemy. It tests whether night coming round, with too few
lamps built, is tense on its own, and how drilling, hauling and the
spiders that come with the dark sit alongside it.

You drop onto a small, turning asteroid, about 130 m across. The pod
lands just after sunrise, on the flat floor of a shallow impact crater,
with room to set up. The sun circles the rock every five minutes, so
the line between day and night crawls over the surface; one pole never
sees night, the other never sees day. On a rock this lumpy, high ground
keeps the sun well past where a smooth horizon would set it. There's
loose ore lying about, big deposits that never run out, craters, and a
few chambers inside, reached by tunnels from the surface.

Power is one battery, shared by everything. Sunlight fills it, falling
on the top of the pod or on panels you build (a panel makes more the
more squarely it faces the sun). Lamps drain it, and they light
themselves whenever the sun's off them. When the battery's flat they go
out. It holds 100, and each battery bank you build adds 80.

Your suit stays warm in light: sun, a lit lamp you can see, or beside
the pod while there's power. In the dark it cools, and in 45 seconds
you freeze. The headlamp lets you see, but doesn't keep you warm.

Ore is banked in the pod. What you carry counts once you hand it in.
Lamps (1 ore), panels (2), batteries (2), drill rigs (3), research labs
(4) and rovers (4, printed from the pod's screen) are paid for from the
bank, as is research, and picking something back up refunds it. What's in the
bank when the pod launches, after twelve minutes, is the score (the
quota is 100). Be beside the pod then, or be left behind.

A drill rig goes over a deposit. It drills while it's lit, by the sun or
a lamp, into a hopper of 12. You start with one rover, and can print
more at the pod. A rover waits by the pod until a rig has a load worth
the trip. Then it drives out, empties the hopper and drives the ore home,
spreading itself over the rigs with the most waiting. Rovers can't
climb steep slopes, so a deposit in a crater or over a ridge is a
longer drive, or one they can't make at all. You can also empty a
hopper by hand.

A research lab works through upgrades for this mission, one at a time,
picked on its screen: each costs ore, takes 30-45 s, and draws power
while it works (it stalls when the battery's flat). Pressing the one in
progress cancels it and refunds the ore. Researched upgrades apply to
everything, already built or not:

- Blade runners: walk 5 and run 8.5, from 3.5 and 6.
- Jetpack: hold Space in the air to fly.
- Armour plating: +50 max health.
- Heated suit: the cold takes twice as long to freeze you.
- Bigger tanks (after the jetpack): it burns fuel 40% slower.
- Overcharged rounds: double damage, so one shot kills a spider.
- Stabiliser: half the bloom from firing, and tighter at rest.
- Faster drills: rigs drill 40% faster.
- Rover tuning: rovers drive 40% faster and carry 4 more.
- Efficient lamps: lamps draw half the power.

In the dark, spiders climb out of the ground wherever no light falls,
more of them and more often as the mission goes on. They go for the
nearest of you, a rover out on the road (their own headlights don't
help them), or anything you've built. What they destroy is gone.
Sunlight sends them back under. Your health comes back once nothing's
hurt you for a few seconds.

## Controls

- **Move:** mouse looks, WASD walks, Shift runs (slowly until you've
  researched blade runners). Space jumps; once you've researched the
  jetpack, hold it in the air to fly; it refills on the ground. C or Ctrl
  while running slides: a burst of speed, faster downhill, and a jump
  out of it keeps the momentum. Land with it held to slide on.
- **Weapons:** 1, 2 or the wheel switch between the gun and the hammer.
  The hammer smashes everything in a short arc in front, one-shotting
  spiders and knocking them flying, and chips ore off a deposit.
- **Grapple (G):** a spider gets yanked to you; anything else (rock, a
  building) pulls you to it for as long as you hold G, about 35 m.
- **Fire:** left mouse, held, when nothing's in hand. Shots land in a
  cone (the crosshair's ticks) that widens as you fire, move or jump, and
  settles back. Hold right mouse to aim down the sights: zoomed, much
  tighter, but slow on your feet.
- **Use (E):** tap at the pod to hand in what you carry, or at a rig to
  empty its hopper into your pockets. Hold on ore or a deposit to mine
  it, or on a lamp, panel or rig to pick it up.
- **Build:** hold Q for the radial menu, move the mouse towards a lamp,
  panel, battery, drill rig or research lab and let go of Q (or let go in the middle to put
  away what's in hand). Then left-click the ground, or for a rig, the
  deposit; right-click puts it away.
- **The pod's screen:** look at a button on it and press E, to print a
  rover (4 ore) or hand in what you carry. It also shows what's banked,
  the rovers, the battery and the launch clock.
- **A rover's screen** (on a stand at its back): HAUL is the usual, STAY
  stops it where it is, GO HOME drives it back to park, unloading what
  it carries, until you tell it to haul again. It also shows what the
  rover's doing, its cargo and its hull.
- **F** toggles the headlamp. **Esc** pauses (Resume, New map, Quit);
  Esc again resumes.
- **R** after a mission: a new asteroid. **Shift+R:** the same one.

The sunset/sunrise clock and the strip under it look along where the sun
will be from where you stand, so they allow for the terrain round you.

## Tuning

Mission, power, health and spider numbers are constants at the top of
`game/game.gd`. The day's length and the sun's path are in
`world/sun.gd`. The rock's size, lumpiness, craters and caves
are in `world/terrain.gd`. Rigs' drilling rate and hopper are in
`world/fixture.gd`. Movement and the gun are in `player/player.gd`,
rovers in `world/rover.gd`, and spiders in `world/spider.gd`.

## Debugging

User arguments after `--`, e.g.
`Godot --path . -- --seed=1 --time=200 --lamps=2`:

- `seed=N`: the asteroid.
- `time=S`: start S seconds in (the pod still lands at t=0's sunrise,
  so `time=200` starts you at night).
- `view=orbit` looks at the whole rock; `view=cave` stands
  you in a cave; `view=screen` in front of the pod's screen; `view=rover`
  behind the first rover.
- `rig` builds a rig on the deposit nearest the pod and stands you
  beside it.
- `lamps=N` builds N lamps around you.
- `spiders=N` brings N spiders up in front of you.
- `tool=lamp`, `tool=panel` or `tool=drill` starts with it in hand.
- `radial=N` holds the build menu up with item N chosen (-1 for none).
- `pitch=D` tilts your view by D degrees.
- `aim` holds aim down the sights; `pause` starts paused.
- `hammer` starts with the hammer out.
- `lab` builds a research lab ahead of you and starts it researching.
- `shot=path.png` saves a screenshot after `shot_at` seconds (default
  3), then quits.

## Layout

- `world/terrain.gd`: the asteroid, a signed distance field (a lumpy,
  stretched ball, craters, chambers and tunnels) meshed once by surface
  nets into chunks with trimesh colliders. The mesh's own vertices make
  the rovers' walkable graph (A*, gentle slopes only). No deformation.
- `world/sun.gd`, `world/space.gdshader`: the sun and the sky.
- `world/fixture.gd`: the pod, ore, deposits, lamps, panels and rigs.
- `world/screen.gd`, `world/screen.gdshader`: the screens on the pod and
  the rovers.
- `world/rover.gd`: the haulers.
- `world/spider.gd`: the spiders.
- `player/player.gd`: you.
- `game/game.gd`: the mission, power, warmth, building, the spiders'
  spawning.
- `ui/hud.gd`: readouts.
- `tests/smoke.gd`: headless,
  `Godot --headless --fixed-fps 60 --path . -s tests/smoke.gd`. It plays
  a minute and a half of a rig and a rover working by day, then half a
  minute of night.
