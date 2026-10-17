extends SceneTree
## SPEC 134: THE REGRESSION CHECK FOR A BUG THE SUITE CANNOT SEE. The same corner of the same race, in
## the COUNTDOWN and the instant after GO, from one run so the camera has not moved between them. The
## cars must point the same way in both, and it must be the way the chevrons point.
##
## Headless never builds a car's 3D model (`Car._ensure_model` refuses on a headless display), so no
## assertion in the suite can look at the picture -- which is why a whole field of cars sat on the grid
## facing backwards through three rounds of "fixes" aimed at the placement, which was never wrong.
## Run this after touching `Car._draw`, `_pose_model`, `_request_redraw` or `CarModel3D.pose`.
##   godot --path . --script res://tools/probe_two_frames.gd
##
## SPEC 141: the race PAUSES when its window loses focus (`Race._notification`), and a probe window
## launched from a terminal usually does not have focus -- so this used to sit paused in the countdown
## until the timeout killed it, and only ever wrote the first frame. It now undoes that pause and SAYS
## it did, because a probe that silently changes the scenario is not measuring the scenario.

var _unpaused := 0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.set_opponent_count(3)
	gs.selected_track = "circle"
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	DirAccess.make_dir_recursive_absolute("res://build/spike/frames")
	# A genuine COUNTDOWN frame: captured while the phase still says so, not after a guessed delay.
	for k in 20:
		await _frame(race)
	if race.phase != 0:
		print("MISSED the countdown -- it was already racing")
	root.get_viewport().get_texture().get_image().save_png("build/spike/frames/a_countdown.png")
	print("countdown phase=%d  you heading %.0f  model yaw %s" % [race.phase, rad_to_deg(race.car.heading),
			_yaw(race.car)])
	# ... and four frames after the lights, before anything has had time to drive anywhere.
	var guard := 0
	while race.phase != 1 and guard < 1200:
		await _frame(race)
		guard += 1
	for k in 4:
		await _frame(race)
	root.get_viewport().get_texture().get_image().save_png("build/spike/frames/b_go.png")
	print("go        phase=%d  you heading %.0f  model yaw %s" % [race.phase, rad_to_deg(race.car.heading),
			_yaw(race.car)])
	if _unpaused > 0:
		print("NOTE: the race paused on focus loss %d time(s); the probe resumed it each time." % _unpaused)
	race.free()
	quit()


## One frame, undoing a focus-loss pause if one happened.
func _frame(race: Node) -> void:
	await process_frame
	if paused:
		_unpaused += 1
		paused = false
		if race.pause_menu != null and race.pause_menu.is_open():
			race.pause_menu.close()


func _yaw(car: Car) -> String:
	var m = car.get_node_or_null("Model3D")
	if m == null or m.get("_yaw") == null:
		return "(no model)"
	return "%.0f" % (-rad_to_deg((m._yaw as Node3D).rotation.y))
