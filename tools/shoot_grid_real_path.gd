extends SceneTree
## SPEC 141: the picture, through the path a player takes. Main menu -> `GameState.start_race` -> one
## frame mid-countdown and one just after GO, the grid cropped from each and stacked, so "did anything
## turn round at the lights" is answered by looking rather than by reading a heading.
##
##   godot --path . --script res://tools/shoot_grid_real_path.gd [-- --track circle]

func _init() -> void:
	await process_frame
	var track := "circle"
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
	for k in 60:
		await _frame()
	var countdown: Image = root.get_viewport().get_texture().get_image()
	var guard := 0
	while int(race.phase) != 1 and guard < 900:
		await _frame()
		guard += 1
	for k in 3:
		await _frame()
	var go: Image = root.get_viewport().get_texture().get_image()
	# Crop round the player's car in screen space and stack the two.
	var cam: Camera2D = root.get_viewport().get_camera_2d()
	var at: Vector2 = race.car.get_global_transform_with_canvas().origin
	var box := Rect2i(int(at.x) - 300, int(at.y) - 110, 420, 180).intersection(Rect2i(Vector2i.ZERO, countdown.get_size()))
	var out := Image.create(box.size.x, box.size.y * 2 + 8, false, countdown.get_format())
	go.convert(countdown.get_format())
	out.fill(Color(0.1, 0.1, 0.1))
	out.blit_rect(countdown, box, Vector2i(0, 0))
	out.blit_rect(go, box, Vector2i(0, box.size.y + 8))
	DirAccess.make_dir_recursive_absolute("res://build/spike")
	var path := "res://build/spike/grid_%s.png" % track
	out.save_png(path)
	print("top = countdown, bottom = 3 frames after GO  ->  %s   (car heading %.0f)" % [path,
			rad_to_deg(race.car.heading)])
	quit()


func _frame() -> void:
	await process_frame
	if paused:
		paused = false
		var s := current_scene
		if s != null and s.get("pause_menu") != null and s.pause_menu.is_open():
			s.pause_menu.close()
