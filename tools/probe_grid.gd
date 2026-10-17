extends SceneTree
## SPEC 131: WHICH WAY IS EVERY CAR ON THE GRID ACTUALLY POINTING? The first version of this probe
## re-implemented `Race._grid_slot` and measured the re-implementation, which is the one thing a probe
## must never do: it agreed with itself and reported every track clean while the Switchback was putting
## cars on the grid facing back down the circuit.
##
## This spawns the REAL race scene and reads the REAL cars: the heading each one was actually given,
## against the way the road runs under it, and against the direction the lap is scored in.
##   godot --headless --path . --script res://tools/probe_grid.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		print("no GameState")
		quit()
		return
	gs.settings_path = "user://tool_settings.cfg"
	gs.set_opponent_count(4)
	print("")
	print("%-13s %-7s %8s %8s   %s" % ["track", "car", "vs road", "vs lap", "notes"])
	for id in TrackRegistry.ids():
		_check(gs, String(id))
		print("")
	quit()


func _check(gs: Node, id: String) -> void:
	gs.selected_track = id
	var race: Node = load("res://scenes/%s.tscn" % "race").instantiate()
	root.add_child(race)
	var track: Node2D = race.track
	var line: PackedVector2Array = track.centerline
	var n := line.size()
	var cars: Array = [["you", race.car]]
	for i in race.rivals.size():
		cars.append(["rival %d" % (i + 1), (race.rivals[i] as Dictionary)["car"]])
	for row in cars:
		var c: Car = (row as Array)[1]
		var i: int = track.get_nearest_index(c.position)
		# The way the ROAD runs here, over a few points so one noisy segment cannot decide it.
		var road: Vector2 = (line[(i + 4) % n] - line[posmod(i - 4, n)]).normalized()
		# ... and the way the LAP is scored, which is the direction of increasing index. These are the
		# same thing unless something has been placed against the flow of the circuit.
		var lap: Vector2 = (line[(i + 1) % n] - line[i]).normalized()
		var facing := Vector2.from_angle(c.heading)
		var off_road := rad_to_deg(absf(facing.angle_to(road)))
		var off_lap := rad_to_deg(absf(facing.angle_to(lap)))
		var note := ""
		if off_lap > 90.0:
			note = "FACING BACK DOWN THE CIRCUIT"
		elif off_lap > 35.0:
			note = "crooked"
		# Where the car is FACING in world terms, and where the first gate it must reach actually is:
		# a car can be perfectly aligned with its own centreline and still be pointing the way a player
		# would not expect, if the circuit's start straight runs the other way from every other one.
		var gates: PackedVector2Array = track.get_checkpoint_positions()
		var to_gate := ""
		if gates.size() > 0:
			var want: Vector2 = (gates[0] - c.position).normalized()
			to_gate = "gate1 %.0f° off" % rad_to_deg(absf(facing.angle_to(want)))
		print("%-13s %-7s %7.0f° %7.0f°  facing %4.0f°  %s %s"
				% [id, String((row as Array)[0]), off_road, off_lap, rad_to_deg(c.heading), to_gate,
				note])
	race.free()
