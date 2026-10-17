extends SceneTree
## SPEC 128: CAN YOU PULL YOURSELF OUT OF THE GRASS? Off the road the car was capped at
## `off_track_max_speed` whatever the rope was doing, and that cap is reached by a rope barely longer
## than the slack radius -- so a 200 px rope and a 900 px rope crawled out at exactly the same speed and
## the one thing a player can do about being off the road did nothing. This drives a car that is off the
## track at a range of rope lengths and prints how far it gets.
##   godot --headless --path . --script res://tools/probe_grass.gd

const DT := 1.0 / 60.0
const SECONDS := 3.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	print("")
	print("%-10s %10s %10s %10s %10s" % ["rope px", "cap px/s", "after 1 s", "after 3 s", "throttle"])
	for rope in [60.0, 120.0, 200.0, 400.0, 650.0, 900.0]:
		_run(rope, false)
	print("")
	print("... and on the road, where nothing has changed:")
	print("%-10s %10s %10s %10s %10s" % ["rope px", "cap px/s", "after 1 s", "after 3 s", "throttle"])
	for rope in [200.0, 900.0]:
		_run(rope, true)
	print("")
	quit()


func _run(rope: float, on_road: bool) -> void:
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(-100000, -100000, 200000, 200000)
	CarRegistry.apply(c, "sport")
	c.rollovers_enabled = false
	c.rope_snap_enabled = false
	c.tyres_enabled = false
	c.set_on_track_provider(func(_p: Vector2) -> bool: return on_road)
	c.reset_to(Vector2.ZERO, 0.0)
	root.add_child(c)
	# The cursor is held `rope` px AHEAD of the car, which is what a player hauling at a stranded car
	# does -- a fixed point would simply be reached, and then every rope length looks the same again.
	var at_one := 0.0
	var t := 0.0
	while t < SECONDS:
		c.physics_step(DT, c.position + Vector2(rope, 0.0))
		t += DT
		if absf(t - 1.0) < DT * 0.5:
			at_one = c.position.x
	print("%-10.0f %10.1f %10.1f %10.1f %9.0f%%" % [rope, c._offroad_cap(), at_one, c.position.x,
			100.0 * c.get_target_speed() / maxf(c.max_speed, 1.0)])
	c.free()
