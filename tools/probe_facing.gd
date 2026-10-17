extends SceneTree
## SPEC 134: is the car's TEXTURE the car's heading? Not the model node's rotation -- `probe_facing`
## already checks that and it is always right -- but the picture actually on screen.
##
## A car is drawn by `draw_texture`ing its `CarModel3D` viewport. That viewport renders at the END of a
## frame, so the texture drawn during a frame is the one from the frame before; and a car that is LOCKED
## during the countdown never asks to be redrawn again, so whatever was in the texture when the car was
## first drawn is what the player looks at until the lights go green.
##
## Must run with a real display: headless never builds a model at all.
##   godot --path . --script res://tools/probe_facing.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("no GameState")
		quit(1)
		return
	gs.settings_path = "user://tool_settings.cfg"
	gs.set_opponent_count(2)
	print("")
	print("%-12s %-8s %8s %8s %8s   %s" % ["track", "car", "heading", "yaw", "renders", "texture"])
	for id in ["circle", "singapore", "serpent"]:
		await _check(gs, String(id))
	print("")
	print("'texture' compares the picture during the COUNTDOWN with the picture once the car is moving.")
	print("They must be the same car pointing the same way; 'STALE' means the player spent the whole")
	print("countdown looking at a car drawn facing somewhere it is not.")
	print("")
	quit()


func _check(gs: Node, id: String) -> void:
	gs.selected_track = id
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	for k in 30:
		await process_frame                       # a good look at the grid, as a player gets
	var shots := {}
	var facts := {}
	for row in _cars(race):
		var c: Car = (row as Array)[1]
		var m = c.get_node_or_null("Model3D")
		if m == null:
			continue
		shots[row[0]] = m.get_texture().get_image()
		facts[row[0]] = [rad_to_deg(c.heading), -rad_to_deg(m._yaw.rotation.y), m.renders_requested]
	# The lights go green, and the car is drawn every frame from here on.
	race._skip_countdown() if race.has_method("_skip_countdown") else race._begin_racing()
	for k in 6:
		await process_frame
	for row in _cars(race):
		var c: Car = (row as Array)[1]
		var m = c.get_node_or_null("Model3D")
		if m == null or not shots.has(row[0]):
			continue
		var now: Image = m.get_texture().get_image()
		var before: Image = shots[row[0]]
		var diff := 0
		for y in range(0, now.get_height(), 4):
			for x in range(0, now.get_width(), 4):
				var p: Color = before.get_pixel(x, y)
				var q: Color = now.get_pixel(x, y)
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) + absf(p.a - q.a) > 0.20:
					diff += 1
		var f: Array = facts[row[0]]
		print("%-12s %-8s %7.0f° %7.0f° %8d   %s" % [id, String(row[0]), f[0], f[1], f[2],
				"STALE (%d px changed)" % diff if diff > 20 else "same"])
	race.free()


func _cars(race: Node) -> Array:
	var out: Array = [["you", race.car]]
	for i in race.rivals.size():
		out.append(["rival %d" % (i + 1), (race.rivals[i] as Dictionary)["car"]])
	return out
