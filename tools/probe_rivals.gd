extends SceneTree
## SPEC 143: DO THE RIVALS RACE EACH OTHER? Three AI rivals, the player's car taken off the road, a race
## simulated through the real race scene, and what happens between them counted: overtakes among the
## rivals, seconds spent sitting on another rival's tail (PRESSURE), mistakes -- and whether a mistake
## comes more often when a car is on the driver's tail than when it is not. "Rivals that race each
## other and crack under pressure" is a claim about these numbers.
##
##   godot --headless --path . --script res://tools/probe_rivals.gd [-- --level hard --track circle --seconds 150]

const DT := 1.0 / 60.0
const TAIL_PX := 75.0            # a car this close behind, roughly in line, is pressure
const TAIL_SIDE := 36.0
const RECENT := 2.0              # s: a mistake within this long of being pressured counts as under pressure
const PASS_MARGIN := 1.0         # centerline points clear before a change of order counts as an overtake

var _track = null


func _init() -> void:
	call_deferred("run")


func _arg(name: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if String(a[i]) == name and i + 1 < a.size():
			return String(a[i + 1])
	return fallback


func run() -> void:
	var level := _arg("--level", "hard")
	var track_id := _arg("--track", "circle")
	var seconds := float(_arg("--seconds", "150"))
	var tail := _arg("--tail", "")                 # "rookie": glue the player's car to that rival's tail
	var force := _arg("--persona", "")             # deal every rival this personality
	var gs := root.get_node("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.set_opponent_count(3)
	gs._fill_opponents(level)
	if force != "":
		for i in gs.opponents.size():
			gs.opponents[i]["profile"] = force
	gs.selected_track = track_id
	gs.laps_override = 99                      # nobody finishes during the measurement
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	race._begin_racing()
	# The player is not part of this: off the road, invisible, so the rivals never see it -- unless it is
	# the GHOST: glued 50 px behind one rival, in its line, so that rival is under pressure all race.
	race.car.lock()
	race.car.visible = false
	race.car.position = Vector2(-500, -500)
	var ghost_of: Car = null
	if tail != "":
		for r in race.rivals:
			if (r["ai"] as AIDriver).get_personality() == tail and ghost_of == null:
				ghost_of = r["car"]
		if ghost_of != null:
			race.car.visible = true
	var t = race.track
	_track = t
	var n: int = t.get_point_count()
	var rows: Array = []
	for r in race.rivals:
		var ai: AIDriver = r["ai"]
		var row := {"r": r, "ai": ai, "car": r["car"], "lt": r["lap_tracker"], "name": String(r["name"]),
				"persona": ai.get_personality(), "mistakes_seen": 0, "m_pressed": 0, "m_free": 0,
				"pressed_s": 0.0, "pressed_ago": INF, "passes": 0, "passed": 0, "contacts": 0, "wrecks": 0,
				"off_s": 0.0, "mood_peak": 0.0, "lead_s": 0.0}
		(r["car"] as Car).hard_impact.connect(func(_f: float) -> void: row["contacts"] += 1)
		(r["car"] as Car).wrecked.connect(func() -> void: row["wrecks"] += 1)
		rows.append(row)
	var order_before := _order(rows, n)
	var ahead_of := {}
	var big_ones := 0
	var caution_s := 0.0
	var cautions := 0
	var was_caution := false
	var green_gaps: Array = []                       # px, leader to last, at each green flag
	var lead_changes := 0
	var leader_idx := -1
	for i in rows.size():
		for j in rows.size():
			if i != j:
				ahead_of["%d>%d" % [i, j]] = _score(rows[i], n) > _score(rows[j], n)
	var steps := int(seconds / DT)
	for k in steps:
		var caution_now: bool = race.is_caution()
		if caution_now:
			caution_s += DT
		if was_caution and not caution_now:
			green_gaps.append(_field_spread(rows))
		if caution_now and not was_caution:
			cautions += 1
		was_caution = caution_now
		if ghost_of != null:
			race.car.position = ghost_of.position - Vector2.from_angle(ghost_of.heading) * 50.0
			race.car.heading = ghost_of.heading
			race.car.velocity = ghost_of.velocity
		race._physics_process(DT)
		# Pressure: who is sitting on whose tail this frame.
		for a in rows:
			a["pressed_ago"] = float(a["pressed_ago"]) + DT
		for a in rows:
			var ca: Car = a["car"]
			if not ca.visible:
				continue
			var fwd := Vector2.from_angle(ca.heading)
			var right := Vector2(-fwd.y, fwd.x)
			for b in rows:
				if b == a:
					continue
				var cb: Car = b["car"]
				if not cb.visible:
					continue
				var rel := cb.position - ca.position
				var ahead := rel.dot(fwd)
				var side := rel.dot(right)
				if ahead < -15.0 and ahead > -TAIL_PX and absf(side) < TAIL_SIDE:
					a["pressed_s"] = float(a["pressed_s"]) + DT         # b is on a's tail
					a["pressed_ago"] = 0.0
			if ghost_of == ca:
				a["pressed_s"] = float(a["pressed_s"]) + DT
				a["pressed_ago"] = 0.0
		for a in rows:
			var ai: AIDriver = a["ai"]
			var m := ai.get_mistake_count()
			if m > int(a["mistakes_seen"]):
				var new := m - int(a["mistakes_seen"])
				a["mistakes_seen"] = m
				if float(a["pressed_ago"]) <= RECENT:
					a["m_pressed"] = int(a["m_pressed"]) + new
				else:
					a["m_free"] = int(a["m_free"]) + new
			if not ai.is_on_track():
				a["off_s"] = float(a["off_s"]) + DT
			a["mood_peak"] = maxf(float(a["mood_peak"]), ai.get_mood())
		# Overtakes among the rivals: the running order, compared with last frame's.
		var order_now := _order(rows, n)
		for i in rows.size():
			for j in rows.size():
				if i == j:
					continue
				var key := "%d>%d" % [i, j]
				var lead: float = _score(rows[i], n) - _score(rows[j], n)
				var was: bool = ahead_of[key]
				if not was and lead >= PASS_MARGIN:
					ahead_of[key] = true
					rows[i]["passes"] = int(rows[i]["passes"]) + 1
					rows[j]["passed"] = int(rows[j]["passed"]) + 1
				elif was and lead <= -PASS_MARGIN:
					ahead_of[key] = false
		order_before = order_now
		rows[order_now[0]]["lead_s"] = float(rows[order_now[0]]["lead_s"]) + DT
		if leader_idx >= 0 and int(order_now[0]) != leader_idx:
			lead_changes += 1
		leader_idx = int(order_now[0])
	print("")
	print("%s, %s rivals, %.0f s simulated, the player %s." % [track_id, level, seconds,
			"glued to the %s's tail" % tail if ghost_of != null else "off the road"])
	print("")
	print("%-26s %-9s %4s %5s %5s %6s %6s %5s %5s %5s %5s %5s %6s %5s" % ["rival", "persona", "laps", "pass", "pssd",
			"tail s", "lead s", "mist", "@tail", "free", "crack", "cont", "off s", "mood"])
	var total_pressed := 0.0
	var total_m_pressed := 0
	var total_m_free := 0
	var total_free := 0.0
	for a in rows:
		var lt: LapTracker = a["lt"]
		var ai: AIDriver = a["ai"]
		print("%-26s %-9s %4d %5d %5d %6.1f %6.1f %5d %5d %5d %5d %5d %6.1f %5.2f" % [String(a["name"]).left(26),
				a["persona"], lt.get_laps_completed(), a["passes"], a["passed"], a["pressed_s"], a["lead_s"],
				ai.get_mistake_count(), a["m_pressed"], a["m_free"], ai.get_crack_count(), a["contacts"], a["off_s"], a["mood_peak"]])
		total_pressed += float(a["pressed_s"])
		total_free += seconds - float(a["pressed_s"])
		total_m_pressed += int(a["m_pressed"])
		total_m_free += int(a["m_free"])
	print("")
	print("Mistakes per minute WITH a car on the tail: %.2f   WITHOUT: %.2f   (tail-time %.0f s of %.0f car-seconds)" % [
			total_m_pressed / maxf(total_pressed / 60.0, 0.01), total_m_free / maxf(total_free / 60.0, 0.01),
			total_pressed, seconds * rows.size()])
	if ghost_of != null:
		for a in rows:
			if a["car"] == ghost_of:
				var ai: AIDriver = a["ai"]
				print("GHOSTED %-8s %s: %d corners, %d mistakes (%d under pressure) = %.0f %% of corners; off the road %.1f s; mood peak %.2f" % [
						a["persona"], level, ai.get_corner_count(), ai.get_mistake_count(), ai.get_crack_count(),
						100.0 * ai.get_mistake_count() / maxf(ai.get_corner_count(), 1), a["off_s"], a["mood_peak"]])
	for a in rows:
		big_ones += (a["ai"] as AIDriver).get_big_one_count()
	var gaps := ""
	for g in green_gaps:
		gaps += "%.0f " % float(g)
	print("INCIDENTS: %d big ones attempted, %d incidents (wrecks), %d cautions for %.0f s in all; loneliest car at each green: %spx; lead changes %d" % [
			big_ones, race.get_incident_count(), race.get_caution_count(), caution_s, gaps, lead_changes])
	var wrecks_all := 0
	for a in rows:
		wrecks_all += int(a["wrecks"])
	print("   wrecks of every cause %d" % wrecks_all)
	var passes := 0
	for a in rows:
		passes += int(a["passes"])
	print("Overtakes among the rivals: %d in %.0f s  (%.1f per minute)" % [passes, seconds, passes / (seconds / 60.0)])
	print("")
	race.free()
	await process_frame
	quit()


## How bunched the field is: the LONGEST distance from any car on the track to its nearest other car.
## A pack reads ~60-150; a car on its own reads the gap to the pack.
func _field_spread(rows: Array) -> float:
	var worst := 0.0
	for row in rows:
		var c: Car = row["car"]
		if not c.visible:
			continue
		var nearest := INF
		for other in rows:
			var o: Car = other["car"]
			if o != c and o.visible:
				nearest = minf(nearest, c.position.distance_to(o.position))
		if nearest < INF:
			worst = maxf(worst, nearest)
	return worst


## The running order (indices into `rows`), leader first.
func _order(rows: Array, n: int) -> Array:
	var idx: Array = []
	for i in rows.size():
		idx.append(i)
	idx.sort_custom(func(i: int, j: int) -> bool:
		return _score(rows[i], n) > _score(rows[j], n))
	return idx


## Centerline points covered since the start, unwrapped (the lap tracker and the AI's progress index wrap
## at different moments, and a score built from both jumps a lap for a frame), with the fraction of the
## current segment, so two cars in the same segment still have an order.
func _score(row: Dictionary, n: int) -> float:
	var ai: AIDriver = row["ai"]
	var c: Car = row["car"]
	var i := ai.progress
	var prev := int(row.get("prev_i", i))
	var step := posmod(i - prev + n / 2, n) - n / 2
	row["prev_i"] = i
	row["covered"] = float(row.get("covered", 0.0)) + float(step)
	var a: Vector2 = _track.centerline[i]
	var b: Vector2 = _track.centerline[(i + 1) % n]
	var frac := clampf((c.position - a).dot(b - a) / maxf((b - a).length_squared(), 1.0), 0.0, 0.999)
	return float(row["covered"]) + frac
