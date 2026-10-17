extends SceneTree
## SPEC 123: THE DESTRUCTION PROTOTYPE, driven through its acceptance scenario. "A front-corner crash
## deforms that corner and changes handling; a stronger repeat can detach its wheel; reset restores all
## state."
##   godot --headless --path . --script res://tools/probe_destruction.gd

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
	c.rope_snap_enabled = false
	c.reset_to(Vector2.ZERO, 0.0)
	root.add_child(c)
	var thrown := [0]
	c.part_lost.connect(func(_p, _v, _c, _s) -> void: thrown[0] += 1)
	print("")
	print("enabled on the Sport: %s" % c.body_parts_enabled)
	print("")
	print("%-22s %-10s %-10s %-10s %8s %8s %8s" % ["moment", "wing_fl", "wheel_fl", "bumper_f",
			"grip FL", "drag", "pull"])
	_say(c, "showroom")

	# One front-corner crash, at the speed a real shunt happens at.
	var corner := c.position + Vector2(13.0, -9.0).rotated(c.heading)
	c._body_hit(corner, 260.0)
	_say(c, "one corner crash")
	var dented := _outline_shift(c)

	# Two more of the same, harder: the wheel goes.
	c._body_hit(corner, 320.0)
	_say(c, "again")
	c._body_hit(corner, 380.0)
	_say(c, "and again")

	# How it drives now: straight-line speed and how far it wanders in three seconds, hands off.
	var speed_now := _flat_out(c)
	c.repair()
	_say(c, "after repair()")
	var speed_fixed := _flat_out(c)
	print("")
	print("Outline pushed in by %.1f px at the hit corner after one crash." % dented)
	print("Flat out: %.0f px/s on the hub, %.0f px/s repaired (%.0f%% of its pace)."
			% [speed_now, speed_fixed, 100.0 * speed_now / maxf(speed_fixed, 1.0)])
	print("%d pieces thrown." % thrown[0])
	c.free()
	quit(0)


func _say(c: Car, moment: String) -> void:
	var b: CarBody = c.get_body()
	var names := ["intact", "dented", "loose", "GONE"]
	print("%-22s %-10s %-10s %-10s %8.2f %8.2f %8.2f" % [moment,
			names[b.state_of("wing_fl")], names[b.state_of("wheel_fl")], names[b.state_of("bumper_front")],
			b.wheel_grip(0), b.drag(), b.pull()])


## How far the drawn outline has moved at the front-left corner.
func _outline_shift(c: Car) -> float:
	var worst := 0.0
	for p in [Vector2(12.0, -9.0), Vector2(18.0, -5.0)]:
		worst = maxf(worst, c.get_body().dent_at(p))
	return worst


## Flat out in a straight line for six seconds, and what the car is doing at the end of it. The rope is
## a strong enough controller to hide a pull -- it steers the car back onto the cursor every frame -- so
## what a dragging corner costs is measured where it cannot be hidden: the speed.
func _flat_out(c: Car) -> float:
	# NOT `reset_to`: that is a respawn, and a respawn puts every panel and wheel back on (`_reset_body`),
	# which is exactly the state this is trying to measure the car out of.
	c.velocity = Vector2.ZERO
	for k in 360:
		c.physics_step(DT, c.position + Vector2.from_angle(c.heading) * 400.0)
	return c.get_speed()
