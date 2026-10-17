extends SceneTree
## SPEC 141: the grid-facing bug, reproduced the way a PLAYER gets to it.
##
## `probe_two_frames` instantiates `race.tscn` directly, and on the desktop it has shown the grid
## correct ever since SPEC 134 -- while the bug kept being reported. So this takes the other road: the
## real main menu, then `GameState.start_race`, which is the scene change a player's click makes.
##
## The check itself is the one that finally settled SPEC 134: for every car, mid-countdown, the texture
## the car is DRAWING is compared with a freshly forced render of the SAME pose. If they differ, the
## player spent the countdown looking at a stale picture -- whatever `heading` and the model's yaw say.
## It also reads the model's own bookkeeping (`_shown`, the pose it BELIEVES the texture holds), because
## the interesting failure is when that belief and the picture disagree.
##
##   godot --path . --script res://tools/probe_grid_real_path.gd

func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.set_opponent_count(3)
	change_scene_to_file("res://scenes/main_menu.tscn")
	for k in 30:
		await _frame()
	gs.start_race("circle")
	var race: Node = null
	for k in 300:
		await _frame()
		race = current_scene
		if race != null and "phase" in race and race.get("car") != null:
			break
	# Well into the countdown, where the player is looking at the grid.
	for k in 60:
		await _frame()
	print("phase %d (0 = countdown)" % int(race.phase))
	var pc: Car = race.car
	var pm = pc.get_node_or_null("Model3D")
	print("tree paused %s | car can_process %s is_processing %s | model can_process %s internal %s | car visible %s in tree %s"
			% [paused, pc.can_process(), pc.is_processing(), pm.can_process() if pm else "-",
			pm.is_processing_internal() if pm else "-", pc.is_visible_in_tree(), pc.is_inside_tree()])
	# Watch the redraw flag across frames: if _process runs, it is cleared at least sometimes.
	var cleared := 0
	for k in 30:
		await _frame()
		if not bool(pc.get("_redraw_pending")):
			cleared += 1
	print("redraw flag seen clear on %d of 30 frames; model mode now %d, renders %d"
			% [cleared, int(pm.render_target_update_mode), int(pm.renders_requested)])
	print("%-9s %8s %8s %8s %9s %8s   %s" % ["car", "heading", "believes", "yaw", "renders", "mode", "texture"])
	var rows: Array = [["you", race.car]]
	for i in race.rivals.size():
		rows.append(["rival %d" % (i + 1), (race.rivals[i] as Dictionary)["car"]])
	for row in rows:
		var c: Car = row[1]
		var m = c.get_node_or_null("Model3D")
		if m == null:
			print("%-9s (no model)" % row[0])
			continue
		var before: Image = m.get_texture().get_image()
		var believed: float = rad_to_deg(float(m._shown[0]))
		var yaw: float = -rad_to_deg((m._yaw as Node3D).rotation.y)
		var renders: int = m.renders_requested
		var mode: int = m.render_target_update_mode
		# Force a render of exactly the pose the model already holds, and read the result back.
		m.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _frame()
		await _frame()
		var after: Image = m.get_texture().get_image()
		var diff := 0
		for y in range(0, after.get_height(), 3):
			for x in range(0, after.get_width(), 3):
				var p: Color = before.get_pixel(x, y)
				var q: Color = after.get_pixel(x, y)
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) + absf(p.a - q.a) > 0.25:
					diff += 1
		print("%-9s %7.0f° %7.0f° %7.0f° %9d %8d   %s" % [row[0], rad_to_deg(c.heading), believed, yaw,
				renders, mode, ("STALE (%d px differ from a fresh render)" % diff) if diff > 30 else "fresh"])
	quit()


func _frame() -> void:
	await process_frame
	if paused:
		paused = false
		var s := current_scene
		if s != null and s.get("pause_menu") != null and s.pause_menu.is_open():
			s.pause_menu.close()
