extends SceneTree
## WHAT IS THE ROPE'S LENGTH FOR? (SPEC 136.)
##
## Started as a spike on splitting the rope into GEARS to allow a shorter rope, and ended up measuring
## something more useful, because the gears turned out to be irrelevant to it. Kept as the record and as
## a regression check on any future change to `speed_per_px` or `slack_radius`.
##
## The method: hold the pointer still at a fixed distance, shake it by a realistic amount, and read how
## much the car's speed wanders. Three stiffnesses of the same rope, same car, same shake.
##
## WHAT IT FOUND, and it is not what the spike set out to test:
##
##   1. Halving the rope EXACTLY doubles the speed wander (1.8 -> 3.8 px/s at a 4 px shake). The rope is
##      long because length buys precision, and the trade is linear.
##   2. Quantising the rope into detents recovers about 13 % of that, whether the detent bites one way
##      or both. It is not a fix. At the SAME length, adding detents changed nothing at all.
##   3. Which is because the wander does not come in through the rope's LENGTH. It comes in through its
##      ANGLE: the same 4 px of shake is 1.0 degrees at 234 px and 1.8 degrees at 129, and that 1.8x is
##      almost exactly the 2.1x in the wander. A shaky hand steers the car, and steering scrubs speed.
##      Nothing done to the length scale can touch it.
##
## So: if the rope ever needs to be shorter, the thing to buy back is STEERING precision, not speed
## precision, and no readout or quantisation will do it.
##
##   godot --headless --path . --script res://tools/probe_rope_length.gd

const DT := 1.0 / 60.0
const CAR := "sport"
const SETTLE := 6.0          # s to reach the demanded speed before measuring
const MEASURE := 20.0        # s of held pointer with the hand shaking
const ASK := 0.70            # hold the rope at this share of the car's top speed
const SHAKES := [0.0, 4.0, 10.0]     # px of wobble: a still hand, a mouse hand, a fingertip
const GEARS := 5

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	await process_frame
	var configs := [
		{"name": "A long analog", "px": 2.0, "gears": 0},
		{"name": "B short analog", "px": 4.0, "gears": 0},
		{"name": "C short, 1-way", "px": 4.0, "gears": GEARS, "easing": true},
		{"name": "D short, 2-way", "px": 4.0, "gears": GEARS, "easing": false},
		{"name": "E long, 2-way", "px": 2.0, "gears": GEARS, "easing": false},
	]
	var probe := _car()
	var top: float = probe.max_speed
	print("")
	print("%s, top speed %.0f px/s, holding the rope at %.0f %% of it." % [CAR, top, ASK * 100.0])
	print("")
	print("%-16s %7s   %s" % ["rope", "length", "  wobble ->  speed wander (px/s) / mean speed / travel"])
	for cfg in configs:
		var d: Dictionary = cfg
		# The pointer distance that asks for ASK of top speed, under THIS rope's stiffness.
		var hold: float = probe.slack_radius + ASK * top / float(d["px"])
		var cells := PackedStringArray()
		for shake in SHAKES:
			var r: Dictionary = _run(float(d["px"]), int(d["gears"]), bool(d.get("easing", true)),
					hold, float(shake))
			cells.append("%4.0f px -> %6.1f / %5.0f / %5.0f" % [shake, r["sd"], r["mean"], r["travel"]])
		print("%-16s %6.0f px   %s" % [String(d["name"]), hold, cells[0]])
		for i in range(1, cells.size()):
			print("%-16s %9s   %s" % ["", "", cells[i]])
	probe.free()
	print("")
	print("WHERE DOES THE WANDER COME FROM? The same 10 px shake, split into the part that moves the")
	print("pointer ALONG the rope (which is a speed demand) and the part that moves it ACROSS (which is")
	print("a steering input, and scrubs speed off in the corners it puts in).")
	print("")
	print("%-16s %7s %10s %10s" % ["rope", "length", "along", "across"])
	for cfg in configs:
		var d2: Dictionary = cfg
		var hold2: float = probe.slack_radius + ASK * top / float(d2["px"])
		var ra: Dictionary = _run(float(d2["px"]), int(d2["gears"]), bool(d2.get("easing", true)),
				hold2, 10.0, 1)
		var rc: Dictionary = _run(float(d2["px"]), int(d2["gears"]), bool(d2.get("easing", true)),
				hold2, 10.0, 2)
		print("%-16s %6.0f px %9.1f %10.1f" % [String(d2["name"]), hold2, ra["sd"], rc["sd"]])
	print("")
	print("'speed wander' is the standard deviation of the car's speed over %.0f s with the pointer" % MEASURE)
	print("HELD STILL and only the wobble moving it -- it is the price of a shaky hand, and the whole")
	print("argument for the rope being long. 'travel' is how far the car got in those seconds: if the")
	print("detents cost speed rather than noise, it shows up there.")
	print("")
	quit()


func _run(px: float, gears: int, easing_only: bool, hold: float, shake: float,
		axis: int = 0) -> Dictionary:
	var c := _car()
	c.speed_per_px = px
	c.rope_gears = gears
	c.rope_gear_easing_only = easing_only
	# The hand is seeded per run so every rope is shaken by exactly the same sequence: the three rows
	# differ by the ROPE and by nothing else.
	_rng.seed = 90210
	var t := 0.0
	while t < SETTLE:
		c.physics_step(DT, c.position + Vector2.from_angle(c.heading) * hold)
		t += DT
	var speeds := PackedFloat32Array()
	var start: Vector2 = c.position
	t = 0.0
	while t < MEASURE:
		var along := Vector2.from_angle(c.heading)
		var across := Vector2(-along.y, along.x)
		var wobble := Vector2.ZERO
		if shake > 0.0:
			if axis != 2:
				wobble += along * _rng.randfn(0.0, shake)
			if axis != 1:
				wobble += across * _rng.randfn(0.0, shake)
		c.physics_step(DT, c.position + along * hold + wobble)
		speeds.append(c.get_speed())
		t += DT
	var mean := 0.0
	for s in speeds:
		mean += s
	mean /= maxf(float(speeds.size()), 1.0)
	var var_sum := 0.0
	for s in speeds:
		var_sum += (s - mean) * (s - mean)
	var sd := sqrt(var_sum / maxf(float(speeds.size()), 1.0))
	var travel: float = start.distance_to(c.position)
	c.free()
	return {"sd": sd, "mean": mean, "travel": travel}


## The same bare car the suite drives: no mouse (the target is handed in), and bounds big enough that
## nothing ever stops it. Without these it sits at the origin doing nothing, which is what the first
## run of this probe measured three times over.
func _car() -> Car:
	var c := Car.new()
	CarRegistry.apply(c, CAR)
	c.use_mouse = false
	c.bounds = Rect2(-1000000, -1000000, 2000000, 2000000)
	c.reset_to(Vector2.ZERO, 0.0)
	return c
