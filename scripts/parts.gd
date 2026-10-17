class_name Parts
extends RefCounted
## The parts you can fit (SPEC 61). Not a ladder -- a choice. Every part is better than stock at ONE
## thing and worse at another, so there is no perfect car: there is a car set up for this track, this
## race length and the way you drive.
##
## The only parts that are a straight gain are the "light" ones, and they give +5 % at the price of
## breaking sooner -- a bet that you will not hit anything.
##
## Each entry: `id`, `name`, `price` (0 = the stock part, always fitted and always free), `good` and
## `bad` (one line each, shown in the garage) and `set` -- multipliers applied to the car's own numbers.
## Stock parts have an empty `set`, so a stock car is exactly the car SPEC 38 tuned.
##
## Pure data + one `apply()`. No scene tree, no GameState.

## SPEC 137: "charge" is the explosive. Stock is what every car leaves the factory with -- enough to
## write itself off and mark the paint of anything touching it -- and the three you can buy trade reach
## against bite against what the car is like to drive around with a bomb in it.
const SLOTS := ["engine", "wheels", "suspension", "body", "rope", "charge"]

const CATALOGUE := {
	"engine": [
		{"id": "stock_engine", "name": "Stock engine", "price": 0,
			"good": "Nothing to learn.", "bad": "Nothing special either.", "set": {}},
		{"id": "turbo", "name": "Turbo", "price": 900,
			"good": "+14 % top speed: it flies down a long straight.",
			"bad": "-18 % drive off a corner -- it has to be kept on the boil.",
			"set": {"max_speed": 1.14, "acceleration": 0.82, "engine_fragility": 1.15}},
		{"id": "torque", "name": "Torque motor", "price": 800,
			"good": "+20 % drive: it fires out of slow corners.",
			"bad": "-6 % top speed, and it is heavy.",
			"set": {"acceleration": 1.20, "max_speed": 0.94, "mass": 1.05, "yaw_inertia": 1.05}},
		{"id": "light_engine", "name": "Lightweight engine", "price": 700,
			"good": "+5 % everywhere, and 8 % lighter.",
			"bad": "Fragile: it takes half again as much from every hit.",
			"set": {"max_speed": 1.05, "acceleration": 1.05, "mass": 0.92, "yaw_inertia": 0.93,
				"engine_fragility": 1.5}},
	],
	"wheels": [
		{"id": "stock_wheels", "name": "Stock tyres", "price": 0,
			"good": "Even on everything.", "bad": "Best at nothing.", "set": {}},
		{"id": "slicks", "name": "Slicks", "price": 850,
			"good": "+16 % grip on tarmac: later braking, faster corners.",
			"bad": "Wear twice as fast, and they are useless the moment you leave the road.",
			"set": {"tire_peak_accel": 1.16, "tyre_wear_overpull": 2.0, "tyre_wear_scrub": 2.0,
				"tyre_wear_grass": 2.0, "off_track_grip_factor": 0.65, "tyre_cold_grip": 0.86}},
		{"id": "gravel", "name": "All-terrain", "price": 750,
			"good": "+70 % grip off the road: the grass and the sand stop being a wall.",
			"bad": "-9 % grip on tarmac, where most of the lap is.",
			"set": {"off_track_grip_factor": 1.7, "sand_grip_factor": 1.7, "tire_peak_accel": 0.91,
				"off_track_max_speed": 1.35, "tyre_wear_grass": 0.5, "tyre_wear_sand": 0.5}},
		{"id": "hard", "name": "Hard compound", "price": 600,
			"good": "Wears a third as fast: a ten-lap race on one set.",
			"bad": "-6 % grip, and slow to come up to temperature.",
			"set": {"tyre_wear_overpull": 0.35, "tyre_wear_scrub": 0.35, "tyre_wear_hit": 0.5,
				"tire_peak_accel": 0.94, "tyre_warm_time": 1.6}},
	],
	"suspension": [
		{"id": "stock_susp", "name": "Stock springs", "price": 0,
			"good": "Forgiving.", "bad": "Vague when you lean on it.", "set": {}},
		{"id": "stiff", "name": "Stiff race springs", "price": 800,
			"good": "The body stays flat: sharper turn-in and a steadier rope.",
			"bad": "Skips over rough ground and lands badly -- kerbs and grass hurt.",
			"set": {"susp_stiffness": 1.30, "susp_damping": 1.15, "offroad_rough": 1.5,
				"sand_rough": 1.5, "susp_rough_damage": 1.4}},
		{"id": "soft", "name": "Long-travel springs", "price": 650,
			"good": "Soaks up rough ground and landings; you can use the grass.",
			"bad": "Rolls in the corners, and rolls over more easily.",
			"set": {"susp_stiffness": 0.78, "susp_damping": 0.92, "offroad_rough": 0.55,
				"sand_rough": 0.6, "two_wheel_tilt": 0.88}},
	],
	"body": [
		{"id": "stock_body", "name": "Stock shell", "price": 0,
			"good": "As it left the factory.", "bad": "As it left the factory.", "set": {}},
		{"id": "cage", "name": "Roll cage", "price": 900,
			"good": "-35 % damage from every hit, and the panels stay on.",
			"bad": "Heavy: slower to get going and slower to change direction.",
			"set": {"damage_per_impact": 0.65, "part_min_hit": 1.4, "mass": 1.12, "yaw_inertia": 1.15,
				"acceleration": 0.95}},
		{"id": "stripped", "name": "Stripped shell", "price": 700,
			"good": "14 % lighter: quicker off the mark and quick to turn.",
			"bad": "Everything hurts it -- 40 % more damage, and pieces come off early.",
			"set": {"mass": 0.86, "yaw_inertia": 0.85, "acceleration": 1.06,
				"damage_per_impact": 1.4, "part_min_hit": 0.7}},
	],
	"rope": [
		{"id": "stock_rope", "name": "Stock rope", "price": 0,
			"good": "The rope you learned on.", "bad": "", "set": {}},
		{"id": "short_rope", "name": "Short rope", "price": 750,
			"good": "Answers instantly, and it is far harder to over-pull.",
			"bad": "A narrow tension zone: holding the boost takes a steady hand.",
			"set": {"speed_per_px": 1.35, "slack_radius": 0.7, "rope_band": 0.6,
				"rope_strain_rate": 0.7}},
		{"id": "long_rope", "name": "Elastic rope", "price": 750,
			"good": "A wide tension zone: the boost charges from a rough cursor.",
			"bad": "Slow to answer, and it drags the car if you pull too far.",
			"set": {"speed_per_px": 0.78, "slack_radius": 1.3, "rope_band": 1.6,
				"rope_strain_rate": 1.3, "overpull_drag": 1.2}},
	],
	# SPEC 137: what happens when the car is written off -- by the F key, or by the last hit its tank
	# takes. Every one of these is a bet on being close to somebody when it happens.
	"charge": [
		{"id": "stock_charge", "name": "Stock tank", "price": 0,
			"good": "Goes off about a car's width.", "bad": "Nobody is frightened of it.", "set": {}},
		{"id": "wide_charge", "name": "Scatter charge", "price": 800,
			"good": "Two and a half times the reach: it catches a whole group.",
			"bad": "Spread thin -- half the bite, and nothing at the rim.",
			"set": {"blast_cars": 2.5, "blast_damage": 0.5, "blast_shove": 1.25}},
		{"id": "shaped_charge", "name": "Shaped charge", "price": 850,
			"good": "Twice the bite at point-blank: it can end somebody outright.",
			"bad": "Barely reaches past the bodywork -- you have to be touching them.",
			"set": {"blast_cars": 0.55, "blast_damage": 2.3, "blast_shove": 0.8}},
		{"id": "armed_charge", "name": "Armed tank", "price": 700,
			"good": "Half again the reach and the bite, and it shoves hard.",
			"bad": "Live the whole race: the tank itself is far easier to set off.",
			"set": {"blast_cars": 1.5, "blast_damage": 1.5, "blast_shove": 1.5,
				"tank_fragility": 1.6}},
	],
}


## Ready-made setups (SPEC 64): the four ways this car can be built, so a player who does not want to
## read five slot descriptions can fit "Sprint" and go racing. Fitting one only uses parts you own; the
## garage says what the rest would cost.
const PROFILES := [
	{"id": "stock", "name": "Stock", "blurb": "As it left the factory. Nothing to learn.",
		"set": {}},
	{"id": "sprint", "name": "Sprint", "blurb": "Short races on clean tarmac: fast, fragile, sharp.",
		"set": {"engine": "turbo", "wheels": "slicks", "suspension": "stiff", "body": "stripped",
			"rope": "short_rope", "charge": "shaped_charge"}},
	{"id": "endurance", "name": "Endurance", "blurb": "Ten laps and contact: it will still be there at the end.",
		"set": {"engine": "torque", "wheels": "hard", "suspension": "soft", "body": "cage",
			"rope": "long_rope", "charge": "stock_charge"}},
	{"id": "dirt", "name": "Dirt", "blurb": "Cuts the grass and the sand on purpose.",
		"set": {"engine": "torque", "wheels": "gravel", "suspension": "soft", "body": "cage",
			"rope": "long_rope"}},
]


## One profile by id, or {}.
static func profile(profile_id: String) -> Dictionary:
	for p in PROFILES:
		if String((p as Dictionary)["id"]) == profile_id:
			return p
	return {}


## The parts a profile fits: {slot: part_id}, stock for anything it does not name.
static func profile_parts(profile_id: String) -> Dictionary:
	var out := {}
	var named: Dictionary = profile(profile_id).get("set", {})
	for slot in SLOTS:
		out[slot] = String(named.get(slot, stock(String(slot))))
	return out


## Every part in a slot, stock first.
static func in_slot(slot: String) -> Array:
	return CATALOGUE.get(slot, []) as Array


## One part by id, or {} if there is no such part.
static func find(part_id: String) -> Dictionary:
	for slot in SLOTS:
		for p in in_slot(String(slot)):
			if String((p as Dictionary)["id"]) == part_id:
				return p
	return {}


## The stock (free) part of a slot: what a car is fitted with until something is bought.
static func stock(slot: String) -> String:
	var list := in_slot(slot)
	return String((list[0] as Dictionary)["id"]) if not list.is_empty() else ""


static func price(part_id: String) -> int:
	return int(find(part_id).get("price", 0))


static func display_name(part_id: String) -> String:
	return String(find(part_id).get("name", part_id))


## Fits `fitted` ({slot: part_id}) to `car`: every multiplier in the parts' `set` blocks, applied to the
## car's own numbers. Unknown fields are ignored, so a part can never typo a car into nonsense.
static func apply(car: Car, fitted: Dictionary) -> void:
	if car == null:
		return
	for slot in SLOTS:
		var part := find(String(fitted.get(slot, stock(String(slot)))))
		var changes: Dictionary = part.get("set", {})
		for field in changes.keys():
			var name := String(field)
			if not name in car:
				continue
			var value: Variant = car.get(name)
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				car.set(name, float(value) * float(changes[field]))
	car.refresh_tuning()


## How wide the fitted tyres are drawn -- slicks and all-terrains are visibly fatter than stock.
const WHEEL_LOOK := {"slicks": 1.12, "gravel": 1.18, "hard": 1.06}


static func wheel_scale(fitted: Dictionary) -> float:
	return float(WHEEL_LOOK.get(String(fitted.get("wheels", "")), 1.0))


## What a car's top speed and weight read as with these parts on, for the garage's numbers.
static func scaled(fitted: Dictionary, field: String) -> float:
	var factor := 1.0
	for slot in SLOTS:
		var part := find(String(fitted.get(slot, stock(String(slot)))))
		factor *= float((part.get("set", {}) as Dictionary).get(field, 1.0))
	return factor
