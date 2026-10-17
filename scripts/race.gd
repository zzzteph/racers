class_name Race
extends Node2D
## Race scene root: builds track, car, lap tracker and UI; runs countdown -> racing -> finished.

enum Phase { COUNTDOWN, RACING, FINISHED }
const COUNTDOWN_STEP := 1.0
const GO_DISPLAY_TIME := 0.7
## SPEC 143: the field card stays this long after GO (three seconds of countdown is not long enough to
## read three rivals), fading over the last FIELD_FADE of it.
const FIELD_LINGER := 4.0
const FIELD_FADE := 1.5
const RESUME_HOLD_TIME := 1.0        # s the car stays held ("Ready") after resuming from pause
## s the car stays held ("Ready") after a respawn. The race does NOT stop for it: the clock and the rivals
## run on (the hold only stops a cursor left far away yanking the fresh car straight off again).
## SPEC 49 -- the tow. A car is in another's wake when it is behind it, within SLIP_RANGE px and no more
## than SLIP_WIDTH px off its line; the tow is strongest right behind, and gone at the edges of the cone.
const SLIP_RANGE := 190.0
const SLIP_WIDTH := 38.0
const SLIP_MIN_SPEED := 180.0        # px/s: no tow at a crawl (there is no air to hide in)
## The rope frays where it drags (SPEC 49): across the barrier, or round a tyre stack it has snagged.
const ROPE_FRAY_WALL := 0.28         # strain per second with the rope lying over the barrier
const ROPE_FRAY_SNAG := 0.55         # strain per second at a full snag

## CLOSE CAMERA (SPEC 50), single player. The view rides with the car at CLOSE_ZOOM times the normal
## scale, so the cars are big enough to read: the dents, the bare rims, the pieces missing. It looks ahead
## CLOSE_LEAD seconds of travel (so a fast car sees where it is going) and catches up at CLOSE_SMOOTH.
## The rope is scaled with the zoom, so the cursor sits at the same distance ON SCREEN as it always did --
## the control is identical, the world is simply bigger around it.
## SPEC 63: the wheel zooms. Step 0 is the classic view (the whole track at once); every step after it
## rides with the car, closer each time. A big world starts at step 1 because it can never be shown whole.
const ZOOM_STEPS := [1.0, 1.4, 1.8, 2.3]
const DEFAULT_ZOOM_STEP := 2
const PINCH_STEP := 0.35             # trackpad magnify units per step of the ladder
const PINCH_PIXELS := 60.0           # px of finger spread per step
var _zoom_step: int = DEFAULT_ZOOM_STEP
var _zoom_target: float = 0.0
## How fast the picture slides to a new zoom step: 1/s of exponential approach.
const ZOOM_GLIDE := 9.0
var _pinch: float = 0.0
var _pinch_span: float = 0.0
var _touches: Dictionary = {}
const CLOSE_ZOOM := 2.0
const CLOSE_LEAD := 0.32
const CLOSE_SMOOTH := 7.0
var close_camera: bool = false

## SPEC 128: NOTHING BLOWS ITSELF UP ANY MORE. Scrapping the car on purpose (SPEC 57) traded a bad race
## for a wait, and rivals did the same on a timer -- so the one decision a damaged car is FOR, "can I get
## this thing round another lap?", had an opt-out button next to it. A hurt car now limps, and that is the
## whole of it: a dead engine still turns the wheels (`engine_dead_power`), a flat tyre still rolls, and
## only the fuel tank ends a race.
##
## What is left is the case that is a BUG rather than a decision: a car genuinely wedged where no amount
## of rope will move it. That is recovered automatically, below -- no explosion, no reward, no button.
## A car counts as stuck once it has been slower than this, with the rope really pulling, for this long.
const STUCK_SPEED := 14.0
const STUCK_PULL := 0.30           # of full throttle: the player IS asking the car to move
const STUCK_TIME := 2.5
## Being HELD is not being stuck. A rival leaning on you against a barrier ticks every other box -- you
## are pulling, you are going nowhere -- and lifting you out of it turns a legitimate block into a free
## escape to the racing line, which pays you for being blocked. Scenery does not count: jammed against a
## wall is the case this exists for.
const STUCK_NOT_SHOVED := 1.0
## ... and the player is told before it happens, with long enough left to move and cancel it. A recovery
## that fires silently is indistinguishable from the game teleporting you for no reason -- and if the
## test above is ever wrong, this is the second where the player can prove it wrong by driving off.
const STUCK_WARN_AT := 0.9
var _stuck_for: float = 0.0
## SPEC 133: has the player moved the mouse yet? Until they have, the rope points down the road rather
## than at a pointer they have not put anywhere on purpose.
var _cursor_taken: bool = false
## How far ahead the rope points while nobody has taken it -- a normal driving length, so the car pulls
## away at the lights instead of creeping or standing still.
const START_ROPE := 300.0
## SPEC 130: the rules of a race, from the pause menu -- the same card, in the same place, as the
## arena's. Kept here rather than read off the help screen because the help screen is a screen: it is
## laid out in columns for a page you navigate to, not a card you open mid-race.
const RACE_RULES := [
	["THE ROPE", "The car drives at your cursor. The further out you hold it, the faster it goes."],
	["CORNERS", "Bring the cursor in to slow down, and lead the car round with it."],
	["THE BRAKE", "Drop the cursor onto the car and it stops. Nothing else stops it that hard."],
	["OFF THE ROAD", "Grass is slow -- but pull hard and the rope will drag you back onto the road."],
	["DAMAGE", "Panels and tyres never end a race. A dead engine limps; only the fuel tank ends it."],
	["THE GATES", "Chevrons show the way. Miss a gate and the lap does not count."],
	["BOOST", "Fill the meter by drifting, passing cleanly and near misses, then spend it on a straight."],
	["A CLEAN PASS", "A place taken without touching anybody pays a boost. One taken through them does not."],
]
## Loaded rather than named: a `class_name` added in this same change is not in the project's class
## cache until it is reimported, and a headless run reads that cache.
var rules_card: CanvasLayer = null
## SPEC 57 -- online, a player left alone (everyone else finished or left) gets this long to reach the
## line before the race is called for them; nobody should have to drive a lap on their own.
const ALONE_GRACE := 10.0
var _alone_left: float = -1.0

## SPEC 135 -- self-destruct, restored. Available once the car is at least this damaged (or on two rims),
## and once every DESTRUCT_COOLDOWN seconds, so it is the way out of a car that cannot be driven any more
## and not a way round the wreck penalty: it costs the same WRECK_TIME plus the run back from the last
## checkpoint that crashing into the tank does.
const DESTRUCT_DAMAGE := 50.0
const DESTRUCT_COOLDOWN := 30.0
var _destruct_left: float = 0.0

const RESPAWN_HOLD_TIME := 0.6
## The part of the screen the world is drawn into (SPEC 69): all of it. The race bar along the bottom
## is gone -- speed, wheel rpm and the gauges were instruments nobody reads at 200 km/h, and the 84 px
## they took is now road. What still has to be said (OFF TRACK, FLAT TYRE, BOOST: CLICK!) is one line
## under the race order board, top left.
## SPEC 107/108: the world's screen -- right of the tower, under the strip -- fitted and centred in it.
const WORLD_SCREEN := Hud.WORLD_AREA
## s between a wreck (the explosion) and the respawn. The race clock keeps running: that is the penalty.
const WRECK_TIME := 2.2
## SPEC 145: INCIDENTS AND CAUTIONS. A rival's wreck brings out the yellow flag: everybody slows to
## CAUTION_SPEED of their top speed, nobody passes (a car's ceiling is the speed of the car ahead of it
## in the order, once within CAUTION_GAP of it), the leader runs at the caution pace and the rest catch
## it up at CAUTION_CATCH. Green again when the field is bunched -- every car within CAUTION_GAP of
## the one ahead -- or after CAUTION_MAX s, never before CAUTION_MIN. The player's own wreck brings out
## nothing (the respawn is punishment enough, and a yellow you can call at will is a tool).
const CAUTION_SPEED := 0.34        # share of top speed, the pace behind the flag
const CAUTION_CATCH := 0.80        # share of top speed a car behind the pack may run to close up
const CAUTION_GAP := 90.0          # px to the car ahead that counts as "closed up"
const CAUTION_CLOSE := 320.0       # px over which a closing car comes down from the catch-up pace
const CAUTION_MIN := 5.0
const CAUTION_MAX := 18.0
const GREEN_HOLD := 1.5            # s the GREEN FLAG flash stays loud
## A rival in a big one (AIDriver.is_in_big_one) that rolls, hits something at INCIDENT_HIT, or leaves
## the road at INCIDENT_OFF px/s has had its incident. Measured with every corner a big one
## (`tools/probe_big_one.gd`): 37-39 of 40 leave the road, 0-2 roll, 0-1 hit something -- the grass
## just slides a car to a stop, so "shot off the road at 300" has to be the crash, or there is none.
const INCIDENT_HIT := 240.0
const INCIDENT_OFF := 150.0
## Centerline points past the start line a car wrecked on the first stretch respawns at, so it is not put
## back behind the line (which would read as a lap with every checkpoint missed).
const RESPAWN_START_OFFSET := 3
## Starting grid: px behind the line of the first slot, px between slots, and the sideways stagger as a
## share of the road half-width. The player starts at the back.
const GRID_FIRST := 40.0
const GRID_GAP := 54.0
const GRID_STAGGER := 0.36
## SPEC 110: catch-up, the honest kind (Big Red Racing showed the other kind reads as cheating). A
## rival BEHIND the player gets up to RIVAL_CATCHUP more pace, growing over CATCHUP_RANGE checkpoints
## of gap, and never more than CATCHUP_CAP of the player's own top speed; a rival ahead gets nothing.
const RIVAL_CATCHUP := 0.10
const CATCHUP_RANGE := 4.0
const CATCHUP_CAP := 0.98
## SPEC 110: the boost tops up for a near miss (a rival passed closer than NEAR_MISS_GAP px at more
## than NEAR_MISS_SPEED px/s of relative speed) and for an overtake -- the reward every few seconds.
const NEAR_MISS_GAP := 26.0
const NEAR_MISS_SPEED := 140.0
const NEAR_MISS_CHARGE := 0.15
## SPEC 126: how much of the camera shake is drawn with "reduce shake and flashing" on.
const CALM_SHAKE := 0.25
const NEAR_MISS_EVERY := 2.0
const OVERTAKE_CHARGE := 0.25
## SPEC 128: how long you have to have been off everybody for a pass to count as your own.
const CLEAN_PASS := 2.0
## SPEC 110: a hard hit on a rival is watched for a spin (SpinWatch) and pays coins into the race's
## purse (Destruction Derby); hits within CHAIN_WINDOW s of the last multiply the pay, up to CHAIN_MAX.
const SPIN_WATCH_SPEED := 150.0
const CHAIN_WINDOW := 3.0
const CHAIN_MAX := 6
## Car-to-car contact: restitution of a hit (0 = dead, 1 = billiard balls).
const CONTACT_RESTITUTION := 0.35
## SPEC 111: which way. Chevrons on the road ahead of the car through the countdown and the first
## GUIDE_START_TIME s of the race (and after a respawn); WRONG WAY, said and shown, once the car has
## driven against the track faster than WRONG_WAY_SPEED for WRONG_WAY_TIME s; an arrow at the road
## after OFF_ROAD_GUIDE_TIME s on the grass.
const GUIDE_START_TIME := 3.0
const GUIDE_AHEAD := 120.0
const GUIDE_NEAR := 70.0
const WRONG_WAY_SPEED := 60.0
const WRONG_WAY_TIME := 0.7
const WRONG_WAY_EVERY := 1.5
const OFF_ROAD_GUIDE_TIME := 1.5
## A gate the car has gone past without taking it (progress this many samples beyond the lap tracker's
## acceptance window) is MISSED: the big arrow points back at it, so the lap is a detour, not a circle.
const MISSED_MARGIN := 4

var phase: Phase = Phase.COUNTDOWN
var world_camera: Camera2D = null
## SPEC 110: the place last seen (an overtake tops the boost up), when each rival was last a near miss,
## the spin watches on rivals the player hit, and the purse those spins have earned.
var _last_place: int = 0
var _near_at: Dictionary = {}
var _spins: Array = []
var _spin_coins: int = 0
var _chain: int = 0
var _chain_at: float = -99.0
## SPEC 111: the arrow on the road and its timers.
var guide: GuideArrow = null
var _guide_start_left: float = 0.0
var _wrong_time: float = 0.0
var _wrong_say_left: float = 0.0
var _off_road_time: float = 0.0
var track: Track
var car: Car
var skid_marks: SkidMarks
var car_effects: CarEffects
var props: TrackProps = null
## SPEC 124: the walls that can be gone through, and the routes behind them.
var breakables: Breakables = null
## SPEC 124: the repair lanes on this circuit, and how long the player has been stopped in one.
var lap_tracker: LapTracker
var hud: Hud
var dashboard: Dashboard
var pause_menu: PauseMenu
var finish_screen: FinishScreen
var feedback_card: FeedbackCard = null        # SPEC 112

var track_id: String = ""
var _countdown_time: float = 0.0
var _go_time_left: float = 0.0
var _field_left: float = -1.0              # SPEC 143: the field card's time after GO
var _caution_left: float = 0.0             # SPEC 145: s the yellow has been out (counts up); 0 = green
var _caution_order: Array = []             # the cars, leader first, as they were when the flag came out
var _cautions: int = 0
var _incidents: int = 0
var _last_countdown_text: String = ""
var _resume_hold_left: float = 0.0
var _hold_running: bool = false      # true: the race runs on through the hold (after a respawn)
var _wreck_left: float = 0.0
var _wreck_count: int = 0
var _boost_was_ready: bool = false
var _boost_hint_shown: bool = false
## One Dictionary per AI rival: {car, ai, lap_tracker, marks, effects, wreck_left, finished, name}.
var rivals: Array = []
var scenery: TownScenery = null          # SPEC 52: the town, on the tracks that have one
## SPEC 57: the race was called because everyone else had gone.
var _last_one_home: bool = false
var _finish_order: Array = []          # cars (player included) in the order they took the flag
var _player_place: int = 1
var _rng := RandomNumberGenerator.new()

# --- multiplayer (Net) ---
## True in a network race: the line-up, track and laps come from Net.race_setup.
var online: bool = false
## A dedicated server has no car of its own: `car` exists but is parked, hidden and never raced.
var spectator: bool = false
## This machine's entry key in Net.race_setup (-1 on a dedicated server).
var my_key: int = -1
var _waiting_start: bool = false
var _net_frame: int = 0
var _race_laps: int = 3
var _by_key: Dictionary = {}           # entry key -> rival Dictionary
## The network race this scene runs: set by Net before add_child for a dedicated server's room race;
## otherwise (a player's own race) taken from Net.race_setup / Net.room_id in _ready.
var net_setup: Dictionary = {}
var net_room: int = -1


func _ready() -> void:
	Engine.time_scale = 1.0
	_confine_mouse()
	if net_setup.is_empty() and Net.is_online() and not Net.race_setup.is_empty():
		net_setup = Net.race_setup
		net_room = Net.room_id
	online = Net.is_online() and not net_setup.is_empty()
	if online:
		Net.register_race(self, net_room)
		track_id = TrackRegistry.resolve(String(net_setup["track"]))
		my_key = Net.my_entry_key(net_setup)
		spectator = my_key < 0
		_race_laps = int(net_setup["laps"])
	else:
		track_id = GameState.selected_track
		_race_laps = GameState.get_laps(track_id)

	# 1. Track
	track = Track.new()
	track.name = "Track"
	track.setup(track_id)
	add_child(track)

	# 2. Car
	car = preload("res://scenes/car.tscn").instantiate() as Car
	car.name = "Car"
	add_child(car)
	car.auto_process = false
	_rng.randomize()
	var lineup: Array = []
	var player_slot := 0
	if online:
		for e in net_setup["entries"]:
			if int(e["key"]) == my_key:
				CarRegistry.apply(car, String(e["car"]), int(e["color"]))
				player_slot = int(e["slot"])
				continue
			var owned := String(e["kind"]) == "ai" and Net.is_server()
			lineup.append({"car": String(e["car"]), "color": int(e["color"]),
					"difficulty": String(e["level"]) if String(e["level"]) != "" else "medium",
					"profile": String(e["profile"]) if String(e["profile"]) != "" else "clean",
					"slot": int(e["slot"]), "key": int(e["key"]), "remote": not owned,
					"name": String(e["name"]), "peer": int(e["peer"]), "kind": String(e["kind"])})
		if Net.bot:
			car.use_mouse = false
	else:
		CarRegistry.apply(car, GameState.selected_car, GameState.selected_color)
		# SPEC 61: whatever is fitted in the garage. The rivals race on stock cars.
		var fitted: Dictionary = GameState.profile.fitted(GameState.selected_car)
		Parts.apply(car, fitted)
		car.set_model_wheel_scale(Parts.wheel_scale(fitted))
		lineup = GameState.resolve_opponents(_rng)
		player_slot = lineup.size()
	if lineup.is_empty() and not online:
		car.reset_to(track.get_start_position(), track.get_start_heading())
	else:
		var slot := _grid_slot(player_slot)
		car.reset_to(slot["pos"], slot["heading"])
	car.rope_drawn_at_nose = true                               # SPEC 106: the rope is drawn from the nose
	car.set_model_priority(true)                                # SPEC 54: your own car never waits
	car.bounds = Rect2(Vector2.ZERO, track.world_size)          # SPEC 52
	car.set_on_track_provider(track.make_on_track_provider())
	car.set_surface_provider(track.make_surface_provider())
	car.wrecked.connect(_on_car_wrecked)
	# SPEC 102: a dead engine is not a wreck -- the car limps, and the SCRAP button is the way out.
	# SPEC 122: a long slide caught straight and clean. The top-up is small on purpose -- drifting
	# already fills the meter about as fast as it can be filled -- so this is mostly the game noticing.
	car.clean_exit.connect(func(held: float) -> void:
		if phase == Phase.RACING:
			hud.flash_message("CLEAN EXIT  %.1f s" % held, Color(0.55, 1.0, 0.62), 0))
	car.engine_died.connect(func() -> void:
		hud.flash_message("ENGINE DEAD  -  LIMP IT HOME", Color(1.0, 0.5, 0.25)))
	car.part_lost.connect(_on_part_lost)
	car.wheel_lost.connect(_on_wheel_lost)
	car.tyre_burst.connect(_on_car_tyre_burst)
	car.oil_leak.connect(_on_oil_leak)
	car.rope_snapped.connect(_on_rope_snapped)
	car.rope_reattached.connect(_on_rope_reattached)
	car.boost_fired.connect(_on_car_boost_fired)
	car.hard_impact.connect(_on_car_impact)
	car.rollover_started.connect(_on_car_rollover)
	track.reset_progress(0 if lineup.is_empty() and not online else int(_grid_slot(player_slot)["index"]))
	car.lock()
	if spectator:
		car.visible = false
		car.position = Vector2(-4000.0, -4000.0)

	# 2b. Ground marks and effects. Both are pure consumers driven explicitly from _physics_process
	# (SPEC 9.B / 9.C / decision 10.13), so their order relative to car.physics_step() is deterministic.
	# z order: Track 0 < SkidMarks 2 < CarEffects "Under" 3 < Track gates 4 < Car under bridge 5 <
	# CarEffects "Over" while under the deck 8 < BridgeDeck 10 < SkidMarks "OnBridge" 15 <
	# CarEffects "Under" while on the deck 16 < Car on bridge 20 < CarEffects "Over" 25 < RopeLine 100.
	skid_marks = SkidMarks.new()
	skid_marks.name = "SkidMarks"
	add_child(skid_marks)
	skid_marks.set_car(car)
	# Point-in-deck query: the car's own deck flag is an along-arc test, so a segment is classified by where
	# it actually is (decision 21.x). Side-effect free, so it is safe to call per segment.
	skid_marks.set_deck_probe(func(p: Vector2) -> bool: return track.is_point_on_deck(p))
	skid_marks.clear()

	car_effects = CarEffects.new()
	car_effects.max_puffs = GameState.puff_budget(true)          # SPEC 54
	if not online or not spectator:
		# SPEC 59: whatever the player has bought and put on the car.
		car_effects.cosmetics = GameState.profile.equipped
		car_effects.cosmetic_tint = car.body_color.lightened(0.25)
	car_effects.name = "CarEffects"
	add_child(car_effects)
	car_effects.set_car(car)
	car.rollover_started.connect(car_effects.on_rollover_started)
	car.rollover_recovered.connect(car_effects.on_rollover_recovered)
	car.hard_impact.connect(car_effects.on_hard_impact)
	_update_bridge_layer()

	# 3. Lap tracker
	lap_tracker = LapTracker.new()
	lap_tracker.setup(track.get_checkpoint_positions(), track.get_checkpoint_indices(),
			track.get_point_count(), track.get_checkpoint_radius(), _race_laps)
	if track.get_point_count() >= 2:
		lap_tracker.set_start_line(track.centerline[0], track.centerline[1] - track.centerline[0])
	lap_tracker.limits_enabled = true
	lap_tracker.lap_limits_lost.connect(_on_lap_limits_lost)
	lap_tracker.lap_completed.connect(_on_lap_completed)
	lap_tracker.race_finished.connect(finish_race)
	lap_tracker.lap_voided.connect(_on_lap_voided)
	lap_tracker.checkpoint_passed.connect(_on_checkpoint_passed)
	track.set_next_checkpoint(lap_tracker.next_checkpoint)

	# 3b. AI rivals, on the grid ahead of the player.
	for k in lineup.size():
		_spawn_rival(k, lineup[k])

	# 3c. Cones and tyre stacks (SPEC 41), the same layout on every client for a track.
	# SPEC 52: the town around the road. Drawn only, and only where a track asks for it.
	# SPEC 52/120: a town on the tracks that ask for one, trees and rocks on the rest -- a circuit with
	# nothing but green between its corners looks unfinished, and the big ones have a lot of green.
	var style := TrackRegistry.get_scenery(track_id)
	if style != "":
		scenery = TownScenery.new()
		scenery.name = "Scenery"
		add_child(scenery)
		scenery.setup(track, hash(track_id) ^ 0x5CE1, style)
	# SPEC 111: a circuit you drew carries its own buildings and props (docs/MAPPING.md, part 2).
	var drawn := TrackRegistry.user_items(track_id)
	var drawn_blocks: Array = drawn.get("blocks", [])
	if not drawn_blocks.is_empty():
		if scenery == null:
			scenery = TownScenery.new()
			scenery.name = "Scenery"
			add_child(scenery)
		scenery.add_blocks(drawn_blocks)
	_push_solids()

	# SPEC 124: the breakable walls, over the ground and under the cars. Built before the props so their
	# rects are in `_solids()` the first time it is asked for.
	breakables = Breakables.new()
	breakables.name = "Breakables"
	add_child(breakables)
	breakables.setup(TrackRegistry.get_breakables(track_id))

	props = TrackProps.new()
	props.name = "Props"
	add_child(props)
	props.setup(track, hash(track_id), TrackRegistry.user_auto_props(track_id))
	if not drawn.is_empty():
		props.add_authored(drawn.get("props", []))
	if scenery != null:
		props.set_solids(scenery.get_solids())     # SPEC 53: a rolling tyre bounces off a building
	# Oil on the road changes every car's grip (SPEC 46).
	var grip := func(p: Vector2) -> float: return props.grip_at(p)
	car.set_hazard_probe(grip)
	# Tyre walls (SPEC 49): where the road runs close to the barrier, the wall takes the hit.
	var walls := func(p: Vector2) -> bool: return track.is_tyre_wall(p)
	car.set_wall_probe(walls)
	car.wall_tyres_hit.connect(_on_wall_tyres_hit)
	for r in rivals:
		var rc := r["car"] as Car
		rc.set_hazard_probe(grip)
		rc.set_wall_probe(walls)
		rc.wall_tyres_hit.connect(_on_wall_tyres_hit)

	# SPEC 111: the way to go, drawn on the road under the HUD.
	guide = GuideArrow.new()
	guide.name = "Guide"
	add_child(guide)

	# 4. UI
	var accent := TrackRegistry.get_accent(track_id)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	# SPEC 126: the calm setting, read once when the race is built.
	car.shake_scale = CALM_SHAKE if GameState.calm_effects() else 1.0
	hud.pause_pressed.connect(func() -> void:
		if phase != Phase.FINISHED and not pause_menu.is_open():
			pause_race())
	hud.self_destruct_pressed.connect(func() -> void: try_self_destruct())   # SPEC 135: the chip and F
	hud.set_accent(accent)
	hud.set_track_name(GameState.get_track_name(track_id))
	hud.set_record_lap(GameState.get_best_lap(track_id))
	hud.update_race_info(lap_tracker.current_lap, lap_tracker.total_laps, 0.0, 0.0, INF)
	hud.show_field(_field_rows())                               # SPEC 143: who you are racing

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.resume_requested.connect(resume_race)
	pause_menu.restart_requested.connect(restart_race)
	pause_menu.menu_requested.connect(_on_menu_requested)
	pause_menu.main_menu_requested.connect(_on_main_menu_requested)
	# SPEC 130: THE SAME PAUSE MENU IN BOTH MODES. The arena's had a Rules button and a race's did not,
	# for no better reason than that the arena happened to own a briefing card -- so the rules of a race
	# were only on the How to play screen, which you cannot reach from inside one. Same buttons, same
	# order, same card.
	pause_menu.set_rules(true)
	rules_card = preload("res://scripts/rules_card.gd").new()
	rules_card.name = "RulesCard"
	add_child(rules_card)
	pause_menu.rules_requested.connect(func() -> void:
		pause_menu.close()
		rules_card.open("HOW A RACE WORKS", RACE_RULES))
	rules_card.closed.connect(func() -> void:
		if phase != Phase.FINISHED:
			pause_menu.open())

	finish_screen = FinishScreen.new()
	finish_screen.name = "FinishScreen"
	add_child(finish_screen)
	finish_screen.race_again_requested.connect(restart_race)
	finish_screen.menu_requested.connect(_on_menu_requested)
	# SPEC 112: feedback from the pause menu and the results card, saying where the player is.
	feedback_card = FeedbackCard.new()
	feedback_card.name = "FeedbackCard"
	add_child(feedback_card)
	pause_menu.feedback_requested.connect(func() -> void:
		feedback_card.open("%s, lap %d of %d" % [GameState.get_track_name(track_id),
				lap_tracker.current_lap, lap_tracker.total_laps], GameState.get_player_name()))
	finish_screen.feedback_requested.connect(func() -> void:
		feedback_card.open("%s, %d laps, finished %d of %d" % [GameState.get_track_name(track_id),
				lap_tracker.total_laps, _player_place, _field_size()], GameState.get_player_name()))

	# 5. The race bar: speed and rpm gauges plus all the race information, in the same place on every
	# track. layer 9: above the world, below the HUD overlays. The world itself is drawn above it.
	# SPEC 69: the bar is still built -- it is what tracks the gearbox, the drift and the status line, and
	# the HUD reads them from it -- but it is not drawn any more.
	dashboard = Dashboard.new()
	dashboard.name = "Dashboard"
	dashboard.visible = false
	add_child(dashboard)
	dashboard.set_car(car)
	dashboard.set_accent(accent)
	dashboard.set_held(true)
	hud.set_bar(dashboard)
	_setup_world_camera()

	if online:
		var tags := runner_tags(net_setup["entries"])
		if not spectator:
			car.tag = String(tags.get(my_key, ""))
		for r in rivals:
			(r["car"] as Car).tag = String(tags.get(int(r["key"]), ""))
		_waiting_start = true
		hud.show_countdown("Waiting...")
		pause_menu.set_online(true)
		finish_screen.set_online(true)
		Net.race_ready(self, net_room)
	else:
		start_countdown()


## Net: every player has loaded -- everyone counts down together.
func net_begin_countdown() -> void:
	_waiting_start = false
	start_countdown()


func start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_countdown_time = 0.0
	_go_time_left = 0.0
	_last_countdown_text = "3"
	_wreck_left = 0.0
	if car_effects != null:
		car_effects.stop_burning()
	hud.hide_wreck()
	for r in rivals:
		(r["car"] as Car).lock()
	Audio.beep(false)
	car.lock()
	if dashboard != null:
		dashboard.set_held(true)
		dashboard.gearbox().reset()
	hud.show_countdown("3")
	_guide_start_left = 0.0
	_wrong_time = 0.0
	_off_road_time = 0.0
	_tick_guide(0.0)


func _physics_process(delta: float) -> void:
	# SPEC 135: the chip is on screen from the lights to the flag, so the key is learnable before it is
	# needed. It ticks OUTSIDE the match below because the countdown and the racing arms both want it.
	if phase == Phase.COUNTDOWN or phase == Phase.RACING:
		_tick_destruct(delta)
	else:
		hud.hide_self_destruct()
	match phase:
		Phase.COUNTDOWN:
			_update_rope_preview()
			# The dash is alive from the first frame (speed 0, gear N, bars empty): it reads as part of
			# the car rather than as a HUD that switches on at GO.
			dashboard.set_held(true)
			dashboard.sample(delta)
			# The duck rule is evaluated in every phase, not only while racing: on `circle` the car
			# spawns at (680, 625), already behind the strip, so the whole 3 s countdown used to be
			# played out behind an 80 %-opaque panel.
			_update_camera()
			_glide_zoom(delta)
			_tick_guide(delta)                      # SPEC 111: the start arrow
			if not _waiting_start:
				_update_countdown(delta)
		Phase.RACING:
			if _wreck_left > 0.0:
				_update_wreck(delta)
				return
			if _resume_hold_left > 0.0:
				if _hold_running:
					# The race never stops for a respawn: the clock, the rivals and the net run on.
					lap_tracker.update_race(delta, car.position, track.get_progress_index(),
							car.is_off_track())
					_update_rivals(delta)
					_tick_spins(delta)                  # SPEC 110
					_step_props(delta)
					resolve_contacts()
					_net_send()
					hud.update_race_info(lap_tracker.current_lap, lap_tracker.total_laps,
							lap_tracker.current_lap_time, lap_tracker.total_time, lap_tracker.best_lap_time)
				dashboard.set_held(true)
				dashboard.sample(delta)
				_update_resume_hold(delta)
				return
			dashboard.set_held(false)
			_update_go_display(delta)
			_tick_caution(delta)                        # SPEC 145
			if Net.bot and not spectator:
				car.target_point = track.centerline[(track.get_progress_index() + 6) % track.get_point_count()]
			_update_slipstream()
			car.physics_step(delta, _player_target())
			_check_boost_ready()
			_update_rivals(delta)
			_step_props(delta)
			resolve_contacts()
			_net_send()
			_update_bridge_layer()
			_sample_effects(delta)
			lap_tracker.update_race(delta, car.position, track.get_progress_index(), car.is_off_track())
			# Re-evaluate the duck now that the PENDING GATE has moved. `_update_bridge_layer()` ran it
			# earlier this frame, but that was before `lap_tracker.update_race()`, so on the frame the
			# car passes a gate the decision was still made against the OLD pending gate: if the new one
			# sits behind the strip, it spent a frame behind an undimmed panel (tester round 5). It sits
			# ABOVE the early return so the finishing frame is covered too. The call is idempotent and
			# only sets a flag -- the fade itself is a 0.25 s lerp in Dashboard.sample() -- so picking
			# the change up here costs nothing visible.
			if phase != Phase.RACING:
				return  # the race finished during update_race (finish_race already set up the UI)
			track.set_next_checkpoint(lap_tracker.next_checkpoint)
			_glide_zoom(delta)
			_tick_stuck(delta)
			_tick_alone(delta)
			_update_standings()
			_tick_guide(delta)                      # SPEC 111: wrong way / back to the road
			_update_camera()
			_update_minimap()
			hud.update_race_info(lap_tracker.current_lap, lap_tracker.total_laps,
					lap_tracker.current_lap_time, lap_tracker.total_time, lap_tracker.best_lap_time)
			hud.set_off_track(car.is_off_track())
			_tick_stuck_notice()
			_feed_audio()
		Phase.FINISHED:
			dashboard.set_held(false)
			_update_go_display(delta)
			# Rope released: the car brakes to a stop instead of freezing on the line.
			car.physics_step(delta, car.position)
			_update_rivals(delta)
			_step_props(delta)
			resolve_contacts()
			_net_send()
			_update_bridge_layer()
			# Marks and effects keep running while the car coasts, but the DRIFT readout stays off: a car
			# that crosses the line sideways is still drifting for a few tenths, and the line would flash
			# back on over the finish screen that finish_race() just cleared it from.
			_sample_effects(delta, false)
			_feed_audio()


## Marks, effects and the drift readout, in a fixed order after the car has moved and been layered.
## Never called while the car is held (countdown / resume hold): a frozen car can neither lay a mark nor
## emit a signal, and the HUD drift line must stay hidden there.
func _sample_effects(delta: float, show_drift: bool = true) -> void:
	skid_marks.sample(delta)
	car_effects.sample(delta)
	# After car.physics_step() and _update_bridge_layer(), in the same fixed order as the marks and
	# effects (decision 10.13), so the dash always shows the frame that has just been simulated.
	dashboard.sample(delta)
	if show_drift:
		hud.set_drift(car.is_drifting(), car.drift_intensity(), car.get_drift_time(), car.get_drift_total())
	else:
		hud.set_drift(false, 0.0, 0.0)


## Z order uses the slightly longer layering zone (no flicker at the deck ends); the raised look (scale +
## shadow) follows the drawn deck itself, so the car does not inflate before it is on the bridge.
## The effects follow the car under the deck as well: while the car is on the lower branch its sparks and
## rollover dirt must not be painted on top of the bridge (see CarEffects.set_under_deck).
func _update_bridge_layer() -> void:
	var on_deck := track.is_car_on_deck()
	car.set_bridge_layer(track.is_car_on_bridge_layer())
	car.set_bridge_scale(on_deck)
	car_effects.set_under_deck(track.is_car_under_bridge())
	# ... and above it while the car is ON it: the deck is opaque, so at the ground layer every puff of
	# smoke and dust the car made while driving over the bridge was hidden underneath it.
	car_effects.set_on_deck(on_deck)


## The world (1280x720) is drawn scaled into the part of the screen above the race bar, centred, so no
## track -- the two legacy ones reach y = 720 -- ever has road, a car or a gate under the bar. Pure view:
## every world coordinate, the physics, the mouse (get_global_mouse_position) and the tests are unchanged.
func _setup_world_camera() -> void:
	world_camera = Camera2D.new()
	world_camera.name = "WorldCamera"
	add_child(world_camera)
	world_camera.make_current()
	# SPEC 63: the game starts ZOOMED IN -- riding with the car is the view it is played at. The wheel
	# (or a pinch) moves up and down the ladder; a world bigger than a screen can never sit at step 0.
	# (SPEC 104 started a one-screen track at the fit; SPEC 110 rides again: "you see a bit of the race".)
	_zoom_step = DEFAULT_ZOOM_STEP
	_apply_zoom(_zoom_step, true)


## Whether the whole track can be shown at once (step 0 of the ladder).
func fits_screen() -> bool:
	return not TrackRegistry.is_big(track_id)




## The zoom the game was authored at: one screen-sized world drawn into the area above the race bar.
## Every rope length and every "how fast does that look" comes from it.
func _reference_zoom() -> float:
	# SPEC 108: the fit of a screen-sized world into the world's screen -- so step 0 of a one-screen
	# track IS the reference, and its ropes are the authored ropes (the driving tests run there).
	return minf(WORLD_SCREEN.size.x / TrackData.SCREEN_SIZE.x, WORLD_SCREEN.size.y / TrackData.SCREEN_SIZE.y)


func _min_zoom_step() -> int:
	return 1 if TrackRegistry.is_big(track_id) else 0


## Puts the camera on step `step` of the ladder: step 0 shows the whole world at once, every step after
## it rides with the car. The rope is rescaled with the zoom, so the cursor sits at the same distance on
## screen whatever the view (SPEC 50/63).
## `glide` false (the default) puts the camera there at once -- setting a race up, or a test. The wheel
## and the pinch pass true, and the picture slides (SPEC 69).
func _apply_zoom(step: int, first: bool = false, glide: bool = false) -> void:
	if world_camera == null or track == null:
		return
	_zoom_step = clampi(step, _min_zoom_step(), ZOOM_STEPS.size() - 1)
	var world := track.world_size
	var ref := _reference_zoom()
	var fit := minf(WORLD_SCREEN.size.x / world.x, WORLD_SCREEN.size.y / world.y)
	var z: float = fit if _zoom_step == 0 else ref * float(ZOOM_STEPS[_zoom_step])
	var was: float = _zoom_target if not first else ref
	# SPEC 69: the rope is rescaled at once (it is physics, and it must not drift during a slide), but
	# the picture slides to the new zoom over ZOOM_GLIDE seconds -- a snap between steps is a jolt.
	_zoom_target = z
	if not glide:
		world_camera.zoom = Vector2(z, z)
	_scale_ropes(z / was)
	close_camera = _zoom_step > 0
	# The same limits and the same smoothing at every step: the camera is always kept inside the world
	# and always eases to where it is going. Zooming all the way out used to swap a following camera for
	# a fixed one and turn the limits off in the same frame, which is a jump, not a zoom.
	world_camera.limit_left = Hud.limit_left(z)                # SPEC 108: the tower's worth of world
	world_camera.limit_top = Hud.limit_top(z)                  # ... and the strip's
	world_camera.limit_right = int(world.x)
	world_camera.limit_bottom = int(world.y)
	world_camera.position_smoothing_enabled = true
	world_camera.position_smoothing_speed = CLOSE_SMOOTH
	if not glide:
		# An instant zoom puts the camera where it belongs instantly too, smoothing and all -- otherwise
		# the first frame of a race (and every test) reads the camera mid-glide.
		world_camera.position = (car.position if close_camera else world * 0.5) + _bar_shift(z)
		world_camera.reset_smoothing()
	hud.set_minimap_visible(close_camera)   # nothing to map when the whole track is on screen
	if close_camera:
		hud.setup_minimap(track.centerline, world)
		_update_minimap()


## The wheel on a desktop, two fingers on a phone (SPEC 63).
func zoom_in() -> void:
	_apply_zoom(_zoom_step + 1, false, true)


func zoom_out() -> void:
	_apply_zoom(_zoom_step - 1, false, true)


func get_zoom_step() -> int:
	return _zoom_step


## The zoom the ladder is on -- what the picture is sliding toward, which is what the rope was scaled for.
func get_zoom() -> float:
	return _zoom_target


## The rope, in world pixels, scaled with the zoom (SPEC 50). A rope that reached 290 px across a whole
## track on screen still reaches 290 px ON SCREEN when the view is twice as close -- so the cursor, the
## tension zone and every car's feel are untouched; only the world around them got bigger.
func _scale_ropes(zoom: float) -> void:
	if zoom <= 0.0:
		return
	var all: Array = [car]
	for r in rivals:
		all.append(r["car"])
	for c in all:
		var a := c as Car
		if a == null:
			continue
		a.speed_per_px *= zoom
		a.slack_radius /= zoom
		a.reattach_extra /= zoom


## The camera rides with the car, looking a little way ahead of it (SPEC 50).
## Eases the picture toward the zoom the ladder asked for (SPEC 69).
func _glide_zoom(delta: float) -> void:
	if world_camera == null or _zoom_target <= 0.0:
		return
	var now := world_camera.zoom.x
	if absf(now - _zoom_target) < 0.002:
		world_camera.zoom = Vector2(_zoom_target, _zoom_target)
		return
	var z := lerpf(now, _zoom_target, clampf(ZOOM_GLIDE * delta, 0.0, 1.0))
	world_camera.zoom = Vector2(z, z)


func _update_camera() -> void:
	if world_camera == null or track == null:
		return
	var shift := _bar_shift(world_camera.zoom.x)
	if not close_camera:
		world_camera.position = track.world_size * 0.5 + shift     # the whole world, centred under the bar
		return
	var look: Vector2 = car.position + car.velocity * CLOSE_LEAD
	if not car.visible:
		look = car.position            # wrecked: sit where the fireball is
	world_camera.position = look + shift


## SPEC 107/108: what the camera centres lands in the middle of the world's screen, not of the window.
static func _bar_shift(z: float) -> Vector2:
	return Hud.world_shift(z)


## Every car as a dot on the minimap (SPEC 50): yours white, the rivals in their own colours.
func _update_minimap() -> void:
	if not close_camera or hud == null or not hud.has_minimap():
		return
	var dots: Array = []
	for r in rivals:
		var rc := r["car"] as Car
		if rc != null and rc.visible:
			dots.append({"pos": rc.position, "color": rc.body_color, "me": false})
	if car.visible:
		dots.append({"pos": car.position, "color": Color.WHITE, "me": true})
	hud.update_minimap(dots)


## Where world point `p` is drawn on the screen (1280x720 base).
func world_to_screen(p: Vector2) -> Vector2:
	if world_camera == null:
		return p
	var view_mid := Vector2(TrackData.SCREEN_SIZE.x, TrackData.SCREEN_SIZE.y) * 0.5
	return (p - world_camera.position) * world_camera.zoom + view_mid


## Shows the rope toward the cursor while the car is held (countdown / resume hold), so the player sees
## where the car will be pulled. (The "bring the cursor to your car" hint is gone -- SPEC 44: no text on
## the track but the countdown and the messages; the rope preview says it.)
func _update_rope_preview() -> void:
	var target := _player_target()
	car.set_rope_preview(target)
	hud.set_hint("")


func _update_resume_hold(delta: float) -> void:
	_update_rope_preview()
	_resume_hold_left -= delta
	if _resume_hold_left <= 0.0:
		_resume_hold_left = 0.0
		hud.set_hint("")
		hud.show_countdown("GO")
		_go_time_left = GO_DISPLAY_TIME
		_confine_mouse()


func is_resume_hold_active() -> bool:
	return _resume_hold_left > 0.0


func _update_countdown(delta: float) -> void:
	_countdown_time += delta
	var step := int(floor(_countdown_time / COUNTDOWN_STEP))
	if step >= 3:
		_begin_racing()
		return
	var text := str(3 - step)
	if text != _last_countdown_text:
		_last_countdown_text = text
		hud.show_countdown(text)
		Audio.beep(false)


func _begin_racing() -> void:
	phase = Phase.RACING
	Audio.beep(true)
	hud.set_hint("")
	hud.show_countdown("GO")
	_go_time_left = GO_DISPLAY_TIME
	_guide_start_left = GUIDE_START_TIME
	_field_left = FIELD_LINGER
	car.unlock()
	lap_tracker.start()
	for r in rivals:
		(r["car"] as Car).unlock()
		(r["lap_tracker"] as LapTracker).start()
	_confine_mouse()


func _update_go_display(delta: float) -> void:
	if _go_time_left > 0.0:
		_go_time_left -= delta
		if _go_time_left <= 0.0:
			hud.hide_countdown()
	if _field_left > 0.0:
		_field_left -= delta
		if _field_left <= 0.0:
			hud.hide_field()
		elif _field_left < FIELD_FADE:
			hud.set_field_alpha(_field_left / FIELD_FADE)


## SPEC 143: the field card's rows -- every rival but you: its colour, the car, the personality it was
## dealt and what that does. Another player is just that.
func _field_rows() -> Array:
	var rows: Array = []
	for r in rivals:
		var c: Car = r["car"]
		var row := {"name": RaceBoard.plain_name(String(r["name"])), "color": c.body_color}
		if String(r.get("kind", "ai")) == "ai":
			row["persona"] = AIDriver.personality_name(String(r["profile"]))
			row["tell"] = AIDriver.personality_tell(String(r["profile"]))
		else:
			row["name"] = String(r["name"])
			row["persona"] = "player"
			row["tell"] = "another player -- anything goes"
		rows.append(row)
	return rows


func _unhandled_input(event: InputEvent) -> void:
	# SPEC 133: the first real movement of the pointer takes the rope, and keeps it for the rest of the
	# race. A touch counts too -- on a phone there is no cursor sitting anywhere until a finger lands.
	# Not consumed: this only watches.
	if not _cursor_taken and (event is InputEventMouseMotion or event is InputEventScreenDrag
			or event is InputEventScreenTouch
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)):
		_cursor_taken = true
	# SPEC 63: the view. Wheel up / down on a desktop, a pinch on a phone or a trackpad.
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			get_viewport().set_input_as_handled()
			zoom_in()
			return
		if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()
			zoom_out()
			return
	var pinch := event as InputEventMagnifyGesture
	if pinch != null:
		get_viewport().set_input_as_handled()
		_pinch += pinch.factor - 1.0
		if absf(_pinch) > PINCH_STEP:
			_apply_zoom(_zoom_step + (1 if _pinch > 0.0 else -1), false, true)
			_pinch = 0.0
		return
	if _handle_touch_pinch(event):
		return
	if _is_boost_input(event):
		get_viewport().set_input_as_handled()
		try_boost()
		return
	# SPEC 135: F writes the car off. A key rather than an action so it cannot be bound to the pointer.
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_F:
		get_viewport().set_input_as_handled()
		try_self_destruct()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if phase == Phase.FINISHED:
		# Esc on the finish screen means the same as its "Tracks" button (Esc always means "back").
		_on_menu_requested()
	elif not pause_menu.is_open():
		pause_race()


# ---------------------------------------------------------------- boost (SPEC 39)

## A (left) click fires the boost -- the game is played with the mouse alone (a tap on a touch screen).
## Two fingers on a touch screen: the distance between them drives the same zoom ladder (SPEC 63).
## Returns true when the event was a pinch (and is therefore not driving input).
func _handle_touch_pinch(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
			_pinch_span = 0.0
		return _touches.size() >= 2
	var drag := event as InputEventScreenDrag
	if drag == null or not _touches.has(drag.index):
		return false
	_touches[drag.index] = drag.position
	if _touches.size() < 2:
		return false
	var keys := _touches.keys()
	var span: float = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
	if _pinch_span <= 0.0:
		_pinch_span = span
		return true
	if absf(span - _pinch_span) > PINCH_PIXELS:
		_apply_zoom(_zoom_step + (1 if span > _pinch_span else -1), false, true)
		_pinch_span = span
	return true


static func _is_boost_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false


## Fires the player's boost if the meter is full and the car is racing. True if it went off.
func try_boost() -> bool:
	if phase != Phase.RACING or spectator or _wreck_left > 0.0 or _resume_hold_left > 0.0:
		return false
	if pause_menu != null and pause_menu.is_open():
		return false
	return car.fire_boost()


func _on_car_boost_fired() -> void:
	Audio.boost()


## The meter just filled: a chime, and the first time in a race, a word on how to use it.
func _check_boost_ready() -> void:
	var ready := car.is_boost_ready()
	if ready and not _boost_was_ready:
		Audio.boost_ready()
		if not _boost_hint_shown:
			_boost_hint_shown = true
			hud.flash_message("BOOST READY - click", Color(1.0, 0.8, 0.2))
	_boost_was_ready = ready


## Alt-tabbing or clicking another window stops mouse motion from arriving, which would leave the car
## driving at a stale, usually far-away cursor. Pause instead.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if not is_inside_tree() or phase == Phase.FINISHED or pause_menu == null or pause_menu.is_open() or online:
		return
	pause_race()


func pause_race() -> void:
	if phase == Phase.FINISHED:
		return
	_clear_transient_hud()
	if online:
		# The other players keep racing: the menu opens over a live race.
		pause_menu.open()
		return
	Audio.set_engine_active(false)
	get_tree().paused = true
	pause_menu.open()


## Clears the two transient HUD lines (the OFF TRACK warning and the lap flash) whenever the car stops
## being simulated. Without this the "Ready" hold after a pause drew the hint on top of a stale
## OFF TRACK or "Lap 2: 0:21.8", both centred in the infield, both unreadable (decision 30.8).
func _clear_transient_hud() -> void:
	hud.set_off_track(false)
	hud.clear_flash()
	# SPEC 122: and the condition chips. Whatever is wrong with the car, nothing about it is actionable
	# while the car is not being simulated, and the strip sits over the finish card.
	# SPEC 111: the big word too ("3", "Ready", "WRECKED!") -- the menu's panel is opaque, but the audit
	# cannot know that, and every resume path below puts the right word back.
	hud.hide_countdown()


func resume_race() -> void:
	pause_menu.close()
	if online:
		if phase == Phase.COUNTDOWN:
			hud.show_countdown("Waiting..." if _waiting_start else _last_countdown_text)
		_confine_mouse()
		return
	get_tree().paused = false
	_clear_transient_hud()
	# Short "Ready" hold (car frozen with its velocity kept, timer stopped, rope preview shown) so a cursor
	# left on the Resume button does not yank the car off the track. During the countdown the same hold is
	# guaranteed by rewinding the countdown, so at least RESUME_HOLD_TIME of rope preview remains.
	if phase == Phase.RACING:
		# A solo race was paused, so the clock may stop for the hold too; it never stops online.
		_resume_hold_left = RESUME_HOLD_TIME
		_hold_running = online
		_go_time_left = 0.0
		hud.show_countdown("Ready")
		_update_rope_preview()
	elif phase == Phase.COUNTDOWN:
		_countdown_time = minf(_countdown_time, 3.0 * COUNTDOWN_STEP - RESUME_HOLD_TIME)
		_last_countdown_text = ""
		_update_countdown(0.0)
		_update_rope_preview()
	else:
		_confine_mouse()


## Keeps the cursor inside the window while driving: the cursor position *is* the control, so a cursor
## that leaves the window freezes the input target at a long, taut rope.
## SPEC 133: WHERE THE ROPE PULLS BEFORE THE PLAYER HAS TOUCHED THE MOUSE.
##
## The lights went green and the car swung round -- "the machines are looking in the opposite direction,
## but when the timer starts they immediately rotate", on every track. The grid was never wrong: the
## headings measure dead-on and the models are drawn facing exactly where the cars face. What happened
## is that `_begin_racing` unlocked the car onto `get_input_target()`, which is the raw mouse, wherever
## it was left -- and on a circuit whose start straight runs WEST (the Circle starts at 168 degrees, the
## Switchback used to start at 180) a pointer anywhere right of the car, including the middle of the
## screen where it naturally sits, is a rope pulling back down the road. The car obeyed it. That is not
## a bug in the placement, it is the game acting on an instruction the player never gave.
##
## So it does not act on one. Until the mouse actually MOVES, the rope points down the road ahead of the
## car; the first flicker of the pointer hands control over and it is never taken back. Nothing warps
## the player's cursor -- moving somebody's pointer for them is worse than the problem.
## Only a MOUSE is second-guessed. `use_mouse` off means somebody is driving this car on purpose -- a
## script, a test, a replay -- and a target set on purpose is an instruction, not a pointer left lying
## where the last screen put it.
func _player_target() -> Vector2:
	if _cursor_taken or not car.use_mouse:
		return car.get_input_target()
	return car.position + Vector2.from_angle(car.heading) * START_ROPE


func _confine_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED


func restart_race() -> void:
	Audio.set_engine_active(false)
	if online:
		_net_to_lobby()
		return
	GameState.restart_race()


## The pause / finish "Tracks" button and Esc on the finish screen (SPEC 16.1): back to the select
## screen, which is where the player picks the next track. The title menu is one more Esc away.
func _on_main_menu_requested() -> void:
	Audio.set_engine_active(false)
	if online:
		Net.leave()
	GameState.go_to_menu()


func _on_menu_requested() -> void:
	Audio.set_engine_active(false)
	if online:
		Net.leave()
		GameState.go_to_menu()
		return
	GameState.go_to_track_select()


func _on_lap_completed(lap: int, lap_time: float) -> void:
	if lap < lap_tracker.total_laps:
		hud.flash_lap(lap, lap_time)


## SPEC 135: the self-destruct. Damaged enough, not already a fireball, and off cooldown.
func try_self_destruct() -> bool:
	if not can_self_destruct():
		Audio.beep(false)
		return false
	_destruct_left = DESTRUCT_COOLDOWN
	hud.flash_message("Scrapped it", Color(1.0, 0.5, 0.25))
	car.self_destruct()
	return true


func can_self_destruct() -> bool:
	# Or on two rims: a car on two burst tyres cannot be steered, which is the same dead end as a dead
	# engine, and a dead engine already reads as 100 % damage so it is in on the damage test alone.
	return phase == Phase.RACING and _wreck_left <= 0.0 and not spectator \
			and _destruct_left <= 0.0 and not car.is_wrecked() \
			and (car.get_damage() >= DESTRUCT_DAMAGE or car.get_burst_count() >= 2)


func _tick_destruct(delta: float) -> void:
	if _destruct_left > 0.0:
		_destruct_left = maxf(_destruct_left - delta, 0.0)
	hud.set_self_destruct(can_self_destruct(), _destruct_left, car.get_damage(), DESTRUCT_DAMAGE)


## SPEC 128: A CAR THAT CANNOT MOVE IS A BUG, SO THE GAME FIXES IT. Not a rescue for a slow lap and not
## a way out of a crash: the test is that the player is pulling hard and the car is going nowhere, for
## `STUCK_TIME` on end. That is a car wedged in geometry, which no amount of driving will solve.
##
## It is deliberately not a reward. Nothing explodes, nothing is repaired, the clock does not stop and
## the car is set down facing along the road at the point it is already at -- so being lifted out costs
## exactly the seconds it took to notice, and is never better than driving.
func _tick_stuck(delta: float) -> void:
	if spectator or _wreck_left > 0.0 or car == null or not car.visible:
		_stuck_for = 0.0
		return
	var trying: bool = car.get_target_speed() >= STUCK_PULL * car.max_speed
	if not trying or car.get_speed() > STUCK_SPEED \
			or car.seconds_since_contact() < STUCK_NOT_SHOVED:
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for < STUCK_TIME:
		return
	_stuck_for = 0.0
	_free_stuck_car()


## Sets the car back down on the road where it already is, pointing the way the track goes. Damage,
## tyres and bodywork are untouched -- this un-wedges a car, it does not fix one.
func _free_stuck_car() -> void:
	var idx := track.get_nearest_index(car.position)
	var n := track.get_point_count()
	var h := (track.centerline[(idx + 1) % n] - track.centerline[posmod(idx - 1, n)]).angle()
	car.reset_to(track.centerline[idx], h, true)     # `true`: the damage stays on the car
	car.unlock()
	hud.flash_message("BACK ON THE ROAD", Color(0.75, 0.82, 0.9), 0)


## SPEC 57: online, once everyone else has finished or left, the last player is given ALONE_GRACE seconds
## and then the race is called -- driving the remaining laps alone is not a race.
func _tick_alone(delta: float) -> void:
	if not online or spectator or phase != Phase.RACING:
		return
	var others := 0
	for r in rivals:
		if bool(r.get("gone", false)) or bool(r["finished"]):
			continue
		others += 1
	if others > 0:
		_alone_left = -1.0
		return
	if _alone_left < 0.0:
		_alone_left = ALONE_GRACE
		hud.flash_message("Last one running - %d s" % int(ALONE_GRACE), Color(1.0, 0.85, 0.3))
	_alone_left -= delta
	if _alone_left <= 0.0:
		_alone_left = -1.0
		_last_one_home = true
		finish_race(lap_tracker.total_time, Array(lap_tracker.lap_times))


## A hit taken by a tyre wall (SPEC 49): tyres are knocked out of it and stay on the road.
func _on_wall_tyres_hit(at: Vector2, force: float) -> void:
	if props == null or force < 60.0:
		return
	var inward := (track.world_size * 0.5 - at).normalized()
	props.add_loose_tyres(at + inward * 10.0, inward, force, 1 if force < 220.0 else 2)
	Audio.impact(clampf(force / 700.0, 0.1, 0.6))


## Track limits (SPEC 49): this lap has spent too long off the road, so its time will not count.
func _on_lap_limits_lost() -> void:
	hud.flash_message("Track limits - lap time won't count")


func _on_checkpoint_passed(_checkpoint: int) -> void:
	track.set_next_checkpoint(lap_tracker.next_checkpoint)


## The car came back over the line with a checkpoint still outstanding: say so, otherwise the only symptom
## is a lap counter that never advances.
## SPEC 122: the lap number a missed gate spoiled, so the chip can clear itself on the next one.
var _void_lap: int = -1
## SPEC 128: the last condition state pushed to the HUD, so the list is rebuilt only when it changes.


func _on_lap_voided(_missing_checkpoint: int) -> void:
	# Priority 3: louder than the guide's MISSED CHECKPOINT (2), which would otherwise take the slot on
	# the same tick -- the lap being lost is the news; the arrow is already pointing at the gate.
	hud.flash_message("Lap not counted - checkpoint missed", Hud.WARN_COLOR, 3)
	# SPEC 122: ... and it stays said. A two-second banner is not enough for a fact that holds for the
	# rest of the lap; the chip clears itself when the next lap starts.
	_void_lap = lap_tracker.current_lap


## SPEC 132: the one thing the chips said that was worth saying. Everything else on that strip was the
## player's own last few seconds read back to them; this is the only line that is NEWS -- the game is
## about to pick the car up and put it down somewhere else -- and it is the only one you can act on, by
## driving off and cancelling it. The hint slot is empty during a race, so it goes there.
func _tick_stuck_notice() -> void:
	var left := STUCK_TIME - _stuck_for
	if _stuck_for >= STUCK_WARN_AT:
		var says := "STUCK  -  freeing the car in %d" % maxi(ceili(left), 1)
		if hud.get_hint() != says:
			hud.set_hint(says)
	elif hud.get_hint().begins_with("STUCK"):
		hud.set_hint("")


## SPEC 124: what the car went through and finished anyway. One line, facts only, no payout -- see
## `FinishScreen.set_survival`. Empty for a clean race, which is most of them.
func _survival_line() -> String:
	var bits := PackedStringArray()
	var body: CarBody = car.get_body()
	if car.body_parts_enabled and body != null:
		var wheels := 0
		for i in CarBody.WHEELS:
			if body.state(i) == CarBody.State.GONE:
				wheels += 1
		var panels := body.gone_count() - wheels
		if wheels > 0:
			bits.append("on %d wheel%s" % [4 - wheels, "" if 4 - wheels == 1 else "s"])
		if panels > 0:
			bits.append("%d panel%s gone" % [panels, "" if panels == 1 else "s"])
	elif car.parts_enabled and car.lost_parts() > 0:
		bits.append("%d piece%s gone" % [car.lost_parts(), "" if car.lost_parts() == 1 else "s"])
	if car.damage_enabled and car.is_engine_dead():
		bits.append("engine dead")
	if car.tyres_enabled and car.get_burst_count() > 0:
		bits.append("%d flat" % car.get_burst_count())
	if bits.is_empty():
		return ""
	return "FINISHED  " + ", ".join(bits)


## SPEC 122: what is still wrong with the car, worst first -- the persistent half of the warnings. The
## status slot shows the one word that matters this instant; the banner announces changes; this says
## what has not gone away, and what to do about it.
func finish_race(total_time: float, lap_times: Array) -> void:
	if phase == Phase.FINISHED:
		return
	phase = Phase.FINISHED
	_wreck_left = 0.0
	car.visible = true
	car_effects.stop_burning()
	hud.hide_wreck()
	# The car is not locked: it keeps simulating with a slack rope and brakes to a stop; the rope is hidden.
	car.rope_visible = false
	_resume_hold_left = 0.0
	lap_tracker.stop()
	hud.set_off_track(false)
	hud.set_hint("")            # SPEC 132: nothing about the car is actionable once it is over
	finish_screen.set_survival(_survival_line())
	hud.set_drift(false, 0.0, 0.0)
	hud.set_hint("")
	hud.hide_countdown()
	# SPEC 111: the results card is the screen now -- the tower, the map, a lingering flash and the
	# arrow all go, so nothing sits under or over it ("UI elements overlap the leaderboard and the map").
	hud.set_board_visible(false)
	hud.set_minimap_visible(false)
	hud.clear_flash()
	if guide != null:
		guide.hide_guide()
	_go_time_left = 0.0
	hud.update_race_info(lap_tracker.current_lap, lap_tracker.total_laps,
			lap_tracker.current_lap_time, total_time, lap_tracker.best_lap_time)
	if not _finish_order.has(car):
		_finish_order.append(car)
	_player_place = _finish_order.find(car) + 1
	if online:
		Net.send_event("finish", my_key, total_time, net_room)
	finish_screen.set_place(_player_place, _field_size())
	finish_screen.set_standings(get_standings_lines())
	# Laps that lost track limits (SPEC 49) still count as laps -- they just cannot set a lap record.
	var record_laps: Array = []
	for i in lap_times.size():
		var voided: bool = i < lap_tracker.voided_laps.size() and bool(lap_tracker.voided_laps[i])
		record_laps.append(INF if voided else float(lap_times[i]))
	var result: Dictionary = GameState.submit_result(track_id, total_time, record_laps)
	var best_lap := INF
	for t in record_laps:
		best_lap = minf(best_lap, float(t))
	finish_screen.show_results(GameState.get_track_name(track_id), total_time, lap_times, best_lap,
			bool(result.get("new_best_lap", false)), bool(result.get("new_best_total", false)),
			GameState.get_best_lap(track_id), GameState.get_best_total(track_id))
	var medal := medal_line(track_id, car.car_id, best_lap)
	finish_screen.set_medal(int(medal[0]), String(medal[1]))
	finish_screen.set_reward(_pay_out(int(medal[0])))
	if _last_one_home:
		finish_screen.set_reward("Everyone else left")


## SPEC 56: coins for the result, the bonus for a first win and for a first gold, and whatever track that
## opened. Online races pay nothing (there would be nothing to stop a room of bots printing coins), and
## neither does a solo time trial -- there was nobody to beat.
func _pay_out(medal: int) -> String:
	if online or spectator:
		return ""
	var gold_car := car.car_id if medal >= Medals.GOLD else ""
	var paid: Dictionary = GameState.reward_race(track_id, _player_place, _field_size() - 1, gold_car)
	if int(paid["coins"]) <= 0:
		return ""
	var parts: Array = ["+%d coins" % int(paid["coins"])]
	if _spin_coins > 0:
		GameState.add_coins(_spin_coins)                 # SPEC 110: the spins' purse
		parts.append("+%d for spins" % _spin_coins)
	if bool(paid["gold"]):
		parts.append("gold bonus")
	# SPEC 117: a win does not open anything any more -- everything is open. What it can do is put a
	# better star on the track, and that is what the line says.
	if bool(paid.get("new_star", false)):
		parts.append("%s STAR%s" % ["*".repeat(int(paid.get("stars", 1))),
				"" if int(paid.get("stars", 1)) == 1 else "S"])
	return "   ".join(parts)


# ---------------------------------------------------------------- damage, wrecks and respawn

func _on_car_impact(force: float) -> void:
	Audio.impact(clampf(force / 400.0, 0.1, 1.0))
	_try_break(car, force)


## SPEC 53/124: everything solid on the circuit, handed to every car -- the buildings and trees, plus the
## breakable walls that are still standing. Called again whenever one goes, which is at most once per
## wall per race.
func _push_solids() -> void:
	var blocks: Array[Rect2] = []
	if scenery != null:
		blocks.append_array(scenery.get_solids())
	if breakables != null:
		blocks.append_array(breakables.solids())
	car.solids = blocks
	for r in rivals:
		(r["car"] as Car).solids = blocks
	if props != null:
		props.set_solids(blocks)


## SPEC 124: did that impact go through a wall? The car that did it pays for it -- `Breakables.SPEED_COST`
## of its speed and `Breakables.DAMAGE` -- and the route is then open for everybody, for the rest of the
## race. Online, only the machine that owns the car decides, and it tells the others.
func _try_break(c: Car, force: float) -> void:
	if breakables == null or c == null or phase != Phase.RACING:
		return
	var idx := breakables.hit(c.last_impact_point(), force)
	if idx < 0 or not is_owned(c):
		return
	if not breakables.break_at(idx):
		return
	c.velocity *= 1.0 - Breakables.SPEED_COST
	c.punch(c.last_impact_point(), Breakables.DAMAGE)
	_push_solids()
	if c == car:
		hud.flash_message("WAY THROUGH OPEN", Color(1.0, 0.84, 0.3), 1)
	if online:
		# SPEC 128: the wall is what happened, `my_key` is who did it -- the server checks the second.
		Net.send_event("wall", idx, 0.0, net_room, my_key)


## SPEC 137: a wreck goes off and takes the paint off whatever is beside it. Online this runs only on
## the machine that owns the car that blew up -- everyone else is told about the damage the usual way,
## and two machines both applying the same blast would charge for it twice.
func _blast_from(source: Car) -> void:
	if source == null or (online and not is_owned(source)):
		return
	var others: Array = [car]
	for r in rivals:
		others.append(r["car"])
	var caught := Car.blast(source, others)
	if caught.is_empty():
		return
	Audio.impact(1.0)
	if source == car and caught.size() > 0:
		hud.flash_message("TOOK %d WITH YOU" % caught.size(), Color(1.0, 0.55, 0.2), 1)
	elif caught.has(car):
		hud.flash_message("CAUGHT IN THE BLAST", Color(1.0, 0.36, 0.2), 1)


func _on_car_rollover(severity: float) -> void:
	Audio.impact(clampf(0.5 + 0.5 * severity, 0.0, 1.0))


## The finish screen's medal line for a race whose best lap was `best_lap` (SPEC 39): [medal, text].
static func medal_line(track: String, car_id: String, best_lap: float) -> Array:
	var m := Medals.medal_for(track, car_id, best_lap)
	if not is_finite(Medals.ai_best_lap(track, car_id)):
		return [0, ""]
	var text := "%s MEDAL!" % Medals.medal_name(m) if m > Medals.NONE else "No medal yet"
	if m < Medals.GOLD:
		text += "   %s needs %s" % [Medals.medal_name(m + 1).capitalize(), GameState.format_time(Medals.target(track, car_id, m + 1))]
	return [m, text]


## Damage hit 100: the car explodes where it is and comes back, repaired, at the last checkpoint it passed
## after WRECK_TIME. The race clock keeps running the whole time -- the lost time is the penalty.
func _on_car_wrecked() -> void:
	if phase != Phase.RACING or _wreck_left > 0.0:
		return
	_wreck_left = WRECK_TIME
	_wreck_count += 1
	if online:
		Net.send_event("wreck", my_key, 0.0, net_room)
	car_effects.explode(car.position)
	_blast_from(car)                          # SPEC 137
	if props != null:
		props.add_fire(car.position)
	car_effects.start_burning(car.position, car.heading, WRECK_TIME)
	Audio.explosion()
	car.lock()
	car.visible = false
	hud.set_off_track(false)
	hud.set_drift(false, 0.0, 0.0)
	hud.set_hint("")
	hud.show_wreck(WRECK_TIME, WRECK_TIME)
	_go_time_left = 0.0
	_wrong_time = 0.0
	_off_road_time = 0.0
	if guide != null:
		guide.hide_guide()


func _update_wreck(delta: float) -> void:
	# The clock runs; the car does not move, so no checkpoint can be taken while it is a fireball. The
	# rivals race on.
	lap_tracker.update_race(delta, car.position, track.get_progress_index())
	_update_rivals(delta)
	_step_props(delta)
	resolve_contacts()
	hud.update_race_info(lap_tracker.current_lap, lap_tracker.total_laps,
			lap_tracker.current_lap_time, lap_tracker.total_time, lap_tracker.best_lap_time)
	car_effects.sample(delta)
	dashboard.set_held(true)
	dashboard.sample(delta)
	Audio.set_engine_active(false)
	_wreck_left -= delta
	if _wreck_left <= 0.0:
		_wreck_left = 0.0
		_respawn()
	else:
		hud.show_wreck(_wreck_left, WRECK_TIME)


## Back on the road at the last checkpoint passed, facing along the track, repaired, with the same short
## "Ready" hold a resume gets, so the cursor does not yank the fresh car straight off again.
func _respawn() -> void:
	var idx := get_respawn_index()
	var n := track.get_point_count()
	var pos := track.centerline[idx]
	var heading := (track.centerline[(idx + 1) % n] - track.centerline[posmod(idx - 1, n)]).angle()
	car.visible = true
	car.reset_to(pos, heading)
	car.repair()
	track.reset_progress(idx)
	track.update_car_progress(pos)
	car.unlock()
	car_effects.stop_burning()
	hud.hide_wreck()
	hud.hide_countdown()
	_resume_hold_left = RESPAWN_HOLD_TIME
	_hold_running = true
	hud.show_countdown("Ready")
	_guide_start_left = GUIDE_START_TIME          # SPEC 111: which way, again, after a mistake
	_update_rope_preview()


## Centerline index the car respawns at: the last checkpoint it passed (just past the line for gate 0).
func get_respawn_index() -> int:
	var idx := track.get_checkpoint_indices()
	var n := track.get_point_count()
	if idx.is_empty() or n == 0:
		return 0
	var last := posmod(lap_tracker.next_checkpoint - 1, idx.size())
	if last == 0:
		return RESPAWN_START_OFFSET % n
	return idx[last]


func is_wrecked() -> bool:
	return _wreck_left > 0.0


func get_wreck_count() -> int:
	return _wreck_count


## Engine note, tyre noise, rough ground and the over-pull scream -- read from the car and the dash.
func _feed_audio() -> void:
	var held := car.is_locked() or phase == Phase.FINISHED and car.get_speed() < 5.0
	Audio.set_engine_active(not held)
	Audio.set_engine(dashboard.get_rpm() / Gearbox.MAX_RPM, dashboard.get_throttle(),
			clampf(car.get_speed() / maxf(car.max_speed, 1.0), 0.0, 1.0))
	Audio.set_charge(car.get_boost_meter(), car.is_drifting() and not car.is_boosting())   # SPEC 110
	var slide := 0.0
	for w in car.get_wheel_states():
		if bool(w.get("is_sliding", false)):
			slide += 0.25
	Audio.set_tyres(maxf(slide, car.drift_intensity()) if car.get_speed() > 60.0 else 0.0)
	Audio.set_rough(car.get_rough() + (0.35 if car.is_off_track() and car.get_speed() > 40.0 else 0.0))
	Audio.set_drag(car.get_overpull())
	var rims := float(car.get_burst_count()) if car.tyres_enabled else 0.0
	Audio.set_scrape(clampf(rims * 0.35, 0.0, 1.0) * clampf(car.get_speed() / 300.0, 0.0, 1.0))
	Audio.set_creak(car.get_rope_strain() if car.rope_snap_enabled else 0.0)


# ---------------------------------------------------------------- grid, rivals, contact, standings

## Grid slot `k` (0 = pole): {pos, heading, index}, walked back along the centerline from the line.
func _grid_slot(k: int) -> Dictionary:
	var n := track.get_point_count()
	var back := GRID_FIRST + GRID_GAP * float(k)
	var i := 0
	var walked := 0.0
	while walked < back and n > 1:
		var prev := posmod(i - 1, n)
		walked += track.centerline[i].distance_to(track.centerline[prev])
		i = prev
	var nxt := (i + 1) % n
	var fwd := (track.centerline[nxt] - track.centerline[i]).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var stagger := track.track_width * 0.5 * GRID_STAGGER * (1.0 if k % 2 == 0 else -1.0)
	return {"pos": track.centerline[i] + right * stagger, "heading": fwd.angle(), "index": i}


func _spawn_rival(k: int, spec: Dictionary) -> void:
	var c := preload("res://scenes/car.tscn").instantiate() as Car
	c.name = "Rival%d" % (k + 1)
	add_child(c)
	c.auto_process = false
	c.use_mouse = false
	CarRegistry.apply(c, String(spec["car"]), int(spec["color"]))
	c.bounds = Rect2(Vector2.ZERO, track.world_size)            # SPEC 52
	# The AI drives with a rope like everyone else, but its rope is not drawn: only yours is (SPEC 44 --
	# five ropes at once was too busy). rope_tint stays set, should they ever be shown again.
	c.rope_visible = false
	c.rope_tint = c.body_color
	var slot := _grid_slot(int(spec.get("slot", k)))
	c.reset_to(slot["pos"], slot["heading"])
	var ai := AIDriver.new()
	ai.setup(c, track, String(spec["difficulty"]), String(spec["profile"]), k * 7919 + 17)
	ai.reset_progress(int(slot["index"]))
	ai.name = "%s %s" % [CarRegistry.get_palette(c.car_id)[int(spec["color"])]["name"],
			CarRegistry.get_display_name(c.car_id)]
	if spec.has("name"):
		ai.name = String(spec["name"])
	# The personality it was dealt, so you know who you are racing (SPEC 42).
	if String(spec.get("kind", "ai")) == "ai":
		ai.name += " - %s" % AIDriver.personality_name(String(spec["profile"]))
	c.set_on_track_provider(ai.make_on_track_provider())
	c.set_surface_provider(track.make_surface_provider())
	c.lock()
	var lt := LapTracker.new()
	lt.setup(track.get_checkpoint_positions(), track.get_checkpoint_indices(),
			track.get_point_count(), track.get_checkpoint_radius(), _race_laps)
	if track.get_point_count() >= 2:
		lt.set_start_line(track.centerline[0], track.centerline[1] - track.centerline[0])
	ai.lap_tracker = lt
	var marks := SkidMarks.new()
	marks.name = "RivalMarks%d" % (k + 1)
	marks.max_segments = 500
	add_child(marks)
	marks.set_car(c)
	marks.set_deck_probe(func(p: Vector2) -> bool: return track.is_point_on_deck(p))
	marks.clear()
	var fx := CarEffects.new()
	fx.max_puffs = GameState.puff_budget(false)                  # SPEC 54: a rival's dust is scenery
	fx.name = "RivalEffects%d" % (k + 1)
	add_child(fx)
	fx.set_car(c)
	fx.set_seed(4099 + k)
	c.rollover_started.connect(fx.on_rollover_started)
	c.rollover_recovered.connect(fx.on_rollover_recovered)
	c.hard_impact.connect(fx.on_hard_impact)
	# SPEC 124: a rival can open a route too -- it costs it exactly what it costs the player.
	c.hard_impact.connect(func(force: float) -> void: _try_break(c, force))
	# SPEC 145: a roll or a hard hit while the driver is in a big one is the incident.
	c.rollover_started.connect(func(_sev: float) -> void: _incident(c, ai, "rolled"))
	c.hard_impact.connect(func(force: float) -> void:
		if force >= INCIDENT_HIT:
			_incident(c, ai, "hit the wall"))
	c.off_track_changed.connect(func(off: bool) -> void:
		if off and c.get_speed() >= INCIDENT_OFF:
			_incident(c, ai, "went off"))
	c.tyre_burst.connect(fx.on_tyre_burst)
	c.tyre_burst.connect(func(_i: int, _at: Vector2) -> void: Audio.tyre_pop())
	c.part_lost.connect(_on_part_lost)
	c.wheel_lost.connect(_on_wheel_lost)
	c.oil_leak.connect(_on_oil_leak)
	var r := {"car": c, "ai": ai, "lap_tracker": lt, "marks": marks, "effects": fx, "wreck_left": 0.0,
			"finished": false, "name": ai.name, "difficulty": String(spec["difficulty"]),
			"profile": String(spec["profile"])}
	r["key"] = int(spec.get("key", -1))
	r["remote"] = bool(spec.get("remote", false))
	r["peer"] = int(spec.get("peer", 0))
	r["kind"] = String(spec.get("kind", "ai"))
	r["gone"] = false
	if r["remote"]:
		r["puppet"] = NetPuppet.new()
	if int(r["key"]) >= 0:
		_by_key[int(r["key"])] = r
	c.wrecked.connect(_on_rival_wrecked.bind(r))
	lt.race_finished.connect(func(_t: float, _laps: Array) -> void: _on_rival_finished(r))
	rivals.append(r)


## Drives every rival one physics frame: think, step, lap tracking, layering, marks and effects.
## A piece came off a car (SPEC 45): it lands on the track and stays there.
func _on_part_lost(pos: Vector2, vel: Vector2, color: Color, size: Vector2) -> void:
	Audio.part_crack()
	if props != null:
		props.add_debris(pos, vel, color, size)


## SPEC 142: a wheel rolls off as a loose tyre, not a sharp piece.
func _on_wheel_lost(pos: Vector2, vel: Vector2) -> void:
	Audio.part_crack()
	if props != null:
		props.add_loose_tyre(pos, vel)


func _on_oil_leak(pos: Vector2) -> void:
	if props != null:
		props.add_oil(pos)


## The rope broke (SPEC 46): a crack, and the car coasts until the cursor is back on it.
func _on_rope_snapped(at: Vector2) -> void:
	Audio.rope_snap()
	if car_effects != null:
		car_effects.on_car_contact(at, 260.0)
	hud.flash_message("Rope snapped!", Color(1.0, 0.45, 0.25))


func _on_rope_reattached() -> void:
	Audio.beep(false)


func _on_car_tyre_burst(index: int, at: Vector2) -> void:
	if car_effects != null:
		car_effects.on_tyre_burst(index, at)
	Audio.tyre_pop()
	hud.flash_message("Tyre burst!", Color(1.0, 0.45, 0.25))


## Cones and tyre stacks (SPEC 41): every car -- the player, the rivals, other players' puppets -- can hit
## them, every frame of the race, finished or not.
func _step_props(delta: float) -> void:
	if props == null:
		return
	var cars: Array = [car]
	for r in rivals:
		cars.append(r["car"])
	var hits := props.step(delta, cars)
	if hits > 0:
		Audio.impact(0.25)
	_sweep_ropes(delta, cars)


## THE ROPE IS A THING IN THE WORLD (SPEC 49). Every live rope sweeps the track it lies across: loose
## cones, tyres and car pieces are flicked aside, a standing tyre stack SNAGS it, and a rope dragged over
## the barrier frays. Snagging and fraying both strain the rope -- hold either and it snaps.
func _sweep_ropes(delta: float, cars: Array) -> void:
	if props == null or delta <= 0.0:
		return
	# SPEC 120: the rope no longer sweeps the props (`TrackProps.sweep_rope` is a stub that says why).
	# What is left is the BARRIER: a cursor parked in the concrete still saws the rope, because that is
	# the player doing something, not the scenery happening to be there.
	for c in cars:
		var a := c as Car
		if a == null or not a.visible or a.is_locked() or not a.rope_visible or a.is_rope_snapped():
			continue
		if _rope_over_barrier(a.position, a.get_rope_target()):
			a.add_rope_strain(ROPE_FRAY_WALL * delta)


## True when the rope lies across the barrier -- i.e. the cursor has been parked in the wall itself, which
## is where players go for a long rope. It costs: the rope saws on the concrete.
func _rope_over_barrier(from: Vector2, to: Vector2) -> bool:
	var m := Track.BARRIER_MARGIN
	var s: Vector2 = track.world_size if track != null else TrackData.SCREEN_SIZE
	var inside := Rect2(Vector2(m, m), s - Vector2(m, m) * 2.0)
	if not inside.has_point(to) and inside.has_point(from):
		return true
	# SPEC 53: a rope dragged over a building saws on it exactly as it does on the barrier.
	return car != null and car.segment_hits_solid(from, to)


## The tow (SPEC 49): how deep each car sits in another car's wake, measured once a frame from the real
## positions -- so it works the same for the player, the AI and another player's puppet.
func _update_slipstream() -> void:
	var cars: Array = [car]
	for r in rivals:
		cars.append(r["car"])
	for a in cars:
		var me := a as Car
		if me == null or not me.slipstream_enabled:
			continue
		if not me.visible or me.velocity.length() < SLIP_MIN_SPEED:
			me.set_slipstream(0.0)
			continue
		var best := 0.0
		for b in cars:
			var other := b as Car
			if other == null or other == me or not other.visible:
				continue
			if other.is_on_bridge_layer() != me.is_on_bridge_layer():
				continue
			if other.velocity.length() < SLIP_MIN_SPEED:
				continue
			var ahead := Vector2.from_angle(other.heading)
			var rel := me.position - other.position
			var behind := -rel.dot(ahead)                    # + = we are behind them
			if behind <= 0.0 or behind > SLIP_RANGE:
				continue
			var side := absf(rel.dot(ahead.orthogonal()))
			if side > SLIP_WIDTH:
				continue
			# Deepest right behind them and fading to nothing at the edges of the cone.
			var along := 1.0 - behind / SLIP_RANGE
			var across := 1.0 - side / SLIP_WIDTH
			best = maxf(best, along * across)
		me.set_slipstream(best)


func _update_rivals(delta: float) -> void:
	if rivals.is_empty():
		return
	var everyone: Array = [car]
	for r in rivals:
		everyone.append(r["car"])
	var now := Time.get_ticks_msec() / 1000.0
	for r in rivals:
		var c: Car = r["car"]
		var ai: AIDriver = r["ai"]
		var lt: LapTracker = r["lap_tracker"]
		if bool(r.get("remote", false)):
			_update_puppet(r, delta, now)
			continue
		if float(r["wreck_left"]) > 0.0:
			r["wreck_left"] = float(r["wreck_left"]) - delta
			lt.update_race(delta, c.position, ai.progress)
			(r["effects"] as CarEffects).sample(delta)
			if float(r["wreck_left"]) <= 0.0:
				_respawn_rival(r)
			continue
		var target := ai.compute_target(delta, everyone) if not bool(r["finished"]) else c.position
		c.physics_step(delta, target)
		# SPEC 128: a hurt rival limps, the same as the player does. It used to scrap itself after three
		# seconds on a dead engine, which was the AI's copy of a button that no longer exists.
		lt.update_race(delta, c.position, ai.progress)
		if track.has_bridge():
			c.set_bridge_layer(track.is_index_on_upper_branch_zone(ai.progress))
			c.set_bridge_scale(track.is_index_on_deck(ai.progress))
		(r["marks"] as SkidMarks).sample(delta)
		(r["effects"] as CarEffects).sample(delta)


## Every pair of cars that overlaps is pushed apart and exchanges momentum along the contact normal
## (mass-weighted, CONTACT_RESTITUTION). Each car then takes its hit (spin, tilt, damage) itself.
func resolve_contacts() -> void:
	var cars: Array = []
	if car.visible and not spectator:
		cars.append(car)
	for r in rivals:
		if (r["car"] as Car).visible and not bool(r.get("gone", false)):
			cars.append(r["car"])
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			_contact(cars[i], cars[j])
	_near_misses(cars)


## SPEC 110: a rival passed close and fast, without touching -- the boost tops up, and the pass is said.
func _near_misses(cars: Array) -> void:
	if spectator or phase != Phase.RACING or not car.visible:
		return
	var now := lap_tracker.total_time
	for c in cars:
		var other := c as Car
		if other == null or other == car:
			continue
		var d := car.position.distance_to(other.position)
		var touch := car.contact_radius() + other.contact_radius()
		if d <= touch or d > touch + NEAR_MISS_GAP:
			continue
		if (car.velocity - other.velocity).length() < NEAR_MISS_SPEED:
			continue
		var key := other.get_instance_id()
		if now - float(_near_at.get(key, -99.0)) < NEAR_MISS_EVERY:
			continue
		_near_at[key] = now
		car.add_boost_charge(NEAR_MISS_CHARGE)
		hud.flash_message("NEAR MISS  +BOOST", Color(1.0, 0.8, 0.2), 0)


## SPEC 110: the spin watches -- a rival the player hit hard is watched for a spin, and the spin is paid
## into the race's purse, chained when the hits come quickly.
func _tick_spins(delta: float) -> void:
	var i := _spins.size() - 1
	while i >= 0:
		var w: SpinWatch = _spins[i]
		var pay := w.tick(delta)
		if pay >= 0:
			_spins.remove_at(i)
			if pay > 0:
				var now := lap_tracker.total_time
				_chain = _chain + 1 if now - _chain_at < CHAIN_WINDOW else 1
				_chain_at = now
				var mult := mini(_chain, CHAIN_MAX)
				_spin_coins += pay * mult
				hud.flash_message("%s  +%d%s" % [SpinWatch.word_for(w.acc), pay * mult,
						"  x%d" % mult if mult > 1 else ""], Color(1.0, 0.7, 0.3), 0)
		i -= 1


## SPEC 110: what the spins earned, for the card and the purse.
func get_spin_coins() -> int:
	return _spin_coins


func _contact(a: Car, b: Car) -> void:
	# SPEC 122: the broadphase is derived from the two cars, not from a number that happened to be big
	# enough for a race car. See `Car.contact_reach()`.
	var reach := a.contact_reach() + b.contact_reach()
	if a.position.distance_squared_to(b.position) > reach * reach:
		return
	if a.is_on_bridge_layer() != b.is_on_bridge_layer():
		return        # one on the figure-8 bridge, one under it
	var ca := a.get_contact_circles()
	var cb := b.get_contact_circles()
	var r2 := a.contact_radius() + b.contact_radius()
	var best := 0.0
	var normal := Vector2.ZERO
	var point := Vector2.ZERO
	for p in ca:
		for q in cb:
			var d := q - p
			var l := d.length()
			var pen := r2 - l
			if pen > best:
				best = pen
				normal = d / l if l > 0.001 else (b.position - a.position).normalized()
				point = p + normal * (Car.CONTACT_RADIUS - pen * 0.5)
	if best <= 0.0 or normal == Vector2.ZERO:
		return
	var ma := maxf(a.mass_now(), 0.05)                 # SPEC 110: a car missing panels is lighter
	var mb := maxf(b.mass_now(), 0.05)
	var push_a := -normal * best * mb / (ma + mb)
	var push_b := normal * best * ma / (ma + mb)
	var vrel := (b.velocity - a.velocity).dot(normal)
	var dva := Vector2.ZERO
	var dvb := Vector2.ZERO
	var closing := 0.0
	if vrel < 0.0:
		closing = -vrel
		var jimp := (1.0 + CONTACT_RESTITUTION) * closing / (1.0 / ma + 1.0 / mb)
		dva = -normal * jimp / ma
		dvb = normal * jimp / mb
	var own_a := is_owned(a)
	var own_b := is_owned(b)
	if not own_a and not own_b:
		return
	if own_a:
		a.apply_contact(point, push_a, dva, closing)
	if own_b:
		b.apply_contact(point, push_b, dvb, closing)
	# Sparks and a thump once per contact (not once per car).
	if closing >= minf(a.contact_min_speed, b.contact_min_speed) and car_effects != null:
		car_effects.on_car_contact(point, closing)
		Audio.impact(clampf(closing / 350.0, 0.15, 1.0))
	# SPEC 110: the player's hard hit on a rival is watched for a spin (paid in coins at the flag).
	if closing >= SPIN_WATCH_SPEED and not spectator and (a == car or b == car) and phase == Phase.RACING:
		var victim: Car = b if a == car else a
		for w in _spins:
			if (w as SpinWatch).car == victim:
				return
		_spins.append(SpinWatch.new(victim, car, false))


func _on_rival_wrecked(r: Dictionary) -> void:
	var c: Car = r["car"]
	if float(r["wreck_left"]) > 0.0:
		return
	r["wreck_left"] = WRECK_TIME
	(r["ai"] as AIDriver).notify_wreck()
	if online and not bool(r["remote"]):
		Net.send_event("wreck", int(r["key"]), 0.0, net_room)
	(r["effects"] as CarEffects).explode(c.position)
	_blast_from(c)                            # SPEC 137
	if props != null:
		props.add_fire(c.position)
	(r["effects"] as CarEffects).start_burning(c.position, c.heading, WRECK_TIME)
	Audio.explosion()
	c.lock()
	c.visible = false
	if phase == Phase.RACING:
		hud.flash_message("%s wrecked!" % String(r["name"]), Color(1.0, 0.6, 0.2))
		_start_caution(String(r["name"]), int(r["key"]))          # SPEC 145


## SPEC 145: a rival in a big one rolled or hit something hard -- that is the incident, and the car is
## a wreck. Through the real wreck path (`_hit_vital` -> `wrecked` -> `_on_rival_wrecked`), so the
## explosion, the blast, the fire and the debris are the real ones. The driver model decided the crash;
## the damage model alone would have left a hurt car limping on (a roll is 22-52 of 100, a wall hit at
## 400 px/s is 32), which is not an incident anybody would throw a flag for.
func _incident(c: Car, ai: AIDriver, how: String) -> void:
	if not ai.is_in_big_one() or not c.visible or c.is_locked() or phase != Phase.RACING:
		return
	_incidents += 1
	c._hit_vital("tank", 500.0)
	if _caution_left > 0.0:                           # it wrecked and the flag is out: say how
		hud.flash_message("CAUTION  -  %s %s" % [RaceBoard.plain_name(String(ai.name)), how],
				Color(1.0, 0.84, 0.25), 2)


## SPEC 145: the yellow flag. `announce` false: the flag came over the wire, do not send it back.
func _start_caution(who: String, key: int, announce: bool = true) -> void:
	if _caution_left > 0.0 or phase != Phase.RACING:
		return
	_caution_left = 0.001
	_cautions += 1
	_caution_order = _running_order()
	for r in rivals:
		if not bool(r.get("remote", false)):
			(r["ai"] as AIDriver).caution = true
	hud.set_caution(true)
	hud.flash_message("CAUTION  -  %s" % RaceBoard.plain_name(who), Color(1.0, 0.84, 0.25), 2)
	if online and announce and Net.is_server():
		Net.send_event("caution", key, 1.0, net_room)


func _end_caution(announce: bool = true) -> void:
	if _caution_left <= 0.0:
		return
	_caution_left = 0.0
	_caution_order = []
	for r in rivals:
		if not bool(r.get("remote", false)):
			var ai: AIDriver = r["ai"]
			ai.caution = false
			ai.caution_cap = INF
	car.speed_limit = INF
	hud.set_caution(false)
	hud.flash_message("GREEN FLAG", Color(0.55, 1.0, 0.62), 2)
	if online and announce and Net.is_server():
		Net.send_event("green", -1, 0.0, net_room)


func is_caution() -> bool:
	return _caution_left > 0.0


## SPEC 145: the cars on the road, leader first, as the standings have them NOW. The queue under the
## flag is re-read every tick: a frozen one went wrong the moment the wreck respawned somewhere else
## (left in its old place, the car behind it was capped to a ghost ahead of it; put last, it could be
## physically ahead of the car it was queued behind -- either way the field never read as bunched and
## every caution ran to CAUTION_MAX).
func _running_order() -> Array:
	var order: Array = []
	for e in get_standings():
		var c: Car = e["car"]
		if c != null and c.visible and not (c == car and spectator):
			order.append(c)
	return order


func get_caution_count() -> int:
	return _cautions


func get_incident_count() -> int:
	return _incidents


## The car ahead of `c` in the frozen order that is still on the track, or null for the leader.
func _caution_ahead_of(c: Car) -> Car:
	var i := _caution_order.find(c)
	while i > 0:
		i -= 1
		var a: Car = _caution_order[i]
		if a != null and is_instance_valid(a) and a.visible:
			return a
	return null


## Every car's ceiling under the flag: the leader at the caution pace; anyone else at the catch-up
## pace until within CAUTION_GAP of the car ahead of it in the order, then that car's own speed, so
## it can close up and cannot pass.
func _caution_cap_for(c: Car) -> float:
	var ahead := _caution_ahead_of(c)
	var top: float = c.max_speed
	if ahead == null:
		return top * CAUTION_SPEED
	# Closed up: the car ahead's own speed. Far back: the catch-up pace. Between: a blend over
	# CAUTION_CLOSE px -- arriving at 480 px/s on a car doing 200 is a shunt, not a queue (measured: the
	# pace car was rammed up to 365 px/s by the car closing on it).
	var floor_v := maxf(ahead.get_speed(), top * CAUTION_SPEED * 0.9)
	var d := c.position.distance_to(ahead.position)
	if d <= CAUTION_GAP:
		return minf(top * CAUTION_CATCH, floor_v)
	return lerpf(floor_v, top * CAUTION_CATCH, clampf((d - CAUTION_GAP) / CAUTION_CLOSE, 0.0, 1.0))


func _tick_caution(delta: float) -> void:
	if _caution_left <= 0.0:
		return
	_caution_left += delta
	_caution_order = _running_order()
	var bunched := true
	for c in _caution_order:
		var cc := c as Car
		if cc == null or not is_instance_valid(cc) or not cc.visible:
			continue
		var cap := _caution_cap_for(cc)
		if cc == car:
			if not spectator:
				car.speed_limit = cap
		else:
			for r in rivals:
				if r["car"] == cc and not bool(r.get("remote", false)):
					(r["ai"] as AIDriver).caution_cap = cap
		var ahead := _caution_ahead_of(cc)
		if ahead != null and cc.position.distance_to(ahead.position) > CAUTION_GAP:
			bunched = false
	# The server (or the only machine, offline) decides when it is green; clients hear it.
	if online and not Net.is_server():
		return
	if _caution_left >= CAUTION_MAX or (_caution_left >= CAUTION_MIN and bunched):
		_end_caution()


func _respawn_rival(r: Dictionary) -> void:
	var c: Car = r["car"]
	var ai: AIDriver = r["ai"]
	var lt: LapTracker = r["lap_tracker"]
	var idx := respawn_index_for(lt)
	var n := track.get_point_count()
	var h := (track.centerline[(idx + 1) % n] - track.centerline[posmod(idx - 1, n)]).angle()
	c.visible = true
	c.reset_to(track.centerline[idx], h)
	c.repair()
	ai.reset_progress(idx)
	c.unlock()
	(r["effects"] as CarEffects).stop_burning()
	r["wreck_left"] = 0.0


func _on_rival_finished(r: Dictionary) -> void:
	r["finished"] = true
	if not _finish_order.has(r["car"]):
		_finish_order.append(r["car"])
	if online and not bool(r["remote"]):
		Net.send_event("finish", int(r["key"]), (r["lap_tracker"] as LapTracker).total_time, net_room)


## Centerline index a car with lap tracker `lt` respawns at: its last checkpoint (just past the line
## for checkpoint 0).
func respawn_index_for(lt: LapTracker) -> int:
	var idx := track.get_checkpoint_indices()
	var n := track.get_point_count()
	if idx.is_empty() or n == 0:
		return 0
	var last := posmod(lt.next_checkpoint - 1, idx.size())
	if last == 0:
		return RESPAWN_START_OFFSET % n
	return idx[last]


## Race score: laps, then checkpoints this lap, then how far toward the next checkpoint. Cars that
## finished rank by the order they took the flag.
func race_score(lt: LapTracker, progress: int, who: Car) -> float:
	var at := _finish_order.find(who)
	if at >= 0:
		return 1.0e6 - float(at)
	var cps := track.get_checkpoint_indices()
	var c := cps.size()
	var n := track.get_point_count()
	if c == 0 or n == 0:
		return 0.0
	var nxt := clampi(lt.next_checkpoint, 0, c - 1)
	var prev := posmod(nxt - 1, c)
	var seg := posmod(cps[nxt] - cps[prev], n)
	var done := posmod(progress - cps[prev], n)
	var frac := clampf(float(done) / maxf(float(seg), 1.0), 0.0, 1.0) if done <= seg else 0.0
	var passed := (nxt - 1) if nxt > 0 else c - 1
	return float(lt.get_laps_completed() * c + passed) + frac


## The player's place right now (1 = leading), and the field size.
func get_player_place() -> int:
	if phase == Phase.FINISHED:
		return _player_place
	var mine := race_score(lap_tracker, track.get_progress_index(), car)
	var place := 1
	for r in rivals:
		if bool(r.get("gone", false)):
			continue
		if race_score(r["lap_tracker"], (r["ai"] as AIDriver).progress, r["car"]) > mine:
			place += 1
	return place


## Perf round: the board is pushed `BOARD_EVERY` apart on the race clock, not every tick -- it costs a
## row per car and a signature the tower compares, and nobody reads a timing tower at 60 Hz. The
## rivals' places (their mood) and your own position are still every tick, off ONE sort instead of
## the three `get_player_place` + `update_board` + `get_standings` used to do.
const BOARD_EVERY := 0.25
var _board_at: float = -1.0


func _update_standings() -> void:
	if rivals.is_empty():
		hud.set_race_position(0, 0)
		return
	var place := get_player_place()
	hud.set_race_position(place, rivals.size() + 1)
	var order := get_standings()
	# SPEC 110: an overtake tops the boost up -- the reward for the pass itself.
	# SPEC 128: a CLEAN one does. Any pass paid, which meant shunting the car ahead off the road and
	# taking its place paid a boost -- and the boost made the next shunt easier, so the reward compounded
	# in favour of the one thing it should never reward. A pass made without touching anybody for
	# `CLEAN_PASS` seconds is a pass; one made through somebody is just a place, and still says so.
	if _last_place > 0 and place < _last_place and phase == Phase.RACING and not spectator:
		if car.seconds_since_contact() >= CLEAN_PASS:
			car.add_boost_charge(OVERTAKE_CHARGE)
			hud.flash_message("CLEAN OVERTAKE  +BOOST", Color(1.0, 0.8, 0.2), 0)
		else:
			hud.flash_message("OVERTAKE  -  not clean, no boost", Color(0.80, 0.82, 0.86), 0)
	_last_place = place
	if _board_at < 0.0 or lap_tracker.total_time - _board_at >= BOARD_EVERY \
			or lap_tracker.total_time < _board_at:
		_board_at = lap_tracker.total_time
		hud.update_board(_board_rows_from(order))
		_apply_catch_up(order)
		hud.set_gap(_gap_text(order))
	# The rivals learn where they are running (mood: dropping a place winds a driver up).
	for i in order.size():
		for r in rivals:
			if r["car"] == order[i]["car"] and not bool(r.get("remote", false)):
				(r["ai"] as AIDriver).notify_place(i + 1)


## SPEC 110: catch-up for the rivals BEHIND the player only -- up to RIVAL_CATCHUP more pace over
## CATCHUP_RANGE checkpoints of gap, capped under the player's own top speed. Nothing for a rival ahead.
func _apply_catch_up(order: Array) -> void:
	if spectator:
		return
	var mine := -1.0
	for e in order:
		if e["car"] == car:
			mine = float(e["score"])
	if mine < 0.0:
		return
	for e in order:
		for r in rivals:
			if r["car"] != e["car"] or bool(r.get("remote", false)):
				continue
			var ai: AIDriver = r["ai"]
			var gap := mine - float(e["score"])
			ai.catch_up = RIVAL_CATCHUP * clampf(gap / CATCHUP_RANGE, 0.0, 1.0) if gap > 0.0 else 0.0
			ai.speed_cap = car.max_speed * CATCHUP_CAP


## SPEC 110: the dashboard's GAP -- metres to the car ahead (negative), or the lead over the car behind
## when first (positive). "" alone on the track.
##
## SPEC 127: ONLY BETWEEN TWO CARS THAT ARE STILL RACING. `race_score()` gives a car that has taken the
## flag `1.0e6 - its place`, which is how the standings keep finishers above everybody else -- and the
## gap is a difference of scores in CHECKPOINTS, so the instant one car finished the readout became
## about a million checkpoints of distance: "-33000000 m". Two finishers were no better, a difference of
## one place reading as a plausible and completely meaningless 33 m.
##
## There is no distance between a car on the road and a car that has stopped racing, so the nearest car
## either side that is still going is the one to measure against, and if there is none there is nothing
## to say.
func _gap_text(order: Array) -> String:
	if spectator or order.size() < 2:
		return ""
	var i := -1
	for k in order.size():
		if order[k]["car"] == car:
			i = k
	if i < 0 or not _still_racing(order[i]):
		return ""
	# The nearest car ahead that is still on the road; failing that, the nearest one behind.
	var other := {}
	var ahead := true
	for k in range(i - 1, -1, -1):
		if _still_racing(order[k]):
			other = order[k]
			break
	if other.is_empty():
		ahead = false
		for k in range(i + 1, order.size()):
			if _still_racing(order[k]):
				other = order[k]
				break
	if other.is_empty():
		return ""
	var cps := maxi(track.get_checkpoint_indices().size(), 1)
	var px_per_cp := float(track.get_point_count()) * TrackData.SAMPLE_SPACING / float(cps)
	var gap_px := absf(float(other["score"]) - float(order[i]["score"])) * px_per_cp
	var metres := int(round(gap_px * TrackRegistry.METRES_PER_PX))
	return ("-%d m" if ahead else "+%d m") % metres


## SPEC 127: has this car NOT taken the flag yet? A finisher's score is a sentinel, not a position, and
## nothing that measures distance may be handed one.
func _still_racing(entry: Dictionary) -> bool:
	return _finish_order.find(entry["car"] as Car) < 0


## Everyone in race order: the cars that took the flag first, in the order they took it, then the rest by
## how far they have got. [{car, name}, ...]
func get_standings() -> Array:
	var entries: Array = []
	if not spectator:
		entries.append({"car": car, "name": GameState.get_player_name(),
				"score": race_score(lap_tracker, track.get_progress_index(), car)})
	for r in rivals:
		if bool(r.get("gone", false)):
			continue
		entries.append({"car": r["car"], "name": String(r["name"]),
				"score": race_score(r["lap_tracker"], (r["ai"] as AIDriver).progress, r["car"])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return entries


## The running order for the corner board (SPEC 55): place, name, the car's own colour, the lap it is on,
## and whether it has finished or dropped out.
func get_board_rows() -> Array:
	return _board_rows_from(get_standings())


## The board rows for a standings list already computed (`get_standings()`).
func _board_rows_from(list: Array) -> Array:
	var rows: Array = []
	# SPEC 111: laps down are counted against the best car still running -- in whole laps of the
	# running order, so a car ten metres behind the leader at the line is not "a lap down" for a moment.
	var cps := maxi(track.get_checkpoint_indices().size(), 1)
	var lead := -INF
	for e in list:
		var s := float(e.get("score", -INF))
		if s < 1.0e5 and s > lead:
			lead = s
	for i in list.size():
		var e: Dictionary = list[i]
		var c := e["car"] as Car
		var lt: LapTracker = lap_tracker
		var out := false
		if c != car:
			for r in rivals:
				if r["car"] == c:
					lt = r["lap_tracker"]
					out = bool(r.get("gone", false))
					break
		var score := float(e.get("score", 0.0))
		var down := 0
		if lead > -INF and score < 1.0e5:
			down = int(floor((lead - score) / float(cps) + 1.0e-4))
		rows.append({"place": i + 1, "name": String(e["name"]), "color": c.body_color,
				"lap": lt.current_lap, "laps": lt.total_laps, "you": c == car,
				"finished": lt.is_finished(), "out": out, "down": maxi(down, 0)})
	return rows


## SPEC 111: which way. One arrow, the loudest case wins: WRONG WAY over the road arrow over the start
## arrow. The track's direction at centerline index `i` is the chord round it.
func track_direction_at(i: int) -> Vector2:
	var n := track.get_point_count()
	if n < 4:
		return Vector2.RIGHT
	return (track.centerline[(i + 3) % n] - track.centerline[posmod(i - 1, n)]).normalized()


## The gate the car has gone past without taking it, or -1. "You can miss a checkpoint by accident and
## then do the whole circle again": the lap tracker keeps waiting for that gate, so every later gate and
## the line are refused until the car comes back for it. The car's progress is measured past the gate's
## own index, beyond the window the tracker still accepts it in; less than half a lap past, because
## further than that the way to the gate is forward again.
func missed_checkpoint() -> int:
	if lap_tracker == null or track == null or lap_tracker.is_finished():
		return -1
	var idx := track.get_checkpoint_indices()
	var n := track.get_point_count()
	var nxt := lap_tracker.next_checkpoint
	if idx.is_empty() or n == 0 or nxt < 0 or nxt >= idx.size():
		return -1
	var past := posmod(track.get_progress_index() - idx[nxt], n)
	if past > LapTracker.INDEX_WINDOW + MISSED_MARGIN and past < n / 2:
		return nxt
	return -1


func _tick_guide(delta: float) -> void:
	if guide == null or spectator or track == null:
		return
	var n := track.get_point_count()
	if n < 4:
		guide.hide_guide()
		return
	var racing := phase == Phase.RACING and _wreck_left <= 0.0
	var i := track.get_progress_index() if phase == Phase.RACING else track.get_nearest_index(car.position)
	var dir := track_direction_at(i)
	if racing and _guide_start_left > 0.0:
		_guide_start_left -= delta
	# A gate left behind: the big arrow points straight at it, and going back for it is not a wrong way.
	var missed := missed_checkpoint() if racing else -1
	if missed >= 0:
		_wrong_time = 0.0
		var to := track.get_checkpoint_positions()[missed] - car.position
		if to.length() > 1.0:
			guide.show_at(car.position + to.normalized() * GUIDE_NEAR, to.angle(), GuideArrow.Kind.CHECKPOINT)
		_wrong_say_left -= delta
		if _wrong_say_left <= 0.0:
			_wrong_say_left = WRONG_WAY_EVERY
			hud.flash_message("MISSED CHECKPOINT  -  go back to the gate",
					GuideArrow.COLORS[GuideArrow.Kind.CHECKPOINT], 2)
		return
	# Against the track: fast enough to mean it, and for long enough to be sure.
	var v := car.velocity
	var speed := v.length()
	if racing and speed > WRONG_WAY_SPEED and v.dot(dir) < -0.3 * speed:
		_wrong_time += delta
	else:
		_wrong_time = maxf(_wrong_time - delta * 2.0, 0.0)
		_wrong_say_left = 0.0
	if racing and car.is_off_track():
		_off_road_time += delta
	else:
		_off_road_time = 0.0
	if _wrong_time >= WRONG_WAY_TIME:
		# Close to the car: the camera looks the way the car is going, which is the wrong way.
		guide.show_at(car.position + dir * GUIDE_NEAR, dir.angle(), GuideArrow.Kind.WRONG_WAY)
		_wrong_say_left -= delta
		if _wrong_say_left <= 0.0:
			_wrong_say_left = WRONG_WAY_EVERY
			hud.flash_message("WRONG WAY  -  turn around", GuideArrow.COLORS[GuideArrow.Kind.WRONG_WAY], 2)
		return
	if _off_road_time >= OFF_ROAD_GUIDE_TIME:
		var to := track.centerline[i] - car.position
		if to.length() > 1.0:
			guide.show_at(car.position + to.normalized() * GUIDE_NEAR, to.angle(), GuideArrow.Kind.TO_ROAD)
			return
	if phase == Phase.COUNTDOWN or _guide_start_left > 0.0:
		# On the road ahead, following it round a bend: just past the start line on the grid (every car
		# is behind the line, and an arrow on the grid sat on the rivals), else GUIDE_AHEAD up the road.
		var ahead := i + int(GUIDE_AHEAD / TrackData.SAMPLE_SPACING)
		var k := ahead % n
		if phase == Phase.COUNTDOWN or (ahead >= n and k < 6):
			k = 6                                  # past the line, clear of the whole grid
		guide.show_at(track.centerline[k], track_direction_at(k).angle(), GuideArrow.Kind.START)
		return
	guide.hide_guide()


func is_wrong_way() -> bool:
	return _wrong_time >= WRONG_WAY_TIME


func get_standings_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var list := get_standings()
	for i in list.size():
		var e: Dictionary = list[i]
		var you := " (you)" if e["car"] == car else ""
		var tg: String = (e["car"] as Car).tag
		out.append("%d.  %s%s%s" % [i + 1, "[%s] " % tg if tg != "" else "", String(e["name"]), you])
	return out


# ---------------------------------------------------------------- multiplayer

## Does this machine simulate `c`? Its own car, and (on the server) the AI. Everything else is a puppet.
func is_owned(c: Car) -> bool:
	if not online:
		return true           # a local race simulates every car
	if c == car:
		return not spectator
	for r in rivals:
		if r["car"] == c:
			return not bool(r.get("remote", false))
	return false


## A remote car: drawn from its owner's packets, tracked for progress and standings only.
func _update_puppet(r: Dictionary, delta: float, now: float) -> void:
	if bool(r.get("gone", false)):
		return
	var c: Car = r["car"]
	var p: NetPuppet = r["puppet"]
	var smp := p.sample(now)
	if smp.is_empty():
		return
	var st: Array = smp[2]
	c.apply_net_state(st, smp[0], smp[1], delta)
	(r["ai"] as AIDriver).update_progress(c.position)
	var lt: LapTracker = r["lap_tracker"]
	var laps := int(st[Car.NET_LAPS])
	while lt.lap_times.size() < laps:
		lt.lap_times.append(0.0)
	lt.next_checkpoint = int(st[Car.NET_NEXT_CP])
	(r["effects"] as CarEffects).sample(delta)


## Sends the state of every car this machine owns (~30 Hz).
func _net_send() -> void:
	if not online:
		return
	_net_frame += 1
	if _net_frame % Net.SEND_EVERY != 0:
		return
	if not spectator:
		Net.send_car_state(my_key, car.get_net_state(lap_tracker.get_laps_completed(), lap_tracker.next_checkpoint),
				net_room)
	for r in rivals:
		if not bool(r.get("remote", false)) and int(r["key"]) >= 0:
			var lt: LapTracker = r["lap_tracker"]
			Net.send_car_state(int(r["key"]), (r["car"] as Car).get_net_state(lt.get_laps_completed(),
					lt.next_checkpoint), net_room)


func net_car_state(key: int, state: Array) -> void:
	var r: Dictionary = _by_key.get(key, {})
	if r.is_empty() or not bool(r.get("remote", false)):
		return
	(r["puppet"] as NetPuppet).push(state, Time.get_ticks_msec() / 1000.0)


func _car_for_key(key: int) -> Car:
	if key == my_key and not spectator:
		return car
	var r: Dictionary = _by_key.get(key, {})
	return r["car"] if not r.is_empty() else null


func net_event(kind: String, key: int, _data: float) -> void:
	var r: Dictionary = _by_key.get(key, {})
	match kind:
		"wreck":
			if not r.is_empty() and bool(r.get("remote", false)):
				var rc: Car = r["car"]
				(r["effects"] as CarEffects).explode(rc.position)
				(r["effects"] as CarEffects).start_burning(rc.position, rc.heading, WRECK_TIME)
				Audio.explosion()
				hud.flash_message("%s wrecked!" % String(r["name"]), Color(1.0, 0.6, 0.2))
		"caution":
			# SPEC 145: the server saw the wreck; the flag is the same flag on every screen.
			if not r.is_empty():
				_start_caution(String(r["name"]), key, false)
		"green":
			_end_caution(false)
		"wall":
			# SPEC 124: somebody opened a route. `key` is the wall; the owner of the car that did it has
			# already paid for it on its own machine, so all this does is take the wall down here too.
			if breakables != null and breakables.break_at(key):
				_push_solids()
				hud.flash_message("WAY THROUGH OPEN", Color(1.0, 0.84, 0.3), 0)
		"finish":
			var c := _car_for_key(key)
			if c != null and not _finish_order.has(c):
				_finish_order.append(c)
			if not r.is_empty():
				r["finished"] = true
			_refresh_online_results()


## The server's final order: everyone's standings are rebuilt from it.
func net_race_over(results: Array) -> void:
	var order: Array = []
	for res in results:
		var c := _car_for_key(int(res["key"]))
		if c != null:
			order.append(c)
	for c in _finish_order:
		if not order.has(c):
			order.append(c)
	_finish_order = order
	_refresh_online_results()
	if spectator or Net.bot:
		print("RACE OVER on %s:" % track_id)
		for line in get_standings_lines():
			print("  " + line)
	if Net.bot and Net.mode != Net.Mode.DEDICATED:
		get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit(0))


func _refresh_online_results() -> void:
	if phase != Phase.FINISHED or spectator:
		return
	_player_place = _finish_order.find(car) + 1
	finish_screen.set_place(_player_place, _field_size())
	finish_screen.set_standings(get_standings_lines())


func _field_size() -> int:
	var n := 0 if spectator else 1
	for r in rivals:
		if not bool(r.get("gone", false)):
			n += 1
	return n


## A player disconnected: their car leaves the track.
func net_peer_left(peer: int) -> void:
	for r in rivals:
		if String(r.get("kind", "")) == "human" and int(r.get("peer", 0)) == peer:
			r["gone"] = true
			(r["car"] as Car).visible = false
	if phase == Phase.RACING:
		hud.flash_message("A player left the race", Color(1.0, 0.8, 0.3))


func _net_to_lobby() -> void:
	Audio.set_engine_active(false)
	Net.return_to_lobby(net_room)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Net.unregister_race(self)


## Multiplayer runner tags: the first letter of each driver's name and how many before them share it
## ("Steph" -> S1, then "Sam" -> S2), in grid-entry order; AI rivals are AI1, AI2 ... {key: tag}.
static func runner_tags(entries: Array) -> Dictionary:
	var out := {}
	var counts := {}
	var ai := 0
	for e in entries:
		if String(e["kind"]) == "ai":
			ai += 1
			out[int(e["key"])] = "AI%d" % ai
			continue
		var letter := "P"
		for ch in String(e["name"]).strip_edges():
			if ch.to_upper() != ch.to_lower():
				letter = ch.to_upper()
				break
		counts[letter] = int(counts.get(letter, 0)) + 1
		out[int(e["key"])] = "%s%d" % [letter, counts[letter]]
	return out
