extends SceneTree
## SPEC 122: why a forced ten-second power slide stops reading as a drift. Reproduces the suite's
## `effects: a drifting car reaches the HUD drift readout` scenario and prints the car's state every
## half second, so the frame it stops drifting can be seen rather than guessed at.
##   godot --headless --path . --script res://tools/probe_drift.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		quit(1)
		return
	gs.settings_path = "user://tool_settings.cfg"
	gs.profile = Profile.new()
	gs.profile.path = "user://tool_profile.cfg"
	gs.selected_track = "serpent"
	gs.set_opponent_count(3)
	var race: Node = load("res://scenes/race.tscn").instantiate()
	root.add_child(race)
	for i in 4:
		await process_frame
	var guard := 0
	while int(race.phase) == 0 and guard < 600:
		race._physics_process(DT)
		guard += 1
	var car: Car = race.car
	car.rollovers_enabled = false
	car.use_mouse = false
	print("")
	print("%6s %8s %8s %8s %8s %8s %8s  %s" % ["s", "drift", "damage", "wrecked", "air", "speed",
			"rear sat", "note"])
	for k in 600:
		car.velocity = Vector2.from_angle(car.heading + 0.9) * 420.0
		car.target_point = car.position + Vector2.from_angle(car.heading).rotated(0.9) * 900.0
		race._physics_process(DT)
		if k % 30 == 0 or k == 599:
			var w: Array = car.get_wheel_states()
			var sat := 0.5 * (float(w[2]["saturation"]) + float(w[3]["saturation"]))
			print("%6.1f %8s %8.1f %8s %8.2f %8.0f %8.2f  %s" % [float(k) * DT, car.is_drifting(),
					car.get_damage(), car.is_wrecked(), car.get_air(), car.get_speed(), sat,
					race.hud.get_drift_text()])
	race.free()
	quit(0)
