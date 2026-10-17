# Rope Racers — the full guide

Everything about the game in one place: the tracks, the cars and the rope, the career and the garage,
damage, the menus and controls, multiplayer, how a release is made, the project layout and every tuning
constant. The [README](../README.md) is the short version.

## Tracks

Press **Race** on the title screen to open the track select: the list of circuits is on the left, a
live preview of the highlighted one — drawn by the real track code, at 1/1.6 scale — is on the right,
with its length, corner count, road width, lap count, difficulty and your records under it.

| Input | Does |
| --- | --- |
| **Up / Down** | Move the highlight (wraps around) |
| **Enter / Space**, **RACE** button, **double-click a row** | Start the highlighted track |
| **Move the mouse over a row** | Highlights it; the preview follows |
| **Esc**, **Back** button | Back to the car screen |

| Track | Where | Length | Corners | Road | What it asks of you |
| --- | --- | --- | --- | --- | --- |
| **Circle** | the test oval | 141 m | 2 | 110 px | One long corner, two straights, no excuses. The one that teaches the rope. |
| **Figure 8** | the crossover | 181 m | 4 | 110 px | Crosses itself on a real bridge — watch which branch you are on. |
| **Neon Harbour** | Night Streets | 166 m | 11 | 100 px | Corner after corner between the walls, and the shortest straight in the game. |
| **Serpent** | six screens of bends | 495 m | 18 | 112 px | Long and winding: you never see more than the next bend. |

**Four, and each one a different job.** Twelve circuits shipped until 0.11.7, and seven of them were
near-twins: `tools/track_table.gd` prints every lap's length, corner count, tightest radius and longest
straight, and read together the desert and street circuits were the same lap under different scenery.
What is left is the oval to learn on, the bridge, the technical one and the long one. The last one is
bigger than the screen -- the camera rides with you. Lengths use the game's one scale (the
same one the speedometer uses).

**Every track is open from the first minute**, and winning one puts **stars** on it: one for a win on
Easy, two on Medium, three on Hard. The track screen shows them where a padlock used to be.

The difficulty badge on the select screen is **measured**, not authored: it is derived from the
circuit's corner density, its tightest radius, how little of the lap is one straight, and how much
run-off it has (`TrackRegistry.get_difficulty()`).

Adding a track costs exactly **one entry in `scripts/track_registry.gd` plus one generator file in
`scripts/tracks/`** — the select screen, the menu, the HUD layout, the records and the checkpoints all
read the registry. Or draw one in the editor with no code at all: see **Making your own maps** below.

---

## Cars, colours and rivals

**Race** opens the **car select** screen (each car you pick revs its engine for a second, in its own
voice: the Formula screams, the Grand Tourer growls, the Kart buzzes): pick a car with **Up / Down** (or
click it), its colour with
**Left / Right** (or click a swatch), then **Enter** / **NEXT: TRACK**. **Records are kept per track and
per car**: lap times of different cars are never mixed (records set before cars existed belong to the
Sport). Best-race totals are also kept per lap count, so the old 3-lap totals never compete with 10-lap
races.

The **RIVALS** panel on the same screen sets how many AI cars you race (0 = a solo time trial, up to 4)
and, for each one, its **car** (Random or a specific one), **colour** (Random or one of the five),
**difficulty** and **style**:

The rivals drive with a **rope and a cursor, like you** (only your own rope is drawn). Their cursor is a **hand**: it reacts a moment late and can only move so fast. They throw the rope
long on the straights, snap it short to brake, and flick it to the inside of a corner to throw the car
into a drift.

| Level | Driver | Hand | Drifts | Boost | Mistakes |
| --- | --- | --- | --- | --- | --- |
| **Easy** | Careful: near the middle of the road, brakes early, wanders a little | slow, 0.22 s late | never | never | runs wide now and then |
| **Medium** | Decent: most of the racing line, brakes later | quicker, 0.12 s late | some corners | yes | the odd one |
| **Hard** | A racer: the full racing line at the limit, late on the brakes | fast, 0.06 s late | most corners (a Sport or Rally more than a Formula) | every straight | none |

The track screen spells out the chosen level under the preview.

**Personalities.** The level is how good a driver is; its **personality** is what it tries to do. Every
rival is dealt one at random (its name in the results says which, e.g. *Green Kart - Hothead*):

| Personality | How it drives |
| --- | --- |
| **Pro** | Smooth throttle, precise, defends the inside, saves its boost to pass. The fewest mistakes. |
| **Hothead** | The rope is either flung out or stabbed back; overdrives every corner, fires the boost the moment it can, gets angry fast. Quickest laps, most mistakes. |
| **Drifter** | Throws most corners sideways, and now and then flicks the tail out on a straight for show. |
| **Bully** | Leans on cars alongside to push them off, blocks, brakes late. |
| **Rookie** | Shaky hand, attention lapses, lifts on the straights, panics when a car appears alongside. The slowest. |
| **Wildcard** | Changes mood every 12-22 s: a Hothead lap, then a Pro one, then a Rookie one... |

Every driver also has a **mood**: being overtaken, wrecking or going off the road winds it up (it asks more
of every corner and makes more mistakes), leading calms it down. And they make the mistakes people make:
braking too late, turning in too early and clipping the cones, running wide on a greedy exit, over-flicking
a drift into a half-spin, flinging the rope so far it drags the car.

| Style | What it does in traffic |
| --- | --- |
| **Clean** | Steers round a car in its way and lifts if it cannot get past. |
| **Aggressive** | Leans on a car that is ALONGSIDE it with the track edge on its far side, to push it onto the grass -- but never rams from straight behind (that would only wreck itself) and never while braking for a corner. |

The rivals drive through exactly the same input you do (a rope target), so they obey the same physics,
take damage, roll, explode and respawn like you. Cars **collide**: they push each other apart and trade
momentum by weight, and a hard hit damages and can tip a car. You start at the back of the grid; the HUD
shows your place (**P2/5**) next to the lap counter, and the finish screen shows where you finished and the
whole field in order.

| Car | Max speed | Weight | Good at | Weak at | Rope |
| --- | --- | --- | --- | --- | --- |
| **Sport** | 120 km/h | 1250 kg | Drifting (a held slide fills its boost fastest); the easiest to drive | No stand-out pace on a clean lap | Standard rope, fair tension zone |
| **Formula** | 130 km/h | 800 kg | Grip and braking; the flowing circuits | The grass; a slow pull-away | Short steel cable, almost no tension zone |
| **Grand Tourer** | 146 km/h | 1600 kg | Top speed, the biggest slingshot boost, wins every shove | Tail-happy on the power, long braking, lazy turn-in | Long bungee, a huge tension zone |
| **Rally** | 118 km/h | 1200 kg | Off the road: grass is a slower road, sand barely stops it | Loose on tarmac | Long slack tow rope; drifts fill its boost |
| **Kart** | 92 km/h | 500 kg | Tight, twisty tracks: pulls away and brakes like nothing else | Top speed; loses every shove | Short cord right on the car; small, quick boosts |

**No car is the best everywhere.** Measured with the hard AI alone (`tools/measure_laps.gd`), the
Formula, the Kart and the Grand Tourer each win tracks and every car is within ~3 % of the fastest on
average (before this round the Formula won all eight by 13-16 %). The Sport and the Rally win their
races with what the AI never does -- long drifts and running off the road.

### The rope, the tension zone and the boost

Every car has **its own rope** -- how far out it reaches full throttle and how much past that it forgives.
Just past the full-throttle length is the car's **tension zone**: hold the cursor there and the rope
turns **gold**, the car is held (not dragged) and its **BOOST** meter fills; drifting fills it too. Two
small gold ticks round the car mark where the zone starts and ends. Further out, at the speed limit,
the rope turns **red** and drags the car as before.

A full meter says **BOOST: CLICK!** -- a **click** fires it (the game is played with the mouse alone): a jet of flame and a few
tenths of extra top speed and drive (the GT's lasts 1.6 s, the Kart's 0.8 s). The boost never takes the
brakes away: shorten the rope and the car slows as usual. The AI rivals charge and fire boosts too, and
only on a straight.

### Medals

Every car has its own medal times on every track, so a quick Kart lap counts as much as a quick
Formula one: **Gold** beats the hard AI's best lap in that car, **Silver** is within 6 % of it, **Bronze**
within 15 %. The track screen shows the three times for your car, the medal you have won (also a disc
on the track's row) and the fastest cars there; the finish screen says which medal the race won and what
the next one needs. The car screen lists each car's **best tracks**.

The four characteristics, and what they do on the road:

* **Max speed** is how fast the wheels can turn. Pull the rope further than that and the car is
  **dragged**: the tyres skid (lose grip), the rope pulls it past its top speed, the chassis wobbles, a
  sideways drag tips it over, and the strain damages it. The dash's wheel-rpm bar goes red and flashes
  *DRAGGING*.
* **Suspension** -- stiff is flat and precise on tarmac but every bump off the road goes straight into
  the chassis; soft rolls more in corners but soaks up rough ground.
* **Weight** -- heavier brakes longer and is slower to rotate, but is steadier.
* **Dynamics** -- acceleration, brakes, tyre grip and how fast the nose follows the rope.

**Tyres and damage**: drag the car with the rope (the rope red) and the tyres wear; after a couple of
seconds of it one **bursts** with a bang and you drive on the **metal rim** -- sparks and flames under that
wheel, less grip, lower top speed, the car pulls and shakes (*FLAT TYRE* in the race bar). Every tyre can
go; a respawn fits new ones. Hard hits **dent** the car and knock **pieces** off it (spoilers, wings,
bumpers, lamps), and a wreck throws the rest; the pieces land on the track and **stay there** for the
rest of the race.

**Damage you can feel**: a piece knocked off the **front** costs the front tyres grip (the nose washes
wide), off the **rear** the tail gets loose at speed, a side missing more panels than the other **pulls the
car that way**, every piece gone makes the car twitchier, and a side without its panels takes more from the
next hit. A car close to wrecking (past 80 %) **drips oil** -- small glossy splashes that take half a wheel's
grip and dry out over 20 s. A wreck leaves a **fire** burning for 4 s that hurts any car driven into it. Pieces of cars on the
road are **sharp**: hit one and a tyre takes a real cut.

**The rope can snap**: drag the car too hard for too long (~3 s flat out past the zone -- after the tyres
have started to go) and the rope breaks with a crack. No pull, no brakes: the car coasts. Bring the cursor
back to the car to tie the rope on again.

**Sounds**: metal rims scraping on the road, the rope creaking as it strains (and cracking when it snaps),
pieces cracking off a car.

**The buildings are solid**: drive into one and you stop, dented — and the rope cannot be dragged
through one either, it saws on the corner until it snaps. Parks and car parks are flat: cut across those.

**Under the panels**: every car is built with an engine and a cockpit inside it. Knock the bonnet off
and the engine block, its plenum and cam covers are there in the hole; take the roof and the windscreen
goes with it, leaving the seats, the wheel and the roll cage. Bumpers, splitters, mirrors, doors,
exhausts, wings and a rally spare wheel are all pieces that can be knocked off and left on the track.

**Cones and tyre stacks**: every corner is lined with traffic cones on the edge of the road, and the
sharpest ones have tyre stacks out on the run-off. Clip a cone and it flies off (it lies where it lands
and can be hit again); hit one fast and it is crushed flat. A tyre stack bursts into loose tyres that
roll away, and costs you real speed and a little damage. Nothing is put back during a race.

Off the road: every track has **sand traps** on the outside of its corners. Grass and (worse) sand have
little grip and a rough surface: arrive fast and the car slides wide, gets kicked about and can go onto
two wheels or roll. **Damage** comes from barrier hits, rollovers (about three wreck a car), rough ground
at speed and over-pulling; a damaged car smokes, burns and loses up to a quarter of its top speed. At
100 % it explodes: after ~2 s it respawns, repaired, at the last checkpoint you passed. The race clock
keeps running -- that is the penalty -- and it keeps running through the short "Ready" after the respawn
too: the race never stops for a wreck.

All car numbers live in `scripts/car_registry.gd` (one entry per car, on top of the shared defaults in
`scripts/car.gd`).

## The world in the race

**The tow.** Sit behind a car at speed and the air it pushes out of the way is yours: the race bar says
**TOW** and your top speed goes up ~7 %. Sit in the deepest part of it and the front tyres go light
(dirty air) -- the tow has to be left before the corner, not carried into it.

**Tyres live and die.** They wear where you scrub them in a long drift, and off the road the ground eats
them -- grass costs rubber, sand costs a lot more. The AI feels this too and drives a flat car slower.
(The cold-tyre warm-up of SPEC 49 is off since 0.106.0.)

**The rope is a real thing.** It sweeps the track it lies across -- cones, loose tyres and car pieces are
flicked aside -- it **snags** on a standing tyre stack (hold it there and the stack bursts), and a cursor
parked out in the barrier **saws the rope on the concrete** until it snaps.

**Tyre walls.** Where the road runs close to the barrier the wall is lined with tyres: a hit there costs
much less damage, but the wall grabs the car instead of letting it bounce on, and knocks tyres onto the
road that stay for the rest of the race. Everywhere else the wall is concrete, and concrete hurts.

**Track limits.** Spend more than a second and a half off the road in one lap and the lap still counts --
but its time will not set a record.

## Bigger than the screen

A track can live in a world bigger than one screen — **Old Town** is four of them (2560x1440). Nothing
about the driving changes: the rope is scaled with the camera, so the cursor sits exactly where it always
did on screen. What changes is that you cannot see it all at once, so a big world is always played with
the close camera and the minimap, and there is room around the road for a **town**: blocks of buildings
with pavements, parks and car parks. They are scenery — the barrier is still what stops you.

## The menus

Four font sizes, two text colours, an 8 px grid and one line per idea (`scripts/ui_theme.gd`), on every
screen: the title menu, the car screen, the track screen, settings, the lobby, the pause menu and the
results. The car screen shows a car's name, one line of what it is good at, four single-line
characteristics and the garage; the results show your place as the headline and the laps on one line.
Everything else was repetition.

## The career

You start with **one track (Circle) and one car (the Sport)**. Win a race and the next track opens -- on
the difficulty you won it at, so the Medium ladder and the Hard ladder are separate. Finishing pays
**stars** (1 for a win on Easy, 2 on Medium, 3 on Hard -- no track is ever locked) and **coins**
(100 for a win, down to 20; x1.5 on Medium, x2 on Hard; +150 the first time you win a track and
+75 for a first gold medal there). A solo time trial pays nothing: there was nobody to beat.

Coins are spent in the **garage** (the car screen's GARAGE button, or Esc back from it):

* **Cars** -- Kart 800, Rally 1500, GT 2200, Formula 3200. A car you have not bought is shown in primer
  grey with its price written across it.
* **Colours** -- every colour of every car is free from the start (SPEC 111); the garage's colour tab is a picker.
* **Parts** -- five slots (engine, wheels, suspension, body and the **rope**), 600-900 coins each,
  fitted per car. They are not levels and there is no best set: a turbo trades drive out of the corners
  for top speed down the straight, slicks trade the grass and your tyre life for grip, all-terrains give
  it back and cost you on tarmac, a roll cage trades weight for damage, a stripped shell the other way,
  a short rope answers instantly but narrows the tension zone, an elastic one is forgiving but slow.
  The only straight gain is the lightweight engine (+5 % everywhere) and it breaks 50 % faster.
  The garage shows what each fitted part is bad at, while you choose.
* **Effects** -- flames, stars, underglow and coloured smoke, 150 each, bought once then worn or not.
* **Profiles** -- Stock, Sprint, Endurance and Dirt: one click fits a whole car and buys what is missing.

The garage shows the car with the part under your cursor already fitted -- and **you can see it**: the
turbo has a scoop, a fat pipe and the bonnet standing open over the engine, all-terrains have knobbles,
the cage puts a bar over the roof, a
stripped shell loses its doors, the springs change how the car sits. Four bars (top speed, drive, grip,
weight) are drawn as they are now and as that part would make them, with what it is good and bad at
underneath. Effects show on the car too, before you buy them.

**Settings -> Practice: all tracks** opens everything without winning it (and pays nothing).

## Parts that break

A hit on the nose costs the **engine** its power. A hit on a front **corner** bends the steering, and the
car pulls that way until you hold it off. Rough ground wears the **suspension**, and the body rolls more.
The tyres wear, burst and run on the rim as before. The race bar names the worst part once it drops below
60 %, and a respawn fits everything new.

**Self-destruct**: press **F** to write the car off on purpose, from 50 % damage, once every 30 seconds.
The game prompts you when it is worth doing. It is the ordinary wreck, so it never beats driving -- it
beats limping.

## The view

The game starts **zoomed in**, riding with your car. The **mouse wheel** (two fingers on a phone) zooms
in and out; zoom all the way out and you get the classic whole-track view. A track bigger than the screen
is always ridden with, and gets a minimap. However you zoom, the rope keeps its length on screen.

## The race order

Top left: every car in order, with its colour, its name and the lap it is on -- `L3/10` -- and your own
row picked out. Under it, the one line that matters when it matters: OFF TRACK, FLAT TYRE,
STEERING 40 %, BOOST: CLICK!

**There is no bar along the bottom any more.** Speed and rpm gauges were instruments nobody reads at
200 km/h; the screen is all road now.

## If it runs slowly

**Settings -> Low graphics** cuts the dust clouds, refreshes the rivals' car models less often and caps
the frame rate at 60. Turn it on for an integrated GPU or a laptop on battery.

Under the hood the whole world is drawn as baked meshes rather than thousands of little shapes: the
ground, the town, the props, the skid marks and the dust are one `draw_mesh` each, which took a frame
from ~3460 draw calls to ~210. Each car's 3D model only re-renders when the car actually looks
different, so five cars no longer mean six 3D render passes every frame.

## The close camera

**Settings -> Close camera** (single player) rides the view with your car at twice the scale, with a
minimap in the corner. The rope is scaled with it, so the cursor sits exactly where it always did on
screen -- but the cars are now big enough to read: the dents, the bare rims, the missing panels, and
**the engine sitting in the hole where the bonnet was**.

### Making your own tracks

Circuits are **Godot scenes you edit**, not code. Draw a `Path2D` inside a `MapTrack` scene in
`scenes/tracks/` -- with `MapBlock` buildings (solid, the rope bends round them) and `MapProp` cones,
tyre stacks and oil drums wherever you put them (SPEC 111) -- and the game picks it up the moment you
save. **`scenes/tracks/_template.tscn`** is a finished example to duplicate and rename. Every track is
checked in the editor (the root node's warning triangle), so a broken one never reaches a race.

**[docs/MAPPING.md](MAPPING.md)** is the guide: the nodes, the numbers that matter and how to check
a circuit before you drive it.

## What's new

The release notes ship with the game: **What's new**, bottom right of the title menu, opens this
changelog inside the game, newest build first, and it opens once by itself the first time a new build
runs. The corner of the menu shows the build number and the network protocol. The notes travel as
`scripts/release_notes_data.gd`, baked from `CHANGELOG.md` by `tools/bake_release_notes.gd` (the
release script does it; the suite fails when the baked copy is stale).

## Feedback

**Feedback** -- the muted button bottom left of the title menu, a line in the pause menu, a button on the
results card -- opens a card: a rating (1 to 5), **Bug / Suggestion / General**, a few words, **SEND**.
It posts straight to the game's Google Form (`Feedback.FORM_URL`) without leaving the game, adding the
version, your name and where you were ("Serpent, lap 2 of 3"); every answer lands in the form's Sheet.
A send that fails is kept in `user://feedback_queue.json` and goes with the next launch (not on the web
build, where the browser hides Google's reply and the post is fire-and-forget). Edit the form and re-read
its question ids into `scripts/feedback.gd`; `tools/send_feedback.gd` posts one entry from the command
line to check.

## Multiplayer

**Multiplayer** on the title menu has four tabs, with **YOU** (your name) on the right -- you connect
first, then pick your car in the room (**CHOOSE CAR** opens the car screen; its button takes you back):

| Tab | What |
| --- | --- |
| **ONLINE** | **PLAY ONLINE** -- the official server, `rope.thenakedcat.games`. |
| **SERVERS** | The server list (from `https://rope.thenakedcat.games/api/servers`): name, players, rooms, **Join**. |
| **DIRECT** | Any server by address: `192.168.1.20` + port, or a full `wss://host/ws`. |
| **HOST LAN** | Your computer is the server and you play too; friends use DIRECT with your IP. |

**Rooms** (on a server): the room list shows the public rooms (a **[locked]** one asks for its password).
**QUICK JOIN** puts you in the busiest open room that is about to race (or makes you one). **Create room**:
a name, **Public** or **Private** (not listed -- friends join with its **6-letter code**, shown at the top of
the room), an optional **password**, and **up to 2-6 players**. **JOIN BY CODE** takes a code (and the
password, if any). The room's creator leads it: the race setup, the player limit, public / private,
**[kick]** next to a player, and **START RACE**. A room that is racing cannot be joined.

**Connection:** the title bar shows the server and your **ping**. If the connection drops, the game
reconnects by itself for 30 s and the server keeps your seat in your room. A game and a server of
different versions refuse each other with a clear message ("update the game"); so does a full server.

**Your own server** (always on, listed in SERVERS, reachable from the web version): see
**[deploy/README.md](../deploy/README.md)** -- Docker + nginx on a small Linux box, Cloudflare in front,
optionally a Cloudflare Worker for a list of several servers -- or the GitHub image route in the
[README](../README.md#host-your-own-server).
Quick local test:

```
Linux:    ./run_server.sh [port]                   (= ./RopeRacers.x86_64 --headless -- --server --port 7777)
Windows:  RUN_SERVER.cmd [port]                    (both ship inside the release zip)
Server-only build (no graphics / sound):  build/server/RopeRacersServer.x86_64 --headless -- --server
```

In a room everyone picks their **car and colour**; the leader picks the **track**, the number of **laps**
(3 / 5 / 10), how many **AI rivals** fill the grid and their **level**, then presses **START RACE**. The grid
is shuffled. Every player's own car is simulated on their own machine (so the rope feels exactly as in
single player, whatever the ping) and sent to the others ~30 times a second, who draw it smoothly
interpolated; the server drives the AI. Cars collide, wreck and respawn as usual; everybody sees the same
finishing order. **Esc** in an online race opens the menu without pausing (the others keep racing). Every car carries a
**tag** under it -- the first letter of its driver's name and a number (Steph **S1**, Sam **S2**, Ann **A1**)
-- and the AI rivals are **AI1**, **AI2**; the tags appear in the results too.

**In the room** (SPEC 111): a **chat** under the players list (Enter or SEND; 120 characters, one line
per half second), **YOUR NAME** to rename yourself on the spot, and **START RACE** counts **5-4-3-2-1**
for everybody with a beep a second -- the leader's button reads **CANCEL** meanwhile. The official server
keeps **three standing rooms** that always exist -- **Race 3, Race 5, Race 6** -- beside
the rooms you create. Every online race pays **leaderboard points**: 10 / 7 / 5 / 3 / 2 for the first
five places and 1 for finishing behind them (leaving early pays nothing); the server keeps the table
for ever, the lobby shows the top 100 with you highlighted, and the results card says what you earned
("+7 pts - leaderboard #12 (58 pts)"). Other players' cars are drawn on their sender's clock with an
adaptive delay, so they move as smoothly as the bots.

Networking is WebSockets: `ws://` on TCP port 7777 for a LAN / home server, `wss://` (TLS, through Caddy /
Cloudflare) for the official server. The **web** build can join (a `wss://` server) but not host.

## Builds, versions and releases

**The repository carries source only.** `build/`, `.godot/` and the packaged `deploy/server|web/` are in
`.gitignore`: an export changes completely every time it is made, never merges, and would cost every clone
forever. The downloads live on the **releases page** instead, one zip per platform, all exported from the
same project:

| Platform | In the release | Notes |
| --- | --- | --- |
| Windows x86-64 | `RopeRacers-<version>-windows.zip` | `RopeRacers.exe` + `RUN_SERVER.cmd` |
| Linux x86-64 | `RopeRacers-<version>-linux.zip` | `RopeRacers.x86_64` + `run_server.sh` |
| Linux ARM64 (e.g. a Raspberry Pi server) | `RopeRacers-<version>-linux-arm64.zip` | |
| macOS (universal, unsigned) | `RopeRacers-<version>-macos.zip` | right-click > Open the first time |
| Web | `RopeRacers-<version>-web.zip` | serve the folder over http |
| Linux server (no graphics / sound) | `RopeRacers-<version>-server.zip` | what deploy/ (Docker) uses |

Android and iOS are not built: they need the Android SDK / an Apple developer setup on the build machine.

### The version number

`MAJOR.MINOR.PATCH`, counted in tens (SPEC 113): **MINOR is the tens of the design section**
the build goes up to and PATCH the section within that ten -- `0.11.3` *is* "everything through SPEC
113", `0.12.0` will be SPEC 120 -- and a fix that adds no section appends a fourth number (`0.11.3.1`).
Up to `0.112.0` the number was `0.<section>.<patch>`. It lives in exactly one place, `config/version` in
`project.godot`; `scripts/version.gd` hands it to the main menu (bottom right, "v0.11.3 - net 4"), the
dedicated server's start-up line, the server's welcome to joining players, the Docker tag and the names
of the release zips.

`Net.PROTOCOL` is a different number: it only moves when the wire format changes, and it alone decides
whether a game and a server refuse each other. A version difference is just a note in the room list
("This server runs v0.72.0 -- you have v0.71.0").

### Making a release

```
sh deploy/release.sh                 # tests, exports all six, zips them into build/release/
GODOT=/path/to/godot sh deploy/release.sh
```

To publish it:

1. bump `config/version` in `project.godot`;
2. add the matching `## <version> <date>` section to [CHANGELOG.md](../CHANGELOG.md);
3. **Actions > release > Run workflow** -- it takes the version from `project.godot`, makes the tag itself
   and publishes. (Tick *Draft* to look it over first, or *Pre-release* to mark it.)

Pushing a tag does the same thing, for when the tag comes first:

```
git tag v0.71.0 && git push origin v0.71.0
```

Either way `.github/workflows/release.yml` stops **before building anything** if the tag disagrees with
`project.godot`, if the version is already tagged, or if the changelog has no section for it. Then it runs
the same `deploy/release.sh` everyone runs locally, takes the release notes out of the changelog and
uploads the six zips.

## Key art and icons

The Godot defaults are gone: the boot splash, the title-menu background and every icon are the game's own
key art -- the low-poly cars racing at you, one up on two wheels, one flipping, one tumbling through the
air, every one on its glowing rope and ring. The other screens get calmer, darker night scenes of
the same circuit, empty -- no cars (floodlights, a vignette) so their panels read on top. The title menu itself is just
the title and the buttons (records are on the track select screen). All of it is rendered from the
game's own car models:

| File | Used for |
| --- | --- |
| `art/splash.png` | Boot splash (1920x1080, with the title) |
| `art/menu_bg.png` | Title-menu background (the same scene without the title) |
| `art/bg_garage.png` | Car select: the start / finish gantry at night |
| `art/bg_tracks.png` | Track select: the straight from high above, at night |
| `art/bg_grid.png` | Multiplayer: the empty starting grid from behind, at night |
| `art/bg_wreck.png` | Settings: across the sand trap, at night |
| `art/icon.png` | Project / window / web icon (256 px) |
| `art/icon.ico` | Windows exe icon (16-256 px) |
| `art/icon_1024.png` | macOS app icon |

To regenerate (e.g. after changing a car model): `godot --path . --script res://tools/render_art.gd`
(needs the real renderer, not `--headless`), then `python tools/make_icons.py` (Pillow) for the icon
badge, `.png` and `.ico`. `tools/` is excluded from the exports.

## Settings

**Settings** on the title menu: your **name** (shown in the race results), **full screen** or windowed,
**music** and **effects volume**, and an **FPS counter**. Every change applies and saves at
once (`user://settings.cfg`).

---

## The race bar

The race screen has two parts that never overlap: the **world** above, and an 84 px **race bar** along
the bottom. The world (the full 1280x720 track area) is drawn scaled to fit above the bar, so no road, car
or gate is ever underneath it, on any track. Everything you need to read is in the bar, in the same place
on every track:

| Block | Shows |
| --- | --- |
| **SPEED** (half-circle) | km/h, scaled to the car's top speed (the Sport reads **120 km/h** flat out). |
| **WHEEL RPM** (half-circle) | How fast the wheels turn against the car's own limit; the end of the arc is red, and the whole arc pulses red while the rope over-pulls. |
| **Track / LAP** | The track name (in its colour) and **LAP 3/10**. |
| **POSITION** | **P2/5** in a race with rivals. |
| **LAP / TOTAL**, **BEST / RECORD** | The times. |
| **Status** | OFF TRACK, DRAGGING or the drift readout, the **boost** meter and the **damage** meter. |

The countdown ("3, 2, 1, GO", "WRECKED!") and the lap flashes / messages are overlays with one fixed place
each: the countdown in the middle, messages at the top.

---

## Controls

The whole game is played with the mouse. There is no keyboard driving input.

| Input | Does |
| --- | --- |
| **Move the mouse** | Steers and accelerates. The car is pulled toward the cursor; distance = throttle. |
| **Cursor far from the car** | Full speed (the Sport at ~324 px of rope, the Kart at ~180, the GT at ~425). Just past it is the gold tension zone (charges the boost); further out the rope drags the car. |
| **Cursor close to the car** (inside the 24 px slack radius) | No pull — the car brakes to a stop. This is your brake. |
| **Yank the cursor sideways at speed** | Overloads the rear tires: the car steps out and **drifts**. |
| **Click** (in a race) | Fire the **boost** when the meter is full (*BOOST: CLICK!*). |
| **II** (top-left, in a race) | Pause -- the same as Esc, for the mouse (and, later, a finger). |
| **Bring the cursor back toward the car during a slide** | Re-grips and straightens the car out. |
| **Up / Down**, **Left / Right** (car screen) | Change car, change colour. |
| **M** | Music on / off (anywhere). |
| **Esc** | Pause (in a race; the pause menu has **Main menu**) / back one screen (car, track, settings, finish screens) / quit (in the main menu). |
| **Mouse (menus)** | Click the buttons: Race, RACE / Back, resume, restart, Tracks, race again. |

Off the asphalt the tires barely grip and the car is slowed hard, but a fast car slides a long way
first -- and the rough ground can flip it (see **Cars**). The figure-8 track has a real bridge: you drive over it on one branch and under it
on the other.

While drifting, a **DRIFT x.x s** readout appears in the HUD panel showing the live slide and the
race's banked drift time.

---

## Project layout

```
project.godot          Godot project (1280x720, canvas_items stretch, GameState autoload)
scenes/                main_menu.tscn, track_select.tscn, race.tscn, car.tscn
scripts/
  car.gd               the car: rope input, 4-wheel tire model, drift, rollover, fake-3D drawing
  tire_model.gd        the saturating tire curve (lateral + longitudinal force per wheel)
  suspension.gd        per-corner spring-damper, weight transfer, body roll/pitch
  skid_marks.gd        persistent per-wheel tire marks on the road / dirt marks on grass
  car_effects.gd       tire smoke, grass dust, barrier sparks, screen shake
  track.gd/track_data.gd/bridge_deck.gd   track geometry, drawing, the figure-8 bridge
  track_registry.gd    every track's metadata (name, colour, width, laps, gates, difficulty)
  track_shape.gd       the circuit authoring helpers: fillets, fitting, resampling, validation
  tracks/*.gd          one generator per built circuit (singapore, serpent) - each
                       returns a closed centerline from build()
  gearbox.gd           the automatic gearbox model: ratios, rpm, shift hysteresis, shift events
  dashboard.gd         the bottom instrument strip (speed / wheel rpm)
  car_registry.gd      the five cars: characteristics, liveries and tuning overrides
  car_model_3d.gd      the cars' low-poly 3D models (a SubViewport per car; not built in headless runs)
  ai_driver.gd         the AI rivals: racing line, speed profile, traffic, difficulty and style
  car_select.gd        the car / colour / rivals screen (scenes/car_select.tscn)
  settings_screen.gd   the settings screen (scenes/settings.tscn)
  net.gd               autoload "Net": hosting / joining / dedicated server, lobby, race sync
  net_puppet.gd        smooth interpolation of other players' cars
  lobby.gd             the multiplayer lobby (scenes/lobby.tscn)
  audio.gd             autoload "Audio": procedural engine, tyres, impacts, explosion, music
  track_select.gd      the track select screen: list, live SubViewport preview, stats, records
  race.gd, hud.gd, lap_tracker.gd, main_menu.gd, pause_menu.gd, finish_screen.gd, game_state.gd
tools/                 render_art.gd (key art + icon render), make_icons.py (icon badge / .ico),
                       measure_laps.gd (every car on every track with the AI; writes the medal times),
                       track_table.gd (every circuit's numbers, side by side -- what cut twelve to five),
                       verify.sh (the suite + the layout sweep: the one gate), zipdir.py (the release archives)
deploy/release.sh      builds every download for one version into build/release/ (ignored by git)
deploy/launchers/      RUN_SERVER.cmd / run_server.sh, copied next to the binaries by release.sh
CHANGELOG.md           what changed in each version
art/                   splash, screen backgrounds, icons (scripts/background_art.gd shows them)
  version.gd           the build number: project.godot -> the menu, the server, the release zips
tests/run_tests.gd     the whole 748-check suite (excluded from the export; tests/net_lobby_tests.gd is loaded by it)
docs/MAPPING.md        how to draw your own track
build/                 the exports (git ignores it; releases carry them)
```

The tuning constants below, and the doc comments in each script, are the reference for how the car,
the rope and the damage behave.

---

## Tuning constants

Every number below is an `@export` on a script, so it can be edited in the file or poked live in the
Godot inspector. Line numbers are as of this build.

### Drift feel — `scripts/car.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `drift_rear_sat` | 241 | 0.35 | Rear-tire saturation at which the car counts as drifting. |
| `drift_min_speed` | 242 | 140.0 | px/s needed before a drift can start. |
| `drift_min_slip` | 251 | 0.30 | rad of body slip that counts as a slide. |
| `drift_hold_slip` | 269 | 0.60 | rad — the slide angle the car settles at (the auto counter-steer target). |
| `drift_hold_spread` | 276 | 0.26 | How much the held angle follows your cursor angle instead of being fixed. |
| `drift_hold_short_factor` | 277 | 0.72 | A short rope holds a tighter slide than a long one. |
| `drift_damp_gain` / `drift_damp_max` | 278 / 279 | 26.0 / 14.0 | Strength and ceiling of the counter-steer that stops the spin. |
| `drift_release_start` / `drift_release_full` | 165 / 166 | 0.95 / 1.30 | Saturation window over which the steering assist lets go so the car *can* break away. |
| `drift_carry_slip` | 283 | 0.45 | Body slip above which a held drift keeps its speed instead of being braked out of. |
| `drift_carry_free` / `drift_carry_fade` / `drift_carry_floor` | 290 / 291 / 292 | 1.10 s / 1.80 s / 0.62 | A drift is free for a bit, then starts costing speed — so drifting for its own sake is slower. |
| `slide_threshold` / `slide_min_speed` | 253 / 254 | 0.90 / 35.0 | When a wheel counts as "sliding" (drives marks and smoke). |

### Tire model — `scripts/car.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `tire_peak_accel` | 110 | 800.0 | Peak lateral grip (px/s² at nominal load) — the headline grip number. |
| `cornering_stiffness` | 103 | 2200.0 | How fast force builds with slip angle before the peak. |
| `tire_shape_c` | 114 | 1.45 | Falloff past the peak: higher = sharper break-away. |
| `load_exponent` | 115 | 0.85 | Load sensitivity; 1.0 = load transfer costs nothing. |
| `high_speed_peak_factor` | 113 | 0.78 | Grip retained at top speed (keeps long ropes cutting corners). |
| `off_track_grip_factor` | 141 | 0.45 | Grass grip multiplier — the car slides easily off track. |
| `long_mu_ratio` | 124 | 1.75 | Longitudinal vs lateral grip budget. |
| `brake_bias` / `brake_grip_bonus` | 137 / 140 | 0.34 / 0.40 | Front/rear braking split, and the extra grip while braking. Re-split for the heavier car so the rear pair still locks under maximum braking (that lock-up *is* the brake mark). |
| `max_steer` / `steer_lead` / `steer_rate` | 143 / 149 / 150 | 0.52 / 1.9 / 7.0 | Front wheel angle limit, the extra lock a driver winds on, and how fast it moves. |
| `yaw_inertia` / `yaw_rate_max` | 178 / 197 | 290.0 / 4.0 | Rotational inertia and the hard spin-rate ceiling. See **Inertia** below — `yaw_inertia` scales the steering assist and the counter-steer too. |

### Inertia — `scripts/car.gd`

The car has weight: it takes 239 px (6.6 car lengths, 0.82 s) to stop from top speed, it keeps
travelling the way it was pointed while the nose comes round, and its rotation cannot step in one
frame. None of it touches the tire forces, so the rope feel and every lap time are unchanged.

Three things it is worth being straight about, because they are easy to assume and are not true:

* **The flick is critically damped.** Throwing the cursor from one side to the other reverses the yaw
  rate in 0.10 s and settles — it does **not** swing past and come back. Measured overshoot is 1.00x in
  the yaw rate and 1.01x in the body slip, at every `yaw_inertia` from 180 to 400.
* **The swing lives in the slide.** Provoke a slide and then drop the cursor on the car and it whips the
  other way to ~2.2 rad/s before it lines up, settling after 0.38 s. That is the snap-oversteer moment,
  and it is catchable.
* **`engine_response` / `brake_response` ship off.** The build-up axis exists as a tunable and is
  disabled by default; see the table.

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `mass` | 170 | 1.25 | Body mass relative to `MASS_REF`. Divides the **brake** (900 -> 720 px/s²) while the engine scales with it, so a heavier car takes longer to stop but never feels laggy pulling away. 1.0 is the pre-inertia car (201 px); 1.6 stops in 289 px. |
| `yaw_inertia` | 178 | 290.0 | How hard the car is to rotate. It divides the steering assist and the counter-steer as well as the tire torque. Judge it by **peak angular acceleration** (35.5 rad/s² at 210, 26.4 at 290) and by the **slide-catch whip** (2.55 rad/s at 210, 2.20 at 290), both of which are monotonic in it. Do *not* judge it by "time to swing 90°": that is asymptotic and runs backwards (1.53 s at 210, 0.57 s at 250 and above). 210 is the reference value at which the whole mechanism is a no-op. |
| `steer_lag_time` | 184 | 0.10 | Seconds the driver's hands need to sweep the yaw demand across its whole range. A slew limit, not a filter. **It is masked below ~0.32 s**: the slew rate at the default is 60 rad/s² while the assist ceiling already caps the yaw at ~19 rad/s², so 0.00 → 0.16 moves the flick's zero crossing by three frames in total. It is real above that, at the cost of tripling the time to reverse a flick. 0 = instant. |
| `engine_response` / `brake_response` | 190 / 191 | INF / INF | Optional first-order build-up on the drive and brake demand (1/s). Ships disabled: at 40 / 60 the careful line is untouched but the committed racing line goes 7.5 % off the road on the figure-8, stops flickering its sliding wheels, and the drift readout stops latching at low speed. |
| `susp_stiffness` / `susp_damping` | 200 / 201 | 260.0 / 18.0 | The weight-transfer lag itself: the front axle needs 0.17 s to take up its share under braking, and is still 0.18 light for over a second after a stab of throttle. Read it live with `Car.get_axle_load_balance()`. |

### Suspension — `scripts/car.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `susp_rest` / `susp_max` | 202 / 203 | 6.0 / 14.0 | px of compression at rest and at the bump stop. |
| `susp_stiffness` | 204 | 260.0 | Spring rate (~2.6 Hz). Higher = flatter, twitchier. |
| `susp_damping` | 205 | 18.0 | Damping (zeta ~0.56): one small overshoot, no jitter. |
| `roll_reference_accel` / `pitch_reference_accel` | 215 / 208 | 1600.0 / 1600.0 | Acceleration that counts as "full" lateral / longitudinal load transfer. |
| `roll_visual_gain` / `pitch_visual_gain` | 232 / 233 | 8.0 / 5.5 | px the body visibly shifts at full lean / full braking. |
| `roll_visual_curve` / `pitch_visual_curve` | 230 / 231 | 0.55 / 0.70 | < 1 amplifies small tilts, so gentle cornering still reads. |
| `visual_smooth` | 219 | 12.0 | Filter on the drawn lean — lower is floatier. |
| `surface_bump` / `bridge_bump` / `roll_land_bump` | 216 / 217 / 218 | 55 / 70 / 150 | The jolts when crossing onto grass, onto the bridge deck, and when a roll lands. |

### Rollovers — `scripts/car.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `rollovers_enabled` | 296 | true | Global off switch. |
| `two_wheel_tilt` / `two_wheel_release` | 301 / 302 | 0.75 / 0.55 | Entry and exit of the lesser "two wheels up" state, which recovers on its own. |
| `two_wheel_max_time` | 304 | 1.2 | Seconds on two wheels before it becomes a real roll. |
| `rollover_tilt` | 308 | 1.05 | Full rollover threshold — unreachable without a shock. |
| `roll_min_speed` / `tip_min_speed` | 309 / 307 | 250.0 / 150.0 | Speeds below which the car will not roll / will not tip. |
| `barrier_trip_speed` / `barrier_trip_gain` / `barrier_trip_span` | 317 / 319 / 320 | 240 / 1.25 / 340 | Clipping the screen barrier sideways as a way to trip the car. |
| `trip_slip_speed` / `trip_gain` / `trip_span` | 325 / 326 / 327 | 170 / 1.20 / 240 | Digging in — sliding sideways as the surface flips between grass and asphalt. |
| `roll_time_base` / `roll_time_per_severity` | 328 / 329 | 0.70 / 0.50 | How long the uncontrollable barrel roll lasts. |
| `roll_drag` / `roll_end_speed` / `roll_spin` | 330 / 331 / 332 | 3.2 / 70.0 / 5.0 | How hard it scrubs off speed, the speed it ends at, and the spin rate. |
| `recover_time` / `roll_cooldown` | 333 / 335 | 0.45 / 1.0 | Righting delay before you get control back, and the grace period after. |
| `shake_impulse` / `shake_decay` | 337 / 338 | 6.0 / 9.0 | Screen shake on impact. |

### Tire marks — `scripts/skid_marks.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `max_segments` | 50 | 1600 | Hard cap on stored mark segments; the oldest are recycled, so long races stay fast. |
| `fade_time` | 54 | 10.0 | Seconds a mark takes to fade out. |
| `mark_min_load` | 63 | 0.35 | Minimum wheel load before a mark is laid — light wheels leave nothing. |
| `mark_min_slip` | 65 | 45.0 | px/s of contact-patch slide needed to mark. |
| `mark_min_lat_sat` / `mark_min_long_sat` | 81 / 82 | 0.45 / 1.00 | How saturated the tire must be sideways / lengthwise to mark. |
| `grass_slip_factor` | 70 | 0.40 | Grass marks (lighter dirt) come easier than rubber on asphalt. |
| `min_segment_length` | 52 | 6.0 | px between recorded points. |
| `max_new_per_frame` | 58 | 4 | Per-wheel budget, one per wheel per frame. |

### Effects — `scripts/car_effects.gd`

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `max_puffs` | 74 | 90 | Cap on live smoke/dust puffs (oldest recycled). |
| `smoke_rate` | 75 | 26.0 | Tire-smoke puffs/s per sliding wheel at full drift intensity. |
| `dust_rate` | 76 | 18.0 | Dust puffs/s per wheel on grass, scaled by speed. |
| `spark_count` / `max_sparks` | 77 / 78 | 10 / 48 | Sparks per barrier scrape, and the live cap. |

### Rope input — `scripts/car.gd`

The original feel constants, unchanged by the physics work:

| Constant | Line | Default | What it does |
| --- | --- | --- | --- |
| `slack_radius` | 67 | 24.0 | px of dead zone around the car where it brakes. |
| `speed_per_px` | 68 | 2.0 | Target speed gained per px of rope beyond the slack. |
| `max_speed` | 71 | 580.0 | px/s top speed (reached at ~314 px of rope). |
| `acceleration` / `brake_deceleration` | 72 / 73 | 520 / 900 | px/s². |
| `turn_rate` | 74 | 3.0 | rad/s ceiling on the demanded yaw rate. |
| `off_track_max_speed` / `off_track_drag` | 76 / 77 | 58.0 / 6.0 | The grass crawl (~10 % of top speed). |
| `screen_margin` | 84 | 22.0 | px barrier that keeps the car on screen. |

### Gearbox and dashboard — `scripts/gearbox.gd`, `scripts/dashboard.gd`

The gearbox is a real model with its own state, ratios, hysteresis and events; it does **not** modulate
torque, so the rope feel and every lap time are exactly what they were without it. It is no longer drawn
(the dash shows wheel rpm); its engine rpm drives the pitch of the engine sound.

| Constant | File | Default | What it does |
| --- | --- | --- | --- |
| `GEAR_TOP_SPEED` | gearbox | 95/135/195/260/345/460 | px/s at which each gear hits the redline. Retuned so the 150-350 px/s band the game is actually played in spans three gears with two shift points in it, and so gear 6 tops out **below** `Car.max_speed` (580) — otherwise the red zone is unreachable, because the box is fed `velocity.dot(heading)` and tyre slip keeps that a few px/s under the cap. |
| `IDLE_RPM` / `REDLINE_RPM` / `MAX_RPM` | gearbox | 900 / 6800 / 7800 | The rev range; the red zone starts at the redline, i.e. at 87 % of the bar (three of its 24 segments). |
| `SHIFT_UP_RPM` / `SHIFT_DOWN_RPM` | gearbox | 6500 / 4200 | Shift thresholds, just under the redline: an ordinary upshift does not sit on the limiter, but gear 6 (which cannot upshift) runs past it on a long straight. |
| `SHIFT_LOCK_TIME` / `SHIFT_CHAIN_TIME` | gearbox | 0.25 / 0.10 | Dwell before a shift that reverses the last one / before another shift the same way. |
| `NEUTRAL_SPEED` | gearbox | 12.0 | px/s below which a coasting car sits in **N** (and below `-12` reads **R**). |
| `KMH_PER_PX` | dashboard | 0.2 | The speedometer scale: 1 px/s = 0.2 km/h (5.6 cm per px, the same scale as the track lengths). |
| `WHEEL_RADIUS_M` | dashboard | 0.30 | Wheel radius for the wheel-rpm readout. |
| `BASE_ALPHA` / `DUCK_ALPHA` / `DUCK_FADE` | dashboard | 0.80 / 0.18 / 8.0 | Strip opacity, the opacity it ducks to over road, and how fast it fades. |
| `THROTTLE_WINDOW` / `BRAKE_WINDOW` | dashboard | 140 / 180 | px/s of rope speed demand that counts as full throttle / full brake (drives the engine sound). |

### Over-pull, off-road and damage -- `scripts/car.gd` (switched on per car by `scripts/car_registry.gd`)

All of these default to OFF on a bare `Car`, so the physics tests keep testing the car they were tuned
against; `CarRegistry.COMMON` switches them on for every car you drive.

| Constant | Game value | What it does |
| --- | --- | --- |
| `overpull_drag` / `overpull_speed_margin` | 520 / 0.12 | px/s^2 the rope drags an over-pulled car with; how far past `max_speed` it can be dragged. |
| `overpull_grip_loss` / `overpull_tilt` / `overpull_wobble` | 0.55 / 5.0 / 7.0 | Tyre grip lost, tilt shock and yaw wobble at full over-pull. |
| `offroad_rough` / `sand_rough` | 1.0 / 1.6 | How hard grass / sand kick the car at speed (scaled by suspension stiffness). |
| `sand_grip_factor` / `sand_max_speed` / `sand_slowdown_rate` | 0.30 / 100 / 2.4 | Sand grip, crawl cap and how fast it bleeds speed. |
| `off_track_slowdown_rate` | 3.2 | Grass speed bleed (the legacy car stopped in ~0.25 s; now a fast car slides first). |
| `damage_per_impact` / `damage_per_roll` + `damage_roll_severity` | 0.08 / 22 + 30 | Damage per px/s of barrier impact; per rollover. |
| `damage_rough` / `damage_overpull` / `damage_speed_loss` | 7 / 9 / 0.25 | Damage per second of rough ground / over-pull; top speed lost at 100 %. |
| `Race.WRECK_TIME` | 2.2 s | Explosion to respawn (the clock keeps running). |
| `Track.SAND_DEPTH` / `SAND_CORNER_RADIUS` | 64 / 320 | Sand trap depth, and how tight a corner must be to get one. |

### Race bar and overlays — `scripts/dashboard.gd`, `scripts/hud.gd`, `scripts/race.gd`

| Constant | Default | What it does |
| --- | --- | --- |
| `Race.WORLD_SCREEN` | 0,0 1280x636 | The part of the screen the world is drawn into (above the bar). |
| `Dashboard.RECT` | 0,636 1280x84 | The race bar. |
| `Dashboard.SPEED_CENTRE` / `RPM_CENTRE` / `GAUGE_RADIUS` | (82,710) / (228,710) / 56 | The two half-circle gauges. |
| `Hud.COUNTDOWN_RECT` / `FLASH_RECT` / `HINT_RECT` | - | The fixed places of the three overlays. |

> **Careful when retuning.** The tire, drift and rope numbers are pinned against each other by the
> `difficulty` and `autopilot` tests: a careful driver (cursor 96-192 px ahead) must lap every track
> cleanly, a reckless full-length rope must run off at the bends, and lap times must stay within
> 25 % of the reference. Change a grip or speed constant and re-run the suite.

---

## Rebuilding the executable

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --export-release "Windows Desktop" build/RopeRacers.exe
```

The export preset lives in `export_presets.cfg` and excludes `tests/*` from the shipped build. For all six
platforms at once, zipped and named after the version, use `sh deploy/release.sh` (see **Builds, versions
and releases**).
