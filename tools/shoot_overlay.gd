extends SceneTree
## Shoots an in-race overlay: the pause menu or the finish screen.
##   godot --path . --script res://tools/shoot_overlay.gd -- --which finish
func _init() -> void:
	await process_frame
	var which := "pause"
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if String(a[i]) == "--which" and i + 1 < a.size():
			which = String(a[i + 1])
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 900
	gs.settings["unlock_all"] = true
	gs.set_opponent_count(3)
	gs.selected_track = "figure8"
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	while race.phase == 0:
		await process_frame
	for i in 60:
		await process_frame
	if which == "finish":
		race.finish_race(96.4, [32.1, 31.8, 32.5])
	else:
		race.pause_race()
	for i in 20:
		await process_frame
	DirAccess.make_dir_recursive_absolute("build/shots")
	root.get_viewport().get_texture().get_image().save_png("build/shots/%s.png" % which)
	print("wrote build/shots/%s.png" % which)
	quit()
