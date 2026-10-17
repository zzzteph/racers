extends SceneTree
## SPEC 121: WHAT A DRAGGED CAR ACTUALLY DOES, second by second -- height off the ground, over-pull,
## speed and tyre wear, with the cursor held far past the rope's full-throttle length and never let go.
##   godot --headless --path . --script res://tools/probe_drag.gd
##
## Written because flight and tyre wear argue with each other: a tyre in the air is not being scrubbed,
## so "dragging the car bursts a tyre within seconds" (SPEC 45) and "pull too hard and it flies"
## (SPEC 121) cannot both be true unless the car comes back down. This prints the hops.

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(-100000, -100000, 200000, 200000)
	CarRegistry.apply(c, "sport")
	c.rollovers_enabled = false
	c.damage_enabled = false
	c.reset_to(Vector2.ZERO, 0.0)
	root.add_child(c)
	print("")
	print("%6s %6s %8s %8s %7s %7s  %s" % ["s", "air", "overpull", "speed", "wear", "burst", "event"])
	var hops := 0
	var was_air := false
	var burst_at := -1.0
	for k in 60 * 12:
		c.physics_step(DT, c.position + Vector2.from_angle(c.heading) * 900.0)
		var t := float(k + 1) * DT
		var air := c.get_air()
		var up := air > 0.0
		var event := ""
		if up and not was_air:
			hops += 1
			event = "take-off %d" % hops
		elif was_air and not up:
			event = "landing %d" % hops
		was_air = up
		if burst_at < 0.0 and c.get_burst_count() > 0:
			burst_at = t
			event += "  BURST"
		if event != "" or k % 30 == 0:
			print("%6.2f %6.2f %8.2f %8.0f %7.2f %7d  %s" % [t, air, c._overpull, c.get_speed(),
					_worst_wear(c), c.get_burst_count(), event])
	print("")
	print("%d hop(s) in 12 s; first burst at %s" % [hops, "never" if burst_at < 0.0 else "%.1f s" % burst_at])
	quit(0)


func _worst_wear(c: Car) -> float:
	var worst := 0.0
	for i in 4:
		worst = maxf(worst, c.get_tyre_wear(i))
	return worst
