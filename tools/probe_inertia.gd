extends SceneTree
## SPEC 130: DOES THE CAR CARRY ITS SPEED? "It starts to stop if you are not pulling further" -- the
## rope behaved like a throttle cable wired to a speedometer: every pixel the cursor moved was a new
## speed to chase, so a hand that stopped moving was a hand on the brakes.
##
## Three things a player actually does, each with the car already at speed:
##   * STOP MOVING THE HAND -- the cursor sits still in the world and the car runs up to it;
##   * HOLD THE LENGTH -- the cursor keeps its distance ahead, which should hold the pace;
##   * DROP IT ON THE CAR -- the deliberate brake, which must still stop it.
##   godot --headless --path . --script res://tools/probe_inertia.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	print("")
	print("Up to speed on a long rope, then the hand does this for 3 s:")
	print("")
	print("%-34s %9s %9s %9s" % ["what the hand does", "from", "after 3 s", "px run on"])
	_run("stops moving (cursor stays put)", func(c: Car, _t: float, mark: Vector2) -> Vector2: return mark)
	_run("holds the length (300 px ahead)",
			func(c: Car, _t: float, _m: Vector2) -> Vector2:
				return c.position + Vector2(300.0, 0.0).rotated(c.heading))
	_run("holds it short (120 px ahead)",
			func(c: Car, _t: float, _m: Vector2) -> Vector2:
				return c.position + Vector2(120.0, 0.0).rotated(c.heading))
	_run("drops it on the car (the brake)",
			func(c: Car, _t: float, _m: Vector2) -> Vector2: return c.position)
	print("")
	print("The brake has to still work: the last row must come to a stop.")
	print("")
	quit()


func _run(label: String, hand: Callable) -> void:
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(-200000, -200000, 400000, 400000)
	CarRegistry.apply(c, "sport")
	c.rollovers_enabled = false
	c.rope_snap_enabled = false
	c.reset_to(Vector2.ZERO, 0.0)
	root.add_child(c)
	# Up to speed on a rope that is long but not an over-pull.
	for k in 240:
		c.physics_step(DT, c.position + Vector2(380.0, 0.0).rotated(c.heading))
	var from := c.get_speed()
	var mark := c.position + Vector2(380.0, 0.0).rotated(c.heading)
	var was := c.position
	var t := 0.0
	while t < 3.0:
		c.physics_step(DT, hand.call(c, t, mark))
		t += DT
	print("%-34s %9.0f %9.0f %9.0f" % [label, from, c.get_speed(), was.distance_to(c.position)])
	c.free()
