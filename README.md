# Rockhopper

A spike for a first-person, Deep Rock-shaped game about short missions
on asteroids, with less combat and more automation. It tests one
question: does "the dark is coming and I didn't build enough lights"
feel tense on its own?

You drop onto a small, turning asteroid. The pod lands just after
sunrise. The sun circles the rock every four minutes, so the line
between day and night crawls over the surface; one pole never sees
night, the other never sees day. Ore sits out on the surface, some of it
on the night side; the caves are there to explore and shelter in.
There's loose ore you can pick up, and a few big deposits that never
run out.

Power is one battery, shared by everything. Sunlight fills it, falling
on the top of the pod or on panels you build (a panel makes more the
more squarely it faces the sun). Lamps drain it, and they light
themselves whenever the sun's off them, even in daytime in a cave. When
the battery's flat they go out.

Your suit stays warm in light: sun, a lit lamp you can see, or beside
the pod while there's power. In the dark it cools, and in 45 seconds
you freeze. The headlamp lets you see but doesn't keep you warm. On a
rock this small and lumpy, high ground sees the sun well after the
valleys have lost it.

Ore is banked in the pod. What you carry counts once you hand it in.
Lamps (1), panels (2) and bots (4) are paid for from the bank, and
picking a lamp or panel back up refunds it. What's in the bank when the
pod launches, after twelve minutes, is the score (the quota is 100). Be
beside the pod then, or be left behind.

You start with two bots, and can print more. Mark a deposit and they fly
out to it, mine while it's lit (by the sun or a lamp), and fly the ore
home two at a time. If several deposits are marked, they spread across
them. In the dark they hover and wait.

In the dark, spiders climb out of the rock wherever no light falls: more
of them, and more often, as the mission goes on. They go for whatever's
nearest of you, a bot out working, a lamp or a panel. Bots and buildings
they destroy are gone. Sunlight sends them back under. Your health comes
back once nothing's hurt you for a few seconds.

## Controls

- **Move:** mouse looks, WASD walks, Shift runs. Space jumps; hold it
  in the air for the jetpack, which refills on the ground.
- **Fire:** left mouse, held, when no lamp or panel's in hand.
- **Use (E):** tap at the pod to hand in what you carry; hold on ore or
  a deposit to mine it, or on a lamp or panel to pick it up.
- **Mark (Q):** look at a deposit, from up to 45 m away, to mark it for
  the bots, or unmark it.
- **Build:** 1 picks a lamp, 2 a panel (again to put it away), then
  left-click the rock. Right-click puts the tool away. 3 prints a bot
  at the pod.
- **F** toggles the headlamp. **Esc** frees the mouse; click to take it
  back.
- **R** after a mission: a new asteroid. **Shift+R:** the same one.

The sunset/sunrise clock and the strip under it look along where the sun
will be from where you stand, so they allow for the terrain round you.

## Tuning

Mission, power, health and spider numbers are constants at the top of
`game/game.gd`. The day's length and the sun's tilt are in
`world/sun.gd`. The rock's size, lumpiness and tunnels are in
`world/asteroid.gd`. Movement and the gun are in `player/player.gd`,
bots in `world/bot.gd`, and spiders in `world/spider.gd`.

## Debugging

User arguments after `--`, e.g.
`Godot --path . -- --seed=1 --time=200 --lamps=2`:

- `seed=N`: the asteroid.
- `time=S`: start S seconds in (the pod still lands at t=0's sunrise,
  so `time=200` starts you at night).
- `view=orbit` looks at the whole rock; `view=cave` stands you in a
  chamber beside some ore.
- `lamps=N` builds N lamps around you.
- `mark` marks the deposit nearest the pod and stands you beside it.
- `spiders=N` brings N spiders up in front of you.
- `tool=lamp` or `tool=panel` starts with it in hand.
- `pitch=D` tilts your view by D degrees.
- `shot=path.png` saves a screenshot after `shot_at` seconds (default
  3), then quits.

## Layout

- `world/asteroid.gd`: the rock, a signed distance field with craters,
  chambers, tunnels between them and to the surface, and noise
  "spaghetti" tunnels, meshed once by surface nets into chunks with
  trimesh colliders. No deformation.
- `world/sun.gd`, `world/space.gdshader`: the circling sun and the sky.
- `world/fixture.gd`: the pod, ore, deposits, lamps and panels.
- `world/bot.gd`: mining drones.
- `world/spider.gd`: the spiders.
- `player/player.gd`: walking on a rock whose down is its centre.
- `game/game.gd`: the mission, power, warmth, building.
- `ui/hud.gd`: readouts.
- `tests/smoke.gd`: headless,
  `Godot --headless --fixed-fps 60 --path . -s tests/smoke.gd`. It plays
  a minute of bots mining by day, then half a minute of night.
