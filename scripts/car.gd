class_name Car
extends Node2D
## The player's car, driven by a spring-like "rope" toward a target point (normally the mouse cursor).
##
## The rope *input* layer is unchanged (SPEC 1.2): distance -> target speed, slack radius brakes, the
## misaligned-rope floor fades with speed, the off-track crawl cap and the screen clamp are as they were.
## Underneath it, the old single-body "turn the heading, decay the lateral velocity" model has been
## replaced by a four-wheel tire + suspension model (SPEC 7):
##
##   * every wheel has a load (from a per-corner spring-damper fed by weight transfer), a slip angle and a
##     saturating tire curve, so the car breaks away and drifts when it is asked for more than it has;
##   * yaw is tire torque **plus a steering assist** that fades out as the rear tires saturate, so below
##     the limit the car steers exactly as it always did and past it the tires alone decide;
##   * lateral load transfer plus a "trip" shock (a barrier clip, or a sideways scrub across a surface
##     change) can put the car on two wheels and roll it over, after which it always rights itself.
##
## Hand-written kinematics (no physics bodies). `physics_step()` works without the node being in the tree,
## contains no randomness and no time-of-day input, and never produces NaN/INF.
## Art is drawn facing +X; node `rotation` == `heading`.

signal off_track_changed(is_off: bool)
## Emitted once when the car goes over: `severity` 0..1 drives the animation length and the effects.
signal rollover_started(severity: float)
## Emitted once when control comes back after a rollover.
signal rollover_recovered()
## px/s of velocity removed by the barrier clamp. Only above `impact_min_speed`, at most one per
## `impact_cooldown`.
signal hard_impact(force: float)
## SPEC 122: a long slide caught and driven out of, straight and clean. Carries how many seconds the
## slide ran for, so the mode can decide what it is worth.
signal clean_exit(slide_seconds: float)
signal drift_started()
signal drift_ended(duration: float)
## Damage changed (0..100). Only when `damage_enabled`.
signal damage_changed(value: float)
## Damage reached 100: emitted once until `repair()` / `reset_to()`.
signal wrecked()
## SPEC 102: the engine vital reached zero. Not a wreck: the car limps from here ("ride the wreck").
signal engine_died()
## SPEC 102: a zone ("front", "rear", "left", "right") lost its last panel -- the vital behind it is open.
signal zone_bared(zone: String)

## SPEC 110: THE DRIFT CHARGE IN TIERS (Mario Kart's mini-turbo). The meter fills by drifting as before,
## but it is read in thirds: blue, orange, purple. A click spends whatever tier is charged for
## `TIER_TIMES` of `boost_time` -- so there is a commit moment every few seconds, not one per lap.
const TIER_TIMES := [0.0, 0.45, 0.7, 1.0]
const TIER_COLORS := [Color.WHITE, Color(0.35, 0.62, 1.0), Color(1.0, 0.6, 0.2), Color(0.85, 0.4, 1.0)]
## SPEC 110: a car missing panels is lighter, so it is thrown further by a bump (Smash's knockback
## grows with the damage): `mass_now()` is `mass` less LIGHT_PER_PART per lost panel, never under 60 %.
const LIGHT_PER_PART := 0.04
## SPEC 110: STRETCH AND SQUASH (Juice it or lose it). The body stretches along its nose when the rope
## snaps taut and when the boost fires, and squashes on a hit; it eases back at STRETCH_DECAY per second.
const STRETCH_BOOST := 0.14
const STRETCH_TAUT := 0.10
const SQUASH_HIT := -0.14
const STRETCH_DECAY := 9.0
## The player / AI spent a full boost meter.
signal boost_fired()
## A tyre burst (SPEC 45): wheel `index` (Car.WHEEL_LOCAL order) at `world_pos`; the car now runs on its rim.
signal tyre_burst(index: int, world_pos: Vector2)
## A piece came off the car (SPEC 45): where, how fast, its colour and size (px) -- Race drops it on the
## track as debris that stays.
signal part_lost(world_pos: Vector2, vel: Vector2, color: Color, size: Vector2)
## SPEC 142: a WHEEL came off (a wreck, or a corner torn away). It rolls, it is rubber, it does not cut.
signal wheel_lost(world_pos: Vector2, vel: Vector2)
## A badly damaged car drips oil (SPEC 46): Race leaves a slick at `world_pos`.
signal oil_leak(world_pos: Vector2)
## The rope broke (dragged too hard for too long) / was picked up again (SPEC 46).
## A hit taken by a tyre wall rather than by concrete (SPEC 49): Race spills tyres onto the road.
signal wall_tyres_hit(world_pos: Vector2, force: float)

signal rope_snapped(world_pos: Vector2)
signal rope_reattached()
## Another car hit this one (Race resolves car-to-car contact): `point` in world space, `force` the
## closing speed in px/s. Only for hits above `contact_min_speed`.
signal collided(point: Vector2, force: float)

enum RollState { GROUNDED = 0, TWO_WHEELS = 1, ROLLING = 2, RECOVERING = 3 }

const Z_UNDER_BRIDGE := 5
const Z_ON_BRIDGE := 20

const BODY_LENGTH := 36.0
const BODY_WIDTH := 18.0
const BRIDGE_SCALE := 1.12

## Wheel order is fixed and public: 0 = FL, 1 = FR, 2 = RL, 3 = RR (L/R = the car's left / right).
## +x = forward, +y = the car's right. The 26 px wheelbase / 18 px track match the drawn body.
const WHEEL_LOCAL := [Vector2(13, -9), Vector2(13, 9), Vector2(-13, -9), Vector2(-13, 9)]
const WHEEL_NAMES := ["FL", "FR", "RL", "RR"]
const WHEEL_COUNT := 4
const WHEELBASE := 26.0     # px between the front and rear axles (WHEEL_LOCAL x spread)
## SPEC 17.3 — the reference point the whole of section 11 was tuned at. `mass = MASS_REF`,
## `yaw_inertia = YAW_INERTIA_REF`, `steer_lag_time = 0`, `engine_response = INF`,
## `brake_response = INF` reproduce the pre-inertia car bit-for-bit.
const MASS_REF := 1.0
const YAW_INERTIA_REF := 210.0

const WHEEL_TRAVEL_MAX := 3.5   # px of drawn suspension travel a corner may show (see _draw)
const WHEEL_INBOARD_MAX := 7.0  # px a squatting corner may be drawn toward the body centreline
const WHEEL_OUTBOARD_MAX := 3.0 # ... and how far a lifting one may be drawn out of it
const STATIC_LOAD := 0.25
## SPEC 49: where the wake turns dirty, and how hard a tyre has to be scrubbing before it wears.
const DIRTY_AIR_FROM := 0.65
const TYRE_SCRUB_FROM := 0.80
## The temperature a car starts a race (and leaves a respawn) on: warm enough to drive, not up to heat.
const TYRE_TEMP_START := 0.5

const SURFACE_ASPHALT := "asphalt"
const SURFACE_GRASS := "grass"
const SURFACE_SAND := "sand"

## Sub-stepping: the tire is stiff, so one 60 Hz explicit step would ring. Two sub-steps at 120 Hz plus
## the per-sub-step lateral guard in TireModel make the model stable and frame-rate independent.
const MAX_SUBSTEP := 1.0 / 120.0
const MAX_SUBSTEPS := 8

# ---------------------------------------------------------------- tunables (rope layer, unchanged)

@export var slack_radius: float = 24.0          # px; no pull inside, car brakes
## SPEC 121: A ROPE IS NOT A BRAKE PEDAL. "When the machine has speed it loses the speed approaching the
## rope -- it must have inertia and not lose it so fast, that's not real." Two things used to hand the
## car its full braking force although nothing was pressing the brakes:
##
##   * the cursor crossing into the SLACK circle. A slack rope does nothing at all, so the braking now
##     fades to `coast_brake` of itself across the outer part of that circle. Inside `coast_zone` of the
##     radius it is still the full stop -- dropping the cursor on the car is the deliberate brake, and
##     that has to keep working exactly as it did.
##   * OVERSHOOTING the cursor at speed, so the rope points backwards. That is the rope hauling the car
##     back, not the brakes. It only softens where the overshoot actually happens -- just past the
##     anchor, within `rope_brake_reach` slack radii of the rim, where there is barely any rope behind
##     the car to pull with -- and it only softens when the anchor is really BEHIND (`cos(diff) < 0`).
##     Further back the rope has real length and real tension and gets all the braking it asks for, so
##     "drop the cursor on the car and stop" is untouched, and so is cornering, where the rope leads.
## SPEC 130: the inertia the player asked for is `rope_ease` below, not these two, and both were halved
## and put back. `coast_brake` is the DELIBERATE brake -- the cursor dropped onto the car -- and
## softening it cost half a second on the one control a player uses to save themselves. `rope_brake` is
## the rope round the BACK of the car hauling it in, which is not the complaint either. A rope that is
## merely short should not brake; a cursor parked on the bonnet absolutely should.
@export var coast_brake: float = 0.14
@export var coast_zone: float = 0.55            # of slack_radius: full braking inside this
@export var rope_brake: float = 0.45            # of the brakes: what a short rope pulling back manages
## SPEC 130: AND THE ROPE HAS SLACK IN IT. The rope is a rubber band, and a rubber band does not hold a
## car at an exact speed -- there is a range of lengths over which it neither pulls nor drags, and the
## car simply keeps what it has. Without it the rope is a throttle cable wired straight to a speedo:
## every pixel the cursor moves is a new speed to be chased, so easing off is braking and the car can
## never coast at all.
##
## Inside this much of `max_speed` BELOW what the car is already doing, the rope asks for nothing and
## the car keeps its speed.
##
## Two things it deliberately is not. It is not symmetric: a band this wide on the accelerating side
## costs the car its top speed (measured: 605 px/s down to 507, because the last stretch of the climb
## always falls inside the band), so going faster gets a much narrower one -- `HOLD_FASTER` of it. And
## it only applies while the rope is actually PULLING: a cursor dropped on the car is a deliberate stop
## and has to still stop it dead, which a hold band around zero would quietly prevent.
@export var rope_hold_band: float = 0.28
## SPEC 130: ZERO, measured. A band on the ACCELERATING side sounds symmetrical and costs a lap 20 to
## 25 %: every corner exit spends it before the car starts pulling, and the AI -- which modulates the
## rope constantly -- could no longer hit the times its own medals are set from. The complaint was
## about LOSING speed, and that is the side the band belongs on.
const HOLD_FASTER := 0.0
## Above this share of `max_speed` the rope is always allowed to keep pulling: a hold band across the
## last stretch of the climb means a car that gets close to its top speed and then simply stops
## climbing, which reads as the engine giving up.
const HOLD_TOP := 0.85
## SPEC 130: ... AND A ROPE CANNOT PUSH. This is the one that was actually stopping the car. With the
## cursor still AHEAD but close, the rope simply is not pulling very hard -- and the old law read that
## as "the demanded speed is now 200, you are doing 600, brake" and handed the wheels the full brakes.
## Nothing in the world was pressing them. Measured with `tools/probe_inertia.gd`: a hand that stopped
## moving took the car from 605 px/s to a standstill in 355 px, which is the whole of the complaint.
##
## A rope pointing STRAIGHT DOWN THE ROAD gets this share of the brakes and no more.
##
## Straight down the road is the whole of it. Applied to any forward rope it also softened every corner
## ENTRY -- which is a player deliberately shortening the rope to slow down, and is supposed to work --
## and the measured cost was a braking distance of 183 px becoming 332, cars running wide on a third of
## their frames, and an AI that could no longer drive the times its own medals are set from. The two
## cases look identical to a speedometer and not at all to a player: catching up to a parked cursor has
## the rope dead ahead, and braking for a corner has it swung out to the side, because that is what
## leads the car round. So the softening fades out with the angle (`EASE_ANGLE`) and a corner keeps all
## of its brakes.
##
## Behind the car is a different thing again -- that IS a rope hauling backwards -- and `rope_brake`
## above governs it; dropping the cursor ON the car is different again, and `coast_brake` covers that.
@export var rope_ease: float = 0.22
## Rad of rope angle over which the easing fades out. 0.45 is about 26 degrees: past that the rope is
## leading the car somewhere rather than trailing straight out in front of it.
const EASE_ANGLE := 0.45
@export var rope_brake_reach: float = 2.5       # slack radii past the rim before it has full authority
@export var speed_per_px: float = 2.0           # target speed gained per px beyond slack
## Tuned so full speed needs ~314 px of rope, which already cuts the tightest bends: the player has to
## shorten the rope (slow down) for corners. Pinned by the "difficulty" regression tests.
@export var max_speed: float = 580.0            # px/s
@export var acceleration: float = 520.0         # px/s^2 toward higher target speed
@export var brake_deceleration: float = 900.0   # px/s^2 toward lower target speed / in slack
@export var turn_rate: float = 3.0              # rad/s ceiling on the demanded yaw rate
@export var min_turn_factor: float = 0.35       # turning scale at standstill (0..1)
@export var off_track_max_speed: float = 58.0   # px/s cap while off track (~10% of max_speed)
@export var off_track_drag: float = 6.0         # extra exponential drag (1/s) while off track
## Exponential slowdown (1/s) while off track and still faster than the crawl cap: bleeds speed down to
## off_track_max_speed within ~0.2-0.3 s instead of stopping dead like hitting a wall.
@export var off_track_slowdown_rate: float = 12.0
@export var heading_min_speed: float = 8.0      # below this the heading is kept
## Clamp margin inside `bounds`. Wide enough that the *body* of the car (nose tip ~23 px from the
## centre) stops at the inner face of the drawn barrier instead of being cut off by the screen edge.
@export var screen_margin: float = 22.0
## SPEC 145: a ceiling the RACE puts on the car -- the pace behind the yellow flag. INF is no ceiling.
## It sits on top of everything else that costs top speed, so a car on a rim under caution is still
## slower than a whole one.
var speed_limit: float = INF
## Speed at which turning reaches full `turn_rate` (below it turning is scaled down to min_turn_factor).
@export var full_turn_speed: float = 110.0
## Minimum fraction of the target speed kept when the rope points sideways/backwards (helps a *slow* car
## swing round for a U-turn). It is faded out with speed so a fast car whose rope points backwards brakes
## instead of powering a donut.
@export var misaligned_speed_factor: float = 0.3

# ---------------------------------------------------------------- tunables (tires and yaw, SPEC 11.1)

## Total cornering stiffness at nominal load (px/s^2 per rad). Replaces the old `grip`.
## RETUNED 9000 -> 2200, below SPEC 11.1's 6000-13000 range, and this is the single most important number
## in the round. The old model's lateral force was `grip * v_lat`, i.e. an effective cornering stiffness of
## `lerpf(7, 1, v/max_speed) * v` = 580..1170 px/s^2/rad — a very soft, very slidey tire, and that slide is
## exactly what kept the old car ON the road: it points at the cursor but travels ~20 deg wide of where it
## points, so it does not cut the bend as hard as a pursuit line would. At 9000 the car tracked the cursor
## with ~2 deg of slip, cut the ellipse ends and put 39-51 % of the 192 px difficulty line on the grass.
## 2200 reproduces the old slide (measured: max 45 px off the centreline on the circle, 51 px on the
## figure 8 at 192 px, against a 55 px road edge) while still being a saturating tire.
@export var cornering_stiffness: float = 2200.0
## Total peak lateral force of the four tires (px/s^2). RETUNED 950 -> 800 (just under SPEC 11.1's
## 850-1100) together with `cornering_stiffness`: it sets the breakaway slip angle
## `alpha_peak = 1.85 * D * tire_shape_c / C` = 0.98 rad (56 deg) and keeps `tire_peak_accel *
## long_mu_ratio` (1400) above `brake_deceleration` (900). Chosen from a (C, D) grid sweep as the cell with
## the largest margin to the road edge on the 96/160/192 px lines while the 314 px line still spends
## 66 % / 81 % of its frames off the road (pin 6.2.2 needs >= 15 %).
@export var tire_peak_accel: float = 800.0
## Peak grip multiplier at `max_speed`; replaces the old `high_speed_grip`, and is what still makes a long
## rope slide wide and cut corners.
@export var high_speed_peak_factor: float = 0.78
@export var tire_shape_c: float = 1.45          # falloff past the peak (1.45 -> the tire keeps 76 % of D)
@export var load_exponent: float = 0.85         # tire load sensitivity; 1.0 = none
## Longitudinal capacity relative to the lateral peak. Kept at 1.75 (SPEC 11.1 range 1.30-1.80): with the
## softer tire the lightly loaded rear axle ran out of brake capacity under full braking and the car only
## made ~680 of its 900 px/s^2 (247 px of stopping distance against the 220 px pin).
## Lowering it to 1.15 was tried, so that the brakes could genuinely lock, and reverted: the friction
## circle then spends most of the tire on the brake/drive demand, and the 192 px difficulty line went from
## 0 % to 41 % of its frames off the road. Hard braking therefore never reaches the tire's *lateral* peak;
## the patch slide it does produce is reported through `TireModel.long_slip_start` instead, and that is
## what lays the marks.
@export var long_mu_ratio: float = 1.75
## Front share of braking. RETUNED 0.70 -> 0.55: at 0.70 the rear axle reached only 0.74-0.81 of its
## longitudinal capacity under maximum braking — LESS than the drive wheels reach at full throttle (0.80-0.90)
## — so "the rears let go under braking" was not true of the shipped numbers, and the only way to see a
## brake mark was a patch-slide threshold so low that full throttle laid marks all the way round a clean lap.
## At 0.55 against the ~78/22 load split the rear pair genuinely CLIPS (measured 1.10 of capacity, 8 frames
## of lock-up from 580 px/s) while the fronts sit at 0.64, which is the lock-up the brake marks are made of.
## Stopping distance is unaffected (measured 184 -> 186 px against the 220 px pin).
## RETUNED AGAIN 0.55 -> 0.34 in the inertia round (SPEC decision 29.27). `mass` 1.25 divides the brake
## (900 -> 720 px/s^2) AND, because the car decelerates less hard, takes weight off the front axle, so at
## 0.55 the rear pair fell from 1.10 of its longitudinal capacity to 0.71 — it stopped locking, and
## standing on the brakes laid no mark at all. 0.34 puts the rear axle back at 1.09 of capacity (the
## fronts at 0.28), i.e. the same lock-up the brake marks were always made of, at the new brake force.
@export var brake_bias: float = 0.34
## Extra mu while braking; replaces the old `brake_grip_recovery` (the forward weight transfer does the
## rest of that job now, physically).
@export var brake_grip_bonus: float = 0.40
@export var off_track_grip_factor: float = 0.45  # grass mu: the car slides much more easily on grass
## SPEC 128: HAULING OUT OF THE GRASS. Off the road the car was capped at `off_track_max_speed` and that
## was the end of it -- and the cap is reached by a rope barely longer than the slack radius, so once you
## were on the grass the cursor stopped meaning anything at all: a 200 px rope and a 900 px rope crawled
## out at exactly the same speed. The one thing the player can do about being off the road did nothing.
##
## The crawl cap is now multiplied by up to this much, in proportion to how hard the rope is being pulled
## (`_haul`, 0..1 of the car's full road speed). A light pull still crawls; a full-arm pull hauls the car
## out of the gravel at a bit over twice the crawl -- which is still a fifth of road pace, so the grass
## has lost none of its cost. What it has gained is something to do about it.
## SPEC 128: WHAT THE REST OF THE CAR DOES WHEN IT BREAKS. The component model had four consequences --
## grip, drag, pull and armour -- which is a car that only ever gets slower. These are the rest of them,
## and each is a different PROBLEM rather than more of the same one: a bent wheel makes the car wander,
## a collapsed corner makes it crash over kerbs, loose bodywork rattles and drags, a rubbing wing eats a
## tyre, a holed radiator cooks the engine if you hold it flat, a hurt drivetrain takes the top end, a
## bent chassis makes it crab, and a torn rope mount makes the rope itself unreliable. Read from
## `CarBody`, which owns what has broken; applied here, which owns what that means.
@export var toe_pull: float = 2.1              # rad/s of wander per unit of `CarBody.toe`
@export var toe_bend: float = 0.16             # rad the front wheels sit off straight, at full toe
@export var susp_sag_drop: float = 5.0         # px of compression a fully collapsed corner sits at
@export var susp_sag_grip: float = 0.35        # grip lost at a fully collapsed corner
@export var flap_drag: float = 0.16            # top speed lost with every panel hanging off
@export var flap_rattle: float = 2.2           # px of shake a flapping car carries
@export var tyre_wear_rub: float = 0.07        # tyre wear per second from a wing rubbing on it
@export var overheat_rate: float = 0.16        # of the heat gauge per second, flat out, fully holed
@export var overheat_cool: float = 0.33        # ... and how fast it comes back down off the throttle
@export var overheat_loss: float = 0.35        # of the engine's power, at a fully cooked engine
@export var crab_drag: float = 2.0             # of the car's drag added per radian of crab
@export var crab_turn_in: float = 8.0          # of the turn lost per radian, turning the hard way
@export var crab_turn_out: float = 4.0         # ... and gained turning the other
@export var mount_slack: float = 0.30          # of the rope's demand lost at a torn-out mount
@export var mount_strain: float = 1.8          # how much faster a bent mount frays the rope
@export var offroad_haul: float = 2.3
## How much of the off-road drag a full haul overcomes. Below the cap the grass applies a flat
## exponential drag whatever the throttle, which is what made a hard pull feel like a slack rope.
@export var offroad_haul_relief: float = 0.65
@export var slip_epsilon: float = 30.0          # px/s, low-speed slip-angle guard
@export var max_steer: float = 0.52             # rad, front wheel angle at parking speed
## How much more than the kinematic (Ackermann) angle the front wheels are allowed to take. The steer
## angle needed for `omega_demand` at speed v is `omega * WHEELBASE / v`; the tire also needs a slip angle
## to make its force, so the driver always turns in a little more than that. Without this speed taper the
## front wheels sit at `max_steer` at 250 px/s, which is ~10x the angle the yaw demand asks for: the car
## snaps into a yaw limit cycle and can never drive straight (measured before this was added).
@export var steer_lead: float = 1.9
@export var steer_rate: float = 7.0             # rad/s
@export var steer_response: float = 12.0        # 1/s, heading error -> demanded yaw rate
@export var assist_gain: float = 14.0           # 1/s, the steering-assist P gain
@export var assist_max: float = 26.0            # rad/s^2
## Rear **lateral** saturation where the assist starts letting go, and where it is fully released (pure
## tires = drift). Measured against lateral slip alone (not the mixed `saturation`, which is dominated by
## the brake/drive demand): a careful lap reads ~0.3, so 0.95 means what it says — the rears are genuinely
## past their peak slip angle. 0.45 was tried for the start and reverted: it releases during ordinary hard
## turn-in and the car spins (SPEC 11.1).
## `drift_release_full` RETUNED 1.60 -> 1.30. `lat_saturation` is `|alpha| / alpha_peak` and
## `|alpha| < PI/2` always (TireModel divides by a strictly positive denominator), so with the shipped
## `alpha_peak` = 0.975 rad it can never reach 1.611 — 1.60 meant "release at 89.4 deg of rear slip", i.e.
## never. Measured over 1200 runs of aggressive rope input the highest rear lateral saturation ever reached
## was 1.34. 1.30 (~74 deg of rear slip) is inside that, so full release is actually attainable. It is
## additionally clamped to 0.82 of the structural ceiling at use, so no retune can put it out of reach again.
@export var drift_release_start: float = 0.95
@export var drift_release_full: float = 1.30
## Body mass, relative to MASS_REF (SPEC 17.3). Divides the BRAKE and the yaw assist; the drive force is
## compensated (a heavier car in this game has a proportionally bigger engine), because a slower pull-away
## reads as input lag rather than weight. 1.0 reproduces the pre-round car exactly.
@export var mass: float = 1.25
## Yaw inertia (px^2). It scales the steering ASSIST and the counter-steer as well as the tire torque
## (SPEC 17.4), so it is the single "how hard is this car to rotate" knob.
##
## RAISED 210 -> 290 (SPEC decision 30.2, superseding 29.28). At the reference value 210 the whole
## mechanism was a mathematical no-op — `inertia_scale` = `YAW_INERTIA_REF / yaw_inertia` = 1.0, so
## every term was bit-identical to the pre-round car and the "rotation" axis of SPEC 17.2 shipped inert.
## 29.28 rejected the raise on one pin: `test_drift_hold`'s gentle-lead case reached 0.31 rad of body
## slip against a `< 0.30` assertion. That pin had 0.002 rad of margin at the SHIPPED value, i.e. it was
## brittle before the change and it is not a gameplay gate: `is_drifting()` is never true in that case at
## 260 or 310, the car does not "understeer into a slide", it crosses one threshold chosen before the
## inertia request existed. The two gates 17.5 does call hard are unaffected — all eight tracks lap
## within 0.05 s of the reference on the careful 96 px line and stay 0.0 % off track on both the 96 px
## and 160 px lines. The pin is moved to 0.34; the default moves.
##
## What it actually buys, measured: peak angular acceleration on a 90 deg rope yank falls 36 -> 26
## rad/s^2, and the counter-whip out of a provoked slide falls 2.33 -> 1.98 rad/s. Note that `t90` is
## NOT a monotonic function of this knob (the heading approaches 90 deg asymptotically, so a
## heavier-rotating car that overshoots gets there sooner); the metrics that do behave monotonically are
## the two above, and they are what the tests pin.
@export var yaw_inertia: float = 290.0
## How long the driver's hands need to sweep the yaw demand across its whole range (+turn_rate ->
## -turn_rate). A SLEW limit, not the first-order lag SPEC 17.4 sketched (decision 29.29): a low-pass
## filter sits inside the steering feedback loop and costs it phase margin, and at 0.09 s the gentle
## constant-radius pin oscillated into a real drift. A slew limit is invisible to any input the hands
## could follow and bites only on the flick it is here for. 0 = instant (the pre-round car).
##
## HONEST RANGE (decision 30.3). The slew rate is `2 * turn_rate / steer_lag_time`; at the default that
## is 60 rad/s^2, while `assist_max` (scaled by `inertia_scale`) already caps the yaw the demand can
## produce at ~19 rad/s^2. The limiter therefore does not bind at all below ~0.32 s: sweeping 0.00 ->
## 0.16 moves the flick's zero crossing by three frames in total. The knob is real above that; below it
## the car behaves as if it were 0. The claim previously carried here and in README:207 — that "above ~0.13
## the committed 224 px line starts to leave the road on figure8" — does not reproduce: measured
## off-track on that line is 0.0 % at 0.00/0.05/0.10, 0.1 % (2 frames of ~1510) at 0.13 and 0.16, and
## back to 0.0 % at 0.25 and 0.40. It is a two-frame blip, not a ceiling.
@export var steer_lag_time: float = 0.10        # s
## First-order lags on the longitudinal demand: the engine takes a moment to come on, the brakes take
## less. Integrated as `1 - exp(-rate * dt)`, never `rate * dt`, so they are frame-rate independent.
## SHIPPED DISABLED (INF = instant). Decision 29.30 stands, and fixer round 1 re-measured it rather than
## taking it on trust: at 40 / 60 1/s -- the mild value the review proposed -- the committed 224 px
## autopilot spends 7.5 % of the figure-8 lap off the road, a committed racing line stops flickering its
## sliding wheels cleanly, and the drift readout stops latching below `drift_min_speed`. Three separate
## behavioural pins move, not just the autopilot's. The careful 96 px line is indeed untouched, and the
## braking distance only grows 239 -> 244 px, but the actuator-build-up axis of SPEC 17.2 cannot be
## bought at that price; `mass` already carries the longer stop it was meant to add. The mechanism
## ships and is tunable; the default is off, and decision 30.15 records the numbers so the next round
## does not have to re-derive them.
@export var engine_response: float = INF      # 1/s
@export var brake_response: float = INF       # 1/s
## Hard clamp on the yaw rate while the car is on its wheels. RETUNED 6.5 -> 4.0: 6.5 rad/s is 372 deg/s,
## and a provoked slide used to pin itself there for 10-17 frames and spin the car to ~90 deg of slip — a
## handbrake 180, not a drift. A real drift is 1-2 rad/s; `omega_demand` never exceeds `turn_rate` (3.0),
## so 4.0 leaves the steering untouched and only removes the spin. (The scripted barrel roll sets
## `_yaw_rate` directly and is not affected.)
@export var yaw_rate_max: float = 4.0
@export var low_speed_yaw_damp: float = 10.0    # 1/s below `heading_min_speed`: a parked car cannot spin

# ---------------------------------------------------------------- tunables (suspension, SPEC 11.2)

@export var susp_rest: float = 6.0              # px of compression at static load
@export var susp_max: float = 14.0              # px, bump stop
@export var susp_stiffness: float = 260.0       # 1/s^2 (~2.6 Hz)
@export var susp_damping: float = 18.0          # 1/s (zeta ~0.56): one small overshoot, no jitter
## RETUNED 1200 -> 1600 (SPEC 11.2 range 900-1600): at 1200 a full 900 px/s^2 stop put 87 % of the load on
## the front axle, leaving the rears with less brake capacity than their share of the demand.
@export var pitch_reference_accel: float = 1600.0
## Must stay above the largest lateral acceleration the tires can actually make, which is
## `tire_peak_accel * (1 + brake_grip_bonus)` = 800 * 1.4 = 1120 px/s^2 — NOT `tire_peak_accel` alone, as
## this comment used to claim. RETUNED 1200 -> 1600 so the claimed margin is real: pure cornering now tops
## out at 1120 / 1600 = 0.70 of tilt, under `two_wheel_tilt` (0.75), so tipping still needs a genuine trip
## (SPEC decision 10.9). At 1200 the true bound was 0.93, above the 0.72 threshold of the day, and a
## 250 px-lookahead lap measured exactly that.
@export var roll_reference_accel: float = 1600.0
@export var surface_bump: float = 55.0          # px/s jolt when crossing onto / off the grass
@export var bridge_bump: float = 70.0           # px/s jolt when driving onto / off the bridge deck
@export var roll_land_bump: float = 150.0       # px/s jolt when a rollover lands
@export var visual_smooth: float = 12.0         # 1/s, roll / pitch display filter
## Drawing gains for the fake-3D lean (SPEC 7.11). The raw load transfer is tiny on a 36x18 px car (the
## hardest corner the rope can drive moved the body by ONE pixel before this existed), so it is normalised
## by `*_visual_reference` and shaped by `*_visual_curve` before it is scaled by the gains.
## RETUNED: the reference used to be a hard CLAMP at 0.5, which both left a careful line invisible (a whole
## 3-lap run at the reference lookahead peaks at 0.078-0.087 of roll = 1.1 px of shift) and flattened
## everything above 0.5 to the same maximum, so a committed corner and a near-tip drew identically. The
## reference is now the roll that reads as a FULL lean and the curve (< 1) lifts the small end: 0.08 of roll
## draws 2.1 px, 0.22 draws 3.6 px, 0.5 draws 5.6 px and 0.95 draws the full 8 px.
@export var roll_visual_reference: float = 0.95
@export var pitch_visual_reference: float = 0.75
@export var roll_visual_curve: float = 0.55     # < 1 amplifies small tilts; 1.0 = the old linear ramp
@export var pitch_visual_curve: float = 0.70
@export var roll_visual_gain: float = 8.0       # px of body shift toward the loaded side at full lean
@export var pitch_visual_gain: float = 5.5      # px of body shift under full braking / acceleration

# ---------------------------------------------------------------- tunables (drift, SPEC 11.3)

## Rear **lateral** saturation needed for is_drifting(). RETUNED 0.95 -> 0.35 with the same change of
## meaning as `drift_release_start`: 0.95 of the *mixed* saturation was reachable at full throttle in a
## dead straight line, and as pure sideways slide it needed the car to be ~50 deg sideways. Measured
## against lateral slip alone: a careful lap peaks at 0.25, a held power slide never falls below 0.44.
@export var drift_rear_sat: float = 0.35
@export var drift_min_speed: float = 140.0      # px/s
## Once a drift has STARTED it stays reported down to this speed while the car is still genuinely sideways.
## A nose-relative slide bleeds to ~130 px/s while still 42 deg sideways, so the plain `drift_min_speed`
## gate switched the HUD readout off at a moment the player can plainly see the car drifting (measured:
## `is_drifting()` went false at 131 px/s with -0.74 rad of body slip).
@export var drift_sustain_speed: float = 90.0   # px/s
@export var drift_sustain_slip: float = 0.45    # rad of body slip that keeps a started drift alive
## rad of body slip. RETUNED 0.20 -> 0.30: a careful 192 px line reaches 0.19 rad, so 0.20 left the drift
## flag one measurement away from firing on a clean lap. A held drift runs at 0.6-0.9 rad.
@export var drift_min_slip: float = 0.30
@export var drift_grace: float = 0.35           # s under the threshold before the drift timer resets
@export var slide_threshold: float = 0.90       # wheel saturation for is_sliding
@export var slide_min_speed: float = 35.0       # px/s of patch slide for is_sliding
## Fraction of a wheel's longitudinal capacity at which its contact patch starts to slide along the wheel
## (TireModel.long_slip_start), and how much of the forward speed a fully slipping patch reports.
## RETUNED 0.62 -> 0.88. A rear-drive car at full throttle sits at 0.80-0.90 of the rear tires' longitudinal
## capacity for most of a lap (the engine asks for `acceleration` whenever the rope is long), so a 0.62 start
## reported a sliding contact patch almost continuously: a clean, non-drifting lap laid 737 segments over a
## 2531 px track — 357 % of the lap covered in black — on wheels the tire model itself reported as gripping.
## 0.88 means the patch starts to slide only as the tire runs out, which with `brake_bias` 0.55 is a rear
## lock-up under hard braking and a genuine slide in a corner.
@export var long_slip_start: float = 0.88
@export var long_slip_weight: float = 0.45
## Body slip angle a slide settles at, at the NOMINAL input (cursor ~45 deg off, rope at the full-speed
## distance). Past it the car generates a restoring yaw acceleration — the counter-steer a driver applies —
## so a provoked slide holds a usable angle instead of running on to 90 deg and scrubbing the car to a stop.
## 0.60 rad = 34 deg; careful lines never exceed ~0.20 rad.
@export var drift_hold_slip: float = 0.60
## rad the cursor ANGLE moves the held slip either way, and the factor a very SHORT rope multiplies it by.
## Without these a drift had exactly one flavour: `omega_demand` saturates at `omega_max` for any cursor
## more than ~14 deg off the nose, so 15/25/35/45/55/65 deg all converged on a bit-identical steady state
## (0.60 rad of slip, 229-233 px/s, a 77-80 px radius), and 200/300/500 px of rope did the same. The held
## angle is now a function of the two continuous axes the player actually has, so a wide cursor sustains a
## wider, slower slide and a short rope tightens it.
@export var drift_hold_spread: float = 0.26
@export var drift_hold_short_factor: float = 0.72
@export var drift_damp_gain: float = 26.0       # rad/s^2 per rad of slip past the held angle
@export var drift_damp_max: float = 14.0        # rad/s^2 ceiling on that restoring term
## Body slip past which the rope is judged against the direction of TRAVEL as well as the nose, so a
## sideways car whose cursor points where it is going keeps its power (a drift can be carried) instead of
## being braked out of the slide by the misaligned-rope fade. Above normal cornering slip (~0.2 rad).
@export var drift_carry_slip: float = 0.45
## The carry above is a speed EXEMPTION, and unbounded it is a stable fixed point: a cursor held 30-50 deg
## off the VELOCITY vector sat at exactly `max_speed` with all four tires sliding and 0.49-0.77 rad of slip
## for as long as it was held — a full-throttle donut that costs nothing. It is therefore free for
## `drift_carry_free` seconds of continuous drifting and then fades over `drift_carry_fade` to
## `drift_carry_floor` of the demanded speed, so a slide keeps its speed through a corner and a slide held
## for its own sake starts costing.
@export var drift_carry_free: float = 1.10      # s
@export var drift_carry_fade: float = 1.80      # s
@export var drift_carry_floor: float = 0.62     # fraction of the demanded speed kept by a long carry

# ---------------------------------------------------------------- tunables (rollover, SPEC 11.4)

@export var rollovers_enabled: bool = true      # global off switch (tests, possible accessibility option)
## Lateral load transfer that puts the car on two wheels. Cornering ALONE cannot reach it: the tilt target
## is `a_lat / roll_reference_accel`, and the largest lateral acceleration the tires can make is
## `tire_peak_accel * (1 + brake_grip_bonus)` = 1120, so pure cornering tops out at 1120 / 1600 = 0.70
## (measured 0.42 on the hardest clean line, 0.19 on a whole careful race). Tipping needs a trip.
@export var two_wheel_tilt: float = 0.75
@export var two_wheel_release: float = 0.55     # exit
@export var two_wheel_settle: float = 0.15      # s under the release threshold before GROUNDED
@export var two_wheel_max_time: float = 1.2     # s on two wheels before it becomes a roll
## RETUNED 190 -> 150 px/s so a hard slide that does not roll still lifts two wheels for a moment: the
## lesser "two wheels up" state the user asked for was measured 0 times in 37 000 frames of play.
@export var tip_min_speed: float = 150.0
@export var rollover_tilt: float = 1.05         # entry; unreachable without a shock
@export var roll_min_speed: float = 250.0       # px/s
@export var tilt_shock_decay: float = 4.0       # 1/s
@export var tilt_shock_max: float = 1.5
@export var impact_min_speed: float = 90.0      # px/s to emit hard_impact
@export var impact_cooldown: float = 0.25       # s between hard_impact emissions
## SPEC 126: how much of the shake is actually drawn. 1 normally, a quarter on the calm setting -- the
## mode sets it, because `Car` must not read the settings (it is built in tests with none).
@export var shake_scale: float = 1.0
## Barrier trip. RETUNED 280 -> 240 px/s with a 340 px/s normalising span (was 420) and gain 1.10 -> 1.25:
## the old numbers needed a ~420 px/s wall-normal component, which is almost unreachable because the car
## must cross the grass (and its crawl cap) to get to the wall.
@export var barrier_trip_speed: float = 240.0
@export var trip_min_tangential: float = 150.0  # px/s
@export var barrier_trip_gain: float = 1.25
@export var barrier_trip_span: float = 340.0    # px/s of normal speed that saturates the barrier trip
## Surface-change trip. RETUNED 260 -> 170 px/s with a 240 px/s span (was 400) and gain 1.55 -> 1.20:
## the reachable range of a sideways scrub onto the grass is 250-350 px/s, which used to produce a shock of
## only ~0.29 — far under any threshold — so the most plausible reckless path (slide off the road) never
## tripped the car at all. It now produces ~0.8-1.0, i.e. two wheels up and sometimes a roll.
@export var trip_slip_speed: float = 170.0
@export var trip_gain: float = 1.20
@export var trip_span: float = 240.0            # px/s of sideways slide that saturates the surface trip
@export var roll_time_base: float = 0.70        # s
@export var roll_time_per_severity: float = 0.50  # s
@export var roll_drag: float = 3.2              # 1/s
@export var roll_end_speed: float = 70.0        # px/s at the end of the roll
@export var roll_spin: float = 5.0              # rad/s at the start of the roll
@export var recover_time: float = 0.45          # s
@export var recover_speed: float = 60.0         # px/s
@export var roll_cooldown: float = 1.0          # s
@export var roll_cooldown_bonus: float = 0.12   # threshold bonus during the cooldown
@export var shake_impulse: float = 6.0          # px per unit of impact
@export var shake_decay: float = 9.0            # 1/s

# ---------------------------------------------------------------- car types (CarRegistry)
# Everything below defaults to OFF / neutral, so a bare `Car.new()` is bit-identical to the car the whole
# suite was tuned against. CarRegistry.apply() switches these on for the cars the player actually drives.

## Over-pull: the rope asks for more speed than the wheels can turn at. The excess no longer goes into
## the tires -- the rope DRAGS the car: the tires skid (lose grip), the body is pulled toward the cursor
## past its top speed, and the lateral part of that pull tips the car. Pull too hard round a corner and
## it rolls.
@export var overpull_enabled: bool = false
@export var overpull_drag: float = 520.0        # px/s^2 of drag at excess 1 (demand = 2x max speed)
@export var overpull_speed_margin: float = 0.12 # a dragged car may exceed max_speed by this fraction
@export var overpull_grip_loss: float = 0.55    # tire grip lost at excess 1
@export var overpull_tilt: float = 5.0          # tilt shock per second at excess 1, full lateral pull
@export var overpull_wobble: float = 7.0        # rad/s^2 of yaw wobble at excess 1
## SPEC 121: THE ROPE CAN PULL YOU OFF THE GROUND. "When you pull too high and fast the machines increase
## speed, but it's a rope -- so it must, like, fly?" Past `overpull_air` of over-pull the nose comes up
## and the car is AIRBORNE: the tyres do nothing at all -- no grip, no steering, no marks, no dust -- and
## the rope is the only thing acting on it, so it goes where it was already going. Ease off and it comes
## down with a bump. It is the rope's own version of a jump, and the price of yanking is that for a
## second you have no say in where you are pointed.
@export var overpull_air: float = 0.45          # over-pull at which the wheels leave the ground
## How long one hop lasts. A rope pulls sideways, not upwards, so it cannot HOLD a car in the air: past
## `air_hold` the car comes down however hard the cursor is still being yanked, and it cannot take off
## again until the pull has eased. Dragging a car flat out is therefore a series of hops -- which is what
## a dragged car does -- and each landing scrubs the tyres (`tyre_wear_land`), so the over-pull still
## costs rubber even though nothing is scrubbing while it is up there.
@export var air_rise: float = 6.0               # 1/s toward fully airborne
@export var air_fall: float = 3.2               # 1/s back down once the pull eases
@export var air_lift: float = 0.18              # how much bigger the body is drawn at full height
@export var air_land_bump: float = 120.0        # px/s of jolt on touching down
@export var air_hold: float = 1.1               # s: the longest one hop can last
@export var tyre_wear_land: float = 0.22        # wear on all four from one landing at full speed
## Off-road behaviour. `offroad_rough` / `sand_rough` > 0 make rough ground kick the car (tilt + yaw)
## in proportion to speed and suspension stiffness; the speed caps decay more slowly than the legacy
## crawl, so a fast car slides a long way on low grip instead of stopping dead.
@export var offroad_rough: float = 0.0
@export var sand_rough: float = 0.0
@export var rough_min_speed: float = 140.0      # px/s below which rough ground is harmless
@export var sand_grip_factor: float = 0.30
@export var sand_max_speed: float = 100.0       # px/s crawl cap in the sand
@export var sand_slowdown_rate: float = 2.4     # 1/s speed decay above that cap
## Damage 0..100. At 100 the car is wrecked (`wrecked` fires once); Race explodes and respawns it.
@export var damage_enabled: bool = false
## THE ROPE, per car (SPEC 39). `slack_radius` / `speed_per_px` above are its length and stiffness;
## `rope_band` is its TENSION ZONE: how far past the top speed (a share of max_speed) the rope may ask
## before it starts to drag the car. A wide band is an elastic rope that forgives a long pull; a narrow
## one is a steel cable that over-pulls the moment you ask for too much. 0.02 = the old dead band.
@export var rope_band: float = 0.02
## Drawing only: how thick the rope is and how much it bows while slack (0 = straight).
@export var rope_draw_width: float = 1.0
@export var rope_sag: float = 0.0
## A rival's rope is drawn in its car's colour (alpha 0 = the player's white rope) and a little thinner.
var rope_tint: Color = Color(0, 0, 0, 0)
## BOOST (SPEC 39). A meter 0..1 filled by riding the tension zone at full speed (`boost_charge_tension`
## per s) and by drifting (`boost_charge_drift` per s at full drift intensity); `fire_boost()` spends a
## full meter on `boost_time` s of extra top speed (`boost_speed`, a share of max_speed) and extra drive
## (`boost_accel` px/s^2). Off by default: a bare Car never charges and never boosts.
@export var boost_enabled: bool = false
## TYRES (SPEC 45). A tyre wears while the rope over-pulls (its wheel is being dragged; loaded wheels
## more) and from hard hits on its corner; at 1 it bursts and the car runs on the metal rim of that wheel:
## that wheel grips `rim_grip`, the car loses `rim_speed_loss` of its top speed per burst tyre and shakes
## (`rim_wobble`). All four can go. Repaired on respawn.
@export var tyres_enabled: bool = false
@export var tyre_wear_overpull: float = 0.55
@export var tyre_wear_hit: float = 0.0016      # wear per px/s of a hard hit, on the wheel nearest the hit
@export var rim_grip: float = 0.45
@export var rim_speed_loss: float = 0.08
@export var rim_wobble: float = 2.5
## BODY DAMAGE (SPEC 45). A hit of at least `part_min_hit` px/s may knock a piece off (its chance grows
## with the hit); a car has `parts_to_lose` of them; a wreck throws what is left.
@export var parts_enabled: bool = false
@export var part_min_hit: float = 170.0
## SPEC 123: PROGRESSIVE DESTRUCTION, component by component -- see `CarBody`. Off by default and on for
## one car in the registry to begin with: it is a prototype, and the zone model underneath it still runs
## for everybody else. With it on, a crash bends the panel it landed on, a hard one takes the wheel
## behind it, and the handling follows the picture -- a missing wheel is a hub on the road.
@export var body_parts_enabled: bool = false
## px/s of closing that a hub dragging on the road scrubs off, per second, per missing wheel.
@export var scrape_drag: float = 260.0
## rad/s^2 the car is hauled toward a corner that is down to its hub.
@export var scrape_pull: float = 1.5
## How much top speed a dragging corner costs, per unit of `CarBody.drag()`. A wheel off is 0.62 of
## that, so about a quarter of the car's pace.
@export var scrape_speed_loss: float = 0.42
@export var parts_to_lose: int = 6
## SPEC 46 -- damage you can feel. Lost pieces change the handling: each one off the FRONT costs the front
## tyres `front_part_grip` of their grip (the nose washes wide), off the REAR the rear ones
## `rear_part_grip` at speed (the tail gets loose), a side missing more than the other PULLS the car that
## way (`side_part_pull`), every piece gone makes it lighter to turn (`light_part_twitch`), and a side
## that has lost its panels lets the next hit through to the vital behind it (SPEC 102 retired
## `bare_side_damage`: a bare zone is not "15 % worse", it is open).
@export var front_part_grip: float = 0.07
@export var rear_part_grip: float = 0.06
@export var side_part_pull: float = 0.7
@export var light_part_twitch: float = 0.04
@export var bare_side_damage: float = 0.15
## Past `oil_leak_damage` % damage (a car close to wrecking) it drips oil every `oil_leak_every` s while it
## moves.
@export var oil_leak_damage: float = 80.0
## SPEC 95: whether a small health bar floats over the car. Off: the damage doll in the corner replaced it.
@export var show_damage_bar: bool = false
@export var oil_leak_every: float = 0.7
## THE ROPE CAN SNAP (SPEC 46). Over-pull strains it (`rope_strain_rate` per s at excess 1; it recovers at
## `rope_strain_recover` per s); at 1 it breaks: no pull, no brakes -- the car coasts -- until the cursor is
## brought back to the car (within slack + `reattach_extra` px), which ties it on again.
@export var rope_snap_enabled: bool = false
@export var rope_strain_rate: float = 0.35
@export var rope_strain_recover: float = 0.3
@export var reattach_extra: float = 14.0
## SLIPSTREAM (SPEC 49). Sitting in another car's wake cuts the air it has to push: `slipstream_speed` of
## extra top speed at a full tow. The last part of the wake is dirty air -- past `DIRTY_AIR_FROM` the front
## tyres lose up to `dirty_air_grip` of their grip, so the tow has to be left before the corner. Race
## measures the wake and feeds it in (`set_slipstream`); a bare Car never tows.
@export var slipstream_enabled: bool = false
@export var slipstream_speed: float = 0.07
@export var dirty_air_grip: float = 0.10
## TYRE WEAR FROM THE GROUND (SPEC 49). Rubber goes where you drive it: scrubbing a tyre sideways (a slide,
## past `TYRE_SCRUB_FROM` of its lateral limit) wears it `tyre_wear_scrub` per second, and off the road the
## ground itself eats all four -- `tyre_wear_grass` / `tyre_wear_sand` per second at the off-road speed cap.
@export var tyre_wear_scrub: float = 0.02
@export var tyre_wear_grass: float = 0.02        # SPEC 96: gentler -- the ground scrubs, it does not eat
@export var tyre_wear_sand: float = 0.07         # (sand still costs more than grass)
## COLD TYRES (SPEC 49). Cold rubber has `tyre_cold_grip` of the grip; driving warms it over
## `tyre_warm_time` s (a slide warms it faster), a crawl lets it go cold again over `tyre_cool_time` s.
## Off by default, so a bare Car (and every test that does not ask for it) starts on warm tyres.
@export var tyre_temp_enabled: bool = false
@export var tyre_cold_grip: float = 0.93
@export var tyre_warm_time: float = 12.0
@export var tyre_cool_time: float = 45.0
## PARTS THAT BREAK (SPEC 58). The hull damage of SPEC 45 is what the car looks like; these are what it
## drives like. Each is a condition from 1 (new) to 0 (finished), and each is hurt by the thing that would
## actually hurt it: the engine by hits on the nose and by fire, the steering by corner hits, the
## suspension by rough ground and hard landings.
##   * engine     -- `engine_power_loss` of the top speed and the drive at zero condition
##   * steering   -- pulls `steering_pull` rad/s toward the damaged side at full speed
##   * suspension -- the body rolls and pitches more (`susp_soft_loss` of the spring)
@export var parts_break: bool = false
@export var engine_power_loss: float = 0.35
## SPEC 102: VITALS. Bodywork is armour and the engine and the fuel tank are the life -- War Thunder's
## rule: nothing you do to the barrel kills the tank. A hit on a zone that still has panels takes a
## panel and costs no life; a hit on a BARE zone reaches the vital behind it: the engine under the nose,
## the tank under the tail, either by which half of a bare side. A dead engine limps at
## `engine_dead_power` of its drive and the car is ridden on; an empty tank is the wreck. Walls,
## rollovers, fire and slams go through the panels (`_add_damage_at(.., true)`, `burn`, `punch`);
## another car does not.
@export var engine_dead_power: float = 0.3
## SPEC 102: how much of what reaches the engine it takes -- a fragile engine (the lightweight one in
## the garage) takes half again as much.
@export var engine_fragility: float = 1.0
## SPEC 137: the same for the fuel tank -- how much of what reaches it it takes. 1.0 everywhere except a
## car carrying an armed charge, which is quicker to go up because that is the price of the reach.
@export var tank_fragility: float = 1.0
@export var engine_hit_damage: float = 0.0012    # per px/s of a hit on the nose
@export var engine_fire_damage: float = 0.06     # per damage point taken from fire
@export var steering_pull: float = 0.55
## How far the front wheels sit off straight when the steering is completely bent (rad, ~3.5 deg). This
## is what the driver has to hold against: the car crabs even with the rope pointing dead ahead.
@export var steering_bend: float = 0.062
@export var steering_hit_damage: float = 0.0009  # per px/s of a hit on a front corner
@export var susp_soft_loss: float = 0.30
## SPEC 96: 0 -- "grass and sand should not damage the car". Rough ground still shakes it, still scrubs
## rubber, still slows it; it no longer eats the suspension or the body.
@export var susp_rough_damage: float = 0.0       # per second of rough ground at full shake

## TYRE WALLS (SPEC 49). Where the barrier is lined with tyres (`set_wall_probe`), a hit is absorbed:
## `tyre_wall_absorb` of the damage and the shock of the same hit on concrete, but the wall grabs the car
## (`tyre_wall_bite` of its speed) instead of letting it bounce away -- safe, and slow.
@export var tyre_wall_absorb: float = 0.45
@export var tyre_wall_bite: float = 0.35
@export var boost_charge_tension: float = 0.0
@export var boost_charge_drift: float = 0.0
@export var boost_time: float = 1.2
@export var boost_speed: float = 0.15
@export var boost_accel: float = 360.0
@export var damage_per_impact: float = 0.08     # damage per px/s the barrier removed
@export var damage_per_roll: float = 22.0       # damage for any rollover ...
@export var damage_roll_severity: float = 30.0  # ... plus this much at severity 1 (about 3 rolls wreck a car)
@export var damage_rough: float = 0.0           # damage per second of full-speed rough ground (SPEC 96: none)
@export var damage_overpull: float = 9.0        # damage per second at excess 1
@export var damage_speed_loss: float = 0.25     # fraction of top speed a 100 % damaged car has lost
## Car-to-car contact (Race.resolve_contacts): damage per px/s of closing speed, the side-impact tilt
## shock at 400 px/s, and the closing speed below which a touch is just a nudge.
@export var contact_damage: float = 0.07
## SPEC 122: the shortest gap between two doses of contact damage, in seconds. `apply_contact` is called
## once per PHYSICS SUB-STEP for every touching pair, so a car held against another at the contact
## threshold was taking `closing * contact_damage` 120 times a second -- around 590 points a second at
## 70 px/s of closing, which is a wreck in a fifth of a second for leaning on somebody. The separation
## impulse and the shove still run every sub-step (the cars must not sink into each other); only the
## damage, the tilt and the squash are held to this interval.
@export var contact_damage_every: float = 0.22
## SPEC 122: THE CLEAN EXIT. Holding a slide is already paid for -- `boost_charge_drift` fills the whole
## meter in about a second of full drift -- but nothing in the game noticed the hard part, which is
## CATCHING it: coming out of a long slide straight, still carrying speed, without touching anything.
## So the top-up is deliberately small (compare `boost_charge_drift` 1.0 per SECOND against 0.08 once);
## the point of it is the recognition, and the boost economy does not need another source.
##
## Once per manoeuvre, and a manoeuvre needs `clean_exit_slide` of real sliding before another exit can
## be claimed -- so a driver flicking the wheel cannot collect one every half second.
@export var clean_exit_enabled: bool = false
@export var clean_exit_charge: float = 0.08     # of the meter, once
@export var clean_exit_slide: float = 0.9       # s of drifting before an exit is worth anything
@export var clean_exit_hold: float = 0.45       # s of straight, quiet driving that ends it
@export var clean_exit_slip: float = 0.14       # rad: how straight "straight" is
@export var clean_exit_speed: float = 180.0     # px/s: an exit at walking pace is not a save
@export var contact_trip: float = 1.1
@export var contact_min_speed: float = 70.0

# ---------------------------------------------------------------- state / testability

var use_mouse: bool = true                  # false -> target_point is used instead of the cursor
var target_point: Vector2 = Vector2.ZERO    # input override for tests / AI
var auto_process: bool = true               # true -> _physics_process calls physics_step itself
var velocity: Vector2 = Vector2.ZERO        # px/s, global
var heading: float = 0.0                    # radians; kept in sync with `rotation`
var bounds: Rect2 = Rect2(0, 0, 1280, 720)  # car position is clamped inside (grown by -screen_margin)
## SPEC 106: the rope is DRAWN from the nose, while it still pulls from the centre. The race's AI and the
## test autopilot are tuned to a centre rope; moving the pull to the nose sent them 77 % slower and 45 %
## of a lap off the road. "In a race the rope starts in the middle" was about the picture, so it is the
## picture that moved.
@export var rope_drawn_at_nose: bool = false
## How far ahead of the centre the nose is, in the car's own units.
const NOSE_OFFSET := 18.0

## SPEC 53: solid things INSIDE the world -- the town's buildings. Rects in world coordinates, set by
## Race; a car is pushed out of one it drives into and loses the speed it carried into it, exactly as it
## does against the barrier. Empty on every track without a town, and on a bare Car.
var solids: Array[Rect2] = []
var rope_visible: bool = true               # false -> RopeLine draws nothing (e.g. after the finish)
## Livery, set by CarRegistry.apply(). Drawing only: nothing in the simulation reads these.
var car_id: String = "sport"
var body_color: Color = Color(0.15, 0.42, 0.92)
var stripe_color: Color = Color(1, 1, 1, 0.85)
var body_style: String = "sport"               # "sport" | "f1" | "gt" | "rally" | "kart"
## The runner's tag drawn under the car in multiplayer ("S1", "S2", "AI1"); "" draws nothing.
var tag: String = ""
## Draw the car as a real low-poly 3D model (CarModel3D) instead of the flat 2D body. Only takes effect
## where 3D can be rendered (never in a headless run), so the simulation and the tests are unaffected.
static var use_3d_models: bool = true
var _model: CarModel3D = null
var _model_distance: float = 0.0

var _surface_provider: Callable = Callable()   # func(pos) -> "grass" | "sand", queried while off track
var _surface: String = SURFACE_ASPHALT
var _overpull: float = 0.0
## SPEC 128: the rope's demand as a fraction of full road speed (0..1), kept from the last step so the
## dashboard and the tension read the same number the physics used.
var _haul: float = 0.0
## SPEC 128: the engine's heat, 0..1. Only ever above zero with a holed radiator; at 1 the engine has
## lost `overheat_loss` of its power and will not get it back until the driver eases off.
var _heat: float = 0.0
## SPEC 121: 0 on the ground, 1 fully airborne on the end of an over-pulled rope; how long this hop
## has lasted; and whether the pull has to ease before another one is allowed.
var _air: float = 0.0
var _air_time: float = 0.0
var _air_spent: bool = false
var _air_drawn: float = -1.0                   # last `_air` the draw scale was set from
var _boost_meter: float = 0.0
var _tyre_wear: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## SPEC 58: 1 = new, 0 = finished.
var _engine_health: float = 1.0
var _steering_health: float = 1.0
var _susp_health: float = 1.0
## SPEC 102: the second vital, and whether the first is gone for good.
var _tank_health: float = 1.0
var _engine_dead: bool = false
var _steering_side: float = 0.0                  # -1 pulls left, +1 pulls right
## SPEC 122: how far off straight a bent rack holds the front wheels, in radians. Recomputed every
## sub-step from `_steering_health`; added to `_steer` only where the wheels are pointed.
var _steer_bend: float = 0.0
var _burst: Array[bool] = [false, false, false, false]
var _parts_left: int = 6
## SPEC 123: the component model, when `body_parts_enabled`. Always allocated (it is a few floats), so
## nothing has to null-check it; it simply does nothing while the flag is off.
var _body := CarBody.new()
var _part_seq: int = 0
var _lost_zone: Dictionary = {"front": 0, "rear": 0, "left": 0, "right": 0}
var _leak_timer: float = 0.0
var _hazard_probe: Callable = Callable()     # func(world_pos) -> grip factor (oil), set by Race
var _wall_probe: Callable = Callable()       # func(world_pos) -> true where the barrier has tyre walls
var _slipstream: float = 0.0                 # 0..1 how deep in another car's wake we are (SPEC 49)
var _tyre_temp: float = 1.0                  # 0 = stone cold, 1 = up to temperature (SPEC 49)
var _rope_strain: float = 0.0
var _rope_snapped: bool = false
var _boost_left: float = 0.0
var _stretch: float = 0.0                    # SPEC 110: >0 stretched along the nose, <0 squashed
var _prev_tension: float = 0.0
var _in_band: bool = false
var _rough: float = 0.0                          # 0..1 how hard rough ground is shaking the car now
var damage: float = 0.0
var _wrecked: bool = false

var _locked: bool = false
var _off_track: bool = false
var _on_bridge: bool = false
var _on_deck: bool = false
var _on_track_provider: Callable = Callable()
var _surface_probe: Callable = Callable()
## Per-wheel samples of the hazard (oil) grip and of the optional per-wheel surface probe, taken ONCE per
## tick at the wheels' start-of-tick positions (`_sample_probes`) and used by every sub-step of it. Asking
## the callables per wheel per sub-step (the closure, then a walk over every surface and slick) cost more
## than the tyre maths, for a difference of at most one sub-step of travel (~5 px) at a slick's edge.
var _wheel_hazard := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
var _wheel_asphalt := PackedByteArray([1, 1, 1, 1])
## True on a tick's LAST sub-step: the one that writes the per-wheel state dictionaries (SPEC 7.7). They
## are read after the tick (marks, effects, HUD, tests), never between sub-steps, so the earlier
## sub-steps' writes were work nobody saw.
var _publish_wheels: bool = true
var _rope_target: Vector2 = Vector2.ZERO
var _has_rope_target: bool = false
var _rope_tension: float = 0.0
var _dust_phase: float = 0.0

var _tires := TireModel.new()
var _susp := Suspension.new()

var _yaw_rate: float = 0.0
var _steer: float = 0.0
## SPEC 17.4: the filtered longitudinal demand (px/s^2) and the filtered yaw demand (rad/s). The
## actuators — engine, brakes, the driver's hands — cannot step in one frame.
var _a_cmd: float = 0.0
var _omega_cmd: float = 0.0
var _a_body: Vector2 = Vector2.ZERO     # previous sub-step's body acceleration (x = long, y = lateral)
var _tilt: float = 0.0                  # (left load - right load), -1..1
var _pitch: float = 0.0                 # (front load - rear load), -1..1
var _tilt_raw: float = 0.0              # _tilt without the TWO_WHEELS lift; drives the rollover machine
var _tilt_shock: float = 0.0            # transient tilt from trips / impacts, decays
var _roll_vis: float = 0.0              # smoothed _tilt, for drawing
var _pitch_vis: float = 0.0             # smoothed _pitch, for drawing

var _roll_state: int = RollState.GROUNDED
var _roll_timer: float = 0.0
var _roll_duration: float = 1.0
var _roll_phase: float = 0.0
var _roll_dir: float = 1.0
var _roll_turns: float = 1.0
var _roll_cooldown_left: float = 0.0
var _two_wheel_time: float = 0.0
var _two_wheel_calm: float = 0.0

var _drift_time: float = 0.0
## Total drift seconds since the last `reset_to()`. The live streak is reset after `drift_grace`, so
## nothing recorded what the player had just done; the HUD shows this alongside it.
var _drift_banked: float = 0.0
var _no_drift_time: float = 0.0
var _drifting: bool = false
var _drift_intensity: float = 0.0
var _body_slip: float = 0.0
var _rear_sat: float = 0.0

var _shake_mag: float = 0.0
var _shake_phase: float = 0.0
var _impact_timer: float = 0.0
## SPEC 122: time left before this car may take contact damage again.
var _contact_timer: float = 0.0
## SPEC 122: the clean exit -- how long this slide has run, how long the car has been settled since, and
## whether a slide long enough to be worth catching has happened yet. `_touched_timer` is any contact at
## all (not just a damaging one): you cannot be credited with catching a slide you were shoved out of.
var _slide_time: float = 0.0
var _settle_time: float = 0.0
var _exit_armed: bool = false
var _touched_timer: float = 0.0
## SPEC 128: seconds since ANOTHER CAR last touched this one. `_touched_timer` answers the same question
## over `clean_exit_hold` (0.45 s), which is the right window for "did that slide end cleanly" and far
## too short for the two things that ask it now: whether an overtake was earned or shoved, and whether a
## car that is going nowhere is wedged or simply being leant on. Walls and scenery do not set it -- being
## jammed against a barrier IS the case the recovery exists for.
var _contact_ago: float = 99.0
var _pending_impact: float = 0.0
var _impact_into: Vector2 = Vector2.RIGHT      # SPEC 102: which way the car was going when the wall stopped it
## Largest body-lateral velocity seen during the current physics frame (signed by the largest magnitude).
## The surface-change trip is judged on this, not on the post-crawl-drag velocity.
var _frame_lat: float = 0.0
## Largest SPEED seen during the current physics frame, for the same reason. The off-track crawl
## (`off_track_slowdown_rate`) destroys the speed that caused a trip before the trip is read, so a
## 580 px/s sideways exit onto the grass reached `_roll_entry` at 137 px/s — under `roll_min_speed` — and
## the car lay down on two wheels instead of rolling. See `_roll_speed_hint`.
var _frame_speed: float = 0.0
## Speed to judge the ROLLOVER ENTRY thresholds on for the next `_roll_entry` call, or < 0 for "use the
## current speed". Set at the moment a trip shock is added (the barrier clamp, or a surface change), so the
## entry is judged on the speed the car carried INTO the trip rather than on what the clamp / the crawl drag
## left one step later. Consumed (reset) by `_roll_entry`; it never affects the EXIT tests.
var _roll_speed_hint: float = -1.0

var _wheels: Array = []                 # 4 reused Dictionaries (SPEC 7.7): never reallocated
var _f_total: Vector2 = Vector2.ZERO
var _tau: float = 0.0


func _init() -> void:
	_build_wheels()
	_apply_tuning()
	_susp.reset()
	_refresh_wheel_geometry()


func _ready() -> void:
	z_index = Z_UNDER_BRIDGE
	var rope := RopeLine.new()
	rope.name = "RopeLine"
	rope.car = self
	add_child(rope)
	rotation = heading + body_crab()
	_ensure_model()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if auto_process and not _locked:
		physics_step(delta, get_input_target())


# ---------------------------------------------------------------- simulation

## One simulation step toward `target` (global). Splits `delta` into 120 Hz sub-steps; the on-track hook
## and the signals are evaluated exactly once, with the final position (SPEC 7.10).
func physics_step(delta: float, target: Vector2) -> void:
	if _locked:
		velocity = Vector2.ZERO
		if delta > 0.0 and is_finite(delta):
			_susp.settle(minf(delta, MAX_SUBSTEP * MAX_SUBSTEPS))
			_sync_suspension()
			_refresh_wheel_geometry()
		return
	if not (delta > 0.0) or not is_finite(delta):
		return

	_apply_tuning()
	var steps := clampi(int(ceil(delta / MAX_SUBSTEP)), 1, MAX_SUBSTEPS)
	var dt := delta / float(steps)
	_pending_impact = 0.0
	_frame_lat = 0.0
	_frame_speed = velocity.length()
	_sample_probes()
	for s in steps:
		_publish_wheels = s == steps - 1
		_sub_step(dt, target)

	_tick_stretch(delta)
	# One barrier impact report per physics frame at most (rate limited on top of that).
	_impact_timer = maxf(0.0, _impact_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_touched_timer = maxf(0.0, _touched_timer - delta)
	_contact_ago = minf(_contact_ago + delta, 99.0)
	if clean_exit_enabled:
		_tick_clean_exit(delta)
	if _pending_impact >= impact_min_speed and _impact_timer <= 0.0:
		_impact_timer = impact_cooldown
		hard_impact.emit(_pending_impact)
		_set_stretch(SQUASH_HIT)                  # SPEC 110: a wall squashes the car
		# SPEC 102: a wall is not a bumper. The hit goes THROUGH the panels to the vital on that side.
		_add_damage_at(position + _impact_into * 16.0, _pending_impact * damage_per_impact, true)

	# On-track hook with the NEW position — exactly once per call (Track.update_car_progress is stateful).
	var was_off := _off_track
	var off := false
	if _on_track_provider.is_valid():
		off = not bool(_on_track_provider.call(position))
	if off != was_off:
		_off_track = off
		# Crossing an edge jolts the suspension, and a car scrubbing sideways fast when the surface
		# changes digs in — that is the classic trip that rolls a real car over.
		_bump(surface_bump)
		# Measured across the whole frame, so the crawl drag that bites the instant the car is flagged
		# off track cannot hide the scrub that caused the trip.
		var lat := _frame_lat
		if absf(lat) >= trip_slip_speed and _roll_state <= RollState.TWO_WHEELS:
			var mag := clampf((absf(lat) - trip_slip_speed) / maxf(trip_span, 1.0), 0.0, 1.0) * trip_gain
			_add_tilt_shock(-signf(lat) * mag)
			# ... and evaluate the rollover machine NOW, on the speed the car carried into the trip. The
			# shock used to be added after the sub-step loop, so `_roll_entry` first saw it on the FOLLOWING
			# frame — by which time step 10's crawl drag had already taken the car from 580 to 137 px/s and
			# the entry failed `roll_min_speed`. Measured: 0 rollovers in 5 minutes of reckless play per
			# track before this; the trip is now read in the frame that caused it.
			_roll_speed_hint = maxf(_frame_speed, velocity.length())
			_roll_entry(0.0)
		off_track_changed.emit(off)
	# Which kind of off-road: only asked while off track, and only when a provider is set (the tracks
	# with sand traps). Grass <-> sand is a surface change too, with the same jolt.
	var surf := SURFACE_ASPHALT
	if _off_track:
		surf = SURFACE_GRASS
		if _surface_provider.is_valid():
			surf = String(_surface_provider.call(position))
	if surf != _surface:
		if _surface != SURFACE_ASPHALT and surf != SURFACE_ASPHALT:
			_bump(surface_bump)
		_surface = surf

	# Remember target for the rope visual.
	_rope_target = target
	_has_rope_target = true

	if _off_track and velocity.length() > 2.0:
		_dust_phase = fmod(_dust_phase + delta * 6.0, TAU)
	rotation = heading + body_crab()
	# The contact-patch positions were written in step 7 of the LAST sub-step, i.e. before step 8 turned the
	# heading and step 11 moved the car, so `get_wheel_states()[i]["position"]` lagged the car's real pose by
	# up to 4.9 px at 580 px/s — most of a wheel length, and exactly where the marks, the smoke and the
	# sparks are placed. Re-derive the pose (and only the pose) from the final position / heading.
	_refresh_wheel_pose()
	_model_distance += velocity.length() * delta
	_request_redraw()


func _sub_step(dt: float, target: Vector2) -> void:
	var v_before := velocity

	# 1. Rollover machine: ROLLING / RECOVERING are scripted and ignore the rope.
	if _roll_state == RollState.ROLLING or _roll_state == RollState.RECOVERING:
		_rope_tension = 0.0
		_overpull = 0.0
		_scripted_roll(dt)
		_susp.settle(dt)
		_sync_suspension()
		_solve_wheels(dt, 0.0, false)          # kinematics only: the marks/effects still want them
		_integrate(dt)
		_a_body = Vector2.ZERO
		_tilt_shock = 0.0
		# The actuators relax while the car is airborne: a demand latched at the moment of the trip must
		# not be handed back to the tires the instant the wheels touch down again (SPEC 17.4).
		var relax := 1.0 - exp(-8.0 * dt)
		_a_cmd -= _a_cmd * relax
		_omega_cmd -= _omega_cmd * relax
		_update_drift(dt)
		_tick_visuals(dt)
		return

	var pos := position
	var anchor := rope_anchor()
	# A snapped rope pulls nothing (SPEC 46); bringing the cursor back to the car ties it on again.
	if _rope_snapped:
		if anchor.distance_to(target) <= slack_radius + reattach_extra:
			_rope_snapped = false
			_rope_strain = 0.0
			rope_reattached.emit()
		else:
			target = pos
	var to_target := target - anchor
	var dist := to_target.length()

	# 2. Rope pull -> target speed (unchanged input layer).
	var pulling := dist > slack_radius
	var rope_speed := 0.0
	var top := _effective_max_speed()
	var boosted_max := max_speed * _boost_mult()
	if pulling:
		rope_speed = minf((dist - slack_radius) * speed_per_px, top)
	# SPEC 128: what the rope is ASKING for as a fraction of full road speed, before any cap -- on the
	# road that is just the throttle, and off it, it is what the crawl cap used to throw away.
	_haul = clampf((dist - slack_radius) * speed_per_px / maxf(max_speed, 1.0), 0.0, 1.0) if pulling else 0.0
	# SPEC 128: a torn rope mount does not hold. The rope still points where it points; what it CANNOT do
	# any more is put the car's whole weight behind it, so the same pull asks for less.
	if body_parts_enabled:
		var mount := _body.rope_mount_damage()
		if mount > 0.0:
			rope_speed *= 1.0 - mount_slack * mount
	# Over-pull: how much MORE than the wheels can deliver the rope is asking for, counted only once the
	# wheels are actually at their limit (a long rope on a slow car is just acceleration).
	# Judged against the UNDAMAGED top speed: otherwise damage (which lowers `top`) would make the car
	# count as over-pulled sooner, which damages it more -- a spiral straight into a wreck.
	_overpull = 0.0
	_in_band = false
	if overpull_enabled and pulling and max_speed > 1.0:
		# The tension zone (`rope_band`, per car): the cursor just past the rope's full-throttle length --
		# asking up to `rope_band` more than the top speed. It is held, not dragged, and holding the rope
		# there (flat out, at any speed) charges the boost. Past it, at the speed limit, the rope drags.
		var ask := ((dist - slack_radius) * speed_per_px - boosted_max) / max_speed
		var excess := clampf(ask - rope_band, 0.0, 1.5)
		var at_limit := clampf((velocity.length() - 0.85 * top) / (0.15 * top), 0.0, 1.0)
		_overpull = excess * at_limit
		_in_band = ask > 0.0 and excess <= 0.0 and not _off_track
	if rope_snap_enabled and not _rope_snapped:
		if _overpull > 0.0:
			# SPEC 128: a bent mount is where a rope lets go, so it frays faster than the rope does.
			var fray := 1.0 + mount_strain * (_body.rope_mount_damage() if body_parts_enabled else 0.0)
			add_rope_strain(rope_strain_rate * minf(_overpull, 1.5) * fray * dt)
		else:
			_rope_strain = maxf(_rope_strain - rope_strain_recover * dt, 0.0)
	if tyre_temp_enabled:
		# Warmed by working the tyres: speed, and a slide most of all. A parked car goes cold again.
		var work := clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0) * (1.0 + _rear_sat)
		_tyre_temp = clampf(_tyre_temp + (work / maxf(tyre_warm_time, 0.1)
				- (1.0 - minf(work, 1.0)) / maxf(tyre_cool_time, 0.1)) * dt, 0.0, 1.0)
	if boost_enabled:
		_tick_boost(dt)
	# Tension honours the current speed limit, so a rope pulled hard while the car crawls on the grass is
	# drawn slack rather than promising full power.
	_rope_tension = _tension_for(rope_speed)

	var speed := velocity.length()

	# 3. Steering: the same law as before, but it now produces a *demanded* yaw rate plus a real front
	#    wheel angle. The tires have to deliver the demand; past the limit they cannot, and the car drifts.
	var turn_factor := lerpf(min_turn_factor, 1.0, clampf(speed / maxf(full_turn_speed, 0.001), 0.0, 1.0))
	var omega_max := turn_rate * turn_factor
	var diff := 0.0
	if pulling:
		diff = wrapf(to_target.angle() - heading, -PI, PI)
	elif speed > heading_min_speed:
		var vdiff := wrapf(velocity.angle() - heading, -PI, PI)
		if absf(vdiff) < PI * 0.5:
			diff = vdiff
	var omega_demand := clampf(diff * steer_response, -omega_max, omega_max)
	# "Braking must brake, not spin" (SPEC 1.2). The target-speed floor is already faded out with speed for
	# a backwards rope; the *yaw* demand needs the same treatment now that the car has real tires. A driver
	# at 580 px/s whose cursor lands behind them does not crank the wheel to full lock — they brake in a
	# straight line and turn round once they are slow. Without this the car yaws away from its velocity,
	# the brake force stops pointing along the travel, and the soft tire cannot scrub the leftover sideways
	# momentum fast enough (measured 41 frames to drop under 100 px/s against the 36-frame pin).
	# While the car is genuinely sideways the nose is not where the car is going, so "the rope points
	# backwards" has to be judged against the direction of TRAVEL as well; otherwise a drift with the cursor
	# out in front of the car reads as a backwards rope and the fade brakes the slide away (measured:
	# 368 -> 5 px/s in 0.67 s, i.e. the drift always cost the car all of its speed). The smaller of the two
	# angles wins, so nothing changes while the car tracks straight — the two are then the same angle.
	# `carry` is 1 while the exemption is free and fades to 0 as the drift is held (see `drift_carry_free`).
	var carrying := pulling and speed >= drift_min_speed and absf(_body_slip) >= drift_carry_slip
	var carry := _carry_strength() if carrying else 0.0
	var rope_off := absf(diff)
	if carrying:
		rope_off = lerpf(rope_off, minf(rope_off, absf(wrapf(to_target.angle() - velocity.angle(), -PI, PI))),
				carry)
	var backwards := clampf((rope_off - PI * 0.5) / (PI * 0.5), 0.0, 1.0)
	omega_demand *= 1.0 - backwards * clampf(speed / maxf(max_speed * 0.5, 0.001), 0.0, 1.0)
	# SPEC 17.4 — the steering column and the driver's hands. `omega_demand` itself is still computed
	# exactly as before (the `backwards` fade included, so "braking must brake, not spin" is untouched);
	# the lag is applied to the RESULT, and every later use reads `_omega_cmd`. Without it a cursor flicked
	# across the car reverses the demand from +3 to -3 rad/s in a single sub-step (SPEC 17.1 A4).
	# SPEC decision 29.29: a SLEW limit, not the first-order lag 17.4 sketched. A low-pass filter sits
	# inside the steering feedback loop (`diff` -> demand -> yaw -> `diff`) and costs it phase margin: at
	# 0.09 s the gentle 15 s constant-radius pin oscillated into a genuine drift (15 drift frames, slip
	# 0.38 rad). A slew limit is invisible to any input the hands could follow — a corner's demand moves far
	# slower than the limit — and only bites on the flick this is here for, which is exactly the "hands and
	# steering column" story. `steer_lag_time` is the time the demand needs to sweep its whole range
	# (+turn_rate -> -turn_rate), so a cursor thrown across the car reverses in `steer_lag_time`, not in one
	# sub-step.
	if steer_lag_time > 0.0:
		var slew := 2.0 * maxf(turn_rate, 0.001) / steer_lag_time
		_omega_cmd += clampf(omega_demand - _omega_cmd, -slew * dt, slew * dt)
	else:
		_omega_cmd = omega_demand
	if not is_finite(_omega_cmd):
		_omega_cmd = 0.0
	# The front wheels serve the *yaw demand*, not the heading error: the Ackermann angle for `omega` at
	# speed v is `omega * WHEELBASE / v`, and `steer_lead` is the bit extra the driver always winds on
	# because a tire needs slip angle to make force. Steering straight off `diff` (SPEC 7.3) cannot hold a
	# tight radius — `diff` is ~9 deg while tracking the ellipse ends, which asks for a third of the yaw
	# the corner needs, so the car washed off the road at the 192 px difficulty line (measured 39 % of
	# frames off track with the tires nowhere near their peak).
	var steer_target := 0.0
	if pulling:
		steer_target = clampf(_omega_cmd * WHEELBASE * steer_lead / maxf(speed, 40.0),
				-max_steer, max_steer)
	_steer += clampf(steer_target - _steer, -steer_rate * dt, steer_rate * dt)
	# SPEC 58: bent steering points the front wheels off straight, so the car pulls toward the damaged
	# side until the driver aims off to hold it.
	#
	# SPEC 122: AS AN OFFSET, NOT AS AN INCREMENT. This used to read `_steer += bend`, and `_steer` is a
	# member that survives the sub-step -- so the bend was added again every sub-step, on top of the bend
	# added by the last one. The slew above can only pull `_steer` back by `steer_rate * dt`, so at 120 Hz
	# any bend bigger than `steer_rate / 120` grew without bound (and nothing clamps `_steer` after the
	# bend, only `steer_target` before it): a lightly bent car ended up with its front wheels at an angle
	# no steering rack has. The bend is a constant offset on the wheels now and `_steer` stays the
	# driver's own command, inside `max_steer`, whatever is broken.
	_steer_bend = 0.0
	if parts_break and _steering_health < 1.0:
		_steer_bend = _steering_side * steering_bend * (1.0 - _steering_health)
	# SPEC 128: a BUCKLED WHEEL sits off straight too, and the front ones are the ones that aim the car.
	if body_parts_enabled:
		_steer_bend += _body.toe() * toe_bend

	# 4. Target speed, with the misaligned-rope floor faded out by speed (unchanged).
	var target_speed := 0.0
	if pulling:
		var align := maxf(cos(diff - _omega_cmd * dt), 0.0)
		# Same reasoning as `rope_off` above: a drift can only be carried if the car keeps its power while
		# the rope points where it is TRAVELLING, not where the nose happens to face. Bounded by `carry`, so
		# the exemption is worth 100 % of the demanded speed for the first second of a slide and
		# `drift_carry_floor` of it once the slide has been held.
		if carrying:
			var travel_align := maxf(cos(wrapf(to_target.angle() - velocity.angle(), -PI, PI)), 0.0)
			align = maxf(align, travel_align * lerpf(drift_carry_floor, 1.0, carry))
		var slow_factor := clampf(1.0 - speed / maxf(full_turn_speed, 0.001), 0.0, 1.0)
		target_speed = rope_speed * lerpf(misaligned_speed_factor * slow_factor, 1.0, align)
	if _rope_snapped:
		target_speed = velocity.dot(Vector2.from_angle(heading)) * exp(-0.6 * dt)

	# 5./6. Weight transfer from the PREVIOUS sub-step's body acceleration, then the suspension solve.
	var p := clampf(-_a_body.x / maxf(pitch_reference_accel, 1.0), -1.0, 1.0)
	var r := clampf(_a_body.y / maxf(roll_reference_accel, 1.0), -1.0, 1.0)
	var lift_left := 1.0
	var lift_right := 1.0
	if _roll_state == RollState.TWO_WHEELS:
		# The inside wheels are off the ground: all the load goes to the outside pair, which costs total
		# grip through the tire's load sensitivity. The direction comes from the LIFT-FREE tilt, so the
		# state cannot argue itself into staying where it is.
		if _tilt_raw >= 0.0:
			lift_right = 0.08
		else:
			lift_left = 0.08
	_susp.step(dt, p, r, lift_left, lift_right)
	_sync_suspension()

	# 7. Per-wheel tire forces.
	var fwd_dir := Vector2.from_angle(heading)
	var right_dir := _right_of(fwd_dir)
	var fwd_speed := velocity.dot(fwd_dir)
	# SPEC 17.4 — the longitudinal axis. `mass` divides the BRAKE only: the engine is assumed to scale with
	# the car (a slower pull-away reads as input lag, not as weight), while the brakes do not, so a heavier
	# car takes proportionally longer to stop. On top of that the demand is no longer a one-frame step —
	# the engine takes a moment to come on and the brakes take a little less.
	# SPEC 121: how much braking the rope is entitled to ask for. See `coast_brake` / `rope_brake`.
	var brake_share := 1.0
	if not _rope_snapped:
		if pulling:
			# Just past the cursor: the rope is hauling the car back with almost no rope to do it with,
			# and a rope is not a brake disc. `near` runs 1 at the rim to 0 once there is a real length
			# of rope behind the car, which is where a yank IS worth the car's full braking.
			var behind := clampf(-cos(diff), 0.0, 1.0)
			var reach := maxf(slack_radius * rope_brake_reach, 0.001)
			var near := 1.0 - clampf((dist - slack_radius) / reach, 0.0, 1.0)
			brake_share = lerpf(1.0, rope_brake, behind * near)
			# SPEC 130: a rope trailing straight out in front is not a brake -- it is a rope that has
			# gone slack-ish. It fades out with the ANGLE (a rope swung aside is leading the car into a
			# corner, and that keeps every bit of its braking) and with `behind` (a rope round the back
			# is hauling, which is the case above).
			var straight := 1.0 - clampf(absf(diff) / EASE_ANGLE, 0.0, 1.0)
			brake_share = minf(brake_share, lerpf(1.0, lerpf(rope_ease, 1.0, behind), straight))
		elif slack_radius > 0.001:
			var fade := maxf((1.0 - coast_zone) * slack_radius, 0.001)
			brake_share = lerpf(1.0, coast_brake,
					clampf((dist - coast_zone * slack_radius) / fade, 0.0, 1.0))
	var a_brake_max := brake_deceleration * MASS_REF / maxf(mass, 0.05) * brake_share
	# Over-pulled, the wheels are already skidding at their limit: the drive cannot slow the car the rope
	# is dragging, so it does not try to brake it back down to max_speed.
	if _overpull > 0.0:
		target_speed = maxf(target_speed, fwd_speed)
	# SPEC 130: the slack in the rubber band (`rope_hold_band`). Not applied to `target_speed` itself --
	# the dashboard should still read what the rope is ASKING for -- only to what the wheels are told to
	# do about it.
	var demand := target_speed
	# ... and only while the rope is in FRONT. A rope round the BACK of the car is hauling it in, which
	# is a real force with a real direction; holding the car's speed against it made the deliberate
	# "drop the cursor and let it drag you down" take half a second longer.
	if pulling and not _rope_snapped and cos(diff) > 0.0:
		var slack := rope_hold_band * max_speed
		if demand < fwd_speed:
			slack *= 1.0                           # easing off: the whole band, which is the point
		elif demand < max_speed * HOLD_TOP:
			slack *= HOLD_FASTER                   # ... and a narrow one climbing, in the middle of the
		else:
			slack = 0.0                            # range only: the last of the climb is never held,
			                                       # or the car cannot reach its own top speed
		if absf(demand - fwd_speed) <= slack:
			demand = fwd_speed
	var a_want := clampf((demand - fwd_speed) / dt, -a_brake_max, acceleration)
	if _boost_left > 0.0 and pulling and a_want >= 0.0:
		# The boost adds drive while the rope asks for speed -- up to the boosted top speed. Shorten the
		# rope and the car brakes as usual: a boost never carries anyone into a corner against their will.
		a_want += boost_accel * _boost_strength()
	var lag_rate := engine_response if a_want > _a_cmd else brake_response
	if is_finite(lag_rate) and lag_rate > 0.0:
		_a_cmd += (a_want - _a_cmd) * (1.0 - exp(-lag_rate * dt))
	else:
		_a_cmd = a_want
	if not is_finite(_a_cmd):
		_a_cmd = 0.0
	var a_demand := _a_cmd
	_solve_wheels(dt, a_demand, true)

	# 8. Yaw: tire torque plus a steering assist that fades out exactly when the rears let go.
	var release := 0.0
	# `lat_saturation` is `|alpha| / alpha_peak` with `|alpha| < PI/2`, so it has a hard structural ceiling.
	# Clamping the release window to 82 % of it keeps "assist fully released" reachable whatever the tire is
	# retuned to (with `drift_release_full` 1.60 it was 89 deg of rear slip, i.e. never).
	var release_ceiling := (PI * 0.5) / maxf(_tires.peak_slip_angle(), 0.02)
	var span := maxf(minf(drift_release_full, release_ceiling * 0.82) - drift_release_start, 0.001)
	release = clampf((_rear_sat - drift_release_start) / span, 0.0, 1.0)
	# SPEC 17.4 — every term in the yaw equation is divided by the same inertia, so `yaw_inertia` is a
	# single honest knob: doubling it halves every angular acceleration the car can make, in a slide and out
	# of it. `assist_max` is still the ceiling on the PRE-inertia assist, so the clamp keeps its meaning.
	var inertia_scale := YAW_INERTIA_REF / maxf(yaw_inertia, 1.0) * (1.0 + light_part_twitch * float(lost_parts()))
	var assist := clampf(assist_gain * (_omega_cmd - _yaw_rate) * (1.0 - release), -assist_max, assist_max) \
			* inertia_scale
	# Counter-steer. Once the assist has let go there is nothing left to stop the nose rotating, so a
	# provoked slide used to run straight past any usable angle to ~85 deg of body slip and then scrub the
	# car to a standstill — a handbrake 180, not a drift, and never worth doing on a lap. Past
	# `drift_hold_slip` the car therefore generates a restoring yaw acceleration that turns the nose back
	# toward the direction of travel (which IS what counter-steering does), so a slide settles at a holdable
	# angle. It fades in with speed so a crawling car is unaffected, and below `drift_hold_slip` it is
	# exactly zero, so nothing about normal cornering changes.
	# SPEC 128: DOG-TRACKING. A bent chassis is not a bent wheel: the axles are square to each other and
	# not to one another, so the car goes down the road at an angle and TURNS BETTER ONE WAY THAN THE
	# OTHER. That asymmetry is the whole feel of it -- one corner on the lap is suddenly hard work and
	# its mirror is fine -- and it is what stops this being another way of saying "the car wanders".
	if body_parts_enabled:
		var crab := _body.crab()
		if crab != 0.0 and _omega_cmd != 0.0:
			var away: bool = signf(_omega_cmd) == signf(crab)
			_omega_cmd *= (1.0 + crab_turn_out * absf(crab)) if away \
					else maxf(1.0 - crab_turn_in * absf(crab), 0.25)
	var hold_slip := _hold_slip_for(diff, dist, pulling)
	var slip_over := maxf(absf(_body_slip) - hold_slip, 0.0)
	var counter := 0.0
	if slip_over > 0.0:
		counter = signf(_body_slip) * clampf(slip_over * drift_damp_gain, 0.0, drift_damp_max) \
				* clampf(speed / maxf(drift_min_speed, 1.0), 0.0, 1.0) * inertia_scale
	# SPEC 121: the assist and the counter-steer are the FRONT TYRES being turned. A car in the air has
	# none on the ground, so neither does anything -- which is what makes flying a commitment: you go
	# where you were going, and the cursor is only holding you up.
	var grounded := 1.0 - _air
	_yaw_rate = clampf(_yaw_rate + (_tau / maxf(yaw_inertia, 1.0) + (assist + counter) * grounded) * dt,
			-yaw_rate_max, yaw_rate_max)
	if speed < heading_min_speed:
		_yaw_rate = lerpf(_yaw_rate, 0.0, minf(1.0, low_speed_yaw_damp * dt))
	heading = wrapf(heading + _yaw_rate * dt, -PI, PI)

	# 9. Body acceleration.
	velocity += _f_total * dt
	# While the rope over-pulls, the drag (9b) may carry the car past what its wheels can turn at.
	velocity = velocity.limit_length(max_speed * _boost_mult() * (1.0 + overpull_speed_margin * minf(_overpull, 1.0)))

	# 9a. SPEC 121: coming down -- because the pull eased, or because the hop ran out of `air_hold`. The
	#     wheels find the ground over `air_fall`, and the touchdown costs a jolt, a shake and rubber:
	#     four tyres dropped onto the road at speed is the scrub the flight itself did not do.
	if _overpull < overpull_air:
		_air_spent = false
		if _air <= 0.0:
			_air_time = 0.0
	if _air > 0.0 and (_overpull < overpull_air or _air_spent):
		_set_air(maxf(_air - air_fall * dt, 0.0))
		if _air <= 0.0:
			_air_time = 0.0
			_bump(air_land_bump)
			_shake_mag = minf(_shake_mag + shake_impulse * 0.8, 18.0)
			if tyres_enabled:
				var hit := tyre_wear_land * clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.5)
				for i in WHEEL_COUNT:
					_wear_tyre(i, hit)

	# 9b. Over-pull: the rope drags the car toward the cursor past what its wheels can turn at. The tires
	#     are skidding (their grip is cut in _solve_wheels), the pull's sideways part tips the body, and
	#     the chassis wobbles. Deterministic: the wobble is a function of position, not of time or chance.
	if _overpull > 0.0:
		var pull_dir := to_target.normalized()
		velocity += pull_dir * overpull_drag * _overpull * dt
		velocity = velocity.limit_length(max_speed * _boost_mult() * (1.0 + overpull_speed_margin))
		var lat_pull := pull_dir.dot(_right_of(Vector2.from_angle(heading)))
		# Same sign as the cornering load transfer (a pull to the right loads the LEFT wheels), so a
		# sideways drag adds to the lean the corner already has instead of cancelling it.
		_add_tilt_shock(lat_pull * overpull_tilt * _overpull * dt)
		# `_terrain_noise` is the ground: a car that is not on it does not feel it (SPEC 121).
		_yaw_rate += _terrain_noise(position * 1.7) * overpull_wobble * _overpull * (1.0 - _air) * dt
		_add_damage(damage_overpull * _overpull * dt)
		# SPEC 121: past `overpull_air` the wheels leave the ground, for `air_hold` at the most.
		if _overpull >= overpull_air and not _air_spent:
			_air_time += dt
			if _air_time >= air_hold:
				_air_spent = true              # down it comes, and no more until the pull eases
			else:
				_set_air(minf(_air + air_rise * dt, 1.0))
		# A tyre in the air is not being scrubbed along the road (SPEC 121), so `_air` takes the wear away.
		if tyres_enabled and _air < 1.0:
			for i in WHEEL_COUNT:
				var lr := clampf(_susp.load[i] / STATIC_LOAD, 0.0, 2.0)
				_wear_tyre(i, tyre_wear_overpull * _overpull * dt * (0.6 + 0.8 * lr) * (1.0 - _air))
	# SPEC 123: a corner down to its hub. It scrubs speed off the whole car and hauls it that way --
	# the two things anybody who has driven on a flat tyre would expect, and the reason a lost wheel is
	# a race-changing event rather than a decal.
	if body_parts_enabled:
		var spd := velocity.length()
		var pace := clampf(spd / maxf(max_speed, 1.0), 0.0, 1.0)
		# SPEC 128: a bent chassis scrubs as well as crabbing -- four wheels dragged slightly sideways
		# down every straight -- so it belongs in the same drag term as the hub.
		var body_drag := _body.drag() + crab_drag * absf(_body.crab())
		if body_drag > 0.0:
			if spd > 1.0:
				velocity -= velocity / spd * minf(scrape_drag * body_drag * dt, spd)
			_yaw_rate += _body.pull() * scrape_pull * pace * dt
		# SPEC 128: BENT WHEEL ALIGNMENT. Separate from the hub's drag: a buckled wheel is still round
		# enough to roll and no longer square enough to point, so the car wanders even when nothing is
		# scraping. It shows up at speed, the way a real misalignment does.
		var toe := _body.toe()
		if toe != 0.0 and spd > 40.0:
			_yaw_rate += toe * toe_pull * pace * dt
		# SPEC 128: A COLLAPSED CORNER sits on its stop -- so it is permanently compressed, which is what
		# the model and the weight transfer both read, and there is no spring left in it.
		for i in WHEEL_COUNT:
			var sag := _body.susp_sag(i)
			if sag > 0.0:
				_susp.compression[i] = maxf(_susp.compression[i], susp_rest + susp_sag_drop * sag)
		# SPEC 128: A RUBBING WING eats the tyre under it. It already costs that corner its grip
		# (`CarBody.wheel_grip`); this is the part that makes it get worse the longer you leave it.
		if tyres_enabled and spd > 30.0:
			for i in WHEEL_COUNT:
				var rub := _body.rub(i)
				if rub > 0.0:
					_wear_tyre(i, tyre_wear_rub * rub * pace * dt)
		# SPEC 128: LOOSE BODYWORK rattles. Not damage -- a noise and a shiver, so a car that is hanging
		# together feels like one before anything else tells you.
		var flap := _body.flap()
		if flap > 0.0:
			_shake_mag = maxf(_shake_mag, flap_rattle * flap * pace)
		# SPEC 128: A COOLING LEAK. Nothing happens when the radiator goes; what happens is that holding
		# it flat afterwards cooks the engine, and easing off lets it come back. The one damage whose
		# cost the driver chooses -- and the reason to drive around a hot engine rather than through it.
		var leak := _body.cooling_leak()
		if leak > 0.0 and pace > 0.55:
			_heat = clampf(_heat + overheat_rate * leak * (pace - 0.55) / 0.45 * dt, 0.0, 1.0)
		elif _heat > 0.0:
			_heat = clampf(_heat - overheat_cool * dt, 0.0, 1.0)
	# A side that has lost more than the other drags: the car pulls that way (SPEC 46).
	var side_diff := float(_lost_zone["right"]) - float(_lost_zone["left"])
	if side_diff != 0.0 and velocity.length() > 60.0:
		_yaw_rate += side_diff * side_part_pull * clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0) * dt
	# SPEC 58: bent steering pulls toward the corner that took the hit, harder the faster you go.
	if parts_break and _steering_health < 1.0 and velocity.length() > 60.0:
		_yaw_rate += _steering_side * steering_pull * (1.0 - _steering_health) \
				* clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0) * dt
	# Oil (SPEC 102: fuel). A car whose TANK is past oil_leak_damage drips while it moves.
	if get_tank_damage() >= oil_leak_damage and damage_enabled and velocity.length() > 30.0:
		_leak_timer -= dt
		if _leak_timer <= 0.0:
			_leak_timer = oil_leak_every
			oil_leak.emit(position - Vector2.from_angle(heading) * 8.0)
	# A car on its rims pulls and shakes, more the faster it goes.
	if tyres_enabled and velocity.length() > 60.0:
		var bursts := get_burst_count()
		if bursts > 0:
			var f := clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0)
			_yaw_rate += _terrain_noise(position * 2.3 + Vector2(37.0, 11.0)) * rim_wobble * float(bursts) * f * dt

	# 10. Off-track crawl (result of the previous hook evaluation). Sand has its own, harsher cap.
	if _off_track:
		# SPEC 128: the cap and the drag both answer to how hard the rope is pulled -- see `_offroad_cap`.
		var cap := _offroad_cap()
		var rate := sand_slowdown_rate if _surface == SURFACE_SAND else off_track_slowdown_rate
		var cur_speed := velocity.length()
		if cur_speed > cap:
			var slowed := maxf(cur_speed * exp(-rate * dt), cap)
			velocity *= slowed / cur_speed
		else:
			velocity *= exp(-_offroad_drag() * dt)
			velocity = velocity.limit_length(cap)
		# Rough ground: kicks the body (tilt) and the nose (yaw) in proportion to speed and to how stiff
		# the suspension is. Enough of it, fast enough, puts the car on two wheels or on its roof.
		# The ground eats rubber (SPEC 49): grass scrubs a tyre, sand is worse. A lap cutting the grass
		# is paid for two laps later, on a flat tyre.
		if tyres_enabled:
			var ground := tyre_wear_sand if _surface == SURFACE_SAND else tyre_wear_grass
			var ground_share := clampf(cur_speed / maxf(cap, 1.0), 0.0, 1.0)
			for i in WHEEL_COUNT:
				_wear_tyre(i, ground * ground_share * dt)
		var rough_k := sand_rough if _surface == SURFACE_SAND else offroad_rough
		var fast := clampf((cur_speed - rough_min_speed) / maxf(max_speed - rough_min_speed, 1.0), 0.0, 1.0)
		_rough = clampf(rough_k * fast, 0.0, 2.0)
		if parts_break and rough_k > 0.0 and fast > 0.0:
			_susp_health = clampf(_susp_health - susp_rough_damage * rough_k * fast * dt, 0.0, 1.0)
		if rough_k > 0.0 and fast > 0.0:
			var stiff := clampf(susp_stiffness / 260.0, 0.4, 2.0)
			_add_tilt_shock(_terrain_noise(position) * rough_k * stiff * fast * 11.0 * dt)
			_yaw_rate += _terrain_noise(position + Vector2(517.0, 233.0)) * rough_k * fast * 9.0 * dt
			_add_damage(damage_rough * rough_k * fast * dt)
	else:
		_rough = 0.0

	# 11. Integrate + clamp to bounds (the clamp runs in every state, including mid-rollover).
	var v_post_forces := velocity
	_integrate(dt)

	# 13. Body acceleration for the next sub-step's weight transfer, taken before the barrier clamp (an
	#     impact is reported through _tilt_shock instead, so a wall cannot saturate the roll for a frame).
	var a_world := (v_post_forces - v_before) / dt
	# Clamped to the envelope the TIRES can actually produce. `v_post_forces` is taken after step 10's
	# off-track crawl scaling, which is an artificial speed cap rather than a contact force: at 580 px/s it
	# removes ~55 px/s in one sub-step, i.e. ~6600 px/s^2 — 7x the car's own brake_deceleration. Fed
	# straight into the weight transfer it produced a bigger nose-dive on touching the grass (pitch 0.91)
	# than the hardest possible braking (0.57) and collapsed the rear load to ~0.2 exactly while the player
	# was trying to recover. The deliberate `_bump(surface_bump)` is still the visible grass jolt.
	var lat_envelope := maxf(tire_peak_accel * (1.0 + maxf(brake_grip_bonus, 0.0)), 1.0)
	_a_body = Vector2(
			# The longitudinal envelope is the brake the car ACTUALLY has, which `mass` divides (SPEC 17.4).
			# Clamping to the raw `brake_deceleration` would let an artificial speed cap (the off-track
			# crawl) dive the nose harder than the hardest possible braking can — which is exactly what
			# `test_suspension_bumps` pins.
			clampf(a_world.dot(fwd_dir), -a_brake_max, maxf(acceleration, 1.0)),
			clampf(a_world.dot(right_dir), -lat_envelope, lat_envelope))
	if not (is_finite(_a_body.x) and is_finite(_a_body.y)):
		_a_body = Vector2.ZERO
	var lat_now := v_before.dot(right_dir)
	if absf(lat_now) > absf(_frame_lat):
		_frame_lat = lat_now
	_frame_speed = maxf(_frame_speed, v_before.length())
	_tilt_shock *= exp(-tilt_shock_decay * dt)
	if absf(_tilt_shock) < 0.0005:
		_tilt_shock = 0.0
	_update_drift(dt)
	_tick_visuals(dt)
	_roll_entry(dt)


## The world's edge: a stop (a circuit's barrier). `sign` is the direction back into the world.
func _rail(v: float, sign: float) -> float:
	return maxf(v, 0.0) if sign > 0.0 else minf(v, 0.0)


## Integrates the position and clamps it inside `bounds`, recording any velocity the barrier removed.
func _integrate(dt: float) -> void:
	# Captured BEFORE any component is zeroed below. The trip sign has to come from the lateral velocity
	# that caused the impact (SPEC 8.2: "the car trips over its outside wheels"); reading it after the clamp
	# gave the surviving TANGENTIAL velocity instead, which rolled an oblique impact onto its unloaded
	# inside wheels, and for a purely sideways slam left ~0 and fell back to `signf(_tilt)`.
	var lat_pre := velocity.dot(_right_of(Vector2.from_angle(heading)))
	var speed_pre := velocity.length()
	var pos := position + velocity * dt
	var area := bounds.grow(-screen_margin)
	var min_p := area.position
	var max_p := area.end
	var removed := 0.0
	var tangential := 0.0
	var velocity_pre := velocity
	if pos.x < min_p.x:
		pos.x = min_p.x
		if velocity.x < 0.0:
			removed = absf(velocity.x)
			tangential = absf(velocity.y)
		velocity.x = _rail(velocity.x, 1.0)
	elif pos.x > max_p.x:
		pos.x = max_p.x
		if velocity.x > 0.0:
			removed = absf(velocity.x)
			tangential = absf(velocity.y)
		velocity.x = _rail(velocity.x, -1.0)
	if pos.y < min_p.y:
		pos.y = min_p.y
		if velocity.y < 0.0:
			removed = maxf(removed, absf(velocity.y))
			tangential = maxf(tangential, absf(velocity.x))
		velocity.y = _rail(velocity.y, 1.0)
	elif pos.y > max_p.y:
		pos.y = max_p.y
		if velocity.y > 0.0:
			removed = maxf(removed, absf(velocity.y))
			tangential = maxf(tangential, absf(velocity.x))
		velocity.y = _rail(velocity.y, -1.0)
	position = pos
	_after_bounds(removed, tangential, lat_pre, speed_pre, velocity_pre)


## What happens AFTER the car has been put back inside its floor: the buildings, the tyre wall, the
## damage, the shake and the trip. `removed` is the speed the barrier took and `tangential` what was left
## along it.
func _after_bounds(removed: float, tangential: float, lat_pre: float, speed_pre: float,
		velocity_pre: Vector2) -> void:
	# Buildings (SPEC 53). Resolved after the barrier clamp and before the damage below, so driving into a
	# wall of the town hurts exactly as much as driving into the wall round it.
	if not solids.is_empty():
		var solid_hit := _resolve_solids()
		if solid_hit.x > removed:
			removed = solid_hit.x
			tangential = solid_hit.y
	# A tyre wall (SPEC 49) takes the hit instead of the car: most of the blow is absorbed, but the tyres
	# grab the car rather than bouncing it back onto the road. Safe, and slow.
	if removed > 5.0 and _wall_probe.is_valid() and bool(_wall_probe.call(position)):
		wall_tyres_hit.emit(position, removed)
		velocity *= 1.0 - clampf(tyre_wall_bite, 0.0, 0.9)
		removed *= tyre_wall_absorb
		tangential *= tyre_wall_absorb
	if removed > 5.0:
		_impact_into = (velocity_pre if velocity_pre.length() > 1.0 else Vector2.from_angle(heading)).normalized()
	if removed > 5.0 and (tyres_enabled or parts_enabled):
		_body_hit(position + _impact_into * 16.0, removed)
	if removed > 5.0:
		_pending_impact = maxf(_pending_impact, removed)
		_bump(clampf(removed * 0.35, 0.0, 160.0))
		_shake_mag = minf(_shake_mag + removed * 0.012, 14.0)
		if removed >= barrier_trip_speed and tangential >= trip_min_tangential \
				and _roll_state <= RollState.TWO_WHEELS:
			var sign_lat := -signf(lat_pre)
			if sign_lat == 0.0:
				sign_lat = signf(_tilt) if _tilt != 0.0 else 1.0
			_add_tilt_shock(sign_lat * clampf(removed / maxf(barrier_trip_span, 1.0), 0.0, 1.0)
					* barrier_trip_gain)
			# Same reason as the surface trip: the clamp has just removed the speed that caused the trip, so
			# the entry must be judged on the speed the car arrived with.
			_roll_speed_hint = maxf(_roll_speed_hint, speed_pre)


## Pushes the car out of any solid it has driven into (SPEC 53) and reports what the wall took:
## (speed into the wall, speed left along it). Both contact circles are tested and the way out is always
## the shallowest axis, so a car scraping a building slides along it instead of catching on the corner.
func _resolve_solids() -> Vector2:
	var out := Vector2.ZERO
	var reach := CONTACT_OFFSET + CONTACT_RADIUS + 2.0
	for s in solids:
		var rect: Rect2 = s
		# Broad phase: the car cannot touch a building whose box is further away than its own reach.
		if absf(rect.get_center().x - position.x) > rect.size.x * 0.5 + reach \
				or absf(rect.get_center().y - position.y) > rect.size.y * 0.5 + reach:
			continue
		var grown := rect.grow(contact_radius())
		for c in get_contact_circles():
			if not grown.has_point(c):
				continue
			var left := c.x - grown.position.x
			var right := grown.end.x - c.x
			var up := c.y - grown.position.y
			var down := grown.end.y - c.y
			var shallow := minf(minf(left, right), minf(up, down))
			var push := Vector2(0.0, down)
			if is_equal_approx(shallow, left):
				push = Vector2(-left, 0.0)
			elif is_equal_approx(shallow, right):
				push = Vector2(right, 0.0)
			elif is_equal_approx(shallow, up):
				push = Vector2(0.0, -up)
			position += push
			var n := push.normalized()
			var into := -velocity.dot(n)
			if into > 0.0:
				out.x = maxf(out.x, into)
				out.y = maxf(out.y, absf(velocity.dot(Vector2(-n.y, n.x))))
				velocity += n * into          # kill the component driving into the wall
			break                             # one push per building per frame
	return out


## True when the straight line from `a` to `b` passes through a solid (SPEC 53) -- the rope's own question.
## A slab test: exact, and cheap enough to ask for every rope every frame.
func segment_hits_solid(a: Vector2, b: Vector2) -> bool:
	for s in solids:
		if _segment_hits_rect(a, b, s):
			return true
	return false


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var dv: float = d.x if axis == 0 else d.y
		var av: float = a.x if axis == 0 else a.y
		var lo: float = rect.position.x if axis == 0 else rect.position.y
		var hi: float = rect.end.x if axis == 0 else rect.end.y
		if absf(dv) < 0.00001:
			if av < lo or av > hi:
				return false
			continue
		var ta := (lo - av) / dv
		var tb := (hi - av) / dv
		if ta > tb:
			var swap := ta
			ta = tb
			tb = swap
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


## Solves the four tires. `apply` false = kinematics only (used while a rollover is scripted).
## Asks the hazard probe (oil, SPEC 46/81) and the optional per-wheel surface probe once per tick, per
## wheel, where the wheels are as the tick begins -- exactly where the first sub-step used to ask.
func _sample_probes() -> void:
	var has_hazard := _hazard_probe.is_valid()
	var has_surface := _surface_probe.is_valid()
	if not has_hazard and not has_surface:
		return
	for i in WHEEL_COUNT:
		var p := position + (WHEEL_LOCAL[i] as Vector2).rotated(heading)
		if has_hazard:
			_wheel_hazard[i] = float(_hazard_probe.call(p))
		if has_surface:
			_wheel_asphalt[i] = 1 if bool(_surface_probe.call(p)) else 0


func _solve_wheels(dt: float, a_demand: float, apply: bool) -> void:
	_f_total = Vector2.ZERO
	_tau = 0.0
	var fwd_dir := Vector2.from_angle(heading)
	var speed := velocity.length()
	var surface := get_surface()
	var mu_base := off_track_grip_factor if _off_track else 1.0
	if _off_track and _surface == SURFACE_SAND:
		mu_base = sand_grip_factor
	if _overpull > 0.0:
		mu_base *= 1.0 - overpull_grip_loss * minf(_overpull, 1.0)
	# SPEC 121: airborne. Not "less grip" -- NO grip: a wheel that is not touching anything cannot push,
	# so the rope's drag is the only force left and the car keeps the line it took off on.
	mu_base *= maxf(1.0 - _air, 0.0)
	mu_base *= lerpf(1.0, high_speed_peak_factor, clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0))
	# Cold rubber (SPEC 49): less grip everywhere until the tyres have been worked up to temperature.
	mu_base *= lerpf(tyre_cold_grip, 1.0, _tyre_temp)
	# Dirty air (SPEC 49): the deepest part of a wake takes the front tyres away, so the tow cannot simply
	# be held into the corner.
	var dirty := 0.0
	if _slipstream > DIRTY_AIR_FROM:
		dirty = dirty_air_grip * (_slipstream - DIRTY_AIR_FROM) / (1.0 - DIRTY_AIR_FROM)
	var braking := a_demand < 0.0
	if braking:
		mu_base *= 1.0 + brake_grip_bonus
	var steer_dir := Vector2.from_angle(heading + steer_angle())
	# Drive / brake shares. They are weighted by load (a loaded wheel takes more of the job) but normalized
	# per axle, so the four shares always sum to exactly 1.0 and `acceleration` / `brake_deceleration`
	# still mean exactly what they meant before the tire model existed (invariant 6.2.1). Weight transfer
	# then changes only the per-wheel *capacity* (P_long), which is the physically meaningful part.
	var front_load := maxf(_susp.load[0] + _susp.load[1], 0.001)
	var rear_load := maxf(_susp.load[2] + _susp.load[3], 0.001)
	var rear_sat := 0.0
	var has_surface_probe := _surface_probe.is_valid()
	var has_hazard := _hazard_probe.is_valid()
	var publish := _publish_wheels
	# Missing pieces (SPEC 46): a bare nose washes wide, a bare tail gets loose at speed. The same for both
	# wheels of an axle, so worked out once per solve.
	var front_mu := 1.0 - front_part_grip * minf(float(_lost_zone["front"]), 3.0)
	var rear_mu := 1.0 - rear_part_grip * minf(float(_lost_zone["rear"]), 3.0) \
			* clampf(speed / maxf(max_speed, 1.0), 0.0, 1.0)
	for i in WHEEL_COUNT:
		var w: Dictionary = _wheels[i]
		var lw: Vector2 = WHEEL_LOCAL[i]
		var r_w := lw.rotated(heading)
		# `_right_of` inlined (the car's right is (-y, x), see that function): two calls per wheel per
		# sub-step were a measurable share of the solve.
		var v_w := velocity + Vector2(-r_w.y, r_w.x) * _yaw_rate
		var is_front := i < 2
		var dir := steer_dir if is_front else fwd_dir
		var right := Vector2(-dir.y, dir.x)
		var v_fwd := v_w.dot(dir)
		var v_lat := v_w.dot(right)
		var load: float = _susp.load[i]
		var mu := mu_base
		if has_surface_probe:
			# Optional per-wheel surface (unused in this round, SPEC decision 10.6), sampled once per tick.
			var on_asphalt := _wheel_asphalt[i] != 0
			if publish:
				w["surface"] = SURFACE_ASPHALT if on_asphalt else SURFACE_GRASS
			if not on_asphalt and not _off_track:
				mu *= off_track_grip_factor
			elif on_asphalt and _off_track:
				mu /= maxf(off_track_grip_factor, 0.01)
		elif publish:
			w["surface"] = surface
		if dirty > 0.0 and is_front:
			mu *= 1.0 - dirty
		if _burst[i]:
			mu *= rim_grip                       # on the metal rim
		mu *= front_mu if is_front else rear_mu
		# SPEC 123: this WHEEL, and the wing rubbing on it. A hub has almost nothing.
		if body_parts_enabled:
			mu *= _body.wheel_grip(i)
			# SPEC 128: and a corner with no spring left cannot keep its tyre on the road.
			mu *= 1.0 - susp_sag_grip * _body.susp_sag(i)
		if has_hazard:
			mu *= _wheel_hazard[i]               # oil, sampled once per tick
		# Longitudinal share: rear wheel drive, `brake_bias` split under braking.
		var share := 0.0
		if a_demand >= 0.0:
			share = 0.0 if is_front else load / rear_load
		elif is_front:
			share = brake_bias * load / front_load
		else:
			share = (1.0 - brake_bias) * load / rear_load
		var long_demand := a_demand * share
		_tires.solve(w, v_fwd, v_lat, load, mu, long_demand, dt, max_speed)
		if _air > 0.0:
			# SPEC 121: with mu at zero the solver reports a wheel sliding infinitely fast (its capacity is
			# nothing, so any slip angle saturates it). A wheel in the air is not sliding -- it is doing
			# nothing -- and the marks and the dust read these fields.
			w["is_sliding"] = false
			w["slip_speed"] = 0.0
			w["saturation"] = 0.0
			w["lat_saturation"] = 0.0
			w["long_saturation"] = 0.0

		# The tick's last sub-step publishes the load and suspension fields; `position`, `forward` and
		# `speed` are re-derived from the final pose by `_refresh_wheel_pose` (SPEC 7.7 / decision 21.8)
		# and `local` never changes, so none of those are written here.
		if publish:
			w["load"] = load
			w["load_ratio"] = load / STATIC_LOAD
			w["compression"] = _susp.compression[i]
			w["steer"] = steer_angle() if is_front else 0.0
			w["lean"] = _susp.lean(i)
		var lat_sat := float(w["lat_saturation"])
		# Scrubbing wears the tyre (SPEC 49): a tyre past TYRE_SCRUB_FROM of its lateral limit is sliding
		# across the road, and a long drift costs rubber exactly as a long over-pull does.
		if apply and tyres_enabled and speed > 60.0:
			var scrub := (lat_sat - TYRE_SCRUB_FROM) / (1.0 - TYRE_SCRUB_FROM)
			if scrub > 0.0:
				_wear_tyre(i, tyre_wear_scrub * minf(scrub, 1.0) * dt)
		if not is_front:
			# LATERAL saturation only: the mixed `saturation` also carries the brake/drive demand, so a
			# dead-straight car at full throttle read 0.85-0.92 and quietly released the steering assist.
			rear_sat += lat_sat
		if apply:
			var f_i := dir * float(w["long_force"]) + right * float(w["lat_force"])
			_f_total += f_i
			_tau += r_w.cross(f_i)
	_rear_sat = rear_sat * 0.5
	if not (is_finite(_f_total.x) and is_finite(_f_total.y)):
		_f_total = Vector2.ZERO
	if not is_finite(_tau):
		_tau = 0.0


## SPEC 122: where the front wheels actually point -- what the driver asked for, plus whatever a bent
## rack is adding. Every reader of the steering angle goes through this, so a broken car and a whole one
## are described the same way.
func steer_angle() -> float:
	return clampf(_steer + _steer_bend, -max_steer * 2.0, max_steer * 2.0)


## Body slip angle the counter-steer holds a slide at, for THIS rope input (SPEC 7.6). A wider cursor angle
## sustains a wider, slower slide; a short rope tightens it. Without this a drift had exactly one flavour,
## because `omega_demand` saturates for any cursor more than ~14 deg off the nose.
func _hold_slip_for(diff: float, rope_len: float, pulling: bool) -> float:
	if not pulling:
		return drift_hold_slip
	var angle_f := clampf(absf(diff) / (PI * 0.5), 0.0, 1.0)
	var full_px := slack_radius + max_speed / maxf(speed_per_px, 0.001)
	var len_f := clampf(rope_len / maxf(full_px, 1.0), 0.0, 1.0)
	var hold := (drift_hold_slip + drift_hold_spread * (2.0 * angle_f - 1.0)) \
			* lerpf(drift_hold_short_factor, 1.0, len_f)
	return clampf(hold, 0.15, 1.20)


## 1 while the drift-carry speed exemption is free, fading to 0 as the slide is held (SPEC 7.6 / 20.x).
func _carry_strength() -> float:
	return clampf(1.0 - (_drift_time - drift_carry_free) / maxf(drift_carry_fade, 0.001), 0.0, 1.0)


## The car's right in world space, i.e. `(-y, x)` of a body vector (SPEC 7.1). NOT `Vector2.orthogonal()`:
## Godot's `orthogonal()` returns `(y, -x)`, which is the car's *left*. Using it would flip the sign of the
## yaw term in the contact-patch velocity, turning the tires' natural yaw damping into yaw amplification
## (the car then locks into a ±40 deg yaw limit cycle and cannot drive straight — measured).
func _right_of(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)


func _sync_suspension() -> void:
	_tilt = _susp.tilt
	_pitch = _susp.pitch
	_tilt_raw = _susp.tilt_raw


func _tick_visuals(dt: float) -> void:
	var k := clampf(visual_smooth * dt, 0.0, 1.0)
	_roll_vis = lerpf(_roll_vis, clampf(_tilt, -1.0, 1.0), k)
	_pitch_vis = lerpf(_pitch_vis, clampf(_pitch, -1.0, 1.0), k)
	_shake_mag = maxf(0.0, _shake_mag * exp(-shake_decay * dt))
	if _shake_mag < 0.02:
		_shake_mag = 0.0
	_shake_phase = fmod(_shake_phase + dt * 47.0, TAU)
	_roll_cooldown_left = maxf(0.0, _roll_cooldown_left - dt)


func _update_drift(dt: float) -> void:
	var fwd_dir := Vector2.from_angle(heading)
	var right_dir := _right_of(fwd_dir)
	var speed := velocity.length()
	_body_slip = atan2(velocity.dot(right_dir), maxf(absf(velocity.dot(fwd_dir)), maxf(slip_epsilon, 0.001)))
	# A started drift keeps its speed gate lowered while the car is still properly sideways, so the readout
	# does not cut out halfway through a slide the player can see.
	var fast_enough := speed >= drift_min_speed \
			or (_drifting and speed >= drift_sustain_speed and absf(_body_slip) >= drift_sustain_slip)
	var now := _roll_state != RollState.ROLLING and _roll_state != RollState.RECOVERING \
			and _rear_sat >= drift_rear_sat and fast_enough \
			and absf(_body_slip) >= drift_min_slip
	if now:
		_drift_intensity = clampf(0.6 * (absf(_body_slip) - drift_min_slip) / 0.55
				+ 0.4 * (_rear_sat - drift_rear_sat) / 0.50, 0.0, 1.0)
		_drift_time += dt
		_drift_banked += dt
		_no_drift_time = 0.0
		if not _drifting:
			_drifting = true
			drift_started.emit()
	else:
		_drift_intensity = 0.0
		if _drifting:
			_drifting = false
			drift_ended.emit(_drift_time)
		_no_drift_time += dt
		if _no_drift_time >= drift_grace:
			_drift_time = 0.0


# ---------------------------------------------------------------- rollovers

## How saturated the rear tyres are right now, 0..1 -- what a drift IS, numerically.
func get_rear_saturation() -> float:
	return clampf(_rear_sat, 0.0, 1.0)


func _add_tilt_shock(amount: float) -> void:
	if not is_finite(amount):
		return
	_tilt_shock = clampf(_tilt_shock + amount, -tilt_shock_max, tilt_shock_max)


func _bump(strength: float) -> void:
	_susp.bump(strength)


func _roll_entry(dt: float) -> void:
	if not rollovers_enabled:
		if _roll_state == RollState.TWO_WHEELS:
			_roll_state = RollState.GROUNDED
		return
	# The LIFT-FREE tilt. In TWO_WHEELS the inside pair is scaled to 0.08 of its load *before* Suspension
	# renormalises, so the lifted split is >= 0.85 for any non-negative roll transfer — the state's own
	# consequence inflated the number used to test whether to leave it, and TWO_WHEELS became a one-way
	# door (measured: 60 s of perfectly straight driving at 580 px/s never left it). Judging the machine on
	# the un-lifted transfer makes the exit test mean what it says; the lifted loads still feed the tires.
	var tilt_eff := clampf(_tilt_raw + _tilt_shock, -2.0, 2.0)
	var mag := absf(tilt_eff)
	var bonus := roll_cooldown_bonus if _roll_cooldown_left > 0.0 else 0.0
	var speed := velocity.length()
	# The ENTRY thresholds are judged on the speed that caused the trip (see `_roll_speed_hint`); the exit
	# tests stay on the current speed, so a car that has genuinely slowed still drops off its two wheels.
	var entry_speed := speed
	if _roll_speed_hint >= 0.0:
		entry_speed = maxf(entry_speed, _roll_speed_hint)
		_roll_speed_hint = -1.0
	match _roll_state:
		RollState.GROUNDED:
			# Straight to ROLLING when the trip is big enough (SPEC 8.2). Routing every rollover through
			# TWO_WHEELS first was tried and reverted: the barrier clamp removes the speed that caused the
			# trip, so by the next sub-step the car was below `roll_min_speed` and a genuine barrier
			# rollover at 400-580 px/s turned into a two-wheel wobble instead.
			if mag >= rollover_tilt + bonus and entry_speed >= roll_min_speed:
				_begin_roll(tilt_eff, entry_speed)
			elif mag >= two_wheel_tilt + bonus and entry_speed >= tip_min_speed:
				_roll_state = RollState.TWO_WHEELS
				_two_wheel_time = 0.0
				_two_wheel_calm = 0.0
		RollState.TWO_WHEELS:
			_two_wheel_time += dt
			if mag >= rollover_tilt + bonus and entry_speed >= roll_min_speed:
				_begin_roll(tilt_eff, entry_speed)
			elif _two_wheel_time >= two_wheel_max_time:
				# Unconditional timeout: the state is bounded in time whatever the tilt does. It becomes a
				# roll only if the car is still tipped over and fast; otherwise it simply drops back.
				if mag >= rollover_tilt - 0.05 and speed >= roll_min_speed:
					_begin_roll(tilt_eff, speed)
				else:
					_roll_state = RollState.GROUNDED
					_two_wheel_time = 0.0
					_two_wheel_calm = 0.0
			elif mag < two_wheel_release or speed < tip_min_speed * 0.5:
				# A slow car cannot stay balanced on two wheels. Without the speed clause a car left
				# leaning against the barrier (the clamp keeps removing the velocity the rope keeps adding,
				# so the load transfer never falls) stayed tilted for as long as the player held it there.
				_two_wheel_calm += dt
				if _two_wheel_calm >= two_wheel_settle:
					_roll_state = RollState.GROUNDED
			else:
				_two_wheel_calm = 0.0


func _begin_roll(tilt_eff: float, speed: float) -> void:
	var severity := clampf((absf(tilt_eff) - rollover_tilt) / 0.5
			+ 0.4 * speed / maxf(max_speed, 0.001), 0.0, 1.0)
	_roll_state = RollState.ROLLING
	_roll_duration = maxf(roll_time_base + roll_time_per_severity * severity, 0.05)
	_roll_timer = _roll_duration
	_roll_phase = 0.0
	# Always an EVEN number of half-turns, so `cos(_roll_phase * PI * _roll_turns)` is back at +1 when the
	# animation ends. With the old `1.0` for a mild roll the last ROLLING frame drew the car upside down
	# (y scale -1) and the first RECOVERING frame drew it upright: the barrel roll read as "lands on its
	# roof, then teleports back". `severity` now buys a longer roll (2 -> 4 half turns), not a mirrored one.
	_roll_turns = 2.0 if severity < 0.6 else 4.0
	_roll_dir = signf(tilt_eff)
	if _roll_dir == 0.0:
		_roll_dir = 1.0
	_tilt_shock = 0.0
	_two_wheel_time = 0.0
	_two_wheel_calm = 0.0
	_bump(clampf(severity * 120.0, 0.0, 160.0))
	_shake_mag = minf(_shake_mag + shake_impulse * (0.5 + severity), 18.0)
	rollover_started.emit(severity)
	# SPEC 102: a car on its roof hurts everywhere -- both vitals take half, through the panels.
	var roll_cost := damage_per_roll + damage_roll_severity * severity
	_hit_vital("engine", roll_cost * 0.5)
	_hit_vital("tank", roll_cost * 0.5)


func _scripted_roll(dt: float) -> void:
	_roll_timer -= dt
	if _roll_state == RollState.ROLLING:
		_roll_phase = clampf(1.0 - _roll_timer / maxf(_roll_duration, 0.001), 0.0, 1.0)
		velocity *= exp(-roll_drag * dt)
		velocity = velocity.limit_length(lerpf(max_speed, roll_end_speed, _roll_phase))
		_yaw_rate = _roll_dir * roll_spin * (1.0 - _roll_phase)
		heading = wrapf(heading + _yaw_rate * dt, -PI, PI)
		if _roll_timer <= 0.0:
			_bump(roll_land_bump)
			_shake_mag = minf(_shake_mag + shake_impulse * 0.5, 18.0)
			_roll_state = RollState.RECOVERING
			_roll_timer = maxf(recover_time, 0.01)
			_roll_phase = 1.0
	else:   # RECOVERING
		velocity = velocity.limit_length(recover_speed)
		_yaw_rate = lerpf(_yaw_rate, 0.0, minf(1.0, low_speed_yaw_damp * dt))
		var speed := velocity.length()
		if speed > heading_min_speed:
			var vdiff := wrapf(velocity.angle() - heading, -PI, PI)
			heading = wrapf(heading + clampf(vdiff, -6.0 * dt, 6.0 * dt), -PI, PI)
		if _roll_timer <= 0.0:
			_roll_state = RollState.GROUNDED
			_roll_timer = 0.0
			_roll_phase = 0.0
			_yaw_rate = 0.0
			_tilt_shock = 0.0
			_roll_cooldown_left = roll_cooldown
			rollover_recovered.emit()


# ---------------------------------------------------------------- wheel states

func _build_wheels() -> void:
	_wheels.resize(WHEEL_COUNT)
	for i in WHEEL_COUNT:
		_wheels[i] = {
			"index": i,
			"name": WHEEL_NAMES[i],
			"local": WHEEL_LOCAL[i],
			"position": Vector2.ZERO,
			"forward": Vector2.RIGHT,
			"load": STATIC_LOAD,
			"load_ratio": 1.0,
			"slip_angle": 0.0,
			"slip_speed": 0.0,
			"saturation": 0.0,
			"lat_saturation": 0.0,
			"long_saturation": 0.0,
			"is_sliding": false,
			"surface": SURFACE_ASPHALT,
			"compression": susp_rest,
			"steer": 0.0,
			"lean": 0.0,
			"speed": 0.0,
			"lat_force": 0.0,
			"long_force": 0.0,
		}


## Refreshes only the geometry / rest fields, so `get_wheel_states()` is meaningful before the first step.
func _refresh_wheel_geometry() -> void:
	var fwd_dir := Vector2.from_angle(heading)
	var steer_dir := Vector2.from_angle(heading + steer_angle())
	var surface := get_surface()
	for i in WHEEL_COUNT:
		var w: Dictionary = _wheels[i]
		var lw: Vector2 = WHEEL_LOCAL[i]
		var r_w := lw.rotated(heading)
		w["position"] = position + r_w
		w["forward"] = steer_dir if i < 2 else fwd_dir
		w["load"] = _susp.load[i]
		w["load_ratio"] = _susp.load[i] / STATIC_LOAD
		w["compression"] = _susp.compression[i]
		w["lean"] = _susp.lean(i)
		w["steer"] = steer_angle() if i < 2 else 0.0
		w["surface"] = surface
		w["speed"] = (velocity + _right_of(r_w) * _yaw_rate).length()


## Re-derives the four contact-patch poses from the CURRENT position / heading / steer, leaving every
## force-producing field (loads, slip, saturations, forces) exactly as `_solve_wheels` computed it.
func _refresh_wheel_pose() -> void:
	var fwd_dir := Vector2.from_angle(heading)
	var steer_dir := Vector2.from_angle(heading + steer_angle())
	for i in WHEEL_COUNT:
		var w: Dictionary = _wheels[i]
		var r_w: Vector2 = (WHEEL_LOCAL[i] as Vector2).rotated(heading)
		w["position"] = position + r_w
		w["forward"] = steer_dir if i < 2 else fwd_dir
		w["speed"] = (velocity + _right_of(r_w) * _yaw_rate).length()


## The four per-wheel state dictionaries, FL FR RL RR. The array and the dictionaries are created once and
## mutated in place: copy any value you intend to keep past the current frame.
func get_wheel_states() -> Array:
	return _wheels


func get_wheel_count() -> int:
	return WHEEL_COUNT


## Pushes the exported numbers into the tire and suspension models. Call it after changing any of them
## at runtime -- fitting an upgrade (SPEC 56) is the one thing that does.
func refresh_tuning() -> void:
	_apply_tuning()


func _apply_tuning() -> void:
	_tires.peak_accel = tire_peak_accel
	_tires.cornering_stiffness = cornering_stiffness
	_tires.shape_c = tire_shape_c
	_tires.load_exponent = load_exponent
	_tires.long_mu_ratio = long_mu_ratio
	_tires.slip_epsilon = slip_epsilon
	_tires.slide_threshold = slide_threshold
	_tires.slide_min_speed = slide_min_speed
	_tires.long_slip_start = long_slip_start
	_tires.long_slip_weight = long_slip_weight
	_susp.rest = susp_rest
	_susp.max_travel = susp_max
	# SPEC 58: worn springs and dampers let the body roll and pitch more.
	_susp.stiffness = susp_stiffness * (1.0 - susp_soft_loss * (1.0 - _susp_health) if parts_break else 1.0)
	_susp.damping = susp_damping


# ---------------------------------------------------------------- queries / control

func get_input_target() -> Vector2:
	if use_mouse and is_inside_tree():
		# Clamped to the canvas rect: in the letterbox bars of a non-16:9 window the mouse maps outside
		# 0..1280 / 0..720, which would hand the car a target it can never reach.
		var m := get_global_mouse_position()
		return Vector2(clampf(m.x, bounds.position.x, bounds.end.x), clampf(m.y, bounds.position.y, bounds.end.y))
	return target_point


func get_speed() -> float:
	return velocity.length()


## Where the rope leaves the car for the PHYSICS: the centre.
func rope_anchor() -> Vector2:
	return position


## Where the rope is DRAWN from (SPEC 106): the nose, whatever it pulls from.
func rope_draw_anchor() -> Vector2:
	if rope_drawn_at_nose:
		return position + Vector2.from_angle(heading) * NOSE_OFFSET
	return rope_anchor()


func get_rope_target() -> Vector2:
	return _rope_target if _has_rope_target else position


func get_rope_tension() -> float:
	return _rope_tension


## Points the rope at `target` without simulating (the car does not move). Used by the race during the
## countdown and the resume hold so the player sees where the car will be pulled. Tension follows distance.
func set_rope_preview(target: Vector2) -> void:
	_rope_target = target
	_has_rope_target = true
	var dist := rope_anchor().distance_to(target)
	var rope_speed := 0.0
	if dist > slack_radius:
		rope_speed = minf((dist - slack_radius) * speed_per_px, max_speed)
	_rope_tension = _tension_for(rope_speed)


## The speed the rope is asking for RIGHT NOW, in px/s, capped exactly the way the car itself caps it
## (`off_track_max_speed` on the grass, `max_speed` on the road). This is the player's throttle pedal, so
## the dashboard reads it from here instead of re-deriving the rope law from `slack_radius` /
## `speed_per_px` — the two used to drift apart, and the dash showed 100 % throttle while the car was
## limited to the grass crawl (fixer round 1, decision 30.9).
func get_target_speed() -> float:
	var dist := rope_anchor().distance_to(get_rope_target())
	var rope_speed := 0.0
	if dist > slack_radius:
		rope_speed = minf((dist - slack_radius) * speed_per_px, _effective_max_speed())
	return minf(rope_speed, _offroad_cap() if _off_track else _effective_max_speed())


## SPEC 128: the crawl cap, raised by however hard the rope is being pulled. Every reader of this --
## the physics, the dashboard throttle and the rope tension -- goes up together, so a player hauling at a
## stranded car sees the rope go taut and the dash climb, and the car actually moves.
func _offroad_cap() -> float:
	var base := sand_max_speed if _surface == SURFACE_SAND else off_track_max_speed
	return base * (1.0 + (maxf(offroad_haul, 1.0) - 1.0) * _haul)


## How much of the grass's flat drag the current pull overcomes.
func _offroad_drag() -> float:
	return off_track_drag * (1.0 - clampf(offroad_haul_relief, 0.0, 0.95) * _haul)


## Rope tension (0..1) for a rope that asks for `rope_speed`, capped by the speed the car can actually
## reach right now (the crawl cap while off track), so the visual never promises power the car has not got.
func _tension_for(rope_speed: float) -> float:
	if max_speed <= 0.0:
		return 0.0
	var limit := _offroad_cap() if _off_track else max_speed
	return clampf(minf(rope_speed, limit) / max_speed, 0.0, 1.0)


func set_on_track_provider(provider: Callable) -> void:
	_on_track_provider = provider


## OPTIONAL and unused in this round (SPEC decision 10.6): a side-effect-free `func(pos) -> bool` used per
## wheel instead of the body flag, so a later round can add per-wheel surfaces without a contract change.
func set_surface_probe(probe: Callable) -> void:
	_surface_probe = probe


func is_off_track() -> bool:
	return _off_track


func get_surface() -> String:
	if not _off_track:
		return SURFACE_ASPHALT
	return _surface if _surface != SURFACE_ASPHALT else SURFACE_GRASS


## OPTIONAL `func(pos) -> String` ("grass" or "sand"), asked once per frame while the car is off track.
func set_surface_provider(provider: Callable) -> void:
	_surface_provider = provider


## 0..~1.5: how far past its wheels' limit the rope is dragging the car right now (0 = not at all).
func get_overpull() -> float:
	return _overpull


## 0..2: how hard rough ground is shaking the car right now (sand can pass 1).
func get_rough() -> float:
	return _rough


## SPEC 128: seconds since another car last touched this one, up to 99. Scenery does not count.
func seconds_since_contact() -> float:
	return _contact_ago


## SPEC 137: THE BLAST. A wreck goes off, and what is standing next to it pays. The radius is measured in
## CAR LENGTHS of the car that blew up (`contact_reach()` is its half-length, so 2.0 is about one whole
## car of clearance beyond the bodywork), because a big car should leave a big hole and because that is
## the unit the garage's charges are sold in.
##
## `blast_damage` is what a car takes dead centre and falls to nothing at the rim, squared, so the last
## third of the radius is a scratch and standing on top of it is fatal. It goes THROUGH panels: bodywork
## is armour against another car, not against a bomb inside it (see `_add_damage_at`'s `through`).
##
## All three are scaled by the fitted charge (`Parts.SLOTS`), which is the only reason they are exports.
@export var blast_cars: float = 2.0
@export var blast_damage: float = 46.0
@export var blast_shove: float = 430.0


## The blast's reach in world px for this car, at this size.
func blast_reach() -> float:
	return maxf(blast_cars, 0.0) * contact_reach()


## Sets off `source`'s blast among `others` and returns the cars it caught. The caller owns the noise and
## the fireball -- this is only what the blast DOES. Nothing here touches the car that blew up: it is
## already wrecked, and a wreck cannot be wrecked twice.
static func blast(source: Car, others: Array) -> Array:
	if source == null or not is_instance_valid(source):
		return []
	var at: Vector2 = source.position
	var radius := source.blast_reach()
	var power := source.blast_damage
	var shove := source.blast_shove
	var caught: Array = []
	if radius <= 0.0 or power <= 0.0:
		return caught
	for o in others:
		var c := o as Car
		if c == null or not is_instance_valid(c) or c == source or c.is_wrecked() or not c.damage_enabled:
			continue
		# Measured to the nearest part of the body, not to `position`: a long car caught by its tail is
		# caught, and measuring centre to centre would let half of it stand inside the fireball unhurt.
		# Clearance between the two BODYWORKS, not between the two middles: `contact_reach()` of the car
		# that went up is subtracted as well. Measured the other way round first, and it meant a radius
		# of two car lengths spent the first one inside the exploding car -- a shaped charge that was
		# supposed to be point-blank lethal did 1 % to a car it was touching.
		var near: Vector2 = c.position
		var gap := INF
		for q in c.get_contact_circles():
			var g: float = at.distance_to(q) - c.contact_radius() - source.contact_reach()
			if g < gap:
				gap = g
				near = q
		if gap >= radius:
			continue
		var f := 1.0 - clampf(maxf(gap, 0.0) / radius, 0.0, 1.0)
		f *= f
		c._add_damage_at(near, power * f, true)
		var away: Vector2 = c.position - at
		away = away.normalized() if away.length() > 0.001 else Vector2.from_angle(c.heading)
		c.velocity += away * shove * f
		c._shake_mag = minf(c._shake_mag + 12.0 * f, 18.0)
		caught.append(c)
	return caught


## SPEC 135: write the car off on purpose -- restored after SPEC 128 removed it. SPEC 128's argument was
## that trading a bad race for a wait is a menu decision wearing a key, and the interesting decision is
## "can I get this thing round another lap?". That is still true, and it is exactly why the caller
## (`Race.can_self_destruct`) will not let the key work until the car is already half broken: the choice
## only exists once limping is genuinely one of the options. What SPEC 128 actually removed was the
## player's last way out of a car wedged nose-first into scenery with a bent rack -- the ONE case where
## the answer is "no" and there is nothing left to decide.
func self_destruct() -> void:
	if _wrecked or not damage_enabled:
		return
	_engine_health = 0.0
	_engine_dead = true
	_tank_health = 0.0
	damage = 100.0
	damage_changed.emit(damage)
	_wrecked = true
	_scatter_parts()
	wrecked.emit()


func get_damage() -> float:
	return damage


func is_wrecked() -> bool:
	return _wrecked


## SPEC 102: the vitals. `damage` (0..100) is the worse of the two.
func get_engine_damage() -> float:
	return 100.0 if _engine_dead else 100.0 * (1.0 - _engine_health)


func get_tank_damage() -> float:
	return 100.0 * (1.0 - _tank_health)


func get_tank_health() -> float:
	return _tank_health


func is_engine_dead() -> bool:
	return _engine_dead


## SPEC 110: what the car weighs in a contact -- `mass` less LIGHT_PER_PART per lost panel (a stripped
## car flies further), never under 60 % of it.
## SPEC 128: and less whatever named components have come off, which is the part that was configured and
## never read. A wheel is 5.5 % of the car and a mirror is a fraction of a percent; before this they both
## weighed exactly one panel, so a car that had lost a wheel shrugged off a shunt the same as one that
## had lost a wing mirror. The 60 % floor still holds: a car is never a feather.
func mass_now() -> float:
	var lighter := LIGHT_PER_PART * float(lost_parts())
	if body_parts_enabled:
		lighter += _body.mass_lost()
	return mass * maxf(1.0 - lighter, 0.6)


## SPEC 110: sudden death -- the vitals brought down to `engine` and `tank` (0..1) if they were higher.
func set_vitals(engine: float, tank: float) -> void:
	if not damage_enabled or _wrecked:
		return
	_engine_health = minf(_engine_health, clampf(engine, 0.0, 1.0))
	_tank_health = minf(_tank_health, clampf(tank, 0.01, 1.0))
	if _engine_health <= 0.0 and not _engine_dead:
		_engine_dead = true
		engine_died.emit()
	_refresh_damage()


## Clears all damage (the respawn after a wreck).
func repair() -> void:
	damage = 0.0
	_wrecked = false
	_reset_body()
	refresh_model()
	damage_changed.emit(0.0)
	queue_redraw()


## New tyres, every panel back on.
func _reset_body() -> void:
	for i in WHEEL_COUNT:
		_tyre_wear[i] = 0.0
		_burst[i] = false
	_parts_left = parts_to_lose
	_body.reset()                              # SPEC 123: every panel and wheel back on
	_heat = 0.0
	# SPEC 128: ... and the picture agrees with it again.
	_shown_body.resize(0)
	if _model != null:
		_model.restore_body()
	_lost_zone = {"front": 0, "rear": 0, "left": 0, "right": 0}
	_rope_strain = 0.0
	_rope_snapped = false
	_engine_health = 1.0
	_steering_health = 1.0
	_susp_health = 1.0
	_tank_health = 1.0
	_engine_dead = false
	_steering_side = 0.0
	_steer_bend = 0.0
	if parts_break:
		_apply_tuning()                           # the springs come back with the car
	if tyre_temp_enabled:
		_tyre_temp = TYRE_TEMP_START  # a fresh set, with some heat in it from the tow back to the road


## The engine's share of its power (SPEC 58): 1 when new, `1 - engine_power_loss` when it is finished.
func engine_factor() -> float:
	if _engine_dead:
		return engine_dead_power                  # SPEC 102: a dead engine limps
	return 1.0 - engine_power_loss * (1.0 - _engine_health) if parts_break else 1.0


func get_engine_health() -> float:
	return _engine_health


## SPEC 124: where the last wall hit landed, in world space -- the same point the impact damage is
## applied at. What a breakable needs in order to know whether it was the thing that was hit.
func last_impact_point() -> Vector2:
	return position + _impact_into * 16.0


## SPEC 128: A BENT CHASSIS, in radians -- the angle between where the car POINTS and where it goes. The
## wheels are still square to each other and no longer square to the road, so the whole car travels down
## the straight slightly sideways. Everything that draws or collides the car uses it (`rotation`), which
## is the point: a crabbed car takes up more road and clips what a straight one would clear.
func body_crab() -> float:
	return _body.crab() if body_parts_enabled else 0.0


## SPEC 130: the speed the wheels are being asked for, AFTER the rubber band's slack (`rope_hold_band`).
## `get_target_speed()` is what the rope is asking for, which is what a throttle reading wants; this is
## what the car is doing about it, which is what a BRAKE reading wants. The dashboard drew a brake at
## two thirds while the car was holding a steady speed on a steady rope, because the two had never had
## to be different before.
func get_held_speed() -> float:
	var asked := get_target_speed()
	var fwd := velocity.dot(Vector2.from_angle(heading))
	var dist := rope_anchor().distance_to(get_rope_target())
	if dist <= slack_radius or _rope_snapped:
		return asked
	var slack := rope_hold_band * max_speed
	if asked >= fwd:
		slack *= HOLD_FASTER if asked < max_speed * HOLD_TOP else 0.0
	# Half a pixel of tolerance: the car settles EXACTLY on the edge of the band and stays there, so an
	# exact comparison here flickered between "holding" and "braking" on floating-point noise -- and the
	# brake needle flickered with it.
	return fwd if absf(asked - fwd) <= slack + 0.5 else asked


## SPEC 128: how hot the engine has got through a holed radiator, 0..1. Zero on a car with a radiator.
func engine_heat() -> float:
	return _heat


## SPEC 122: which way a bent rack pulls -- +1 right, -1 left, 0 when nothing is bent. The HUD will only
## say "pulls right" when it knows the direction; "steering damaged" on its own is not actionable.
func steering_pull_side() -> int:
	if _steering_health >= 0.999 or not parts_break:
		return 0
	return int(signf(_steering_side))


func get_steering_health() -> float:
	return _steering_health


func get_suspension_health() -> float:
	return _susp_health


## The worst part on the car, for the dashboard's warning light: ["engine"|"steering"|"suspension", 0..1].
func worst_part() -> Array:
	var worst := "engine"
	var value := _engine_health
	if _steering_health < value:
		worst = "steering"
		value = _steering_health
	if _susp_health < value:
		worst = "suspension"
		value = _susp_health
	if _tank_health < value:
		worst = "tank"
		value = _tank_health
	return [worst, value]


## Top speed after damage: a battered car is down on power.
func _effective_max_speed() -> float:
	var rims := 1.0 - rim_speed_loss * float(get_burst_count()) if tyres_enabled else 1.0
	rims = minf(rims, speed_limit / maxf(max_speed * _boost_mult(), 1.0))   # SPEC 145: the yellow flag
	rims *= engine_factor()                      # SPEC 58: a sick engine is down on power
	# SPEC 123: a corner on its hub, or a bay hanging open, costs the car its pace. It has to come off
	# the TOP SPEED and not only out of the drive: the rope commands a target speed, so drag alone only
	# makes the car slower to get there and a car dragging a wheel would still have reached 600 px/s.
	if body_parts_enabled:
		rims *= 1.0 - clampf(_body.drag() * scrape_speed_loss, 0.0, 0.55)
		# SPEC 128: and the three other ways a car loses its pace -- a drivetrain that will not pull the
		# top gears, bodywork flapping in the air, and an engine cooking itself through a holed radiator.
		rims *= 1.0 - clampf(_body.drivetrain_loss(), 0.0, 0.6)
		rims *= 1.0 - clampf(flap_drag * _body.flap(), 0.0, 0.25)
		rims *= 1.0 - clampf(overheat_loss * _heat, 0.0, 0.5)
	# SPEC 102: the engine IS the damage that costs speed. A hurt tank leaks; it does not slow you.
	return max_speed * _boost_mult() * rims


# ---------------------------------------------------------------- tyres and body damage (SPEC 45)

func _wear_tyre(i: int, amount: float) -> void:
	if not tyres_enabled or _burst[i] or not (amount > 0.0):
		return
	_tyre_wear[i] = minf(_tyre_wear[i] + amount, 1.0)
	if _tyre_wear[i] >= 1.0:
		_burst[i] = true
		_shake_mag = minf(_shake_mag + shake_impulse, 18.0)
		_yaw_rate += (1.0 if (WHEEL_LOCAL[i] as Vector2).y > 0.0 else -1.0) * 0.6
		tyre_burst.emit(i, wheel_world(i))
		queue_redraw()


## A hit at `point` (world) of `closing` px/s: the tyre at that corner takes a knock, and a hard one may
## knock a piece off that side of the car.
func _body_hit(point: Vector2, closing: float) -> void:
	# SPEC 58: where the hit landed decides what it broke. Straight on the nose is the engine; a front
	# corner bends the steering.
	# SPEC 58/102: a front-corner hit bends the steering (the module behind the wing). The engine is not
	# hurt here any more -- it is a VITAL, reached only through a bare nose (`_add_damage_at`).
	if parts_break and closing > 40.0:
		var local := _local_dir(point)
		if local.x > 0.55 and absf(local.y) > 0.35:
			_steering_health = clampf(_steering_health - steering_hit_damage * closing, 0.0, 1.0)
			_steering_side = signf(local.y)
	if tyres_enabled and closing > part_min_hit:
		var best := 0
		var best_d := INF
		for i in WHEEL_COUNT:
			var d := wheel_world(i).distance_to(point)
			if d < best_d:
				best_d = d
				best = i
		_wear_tyre(best, tyre_wear_hit * closing)
	# SPEC 123: the component model, where it is switched on. It runs BESIDE the zone model rather than
	# instead of it -- the zones still decide what a vital is exposed to and what the decals draw -- and
	# it is what bends a named panel, buckles a named wheel and changes how the car drives.
	if body_parts_enabled:
		_hit_components(point, closing)
	if not parts_enabled or _parts_left <= 0 or closing < part_min_hit:
		return
	# SPEC 102: the panels are armour, so a hard hit on a zone that still has one takes it, every time
	# (it used to be a dice roll) -- and a hit on a bare zone dents what is left and takes nothing: the
	# vital behind it is what pays now.
	_part_seq += 1
	if armour_left(_zone_of(_local_dir(point))) <= 0:
		if _model != null:
			_model.dent(_local_dir(point), clampf(closing / 400.0, 0.2, 1.0))
		return
	_lose_part(point, closing)


## SPEC 123: one blow, spread over whatever was near it. Everything that changed state is thrown off the
## car as debris and said out loud; a wheel coming off is loud, a wing is not.
func _hit_components(point: Vector2, closing: float) -> void:
	# `heft` is the mass behind the blow against a reference car: a heavy car does more damage, which is
	# the same relationship `mass` already has with braking.
	var heft := clampf(mass / MASS_REF, 0.3, 2.5)
	for change in _body.hit(_local_point(point), closing, heft):
		var d: Dictionary = change
		if int(d["to"]) != CarBody.State.GONE:
			continue
		var at: Vector2 = d["at"]
		var out := Vector2.from_angle(at.angle() + heading)
		var wheel := String(d["kind"]) == "wheel"
		var where := position + at.rotated(heading)
		var fling := velocity * 0.5 + out * clampf(closing * 0.45, 70.0, 240.0)
		if wheel:
			wheel_lost.emit(where, fling)                # SPEC 142: a tyre rolls, it does not cut
			_shake_mag = minf(_shake_mag + shake_impulse, 18.0)
		else:
			part_lost.emit(where, fling, body_color, Vector2(9.0, 4.0))
	_refresh_wheel_geometry()
	queue_redraw()


## SPEC 123: what is left of the car, for the HUD, the results and the tests.
func get_body() -> CarBody:
	return _body


## SPEC 123: where `point` is, seen from the car, in PIXELS on the car's own 36x18 body -- which is the
## frame `CarBody` places its components in. `_local_dir` below normalises the same thing to a direction,
## which is all the zone model ever needed.
func _local_point(point: Vector2) -> Vector2:
	return (point - position).rotated(-heading)


## Where `point` is, seen from the car: (forward, right), normalized.
func _local_dir(point: Vector2) -> Vector2:
	var d := (point - position).rotated(-heading)
	return d.normalized() if d.length() > 0.5 else Vector2.RIGHT


## SPEC 80: throw a piece off, because something other than an impact decided it was time -- shed one
## at each damage threshold and a car visibly comes apart instead of looking showroom-fresh right up to
## the moment it explodes. Does nothing once there is nothing left to lose.
func throw_part(point: Vector2) -> bool:
	if not parts_enabled or _parts_left <= 0:
		return false
	# SPEC 102: from the zone that was hit while it has panels; otherwise from the next zone that does.
	var zone := _zone_of(_local_dir(point))
	if armour_left(zone) > 0:
		_lose_part(point, part_min_hit + 60.0)
		return true
	for other in ["front", "rear", "left", "right"]:
		if armour_left(String(other)) > 0:
			_lose_part(position + _zone_point(String(other)), part_min_hit + 60.0)
			return true
	return false


## A world offset onto the middle of `zone`, for a part that has to come off a particular side.
func _zone_point(zone: String) -> Vector2:
	var fwd := Vector2.from_angle(heading)
	match zone:
		"front":
			return fwd * 16.0
		"rear":
			return -fwd * 16.0
		"right":
			return _right_of(fwd) * 10.0
		_:
			return -_right_of(fwd) * 10.0


func _lose_part(point: Vector2, closing: float) -> void:
	_parts_left -= 1
	var local := _local_dir(point)
	var zone := _zone_of(local)
	_lost_zone[zone] = int(_lost_zone[zone]) + 1
	if armour_left(zone) <= 0:
		zone_bared.emit(zone)                     # SPEC 102: what is behind it can be hit now
	var piece := {}
	if _model != null:
		_model.dent(local, clampf(closing / 400.0, 0.2, 1.0))
		piece = _model.detach_part(local)
	var col: Color = piece.get("color", body_color if _part_seq % 3 != 0 else Color(0.1, 0.1, 0.11))
	var size: Vector2 = piece.get("size", Vector2(7.0, 4.0) if _part_seq % 2 == 0 else Vector2(5.0, 3.0))
	var out := Vector2.from_angle(local.angle() + heading)
	part_lost.emit(position + out * 12.0, velocity * 0.55 + out * clampf(closing * 0.4, 60.0, 220.0), col, size)


## The wreck: whatever was still on the car comes off, and a wheel or two with it.
func _scatter_parts() -> void:
	if not parts_enabled:
		return
	var n := maxi(_parts_left, 0) + 2
	for k in n:
		_part_seq += 1
		var ang := float(k) / float(n) * TAU + 0.7
		var out := Vector2.from_angle(ang)
		var col := body_color
		var size := Vector2(8.0, 5.0)
		var fling := velocity * 0.4 + out * (120.0 + 30.0 * float(k % 3))
		if k >= n - 2:
			wheel_lost.emit(position + out * 10.0, fling)   # SPEC 142: a wheel rolls off, rubber
			continue
		if k % 3 == 1:
			col = Color(0.12, 0.14, 0.18)               # glass / trim
			size = Vector2(6.0, 3.0)
		part_lost.emit(position + out * 10.0, fling, col, size)
	_parts_left = 0
	# SPEC 123: and every named component with them.
	if body_parts_enabled:
		for change in _body.scatter():
			var d: Dictionary = change
			var at: Vector2 = d["at"]
			var out := Vector2.from_angle(at.angle() + heading)
			if String(d["kind"]) == "wheel":
				wheel_lost.emit(position + at.rotated(heading), velocity * 0.4 + out * 150.0)
			else:
				part_lost.emit(position + at.rotated(heading), velocity * 0.4 + out * 150.0,
						body_color, Vector2(8.0, 4.0))


## "front", "rear", "left" or "right" for a car-local direction (x forward, y right).
static func _zone_of(local: Vector2) -> String:
	if absf(local.x) >= absf(local.y):
		return "front" if local.x > 0.0 else "rear"
	return "right" if local.y > 0.0 else "left"


func lost_parts() -> int:
	return int(_lost_zone["front"]) + int(_lost_zone["rear"]) + int(_lost_zone["left"]) + int(_lost_zone["right"])


func get_lost_zones() -> Dictionary:
	return _lost_zone.duplicate()


## SPEC 102: how many panels each zone starts with -- its armour. `parts_to_lose` is split so the sides
## open first (one panel each on a race car) and the nose and the tail carry the most.
func armour_capacity(zone: String) -> int:
	var side := maxi(parts_to_lose / 5, 1)
	var front := (parts_to_lose - 2 * side + 1) / 2
	match zone:
		"front":
			return front
		"rear":
			return parts_to_lose - 2 * side - front
		_:
			return side


func armour_left(zone: String) -> int:
	return maxi(armour_capacity(zone) - int(_lost_zone.get(zone, 0)), 0)


## True when the zone has no panel left: a hit there reaches the vital behind it.
func is_bare(zone: String) -> bool:
	return parts_enabled and armour_left(zone) <= 0


## How many of the four zones are open.
func bare_zone_count() -> int:
	var n := 0
	for zone in ["front", "rear", "left", "right"]:
		if is_bare(String(zone)):
			n += 1
	return n


## Something sharp under wheel `point` (world): that tyre takes `amount` of wear (SPEC 46: car debris).
func puncture(point: Vector2, amount: float) -> void:
	var best := 0
	var best_d := INF
	for i in WHEEL_COUNT:
		var d := wheel_world(i).distance_to(point)
		if d < best_d:
			best_d = d
			best = i
	_wear_tyre(best, amount)


## Wider wheels for a fitted set (SPEC 56).
func set_model_wheel_scale(scale: float) -> void:
	if _model != null:
		_model.set_wheel_scale(scale)


## The player's car refreshes its 3D model the moment it changes; rivals share a budget (SPEC 54).
func set_model_priority(on: bool) -> void:
	if _model != null:
		_model.priority = on


## Oil (and anything else slippery) on the road: `probe(world_pos) -> grip factor` per wheel.
func set_hazard_probe(probe: Callable) -> void:
	_hazard_probe = probe


## Where the barrier is lined with tyres: `probe(world_pos) -> bool` (SPEC 49).
func set_wall_probe(probe: Callable) -> void:
	_wall_probe = probe


## How deep in another car's wake this car is, 0..1 (SPEC 49). Race measures it every frame.
func set_slipstream(amount: float) -> void:
	_slipstream = clampf(amount, 0.0, 1.0) if slipstream_enabled else 0.0


func get_slipstream() -> float:
	return _slipstream


## How much grip this car has right now against a warm, healthy set (SPEC 49): the tyre temperature and
## any burst tyre. A driver feels this -- the AI plans its corner speeds from it (v scales with sqrt(mu)).
func grip_condition() -> float:
	var g := lerpf(tyre_cold_grip, 1.0, _tyre_temp) if tyre_temp_enabled else 1.0
	if tyres_enabled:
		var n := get_burst_count()
		if n > 0:
			g *= lerpf(1.0, rim_grip, clampf(float(n) / 4.0, 0.0, 1.0))
	return g


## Tyre temperature, 0 (stone cold) to 1 (up to temperature) -- SPEC 49.
func get_tyre_temp() -> float:
	return _tyre_temp


func set_tyre_temp(value: float) -> void:
	_tyre_temp = clampf(value, 0.0, 1.0)


## The rope frays where it drags (SPEC 49): across the barrier, or round a tyre stack it has snagged.
## Race feeds that in here, and it pushes the rope toward the snap exactly as an over-pull does.
func add_rope_strain(amount: float) -> void:
	if not rope_snap_enabled or _rope_snapped or not (amount > 0.0):
		return
	_rope_strain += amount
	if _rope_strain >= 1.0:
		_rope_snapped = true
		_rope_strain = 0.0
		_overpull = 0.0
		rope_snapped.emit(position)


func is_rope_snapped() -> bool:
	return _rope_snapped


func get_rope_strain() -> float:
	return _rope_strain


func wheel_world(i: int) -> Vector2:
	return position + (WHEEL_LOCAL[i] as Vector2).rotated(heading)


func is_tyre_burst(i: int) -> bool:
	return _burst[i]


func get_burst_count() -> int:
	var n := 0
	for b in _burst:
		if b:
			n += 1
	return n


func get_tyre_wear(i: int) -> float:
	return _tyre_wear[i]


func get_parts_left() -> int:
	return _parts_left


# ---------------------------------------------------------------- boost (SPEC 39)

func _tick_boost(dt: float) -> void:
	if _boost_left > 0.0:
		_boost_left = maxf(_boost_left - dt, 0.0)
		return
	var gain := 0.0
	if _in_band:
		gain += boost_charge_tension
	if _drifting:
		gain += boost_charge_drift * clampf(_drift_intensity, 0.0, 1.0)
	_boost_meter = minf(_boost_meter + gain * dt, 1.0)


## Spends a full meter: `boost_time` s of extra top speed and drive. False (and nothing happens) if the
## meter is not full, the car is already boosting, is locked, wrecked or upside down.
## SPEC 110: spends whatever TIER is charged (a third, two thirds, all) for that tier's share of
## `boost_time`. The AI still waits for a full meter (`is_boost_ready`); the player clicks when it suits.
func fire_boost() -> bool:
	var tier := boost_tier()
	if not boost_enabled or tier < 1 or _boost_left > 0.0 or _locked or _wrecked \
			or _engine_dead or _roll_state == RollState.ROLLING:
		return false
	_boost_meter = 0.0
	_boost_left = boost_time * float(TIER_TIMES[tier])
	_set_stretch(maxf(_stretch, STRETCH_BOOST))
	boost_fired.emit()
	return true


## SPEC 110: the charge in thirds: 0 none, 1 blue, 2 orange, 3 purple (full).
func boost_tier() -> int:
	if not boost_enabled:
		return 0
	return clampi(int(floor(_boost_meter * 3.0 + 0.0001)), 0, 3)


func can_fire_boost() -> bool:
	return boost_enabled and boost_tier() >= 1 and _boost_left <= 0.0 and not _locked and not _wrecked \
			and not _engine_dead


## SPEC 110: a top-up from outside the drift -- a near miss, an overtake.
func add_boost_charge(amount: float) -> void:
	if boost_enabled and amount > 0.0:
		_boost_meter = minf(_boost_meter + amount, 1.0)


## SPEC 110: the stretch eases back, and the rope snapping taut stretches the car along its nose.
func _tick_stretch(dt: float) -> void:
	if _rope_tension > 0.8 and _prev_tension < 0.4:
		_set_stretch(maxf(_stretch, STRETCH_TAUT))
	_prev_tension = _rope_tension
	if absf(_stretch) > 0.0005:
		_set_stretch(_stretch * exp(-STRETCH_DECAY * maxf(dt, 0.0)))
	elif _stretch != 0.0:
		_set_stretch(0.0)


## SPEC 122: a slide, then the catch. Run once per physics FRAME (not per sub-step), because the two
## times it measures are in seconds of driving and must not depend on the sub-step count.
##
## Guarding against a reward farmed from steering jitter takes both halves: the slide must run for
## `clean_exit_slide` before an exit means anything, and the car must then be settled for
## `clean_exit_hold` CONTINUOUSLY -- one frame of slip resets the hold, and a slide that fizzles out
## without ever settling bleeds its credit away rather than banking it.
func _tick_clean_exit(delta: float) -> void:
	if _locked or _wrecked:
		_slide_time = 0.0
		_settle_time = 0.0
		_exit_armed = false
		return
	if _drifting:
		_slide_time += delta
		_settle_time = 0.0
		if _slide_time >= clean_exit_slide:
			_exit_armed = true
		return
	if not _exit_armed:
		_slide_time = maxf(_slide_time - delta, 0.0)
		return
	var settled: bool = velocity.length() >= clean_exit_speed \
			and absf(get_slip_angle()) <= clean_exit_slip \
			and _touched_timer <= 0.0 and _roll_state == RollState.GROUNDED and _air <= 0.0
	if not settled:
		_settle_time = 0.0
		# Not caught -- a spin, a wall, a shove. The credit for the slide decays rather than waiting
		# around for an unrelated straight later on.
		_slide_time = maxf(_slide_time - delta, 0.0)
		if _slide_time < clean_exit_slide * 0.5:
			_exit_armed = false
		return
	_settle_time += delta
	if _settle_time < clean_exit_hold:
		return
	var held := _slide_time
	_exit_armed = false
	_slide_time = 0.0
	_settle_time = 0.0
	add_boost_charge(clean_exit_charge)
	clean_exit.emit(held)


## SPEC 122: how long the slide that is running now has lasted, and whether catching it would count.
func get_slide_time() -> float:
	return _slide_time


func clean_exit_ready() -> bool:
	return _exit_armed


## The stretch is the node's scale, applied the moment it is set (a boost stretches THIS frame).
func _set_stretch(v: float) -> void:
	_stretch = v if absf(v) > 0.0005 else 0.0
	_apply_scale()


## SPEC 122: THE ONE PLACE THAT WRITES `scale`. Three things want to change how big the car is drawn --
## the bridge deck, SPEC 121's flight, and the squash of a boost or a bump -- and each of them used to
## assign `scale` outright. So whichever ran last won, and a car that was pulled hard could visibly
## shrink and stay shrunk until something else happened to write the scale back. They are multiplied
## together here instead, and nothing else in the file assigns `scale` at all.
func _apply_scale() -> void:
	var s := (BRIDGE_SCALE if _on_deck else 1.0) * (1.0 + air_lift * _air)
	scale = Vector2(s * (1.0 + _stretch), s * (1.0 - 0.5 * _stretch))


func get_stretch() -> float:
	return _stretch


## 1 while boosting (fading out over the last 30 % of it), else 0.
func _boost_strength() -> float:
	if _boost_left <= 0.0 or boost_time <= 0.0:
		return 0.0
	return clampf(_boost_left / (boost_time * 0.3), 0.0, 1.0)


## Everything that lifts the car's speed ceiling: the boost, and the tow of a slipstream (SPEC 49). Used
## for the ceiling AND for the rope's demand, so a towed car asks for the extra speed as well as keeping it.
func _boost_mult() -> float:
	return (1.0 + boost_speed * _boost_strength()) * (1.0 + slipstream_speed * _slipstream)


func get_boost_meter() -> float:
	return _boost_meter


func is_boosting() -> bool:
	return _boost_left > 0.0


func is_boost_ready() -> bool:
	return boost_enabled and _boost_meter >= 1.0 and _boost_left <= 0.0


## True while the rope rides the tension zone at full speed (the boost is charging from it).
func is_in_tension_zone() -> bool:
	return _in_band


## What the race bar shows: the meter while charging, the boost still left (as a share) while boosting.
func get_boost_display() -> float:
	if _boost_left > 0.0:
		return clampf(_boost_left / maxf(boost_time, 0.01), 0.0, 1.0)
	return _boost_meter


## Rope lengths (px from the car) where the tension zone starts (full throttle) and ends (past it, the
## rope drags) -- for drawing the zone.
func get_zone_radii() -> Vector2:
	var spp := maxf(speed_per_px, 0.001)
	var bm := _boost_mult()
	return Vector2(slack_radius + max_speed * bm / spp, slack_radius + max_speed * (bm + rope_band) / spp)


## For tests / tools: fill or empty the meter.
func set_boost_meter(v: float) -> void:
	_boost_meter = clampf(v, 0.0, 1.0)


## Damage with no place on the car -- fire, the ring, an over-pulled rope: heat. SPEC 102: it cooks the
## engine, and once the engine is dead it reaches the fuel.
func _add_damage(amount: float) -> void:
	if not damage_enabled or _wrecked or not (amount > 0.0) or not is_finite(amount):
		return
	_hit_vital("engine", amount)


## SPEC 102: damage that landed somewhere. While the zone it hit still has panels it costs nothing here
## (`_body_hit` takes the panel); a bare zone lets it through to the vital behind it -- the engine under
## the nose, the tank under the tail, either by which half of a bare side. `through` is for what no
## panel stops: a wall, a slam, a blast.
func _add_damage_at(point: Vector2, amount: float, through: bool = false) -> void:
	if not damage_enabled or _wrecked or not (amount > 0.0) or not is_finite(amount):
		return
	var local := _local_dir(point)
	var zone := _zone_of(local)
	# SPEC 123: TWO MODELS, ONE RULE EACH, never both on the same car. The zone model is all-or-nothing
	# -- a panel is there, so the vital behind it cannot be touched at all, which makes bodywork a stack
	# of extra lives. The component model ABSORBS instead: a bumper that is still on takes most of the
	# blow and passes the rest through, and one that has been knocked off passes all of it. A car with
	# `body_parts_enabled` uses the second and only the second.
	if body_parts_enabled:
		if not through:
			amount *= _body.shield(local)
	elif not through and parts_enabled and armour_left(zone) > 0:
		return
	var vital := "engine" if zone == "front" or (zone != "rear" and local.x >= 0.0) else "tank"
	_hit_vital(vital, amount)


## The vital takes `amount` (on the 0..100 damage scale). A dead engine passes what it is given on to
## the tank -- the fire reaches the fuel, the crushed nose reaches the rest -- so a wreck is always
## reachable, only never by anything that could not reach a vital in the first place.
## SPEC 122: THE OVERFLOW IS WORKED OUT ON THE BLOW, NOT ON THE ENGINE'S VIEW OF IT. `engine_fragility`
## is how much of a blow the ENGINE feels -- a fragile engine is hurt more by the same crash -- and this
## used to scale `amount` in place and then subtract the engine's remaining health from the SCALED
## figure before passing it to the tank. So a fragility of 2 did not just make the engine twice as easy
## to kill, it also handed the tank twice the surplus: a 10-point hit on a nearly dead engine put 20
## points into the fuel. A modifier is applied to the base value, once, and what passes through is the
## share of the ORIGINAL blow the engine could not absorb.
func _hit_vital(vital: String, amount: float) -> void:
	if not damage_enabled or _wrecked or not (amount > 0.0) or not is_finite(amount):
		return
	if vital == "engine" and not _engine_dead:
		# `left` is the engine's whole remaining health -- how much of this blow it can still absorb.
		var left := maxf(_engine_health, 0.0) * 100.0
		var felt := amount * maxf(engine_fragility, 0.0)
		_engine_health = clampf(_engine_health - felt / 100.0, 0.0, 1.0)
		if _engine_health <= 0.0:
			_engine_dead = true
			_boost_left = 0.0
			engine_died.emit()
		if felt <= left or felt <= 0.0:
			_refresh_damage()
			return
		# The engine took `left` of what it felt; the rest of the blow went past it, and the tank is hit
		# by that fraction of the blow as it was DEALT.
		amount *= (felt - left) / felt
	_tank_health = clampf(_tank_health - amount * maxf(tank_fragility, 0.0) / 100.0, 0.0, 1.0)
	_refresh_damage()
	if _tank_health <= 0.0 and not _wrecked:
		_wrecked = true
		_scatter_parts()
		wrecked.emit()


## `damage` is the worse vital, so everything that reads it (the scratches, the AI's caution, the SCRAP
## threshold, the net state) keeps reading the car's distance from a wreck.
func _refresh_damage() -> void:
	var now := 100.0 * maxf(1.0 - _engine_health, 1.0 - _tank_health)
	if not is_equal_approx(now, damage):
		damage = now
		damage_changed.emit(damage)


## Smooth deterministic noise in -1..1 over ~140 px (rough ground, the over-pull wobble). A function of
## position only, so replays and the determinism tests are unaffected.
static func _terrain_noise(p: Vector2) -> float:
	return clampf(sin(p.x * 0.045 + sin(p.y * 0.031) * 2.0) * 0.6
			+ sin(p.y * 0.052 + p.x * 0.017) * 0.4, -1.0, 1.0)


func lock() -> void:
	_locked = true
	velocity = Vector2.ZERO
	_rope_tension = 0.0
	# A locked car is not driving: the actuator states go with the velocity (SPEC 17.4).
	_a_cmd = 0.0
	_omega_cmd = 0.0


func unlock() -> void:
	_locked = false


func is_locked() -> bool:
	return _locked


## SPEC 128: `keep_damage` puts the car down WITHOUT repairing it -- the same clean slate for everything
## that is about motion (velocity, yaw, suspension, roll, drift, boost, the rope) and not a scratch taken
## off the bodywork. Un-wedging a stuck car uses it: being lifted out is a rescue from a bug, and a free
## rebuild would make driving into scenery the fastest repair in the game.
func reset_to(pos: Vector2, heading_rad: float, keep_damage: bool = false) -> void:
	position = pos
	heading = wrapf(heading_rad, -PI, PI)
	rotation = heading + body_crab()
	velocity = Vector2.ZERO
	_rope_tension = 0.0
	_has_rope_target = false
	_apply_tuning()
	_yaw_rate = 0.0
	_steer = 0.0
	_a_cmd = 0.0
	_omega_cmd = 0.0
	_a_body = Vector2.ZERO
	_frame_lat = 0.0
	_frame_speed = 0.0
	_roll_speed_hint = -1.0
	_susp.reset()
	_sync_suspension()
	_tilt_shock = 0.0
	_roll_vis = 0.0
	_pitch_vis = 0.0
	_roll_state = RollState.GROUNDED
	_roll_timer = 0.0
	_roll_phase = 0.0
	_roll_dir = 1.0
	_roll_cooldown_left = 0.0
	_two_wheel_time = 0.0
	_two_wheel_calm = 0.0
	_drift_time = 0.0
	_drift_banked = 0.0
	_no_drift_time = 0.0
	_drifting = false
	_drift_intensity = 0.0
	_body_slip = 0.0
	_rear_sat = 0.0
	_shake_mag = 0.0
	_shake_phase = 0.0
	_impact_timer = 0.0
	_contact_timer = 0.0
	_touched_timer = 0.0
	_contact_ago = 99.0
	_slide_time = 0.0
	_settle_time = 0.0
	_exit_armed = false
	_pending_impact = 0.0
	_dust_phase = 0.0
	_overpull = 0.0
	_set_air(0.0)
	_air_time = 0.0
	_air_spent = false
	_in_band = false
	_boost_meter = 0.0
	_boost_left = 0.0
	_stretch = 0.0
	_prev_tension = 0.0
	_apply_scale()
	_rough = 0.0
	_surface = SURFACE_ASPHALT
	if not keep_damage:
		_reset_body()
		damage = 0.0
		_wrecked = false
	_refresh_wheel_geometry()
	if _off_track:
		_off_track = false
		off_track_changed.emit(false)
	queue_redraw()


# ---------------------------------------------------------------- drift / attitude queries

func is_drifting() -> bool:
	return _drifting


func drift_intensity() -> float:
	return _drift_intensity


func get_drift_time() -> float:
	return _drift_time


## Total seconds spent drifting since the last `reset_to()` (the live streak is `get_drift_time()`).
func get_drift_total() -> float:
	return _drift_banked


## 1..0: how much of the drift-carry speed exemption is left (see `drift_carry_free`). 1 while a slide is
## young, 0 once it has been held long enough that it starts costing speed.
func get_drift_carry() -> float:
	return _carry_strength()


func get_slip_angle() -> float:
	return _body_slip


func get_yaw_rate() -> float:
	return _yaw_rate


## The driver's own steering command, inside `max_steer`. `steer_angle()` is this plus whatever a bent
## rack is adding, and that is what the wheels are actually pointed along (SPEC 122).
func get_steer_angle() -> float:
	return _steer


## -1..1, + = leaning onto the car's LEFT wheels. During a rollover this is the barrel-roll animation:
## `sin` rather than `cos`, so it reads 0 when the car is on its wheels — at the START of the roll and
## again at the END of it — and sweeps to +-1 while it is over. With `cos` it was +-1 at both ends, i.e.
## "fully leant" at exactly the two moments the car is upright, and every consumer of this value (the
## shadow offset above all) jumped by a whole unit on the ROLLING -> RECOVERING frame.
func get_body_roll() -> float:
	if _roll_state == RollState.ROLLING:
		return clampf(_roll_dir * sin(_roll_phase * PI * _roll_turns), -1.0, 1.0)
	return clampf(_roll_vis, -1.0, 1.0)


## -1..1, + = nose down (braking).
func get_body_pitch() -> float:
	return clampf(_pitch_vis, -1.0, 1.0)


## 0..1, how far off the ground the car is during a rollover.
func get_roll_height() -> float:
	if _roll_state == RollState.ROLLING:
		return clampf(sin(_roll_phase * PI), 0.0, 1.0)
	return 0.0


## The -1..1 values `_draw` actually leans the body by: `get_body_roll()` / `get_body_pitch()` normalised by
## `*_visual_reference` and shaped by `*_visual_curve`. Public so the shape can be pinned and so a future
## consumer (a chase camera, a mirror) leans by exactly what the car does.
func get_display_roll() -> float:
	if _roll_state == RollState.ROLLING:
		return get_body_roll()
	return _shape_display(get_body_roll(), roll_visual_reference, roll_visual_curve)


func get_display_pitch() -> float:
	return _shape_display(get_body_pitch(), pitch_visual_reference, pitch_visual_curve)


## (pitch, roll), unsmoothed, -1..1 each.
func get_load_transfer() -> Vector2:
	return Vector2(clampf(_pitch, -1.0, 1.0), clampf(_tilt, -1.0, 1.0))


## SPEC 17.4 — the weight transfer made visible. Front share of the total load, 0..1 (0.5 == neutral,
## > 0.5 == nose loaded under braking). A pure read of `_susp.load[]`, which always sums to 1.
func get_axle_load_balance() -> float:
	var front := float(_susp.load[0]) + float(_susp.load[1])
	var total := front + float(_susp.load[2]) + float(_susp.load[3])
	if not (total > 0.0) or not is_finite(total):
		return 0.5
	return clampf(front / total, 0.0, 1.0)


## Left share of the total load, 0..1 (SPEC 7.4 sign: + roll == loaded on the car's LEFT).
func get_lateral_load_balance() -> float:
	var left := float(_susp.load[0]) + float(_susp.load[2])
	var total := left + float(_susp.load[1]) + float(_susp.load[3])
	if not (total > 0.0) or not is_finite(total):
		return 0.5
	return clampf(left / total, 0.0, 1.0)


## Decaying impact shake in px. Deterministic (driven by accumulated dt, never by the clock).
func get_shake_offset() -> Vector2:
	if _shake_mag <= 0.0:
		return Vector2.ZERO
	# SPEC 126: a quarter of it on the calm setting. Not none: the shake is how a hard hit is FELT, and
	# a player who has turned the spectacle down still has to know they hit something.
	return Vector2(sin(_shake_phase * 3.7), cos(_shake_phase * 5.3)) * _shake_mag * shake_scale


func get_roll_state() -> int:
	return _roll_state


func is_rolling() -> bool:
	return _roll_state == RollState.ROLLING or _roll_state == RollState.RECOVERING


func is_on_two_wheels() -> bool:
	return _roll_state == RollState.TWO_WHEELS


func get_roll_time_left() -> float:
	if _roll_state == RollState.ROLLING or _roll_state == RollState.RECOVERING:
		return maxf(_roll_timer, 0.0)
	return 0.0


## Z ordering only: `true` draws the car above the bridge deck, `false` below it. The layering zone is
## deliberately a little longer than the drawn deck (it prevents flicker at the deck ends), so the visible
## "climbing onto the bridge" cue (scale + shadow) is driven separately by `set_bridge_scale()`.
func set_bridge_layer(on_bridge: bool) -> void:
	if on_bridge == _on_bridge and z_index == (Z_ON_BRIDGE if on_bridge else Z_UNDER_BRIDGE):
		return
	_on_bridge = on_bridge
	z_index = Z_ON_BRIDGE if on_bridge else Z_UNDER_BRIDGE
	queue_redraw()


## SPEC 121: how far off the ground the rope has pulled the car -- 0 on its tyres, 1 fully airborne.
func get_air() -> float:
	return _air


## SPEC 121: true while the tyres are doing nothing because none of them is touching the ground.
func is_airborne() -> bool:
	return _air > 0.0


## SPEC 121: the visible part of flying -- a bigger body, from further away. It only ever sets `_air`
## and asks `_apply_scale()` for the drawing, so it cannot undo the deck or the squash (SPEC 122).
func _set_air(value: float) -> void:
	_air = value
	if is_equal_approx(_air, _air_drawn):
		return
	_air_drawn = _air
	_apply_scale()
	_request_redraw()


## Raised look (scale + stronger drop shadow) while the car is actually on the drawn deck.
func set_bridge_scale(on_deck: bool) -> void:
	if on_deck == _on_deck:
		return
	_on_deck = on_deck
	_apply_scale()
	_bump(bridge_bump)
	queue_redraw()


func is_on_bridge_layer() -> bool:
	return _on_bridge


func is_on_bridge_deck() -> bool:
	return _on_deck


# ---------------------------------------------------------------- drawing

## Perf round: the car asks for a redraw from every physics tick (`physics_step`, a net state), and
## `queue_redraw` from a tick runs `_draw` in that tick's own message flush -- so at two or three ticks a
## frame the body, the model pose and the decals were painted two or three times for one picture, and a
## slow frame made the next one slower. The tick only raises a flag; `_process` issues ONE redraw per
## drawn frame. (The one-off redraws -- reset, repair, a burst tyre, a layer change -- stay as they are.)
var _redraw_pending: bool = false


func _request_redraw() -> void:
	_redraw_pending = true


func _process(_delta: float) -> void:
	if _redraw_pending:
		_redraw_pending = false
		queue_redraw()


func _draw() -> void:
	var hl := BODY_LENGTH * 0.5
	var hw := BODY_WIDTH * 0.5
	var roll := get_body_roll()
	var pitch := get_body_pitch()
	var height := get_roll_height()
	var shake := get_shake_offset().rotated(-heading)

	# Display attitude. The load transfer a corner can actually reach tops out around 0.5 (and 0.12-0.19
	# over a whole careful race), so the raw values are normalised by their reachable range before they are
	# drawn: at 1:1 screen scale the un-normalised version moved a 36x18 px car by about one pixel and the
	# lean simply could not be seen. During a barrel roll `roll` is already the animation in -1..1.
	var rolling := _roll_state == RollState.ROLLING
	var roll_disp := roll if rolling else _shape_display(roll, roll_visual_reference, roll_visual_curve)
	var pitch_disp := _shape_display(pitch, pitch_visual_reference, pitch_visual_curve)
	# (`roll_disp` / `pitch_disp` are `get_display_roll()` / `get_display_pitch()`, inlined on the hot path.)

	# Drop shadow. The light direction is fixed in SCREEN space, so only that part is rotated into local
	# space; the roll/pitch shift is a body-frame quantity and is added afterwards. (Adding it before the
	# rotation made the same lean produce a sideways shadow at heading 0 and a lengthwise one at heading 90.)
	# It moves against the body, which leans onto its loaded, outside wheels.
	var local_shadow := (Vector2(8, 10) if _on_deck else Vector2(3, 4)).rotated(-heading)
	local_shadow += Vector2(-pitch_disp, roll_disp) * 5.0
	if height > 0.0:
		# Airborne: the car goes over toward `_roll_dir` (+1 = onto its left, i.e. -y), so relative to the
		# body the shadow stays behind on the other side.
		local_shadow += Vector2(2.0, _roll_dir * 26.0) * height
	if _air > 0.0:
		# SPEC 121: airborne on the rope. The shadow slides out behind the car and goes soft, which is
		# what says "off the ground" rather than "closer to the camera".
		local_shadow += Vector2(9.0, 7.0).rotated(-heading) * _air
	var shadow_alpha := (0.45 if _on_deck else 0.3) * lerpf(1.0, 0.55, height) * lerpf(1.0, 0.5, _air)
	var shadow_scale := 1.0 + 0.18 * height
	draw_set_transform(local_shadow, 0.0, Vector2(shadow_scale, shadow_scale))
	draw_colored_polygon(_body_outline(hl + 1.0, hw + 1.0), Color(0, 0, 0, shadow_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Dust puffs behind the car when off track (CarEffects adds the rest; this is the old cue, kept).
	if _off_track:
		var dust := Color(0.55, 0.42, 0.25, 0.45)
		for i in 3:
			var ph := _dust_phase + float(i) * TAU / 3.0
			var back := -hl - 4.0 - fmod(ph, TAU) * 1.6
			var side := sin(ph * 1.7 + float(i)) * hw * 0.8
			draw_circle(Vector2(back, side), 3.0 + fmod(ph, TAU) * 0.6, dust)

	# SPEC 123: a corner running on its hub, whichever way the car is drawn. Struck metal, so the sparks
	# trail BACKWARDS from the hub along the car and flicker with the speed it is going.
	if body_parts_enabled and _body.scraping() and _air <= 0.0:
		var spd := clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0)
		for at in _body.scrape_points():
			var p: Vector2 = at
			for k in 3:
				var ph := _dust_phase * 2.4 + float(k) * 2.1 + p.y
				var back := p + Vector2(-3.0 - fmod(ph, 2.0) * 5.0 * spd, sin(ph) * 2.0)
				draw_circle(back, 1.4 - 0.3 * float(k), Color(1.0, 0.82, 0.35, 0.75 * spd))
	if _model != null:
		_draw_model(roll_disp, pitch_disp, height, rolling, shake)
		# SPEC 90: what has happened to this car, drawn ON it. The model hides a mesh the size of a few
		# pixels when a panel goes and dents by four units -- correct, and invisible from a top-down camera.
		# These decals are the part a player can see: holes where panels were, scratches, scorch.
		_draw_damage_decals(hl, hw)
		_draw_damage_bar()
		return

	# Body attitude: shifted and squashed across the roll / pitch axis — a top-down car leaning onto its
	# outside wheels. During a rollover the y scale sweeps through negative values: that is the barrel roll.
	# `+roll` = loaded on the car's LEFT, which is -y in body space (WHEEL_LOCAL FL = (13, -9)) — so the
	# body shifts to -y. It used to shift to +y, i.e. onto the UNLOADED inside wheels: the car leant into
	# the corner like a motorcycle, and disagreed with its own wheels, which moved the other way.
	# Computed BEFORE the wheels so a barrel roll can carry them with it (21.13).
	var body_offset := Vector2(pitch_disp * pitch_visual_gain, -roll_disp * roll_visual_gain) + shake
	var body_scale := Vector2(1.0 - absf(pitch_disp) * 0.10, 1.0 - absf(roll_disp) * 0.28)
	if rolling:
		body_scale = Vector2(1.0 + 0.10 * height, cos(_roll_phase * PI * _roll_turns))
		if absf(body_scale.y) < 0.06:
			body_scale.y = 0.06 * signf(body_scale.y) if body_scale.y != 0.0 else 0.06
		body_scale *= 1.0 + 0.12 * height

	# Wheels: leaning, sunk toward the body by their suspension compression, fronts pointing along _steer.
	var wheel_col := Color(0.08, 0.08, 0.08)
	for i in WHEEL_COUNT:
		var lw: Vector2 = WHEEL_LOCAL[i]
		var lean: float = _susp.lean(i)
		# A COMPRESSED corner is pulled toward the body (the car squats onto it) and an extended one is
		# pushed out. Clamped, because `bump()` drives a corner to the bump stop (14 px of compression =
		# 17.6 px of raw travel) whenever the car crosses onto the bridge, hits the grass or lands a roll.
		var travel: float = clampf((_susp.compression[i] - susp_rest) * 2.2,
				-WHEEL_TRAVEL_MAX, WHEEL_TRAVEL_MAX)
		# Both terms are expressed as one signed distance TOWARD the body centreline and then bounded, so
		# no combination of roll and bump can throw a wheel clear of the car: a `bump()` extends all four
		# corners at once, and the lean term is one-sided, which used to leave one pair sitting 7.5 px off
		# an 18 px-wide body — four black squares the car had driven out of.
		var side: float = signf(lw.y)
		var inboard := clampf(travel - lean * 4.0 * side, -WHEEL_OUTBOARD_MAX, WHEEL_INBOARD_MAX)
		var wp := lw + Vector2(0.0, -inboard * side) + shake
		var ang := steer_angle() if i < 2 else 0.0
		# A lifted (extended) corner is drawn shorter and narrower — the wheel is coming off the ground.
		var wheel_scale := Vector2(1.0 - absf(lean) * 0.45, 1.0 - maxf(-lean, 0.0) * 0.4)
		if rolling:
			# Mid barrel roll the wheels go over WITH the body; drawn on the ground they read as four
			# black squares the car has left behind.
			wp = body_offset + wp * body_scale
			wheel_scale *= body_scale
		# SPEC 123: what is actually at this corner. A buckled wheel is drawn askew and smaller; a wheel
		# that has come off leaves the hub, which is a bright little disc on the road throwing sparks.
		var corner := _body.state(i) if body_parts_enabled else CarBody.State.INTACT
		if corner == CarBody.State.GONE:
			draw_set_transform(wp, ang, Vector2.ONE)
			draw_circle(Vector2.ZERO, 2.6, Color(0.55, 0.56, 0.60))
			draw_circle(Vector2.ZERO, 1.3, Color(0.22, 0.22, 0.24))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		if corner == CarBody.State.LOOSE:
			ang += 0.34 * signf(lw.y)                  # sitting at an angle on a bent upright
			wheel_scale *= 0.88
		draw_set_transform(wp, ang, wheel_scale)
		draw_rect(Rect2(Vector2(-4.0, -2.2), Vector2(8.0, 4.4)), wheel_col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(body_offset, 0.0, body_scale)

	var paint := body_color.lerp(Color(0.18, 0.16, 0.15), clampf(damage / 100.0, 0.0, 1.0) * 0.45)
	if _off_track:
		paint = paint.lerp(Color(0.55, 0.42, 0.25), 0.45)
	var dark := Color(0.08, 0.08, 0.1)

	# Wings sit under the body so its outline stays on top (Formula car only).
	if body_style == "f1":
		draw_rect(Rect2(Vector2(hl - 1.0, -hw - 3.0), Vector2(4.0, BODY_WIDTH + 6.0)), dark)
		draw_rect(Rect2(Vector2(-hl - 3.0, -hw - 1.0), Vector2(5.0, BODY_WIDTH + 2.0)), dark)

	draw_colored_polygon(_body_outline(hl, hw), paint)

	# Livery stripes.
	match body_style:
		"gt":
			draw_rect(Rect2(Vector2(-hl + 2.0, -4.0), Vector2(BODY_LENGTH - 10.0, 2.2)), stripe_color)
			draw_rect(Rect2(Vector2(-hl + 2.0, 1.8), Vector2(BODY_LENGTH - 10.0, 2.2)), stripe_color)
		"rally":
			draw_rect(Rect2(Vector2(-hl + 2.0, -hw), Vector2(BODY_LENGTH - 8.0, 3.0)), stripe_color)
			draw_rect(Rect2(Vector2(-hl + 2.0, hw - 3.0), Vector2(BODY_LENGTH - 8.0, 3.0)), stripe_color)
			draw_circle(Vector2(-4.0, 0.0), 4.0, Color(1, 1, 1))       # roof number disc
			draw_circle(Vector2(-4.0, 0.0), 4.0, dark, false, 1.0)
		_:
			draw_rect(Rect2(Vector2(-hl + 2.0, -1.5), Vector2(BODY_LENGTH - 10.0, 3.0)), stripe_color)

	var glass := Color(0.12, 0.16, 0.22)
	if body_style == "kart" or body_style == "f1":
		# Open cockpit: the driver's helmet instead of a roof.
		draw_circle(Vector2(-3.0, 0.0), 4.5, glass)
		draw_circle(Vector2(-3.0, 0.0), 3.4, stripe_color if body_style == "f1" else Color(0.95, 0.85, 0.2))
	else:
		# Windshield (front half) and rear window.
		draw_colored_polygon(PackedVector2Array([
			Vector2(2.0, -hw + 3.0), Vector2(8.0, -hw + 4.0), Vector2(8.0, hw - 4.0), Vector2(2.0, hw - 3.0)
		]), glass)
		draw_rect(Rect2(Vector2(-hl + 5.0, -hw + 4.0), Vector2(3.0, BODY_WIDTH - 8.0)), glass)

	# Damage: scorch marks that spread with the damage (fixed spots, so they do not flicker).
	if damage > 15.0:
		var burn := Color(0.08, 0.06, 0.05, clampf((damage - 15.0) / 85.0, 0.0, 1.0) * 0.75)
		var spots := [Vector2(-10, -4), Vector2(6, 5), Vector2(-2, 6), Vector2(11, -5), Vector2(-14, 3)]
		var n := int(clampf(damage / 20.0, 1.0, 5.0))
		for i in n:
			draw_circle(spots[i], 2.5 + 0.03 * damage, burn)

	# Nose triangle (bright yellow) pointing +X.
	draw_colored_polygon(PackedVector2Array([
		Vector2(hl + 5.0, 0.0), Vector2(hl - 4.0, -hw + 2.0), Vector2(hl - 4.0, hw - 2.0)
	]), Color(1.0, 0.85, 0.1))

	# Outline.
	var outline := _body_outline(hl, hw)
	outline.append(outline[0])
	draw_polyline(outline, Color(0.05, 0.05, 0.1), 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_damage_bar()


## Damage bar above the car and the runner tag under it, both screen-aligned.
## SPEC 90: the marks of a fight, in the car's own frame (x forward, y right), over the model.
##   * every panel lost in a zone is a dark HOLE on that side with a bare-metal edge -- the exposed frame;
##   * scratches gather with damage from 30 on;
##   * scorch spreads from the bonnet from 65 on, black by the end.
## Deterministic in the car's own state, so two frames of the same car look the same.
func _draw_damage_decals(hl: float, hw: float) -> void:
	if not damage_enabled or not visible:
		return
	# SPEC 91: baked. The holes, scratches and scorch only change when a panel goes or the damage crosses
	# a band, and rebuilding their geometry every frame for every car was measured at 0.84 ms a frame
	# for four cars -- a fifth of the whole script budget, for something that never moved.
	var key := "%d/%d/%d/%d/%d" % [int(_lost_zone["front"]), int(_lost_zone["rear"]),
			int(_lost_zone["left"]), int(_lost_zone["right"]), int(damage / 6.0)]
	if key != _decal_key:
		_decal_key = key
		_bake_decals(hl, hw)
	if _decal_mesh == null:
		return
	# Perf round: ONE mesh, built when the key changes. It was a polygon, a polyline, a line or a circle
	# per decal -- some thirty commands per damaged car per draw -- for geometry that never moves.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_mesh(_decal_mesh, null)


const DECAL_HOLE := Color(0.08, 0.07, 0.07, 0.92)
const DECAL_METAL := Color(0.70, 0.70, 0.74, 0.85)
const DECAL_SCRATCH := Color(0.1, 0.1, 0.12, 0.75)
var _decal_key: String = ""
## Held for as long as it is drawn: `draw_mesh` records a reference, not a copy.
var _decal_mesh: ArrayMesh = null


## The decal geometry for the car's current state: dark jagged holes per lost zone (up to three each,
## bigger and rougher the more that side has lost, with a bare-metal edge), scratches from 30 damage,
## scorch on the bonnet from 65. Baked into `_decal_mesh` (null when there is nothing to show).
func _bake_decals(hl: float, hw: float) -> void:
	var m := MeshPaint.new()
	var zones := {
		"front": [Vector2(hl - 4.0, 0.0), true],
		"rear": [Vector2(-hl + 4.0, 0.0), true],
		"left": [Vector2(0.0, -hw + 2.5), false],
		"right": [Vector2(0.0, hw - 2.5), false],
	}
	for zone in zones.keys():
		var n := int(_lost_zone.get(zone, 0))
		if n <= 0:
			continue
		var at: Vector2 = zones[zone][0]
		var across: bool = zones[zone][1]
		for k in mini(n, 3):
			var shift := (float(k) - float(mini(n, 3) - 1) * 0.5) * (6.0 if across else 9.0)
			var c := at + (Vector2(0.0, shift) if across else Vector2(shift, 0.0))
			var w := 7.0 + 2.0 * float(k)
			var h := 4.0 + 1.5 * float(k)
			var pts := PackedVector2Array()
			for i in 7:
				var a := TAU * float(i) / 7.0
				var r := Vector2(cos(a) * w * 0.5, sin(a) * h * 0.5)
				var jag := 0.8 + 0.35 * sin(float(i) * 2.3 + float(k) * 1.7 + float(n))
				pts.append(c + r * jag)
			m.add_fan(c, pts, DECAL_HOLE)               # jagged, so a fan from the centre, not a corner
			for e in 3:                                 # the bare-metal edge along four of the points
				m.add_line(pts[e], pts[e + 1], 1.2, DECAL_METAL)
	if damage >= 30.0:
		var scratches := int(clampf((damage - 30.0) / 12.0, 1.0, 6.0))
		for i in scratches:
			var t := float(i) * 1.37 + float(_part_seq) * 0.7
			var sx := sin(t * 3.1) * hl * 0.7
			var sy := cos(t * 2.3) * hw * 0.6
			var d := Vector2(cos(t * 5.0), sin(t * 4.0)).normalized() * (4.0 + 3.0 * absf(sin(t)))
			m.add_line(Vector2(sx, sy) - d, Vector2(sx, sy) + d, 0.8, DECAL_SCRATCH)
	if damage >= 65.0:
		var burn := clampf((damage - 65.0) / 35.0, 0.0, 1.0)
		for i in 3:
			m.add_circle(Vector2(hl * 0.55 - float(i) * 4.0, sin(float(i) * 2.0 + float(_part_seq)) * 3.0),
					4.0 + 3.0 * burn + float(i), Color(0.05, 0.04, 0.04, 0.35 + 0.3 * burn), 10)
	_decal_mesh = m.build()


## How many panels have gone from that side of the car (front / rear / left / right).
func lost_in_zone(zone: String) -> int:
	return int(_lost_zone.get(zone, 0))


func _draw_damage_bar() -> void:
	if tag != "" and visible:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		var font := ThemeDB.fallback_font
		var size := 14
		var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Vector2(-w * 0.5, 34.0)
		draw_string_outline(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
		draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size, body_color.lightened(0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# SPEC 95: the bar over the car is gone -- the damage doll in the corner says it, and says where.
	if show_damage_bar and damage_enabled and damage > 0.5 and not _wrecked:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		var bar := Rect2(Vector2(-18.0, -30.0), Vector2(36.0, 5.0))
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7))
		var f := clampf(damage / 100.0, 0.0, 1.0)
		var col := Color(0.35, 0.9, 0.3).lerp(Color(1.0, 0.8, 0.1), clampf(f * 2.0, 0.0, 1.0)) 				.lerp(Color(1.0, 0.15, 0.1), clampf(f * 2.0 - 1.0, 0.0, 1.0))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## -1..1 display value for a raw load transfer: normalised by `reference` and shaped by `curve` (< 1 lifts
## the small end so a careful line's 0.08 of roll is visible, while the top of the range still spreads).
func _shape_display(value: float, reference: float, curve: float) -> float:
	var n := clampf(absf(value) / maxf(reference, 0.01), 0.0, 1.0)
	if n <= 0.0:
		return 0.0
	return signf(value) * pow(n, maxf(curve, 0.05))


func _body_outline(hl: float, hw: float) -> PackedVector2Array:
	var pts := PackedVector2Array([
		Vector2(-hl, -hw + 2.0), Vector2(-hl + 2.0, -hw), Vector2(hl - 6.0, -hw),
		Vector2(hl, -hw + 4.0), Vector2(hl, hw - 4.0), Vector2(hl - 6.0, hw),
		Vector2(-hl + 2.0, hw), Vector2(-hl, hw - 2.0),
	])
	if not body_parts_enabled:
		return pts
	# SPEC 123: LOCALISED DEFORMATION. Each corner of the outline is pulled toward the middle of the car
	# by however far the bodywork nearest it has been pushed in, so a bent front-left corner is bent at
	# the front left and the other three are untouched. It is the same shape, dented -- not a smaller car
	# and not a different one.
	var out := PackedVector2Array()
	for p in pts:
		var depth := _body.dent_at(p)
		out.append(p if depth <= 0.0 else p - p.normalized() * minf(depth, p.length() * 0.45))
	return out


# ---------------------------------------------------------------- 3D model

func _ensure_model() -> void:
	if _model != null or not use_3d_models or DisplayServer.get_name() == "headless":
		return
	_model = CarModel3D.new()
	_model.name = "Model3D"
	add_child(_model)
	_model.build(body_style, body_color, stripe_color)


## Rebuilds the 3D model for the current livery (CarRegistry.apply calls this after a car change).
func refresh_model() -> void:
	if _model != null:
		_model.build(body_style, body_color, stripe_color)
	queue_redraw()


func has_3d_model() -> bool:
	return _model != null


## Poses the 3D model from the same visual state the 2D body uses.
## SPEC 128: THE DAMAGE, ON THE MODEL. Pushed from `_pose_model`, which every drawn car runs, so one
## path covers all three ways a body changes: a local crash, a remote car rebuilt from `from_bits()`, and
## a reset. It compares the component states against the ones last shown and sends only what moved, so an
## undamaged car -- which is most cars, most of the time -- costs eleven integer compares a frame.
var _shown_body := PackedInt32Array()


func _sync_model_body() -> void:
	if _model == null or not body_parts_enabled:
		return
	if _shown_body.size() != CarBody.PARTS.size():
		_shown_body.resize(CarBody.PARTS.size())
		for i in _shown_body.size():
			_shown_body[i] = -1
	for i in CarBody.PARTS.size():
		var st := _body.state(i)
		if st == _shown_body[i]:
			continue
		_shown_body[i] = st
		if i < CarBody.WHEELS:
			_model.set_wheel_state(i, st)
		else:
			var part: Dictionary = CarBody.PARTS[i]
			_model.set_part_state(String(part["id"]), part["at"] as Vector2, st)


func _pose_model(roll_disp: float, pitch_disp: float, rolling: bool) -> void:
	for wi in WHEEL_COUNT:
		_model.set_tyre_burst(wi, _burst[wi])
	_sync_model_body()
	var offsets := PackedFloat32Array()
	offsets.resize(WHEEL_COUNT)
	for i in WHEEL_COUNT:
		offsets[i] = clampf(_susp.compression[i] - susp_rest, -4.0, 4.0)
	var roll_angle := _roll_phase * PI * _roll_turns * _roll_dir if rolling else 0.0
	_model.pose(heading, 0.0 if rolling else roll_disp, pitch_disp, roll_angle, steer_angle(), offsets,
			_model_distance, damage)
	_model_distance = 0.0
	# SPEC 134: THE PICTURE IS ALWAYS ONE RENDER BEHIND, so a car that stops being drawn keeps the wrong
	# one. The model's viewport renders at the END of the frame, so the texture this `_draw` hands to
	# `draw_texture` is the one from before the pose just above. A moving car is redrawn every frame and
	# never notices. A car HELD ON THE GRID is drawn once, and the picture the player then looks at for
	# the whole countdown is the one rendered before `reset_to` placed it -- the model pointing whichever
	# way it was built, which is east. On a circuit that starts westward the entire field sits on the
	# grid facing backwards and snaps round the instant the lights go green and the redraws resume.
	#
	# One more draw, and only when a render is actually pending. Through `_request_redraw` and never
	# `queue_redraw` -- this runs from inside `_draw`, and asking a node being drawn to draw again
	# re-enters and takes the process down with it (signal 11, reproducibly). The flag is read by
	# `_process`, which is the same rule SPEC 109 set for the physics ticks.
	#
	# SPEC 141: SPEC 134 GOT HALF OF THIS WRONG, and the grid bug came back through the half. It asked
	# "is a render pending?" by reading `render_target_update_mode == UPDATE_ONCE` -- but Godot consumes
	# UPDATE_ONCE inside the renderer and never resets the node's property, so that read is true forever
	# after the first request. Every car redrew itself every frame for its whole life, which hid the
	# real defect in the probe and cost a redraw per car per frame everywhere else. And redrawing did not
	# help anyway: the picture a grid car was stuck on was rendered in the frame the scene was built, a
	# render that does not land, and the model had recorded that pose as shown so it never asked again.
	# `render_pending()` is the model's own bookkeeping: a render requested THIS frame, or the model's
	# settling window after it entered the tree or was rebuilt (`CarModel3D.SETTLE_FRAMES`).
	if _model.render_pending():
		_request_redraw()


## Poses the 3D model from the same visual state the 2D body uses, and paints its texture screen-aligned
## (the model turns inside its own viewport, so the lighting stays fixed on screen).
func _draw_model(roll_disp: float, pitch_disp: float, height: float, rolling: bool, shake: Vector2) -> void:
	_pose_model(roll_disp, pitch_disp, rolling)
	var s := (CarModel3D.VIEW_UNITS / float(CarModel3D.VIEW_PIXELS)) * (1.0 + 0.25 * height)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2(s, s))
	var tex := _model.get_car_texture()
	var half := Vector2(CarModel3D.VIEW_PIXELS, CarModel3D.VIEW_PIXELS) * 0.5
	var world_shake := shake.rotated(rotation) / s
	var tint := Color(0.85, 0.78, 0.68) if _off_track else Color.WHITE
	draw_texture(tex, -half + world_shake - Vector2(0.0, height * 18.0) / s, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- car-to-car contact

## Radius and forward/back offsets of the two circles a car is made of for car-to-car contact.
const CONTACT_RADIUS := 9.5
const CONTACT_OFFSET := 8.5


## The two contact circle centres, in world space.
## SPEC 80: the radius the car actually collides at.
func contact_radius() -> float:
	return CONTACT_RADIUS


## SPEC 122: how far from `position` this car can touch anything -- the far circle's centre plus its
## radius. The two contact resolvers ask this instead of rejecting a pair more than a FIXED distance
## apart before looking at the circles at all.
func contact_reach() -> float:
	return CONTACT_OFFSET + CONTACT_RADIUS


func get_contact_circles() -> PackedVector2Array:
	var f := Vector2.from_angle(heading) * CONTACT_OFFSET
	return PackedVector2Array([position + f, position - f])


## Applied by Race when another car hits this one: `push` separates the two bodies, `dv` is this car's
## share of the collision impulse, `point` is where they touched and `closing` how fast. A hard hit spins
## the car (off-centre impulse), rocks it (side impact -> tilt, which can tip it), shakes it and damages it.
func apply_contact(point: Vector2, push: Vector2, dv: Vector2, closing: float) -> void:
	if not (is_finite(push.x) and is_finite(push.y) and is_finite(dv.x) and is_finite(dv.y)):
		return
	position += push
	if _locked:
		return
	# SPEC 122: any contact at all, damaging or not -- a slide you were shoved out of was not caught.
	_touched_timer = maxf(_touched_timer, clean_exit_hold)
	_contact_ago = 0.0
	velocity += dv
	if _roll_state == RollState.ROLLING or _roll_state == RollState.RECOVERING:
		return
	var r := point - position
	_yaw_rate = clampf(_yaw_rate + r.cross(dv) / maxf(yaw_inertia, 1.0) * 1.6,
			-yaw_rate_max, yaw_rate_max)
	if closing < contact_min_speed:
		return
	# SPEC 122: one dose per `contact_damage_every`, not one per sub-step. Everything above this line --
	# the separation, the impulse, the spin -- still happens every time, because that is what keeps two
	# bodies out of each other; everything below is the CRASH, and a crash is an event.
	if _contact_timer > 0.0:
		return
	_contact_timer = contact_damage_every
	var right := _right_of(Vector2.from_angle(heading))
	var side := dv.dot(right)
	# Shoved sideways, the tires dig in and the body tips over the wheels on the side it is pushed toward.
	_add_tilt_shock(-signf(side) * clampf(absf(side) / 400.0, 0.0, 1.0) * contact_trip)
	_roll_speed_hint = maxf(_frame_speed, velocity.length())
	_roll_entry(0.0)
	_shake_mag = minf(_shake_mag + shake_impulse * clampf(closing / 300.0, 0.0, 1.5), 18.0)
	_bump(clampf(closing * 0.2, 0.0, 80.0))
	_set_stretch(SQUASH_HIT)                      # SPEC 110: a hit squashes the car
	# SPEC 102: what is behind the panel pays only if the panel was already gone; then the panel goes.
	_add_damage_at(point, closing * contact_damage)
	_body_hit(point, closing)
	collided.emit(point, closing)


## The car ran into a loose object on the track (a cone, a tyre stack -- TrackProps, SPEC 41): it loses
## `speed_loss` of its speed, takes `damage`, and a heavy object shakes and nudges it sideways.
## `kick` (SPEC 142) is how hard the thing knocks the car OFF ITS LINE as it goes under a wheel: a
## sideways shove of that many px/s, away from the side the thing was hit on, with a twitch of the nose
## the same way. Nothing for a cone, a twitch for a piece of a wrecked car, a bump for a loose tyre, a
## shove for a tyre stack. It is a VELOCITY the tyres then have to kill, which is what moves the car:
## the stack's old "heavy" kick was 0.8 rad/s of yaw, and the steering assist cancels any yaw inside
## 0.07 s -- measured, it moved the car 0.8 px. 60 px/s sideways moves it 12.
func hit_object(point: Vector2, speed_loss: float, damage_amount: float, kick: float = 0.0) -> void:
	if _locked or not is_finite(point.x):
		return
	velocity *= clampf(1.0 - speed_loss, 0.0, 1.0)
	_add_damage_at(point, damage_amount)         # SPEC 102: a cone cannot reach a vital through a panel
	if kick > 0.0:
		var r := point - position
		var away := Vector2.from_angle(heading).orthogonal()
		if away.dot(r) > 0.0:
			away = -away
		velocity += away * kick
		_yaw_rate = clampf(_yaw_rate + signf(Vector2.from_angle(heading).cross(away)) * kick / 120.0,
				-yaw_rate_max, yaw_rate_max)
		_shake_mag = minf(_shake_mag + shake_impulse * clampf(kick / 180.0, 0.2, 0.6), 18.0)


## SPEC 102: damage nothing on the car stops -- a slam, a blast. Lands where `point` is, goes through.
func punch(point: Vector2, amount: float) -> void:
	_add_damage_at(point, amount, true)


## SPEC 102: fire and the ring. Cooks the engine, then the fuel.
func burn(amount: float) -> void:
	_add_damage(amount)


# ---------------------------------------------------------------- network (multiplayer puppets)

## Index of each field in the state array a car's owner sends to everyone else (Net.send_car_state).
const NET_POS_X := 0
const NET_POS_Y := 1
const NET_HEADING := 2
const NET_FLAGS := 12
const NET_LAPS := 16
const NET_NEXT_CP := 17
## SPEC 123: two bits per component of the body (`CarBody.to_bits`). Gameplay-affecting, so it is
## decided by the machine that owns the car and every other machine draws and simulates what it is told;
## a reconnecting client is handed the current value with the rest of the state, so the car it rebuilds
## has the same panels missing as everybody else's copy.
const NET_BODY := 18
## SPEC 128: HOW MANY FIELDS A CAR'S STATE HAS. `Net.send_car_state()` appends its timestamp AFTER them
## and `NetPuppet` reads it back at this index, so the two must agree -- and they did not: the body bits
## were added at 18 and the puppet went on reading 18 as the clock. Every packet from an undamaged car
## therefore carried a timestamp of zero, which is what the interpolator uses to order and blend states.
## The number lives here, once, and both ends name it.
const NET_FIELDS := 19


## Everything another machine needs to draw this car and rank it: pose, motion, the rollover animation,
## damage, the steered wheels, surface / layer / visibility flags, lean, and lap progress.
func get_net_state(laps_done: int = 0, next_cp: int = 1) -> Array:
	var flags := (1 if _off_track else 0) | (2 if visible else 0) | (4 if _wrecked else 0) 			| (8 if _drifting else 0) | (16 if _on_bridge else 0) | (32 if _on_deck else 0) \
			| (64 if _boost_left > 0.0 else 0) | (128 if _in_band else 0) \
			| (256 if _burst[0] else 0) | (512 if _burst[1] else 0) | (1024 if _burst[2] else 0) \
			| (2048 if _burst[3] else 0) | (4096 if _rope_snapped else 0)
	return [position.x, position.y, heading, velocity.x, velocity.y, _yaw_rate, _roll_state, _roll_phase,
			_roll_dir, _roll_turns, damage, _steer, flags, _drift_intensity, _roll_vis, _pitch_vis,
			laps_done, next_cp, _body.to_bits()]      # NET_FIELDS of them; the stamp goes after


## Draws this car (a PUPPET: never simulated here) as its owner reported it, at the interpolated pose
## `pos` / `head`. `dt` advances the wheel spin.
func apply_net_state(s: Array, pos: Vector2, head: float, dt: float) -> void:
	if s.size() < 18:
		return
	position = pos
	heading = wrapf(head, -PI, PI)
	rotation = heading + body_crab()
	velocity = Vector2(float(s[3]), float(s[4]))
	_yaw_rate = float(s[5])
	_roll_state = int(s[6])
	_roll_phase = float(s[7])
	_roll_dir = float(s[8])
	_roll_turns = float(s[9])
	damage = float(s[10])
	_engine_health = 1.0 - clampf(damage / 100.0, 0.0, 1.0)   # SPEC 102: a puppet's smoke reads the engine
	_steer = float(s[11])
	var flags := int(s[NET_FLAGS])
	_off_track = (flags & 1) != 0
	visible = (flags & 2) != 0
	_wrecked = (flags & 4) != 0
	_drifting = (flags & 8) != 0
	set_bridge_layer((flags & 16) != 0)
	set_bridge_scale((flags & 32) != 0)
	_boost_left = boost_time if (flags & 64) != 0 else 0.0
	_in_band = (flags & 128) != 0
	for i in WHEEL_COUNT:
		_burst[i] = (flags & (256 << i)) != 0
	_rope_snapped = (flags & 4096) != 0
	_drift_intensity = float(s[13])
	_roll_vis = float(s[14])
	_pitch_vis = float(s[15])
	# SPEC 123: an older build sends seventeen fields and no body; its cars are simply undamaged here,
	# which is what they were before this existed.
	if s.size() > NET_BODY:
		_body.from_bits(int(s[NET_BODY]))
	_model_distance += velocity.length() * dt
	_refresh_wheel_pose()
	_request_redraw()
