extends SceneTree
## Shoots any menu scene: godot --path . --script res://tools/shoot_screen.gd -- --scene track_select
func _init() -> void:
	await process_frame
	var which := "track_select"
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if String(a[i]) == "--scene" and i + 1 < a.size():
			which = String(a[i + 1])
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 3100
	gs.profile.finish_race("circle", "medium", 1, 3)
	# SPEC 115: the title menu opens its release notes the first time a build runs; a screenshot of the
	# MENU wants them shut, so the tool says it has seen this build.
	gs.settings["seen_version"] = Version.number()
	# Pictures of the menus get published: no real player's name on them, and no FPS counter.
	gs.settings["player_name"] = "You"
	gs.settings["show_fps"] = false
	gs.apply_settings()
	root.add_child(load("res://scenes/%s.tscn" % which).instantiate())
	for i in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("build/shots")
	root.get_viewport().get_texture().get_image().save_png("build/shots/%s.png" % which)
	print("wrote build/shots/%s.png" % which)
	quit()
