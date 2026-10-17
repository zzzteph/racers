extends SceneTree
## SPEC 121: EACH PERSONALITY'S TIME ON EVERY CIRCUIT, so the suite's "the Rookie is the slowest" can be
## pinned on circuits where that is actually true rather than on whichever three were handy.
##   godot --headless --path . --script res://tools/probe_personalities.gd
##
## Three laps, the hard AI, a Sport, alone on the road -- exactly what `test_personalities` drives.

const DT := 1.0 / 60.0
const WHO := ["pro", "hothead", "drifter", "rookie"]


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	print("")
	var head := "%-14s" % "circuit"
	for pe in WHO:
		head += "%10s" % pe
	print(head + "   slowest")
	var totals := {}
	for pe in WHO:
		totals[pe] = 0.0
	for id in TrackRegistry.ids():
		var sid := String(id)
		var line := "%-14s" % sid
		var slowest := ""
		var worst := -1.0
		for pe in WHO:
			var t := _lap(sid, String(pe))
			totals[pe] = float(totals[pe]) + t
			line += "%10.1f" % t
			if t > worst:
				worst = t
				slowest = String(pe)
		print(line + "   " + slowest)
	var sum_line := "%-14s" % "TOTAL"
	var worst_all := -1.0
	var slowest_all := ""
	for pe in WHO:
		sum_line += "%10.1f" % float(totals[pe])
		if float(totals[pe]) > worst_all:
			worst_all = float(totals[pe])
			slowest_all = String(pe)
	print(sum_line + "   " + slowest_all)
	quit(0)


func _lap(id: String, persona: String) -> float:
	var t := Track.new()
	t.setup(id)
	root.add_child(t)
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(Vector2.ZERO, t.world_size)
	CarRegistry.apply(c, "sport")
	c.reset_to(t.get_start_position(), t.get_start_heading())
	var ai := AIDriver.new()
	ai.setup(c, t, "hard", persona, 17)
	ai.reset_progress(0)
	c.set_on_track_provider(ai.make_on_track_provider())
	c.set_surface_provider(t.make_surface_provider())
	var lt := LapTracker.new()
	lt.setup(t.get_checkpoint_positions(), t.get_checkpoint_indices(), t.get_point_count(),
			t.get_checkpoint_radius(), 3)
	lt.set_start_line(t.centerline[0], t.centerline[1] - t.centerline[0])
	lt.start()
	var frames := 0
	while not lt.finished and frames < 60 * 150:
		c.physics_step(DT, ai.compute_target(DT, [c]))
		lt.update_race(DT, c.position, ai.progress)
		frames += 1
	var out := lt.total_time if lt.finished else INF
	c.free()
	t.free()
	return out
