# Rockhopper

Play it in a browser: https://play.devoncoleman.com/rockhopper/

A spike for a first-person game shaped like Deep Rock Galactic, but with
less combat and more automation: short missions on asteroids, where the
dark is the enemy. It tests whether night coming round, with too few
lamps built, is tense on its own, and how drilling, hauling and the
spiders that come with the dark sit alongside it.

Each mission starts in a lobby over the map it'll be played on, with
its deposits (and the ore each holds) and vents (and the power a tap on
each would make) already down: the leader (whoever's been connected
longest; you, solo) clicks where the pod should land, on level ground
with room round it, away from the wall, off the deposits and at least
35 m from any vent (rings show where), or rolls a new map; everyone else says they're ready, and the leader
drops the pod. It comes down out of the sky over 7 s, watched from
nearby, and everyone starts beside it. The leader's pause menu can send
everyone back to the lobby, on the same map, any time; a finished
mission goes back to it 15 s later on a new map.

You drop onto a turning asteroid, into a round patch of rolling hills,
rises and hollows 160 m across, marked out by a blue hologram wall you can't go past (it shows when
you're within about 18 m of it, and always from the pod); beyond it
the ground flattens out into a plain, ringed by mountains you can't
reach: walled in some ways, open others, different on every map, with
one giant somewhere. The pod lands mid-morning. The
rock turns every five minutes: three minutes of sun crossing the sky,
then two of night. Low in the sky, it throws the hills' shadows long, so the
hollows go dark first and the high ground holds the light longest. A
range to the west brings dusk early, its shadow sweeping in across the
floor; one to the east holds the dawn back. There's loose ore lying about, eight
big deposits spread out, each holding 30-70 ore (a deposit that's dug
out is spent), four vents, out from the middle, and a few caves under
the ground to shelter in. Craters are shallow bowls, never breaking into a cave.

Power is one battery, shared by everything. Sunlight fills it, falling
on the top of the pod or on panels you build (a panel makes more the
more squarely it faces the sun). At night the only power is from vents:
a geothermal tap (5 ore) built over one makes 1.4-2.8 a second (more
the further out the vent is), day and night, while strung cables tie it
back to the pod, through any number of pylons. A tap is loud, so
spiders come for it, and a cable cut anywhere on the line cuts the power.
Lamps (0.4 a second) drain the battery, as do the pod's lights (0.25)
and the small light on everything built (0.08 each), all lighting
themselves whenever the sun's off them. When the battery's flat they go
out. It holds 100, and each battery bank you build adds 80.

Your suit stays warm in light: sun, a lit lamp you can see, within 7 m
of a building's light, by a vent, or beside the pod while there's power. In the dark it cools, and in 45 seconds
you freeze. The headlamp lets you see, but doesn't keep you warm.

Ore is banked in the pod. What you carry counts once you hand it in.
Lamps (1 ore), pylons (1), barricades (1), panels (2), batteries (2 ore
and 1 alloy), drill rigs (3), research labs (4), armories (4), turrets
(4 ore and 2 alloy), foundries and taps (5) are paid for from the bank, as are
research and gear, and picking something back up refunds it.
Buildings are placed by the commander, from the pod, as blueprints:
glowing blue holograms, free to place, that do nothing until soldiers
hammer them up (2 blows for a lamp or pylon, 3 for a panel or battery, 5
for a rig or barricade, 6 for a lab, armory, foundry or turret). Each blow pays
its share of the cost
from the bank, the first blows first, and lands only if the bank can pay
it. Buildings stand upright on a concrete plinth sunk into the rock, on
ground up to 20° steep (35° for lamps and pylons). What's in the bank
when the pod launches is the score (the quota is 100 ore; alloy doesn't
count). The commander calls the launch, whenever they like: it lifts off
45 s later, and anyone not beside the pod then is left behind. Staying
on banks more, but every night is worse than the last. Calling it spools
the engines up, and the noise tears two bug holes open 16-30 m from the
pod (three with three players or more), day or night. Frenzied spiders
pour out of them, one every 1.4 s up to 6 at once (scaled up with more
players, like the night's), and go straight for the pod, sun or no sun,
unless you hurt them. Hold the pod till lift-off. Calling the launch off
closes those holes, but the spiders already out stay.

A drill rig goes over a deposit. It drills while it's lit, by the sun or
a lamp, into a hopper of 12, which you can empty by hand, till the
deposit's spent. Cables carry
it away. The commander lays the cables, free, from one pylon, rig, tap
or foundry to another or to the pod, up to 20 m, with clear air under it;
one run to a blueprint, or to open ground (which puts a pylon blueprint
there), waits as a hologram line and goes up once soldiers have built
both its ends. Ore and alloy travel along it one way at 3 m/s, 1.5
m apart. Rigs send ore, foundries send alloy, pylons pass on whatever
reaches them (holding 4), and the pod
takes everything into the bank. A
place with several cables out takes turns between them. When something
can't take any more, what's on the cable waits at the end.

A foundry smelts 2 ore into 1 alloy every 6 s, drawing 1 power a second
while it works, with bins of 10 for each. Alloy pays for batteries and
the bigger upgrades, batteries and turrets.

A turret shoots the nearest spider within 22 m that it can see, if the
spider's in light (sun, lamp or flare), a shot every 0.9 s, 10 damage
each. Each shot spends a round and 0.3 of the battery. It holds 40
rounds, and soldiers fill it: an ammo box from an armory's screen costs
2 ore, you carry one at a time, and E on a turret loads it, full. It's loud for 2 s after it fires, and a spider
it shoots comes for it. Spiders can't get past a barricade (a wall 3 m
long and 2 m high, 120 hull, set across the way to the pod); one that
walks into it chews through instead.

Soldiers ride cables: E while looking at one grabs it, and you slide
along underneath at 11 m/s, the way you're facing. E or Space lets go,
keeping your speed, and you drop off at the end.

The commander can switch anything built off and on, to save power at
night (off, it's dark too) or to quiet it. A rig that's drilling is loud, a
foundry that's smelting louder, and a lab at work a little; the pod hums.
Spiders hear them from further than they can see.

Research labs work through upgrades for this mission, laid out as a tech
tree in the command chair's research panel, the only place they're
picked or followed (labs have no screen). The commander queues them:
clicking one queues it, after whatever it needs that isn't done or
queued yet; clicking it again takes it off the queue (with what's queued
after it), or cancels it under way for a refund. Each idle lab takes the
first queued upgrade it can start: what it needs is done, and the bank
can pay. Each costs ore, the bigger ones alloy too, paid when a lab
starts it, takes 25-45 s, and draws power while it works (it stalls when
the battery's flat, or it's switched off). Researched upgrades apply to
everything, already built or not, except gear (marked *): that, once
researched, each soldier orders their own at an armory (see below).

- Rifle*: soldiers start with only the hammer.
  - Overcharged rounds: double damage, so two shots kill a spider, not
    three.
  - Stabiliser: half the bloom from firing, and tighter at rest.
- Blade runners*: walk 5 and run 8.5, from 3.5 and 6, and slide up to 16
  m/s, from 8; jumping out of a slide speeds you up, where without them
  you slow back towards running speed in the air.
  - Jetpack*: hold Space in the air to fly.
    - Bigger tanks: the jetpack burns fuel 40% slower.
  - Grapple*: middle mouse hooks what you're looking at (see Controls).
- Heated suit*: the cold takes twice as long to freeze you.
- Armour plating*: +50 max health.
- Faster drills: rigs drill 40% faster.
  - Fast cables: cables carry twice as fast.
- Efficient lamps: lamps draw half the power.

Armories make gear, one piece at a time. Soldiers order their own on the
screen on an armory's side: a button for each piece (once the
commander's researched it), one for an ammo box, and one for flares. Pressing an order
again takes it back, or cancels it under way for a refund. Each idle
armory takes the first order it can, when the bank can pay: a rifle,
blade runners, a grapple or a heated suit cost 2 ore, a jetpack 2 ore and
1 alloy, armour 1 ore and 2 alloy; each takes 10-18 s, drawing power
(0.6/s) and making some noise. What's made waits for you: its button
reads READY, and pressing it puts it on.

At nightfall, bug holes tear open in the ground, 34-62 m from the
pod: one the first night, two the second, and so on, and one more with three or
more players. They open one by one as dusk sweeps across the map from
east to west over 30 s, glow red, and close the same way as the sunrise
sweeps across it (shade doesn't keep one open). Spiders climb out of
them all night, and after dawn from any the sunrise hasn't reached yet, more of them and
more often as the mission goes on, and with more players: at most 3 at
once at first and 8 by twelve minutes in, solo, coming up as often as
every 1.7 s at first and 0.8 s by then, and still climbing after (to 16
at once and every 0.4 s), with each player past the first adding
half as much again. They go for the nearest thing within 40 m, one of
you or anything you've built, counting you a little nearer than you are
and the pod a little further; but anything working loud enough draws
them from further off (a drilling rig counts as 20 m nearer, a smelting
foundry 30, a lab at work 8, the pod 5), until they're within 15 m of it,
where noise counts for less and less. Shoot or hammer one and it comes
for you for the next 4 s. With nothing near, they make for the pod. What they destroy is
gone. Sunlight sends them back under. Your health comes back once
nothing's hurt you for a few seconds.

The pod has 500 hull. If the spiders tear it open, the mission's lost.
It mends itself slowly while there's power and nothing's bitten it for 8 s,
and every hammer blow patches 25 (the hammer mends anything damaged that
way).

Each soldier lands with 4 flares, and can carry 6; they don't come back,
but an armory's screen sells 3 for 1 ore. A flare burns for 35 s
wherever it lands, lighting the ground round it and keeping spiders from
climbing out near it (a rig by one keeps drilling, and turrets can see
by it), but it doesn't keep you warm.

## Playing together

The menu offers solo, or online play on the one server,
`wss://rockhopper.play.devoncoleman.com:9443`. Everyone starts as a
soldier. The commander's seat is in the pod: "Take command" on the pod's
screen climbs in (one commander at a time), out of harm's way and the
cold, counted aboard at launch, with an overhead view of the area (WASD,
the screen edges or the middle button pan, the wheel zooms, Q and E turn it);
X climbs back out beside the pod. In solo, the seat's yours too: climb
in to plan, climb out to build. The server runs the
world: spiders, building, cables, power, research, the bank and the
clock. Each client moves its own soldier and asks the server for
everything else. Every client generates the same map from the server's
seed. Freezing or being killed puts you down where you fell, and
spiders leave you be: you stay down, for good, till another soldier
holds E on you for 2.5 s, which gets you back up with half your health,
and what you carried and wore. With nobody left standing (the commander,
safe in the pod, counts as standing, and can climb out to help), the
mission's lost.

The server turns away a client on a different build. The build is a hash
of the game's scripts and shaders (everything but `addons`, `tests` and
`tools`), shown under the menu and in the server's log, so uncommitted
edits count too.

From the command line, after `--`:

- `server` (with `port=`, default 7777, and `seed=`): a dedicated server,
  headless, with no player of its own.
- `host`: a server with you playing on it.
- `join=address:port` (or a `ws://` or `wss://` URL), with `name=`: any
  other server, for testing.

Godot's multiplayer runs over WebSockets (`WebSocketMultiplayerPeer`), so
browsers can join; the port is TCP. In a browser, Esc frees the mouse
before the game hears the key, so losing the mouse mid-mission pauses.

The dedicated server runs on a Debian box: `tools/deploy_server.sh
[user@host] [port]` (from a machine with ssh access) installs Godot's
Linux build there, clones or pulls this repo, and runs it headless as a
systemd user service, restarting on failure. A timer
(`rockhopper-update.timer`) checks GitHub every minute and, when `main`
has moved, updates to it and restarts the server, so pushing is all an
update needs: the server and the web build both catch up within a couple
of minutes (anyone mid-mission is dropped, and reloads onto the new
build). Logs: `journalctl --user -u rockhopper -f` on the box, and
`-u rockhopper-update` for the updates.

Browsers on the HTTPS site need `wss://`: `tools/proxy_server.sh` puts the
server behind the shared Caddy on the box at
`wss://rockhopper.play.devoncoleman.com:9443` (the same one as
Sloprunner's: a wildcard certificate for `*.play.devoncoleman.com` from the
Route 53 DNS challenge, port 9443 forwarded on the router, a route file per
game in `~/caddy/sites/`). `tools/proxy_server.sh stop` takes the route
down.

The web build: push to `main`, and `.github/workflows/deploy-pages.yml`
exports the `rockhopper` preset and publishes it to
`devonbacon/game-demo-test` under `rockhopper/`, beside Sloprunner, RTL and
Skiff. It has no threads (so no special headers): the music renders a few
milliseconds a frame instead of on a worker. It draws with the
Compatibility renderer (`rendering_method.web`), while desktop keeps
Forward+, so the browser's nights look a little warmer and brighter. The
build hash is the same as the desktop's, so both join the same server.

To share a build: `tools/export_windows.sh` exports a Windows build and
zips it as `build/rockhopper-<build>.zip`, named for the hash the server
checks. It needs Godot's Windows export templates installed. Scripts go in
as text so the exported game hashes the same as the source does.

Playtest logs: the server (or `metrics` solo) logs each mission to
`user://sessions/<started>.jsonl`, a JSON object a line: who joined and
left, what was built, researched, ordered and lost, falls and revives,
holes and the launch, a sample of how things stand every 30 s, and
running tallies per player (kills, damage dealt and taken, ore mined and
handed in, repairs, revives). `tools/fetch_sessions.sh` copies the
server's into `sessions/`; `python tools/session_summary.py [file]`
prints a mission's timeline, samples and tallies.

Debug arguments skip the lobby, landing a short walk from a deposit. `command`
starts in the commander's seat (with `research`, the research panel
open; `place=pylon` holds that to place); `relobby` has the leader send
everyone back to the lobby once, 12 s in; `bitten` starts with the pod
and everything built damaged;
`probe=builder|walker|stander|commander` scripts a joined client, for
checking a server headlessly.

## Commanding

The commander's view is overhead, lit up like a tactical display so the
night doesn't blind it, with markers on soldiers (blue diamonds),
spiders (red dots), bug holes, blueprints, rigs and foundries (LOUD
under the ones spiders can hear), and OFF on whatever's switched off.

- **Camera:** WASD, the screen edges or dragging with the middle button
  pan, the wheel zooms, Q and E turn it.
- **Building:** 1-9, 0, - or the bar at the bottom picks a lamp, panel,
  battery, rig, lab, pylon, foundry, turret, barricade, armory or vent
  tap; left-click places it as a
  blueprint (Shift keeps placing), right-click or Esc puts it away. A rig
  snaps to the deposit nearest the mouse, and a tap to the vent. Vents
  show what a tap would make, and deposits the ore they've left. Placing something that takes
  cables shows a ring for how far one reaches, and circles what's in
  reach. Damaged buildings show a health bar. Things face the pod to start
  with (barricades standing across the way to it); the wheel turns what
  you're placing, and Ctrl and the wheel zooms meanwhile. Delete over a
  blueprint cancels it, refunding what its blows have
  paid.
- **Cables (C, or the bar):** click a pylon, rig, foundry or the pod
  (built or a blueprint) to run one from it, then another to tie it on,
  or open ground to put a pylon blueprint there for it; either way it
  carries on from there, so a line of pylons is a click each.
  Right-click lets go; a ring shows how far it reaches (20 m). A cable
  runs the way you laid it, except that it always runs into the pod and
  out of a rig. Over a cable, F turns it round and Delete cuts it.
  They show arrowed the way they run.
- **Inspect:** click something built to see how it's doing (a foundry's
  bins, a rig's hopper, its hull, whether it's loud). P, or the button
  beside it, switches it off or on; P over a building does the same.
- **Ping:** right-click.
- **Launch (L, twice, or the bar):** the pod lifts off 45 s later with
  whoever's beside it, and the engines tear bug holes open near it; L
  again calls it off.
- **The pod's hull** is on the readout; when spiders bite it, the edges
  flash red.
- **Research (R):** the tech tree; click to queue (see above).
- **X** climbs out; **Esc** pauses.

## Controls

- **Move:** mouse looks, WASD walks, Shift runs (slowly until you've
  got blade runners). Space jumps; once you've a jetpack, hold it in the
  air to fly; it refills on the ground. C or Ctrl
  while running slides: a burst of speed, faster downhill, and a jump
  out of it keeps the momentum (up to 8 m/s, easing back to running speed
  in the air, until blade runners). Land
  with it held to slide on. You can steer well in the air.
- **Weapons:** you start with the hammer; once you've a rifle from an
  armory, 1, 2 or the wheel switch between them.
  The hammer smashes everything in a short arc in front, hurting
  spiders (two blows kill one), knocking each back a little and
  stunning it for a second, chips ore off a deposit, and puts up the
  commander's blueprints a blow at a time.
- **Repairs:** anything built that's been bitten shows a health bar over
  it, green to red; hammer it to patch it up.
- **Grapple (middle mouse, once you've one):** a spider gets tugged
  towards you; anything else (rock, a building) reels you in, up to
  10 m/s, for as long as you hold the button, from up to 25 m. It takes
  5 s to be ready again after you let go or tug a spider.
- **Fire:** left mouse, held, about 3 shots a second; a spider takes
  three (30 health, 10 a shot; two hammer blows). Shots land in a
  cone (the crosshair's ticks) that widens as you fire, move or jump, and
  settles back. Hold right mouse to aim down the sights: zoomed, much
  tighter, but slow on your feet.
- **Use (E):** tap at the pod to hand in what you carry, or at a rig to
  empty its hopper into your pockets. Hold on ore or a deposit to mine
  it, or on anything built to pick it up. On a cable overhead, E rides it
  (E or Space lets go).
- **The pod's screen:** look at a button on it and press E, to hand in
  what you carry, or take command. It also shows the ore and alloy
  banked, the battery, the hull and, once it's called, the launch countdown.
- **Flare (Q):** throws one where you're looking.
- **Ping (G):** marks the spot you're looking at for everyone
  for 8 s: a beam of light, and a marker on screen with your name and how
  far it is. The commander's pings are gold.
- **F** toggles the headlamp. **Esc** pauses (Resume, New map, Quit);
  Esc again resumes.
- **R** after a mission: a new map. **Shift+R:** the same one.

The sunset/sunrise clock and the strip under it look along where the sun
will be from where you stand, so they allow for the terrain round you.

## Music

A synth score in D minor after Tron: Legacy, with Deep Rock Galactic in
its fights, rendered at startup and following the mission. By day, a
wide pad and a soft bass, now and then an arpeggio. At night the bass
pulses in sixteenths, pumping, the arpeggio runs, low brass swells on
the chord changes, and every other phrase the brass plays the theme.
With three or more spiders near you (or the pod, from the command
chair), rock drums and chugging guitar come in under the theme. When the
pod's being bitten, or once the launch is called, it goes four on the floor
with the arpeggio an octave up. It climbs straight away, with a crash,
and comes back down only after four calmer bars. The pause menu has its
volume, kept between runs. The score is `audio/music.gd`; the synth,
`audio/instruments.gd`, comes from Real-Time Logistics.

## Sound effects and the sound editor

Actions have synth sound effects: guns and turrets, the hammer, mining,
handing in, flares, the grapple, cables, spiders hurt, dying and biting,
pings, announcements (building, research and the pod alarm have their
own), and the commander's clicks. The jetpack and cable riding loop.
Things in the world sound from where they happen, and the server sends
them to everyone in earshot (`Game.sound`); your own gun, swing, grapple
and clicks sound at once on your machine.

Everything the music and effects are made from is in
`audio/sounds.json`: the tempo, chords, theme, each mood's step
patterns, levels and instruments, and each effect's instrument and
settings. F2 (or the pause menu) opens the sound editor, adapted from
Real-Time Logistics' music editor, which changes it all as it plays: it
holds a mood, mutes parts, and plays an effect each time you change it.
Save writes `audio/sounds.json` when run from the Godot editor, and
`user://sounds.json` anywhere else, where it then wins over the
project's. Copy and Paste move the whole file as JSON. The pause menu
has the effects' volume too.

## Tuning

Mission, power, health and spider numbers are constants at the top of
`game/game.gd`. The day's length and the sun's path are in
`world/sun.gd`. The map's size, wall, hills and caves are in
`world/terrain.gd`. Rigs' drilling rate and hopper are in
`world/fixture.gd`, with foundries, noise and what costs alloy; cables
in `world/link.gd`. Movement, the gun and riding cables are in
`player/player.gd`, and spiders in `world/spider.gd`.

## Debugging

User arguments after `--`, e.g.
`Godot --path . -- --seed=1 --time=200 --lamps=2`:

- `seed=N`: the map.
- `time=S`: start S seconds in (`time=150` is dusk).
- `view=overview` looks down on the whole area; `view=cave` stands
  you in a cave; `view=screen` in front of the pod's screen.
- `rig` builds a rig on the deposit nearest the pod and stands you
  beside it.
- `vent` stands you by the nearest vent, with a tap on the next
  (`vent=tap`, by the tap).
- `lobby` keeps the lobby (with `shot`, screenshots it).
- `defence` builds a loaded turret, a lamp and three barricades on the
  side of you away from the pod.
- `cables` builds a rig on the deposit nearest the pod and a foundry
  halfway home, cables them rig to foundry to pod, and stands you by
  the foundry.
- `lamps=N` builds N lamps around you.
- `spiders=N` brings N spiders up in front of you.
- `plan=N` places N blueprints round the pod, part built.
- `flares=N` throws N flares ahead of you; `ping` pings 25 m ahead.
- `yaw=D` turns you and `pitch=D` tilts your view, by D degrees.
- `aim` holds aim down the sights; `pause` starts paused.
- `hammer` starts with the hammer out.
- `lab` builds a research lab ahead of you and queues the rifle;
  `armory` builds an armory there instead;
  `upgrades=gun,jetpack,...` starts with those researched, and the gear
  on.
- `shot=path.png` saves a screenshot after `shot_at` seconds (default
  3), then quits.

- `mood=0-3` holds the music in a mood (day, night, swarm, siege);
  `record=path.wav` records the music for `record_for` seconds (default
  30) once it's ready, then quits; `solo=name` plays only the sounds
  whose names start with it (bass, arp, brass, braam, guitar, kick,
  snare, hat, tom, pad).
- `sound_editor=N` opens the sound editor on tab N.
## Layout

- `world/terrain.gd`: the ground, a signed distance field (hills,
  boulders, small craters, caves) meshed once by surface nets into chunks
  with trimesh colliders, plus a navigation mesh baked from it (used to
  place deposits you can walk to), a flat plain out to the horizon, the
  mountains (a ridged-noise ring with a collider, so the sun sees them), and
  the hologram wall (`world/boundary.gdshader`). No deformation.
- `world/sun.gd`, `world/space.gdshader`: the sun and the sky.
- `world/fixture.gd`: the pod, ore, deposits, and everything built.
- `world/link.gd`: cables.
- `world/screen.gd`, `world/screen.gdshader`: the pod's screen.
- `world/flare.gd`: flares.
- `world/hole.gd`: bug holes.
- `world/spider.gd`: the spiders.
- `player/player.gd`: you.
- `game/game.gd`: the mission, power, warmth, building, the spiders'
  spawning, and the server/client split (snapshots, requests).
- `net/net.gd` (autoload `Net`): connections and every RPC.
- `game/avatar.gd`: other soldiers.
- `menu/menu.gd`: the front door.
- `audio/music.gd` (autoload `Music`), `audio/instruments.gd`: the
  soundtrack and its synth.
- `audio/sfx.gd` (autoload `Sfx`): sound effects.
- `audio/sounds.gd`, `audio/sounds.json`: what the music and effects
  are made from.
- `ui/sound_editor/` (autoload `SoundEditor`): the sound editor.
- `game/metrics.gd`: the playtest log.
- `game/commander.gd`: the commander's view.
- `lobby/lobby.gd`: the lobby, before the drop.
- `ui/hud.gd`: readouts.
- `tests/smoke.gd`: headless,
  `Godot --headless --fixed-fps 60 --path . res://tests/smoke.tscn`. It plays
  a minute and a half of a rig cabled through a foundry to the pod by
  day, with a ride on a cable, then half a minute of night.
