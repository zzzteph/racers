extends SceneTree
## Throwaway visual verification driver (NOT part of the shipped game).
##
## Loads the real race scene for a track, skips the countdown, autopilots the car with `target_point`
## a configurable distance ahead on the centerline, and saves PNG screenshots of selected frames.
##
##   godot --path <project> --script res://tests/visual_demo.gd -- <mode> <out_dir> [track]
##
## modes: "menu" | "circle" | "figure8"
##   plus the physics-extension manoeuvres (visual verifier round, third arg = track id):
##   "lap" (clean fast lap) | "drift" (power slide through a bend) | "brake" (full-speed stop) |
##   "grass" (high-speed excursion onto the grass) | "rollover" (reckless line until the car goes over) |
##   "bridge" (figure-8 crossing on both branches while laying marks)
##
## Must not statically reference Race/Hud/FinishScreen (they use the GameState identifier, which is not
## registered when a --script runner is compiled) -- see SPEC decision 16.

const DT := 1.0 / 60.0

var _out_dir := "res://.visual_frames"
var _mode := "circle"
var _shot := 0
var _log: Array[String] = []
var _car_ref: Car = null
var _track_ref: Track = null
var _race_ref: Node = null
var _track_id := "circle"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_out_dir = args[1]
	if args.size() > 2:
		_track_id = args[2]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("visual_demo: mode=%s out=%s track=%s" % [_mode, _out_dir, _track_id])
	_run()


func _run() -> void:
	match _mode:
		"menu":
			await _run_menu()
		"lap":
			await _run_lap(_track_id)
		"drift":
			await _run_drift(_track_id)
		"brake":
			await _run_brake(_track_id)
		"grass":
			await _run_grass(_track_id)
		"rollover":
			await _run_rollover(_track_id)
		"bridge":
			await _run_bridge()
		_:
			await _run_race(_mode)
	if not _log.is_empty():
		var f := FileAccess.open("%s/_log.txt" % _out_dir, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_log))
			f.close()
	print("visual_demo: wrote %d frames" % _shot)
	quit(0)


# ------------------------------------------------------------------ helpers

func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var name := "%03d_%s.png" % [_shot, tag]
	img.save_png("%s/%s" % [_out_dir, name])
	if _car_ref != null:
		var extra := ""
		if _race_ref != null and _race_ref.get("skid_marks") != null:
			extra = " marks=%d puffs=%d" % [
				_race_ref.skid_marks.get_segment_count(), _race_ref.car_effects.get_puff_count()]
		_log.append(("%s pos=(%.1f,%.1f) heading=%.1fdeg vel_dir=%.1fdeg speed=%.0f off=%s z=%d deck=%s idx=%d"
				+ " slip=%.2f yaw=%.2f drift=%s int=%.2f t=%.2f roll=%d tilt=(%.2f,%.2f) disp=(%.2f,%.2f)"
				+ " h=%.2f%s") % [
			name, _car_ref.position.x, _car_ref.position.y, rad_to_deg(_car_ref.heading),
			rad_to_deg(_car_ref.velocity.angle()), _car_ref.get_speed(), str(_car_ref.is_off_track()),
			_car_ref.z_index, str(_car_ref.is_on_bridge_deck()),
			_track_ref.get_progress_index() if _track_ref != null else -1,
			_car_ref.get_slip_angle(), _car_ref.get_yaw_rate(), str(_car_ref.is_drifting()),
			_car_ref.drift_intensity(), _car_ref.get_drift_time(), _car_ref.get_roll_state(),
			_car_ref.get_load_transfer().x, _car_ref.get_load_transfer().y,
			_car_ref.get_display_pitch(), _car_ref.get_display_roll(), _car_ref.get_roll_height(), extra])
	_shot += 1


## Renders one frame without stepping the sim.
func _idle_frame() -> void:
	await RenderingServer.frame_post_draw


# ------------------------------------------------------------------ main menu

func _run_menu() -> void:
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu: Node = scene.instantiate()
	root.add_child(menu)
	for i in 10:
		await _idle_frame()
	await _capture("main_menu")
	# Hover/focus the first button so the focus style is visible too.
	var btn := menu.find_child("RaceButton", true, false)
	if btn != null:
		btn.grab_focus()
	for i in 4:
		await _idle_frame()
	await _capture("main_menu_focus")


# ------------------------------------------------------------------ race

func _run_race(track_id: String) -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.selected_track = track_id
	var scene: PackedScene = load("res://scenes/race.tscn")
	var race: Node = scene.instantiate()
	root.add_child(race)
	await process_frame
	print("visual_demo: race ready track=%s car=%s" % [race.track, race.car])
	# Drive the race explicitly, one physics step per rendered frame.
	race.set_physics_process(false)
	var track: Track = race.track
	var car: Car = race.car
	_car_ref = car
	_track_ref = track
	car.use_mouse = false
	car.target_point = car.position + Vector2.from_angle(car.heading) * 120.0
	# Do not hijack the real cursor while the demo window is open.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var n := track.get_point_count()
	var bridge_c := track.get_bridge_center()
	var has_bridge: bool = track.has_bridge()

	# --- countdown (car held, rope preview + hint) ---
	var cd := 0
	while race.phase == 0 and cd < 400:
		# First half of the countdown: cursor left far away (as if on the menu button) so the hint shows.
		car.target_point = Vector2(640, 40) if cd < 100 else car.position + Vector2.from_angle(car.heading) * 120.0
		race._physics_process(DT)
		await _idle_frame()
		if cd == 5 or cd == 70 or cd == 130 or cd == 178:
			await _capture("countdown_%s_%03d" % [track_id, cd])
		cd += 1
	# a couple of frames of the "GO" text
	for i in 6:
		race._physics_process(DT)
		await _idle_frame()
	await _capture("go_%s" % track_id)

	# --- racing: mostly a moderate lead, with a far-ahead stretch that makes the rope taut and cuts a corner ---
	var far_from := 520
	var far_to := 700
	var steps := 1500
	for k in steps:
		var idx: int = track.get_progress_index()
		# 14 points (~224 px) is the committed line: it stays on the road but works the tires hard enough to
		# lay rubber and drift through the bends, which is what these frames are for.
		var lookahead := 14
		if k >= far_from and k < far_to:
			lookahead = 26   # ~416 px of arc: full speed, taut red rope, corner cut
		car.target_point = track.centerline[(idx + lookahead) % n]
		race._physics_process(DT)
		await _idle_frame()
		var near_bridge: bool = has_bridge and car.position.distance_to(bridge_c) < 230.0
		if near_bridge:
			var side := "upper" if track.is_car_on_bridge_layer() else "lower"
			await _capture("bridge_%s_%04d" % [side, k])
		elif (k >= 300 and k < 316) or k % 12 == 0:   # dense burst for rotation checking
			var tag := "far" if (k >= far_from and k < far_to) else "run"
			if car.is_off_track():
				tag = "off"
			await _capture("%s_%s_%04d" % [tag, track_id, k])
		if race.phase == 2:
			break

	# --- fast forward (no rendering) to the finish ---
	var guard := 0
	while race.phase != 2 and guard < 40000:
		var idx: int = track.get_progress_index()
		car.target_point = track.centerline[(idx + 10) % n]
		race._physics_process(DT)
		race.hud._process(DT)   # no rendering happens here, so tick the HUD's flash timer by hand
		guard += 1
	print("visual_demo: fast-forward steps=%d phase=%d" % [guard, race.phase])

	# --- finish screen ---
	for i in 40:
		race._physics_process(DT)
		await _idle_frame()
	await _capture("finish_%s" % track_id)

	# --- pause menu (from a fresh race so it is not the finished phase) ---
	race.free()
	await _capture_pause(track_id)
	await _capture_wall(track_id)


func _capture_pause(track_id: String) -> void:
	var scene: PackedScene = load("res://scenes/race.tscn")
	var race: Node = scene.instantiate()
	root.add_child(race)
	race.set_physics_process(false)
	var car: Car = race.car
	_car_ref = car
	_track_ref = race.track
	car.use_mouse = false
	car.target_point = car.position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 190:
		race._physics_process(DT)
	race.pause_race()
	for i in 4:
		await _idle_frame()
	await _capture("pause_%s" % track_id)
	paused = false
	race.free()


## Drives the car straight off the road into the screen-edge barrier: checks the off-track dust/tint, the
## OFF TRACK warning, the slack rope while crawling, and that the car visibly stops against the drawn wall.
func _capture_wall(track_id: String) -> void:
	var scene: PackedScene = load("res://scenes/race.tscn")
	var race: Node = scene.instantiate()
	root.add_child(race)
	await process_frame
	race.set_physics_process(false)
	var car: Car = race.car
	_car_ref = car
	_track_ref = race.track
	car.use_mouse = false
	car.target_point = car.position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var guard := 0
	while race.phase == 0 and guard < 400:
		car.target_point = car.position
		race._physics_process(DT)
		guard += 1
	var corner := Vector2(-300, -300)   # outside the screen: the car must stop against the drawn barrier
	car.reset_to(Vector2(190, 175), deg_to_rad(-135.0))   # already out on the grass, close to the corner
	for k in 700:
		car.target_point = corner
		race._physics_process(DT)
		await _idle_frame()
		if k == 60 or k == 160 or k == 400 or k == 690:
			await _capture("wall_%s_%03d" % [track_id, k])
	race.free()


# ================================================================== physics-extension manoeuvres
# Visual verifier round: scripted runs that make the drift / suspension / rollover / tire-mark systems
# happen on purpose, so the rendered frames can be inspected.

## Builds a real race, skips the countdown with the cursor parked on the car (nothing is laid while held),
## and hands back the scene ready to drive one physics step per rendered frame.
func _begin(track_id: String) -> Node:
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.selected_track = track_id
	var scene: PackedScene = load("res://scenes/race.tscn")
	var race: Node = scene.instantiate()
	root.add_child(race)
	await process_frame
	race.set_physics_process(false)
	var car: Car = race.car
	_car_ref = car
	_track_ref = race.track
	_race_ref = race
	car.use_mouse = false
	car.target_point = car.position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var guard := 0
	while race.phase == 0 and guard < 400:
		car.target_point = car.position
		race._physics_process(DT)
		guard += 1
	return race


func _lead(track: Track, lookahead: int) -> Vector2:
	var n := track.get_point_count()
	return track.centerline[(track.get_progress_index() + lookahead) % n]


## Signed turn direction (+1 = the centerline bends to the right on screen) and how sharp it is.
func _turn_ahead(track: Track, ahead: int) -> Vector2:
	var n := track.get_point_count()
	var i := track.get_progress_index()
	var p0: Vector2 = track.centerline[i]
	var p1: Vector2 = track.centerline[(i + ahead) % n]
	var p2: Vector2 = track.centerline[(i + ahead * 2) % n]
	var t1 := p1 - p0
	var t2 := p2 - p1
	if t1.length() < 1.0 or t2.length() < 1.0:
		return Vector2.ZERO
	return Vector2(signf(t1.cross(t2)), absf(t1.angle_to(t2)))


## Outward normal of the road at the car (points away from the centerline).
func _outward(track: Track) -> Vector2:
	var n := track.get_point_count()
	var i := track.get_progress_index()
	var t: Vector2 = (track.centerline[(i + 1) % n] - track.centerline[i]).normalized()
	var away: Vector2 = _car_ref.position - track.centerline[i]
	var nrm := Vector2(-t.y, t.x)
	return nrm if nrm.dot(away) >= 0.0 else -nrm


func _step_cruise(race: Node, lookahead: int) -> void:
	race.car.target_point = _lead(race.track, lookahead)
	race._physics_process(DT)
	await _idle_frame()


## Drives until `cond` is true (or `limit` frames), capturing a context frame every `every` frames.
func _cruise_until(race: Node, lookahead: int, limit: int, tag: String, every: int, cond: Callable) -> bool:
	for k in limit:
		await _step_cruise(race, lookahead)
		if every > 0 and k % every == 0:
			await _capture("%s_%04d" % [tag, k])
		if cond.is_valid() and bool(cond.call()):
			return true
	return false


# ------------------------------------------------------------------ clean fast lap

func _run_lap(track_id: String) -> void:
	var race: Node = await _begin(track_id)
	var car: Car = race.car
	for k in 2600:
		# 12 points (~192 px) is the "ordinary fast line" the tests pin as clean: it must NOT paint the road.
		await _step_cruise(race, 12)
		if k % 14 == 0:
			await _capture("lap_%s_%04d" % [track_id, k])
		if race.lap_tracker.get_laps_completed() >= 1:
			break
	_log.append("clean lap %s: marks=%d dropped=%d drift_total=%.2f roll_state=%d" % [
		track_id, race.skid_marks.get_segment_count(), race.skid_marks.get_dropped_count(),
		car.get_drift_total(), car.get_roll_state()])
	await _capture("lap_%s_clean_end" % track_id)
	# Second lap on the committed line (~256 px): this one is meant to lay rubber in the corners, so the
	# two laps together show marks appearing only where the tires are actually working.
	for k in 2600:
		await _step_cruise(race, 16)
		if k % 14 == 0:
			await _capture("lap_%s_hot_%04d" % [track_id, k])
		if race.lap_tracker.get_laps_completed() >= 2:
			break
	_log.append("committed lap %s: marks=%d dropped=%d drift_total=%.2f" % [
		track_id, race.skid_marks.get_segment_count(), race.skid_marks.get_dropped_count(),
		car.get_drift_total()])
	await _capture("lap_%s_hot_end" % track_id)
	race.free()


# ------------------------------------------------------------------ power slide

func _run_drift(track_id: String) -> void:
	var race: Node = await _begin(track_id)
	var car: Car = race.car
	var track: Track = race.track
	# Get up to speed on the committed line, then wait for a real bend.
	var armed := await _cruise_until(race, 18, 900, "drift_%s_approach" % track_id, 40,
			func() -> bool:
				var t := _turn_ahead(track, 8)
				return car.get_speed() > 420.0 and t.y > 0.28)
	_log.append("drift %s: armed=%s speed=%.0f idx=%d" % [track_id, str(armed), car.get_speed(),
			track.get_progress_index()])
	var turn := _turn_ahead(track, 8)
	var sgn: float = turn.x if turn.x != 0.0 else 1.0
	# The yank: the cursor thrown ~52 deg across the nose, into the turn (SPEC decision 19).
	for k in 26:
		var fwd := Vector2.from_angle(car.heading)
		car.target_point = car.position + fwd.rotated(sgn * 0.9) * 2000.0
		race._physics_process(DT)
		await _idle_frame()
		if k % 2 == 0:
			await _capture("drift_%s_slide_%04d" % [track_id, k])
	# ... then what a player does next: a short rope led along the road, which holds the slide through the
	# bend instead of spinning the car off it.
	for k in 60:
		await _step_cruise(race, 9)
		if k % 2 == 0:
			await _capture("drift_%s_hold_%04d" % [track_id, k])
	# Recovery: the one control the player has - bring the cursor back onto the car.
	for k in 60:
		car.target_point = car.position
		race._physics_process(DT)
		await _idle_frame()
		if k % 3 == 0:
			await _capture("drift_%s_recover_%04d" % [track_id, k])
	_log.append("drift %s: marks=%d drift_total=%.2f" % [track_id, race.skid_marks.get_segment_count(),
			car.get_drift_total()])
	race.free()


# ------------------------------------------------------------------ hard brake

func _run_brake(track_id: String) -> void:
	var race: Node = await _begin(track_id)
	var car: Car = race.car
	# 18 points (~288 px) is the fastest lead that still holds the road: a longer one cuts the corner,
	# ends up on the grass at the 58 px/s crawl cap and never reaches braking speed at all.
	var track: Track = race.track
	await _cruise_until(race, 18, 1200, "brake_%s_approach" % track_id, 60,
			func() -> bool:
				return car.get_speed() > 430.0 and not car.is_off_track() \
						and _turn_ahead(track, 6).y < 0.06)
	# Charge: the rope is stretched to full length but kept POINTING along the road (its direction comes from
	# a short 8-point lead, only its length is exaggerated), which is how a player reaches 580 px/s on a
	# straight without the corner cut a distant centerline point would give.
	for k in 120:
		var dir := (_lead(track, 8) - car.position).normalized()
		car.target_point = car.position + dir * 420.0
		race._physics_process(DT)
		await _idle_frame()
		if k % 20 == 0:
			await _capture("brake_%s_charge_%04d" % [track_id, k])
		if car.get_speed() > 545.0 or _turn_ahead(track, 6).y > 0.10:
			break
	_log.append("brake %s: entry speed=%.0f off=%s" % [track_id, car.get_speed(), str(car.is_off_track())])
	for k in 70:
		car.target_point = car.position          # cursor snapped onto the car = full brake
		race._physics_process(DT)
		await _idle_frame()
		if k % 2 == 0:
			await _capture("brake_%s_%04d" % [track_id, k])
	_log.append("brake %s: end speed=%.0f marks=%d" % [track_id, car.get_speed(),
			race.skid_marks.get_segment_count()])
	race.free()


# ------------------------------------------------------------------ high-speed run onto the grass

func _run_grass(track_id: String) -> void:
	var race: Node = await _begin(track_id)
	var car: Car = race.car
	var track: Track = race.track
	await _cruise_until(race, 18, 1200, "grass_%s_approach" % track_id, 60,
			func() -> bool: return car.get_speed() > 460.0 and not car.is_off_track())
	var aim: Vector2 = car.position + _outward(track) * 700.0
	aim.x = clampf(aim.x, 30.0, 1250.0)
	aim.y = clampf(aim.y, 30.0, 690.0)
	_log.append("grass %s: entry speed=%.0f aim=(%.0f,%.0f)" % [track_id, car.get_speed(), aim.x, aim.y])
	for k in 150:
		car.target_point = aim
		race._physics_process(DT)
		await _idle_frame()
		if k % 3 == 0:
			await _capture("grass_%s_%04d" % [track_id, k])
	race.free()


# ------------------------------------------------------------------ rollover

func _run_rollover(track_id: String) -> void:
	var race: Node = await _begin(track_id)
	var car: Car = race.car
	var track: Track = race.track
	var events: Array[String] = []
	car.rollover_started.connect(func(sev: float) -> void: events.append("started sev=%.2f" % sev))
	car.rollover_recovered.connect(func() -> void: events.append("recovered"))
	var burst := 0
	var rolls := 0
	var forced := false
	for k in 2600:
		# A reckless line (~350 px of rope) is what SPEC 8.2 says rolls the car a few times a race.
		if not forced and k == 1400 and rolls == 0:
			# Fallback: the scripted surface trip of the tests - a fast sideways scrub across the road edge.
			forced = true
			var f := Vector2.from_angle(car.heading)
			var right := Vector2(-f.y, f.x)
			var out := _outward(track)
			var side: float = signf(right.dot(out))
			if side == 0.0:
				side = 1.0
			car.velocity = (f * 260.0 + right * side * 520.0).limit_length(car.max_speed - 5.0)
			events.append("forced scrub at k=%d speed=%.0f" % [k, car.velocity.length()])
		await _step_cruise(race, 22)
		var st: int = car.get_roll_state()
		if st != 0:
			burst = maxi(burst, 130)
			if st == 2:
				rolls = maxi(rolls, 1)
		if burst > 0:
			await _capture("roll_%s_%04d_s%d" % [track_id, k, st])
			burst -= 1
			if burst == 0 and rolls > 0:
				# a few settled frames after the recovery, to prove the car is upright and driving again
				for j in 40:
					await _step_cruise(race, 12)
					if j % 4 == 0:
						await _capture("roll_%s_after_%03d" % [track_id, j])
				break
		elif k % 60 == 0:
			await _capture("rollctx_%s_%04d" % [track_id, k])
		if race.phase == 2:
			break
	_log.append("rollover %s: events=%s final_state=%d speed=%.0f pos=(%.0f,%.0f) off=%s" % [
			track_id, str(events), car.get_roll_state(), car.get_speed(), car.position.x, car.position.y,
			str(car.is_off_track())])
	race.free()


# ------------------------------------------------------------------ bridge, both branches, laying marks

func _run_bridge() -> void:
	var race: Node = await _begin("figure8")
	var car: Car = race.car
	var track: Track = race.track
	var centre := track.get_bridge_center()
	var upper := 0
	var lower := 0
	var slid_on_deck := false
	for k in 3000:
		# Once, while actually ON the deck: yank the cursor sideways so the car slides across the bridge.
		# A deck-layer mark must stay inside the deck polygon and never paint over its rails (SPEC 21.11).
		if not slid_on_deck and track.is_car_on_deck() and car.get_speed() > 360.0:
			slid_on_deck = true
			for j in 16:
				var fwd := Vector2.from_angle(car.heading)
				car.target_point = car.position + fwd.rotated(0.9) * 2000.0
				race._physics_process(DT)
				await _idle_frame()
				await _capture("bridge_deckslide_%02d" % j)
			continue
		# 14 points (~224 px) is the committed line: it works the tires hard enough to lay rubber.
		await _step_cruise(race, 14)
		var near: bool = car.position.distance_to(centre) < 250.0
		if near:
			var on_upper: bool = track.is_car_on_bridge_layer()
			if on_upper:
				upper += 1
			else:
				lower += 1
			await _capture("bridge_%s_%04d" % ["upper" if on_upper else "lower", k])
		elif k % 60 == 0:
			await _capture("bridgectx_%04d" % k)
		if upper > 90 and lower > 90:
			break
		if race.phase == 2:
			break
	_log.append("bridge: upper_frames=%d lower_frames=%d marks=%d" % [upper, lower,
			race.skid_marks.get_segment_count()])
	race.free()
