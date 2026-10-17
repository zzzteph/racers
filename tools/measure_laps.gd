extends SceneTree
## Lap-time table: every car on every track, driven by the hard, clean AI (the best driver the game
## has), alone on the road. The car is set up exactly as a player's car (CarRegistry.apply), so the rope,
## over-pull, rough ground, sand, damage and the boost all apply; a wreck costs Race.WRECK_TIME and a
## respawn at the last checkpoint, as in a race.
##
##   godot --headless --path . --script res://tools/measure_laps.gd [-- --laps 3 --tracks circle,miami --cars f1,kart
##       --level hard|medium|easy --persona pro|hothead|drifter|bully|rookie|wildcard --set max_speed=700,acceleration=600 --write-medals 1]
##
## --write-medals 1 (with the default hard level, all tracks and all cars) writes every car's best lap on
## every track to scripts/medal_times.gd: the medal targets (Medals) and each car's best tracks.
##
## Prints, per track, each car's race time, best lap, wrecks and time off the road, then each car's
## average rank and its time relative to the fastest car. This measures the cars through the AI's
## driving: the AI plans for 80 % of the grip and 70 % of the brakes, and it never cuts across the grass
## on purpose, so a car's off-road talent is under-counted.

const DT := 1.0 / 60.0
const WRECK_TIME := 2.2

var _level := "hard"
var _persona := "pro"
var _set: Array = []      # --set key=value,key=value: applied on top of the registry (for tuning)


func _init() -> void:
	var args := _args()
	var laps := int(args.get("laps", "3"))
	_level = String(args.get("level", "hard"))
	_persona = String(args.get("persona", "pro"))
	if args.has("set"):
		for kv in String(args["set"]).split(","):
			var p := kv.split("=")
			if p.size() == 2:
				_set.append([p[0], float(p[1])])
	var tracks := TrackRegistry.ids() if not args.has("tracks") else PackedStringArray(String(args["tracks"]).split(","))
	var cars := CarRegistry.ids() if not args.has("cars") else PackedStringArray(String(args["cars"]).split(","))
	if args.has("compare"):
		_compare(tracks, String(args["compare"]), laps)
		quit()
		return
	var table := {}       # car -> [ranks], [relative]
	var best_laps := {}   # track -> car -> best lap
	var totals := {}      # track -> car -> race time
	for c in cars:
		table[c] = {"ranks": [], "rel": [], "wrecks": 0}
	print("Lap times: %s %s AI, %d laps, alone." % [_level, _persona, laps] + "  race = total, lap = best lap, wr = wrecks, off = s off the road, top = share of top speed reached")
	for t in tracks:
		var rows := []
		best_laps[t] = {}
		totals[t] = {}
		for c in cars:
			var r := _run(t, c, laps)
			rows.append(r)
			best_laps[t][c] = float(r["lap"])
			totals[t][c] = float(r["total"])
		var best := INF
		for r in rows:
			best = minf(best, float(r["total"]))
		var sorted := rows.duplicate()
		sorted.sort_custom(func(a, b): return float(a["total"]) < float(b["total"]))
		print("\n%s" % TrackRegistry.get_display_name(t))
		for i in sorted.size():
			var r: Dictionary = sorted[i]
			var total := float(r["total"])
			print("  %d. %-13s race %7.2f s  lap %6.2f s  %+6.1f %%  wr %d  off %4.1f s  boosts %d  zone %4.1f s  top %3.0f %%  drifts %d  mistakes %d" % [i + 1,
					CarRegistry.get_display_name(String(r["car"])), total, float(r["lap"]),
					(total / best - 1.0) * 100.0, int(r["wrecks"]), float(r["off"]), int(r["boosts"]), float(r["band"]), float(r["top"]) * 100.0, int(r["drifts"]), int(r["mistakes"])])
			table[r["car"]]["ranks"].append(i + 1)
			table[r["car"]]["rel"].append((total / best - 1.0) * 100.0)
			table[r["car"]]["wrecks"] += int(r["wrecks"])
	print("\nSummary (all tracks)")
	for c in cars:
		var ranks: Array = table[c]["ranks"]
		var rel: Array = table[c]["rel"]
		var wins := ranks.count(1)
		print("  %-13s avg rank %.2f  wins %d/%d  avg %+5.1f %% off the fastest  wrecks %d" % [
				CarRegistry.get_display_name(c), _avg(ranks), wins, ranks.size(), _avg(rel), int(table[c]["wrecks"])])
	if args.has("write-medals"):
		_write_medals(best_laps, totals, laps)
	quit()


## --compare <car>: every personality in that car on every track -- totals side by side.
func _compare(tracks: PackedStringArray, car_id: String, laps: int) -> void:
	print("Personalities, %s AI in the %s, %d laps, %d tracks (sums over the tracks)" % [_level, car_id, laps, tracks.size()])
	print("  %-9s %9s %8s %6s %7s %7s %7s %7s %6s" % ["", "race s", "off s", "wrecks", "drifts", "mistks", "boosts", "lapses", "flats"])
	for pe in ["pro", "hothead", "drifter", "bully", "rookie", "wildcard"]:
		_persona = pe
		var tot := {"total": 0.0, "off": 0.0, "wrecks": 0, "drifts": 0, "mistakes": 0, "boosts": 0, "lapses": 0, "flats": 0}
		for t in tracks:
			var r := _run(t, car_id, laps)
			for k in tot.keys():
				tot[k] += r[k]
		print("  %-9s %9.1f %8.1f %6d %7d %7d %7d %7d %6d" % [pe, tot["total"], tot["off"], tot["wrecks"],
				tot["drifts"], tot["mistakes"], tot["boosts"], tot["lapses"], tot["flats"]])


func _write_medals(best_laps: Dictionary, totals: Dictionary, laps: int) -> void:
	var out := "class_name MedalTimes
extends RefCounted
"
	out += "## GENERATED by tools/measure_laps.gd --write-medals 1 -- do not edit by hand; re-run the tool after
"
	out += "## changing a car or a track. Every car's best lap on every track (s), driven by the hard, clean AI
"
	out += "## alone over %d laps. Medals uses them as the medal targets; the car screen ranks the cars by them.

" % laps
	out += "const AI_BEST_LAP := {
"
	for t in best_laps.keys():
		var parts := PackedStringArray()
		for c in best_laps[t].keys():
			parts.append("\"%s\": %.3f" % [c, float(best_laps[t][c])])
		out += "	\"%s\": {%s},
" % [t, ", ".join(parts)]
	out += "}

## The same drives' race times (s) -- who wins a race, which is what the balance is judged on.
"
	out += "const AI_RACE_TIME := {
"
	for t in totals.keys():
		var parts2 := PackedStringArray()
		for c in totals[t].keys():
			parts2.append("\"%s\": %.3f" % [c, float(totals[t][c])])
		out += "	\"%s\": {%s},
" % [t, ", ".join(parts2)]
	out += "}
"
	# A table with a missing time in it is worse than no new table: `inf` in a const dictionary does not
	# even parse, so writing one would take the whole game down. Refuse, and say which run failed.
	for table in [best_laps, totals]:
		for tid in (table as Dictionary).keys():
			for cid in (table[tid] as Dictionary).keys():
				if not is_finite(float(table[tid][cid])):
					printerr("measure_laps: %s/%s did not finish -- medal_times.gd NOT written" % [tid, cid])
					return
	var f := FileAccess.open("res://scripts/medal_times.gd", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("
wrote scripts/medal_times.gd")


func _run(track_id: String, car_id: String, laps: int) -> Dictionary:
	var track := Track.new()
	track.setup(track_id)
	root.add_child(track)
	var car := preload("res://scenes/car.tscn").instantiate() as Car
	root.add_child(car)
	car.auto_process = false
	car.use_mouse = false
	CarRegistry.apply(car, car_id, 0)
	# SPEC 52: the car is clamped at ITS world's barrier. Without this a big track keeps the default
	# 1280x720 bounds, the car cannot leave the first quarter of it, and every lap reads as INF.
	car.bounds = Rect2(Vector2.ZERO, track.world_size)
	for kv in _set:
		car.set(kv[0], kv[1])
	car.reset_to(track.get_start_position(), track.get_start_heading())
	var ai := AIDriver.new()
	ai.setup(car, track, _level, _persona, 17)
	ai.reset_progress(0)
	car.set_on_track_provider(ai.make_on_track_provider())
	car.set_surface_provider(track.make_surface_provider())
	var lt := LapTracker.new()
	lt.setup(track.get_checkpoint_positions(), track.get_checkpoint_indices(), track.get_point_count(),
			track.get_checkpoint_radius(), laps)
	if track.get_point_count() >= 2:
		lt.set_start_line(track.centerline[0], track.centerline[1] - track.centerline[0])
	lt.start()
	var wrecks := [0]
	var wreck_left := [0.0]
	car.wrecked.connect(func() -> void:
		wrecks[0] += 1
		wreck_left[0] = WRECK_TIME
		car.lock())
	var boosts := [0]
	car.boost_fired.connect(func() -> void: boosts[0] += 1)
	var band := 0.0
	var top := 0.0
	var off := 0.0
	var steps := 0
	var limit := int(60.0 * 60.0 * 4.0)        # 4 minutes of race
	var n := track.get_point_count()
	while not lt.finished and steps < limit:
		steps += 1
		if wreck_left[0] > 0.0:
			wreck_left[0] -= DT
			lt.update_race(DT, car.position, ai.progress)
			if wreck_left[0] <= 0.0:
				var idx: int = ai.progress
				var cps := track.get_checkpoint_indices()
				if not cps.is_empty():
					var last := posmod(lt.next_checkpoint - 1, cps.size())
					idx = cps[last] if last != 0 else 3 % n
				car.reset_to(track.centerline[idx], (track.centerline[(idx + 1) % n] - track.centerline[posmod(idx - 1, n)]).angle())
				car.repair()
				ai.reset_progress(idx)
				car.unlock()
			continue
		var target := ai.compute_target(DT, [car])
		car.physics_step(DT, target)
		lt.update_race(DT, car.position, ai.progress)
		if track.has_bridge():
			car.set_bridge_layer(track.is_index_on_upper_branch_zone(ai.progress))
			car.set_bridge_scale(track.is_index_on_deck(ai.progress))
		if car.is_off_track():
			off += DT
		if car.is_in_tension_zone():
			band += DT
		top = maxf(top, car.get_speed())
	var total := lt.total_time if lt.finished else INF
	var flats := car.get_burst_count() if car.tyres_enabled else 0
	var out := {"car": car_id, "total": total, "lap": lt.best_lap_time, "wrecks": wrecks[0], "off": off,
			"drifts": ai.get_drift_count(), "mistakes": ai.get_mistake_count(), "lapses": ai.get_lapse_count(), "flats": flats,
			"boosts": boosts[0], "band": band, "top": top / car.max_speed}
	car.queue_free()
	track.queue_free()
	return out


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
