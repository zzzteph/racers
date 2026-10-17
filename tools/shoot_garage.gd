extends SceneTree
## Shoots the car screen (the garage) with some coins in the bank, so the parts UI can be looked at.
func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.profile.coins = 5000
	gs.profile.buy_part("sport", "turbo")
	gs.profile.buy_part("sport", "slicks")
	gs.profile.buy_effect("flames")
	gs.selected_car = "gt"          # a car nobody has bought yet: grey, with its price across it
	var scene: PackedScene = load("res://scenes/car_select.tscn")
	root.add_child(scene.instantiate())
	for i in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute("build/shots")
	root.get_viewport().get_texture().get_image().save_png("build/shots/garage.png")
	print("wrote build/shots/garage.png")
	quit()
