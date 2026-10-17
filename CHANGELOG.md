# Changelog

What changed, build by build. The newest release is at the top.

**How the number works** (SPEC 72, counted in tens since SPEC 113): `MAJOR.MINOR.PATCH`, where MINOR is
the **tens of the highest SPEC section** in the build and PATCH the section within that ten — `0.11.3`
*is* "everything up to SPEC 113", `0.12.0` will be SPEC 120. A fix that adds no section appends a fourth
number (`0.11.3.1`). Up to `0.112.0` the number was `0.<section>.<patch>`; those builds keep their names
below. The number lives in exactly one place, `application/config/version` in `project.godot`; the game,
the server, the Docker tag and the release zips all read it from there.

`Net.PROTOCOL` is a separate number, and only moves when the wire format changes: two builds with the same
protocol can race together even if their versions differ.

**Downloads** are GitHub *releases*, not files in the repository — see the releases page, or build your own
with `sh deploy/release.sh`.

## 0.14.6 — 2026-10-17

- **Four circuits.** The Switchback is gone; Circle, Figure 8, Neon Harbour and the Serpent remain.
  Online play needs this version on both ends (net 9).
- **Lighter cars.** The last of the arena's and the delivery's code is out of the game -- the cars no
  longer scan for nearby walls every few frames in a race, for tricks that no longer exist.

## 0.14.5 — 2026-10-02

- **Rivals have big ones.** A Hothead, a Rookie, a Drifter or a Bully will now and then throw it in
  flat out with the rope snatched the wrong way, shoot off the road at speed and wreck -- explosion,
  blast, fire and debris, the real ones. A Pro never does. Lean on a rival and it happens more.
- **The yellow flag.** A rival's wreck brings out a caution: everyone slows, the field closes up
  behind the leader, nobody passes, and the green flag is a restart with the whole field on top of
  each other. Your own wreck brings out nothing.

## 0.14.4 — 2026-10-01

- **The effects you buy show up in the race.** Flames are a burner out of the exhaust, stars a
  sparkle trail, the underglow a pool of your colour under the car, and the smoke effect -- which was
  never applied -- colours your tyre smoke. They were all drawn before, at a size nobody could see.

## 0.14.3 — 2026-10-01

- **Rivals crack under pressure.** Sit on a rival's tail and it winds up: a Rookie is wrong at a corner
  every few corners, a Hothead over-drives, a Bully blocks the inside harder, a Pro barely notices. Clear
  air lets them off again. Measured, not guessed: a pressured Rookie on hard is wrong at a quarter of
  its corners, alone at a twelfth.
- **You are told who you are racing.** THE FIELD card on the grid: every rival's car, its personality,
  and what that personality does, in a line each. It stays four seconds into the race and fades.
- **Three rivals are three different personalities**, every race (and every network room).

## 0.14.2 — 2026-10-01

- **Wreck debris matters now.** The pieces a wrecked car leaves on the track cut the tyre that runs
  over them (two under one wheel burst it) and knock the car off its line; its wheels roll off as loose
  tyres that bump but do not cut. Everything a wreck leaves lies there for about three laps and then
  fades, instead of for the whole race.
- **Tyre stacks actually shove.** Running over one was meant to knock the car sideways and, measured,
  moved it less than a pixel. It moves it a car-width now.

## 0.14.1 — 2026-09-29

- **The cars on the grid really, genuinely face the right way.** On a player's normal route into a race
  every car was drawn from a picture taken while the race was still being built, and the game had
  recorded that picture as up to date -- so the whole countdown showed them facing the wrong way, and
  they snapped round the moment they moved at GO. Checked on all five circuits, through the menu the way
  a player gets there.
- **Cars stop redrawing themselves when nothing has changed.** The previous fix for this bug had every
  car redrawing every frame for its whole life. They now draw once after each change, and then stop.

## 0.14.0 — 2026-09-29

- **Rope Racers is a racing game.** The stunt arena, the trick training and the Rotterdam delivery
  region have been removed — the scripts, the scenes, the tests and the tools, not hidden behind a
  setting. One mode, and everything left serves it.
- **Multiplayer stays, and it races.** Playing other people is still here; what it cannot do any more
  is host a stunt match. The mode toggle is gone from the room panel, the two standing arena rooms are
  gone from the server, and every room in the list is a race.
- The delivery region is not lost — it became its own game.
- **Multiplayer will not talk to an older build.** Taking the arena out removed two of the game's
  network messages, which renumbers the rest, so the protocol moved from 7 to 8. Everyone in a room
  needs 0.14.0 or newer.
- 775 assertions, all green, and a new `tools/audit_modes.py` that proves nothing of the removed modes
  is left in the code, the scenes, the input map or the asset paths.

## 0.13.9 — 2026-09-28

- **The web build has sound again.** It was producing complete silence: the audio context was running,
  the output was connected, every sound was rendered and loud, the music player was playing — and the
  mixer put out nothing at all. Godot's default web audio path is the culprit; the build now uses the
  browser's own path instead. Measured before and after in a real browser, and confirmed by ear.
- **Rotterdam: cargo, traffic and police.** Delivery is a chase now. Loading cargo dispatches police
  from the nearest station BY ROAD, they hunt you with real line of sight, lose you behind buildings
  and search the last place they saw you, and box you in for three seconds to make an arrest stick.
  Three heat levels, reinforcements from real stations, and a wallet that is the same one the rest of
  the game uses.
- **The load changes the car.** Weight and fragility are separate: a heavy container is slow away and
  long to stop, a pallet of glass does not care about weight and cares a great deal about kerbs. The
  modifiers come off exactly on every ending — delivered, busted, wrecked, abandoned or quit.
- **Roads have lanes.** Two, three (with a real central turning lane) or four, with width derived from
  the lane count, bridges as wide as the road that crosses them, fourteen police stations, safe arrival
  points and eight ramps that use the real airborne physics.
- Measured: the regional loop takes **599 s** in the stock Sport with no boost. Frame time on the
  highway with four other cars is 3.1 ms average against a 16.6 ms budget.
- Delivery is entered straight from the menu now — it is a one-car mode, so it no longer asks.

## 0.13.7 — 2026-09-28

- **A wreck goes off, and what is beside it pays.** Blowing your car up -- on purpose with F, or by
  finally losing the tank -- now damages and shoves the cars around it, straight through their panels.
  Bodywork is armour against another car, not against a bomb. It is the first thing in the game that
  lets one driver end another's race deliberately, and it costs you your own car to do it.
- **A sixth garage slot: the charge.** Stock tank goes off about a car's width. Scatter charge reaches
  two and a half times as far and marks a whole group. Shaped charge barely reaches past the bodywork
  and kills outright what it touches. Armed tank has half again the reach and bite, and a tank that is
  far easier to set off.
- Measured rather than guessed: cars in a race run 29 px apart at the tenth percentile, cars in the Pit
  347 px, so the blast is a race weapon that pays off in the arena only when somebody is leaning on you.
  A scrum of four round a wreck never chain-reacts.

## 0.13.6 — 2026-09-28

- **You can see what speed you are asking for.** The rope's length has always been the speed demand, with
  nothing to read it against -- 130 px out of a possible 180 looks the same as 130 out of 400. The game's
  six-speed gearbox is now drawn where the eye already is: as pips behind the cursor, lit up to the gear
  the rope is pulling for, and as one mark on the rope at the top of that gear, which is what you aim
  back to when easing down. The gap between the pips and the gear on the dashboard is the acceleration
  you have been promised but not yet given.
- Nothing about the rope's physics changed, and the rope is not shorter.

## 0.13.5 — 2026-09-28

- **F writes the car off again, and the game says so.** Self-destruct is back after SPEC 128 removed it,
  as one thing rather than the five notices it had grown into: a chip in the top-right corner, under the
  minimap, on screen for the whole race. It names the key even while it is refusing -- that is its job,
  a control nobody knows about is not a control -- and it is a real button as well, because there is no
  keyboard on a phone. It works once the car is half broken or on two rims, and once every 30 s; it
  costs exactly what a crash costs, the same wait and the same respawn repaired at the last checkpoint.
- **Things break in the arena.** Bodywork and vitals both, with no switch to turn them off: panels come
  off, tyres burst, cars roll, and a car whose tank goes is OUT -- it keeps its score, loses the run it
  was carrying, burns, and comes off the floor. The mode is built on shoving, and shoving that leaves no
  mark is a mechanic with no stakes.
- **Two things measured rather than guessed, over six real matches.** An arena engine can now be worn
  but not killed: at first, two cars in every single match lost the engine before 1:10 and spent the
  rest of it unable to perform -- silently, which is worse than a wreck. And a knock on the floor costs
  half what the same knock costs on a circuit, because three minutes of deliberate ramming is a very
  different dose than a race. The result is one wreck at 2:46 with everybody else finishing battered,
  instead of two cars out by 2:05.
- The arena strip gains a DAMAGE readout -- zoomed out to fit the map, a car is 36 px and a missing wing
  is two of them.
- Self-destruct is deliberately not in the arena: with no respawn there, the key would just mean "quit".

## 0.13.4 — 2026-09-27

- **The cars on the grid really do face the right way now.** They were being drawn from a picture taken
  before they were placed -- a car held for the countdown is only drawn once, and its model renders a
  frame later -- so the whole field sat pointing east until the lights went green and the redraws
  started. On a circuit that starts westward, like the Circle, that looked like every car flipping
  round at GO. Reported three times before I looked at the right thing; the two previous attempts
  measured the heading and the pose, which were correct all along.

## 0.13.3 — 2026-09-27

- **The car no longer spins round the moment the lights go green.** It was never facing the wrong way:
  the grid is correct on every track. What happened is that the race handed the car straight to the
  mouse pointer, wherever it had been left -- and on a circuit that starts westward, a pointer sitting
  in the middle of the screen is a rope pulling back down the road, so the car whipped round to follow
  it. Until you actually move the pointer, the rope now points down the road ahead of the car; the
  first touch of the mouse hands it over and keeps it.

## 0.13.2 — 2026-09-27

- **The notes along the bottom of a race are gone** -- LAP NOT COUNTED, 2 FLAT TYRES, STEERING BENT and
  the rest. Every one of them told you something you had just done and could already feel through the
  car. The one warning worth keeping stayed: when a car is genuinely wedged, it counts down before the
  game picks it up, so you can drive off and cancel it.

## 0.13.1 — 2026-09-27

- **The Switchback's grid faced back down the circuit.** Its start straight runs east to west, so every
  car lined up pointing off the left of the screen and then spun round at the green light. The lap now
  starts further round the same road -- facing east, on a straight, with the first gate dead ahead. Not
  a corner of the circuit moved; only the start line did.
- **The help pages have room to breathe.** The lines were packed tight enough to be a wall; they have
  half again as much air, and the column scrolls so nothing had to be cut to make it fit.
- **More inertia still.** Holding a short rope now carries the car nearly twice as far as it did before
  any of this (1259 px against the original 693), and a hand that stops moving leaves it rolling instead
  of stopping. Dropping the cursor on the car still stops it exactly as hard as it always did.
- The rivals were retuned to match: they plan their braking against what the rope can actually deliver,
  the careful ones brake earlier, and the Grand Tourer -- the heavy car, worst hit by a rope that cannot
  brake down a straight -- got bigger brakes. Three different cars now win a track and none is more than
  6.7 % off the pace.

## 0.13.0 — 2026-09-27

- **The rope has slack in it, and it cannot brake you.** It used to set a speed and hold the car to it
  exactly, so a hand that stopped moving was a hand on the brakes -- the car ran up to the cursor and
  stopped dead. Now there is a range of rope length over which the car simply keeps what it has, and a
  rope pointing straight down the road does not slow you at all. Holding a short rope carries the car
  half as far again as it used to. Dropping the cursor onto the car still stops it exactly as hard.
- **A figure eight and a long slide were impossible.** Not hard -- impossible: the game's own teacher
  could not land either in fourteen seconds of trying. A pair of donuts forgot the first one if anything
  at all happened in between, and a slide's distance was wiped by a single frame of grip. Both fixed,
  and all five lessons now demonstrate comfortably.
- **The training says what else is out there.** It teaches five tricks and the mode scores thirteen; the
  card at the end names the other eight and what they pay.
- **The arena is bumper cars again** -- BODYWORK: BREAKS is gone, and so is the hot zone.
- **The track preview shows the track**, not the empty world around it; the Switchback no longer draws a
  quarter of itself as grass.
- **The arena rules turn pages** instead of running off the bottom of the screen, and a race's pause menu
  has the same buttons as an arena's, including Rules.
- Wheels you fitted in the garage now appear on the car-select screen. The garage's part description
  scrolls instead of covering the BUY button. BACK and SPRINT N LAPS no longer overlap. The track screen
  has stopped reciting your star bookkeeping, your best lap and a complexity rating at you. The title
  screen no longer prints its own changelog next to the What's new button. "THE STUNT MATCH" no longer
  sits on top of the line beside it.

## 0.12.9 — 2026-09-27

- **Being shoved is no longer treated as being stuck.** The new automatic recovery would lift a car out
  when a rival had it pinned against a barrier and set it back on the racing line -- a free escape from
  a legitimate block. Only a car nobody is touching is freed now, and you get a countdown first, so you
  can drive off and cancel it.
- **A boost for the pass you made, not the one you shoved.** Knocking the car ahead off the road and
  taking its place used to pay a boost, which made the next shunt easier. A pass made clean pays; one
  made through somebody is still a place.
- **The trick economy, measured and rebalanced.** Running a wall paid 78 points a minute for ordinary
  racing; a violent weave was being counted as a J-turn; and the same flick was paid twice, once as a
  slalom and once as a drift switch. Now: plain driving pays nothing, racing hard pays 38 a minute, and
  performing pays 114-144. Racing is not a way to score and scoring is not an accident.
- **The hot zone moves.** It opened dead centre every time, so after the first one it told you nothing.
  It now opens somewhere new, announced three seconds ahead with a marker -- and the rivals go to it,
  so the biggest pots are still where somebody is most likely to clip you.
- **A real two-client session** (`tools/two_clients.sh`): a dedicated server and two clients as separate
  processes, failing on any script error, any RPC to a peer that is not there, or the two of them
  disagreeing about the result. Everything the suite knew about multiplayer it had learned from one
  process talking to itself, which is how the broken arena packet shipped. It found a bug on its first
  run: the room's "who leads this" line had never once shown a name.

## 0.12.8 — 2026-09-27

- **Damage you can see.** A car limping on three wheels and a hub was still drawn with four round
  tyres: the physics has known what is broken since 0.12.3 and the model never did. A buckled corner
  leans and sits low, a missing one drops onto its hub, panels come off, and a car you are racing
  against online looks like whatever has happened to it.
- **Eight more ways to be broken, each a different problem.** A bent wheel wanders. A collapsed corner
  has no spring left. Loose bodywork rattles and drags. A rubbing wing eats its tyre. A holed radiator
  costs nothing until you hold it flat, and then the power fades until you back off. A hurt drivetrain
  takes the top end. A bent chassis dog-tracks -- it turns better one way than the other. A torn rope
  mount leaves the engine fine and the rope unable to use it.
- **You can pull yourself out of the grass.** The crawl off the road ignored the rope completely, so a
  short pull and a full-arm haul got you out at exactly the same speed. Hauling is worth 2.3x the crawl
  now -- still a fifth of road pace, so the grass costs what it always cost.
- **No more blowing your own car up, and no more pit stops.** Scrapping the car traded a bad race for a
  wait, which is a menu decision wearing a key; rivals did the same on a timer. A hurt car limps home
  instead -- a dead engine still turns the wheels, and only the fuel tank ends a race. A car genuinely
  wedged in the scenery is lifted back onto the road by itself, with no explosion and no reward.
- **Nine more tricks.** A DRIFT SWITCH, a SLALOM, a PRECISION STOP on the cursor and an ORBIT TRANSFER
  between two anchors; and, against the scenery, a J-TURN, THREAD THE NEEDLE, a WALL SKIM and a SAVE --
  the only trick you are paid for not crashing. The tally shows what you have landed plus the next
  three to try, rather than thirteen names down the side of the screen.
- **Grades that mean something, in every car.** Every trick is graded C to S and the grade decides what
  it pays -- a C pays what the trick used to be worth and an S pays double, so a scruffy attempt lands
  instead of being refused. Checked in all five cars with a circle drawn the way a hand draws one.
- **Online arenas were not scoring at all.** The score packet still carried numbers deleted in 0.11.6,
  so the scoring tick crashed four times a second -- taking the clock and the hot zone with it. A
  breakable wall opened only for the driver who broke it, because the server checked the wall's number
  as if it were a car's. Both fixed; `Net.PROTOCOL` is 7.
- **The keyboard can get around the lobby**, and a card that covers the screen takes the keyboard
  instead of leaving it on the buttons underneath.
- **Faster.** The car's damage was recomputed from scratch eight times a sub-step. The figure-eight
  frame average is 0.62 ms, down from 1.50 ms -- quicker than before any of this was added.
- Includes the 0.12.7 grading round: every trick graded, the thresholds relaxed, a coach's hint on a
  loop that paid nothing, and the "-33000000 m" gap readout fixed.

## 0.12.6 — 2026-09-27

- **A wall you can drive through.** On the Switchback, a barrier across a service road between the two
  legs of the descent. Hit it hard enough and it goes -- it costs you 42 % of your speed, once -- and
  the route it opens is about nine tenths of a second a lap faster, for everybody, for the rest of the
  race.
- **A repair lane.** Stop properly in the marked bay and hold the car still, and the bodywork is
  straightened and a lost wheel goes back on. Leaving early loses the progress: it is a decision to
  give up the time, not something to nibble at.
- **The results card says what you survived** -- "FINISHED on 3 wheels, 2 panels gone" -- and pays
  nothing for it, because anything that pays for damage is a thing to farm.
- **BODYWORK: BREAKS**, on the arena screen. The same floor, the same tricks and the same clock with
  the panels able to come off. A separate choice; the ordinary stunt arena is untouched.
- **Free practice.** Take the rivals down to none: the same floor and the same scoring with nobody to
  bump you and no clock. It pays no coins and sets no record.
- **Reduce shake and flashing**, in Settings. A quarter of the camera shake and an announcement that
  holds still -- and every warning, chip and status line exactly as it was.
- **Multiplayer**: a wrong password is fixed inside the dialog that asked for it, which now names the
  room; the room list says whether a room is racing or doing stunts; a guest is told who the leader is
  and what is set instead of seeing dead controls; chat names are readable whatever colour the car is;
  the results buttons say "Back to room" and "Leave multiplayer"; and the feedback card no longer
  claims a delivery the browser will not confirm, and shows how much room is left to type.

## 0.12.3 — 2026-09-27

- **Cars come apart where you hit them.** A prototype on the Sport, in races: eleven named components
  -- four wheels, two bumpers, a bonnet, four wings -- each of which bends, works loose and finally
  comes off. A front-corner crash dents that corner and nothing else; two harder ones take the wheel.
- **And they drive like it.** A buckled wheel sits at an angle and has half its grip; a wheel that has
  gone leaves the hub scraping on the road -- sparks, a hard pull that way, and about a third of the
  car's pace. A bent wing rubs its tyre; an open bonnet is drag and an exposed engine.
- **Bodywork absorbs instead of granting extra lives.** A bumper that is still on takes most of a blow
  and passes the rest through; one that has been knocked off passes all of it.
- Nothing breaks in the stunt arena or the training, and nothing changes for the other four cars.

## 0.12.2 — 2026-09-27

- **The car stops shrinking.** Hitting a wall in the training (or pulling hard in an arena) dropped the
  car to race size and left it there. Everything that changes how big a car is drawn now multiplies
  together instead of overwriting.
- **One button that works.** A new profile arriving at the arena list used to find a greyed-out LEARN
  with the real action hidden beside it. The big button is START TRAINING, and it is enabled.
- **The game says what it does.** Contact does not take your points -- it breaks the trick and holds
  the bank. Tricks ADD their points; a different trick raises the multiplier. Overtime is decided by a
  bank that takes the lead. Colours are free. The Formula is not the fastest or the lightest car. A
  race has no reverse. A solo run is a TIME TRIAL and says what it pays. Escape no longer starts a
  match, M no longer toggles anything, and nothing says "fight" any more.
- **BANKED, PENDING and your next multiplier**, on the screen under your car, with a bar for the bank
  timer that turns red when the bell will get there first. The trick announcement is on the screen too
  -- it used to be painted at the middle of the map, which the camera often is not looking at.
- **Why that loop did not count.** "Too wide -- make the circle smaller", "not all the way ROUND the
  cursor", "keep the rope the same length": the detector's own reason, in the training, when it has one.
- **The training has four buttons**: watch again, restart the lesson, skip THIS lesson, and leave.
  Skipping one no longer claims you have learned all five, and the demonstrator drives your car rather
  than a different one with different handling.
- **Warnings that stay up.** A snapped rope, a flat, a bent rack, a dead engine and a lap that will not
  count each get a small chip along the bottom saying what to do about it, for as long as it is true.
  PRESS F TO DESTROY is RESET CAR [F].
- **The rope has inertia going in as well as out.** Catching up to the cursor no longer yanks the car
  to a halt; the rope hauls you back like a rope, not like a brake disc.
- **Bent steering behaves.** It pulled harder and harder the longer you drove instead of holding a
  fixed offset.
- **Leaning on somebody stops working.** A car that parks against you used to hold you to nothing at
  all. After a couple of seconds the contact stops counting against you and your car shoves them off --
  an ordinary bump is completely unchanged.
- **Catching a long slide** is called out, and **three different tricks in one run** pays a bonus.
- **Multiplayer**: the room list says whether a room is racing or doing stunts and its rows fit the
  panel; the leaderboard's points column is on the screen; connecting and reconnecting get a card that
  says where to and offers CANCEL, instead of a blank screen.

## 0.12.1 — 2026-09-26

- **The rope has inertia.** A slack rope is not a brake pedal: bring the cursor inside the slack circle
  at speed and the car coasts instead of standing on everything it has, and catching the cursor no
  longer yanks the car to a halt. Dropping the cursor on the car is still a full stop -- that is the
  brake, and it works exactly as it did.
- **Pull too hard and the car FLIES.** Past a certain over-pull the wheels leave the ground: no grip,
  no steering, no marks, no dust. It goes where it was already going and the rope is the only thing
  acting on it. A hop lasts about a second and then it comes down with a bump, so dragging a car flat
  out is a series of leaps -- and every landing costs rubber off all four tyres.
- **The figure eight is an eight.** The training and the rivals used to demonstrate it by driving the
  same circle backwards; they draw two circles now, crossing between them. And one frame of wobble no
  longer throws a whole loop away, which is why the hardest trick in the mode so often did not count.
- **Two circuits rebuilt.** The Switchback's descent switches back through the middle of the mountain
  instead of dropping down the east edge, and the Serpent's top edge plunges twice to the middle of
  the world instead of dipping three times. The biggest patch of ground the road never reached: 13 %
  to 8 % on one, 19 % to 10 % on the other.
- **Trees you can hit.** Bigger, fewer and properly built -- a trunk, a faceted crown and three lit
  faces instead of two green blobs -- and solid. They stand two car widths back from the road, so a
  tree is something you hit by getting it wrong, not something waiting at the edge of the tarmac.
- **Tony Hawk.** The trick you just landed is shouted across the middle of the screen: the name, what
  it paid and the chain it is on.
- **The arena floor grows with the field.** Two cars get the floor as drawn; every car after that adds
  room, so eight of you are not all drawing circles in the same spot.
- **It is a STUNT, not a fight** -- on the button and on the briefing card, where the old word had
  been sitting since the fight was deleted. And the arena screen no longer shows a map of a floor
  that is a plain rectangle either way.
- **PRESS F TO DESTROY counts down** while it is cooling, instead of showing nothing at all.
- **The multiplayer room:** START RACE fits, the leaderboard sits between the players and the chat,
  and there is no picture of a circuit taking up the room.
- **Names stop at 16 characters** everywhere, and the field says so.

## 0.12.0 — 2026-09-26

- **Two arenas: the Box and the Circle.** The round one is round for the cars too -- the rail is a
  circle, with the bumper bent round it -- and it suits the mode better than corners do.
- **The training.** The first visit to the arena teaches all five tricks, one at a time: the computer
  drives one with its cursor drawn as a ring you can follow, then it is your turn, and the lesson
  waits until you land it. The arenas open when the five are done; SKIP opens them for anybody who
  already knows.
- **No more M.** The music key is gone -- the volume slider in Settings is the only control.
- **Five circuits, wearing scenery.** Trees, copses and rocks fill the ground the road leaves empty
  (the Serpent's middle, the Switchback's far side). None of it is solid: a tree is not a wall.
- **The rope leaves the track alone.** It no longer flicks cones about or snags on tyre stacks -- the
  car hits what it drives into, and the rope is a line between your hand and your car.
- **The track list, readable.** The medal and the stars no longer sit on top of the lap times, and the
  stars are big enough to see -- gold for a win, a grey outline for one still to come.
- **PRESS F TO DESTROY**, at the top of the screen, as a button you can click, instead of a line in
  the corner that only a touch screen ever showed.
- **How to play, in three pages**: RACE, ARENA and MACHINES -- the last of which finally says what the
  five cars, their tyres, their damage and their parts actually do.
- **One margin.** Every button is built to the same padding and the same minimum height, and every
  Back button on every screen sits in exactly the same place.
- **The multiplayer room, rebuilt**: players and the leaderboard on the left, the chat filling the
  right, the race setup in one wide panel below -- and no AI rivals in a room. The room browser is
  just rooms now; the leaderboard belongs where the players are.

## 0.11.7 — 2026-09-26

- **The arena is a stunt show, and only that.** No damage, no wrecks, no repairs, no pickups, no
  people, no props, no coins -- and no ring of fire closing in, no rounds and no sudden death. Cars
  shove each other like bumper cars, nothing breaks, and the clock is the only thing that ends a
  match: three minutes, most points wins. Touching somebody still ends both runs where they are, but
  nobody takes anybody's pot any more.
- **The rivals are stunt drivers.** They have nothing to hunt: no prey, no leader to pull down, no pot
  to steal. They find a patch of floor and perform, and every one of them scores.
- **The tricks, down the left of the screen.** All five of them -- DONUT, DOUBLE, EIGHT, ORBIT, SLIDE
  -- with what each is worth and how many you have landed. The ones you have not done yet are dim: the
  column is the list of what there is to do as much as the count of what you have done.
- **Help that says how.** How to play gains a stunts section: what each trick is, what it pays, and
  that a donut comes from swinging the cursor in a circle. The briefing before the first match says
  the same. A trick that is not explained now fails the tests.
- **A chain wants variety.** Landing the same trick again pays, but only a DIFFERENT one steps the
  multiplier -- one long drift used to hold x6 for a whole match. And a long slide is a long one now.
- **Music with the lights on.** The arena's tune was written to sound like trouble (phrygian dominant,
  168 BPM); it is A major at 160 now, with a riff that climbs.
- **Every circuit is open, and wins are stars.** The unlock ladder is gone: all five tracks can be
  raced from the first minute, and winning puts stars on one -- 1 for easy, 2 for medium, 3 for hard,
  shown on the track screen where the padlock used to be.
- **Five circuits, not twelve.** Seven of them were near-twins by length, corner count and tightest
  corner (a table of all twelve is what decided it). What is left is one of each kind: **Circle** to
  learn on, **Figure 8** for the bridge, **Neon Harbour** for the corners, **Switchback** for the
  hairpins, **Serpent** for the six screens of bends.

## 0.11.5 — 2026-09-26

- **The arena is a stunt arena now.** There are no coins anywhere: on the floor, in a wreck, in the
  rain, in the score. Everybody starts on nothing and scores by DRIVING -- a **donut**, a **double
  donut**, a **figure eight** (one donut each way, without stopping), an **orbit** all the way round
  your own cursor, and a **long slide** that pays again the further you hold it. A donut drawn evenly
  pays a precision bonus.
- **The rivals are stunt drivers, not wreckers.** Performing is their job: they pick a patch of clear
  floor, swing their cursor round it and draw the same tricks you do, judged by the same watch. They no
  longer hunt the car that is nearly out or the car in front -- the only reason left to drive at
  somebody is the pot they are carrying, and a driver with no room to work goes and finds some.
- **A run is not yours until it banks.** Tricks go into a **pot** over your car that multiplies while
  you keep landing them, and becomes score after three seconds of not landing one. Touching anybody
  ends the run; a real bump hands your whole pot to whoever landed it. Stopping somebody else is now
  the most profitable thing on the floor, and carrying a big pot across it is the hardest.
- **Wrecks move score, not coins**: half of what you have banked goes to whoever wrecked you (nothing
  at all to a wall, the fire, or your own SCRAP). Streaks multiply tricks; sudden death is tricks x3;
  the WRECKER arrives already on the board. Coin rain is now a **hot zone** -- a ring in the middle,
  announced three seconds ahead, where every trick is worth double for fifteen seconds.
- **On screen**: the pot over every car carrying one, a ring under the car that closes as the loop
  comes round, POINTS on the instruments and the board, your run (pot, multiplier, seconds to bank) on
  the status line, and a card that counts your tricks, your best one and what you took off other people.
- **What this build is, on the title screen.** Above the What's new button, one muted line of the
  current version's headlines -- tap it and the full notes open. The build number is still in the
  corner under it; now something next to it says what the build actually brought.
- **Multiplayer protocol 5.** The stunt arena changes what the wire carries, so a 0.11.5 game and an
  older server refuse each other; the server needs the new build.

## 0.11.3 — 2026-09-25

- **What's new, in the game.** The release notes ship with the build and open from the corner of the
  title menu (and once by themselves the first time a new build runs): every version, what it added
  and what it took away, newest first.
- **The room, tidied.** The chosen track's map sits beside the players list instead of floating in the
  middle; the chat runs the whole width under both; the 5-4-3-2-1 countdown has a card of its own
  instead of being drawn over the settings.
- **The version counted in tens**: 0.11.3 is SPEC 113 (the middle number moves every ten sections,
  the third within the ten; a fourth number only for a fix). 0.112.0 was the last of the old shape.

## 0.112.0 — 2026-09-24

- **Feedback that lands in the form.** A FEEDBACK card -- a rating, Bug / Suggestion / General, a few
  words, SEND -- from the title menu's corner button, the pause menu and the results card. It posts to
  the game's Google Form without leaving the game, with the version, your name and where you were
  added on; a send that fails is kept and goes with the next launch. `tools/send_feedback.gd` posts
  one entry from the command line.
- **Deploying from the GitHub image**, step by step, in the README; the server's data volume
  (`rope-racers-data`) keeps the leaderboard across deploys, and the image is built so the volume is
  writable from the first start.

## 0.111.0 — 2026-09-24

- **Which way.** Chevrons on the road ahead of the car through the countdown, the first seconds and
  after every respawn; WRONG WAY said and shown when you drive against the track; a big arrow back to a
  checkpoint you went past without taking it (MISSED CHECKPOINT), so a missed gate costs a detour, not
  another lap; an arrow to the road after a while on the grass.
- **The tower** says nothing for a car on the leader's lap and "-1 LAP" for a lapped one (no more
  "L1 / L2"), and shows the top five and you.
- **SCRAP READY - press F** on the strip while scrapping is offered; a SCRAP button on touch screens.
- **Every colour is free** from the start.
- **One screen at a time.** The results card clears the tower, the map and any flash from under it;
  the overlap audit now sees the tower and the map and checks every race screen (two collisions found
  and fixed: the respawn line under WRECKED!, the big word under the pause menu).
- **Two more circuits**, as different as they come: the **Switchback** (a ladder of hairpins up one
  side of the mountain, a sweeping descent down the other) and the **Blocks** (the docks: every corner
  square, a bus stop, a double-apex 180 and the longest straight in the game).
- **Multiplayer**: chat in the room; change your name in the room; START counts 5-4-3-2-1 for
  everybody (the leader can CANCEL); remote cars move as smoothly as the bots (sender-stamped
  packets, an adaptive delay); five standing rooms on the official server (Arena 6, Arena 4, Race 3,
  Race 5, Race 6) beside the rooms you create; a **leaderboard** -- 10/7/5/3/2 points a race, 1 for
  finishing, kept for ever on the server and shown in the lobby, with your points on the results
  card. Protocol 4: this build does not race with older ones.
- **Draw your own circuit, with things on it.** A `MapTrack` scene now takes `MapBlock` buildings
  (solid, the rope bends round them) and `MapProp` cones, tyre stacks and oil drums; automatic cones
  can be turned off; the road, the start line and the direction are drawn in the editor;
  `scenes/tracks/_template.tscn` is a finished example to duplicate. `docs/MAPPING.md` part 2 is the
  guide.

## 0.110.0 — 2026-09-24

- **The camera rides again**, and a track for it: the Serpent, six screens of bends. Every race
  starts riding with the car, cars their own size; the whole-track view is the wheel's last step.
- **Sprint laps**: four of a short track, three of a long one, two of the Serpent; ENDURANCE on the
  track screen races the full ten.
- **The drift charge in tiers** — blue, orange, purple on the rope and the rear wheels, with a rising
  tone; a click spends what is charged. Near misses and overtakes top it up.
- **Honest catch-up** for rivals behind you, capped under your speed, with the GAP on the dashboard.
- **The bump is the score.** Hard hits knock coins out of the victim; spins pay 2/4/10, doubled on the
  leader, chained when quick; the same spins pay a purse in races. Stripped cars fly further; sudden
  death starts everybody one hit from the end.
- **Stretch and squash**, an engine note that follows the speed, and an engine sound in the arena.

## 0.109.0 — 2026-09-24

- **A frame that holds.** Measured on a mobile-class laptop: process time down 31 % in the arena and
  33 % in a race (48 and 42 fps at the cap → a flat 60; 183 and 204 uncapped), and the two feedback
  loops that turned a dip into a spiral are gone — every redraw happens once per drawn frame instead of
  once per physics tick, and the audio is prebuilt WAVs instead of per-sample synthesis (3.8 ms a frame
  → 0.03). Debris, decals, effects, skid marks, props and the HUD draw from baked meshes; car physics
  samples the ground once per tick; a slow device now dilates time instead of spiralling.

## 0.108.1 — 2026-09-23

- **The SCRAP button is gone.** F scraps the car.

## 0.108.0 — 2026-09-23

- **The dashboard, the way racing games do it.** Instruments across the top (POSITION, LAP, LAP TIME,
  BEST LAP; in the arena COINS, PLACE, ROUND, BELL IN, TIME LEFT) and the running order as a timing
  tower down the left, naming the car with its colour as a chip. The world is fitted into what is
  left, so nothing covers the track.
- **Rivals scrap too** — on a dead engine, two rims or past half damage, as a player would — so
  damaging them and scrapping yourself is no longer a trick only you can pull.
- **SCRAP is F.** The button is for touch screens; the help and the brief say so.
- **The Rally grips a little more** (it had lost its edge with the cold tyres); medal times re-measured.

## 0.107.0 — 2026-09-23 (not released)

- **The dashboard.** One strip across the top with the running order as chips, the clock, the pause,
  the lap and times (or the round and the bell) and the status words; the world is drawn under it, so
  nothing covers the track any more. The flash and the hint sit under the strip.
- **The oasis is out.** The Pit is the arena.
- **The chase view is out** (played and dropped): no VIEW button, no V, no behind or front camera, no
  wheel controls. Top-down on the rope, as before. The big-car one-screen races stay.
- **The rope is drawn from the nose in races too** (it started in the middle of the car); it still
  pulls from the centre, so the AI and the medal times are as they were (re-measured).
- **No more cold tyres.** Every car starts on warm rubber; the COLD TYRES warning is gone.

## 0.105.0 — 2026-09-23

- **Behind the wheel there is no rope.** In the chase view (arena and race, online too): left button
  gas, right button brake (then reverse in the arena), the cursor across the screen is the wheel,
  middle button or Space is the boost. The rope is not drawn. TOP brings the rope back.

## 0.104.0 — 2026-09-23

- **The chase view.** In the arena and in a race, the VIEW button (or V) puts the camera behind your
  car, then in front of it, with every car's real 3D model standing on the floor: wheels, panels,
  dents, the engine in the hole. The cursor still drives the car. TOP brings the top-down view back.
- **One-screen tracks are presented like the Pit.** Every track but the town starts with the whole
  circuit on screen and the cars 1.7 times as big -- a Micro Machines race. The wheel still zooms in.
  The medal times were re-measured.

## 0.102.1 — 2026-09-23

- The "NOSE BARE" / "TAIL BARE" flashes are gone. The car's bare metal says it.

## 0.102.0 — 2026-09-23

- **Vitals.** Bodywork is armour, the engine and the fuel tank are the life. A hit on a zone that still
  has a panel takes the panel and costs no life; a hit on a bare nose reaches the engine, on a bare
  tail the tank. Nothing that cannot reach a vital can wreck a car.
- **Ride the wreck.** A dead engine is not a wreck: the car limps at 30 % drive, smoking, still in the
  fight, and you decide — ride it, or SCRAP. Only an empty tank is the wreck. Rivals limp, then scrap.
- **The rivals aim for the weak spot** — an open zone or a dead engine makes a car prey.
- The brief and the help say it: "Panels first. Then the engine (bare nose) or the tank (bare tail)."

## 0.101.0 — 2026-09-23

- **Racing is back.** After one arena, every press of Race led to the arena picker (the mode never
  reset). The Race button leads to the car, then the tracks, always.
- **The machines are stronger.** Two cars pressed together were charged for the contact on every
  frame; now a pair is billed once per 0.6 s, and each bill is smaller. A fight lasts.
- **A wreck is debris, not a shell.** No more solid burnt-out cars piling up: a destroyed car bursts
  into pieces that lie where they fall, leaves a scorch and burns for six seconds.
- **SCRAP in the arena** — past half damage or on two rims, the SCRAP button (or F) wrecks you and
  brings you back on four tyres; half your coins drop like any wreck.
- **The arena preview** shows the map exactly as it plays: no zone squares, no spawn dots.

## 0.100.0 — 2026-09-23

- **The Pit** — a new default arena (1440x810) that fits on one screen, like a bumper-car carousel:
  the camera holds the middle, every rival is always in view, the cars are bigger and slower on it, the
  edge is a rubber rail that bounces you back (and barely hurts), the floor is steel plates with a
  striped bumper, the last ring is smaller. Maps bigger than the screen (the oasis) still scroll.
- **The damage doll is gone** (it overlapped the interface); scrapping a car in a race is a SCRAP
  button that appears only when it is worth it (F still works).
- **The arena screen previews the real map** — its ground, sand, grass, props — the way the track
  screen renders a track.

## 0.97.0 — 2026-09-23

- **Oil that looks like oil.** Slicks are splatters (blob, sheen, droplets) instead of concentric circles;
  a hurt car drips a trail of oil that stays on the road and pools into a small slick where it lingers.
- **Grass and sand no longer damage the car** (body or suspension); they still shake it, slow it and wear
  the tyres, gently.
- **Same damage effects in both modes**; a race keeps 320 pieces of debris on the track (was 120). The
  health bar over the car is gone — the damage doll replaces it.
- **The interface, audited**: `UiAudit` + `tools/check_overlaps.gd` + `tools/shoot_screens.gd` + a suite
  check that no text overlaps or is clipped on any screen. Fixed: the track screen's clipped level line
  and cramped rows, the car screen's description, the arena screen's subtitle, the briefing's start line.
- **A clearer HUD, from three reviews.** Clock top right; round + bell panel with a bar under the board;
  the doll under that; the status line keeps only SUDDEN DEATH / SHIELD / DOUBLE / STREAK. Coins are a
  "+1" off your car instead of a banner; banners have priorities; the bell puts ROUND n in big letters.
  The doll is the scrap button (TAP TO SCRAP; F still works) — no more "Press F". Bigger pause, board,
  card buttons and arena-screen buttons; a FIGHT button on the briefing; captions 16 px; Quit hidden
  on phones; "Fight again" / "Arenas" labels in the arena; every lobby and settings control 44 px tall.

## 0.95.0 — 2026-09-23

- **The damage doll**: your car schematically in the bottom-left corner of both modes (MechWarrior /
  Doom style) — four body panels, engine, steering, four wheels on a green-amber-red-black ramp, holes
  where panels came off, a red cross on a burst tyre, and what is left as a number.

## 0.94.0 — 2026-09-23

- **No mods, no cards.** The round bell no longer deals stacking mods on a pick card (played and
  disliked); the mod unlocks and their feats are gone with it. The rest of the run stays: fixed pace
  (10 + 2 coins per car, or 45 s), the bell as a moment, THE WRECKER in round 3, double damage from
  round 4, OUT in sudden death, coins inside the ring, the briefing once, the one-second rematch, the
  boost arc, the card with a best per arena. The briefing's second picture is the ring closing.

## 0.93.0 — 2026-09-23

- **Arena: the run.** Every round bell deals three stacking mods (ram plate, magnet, big tank, nitro,
  heavy, spikes, greed, slicks, thick skin, afterburner, scavenger) — pick one, it is bolted on and
  drawn on the car. Rounds are a fixed pace (10 coins + two per car, or 45 s; dropped coins don't count), the
  status line counts down to the bell, the ring's next stop is drawn dashed, the round's winner keeps
  a star, THE WRECKER enters in round 3, damage doubles from round 4, round 5 by coins is capped at
  45 s, wrecked in sudden death you are OUT (no spectating), and coins keep inside the ring.
- **Arena: the card.** Best per arena / skill / field, NEW BEST, rounds won, your build, what the fight
  unlocked and what the next one would; the payout scales with rival skill and says what it is for.
  Six mods unlock by playing (rounds won, wins, survival, coins carried) — never by logging in.
- **Arena: the restart.** The briefing is read once (Rules in the pause menu), "Race again" counts
  down from one, the boost meter is an arc on your car.
- **Arena briefing pictures** (`art/help/arena_*.png`, from `tools/make_arena_art.gd`).
- **Multiplayer arena.** Rooms have a MODE (race / arena); the server's arena is the authority on
  coins, rounds, the ring and the end, cars are their owners' puppets everywhere else. Protocol 3.
- Damage decals are baked once per change instead of rebuilt every frame.

## 0.90.0 — 2026-09-22

Damage you can see (SPEC 90).

### Fixed
- **Lost panels now fly off, land, and stay on the ground** in the car's colour. The signal existed;
  the arena had it connected to nothing.
- **The car wears its damage**: a jagged hole with a bare-metal edge for every panel lost on that side,
  scratches from 30 damage, scorch from 65 — drawn on top of the model, which had been hiding
  pixel-sized meshes and calling it destruction.
- **The smoke ladder**: white from 30, black from 55, bonnet fire from 80 — twice the size, scaled with
  the car. It was one faint wisp from 35.
- **The ring closes every round**: round two's ring is the circle inside the map, not the one through
  its corners (which left rounds two and three closing nothing on the oasis), and the ROUND banner is no
  longer overwritten by the coin flash in the same frame.
- `tools/shoot_arena.gd --live` runs the match at the engine's own pace and prints frame times
  (`--uncapped` lifts vsync and the fps cap; `--prof` prints timers of instrumented functions).
- **Tyres smoke before they burst**, and take three hits instead of one. Driving on the rims costs less
  speed and wobble than a race, and no longer throws fire — a limp, not a death.

### Added
- **Rounds counted in coins**: every 10 coins taken by anybody ends a round and the ring of fire closes a
  step; round 5 is sudden death. The clock still forces it in the last 30 s.

## 0.89.0 — 2026-09-22

Physics that pays (SPEC 89): the arena finally rewards what the tyre model can do. All behind the arena;
the tyres themselves are untouched.

### Added
- **Mass in the price of a hit** — what you deal is scaled by your mass over theirs (0.6–1.7×). The car
  you picked now decides how you fight.
- **The SLAM**: nose-first above 85 % of top speed is a different kind of hit — a part guaranteed off,
  1.5× damage, thrown twice as hard, and a flank hit **rolls** them. Announced and counted.
- **Hit-stop on a slam, slow motion on a kill** (70 ms / 0.55 s at 0.3×), on the real clock.
- **Boost from fighting**: a clean nose-to-flank hit is a third of a bar, a kill fills it.
- Drifting already charged the boost on circuits (SPEC 39); the arena now guarantees it never charges
  slower there than on a circuit.
- **A speed trail** behind any car fast enough to slam, and FULL SPEED on your status line, so a slam is
  never a surprise to the car receiving it.

## 0.88.0 — 2026-09-22

### Changed
- **The rope is tied to the nose in the arena** (SPEC 88) — drawn from the front bumper, and measured
  from it too, so a side-on car brings its nose round first. Circuits keep the centre anchor.
- **The leader bounty is off.** Played and disliked: it made every round a queue behind the leader.
  Kills still move half the pile.
- **No shield pick-up** — a car you cannot hurt is a car you stop fighting. Repair and double damage
  remain; respawn immunity is 2 s.
- **The AI spreads out** instead of piling into the middle when coin rain falls, and a rival caught
  outside the ring of fire heads straight for the middle rather than driving on through it.

## 0.87.0 — 2026-09-22

The arena gets an economy and an ending (SPEC 87) — the first slice of the design review.

### Added
- **Kills have names and move value.** A wreck drops **half** its coins (was a quarter); whoever hit it
  in the last 4 s gets the kill on their record and the announcement. No bonus for the kill itself:
  wrecking a car with nothing pays nothing, so the rich car is the one worth hunting.
- **A bounty on the leader**: +1 every 10 s in front, collected by whoever wrecks them. Shown over the
  leader's ring and in the status line. Leading is dangerous now.
- **Kill streaks**: three kills without dying and every coin is worth two, five and three. Dying resets
  it. Streaks multiply pick-ups, not kills — the hunter still has to collect.
- **Sudden death**: the last 30 s are coins ×3, no respawns, and a ring of fire closing in from the
  edges. A tie at the bell goes to overtime — first coin wins.
- **Coin rain**: every 35–60 s, ten coins fall in the middle of the map for 15 s, announced 3 s ahead.
- **3 s of shield after a respawn**, so a spawn kill is not free coins.

### Fixed
- `deploy/release.sh` now says, as the LAST thing on screen, when `build/RopeRacers.exe` could not be
  replaced because the game was open — a stale copy got played for two versions because the warning was
  in the middle of the export log.

## 0.86.0 — 2026-09-22

### Added
- **A briefing before every arena round** (SPEC 86): the seven things that differ from a race, on a card
  that waits for a click. The countdown starts after it.
- **Wrecks are solid and burn** for 20 seconds — cover once the fire is out, 7 damage a second while it
  is not, with "ON FIRE" on your HUD.
- **Up to ten rivals** on the arena screen (was capped by the map's spawn count).
- **The arena's own music**: 168 bpm, phrygian dominant, four-to-the-floor. The race keeps its groove.

### Changed
- **Coins flip** on the spot, twice a second, and are bigger again (radius 17 → 26).
- **Your skid marks last five times longer** (50 s). Rivals' last a race's 10 s — everyone on 50 s cost
  half the frame rate. With fade redraws throttled the scene measures 57 fps, up from 55.

## 0.85.0 — 2026-09-22

### Added
- **Wrecks stay.** A destroyed car leaves its burnt-out shell where it died for the rest of the round —
  the scoreboard of the fight, and something to take cover behind.
- **Rival skill is chosen on the arena screen** (easy / medium / hard). It had none, so every fight was
  against medium drivers.
- **Six zoom steps, 0.55 to 3.0** — nearly the whole arena, down to right on top of the car. The old
  ladder spanned 1.1 to 2.1, which was four pictures of the same thing.

### Changed
- **`downtown` is deleted.** A good map, the wrong mode: walls let a leader break away and never be seen
  again, which turns a brawl into a chase. `oasis` is the only arena that ships; anything you build joins
  it in the list.
- **Cars take another 35 % more punishment** (toughness 0.55 → 0.40) — about one death each per round.
- **Skid marks last the round** (2000 segments for you, 700 per rival).
- **`oasis` cleaned up**: no palms, no ponds, and nothing across the middle — an oasis, a pond and a
  rubble strip had been lying on top of each other and on top of the busiest coin spawn. Two oases off
  to the sides, four sand patches, two rubble patches off-centre, bare asphalt in the middle.

### Fixed
- **60 fps → 41 when the effects went in, now 55.** The ground and the leader's ring were drawn on the
  same canvas, so moving one circle re-tessellated the entire map every frame. The ground is drawn once;
  everything that moves is on its own layer. Rivals' effects sample on alternate frames at double the
  step — their smoke is scenery.

## 0.84.0 — 2026-09-22

### Fixed
- **The arena had no effects at all** (SPEC 84). It never built a `CarEffects` or a `SkidMarks` for any
  car — so no smoke, no dust, no sparks, no skid marks, no flying parts, no fireball and no burst-tyre
  puff, and a wreck was a car vanishing. Every car now gets both, wired to the same signals a race uses,
  plus "TYRE BURST" on your HUD when one goes.
- **The red wreck tint covered only 1280×720** of the window — at any other size, full screen included,
  the red stopped partway across. It is anchored to the viewport now.

### Changed
- **Cars take about twice as long to kill** (toughness 0.8 → 0.55). The damage still arrives; there is
  now time to watch it arrive.
- **`oasis` has nothing solid on it** — the four containers are gone. Nothing to hide behind and nothing
  to hit but each other and the junk you brought with you.
- **No pedestrians on open arenas** (`ArenaMap.pedestrians`). People belong in a town.

## 0.83.0 — 2026-09-22

### Added
- **A new arena, `oasis`** (SPEC 83), and the one you meet first: open asphalt, 2400×1700, with three
  oases (grass, a pond, palms), four patches of sand, a strip of broken ground, four containers and
  junk worth hitting. A town is a chase; an open arena is a fight, because nobody can break away.
  `downtown` is still there for when you want the chase.
- **`MapSurface`** — the fourth thing you can place: SAND, GRASS, WATER or RUBBLE. Each has its own grip
  and speed ceiling, none of them stops a car, and they are drawn as soft blobs whose edge is exactly
  what the car feels. Cutting a corner across the sand is now a decision.

### Changed
- **Cars are destructible again.** Toughness had gone from "explodes with nothing to watch" (1.0) all
  the way to "nothing happens" (0.24) — an invincible car is a bumper car, which is why the race felt
  better. It is now 0.8, and a panel comes off at 65 px/s of impact instead of 90, so something sheds
  nearly every time two cars touch hard. Over a minute of fighting every car ends up battered, panels
  and tyres gone, and half of them die.
- Pedestrians walk the grass on maps with open ground, and zebra crossings are only painted round
  blocks 240 px or bigger — a shipping container is not a city block.

## 0.82.0 — 2026-09-22

Six things wrong with the town, all of them the same shape: the map was busy and the fight was not.

### Changed
- **`downtown` rebuilt around six 600×600 blocks with 200 px avenues** (was a 5×4 grid of 300×212). You
  now have somewhere to drive: 10–12 k px covered a minute instead of 5–7 k, stuck 7–12 % of the time
  instead of 12–20 %, and 11–13 coins each instead of 5–9.
- **Street furniture cut from 265 to 66**, all on the pavement. One memorable thing per street beats
  forty forgettable ones.
- **Cars take four times the punishment** (SPEC 82) and shed a piece at **ten** thresholds instead of
  five, so a car visibly loses most of itself before it dies — and the status line names your condition
  (DENTED / BATTERED / CRITICAL). Two cars shed all ten panels and burst three tyres in a minute of
  fighting without either of them dying.
- **Debris is made of its material**: wood splinters lying the way they flew, glass shards, bent steel,
  litter, crumpled panels — flat on the road with shadows, scattered in a fan rather than a ring.
- **The rivals actually compete**: each goes for the coin it can reach *first*, gives up on one somebody
  else will clearly win, presses harder when contested, and the whole field hunts whoever is 3+ coins
  ahead. A gold ring marks the leader, and you are told when somebody beats you to a coin.

### Fixed
- **Pedestrians walked in the road.** `_walkable` allowed anything that was not a building — which is
  the entire road. They now keep to the pavement ring and to painted zebra crossings, and anyone knocked
  off walks back to the kerb. A test walks all 26 for 400 frames and fails if one is in the road.

## 0.81.0 — 2026-09-22

### Added
- **Thirty more things in the street** (SPEC 81), taking `MapProp` from 12 kinds to 42: bollards,
  parking meters, post boxes, benches, bus shelters, phone boxes, traffic lights, road signs, bike
  racks, litter bins, kiosks, vending machines, market stalls, cafe tables, A-boards, ice cream vans,
  oil drums, gas canisters, portaloos, scaffolding, cable spools, cement mixers, roadworks lamps, panel
  piles, engine blocks, dumped sofas, white goods, shopping trolleys, trees and hedges. Each drawn as a
  thing, each with its own weight, drag, damage and breaking point.
- **Six of them do something when they break**: a kiosk pays 2 coins, a parking meter, vending machine
  and market stall pay 1; an oil drum leaves a slick that costs grip for 26 seconds; and a gas canister
  **explodes** — 120 px, everyone thrown and damaged, nearby props knocked too, so a roadworks yard goes
  up in a chain. It hurts whoever set it off just as much.
- **`downtown` has districts**: civic, shops, market, transport, green and roadworks frontages, a
  junkyard square, a cafe square under trees, a roadworks across one street, and an ice cream van.
  265 objects — still none of them in the road.

## 0.80.0 — 2026-09-22

A town worth driving through.

### Added
- **Pedestrians** (SPEC 80): 26 people walk the pavements. Run one over above 90 px/s and they are gone
  completely — a mark on the road, a coin in your pocket. They never slow you down, so the only cost is
  the line you gave up to do it.
- **Objects that are objects**: `MapProp` went from 5 kinds to 12 — fences, skips, pallets, crates, road
  barriers, lamp posts with a pool of light, and stripped car wrecks. Each drawn as a thing with a
  shadow, each with its own weight, drag, damage and breaking point.
- **A junkyard** in one of `downtown`'s two squares: fenced, four dead cars, pallets and crates.

### Changed
- **Coins sit in the middle of the road** and are twice the size. The cell still picks which ninth of the
  map; the coin then snaps to the crown of the nearest street (58–89 px clear of any building on
  `downtown`).
- **The junk is gone.** 429 props became 153, none of them in the road — lamp posts on junction corners,
  fences along the pavements, skips in the alleys. A street you cannot drive down is not scenery.
- **Cars are 1.45× bigger** (`Car.body_scale`), drawing and collision together, so you can actually see a
  door come off. The handling is unchanged.
- **A car falls apart before it dies**: a piece thrown off at 22, 40, 58, 74 and 88 damage, each
  announced, and cars take far longer to kill. Fifty seconds of four-car fighting now ends with shed
  panels and burst tyres rather than an explosion out of nowhere.
- Pavements are 38 px instead of 20 — they are where the people are, so they have to read as somewhere
  you should not be.

## 0.79.0 — 2026-09-22

The arena, after playing it. Thirteen fixes, most of them the same lesson: answer "why can I not just..."
with a control, not a wall.

### Added
- **Reverse** (SPEC 79): nearly stopped with the cursor behind you and the car backs out under power.
  A nose-first mistake used to end the match. (9 px of progress without it, 151 px with it.)
- **Zoom in the arena**: the mouse wheel, four steps, gliding between them, plus pinch. It was missing.
- **Arrows to the coins**: a faint arrow per coin and bonus, with a tail that says how far.
- **Props you can smash**: cones and bins break, planters and tyre stacks hurt. `downtown` went from 70
  props to 429 — a cluster at every junction, a line down every street, planters against the buildings.

### Changed
- **The rope no longer hooks buildings.** It read badly in the hand: a corner you did not aim for takes
  the car somewhere you did not ask for. The corner-finding it brought is now what the bots steer with.
- **Two coins, in the middle of one of nine cells** — never scattered. Nine known places is a map you
  learn; two at a time is a decision every time. Zones you draw now fine-tune where in a cell things
  appear rather than being the rule.
- **Cars are 30 % quicker** here: at circuit speed, with the camera close, a town felt like a car park.
- **Cars come apart instead of popping**: panels and tyres now go at town speeds (90 px/s rather than
  170), and a car takes longer to kill. A minute of four-car fighting leaves burst tyres and missing
  panels on the survivors.
- **Buildings are drawn as solid blocks inside their own footprint** — the old roof-offset read as two
  loose walls and made street props look like they were on the roof.
- **Bots find their way**: a two-step look-ahead around buildings and a stuck detector that reverses out.
  They drive 5–7 k px a minute now and all of them score.

### Fixed
- "WRECKED!" stayed on screen for the rest of the match after your first death.
- A car resting against a planter was charged the full hit every frame and quietly exploded.

## 0.78.0 — 2026-09-22

The mode that makes the physics worth mastering, and the tools to build places for it.

### Added
- **ARENA** (SPEC 77): a town, 2-6 cars, three minutes, coins in the street. Most coins wins. Wreck and
  you drop a quarter of what you were carrying, right where you died. Repair, shield and double-damage
  bonuses appear in their own zones.
- **The rope bends around corners** (SPEC 75): in an arena the rope hooks building corners, the car is
  pulled toward the bend, and the speed it asks for is the whole path -- so you swing round a block and
  the bend releases like a sling. Off on circuits, where nothing changed.
- **Hitting people properly** (SPEC 77): the nose is armoured (x0.45), the flanks (x1.15) and the tail
  (x1.45) are not, and landing it nose-first pays x1.3. Ramming is now an aiming problem.
- **Make your own arenas** (SPEC 76): `ArenaMap`, `MapBlock`, `MapZone`, `MapSpawn` and `MapProp` are
  editor nodes that draw themselves. Any scene in `scenes/arenas/` is in the game the moment you save it,
  and it is checked -- in the editor, on the command line and in the picker -- before anyone plays it.
- **Draw your own circuits** (SPEC 78): a `MapTrack` scene with a `Path2D`. It is resampled, measured and
  refused if it crosses itself or has a corner no car could take, then listed under "Yours".
- **[docs/MAPPING.md](docs/MAPPING.md)**: how to build both, and what makes a map good.
- Tools: `check_map.gd` (checks any map), `smoke_arena.gd` (plays a match headless and reports it),
  `shoot_arena.gd` (a picture of a match).

### Changed
- The rival AI can drive without a racing line (`free_roam`): it is given a point and finds its own way
  around buildings, keeping every habit that makes it feel human.
- The race order board doubles as the arena scoreboard.

## 0.74.0 — 2026-09-21

### Fixed
- **Multiplayer: a car you had not bought could follow you back into the room** (SPEC 73). Highlighting a
  locked car on the car screen announced it to the room immediately, and Back left it selected. The room
  is now told `owned_car()` rather than whatever is being browsed, Back restores the car the screen opened
  with, and the room's quick car switch skips locked cars.

### Changed
- **How to play is a main menu button** (SPEC 74), between Multiplayer and Settings, instead of a row
  buried in Settings; its Back returns to the menu. Settings is now four settings and nothing else.

## 0.71.0 — 2026-09-21

The first published release. Everything below had been built already; this is where the builds start
coming out of the repository as downloads instead of living inside it.

### Added
- **The career** (SPEC 56): coins for finishing, a Mario-Kart ladder where the next track opens when you
  medal on this one, cars to buy, and a garage that saves between sessions.
- **Parts with a price in handling, not just coins** (SPEC 58, 61): five slots, every part a trade — the
  turbo that pulls harder and overheats, slicks that grip until it rains. No part is simply better.
- **The garage as its own screen** (SPEC 64, 67, 68): eight tabs, a live 3D preview that fits what you
  highlight, a model for every part, and a bonnet that stands open over a non-stock engine.
- **A world bigger than the screen** (SPEC 52, 53): scrolling tracks, a town to race through, and
  buildings you cannot drive through.
- **The close camera** (SPEC 50): the GTA2-style view, four zoom steps on the wheel or two fingers.
- **Mechanics that reward technique** (SPEC 49): slipstream, tyres that wear and go cold, a rope with a
  physical footprint, tyre walls that give, and track limits that cost you.
- **Self-destruct and last-car-running** (SPEC 57), the **running order board** (SPEC 55), **damage you can
  see** (SPEC 51), and **cosmetics** — colours, flames, smoke, stars, underglow (SPEC 59).
- **One command to deploy a server** (SPEC 66): `ghcr.io/<owner>/rope-racers:latest`, built by CI.
- **Versioning and releases** (SPEC 72): the build shows in the main menu corner, the server tells you when
  it is ahead of you, and every tag publishes Windows, Linux, Linux ARM64, macOS, web and server builds.

### Changed
- **The menus, read at a glance** (SPEC 62, 63): one type scale, one grid, nothing overlapping, and the
  race screen down to what a driver actually reads.
- **No race bar** (SPEC 69): the speed, the gauges and the wheel readouts are gone; the 84 px they took is
  road, and the one line that mattered sits under the order board.
- **A locked car looks locked** (SPEC 70, 71): primer grey with its price across it, and the garage and
  NEXT shut until it is bought.
- **A frame costs less** (SPEC 54): one mesh instead of thousands of draw calls — 3458 draw calls down to
  214, and the worst frame from 44 ms to 2.4 ms.

### Fixed
- Cars that had not been bought could still be raced.
- The last zoom step out snapped instead of gliding; every step now shares the same limits and easing.
- AI cars appeared to levitate and slide sideways (a model-refresh budget that starved the pose).
- Tools and tests could overwrite real settings and career saves; both now use throwaway files.

## Before 0.71.0

Eight tracks, medals and ghosts, the rope and its tension zones, damage, weather, hazards, replays, the
dedicated server with rooms and join-by-code, and everything else the first forty-eight SPEC sections
describe. There are no release builds for any of it — the history is in `docs/SPEC.md` and in git.
