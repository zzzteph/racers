extends SceneTree
## SPEC 128: DOES THE DAMAGE SHOW? `CarBody` has decided what has broken since SPEC 123 and the physics
## has read it ever since, but nothing told the 3D model -- so a car running on three wheels and a hub
## was still drawn with four round tyres. This walks one car through a corner crash and reads the MODEL
## after each blow: what the player would see, not what the state machine says.
##   godot --headless --path . --script res://tools/probe_visible_damage.gd

const STATES := ["intact", "dented", "loose", "GONE"]


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
	# Headless never builds a model (`_ensure_model` bails on it), so one is fitted here by hand: the
	# probe is checking `Car._sync_model_body`, which is the real path, not a copy of it.
	var model := CarModel3D.new()
	model.name = "Model3D"
	c.add_child(model)
	model.build(c.body_style, c.body_color, c.stripe_color)
	c._model = model
	root.add_child(c)
	await process_frame
	print("")
	print("%-26s %-8s %-8s %6s %6s %7s   %s" % ["moment", "FL body", "FL model", "tyre", "rim",
			"drop", "pieces on the car"])
	_say(c, "showroom")
	var corner: Vector2 = c.position + Vector2(13.0, -9.0)
	for blow in [260.0, 320.0, 380.0, 470.0]:
		c._body_hit(corner, blow)
		c._pose_model(0.0, 0.0, false)
		_say(c, "corner at %d px/s" % int(blow))
	# The nose, which is a panel rather than a wheel: it should come off the picture too.
	for blow in [300.0, 360.0, 460.0]:
		c._body_hit(c.position + Vector2(17.0, 0.0), blow)
	c._pose_model(0.0, 0.0, false)
	_say(c, "and a nose-on")
	c._reset_body()
	c._pose_model(0.0, 0.0, false)
	_say(c, "reset")
	print("")
	quit()


func _say(c: Car, moment: String) -> void:
	var m = c._model
	var body: int = c._body.state(CarBody.WHEEL_FL)
	var model: int = m.wheel_state(CarBody.WHEEL_FL)
	var tyre: bool = (m._tyres[CarBody.WHEEL_FL] as MeshInstance3D).visible
	var rim: bool = (m._rims[CarBody.WHEEL_FL] as MeshInstance3D).visible
	var base: Vector3 = (m._wheels[CarBody.WHEEL_FL] as Node3D).get_meta("base")
	var drop: float = base.y - (m._wheels[CarBody.WHEEL_FL] as Node3D).position.y
	var on := 0
	for ch in m._body_parts.get_children():
		var mi := ch as MeshInstance3D
		if mi != null and mi.visible and not mi.has_meta("inner"):
			on += 1
	print("%-26s %-8s %-8s %6s %6s %7.2f   %d" % [moment, STATES[body], STATES[model], tyre, rim,
			drop, on])
