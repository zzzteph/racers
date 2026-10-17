class_name CarRegistry
extends RefCounted
## The cars the player can choose from. Pure data + static lookups, like TrackRegistry: no scene tree,
## no GameState, so it is usable from `--script` test runs.
##
## Every car is described by four characteristics the player sees on the select screen:
##   * MAX SPEED   -- how fast its wheels can turn (`max_speed`). Ask the rope for more than that and the
##                    car is DRAGGED: it loses grip, wobbles and can flip (`overpull_*`).
##   * SUSPENSION  -- stiffness / damping. Stiff = flat and precise on tarmac, but every bump off the road
##                    goes straight into the chassis. Soft = rolls in the corners, soaks up the rough.
##   * WEIGHT      -- `mass` (longer braking) and `yaw_inertia` (slower to rotate, more stable).
##   * DYNAMICS    -- acceleration, brakes, tire grip and how quickly the nose follows the rope.
## The characteristics are FIXED per car type; the numbers behind them are the `overrides` below, applied
## on top of the shipped Car defaults. Tune a car by editing its entry.

const DEFAULT_ID := "sport"

## Switched on for EVERY car the player drives: over-pull, rough ground, sand, damage. A bare
## `Car.new()` has them all off, which is what the physics tests pin.
const COMMON := {
	"overpull_enabled": true,
	"damage_enabled": true,
	"offroad_rough": 1.0,
	"sand_rough": 1.6,
	# The legacy crawl killed all speed on the grass in ~0.25 s; now a fast car slides a long way on the
	# low grip before the grass stops it -- which is where it gets out of shape and can flip.
	"off_track_slowdown_rate": 3.2,
	"boost_enabled": true,
	"tyres_enabled": true,
	"parts_enabled": true,
	"rope_snap_enabled": true,
	# SPEC 58: the engine, the steering and the suspension each break in their own way.
	"parts_break": true,
	# SPEC 49: the tow behind another car, and rubber that has to be warmed up and then lasts a race.
	"slipstream_enabled": true,
	"clean_exit_enabled": true,        # SPEC 122: catching a long slide is worth saying out loud
	# SPEC 106: "I do not need cold tyres" -- the warm-up is off for every car. The model stays in Car,
	# off, for a car that switches it on.
	"tyre_temp_enabled": false,
}

## Display order. `suspension` and `dynamics` are 1-5 ratings for the select screen; `weight_kg` is the
## display weight (the physics uses `mass`, where 1.0 = 1000 kg).
const CARS := [
	{
		"id": "sport",
		"price": 0,                       # SPEC 56: coins to unlock it (0 = the starter)
		"name": "Sport",
		"description": "The all-rounder. Balanced, forgiving, happy to drift.",
		"good": "Drifting: a held slide fills its boost fastest. The easiest car to drive.",
		"weak": "No stand-out pace on a clean lap: the specialists edge it.",
		"rope": "The standard rope, a fair tension zone. Boosts from drifts and the zone.",
		"style": "sport",
		"body": Color(0.15, 0.42, 0.92),
		"stripe": Color(1, 1, 1, 0.85),
		"suspension": 3, "weight_kg": 1250, "dynamics": 3,
		"overrides": {
			# SPEC 123: the destruction prototype rides on the Sport, and only the Sport. Every other car
			# keeps the zone model until this has been played with.
			"body_parts_enabled": true,
			# Stock handling (every pinned physics test drives it); a little more top speed.
			"max_speed": 600.0,
			# ROPE: the standard rope, a fair tension zone. Charges its boost from drifts and the zone alike.
			"rope_band": 0.10,
			"boost_charge_tension": 0.60,
			"boost_charge_drift": 1.00,
			"boost_time": 1.4,
			"boost_speed": 0.20,
			"boost_accel": 420.0,
		},
	},
	{
		"id": "f1",
		"price": 3200,                       # SPEC 56: coins to unlock it (0 = the starter)
		"name": "Formula",
		"description": "Grip and brakes. Stiff, light, and it hates the grass.",
		"good": "Grip and braking: quick everywhere, best on the flowing circuits.",
		"weak": "The grass (it barely moves off the road) and a slow pull-away.",
		"rope": "A short steel cable: stiff and exact, almost no tension zone.",
		"style": "f1",
		"body": Color(0.86, 0.12, 0.12),
		"stripe": Color(1, 1, 1, 0.9),
		"suspension": 5, "weight_kg": 800, "dynamics": 5,
		"overrides": {
			"max_speed": 650.0,
			"acceleration": 430.0,
			"brake_deceleration": 900.0,
			"tire_peak_accel": 755.0,
			"cornering_stiffness": 2700.0,
			"high_speed_peak_factor": 0.83,      # downforce: keeps its grip at speed
			"mass": 0.8,
			"yaw_inertia": 240.0,
			"susp_stiffness": 400.0,
			"susp_damping": 24.0,
			"off_track_max_speed": 45.0,
			"off_track_grip_factor": 0.35,
			"two_wheel_tilt": 0.90,              # low and wide: hard to tip on tarmac
			# ROPE: a short steel cable -- stiff, precise, and almost no tension zone: ask for a little too
			# much and it drags. Its short, sharp boost comes from holding that knife edge.
			"slack_radius": 20.0,
			"speed_per_px": 2.4,
			"rope_band": 0.03,
			"rope_draw_width": 0.8,
			"boost_charge_tension": 0.60,
			"boost_charge_drift": 0.24,
			"boost_time": 0.9,
			"boost_speed": 0.10,
		},
	},
	{
		"id": "gt",
		"price": 2200,                       # SPEC 56: coins to unlock it (0 = the starter)
		"name": "Grand Tourer",
		"description": "Heavy and powerful. The fastest car there is -- in a straight line.",
		"good": "Top speed, the biggest slingshot boost, and it wins every shove.",
		"weak": "Tail-happy on the power, long braking, lazy turn-in.",
		"rope": "A long bungee: soft, a huge tension zone, the longest boost.",
		"style": "gt",
		"body": Color(0.12, 0.40, 0.26),
		"stripe": Color(0.95, 0.80, 0.25, 0.9),
		"suspension": 2, "weight_kg": 1600, "dynamics": 2,
		"overrides": {
			"max_speed": 730.0,
			"acceleration": 560.0,
			# SPEC 131: 1250 -> 1500. The Grand Tourer is the heavy one, so its braking is already divided
			# by its mass -- and a rope that can no longer brake the car down a straight multiplied that
			# penalty rather than adding to it. It came out 7.2 % off the average pace and six seconds a
			# lap off the road in the hands of a careful driver. Bigger brakes on the heavy car is what a
			# heavy car has.
			"brake_deceleration": 1500.0,
			"tire_peak_accel": 850.0,
			"cornering_stiffness": 2600.0,
			"high_speed_peak_factor": 0.76,
			"mass": 1.6,
			"yaw_inertia": 370.0,
			"steer_lag_time": 0.14,
			"susp_stiffness": 190.0,
			"susp_damping": 14.0,
			# ROPE: a long bungee -- soft and forgiving, a huge tension zone, and the biggest slingshot.
			"slack_radius": 30.0,
			"speed_per_px": 1.85,
			"rope_band": 0.25,
			"rope_draw_width": 1.6,
			"boost_charge_tension": 0.70,
			"boost_charge_drift": 0.20,
			"boost_time": 1.6,
			"boost_speed": 0.25,
			"boost_accel": 520.0,
		},
	},
	{
		"id": "rally",
		"price": 1500,                       # SPEC 56: coins to unlock it (0 = the starter)
		"name": "Rally",
		"description": "Loose on tarmac, at home on grass and sand. Slides long and keeps its speed.",
		"good": "Off the road: grass is just a slower road, and sand barely stops it.",
		"weak": "Loose on tarmac: a perfectly clean lap is not its game.",
		"rope": "A long, slack tow rope you swing it on. Drifts fill its boost.",
		"style": "rally",
		"body": Color(0.95, 0.95, 0.95),
		"stripe": Color(0.10, 0.45, 0.85, 0.95),
		"suspension": 1, "weight_kg": 1200, "dynamics": 3,
		"overrides": {
			"max_speed": 590.0,
			"acceleration": 680.0,
			# SPEC 108: 820 -> 845. With the cold-tyre warm-up gone (SPEC 106) the Rally lost the edge its
			# gravel tyres had while everybody else's were cold, and the hard AI ran it wide on the
			# tight tracks; a little more grip is what those tyres were, and it drives it inside 5 %.
			"tire_peak_accel": 845.0,
			"mass": 1.2,
			"susp_stiffness": 170.0,              # long, soft travel
			"susp_damping": 13.0,
			"off_track_max_speed": 190.0,        # gravel tyres: the grass is a slower road, not a trap
			"off_track_drag": 2.0,
			"off_track_grip_factor": 0.80,
			"sand_max_speed": 170.0,
			"sand_grip_factor": 0.60,
			"offroad_rough": 0.35,
			"sand_rough": 0.6,
			"drift_carry_free": 2.0,             # a held slide keeps its speed for longer
			"drift_carry_floor": 0.80,
			"trip_gain": 0.6,                    # crossing back onto tarmac sideways does not trip it
			"barrier_trip_gain": 0.9,
			"roll_min_speed": 300.0,
			# ROPE: a long, slack tow rope you swing the car on; drifts are what fill its boost.
			"slack_radius": 40.0,
			"speed_per_px": 1.9,
			"rope_band": 0.12,
			"rope_draw_width": 1.2,
			"boost_charge_tension": 0.30,
			"boost_charge_drift": 1.80,
			"boost_time": 1.1,
			"boost_speed": 0.15,
		},
	},
	{
		"id": "kart",
		"price": 800,                       # SPEC 56: coins to unlock it (0 = the starter)
		"name": "Kart",
		"description": "Slow, light and darty. Flicks into any corner, but no suspension at all.",
		"good": "Tight, twisty tracks: it pulls away and brakes like nothing else.",
		"weak": "Top speed, and it loses every shove.",
		"rope": "A short cord: the cursor sits right on the car. Small, quick boosts.",
		"style": "kart",
		"body": Color(0.35, 0.78, 0.22),
		"stripe": Color(0.10, 0.10, 0.10, 0.85),
		"suspension": 5, "weight_kg": 500, "dynamics": 4,
		"overrides": {
			"max_speed": 460.0,
			"acceleration": 590.0,
			"brake_deceleration": 700.0,
			"tire_peak_accel": 870.0,
			"mass": 0.5,
			"yaw_inertia": 170.0,
			"turn_rate": 3.8,
			"susp_stiffness": 450.0,
			"susp_damping": 26.0,
			"two_wheel_tilt": 1.00,
			"roll_min_speed": 330.0,
			# ROPE: a short cord -- the cursor is right on the car, every flick lands. Small, frequent boosts.
			"slack_radius": 14.0,
			"speed_per_px": 2.8,
			"rope_band": 0.08,
			"rope_draw_width": 0.7,
			"boost_charge_tension": 0.50,
			"boost_charge_drift": 1.10,
			"boost_time": 0.8,
			"boost_speed": 0.20,
			"boost_accel": 420.0,
		},
	},
]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CARS:
		out.append(String(c["id"]))
	return out


static func has(id: String) -> bool:
	return not _find(id).is_empty()


static func _find(id: String) -> Dictionary:
	for c in CARS:
		if c["id"] == id:
			return c
	return {}


static func get_entry(id: String) -> Dictionary:
	return _find(resolve(id))


## `id` if it is a known car, else DEFAULT_ID. A stale `selected_car` can never reach a Car.
static func resolve(id: String) -> String:
	return id if has(id) else DEFAULT_ID


static func index_of(id: String) -> int:
	var all := ids()
	for i in all.size():
		if all[i] == id:
			return i
	return 0


static func get_display_name(id: String) -> String:
	return String(get_entry(id)["name"])


static func get_description(id: String) -> String:
	return String(get_entry(id)["description"])


## What this car costs in the garage (SPEC 56). 0 is the starter car, which is never locked.
static func get_price(id: String) -> int:
	return int(get_entry(id).get("price", 0))


static func get_style(id: String) -> String:
	return String(get_entry(id)["style"])


static func get_body_color(id: String, color_index: int = 0) -> Color:
	return get_palette(id)[clampi(color_index, 0, PALETTE_SIZE - 1)]["body"]


static func get_stripe_color(id: String, color_index: int = 0) -> Color:
	return get_palette(id)[clampi(color_index, 0, PALETTE_SIZE - 1)]["stripe"]


## Five liveries per car, generated from its factory colour: the factory livery first, then four more
## spread round the colour wheel at the same saturation / brightness (a white car gets four strong
## colours instead, since white has no hue to turn). Each is {"body", "stripe", "name"}.
const PALETTE_SIZE := 5
const _HUE_STEPS := [0.0, 0.18, 0.36, 0.55, 0.74]
const _PRESETS := [Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.12), Color(0.95, 0.75, 0.1),
		Color(0.85, 0.1, 0.45), Color(0.1, 0.6, 0.7)]


static func get_palette(id: String) -> Array:
	var e := get_entry(id)
	var base: Color = e["body"]
	var stripe: Color = e["stripe"]
	var out: Array = [{"body": base, "stripe": stripe, "name": color_name(base)}]
	for k in range(1, PALETTE_SIZE):
		var body: Color
		if base.s < 0.2:
			body = _PRESETS[k]
		else:
			body = Color.from_hsv(fposmod(base.h + float(_HUE_STEPS[k]), 1.0), maxf(base.s, 0.6),
					clampf(maxf(base.v, 0.55), 0.0, 0.95))
		# Contrast stripe: white on a dark or saturated body, near-black on a light one.
		var light := body.get_luminance() > 0.6
		var st := Color(0.08, 0.08, 0.1, 0.9) if light else Color(1.0, 1.0, 1.0, 0.9)
		out.append({"body": body, "stripe": st, "name": color_name(body)})
	return out


## A plain-English name for a colour ("Red", "Blue", "White" ...).
static func color_name(c: Color) -> String:
	if c.s < 0.2:
		return "White" if c.v > 0.7 else ("Black" if c.v < 0.25 else "Grey")
	var h := c.h * 360.0
	var names := [[15.0, "Red"], [40.0, "Orange"], [65.0, "Yellow"], [95.0, "Lime"], [160.0, "Green"],
			[195.0, "Teal"], [250.0, "Blue"], [285.0, "Purple"], [335.0, "Pink"], [361.0, "Red"]]
	for n in names:
		if h < float(n[0]):
			return String(n[1])
	return "Red"


## The car's own overrides only (not COMMON).
## What the car is good at / weak at, and its rope, for the car screen (SPEC 39).
static func get_good(id: String) -> String:
	return String(get_entry(id).get("good", ""))


static func get_weak(id: String) -> String:
	return String(get_entry(id).get("weak", ""))


static func get_rope_text(id: String) -> String:
	return String(get_entry(id).get("rope", ""))


static func get_overrides(id: String) -> Dictionary:
	return get_entry(id)["overrides"]


## Top speed in px/s (the shipped Car's 580 when the car does not override it).
static func get_max_speed(id: String) -> float:
	return float(get_overrides(id).get("max_speed", 580.0))


## Top speed as the speedometer shows it.
static func get_max_speed_kmh(id: String) -> int:
	return int(round(get_max_speed(id) * Dashboard.KMH_PER_PX))


static func get_suspension(id: String) -> int:
	return int(get_entry(id)["suspension"])


static func get_weight_kg(id: String) -> int:
	return int(get_entry(id)["weight_kg"])


static func get_dynamics(id: String) -> int:
	return int(get_entry(id)["dynamics"])


## Configures `car` as car `id`: the shipped defaults, then COMMON, then the car's own overrides, plus
## its livery. Starts from a fresh Car's values, so applying car A then car B leaves nothing of A behind.
static func apply(car: Car, id: String, color_index: int = 0) -> void:
	if car == null:
		return
	var rid := resolve(id)
	var fresh := Car.new()
	for key in COMMON.keys():
		car.set(key, fresh.get(key))
	for c in CARS:
		for key in c["overrides"].keys():
			car.set(key, fresh.get(key))
	fresh.free()
	for key in COMMON.keys():
		car.set(key, COMMON[key])
	var overrides := get_overrides(rid)
	for key in overrides.keys():
		car.set(key, overrides[key])
	car.car_id = rid
	car.body_color = get_body_color(rid, color_index)
	car.stripe_color = get_stripe_color(rid, color_index)
	car.body_style = get_style(rid)
	car.refresh_model()
