extends SceneTree
func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 2600
	gs.profile.buy_part("sport", "slicks")
	var g: Node = load("res://scenes/garage.tscn").instantiate()
	root.add_child(g)
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("build/shots/garage_screen.png")
	print("wrote build/shots/garage_screen.png tab=", g.get_tab())
	quit()
