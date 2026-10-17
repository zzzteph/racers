extends SceneTree
## SPEC 145: the screen under a caution, through the player's path (menu -> race), the flag thrown by
## hand two seconds after GO so the frame does not depend on a rival choosing that moment to crash.
##   godot --path . --script res://tools/shoot_caution.gd [-- --track figure8]

func _init() -> void:
	await process_frame
	var track := "figure8"
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if String(a[i]) == "--track" and i + 1 < a.size():
			track = String(a[i + 1])
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.records_path = "user://tool_records.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.set_opponent_count(3)
	change_scene_to_file("res://scenes/main_menu.tscn")
	for k in 30:
		await _frame()
	gs.start_race(track)
	var race: Node = null
	while true:
		await _frame()
		race = current_scene
		if race != null and "phase" in race and race.get("car") != null:
			break
	race.car.use_mouse = false
	var t = race.track
	var n: int = t.get_point_count()
	var guard := 0
	while guard < 900 and (int(race.phase) != 1 or guard < 300):
		var i: int = t.get_nearest_index(race.car.position)
		race.car.target_point = t.centerline[(i + 7) % n]
		await _frame()
		guard += 1
	var victim: Car = (race.rivals[0] as Dictionary)["car"]
	victim._hit_vital("tank", 500.0)
	for k in 45:
		var i: int = t.get_nearest_index(race.car.position)
		race.car.target_point = t.centerline[(i + 7) % n]
		await _frame()
	var img: Image = root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build/spike")
	img.save_png("res://build/spike/caution_%s.png" % track)
	print("caution %s, player limit %.0f, speed %.0f, status '%s' -> build/spike/caution_%s.png" % [
			race.is_caution(), race.car.speed_limit, race.car.get_speed(), race.hud.get_status_line(), track])
	quit()


func _frame() -> void:
	await process_frame
	if paused:
		paused = false
		var s := current_scene
		if s != null and s.get("pause_menu") != null and s.pause_menu.is_open():
			s.pause_menu.close()
