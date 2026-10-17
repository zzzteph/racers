extends SceneTree
## SPEC 142: what a yaw kick of a given size does to a car at racing speed -- peak lateral drift off its
## line and peak heading excursion over the next second, rope target held straight ahead (so this is the
## car's own recovery, not a player's correction).
##   godot --headless --path . --script res://tools/probe_kick.gd

const DT := 1.0 / 60.0


func _init() -> void:
	call_deferred("run")


func run() -> void:
	print("")
	print("hit_object kick px/s   peak drift px   peak heading deg   drift at 1 s px")
	for kick in [0.0, 50.0, 80.0, 110.0]:
		_one(float(kick), 0.0)
	print("")
	quit()


func _one(kick: float, shove: float) -> void:
	for pass_ in 1:
		var c := Car.new()
		c.use_mouse = false
		c.bounds = Rect2(-100000, -100000, 200000, 200000)
		CarRegistry.apply(c, "sport")
		root.add_child(c)
		c.reset_to(Vector2(200, 400), 0.0)
		c.velocity = Vector2(420, 0)
		for k in 30:
			c.physics_step(DT, c.position + Vector2(300, 0))
		var y0 := c.position.y
		c.hit_object(c.position + Vector2(8.5, 9.0), 0.015, 0.0, kick)
		if shove != 0.0:
			c.velocity += Vector2(0, -shove)
		var peak := 0.0
		var peak_h := 0.0
		for k in 60:
			c.physics_step(DT, Vector2(c.position.x + 300.0, y0))
			peak = maxf(peak, absf(c.position.y - y0))
			peak_h = maxf(peak_h, absf(rad_to_deg(c.heading)))
		print("   %5.1f                %5.1f            %5.1f              %5.1f  (ended %s of the line)" % [kick if shove == 0.0 else shove, peak, peak_h, absf(c.position.y - y0), "above" if c.position.y < y0 else "below"])
		c.free()
