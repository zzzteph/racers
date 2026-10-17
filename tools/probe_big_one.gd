extends SceneTree
## SPEC 145: WHAT BECOMES OF A BIG ONE. One AI car alone on a circuit, every corner a big one (the flick
## thrown in at BIG_FLICK, no braking), and each one classified by what the physics made of it within
## the window: a ROLL, a hard HIT, went OFF the road and nothing more, or NOTHING at all.
##   godot --headless --path . --script res://tools/probe_big_one.gd [-- --track figure8 --car sport --persona hothead]

const DT := 1.0 / 60.0


func _init() -> void:
	call_deferred("run")


func _arg(name: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if String(a[i]) == name and i + 1 < a.size():
			return String(a[i + 1])
	return fallback


func run() -> void:
	var track_id := _arg("--track", "figure8")
	var car_id := _arg("--car", "sport")
	var persona := _arg("--persona", "hothead")
	var fast := float(_arg("--fast", "150"))
	var t := Track.new()
	root.add_child(t)
	t.setup(track_id)
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(Vector2.ZERO, t.world_size)
	CarRegistry.apply(c, car_id)
	root.add_child(c)
	c.reset_to(t.get_start_position(), t.get_start_heading())
	var ai := AIDriver.new()
	ai.setup(c, t, "hard", persona, 23)
	ai.reset_progress(0)
	ai.force_big = true
	c.set_on_track_provider(ai.make_on_track_provider())
	c.set_surface_provider(t.make_surface_provider())
	var rolled := [0]
	var hit := [0]
	c.rollover_started.connect(func(_s: float) -> void: rolled[0] += 1)
	c.hard_impact.connect(func(f: float) -> void:
		if f >= 240.0:
			hit[0] += 1)
	var outcomes := {"roll": 0, "hit": 0, "off_fast": 0, "off": 0, "nothing": 0}
	var off_fast := false
	var in_one := false
	var saw_roll := 0
	var saw_hit := 0
	var went_off := false
	var peak_slip := 0.0
	var peak_lat := 0.0
	var speeds: Array = []
	var big_before := 0
	var frames := 0
	while outcomes["roll"] + outcomes["hit"] + outcomes["off_fast"] + outcomes["off"] + outcomes["nothing"] < 40 and frames < 60 * 400:
		var target := ai.compute_target(DT, [c])
		c.physics_step(DT, target)
		frames += 1
		if ai.is_in_big_one():
			if not in_one:
				in_one = true
				saw_roll = rolled[0]
				saw_hit = hit[0]
				went_off = false
				off_fast = false
				peak_slip = 0.0
				peak_lat = 0.0
				speeds.append(c.get_speed())
			if c.is_off_track() and not went_off:
				off_fast = c.get_speed() >= fast
			went_off = went_off or c.is_off_track()
			peak_slip = maxf(peak_slip, absf(rad_to_deg(c.get_slip_angle())))
		elif in_one:
			in_one = false
			if rolled[0] > saw_roll:
				outcomes["roll"] += 1
			elif hit[0] > saw_hit:
				outcomes["hit"] += 1
			elif off_fast:
				outcomes["off_fast"] += 1
			elif went_off:
				outcomes["off"] += 1
			else:
				outcomes["nothing"] += 1
	var avg := 0.0
	for v in speeds:
		avg += float(v)
	avg /= maxf(speeds.size(), 1)
	print("%s / %s / %s: %d big ones -> roll %d, hard hit %d, off the road at %.0f+ %d, off slower %d, nothing %d   (flick at %.0f px/s avg)" % [
			track_id, car_id, persona, speeds.size(), outcomes["roll"], outcomes["hit"], fast, outcomes["off_fast"], outcomes["off"], outcomes["nothing"], avg])
	quit()
