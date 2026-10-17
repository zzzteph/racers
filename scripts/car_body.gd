class_name CarBody
extends RefCounted
## PROGRESSIVE DESTRUCTION, COMPONENT BY COMPONENT (SPEC 123). The car already lost panels by ZONE --
## four counters, front/rear/left/right, each just a number of pieces gone -- which is enough to draw
## holes and to decide whether a vital is exposed, and not enough for anything to look or drive like it
## has been in a crash. A front corner that has been hit twice looked exactly like a rear corner that
## had been hit twice, and neither changed how the car drove except through a grip multiplier applied
## to a whole axle.
##
## This is the same idea with the parts named. Eleven components, each with:
##
##   * a PLACE on the car (car-local, x forward, y right) and a size,
##   * a STRENGTH -- how much punishment it absorbs before it moves on a state,
##   * a MASS, which is what it takes with it when it leaves,
##   * and a state: INTACT -> DENTED -> LOOSE -> GONE.
##
## A hit does not pick one component. It spreads over everything near where it landed, in proportion to
## how near -- so a front-corner crash bends the wing (weak) long before it buckles the wheel (strong),
## and a second one in the same place takes the wheel off. That is the whole mechanic: the damage is
## where the crash was, and what breaks is whatever was weakest there.
##
## WHAT BREAKS IS WHAT CHANGES. Every consequence below is read from the component states by the car's
## own physics, so the handling always matches the picture:
##
##   * a LOOSE wheel has most of its grip and pulls; a GONE one is a hub on the road -- almost no grip,
##     a lot of drag, sparks, and a hard pull to that side;
##   * a bent wing rubs its tyre (a little grip, a little drag on that corner);
##   * a missing bumper stops protecting the end behind it, which is what `armour` already meant;
##   * a missing bonnet is an open engine bay: more drag, and the engine is exposed.
##
## Pure: no scene tree, no autoloads, no signals, no drawing. `Car` owns one of these, feeds it hits and
## reads the consequences; the suite can drive it directly. `to_bits()` puts the whole state in one int
## for the network.

enum State { INTACT, DENTED, LOOSE, GONE }

## The four wheels come first and in `Car.WHEEL_LOCAL` order, so a wheel's component index IS its wheel
## index and nothing has to map between them.
const WHEEL_FL := 0
const WHEEL_FR := 1
const WHEEL_RL := 2
const WHEEL_RR := 3
const WHEELS := 4

## `strength` is in the same units as the load below: roughly px/s of closing speed absorbed per state.
## A wheel is much stronger than the wing over it, which is what makes the wing the first thing to go in
## any corner shunt and the wheel the thing a really hard one takes.
const PARTS := [
	{"id": "wheel_fl", "at": Vector2(13, -9), "reach": 8.0, "strength": 330.0, "mass": 0.055, "kind": "wheel"},
	{"id": "wheel_fr", "at": Vector2(13, 9), "reach": 8.0, "strength": 330.0, "mass": 0.055, "kind": "wheel"},
	{"id": "wheel_rl", "at": Vector2(-13, -9), "reach": 8.0, "strength": 330.0, "mass": 0.055, "kind": "wheel"},
	{"id": "wheel_rr", "at": Vector2(-13, 9), "reach": 8.0, "strength": 330.0, "mass": 0.055, "kind": "wheel"},
	{"id": "bumper_front", "at": Vector2(17, 0), "reach": 10.0, "strength": 130.0, "mass": 0.030, "kind": "bumper"},
	{"id": "bumper_rear", "at": Vector2(-17, 0), "reach": 10.0, "strength": 130.0, "mass": 0.030, "kind": "bumper"},
	{"id": "bonnet", "at": Vector2(8, 0), "reach": 9.0, "strength": 200.0, "mass": 0.045, "kind": "bonnet"},
	{"id": "wing_fl", "at": Vector2(11, -8), "reach": 8.0, "strength": 190.0, "mass": 0.035, "kind": "wing"},
	{"id": "wing_fr", "at": Vector2(11, 8), "reach": 8.0, "strength": 190.0, "mass": 0.035, "kind": "wing"},
	{"id": "wing_rl", "at": Vector2(-11, -8), "reach": 8.0, "strength": 200.0, "mass": 0.035, "kind": "wing"},
	{"id": "wing_rr", "at": Vector2(-11, 8), "reach": 8.0, "strength": 200.0, "mass": 0.035, "kind": "wing"},
	# SPEC 128: WHAT IS UNDER THE SKIN. Everything above is bodywork -- it bends, it comes off, it makes
	# debris. These four do none of that: they are the car's own organs, they stay where they are, and
	# what they do when they break is change how it drives rather than how it looks. Each sits behind a
	# `cover`, so a blow only reaches it through whatever panel is in the way (`shield`) -- which is what
	# makes bodywork worth having even though it never stops a hit outright.
	#
	# `mass` is 0 for all of them: they are still bolted to the car however broken they are, so nothing
	# comes off and the car does not get lighter.
	{"id": "radiator", "at": Vector2(14, 0), "reach": 7.0, "strength": 150.0, "mass": 0.0,
			"kind": "radiator", "inner": true, "cover": "bumper_front"},
	{"id": "drivetrain", "at": Vector2(-6, 0), "reach": 9.0, "strength": 420.0, "mass": 0.0,
			"kind": "drivetrain", "inner": true, "cover": "bumper_rear"},
	{"id": "chassis", "at": Vector2(0, 0), "reach": 16.0, "strength": 900.0, "mass": 0.0,
			"kind": "chassis", "inner": true, "cover": ""},
	{"id": "rope_mount", "at": Vector2(18, 0), "reach": 6.0, "strength": 260.0, "mass": 0.0,
			"kind": "rope_mount", "inner": true, "cover": "bumper_front"},
]
## How far past its own `reach` a component still feels a hit, in px. Without it a blow that lands
## exactly between two panels moves neither, which is not how metal works.
const SPREAD := 9.0
## The load, as a multiple of `strength`, at which a component reaches each state. A component that
## reaches GONE detaches; a wheel skips DENTED (a wheel is round or it is not).
const DENT_AT := 1.0
const LOOSE_AT := 2.4
const GONE_AT := 4.0
## A wheel has no dented state, so it would otherwise sit in LOOSE across three quarters of the ladder.
## Measured against the acceptance scenario with `tools/probe_destruction.gd`: one corner crash at
## 260 px/s bends the wing and leaves the wheel round, a second buckles it, a third takes it off.
const WHEEL_GONE_AT := 3.0
## A component is never moved by a hit gentler than this (px/s of closing): parking against a wall is
## not a crash.
const MIN_CLOSING := 60.0

## What each state does to the wheel it belongs to: how much of its grip is left, and how much extra
## rolling drag it adds. A GONE wheel is a hub dragging on the road.
const WHEEL_GRIP := [1.0, 1.0, 0.55, 0.10]
const WHEEL_DRAG := [0.0, 0.0, 0.18, 0.62]
## ... and a bent wing rubs the tyre inside it.
const WING_GRIP := [1.0, 0.94, 0.86, 0.90]
## Body drag added by an open bay or a missing bumper, as a fraction of the car's own.
const HOLE_DRAG := 0.06

## One entry per `PARTS` row: the punishment it has taken, in `strength` units. Write it with
## `set_load()` rather than assigning it, so the cached consequences below are rebuilt with it.
var load: PackedFloat32Array = PackedFloat32Array()
## SPEC 128: THE CONSEQUENCES, WORKED OUT ONCE PER CRASH INSTEAD OF ONCE PER FRAME. Every query below
## walks `PARTS` -- some of them twice, with a string lookup per wheel -- and the car asks for eight of
## them every sub-step. The state only changes when something breaks, so they are computed when it does.
var _c_drag: float = 0.0
var _c_pull: float = 0.0
var _c_toe: float = 0.0
var _c_flap: float = 0.0
var _c_crab: float = 0.0
var _c_leak: float = 0.0
var _c_drive: float = 0.0
var _c_mount: float = 0.0
var _c_mass: float = 0.0
var _c_gone: int = 0
var _c_scraping: bool = false
var _c_grip := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _c_sag := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _c_rub := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _c_wheel_drag := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _init() -> void:
	reset()


func reset() -> void:
	load = PackedFloat32Array()
	load.resize(PARTS.size())
	for i in load.size():
		load[i] = 0.0
	_recompute()


## The only way to set the punishment directly (the suite and the probes): it rebuilds the consequences.
func set_load(v: PackedFloat32Array) -> void:
	load = v
	_recompute()


## Everything the car asks for every frame, worked out from the states, once.
func _recompute() -> void:
	_c_drag = 0.0
	_c_toe = 0.0
	_c_mass = 0.0
	_c_gone = 0
	_c_scraping = false
	var left_drag := 0.0
	var right_drag := 0.0
	for i in WHEELS:
		var st := state(i)
		var wd: float = float(WHEEL_DRAG[st])
		_c_wheel_drag[i] = wd
		_c_drag += wd
		if (PARTS[i]["at"] as Vector2).y < 0.0:
			left_drag += wd
		else:
			right_drag += wd
		if st == State.GONE:
			_c_scraping = true
		var wing := index_of(String(WING_ID[i]))
		var wing_st := state(wing) if wing >= 0 else State.INTACT
		_c_grip[i] = float(WHEEL_GRIP[st]) * float(WING_GRIP[wing_st])
		_c_sag[i] = maxf(float(SAG_AT[st]), 0.25 if wing_st >= State.LOOSE else 0.0)
		_c_rub[i] = 0.0 if st == State.GONE else float(RUB_AT[wing_st])
		var bite: float = float(TOE_AT[st]) * (TOE_FRONT if i < 2 else TOE_REAR)
		_c_toe += -bite if (PARTS[i]["at"] as Vector2).y < 0.0 else bite
	_c_toe = clampf(_c_toe, -1.0, 1.0)
	_c_pull = clampf(right_drag - left_drag, -1.0, 1.0)
	for id in ["bumper_front", "bumper_rear", "bonnet"]:
		if state_of(String(id)) >= State.LOOSE:
			_c_drag += HOLE_DRAG
	var panels := 0.0
	var loose := 0.0
	var side_left := 0.0
	var side_right := 0.0
	for i in PARTS.size():
		var st := state(i)
		if st == State.GONE:
			_c_gone += 1
			_c_mass += float(PARTS[i]["mass"])
		if bool(PARTS[i].get("inner", false)) or String(PARTS[i]["kind"]) == "wheel":
			if String(PARTS[i]["kind"]) == "wheel":
				if (PARTS[i]["at"] as Vector2).y < 0.0:
					side_left += load[i]
				else:
					side_right += load[i]
			continue
		panels += 1.0
		if st == State.LOOSE:
			loose += 1.0
		elif st == State.DENTED:
			loose += 0.35
		if (PARTS[i]["at"] as Vector2).y < 0.0:
			side_left += load[i]
		elif (PARTS[i]["at"] as Vector2).y > 0.0:
			side_right += load[i]
	_c_flap = clampf(loose / maxf(panels, 1.0), 0.0, 1.0)
	_c_leak = float(LEAK_AT[state_of("radiator")])
	_c_drive = float(DRIVE_AT[state_of("drivetrain")])
	_c_mount = float(MOUNT_AT[state_of("rope_mount")])
	# Which way a bent chassis is bent is decided by the car, not by chance: whichever side has taken more.
	_c_crab = float(CRAB_AT[state_of("chassis")]) * (1.0 if side_right >= side_left else -1.0)


## The state of component `i`.
func state(i: int) -> int:
	if i < 0 or i >= load.size():
		return State.INTACT
	var l := load[i]
	var wheel := String(PARTS[i]["kind"]) == "wheel"
	if l >= (WHEEL_GONE_AT if wheel else GONE_AT):
		return State.GONE
	if l >= LOOSE_AT:
		return State.LOOSE
	if l >= DENT_AT:
		# A wheel has no dented state: it is round or it is buckled.
		return State.LOOSE if wheel else State.DENTED
	return State.INTACT


func state_of(id: String) -> int:
	return state(index_of(id))


## SPEC 128: built once, for the whole class. This used to be a scan over `PARTS` comparing STRINGS, and
## the consequence queries below call it per wheel, per sub-step, per car -- which is fifteen string
## compares times four wheels times two sub-steps times eight cars, every frame, to look up four numbers
## that never change.
static var _by_id: Dictionary = {}
static func index_of(id: String) -> int:
	if _by_id.is_empty():
		for i in PARTS.size():
			_by_id[String(PARTS[i]["id"])] = i
	return int(_by_id.get(id, -1))


## Which wing sits over each wheel, in wheel order.
const WING_ID := ["wing_fl", "wing_fr", "wing_rl", "wing_rr"]


## A BLOW. `local` is where it landed in the car's own frame (x forward, y right, in px); `closing` is
## the normal closing speed in px/s; `heft` scales it for the mass behind the hit -- 1.0 for an
## equal-weight car, more for something heavier, less for a cone.
##
## Returns the components whose state CHANGED, each as {"index", "id", "from", "to", "at", "mass"} --
## the car turns those into debris, sounds and exposed vitals. Empty for a blow that moved nothing,
## which is most of them.
func hit(local: Vector2, closing: float, heft: float = 1.0) -> Array:
	var changed: Array = []
	if not (closing >= MIN_CLOSING) or not is_finite(closing) or not is_finite(local.x):
		return changed
	var force := closing * maxf(heft, 0.0)
	for i in PARTS.size():
		var part: Dictionary = PARTS[i]
		var dist := local.distance_to(part["at"] as Vector2)
		var span: float = float(part["reach"]) + SPREAD
		if dist >= span:
			continue
		# Right on the part takes all of it; the edge of its span takes none. Squared, so a blow is felt
		# by the thing it actually landed on far more than by its neighbours.
		var share := 1.0 - dist / span
		share *= share
		# SPEC 128: what is UNDER a panel feels only what the panel lets through. `shield` is already the
		# rule for the vitals; this is the same rule for the components behind the same bodywork, so a
		# car with its nose still on protects its radiator, and one that has lost the nose does not.
		if bool(part.get("inner", false)):
			var cover := String(part.get("cover", ""))
			share *= _through(cover) if cover != "" else 1.0
		var before := state(i)
		var cap: float = WHEEL_GONE_AT if String(part["kind"]) == "wheel" else GONE_AT
		load[i] = minf(load[i] + force * share / maxf(float(part["strength"]), 1.0), cap)
		var after := state(i)
		if after != before:
			changed.append({"index": i, "id": String(part["id"]), "from": before, "to": after,
					"at": part["at"] as Vector2, "mass": float(part["mass"]),
					"kind": String(part["kind"])})
	if not changed.is_empty():
		_recompute()
	return changed


## How much of a blow gets past the panel `cover`, 0..1. An intact panel takes most of it; one that has
## been knocked off takes none.
func _through(cover: String) -> float:
	return float([0.35, 0.55, 0.80, 1.0][state_of(cover)]) if index_of(cover) >= 0 else 1.0


## Everything still attached comes off: the wreck.
func scatter() -> Array:
	var out: Array = []
	for i in PARTS.size():
		if state(i) == State.GONE or bool(PARTS[i].get("inner", false)):
			continue                  # SPEC 128: the engine bay does not fly off; it is just wrecked
		var before := state(i)
		load[i] = WHEEL_GONE_AT if String(PARTS[i]["kind"]) == "wheel" else GONE_AT
		out.append({"index": i, "id": String(PARTS[i]["id"]), "from": before, "to": State.GONE,
				"at": PARTS[i]["at"] as Vector2, "mass": float(PARTS[i]["mass"]),
				"kind": String(PARTS[i]["kind"])})
	_recompute()
	return out


# ---------------------------------------------------------------- what it does to the driving

## How much of wheel `i`'s grip is left: its own state, and the wing over it rubbing.
func wheel_grip(i: int) -> float:
	return _c_grip[i] if i >= 0 and i < WHEELS else 1.0


## Extra rolling resistance from this wheel, as a fraction of the car's drive. A hub on the road is most
## of it.
func wheel_drag(i: int) -> float:
	return _c_wheel_drag[i] if i >= 0 and i < WHEELS else 0.0


## The whole car's extra drag: the wheels that are not wheels any more, plus the holes in the bodywork.
func drag() -> float:
	return _c_drag


## Which way the car pulls, -1 (left) to +1 (right), from wheels that are dragging on one side. A hub on
## the left corner hauls the car left, hard.
func pull() -> float:
	return _c_pull


## SPEC 128: BENT WHEEL ALIGNMENT. A buckled wheel does not sit straight, so the car tracks off-line even
## with the rope dead ahead -- and that is a different thing from the DRAG of a hub, which is what `pull`
## already measured. A front corner matters most, because that is the end that steers. -1 pulls left,
## +1 right; a buckled front-left wheel drags its own corner back, which pulls the nose LEFT.
const TOE_FRONT := 0.55
const TOE_REAR := 0.25
const TOE_AT := [0.0, 0.0, 1.0, 0.7]     # a hub has less bite than a buckled wheel, so it steers less
func toe() -> float:
	return _c_toe


## SPEC 128: A COLLAPSED SUSPENSION CORNER, 0..1 -- how far the spring at corner `i` has given up. The
## corner sits down on its stop, so it cannot absorb anything: over a kerb or a landing it bottoms out
## instead of soaking it up, and the weight that should be spread over four corners is on three.
const SAG_AT := [0.0, 0.0, 0.45, 1.0]
func susp_sag(i: int) -> float:
	return _c_sag[i] if i >= 0 and i < WHEELS else 0.0


## SPEC 128: LOOSE BODYWORK, 0..1 -- how much of the car is hanging off it rather than bolted to it. A
## flapping panel is not a hole: it is still there, and it rattles, catches the air and drags.
const FLAP_DRAG := 0.05
func flap() -> float:
	return _c_flap


## SPEC 128: TYRE RUBBING, 0..1 -- a bent wing sitting on the tyre under it. It already costs grip
## (`wheel_grip`); this is the other half, which is that rubber against bodywork does not last.
const RUB_AT := [0.0, 0.5, 1.0, 0.0]     # a wing that has gone is not rubbing anything
func rub(i: int) -> float:
	return _c_rub[i] if i >= 0 and i < WHEELS else 0.0


## SPEC 128: A COOLING LEAK, 0..1 -- a holed radiator. Nothing happens the moment it goes; what happens
## is that the engine can no longer shed the heat it makes, so a long stretch at full throttle cooks it
## and the power fades until the driver backs off. `Car` owns the heat; this is how fast it builds.
const LEAK_AT := [0.0, 0.35, 0.7, 1.0]
func cooling_leak() -> float:
	return _c_leak


## SPEC 128: A HURT DRIVETRAIN, 0..1 -- how much of the car's top end has gone. A bent shaft still turns;
## it just will not pull the last of the gears.
const DRIVE_AT := [0.0, 0.10, 0.25, 0.45]
func drivetrain_loss() -> float:
	return _c_drive


## SPEC 128: A BENT CHASSIS, in radians. The car no longer points where it goes: the wheels are square
## to a frame that is not square any more, so it CRABS -- it drives down the road slightly sideways, and
## the driver has to hold a permanent correction. The one damage a driver feels on every straight.
const CRAB_AT := [0.0, 0.035, 0.08, 0.14]
func crab() -> float:
	return _c_crab


## SPEC 128: A DAMAGED ROPE ATTACHMENT, 0..1 -- the mount the rope pulls the whole car by. It is the one
## component that damages the CONTROL rather than the car: a bent mount cannot take the strain, so the
## rope frays sooner, and a torn-out one slips, so hauling on it is answered late and loosely.
const MOUNT_AT := [0.0, 0.2, 0.5, 0.85]
func rope_mount_damage() -> float:
	return _c_mount


## True while any corner is running on its hub: the car scrapes, throws sparks and makes a noise.
func scraping() -> bool:
	return _c_scraping


## Which corners are on the hub, as world-frame-agnostic local points -- where the sparks come from.
func scrape_points() -> Array:
	var out: Array = []
	for i in WHEELS:
		if state(i) == State.GONE:
			out.append(PARTS[i]["at"] as Vector2)
	return out


## SPEC 123: the bodywork ABSORBS and TRANSMITS rather than granting extra lives. A blow landing on an
## end whose bumper is gone reaches what is behind it in full; while the bumper is there it takes this
## share of it. (The old zone `armour` was binary: a panel was there, so the vital could not be hit at
## all, which made bodywork a stack of hit points.)
func shield(local: Vector2) -> float:
	var id := "bumper_front" if local.x >= 0.0 else "bumper_rear"
	var through := [0.35, 0.55, 0.80, 1.0]
	var s: float = float(through[state_of(id)])
	if local.x >= 0.0 and state_of("bonnet") >= State.LOOSE:
		s = maxf(s, 0.85)                 # an open bay is no protection at all
	return s


## SPEC 123: how far the bodywork is pushed IN at this point on the outline, in px. The outline the car
## draws asks this for every vertex, so a bent corner is bent where it was hit and nowhere else.
func dent_at(local: Vector2) -> float:
	var worst := 0.0
	for i in PARTS.size():
		if String(PARTS[i]["kind"]) == "wheel" or bool(PARTS[i].get("inner", false)):
			continue                  # SPEC 128: a bent radiator does not change the car's outline
		var s := state(i)
		if s == State.INTACT:
			continue
		var dist := local.distance_to(PARTS[i]["at"] as Vector2)
		var span: float = float(PARTS[i]["reach"]) + SPREAD
		if dist >= span:
			continue
		var depth: float = float([0.0, 2.6, 4.4, 6.0][s]) * (1.0 - dist / span)
		worst = maxf(worst, depth)
	return worst


## How many components have gone, and how badly the car is knocked about overall (0..1) -- for the AI's
## caution, the results card and the tests.
## SPEC 128: how much of the car is no longer on it, as a fraction of its whole mass. Every component
## has carried a `mass` since SPEC 123 and nothing read it -- the car got lighter by a flat amount per
## PANEL and a wheel leaving changed nothing, so losing a wheel and losing a mirror weighed the same.
func mass_lost() -> float:
	return _c_mass


func gone_count() -> int:
	return _c_gone


func wear() -> float:
	var total := 0.0
	var most := 0.0
	for i in load.size():
		total += load[i]
		most += WHEEL_GONE_AT if String(PARTS[i]["kind"]) == "wheel" else GONE_AT
	return clampf(total / maxf(most, 1.0), 0.0, 1.0)


# ---------------------------------------------------------------- the network

## Two bits per component, in `PARTS` order: the whole body in one int (22 bits for eleven parts).
func to_bits() -> int:
	var bits := 0
	for i in PARTS.size():
		bits |= (state(i) & 3) << (i * 2)
	return bits


func from_bits(bits: int) -> void:
	for i in PARTS.size():
		var s := (bits >> (i * 2)) & 3
		var top: float = WHEEL_GONE_AT if String(PARTS[i]["kind"]) == "wheel" else GONE_AT
		load[i] = float([0.0, DENT_AT, LOOSE_AT, top][s])
	_recompute()
