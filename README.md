# Rockhopper

A spike for a first-person, Deep Rock-shaped game about short missions
on asteroids, with less combat and more automation. It tests one
question: does "the dark is coming and I didn't build enough lights"
feel tense on its own?

You drop onto a small, turning asteroid. The pod lands just after
sunrise. The sun circles the rock every four minutes, so the line
between day and night crawls over the surface; one pole never sees
night, the other never sees day. Ore sits in the caves, which the sun
never reaches, and in a few spots on the surface.

Power is one battery, shared by everything. Sunlight fills it, falling
on the top of the pod or on panels you build (a panel makes more the
more squarely it faces the sun). Lamps drain it, and they light
themselves whenever the sun's off them, even in daytime in a cave. When
the battery's flat they go out.

Your suit stays warm in light: sun, a lit lamp you can see, or beside
the pod while there's power. In the dark it cools, and in 45 seconds
you freeze. The headlamp lets you see but doesn't keep you warm.

Ore pays for lamps (1) and panels (2), and picking something back up
refunds it. What you hand in at the pod is the score. The pod launches
after twelve minutes: be beside it or be left behind.

## Controls

- **Move:** mouse looks, WASD walks, Shift runs. Space jumps; hold it
  in the air for the jetpack, which refills on the ground.
- **Use (E):** tap at the pod to hand in what you carry; hold on ore to
  mine it, or on a lamp or panel to pick it up.
- **Build:** 1 picks a lamp, 2 a panel (again to put it away), then
  left-click the rock. Right-click puts the tool away.
- **F** toggles the headlamp. **Esc** frees the mouse; click to take it
  back.
- **R** after a mission: a new asteroid. **Shift+R:** the same one.

The sunset/sunrise clock goes by the rock's centre, so on a crest or in
a crater the real thing comes a little early or late.

## Tuning

Mission and power numbers are constants at the top of `game/game.gd`;
the day's length and the sun's tilt are in `world/sun.gd`; the rock's
size, lumpiness and tunnels are in `world/asteroid.gd`; movement is in
`player/player.gd`.

## Debugging

User arguments after `--`, e.g.
`Godot --path . -- --seed=1 --time=200 --lamps=2`:

- `seed=N`: the asteroid.
- `time=S`: start S seconds in (the pod still lands at t=0's sunrise,
  so `time=200` starts you at night).
- `view=orbit` looks at the whole rock; `view=cave` stands you in a
  chamber beside some ore.
- `lamps=N` builds N lamps around you.
- `pitch=D` tilts your view by D degrees.
- `shot=path.png` saves a screenshot after `shot_at` seconds (default
  3), then quits.

## Layout

- `world/asteroid.gd`: the rock, a signed distance field with craters,
  chambers, tunnels between them and to the surface, and noise
  "spaghetti" tunnels, meshed once by surface nets into chunks with
  trimesh colliders. No deformation.
- `world/sun.gd`, `world/space.gdshader`: the circling sun and the sky.
- `world/fixture.gd`: the pod, ore, lamps and panels.
- `player/player.gd`: walking on a rock whose down is its centre.
- `game/game.gd`: the mission, power, warmth, building.
- `ui/hud.gd`: readouts.
- `tests/smoke.gd`: headless, `Godot --headless --path . -s tests/smoke.gd`.
