extends SceneTree
## SPEC 143: the whole screen mid-countdown, through the path a player takes (menu -> start_race) --
## what a player is told about the field before the lights go out.
##   godot --path . --script res://tools/shoot_countdown.gd [-- --track circle]

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
	var img: Image = root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build/spike")
	var path := "res://build/spike/countdown_%s.png" % track
	img.save_png(path)
	for r in race.rivals:
		print("rival: %s  (%s, %s)" % [r["name"], r["difficulty"], r["profile"]])
	print("-> %s" % path)
	quit()


func _frame() -> void:
	await process_frame
	if paused:
		paused = false
		var s := current_scene
		if s != null and s.get("pause_menu") != null and s.pause_menu.is_open():
			s.pause_menu.close()
