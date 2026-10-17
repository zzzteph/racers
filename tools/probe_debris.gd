extends SceneTree
## SPEC 142: DOES WRECK DEBRIS MATTER? A piece of a car that came off in a crash stays on the track and,
## on paper, punctures the tyre that runs over it (SPEC 45/96). Whether a player ever notices is a
## different question: a piece is a 4 px circle, and a car is 36 px wide.
##
## Three measurements, all through the real race scene:
##   1. A rival is wrecked on the Circle. The player's car is driven through the field at racing speed,
##      round the circuit, several passes down random lines across the road: pieces hit, speed lost,
##      tyre wear taken, tyres burst.
##   2. A rival on its own AI line, lap after lap, past the same wreck.
##   3. A whole race, three rivals, five laps, nobody steering the player: how many pieces are lying
##      on the track by the end, and how many wrecks it took.
##
##   godot --headless --path . --script res://tools/probe_debris.gd

const DT := 1.0 / 60.0
const PASSES := 12
const SPEED := 420.0
const AHEAD := 7                                   # centerline points the rope target leads the car by


func _init() -> void:
	call_deferred("run")


func _race(gs: Node, rivals: int) -> Node:
	gs.set_opponent_count(rivals)
	gs.selected_track = "circle"
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	race._begin_racing()
	return race


## Wrecks rival 0 on centerline point `at` and lets the pieces land. Returns how many there are.
func _wreck(race: Node, at: int) -> Dictionary:
	var t = race.track
	var props = race.props
	var victim: Car = (race.rivals[0] as Dictionary)["car"]
	var mid: Vector2 = t.centerline[at]
	victim.reset_to(mid, 0.0)
	victim.velocity = Vector2(300.0, 0.0)
	victim._hit_vital("tank", 500.0)            # the `wrecked` signal does the rest, as in a race
	for k in int(3.0 / DT):
		race._step_props(DT)
	var pieces := 0
	var tyres := 0
	var spread := Rect2(mid, Vector2.ZERO)
	for p in props._props:
		var kind := int(p["kind"])
		if kind == TrackProps.KIND_PART:
			pieces += 1
			spread = spread.expand(p["pos"])
		elif kind == TrackProps.KIND_TYRE:
			tyres += 1
	return {"car": victim.car_id, "pieces": pieces, "tyres": tyres, "spread": spread.size}


func _wear(c: Car) -> Dictionary:
	var wear := 0.0
	var burst := 0
	for i in Car.WHEEL_COUNT:
		wear += c._tyre_wear[i]
		if c._burst[i]:
			burst += 1
	return {"wear": wear, "burst": burst}


func run() -> void:
	var gs := root.get_node("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	var race := _race(gs, 1)
	var t = race.track
	var props = race.props
	var n: int = t.get_point_count()
	var at := 20
	var w := _wreck(race, at)
	print("")
	print("A wrecked %s leaves %d sharp pieces and %d loose tyres, spread over %.0f x %.0f px." % [
			w["car"], w["pieces"], w["tyres"], (w["spread"] as Vector2).x, (w["spread"] as Vector2).y])
	print("The road is %.0f px wide; a car is %.0f x %.0f; a piece is hit within %.1f px of a contact circle."
			% [TrackRegistry.get_width("circle"), Car.BODY_LENGTH, Car.BODY_WIDTH,
			float(TrackProps.SPEC[TrackProps.KIND_PART]["r"]) + Car.CONTACT_RADIUS])
	print("")
	# 1. The player, round the circuit through it at speed, down a different line each pass.
	var me: Car = race.car
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var half := TrackRegistry.get_width("circle") * 0.5
	var hits_total := 0
	var wear_total := 0.0
	var speed_lost := 0.0
	var bursts := 0
	var passes_hit := 0
	var start := posmod(at - 10, n)
	for k in PASSES:
		me.repair()
		var lane := rng.randf_range(-half * 0.75, half * 0.75)
		var dir: Vector2 = (t.centerline[(start + 1) % n] - t.centerline[posmod(start - 1, n)]).normalized()
		me.reset_to(t.centerline[start] + dir.orthogonal() * lane, dir.angle())
		me.velocity = dir * SPEED
		var hits_before: int = props._part_hits
		var v_min := SPEED
		var v_at_field := SPEED
		var steps := int(2.2 / DT)
		for s in steps:
			var i: int = t.get_nearest_index(me.position)
			# Aim at the track ahead but keep the lane, so the line through the field is the lane chosen.
			var ahead: Vector2 = t.centerline[(i + AHEAD) % n]
			var d2: Vector2 = (t.centerline[(i + AHEAD + 1) % n] - t.centerline[(i + AHEAD - 1) % n]).normalized()
			me.physics_step(DT, ahead + d2.orthogonal() * lane)
			race._step_props(DT)
			if i == at - 2:
				v_at_field = me.velocity.length()
			if i >= at - 2 and i <= at + 4:
				v_min = minf(v_min, me.velocity.length())
		var hits: int = props._part_hits - hits_before
		var ww := _wear(me)
		hits_total += hits
		wear_total += float(ww["wear"])
		bursts += int(ww["burst"])
		if hits > 0:
			passes_hit += 1
		speed_lost += maxf(v_at_field - v_min, 0.0)
	print("THE PLAYER, %d passes through the field at ~%.0f px/s on random lines round the circuit:" % [PASSES, SPEED])
	print("   passes that hit a sharp piece %d of %d" % [passes_hit, PASSES])
	print("   sharp pieces hit in total     %d  (%.1f per pass; each hit sends the piece on down the track)" % [
			hits_total, float(hits_total) / float(PASSES)])
	print("   tyre wear inflicted, total    %.2f  (1.0 bursts a tyre; %.2f per piece)" % [wear_total,
			TrackProps.PART_PUNCTURE])
	print("   tyres burst                   %d" % bursts)
	print("   speed lost through the field  %.0f px/s per pass" % (speed_lost / float(PASSES)))
	print("   pieces still on the track     %d" % props.get_prop_count(TrackProps.KIND_PART))
	print("")
	race.free()
	await process_frame
	# 2. A rival on its own line, lap after lap, through the same wreck.
	race = _race(gs, 2)
	t = race.track
	props = race.props
	_wreck(race, at)
	var other: Dictionary = race.rivals[1]
	var oc: Car = other["car"]
	var olt: LapTracker = other["lap_tracker"]
	var ai_hits_before: int = props._part_hits
	for k in int(70.0 / DT):
		race._physics_process(DT)
	var ow := _wear(oc)
	print("A RIVAL on its own line for 70 s (%d laps) past the same wreck:" % olt.get_laps_completed())
	print("   pieces it hit                 %d" % (props._part_hits - ai_hits_before))
	print("   tyre wear it took             %.2f, tyres burst %d" % [ow["wear"], ow["burst"]])
	print("   damage                        %.0f %%" % oc.get_damage())
	print("   wreck debris left after 70 s  %d pieces, %d loose tyres  (it lives %.0f s here)" % [
			props.get_prop_count(TrackProps.KIND_PART), props.get_prop_count(TrackProps.KIND_TYRE),
			props.get_debris_life()])
	print("")
	race.free()
	await process_frame
	# 3. A whole race: how much debris piles up.
	race = _race(gs, 3)
	props = race.props
	var wrecks := 0
	for r in race.rivals:
		((r as Dictionary)["car"] as Car).wrecked.connect(func() -> void: wrecks += 1)
	race.car.wrecked.connect(func() -> void: wrecks += 1)
	var seconds := 0.0
	var most := 0
	while seconds < 240.0 and race.phase == 1:
		race._physics_process(DT)
		seconds += DT
		most = maxi(most, props.get_prop_count(TrackProps.KIND_PART))
	print("A WHOLE RACE, three rivals, %d laps, %.0f s simulated:" % [race.lap_tracker.total_laps, seconds])
	print("   wrecks                        %d" % wrecks)
	print("   pieces on the track at the end %d  (most at once %d, cap %d)" % [
			props.get_prop_count(TrackProps.KIND_PART), most, TrackProps.MAX_PARTS])
	print("   piece hits in the race        %d" % props._part_hits)
	print("")
	race.free()
	await process_frame
	quit()
