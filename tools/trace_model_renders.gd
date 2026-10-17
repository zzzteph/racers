extends SceneTree
## SPEC 141: WHICH render gets lost? Frame by frame from the first frame of a race reached through the
## real menu path, for the player's car: how many renders the model has asked for, what pose it
## believes its texture holds, what the 3D yaw actually is, and a hash of the texture it is drawn from.
## A request that is never followed by a change of hash is a render that never reached the picture.
##
##   godot --path . --script res://tools/trace_model_renders.gd

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
		await process_frame
	gs.start_race("circle")
	var race: Node = null
	while true:
		await process_frame
		race = current_scene
		if race != null and "phase" in race and race.get("car") != null:
			break
	var car: Car = race.car
	var last_hash := 0
	var last_req := -1
	print("%5s %6s %6s %9s %7s %7s %12s  %s" % ["frame", "phase", "reqs", "believes", "yaw", "mode", "tex hash", ""])
	for f in 40:
		var m = car.get_node_or_null("Model3D")
		if m == null:
			print("%5d  (no model yet)" % f)
			await process_frame
			continue
		var img: Image = m.get_texture().get_image()
		var h: int = hash(img.get_data()) if img != null else 0
		var reqs: int = m.renders_requested
		var note := ""
		if h != last_hash:
			note += "texture CHANGED  "
		if reqs != last_req:
			note += "render REQUESTED  "
		print("%5d %6d %6d %8.0f° %6.0f° %7d %12d  %s" % [f, int(race.phase), reqs,
				rad_to_deg(float(m._shown[0])), -rad_to_deg((m._yaw as Node3D).rotation.y),
				int(m.render_target_update_mode), h, note])
		last_hash = h
		last_req = reqs
		await process_frame
	quit()
