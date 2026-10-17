extends SceneTree
## SPEC 128: EVERY WAY THE CAR CAN BE BROKEN, AND WHAT EACH ONE COSTS. The component model started with
## four consequences -- grip, drag, pull, armour -- which is a car that only ever gets slower in the same
## way. Eight more were added, and each has to be a DIFFERENT problem, or it is decoration.
##
## One damaged car per row, everything else identical, driven down the same straight and then through the
## same corner. If a row reads the same as "showroom", that damage does nothing.
##   godot --headless --path . --script res://tools/probe_damage_ladder.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.settings_path = "user://tool_settings.cfg"
	print("")
	print("%-22s %8s %8s %8s %8s %8s %7s" % ["what is broken", "straight", "flat out",
			"wander", "left|right", "FL tyre", "heat"])
	_row("showroom", [])
	_row("a buckled front wheel", [["wheel_fl", 2]])
	_row("a collapsed corner", [["wheel_fl", 3]])
	_row("loose bodywork", [["wing_fl", 2], ["wing_rr", 2], ["bonnet", 2]])
	_row("a wing on the tyre", [["wing_fl", 1]])
	_row("a holed radiator", [["radiator", 3]])
	_row("a hurt drivetrain", [["drivetrain", 3]])
	_row("a bent chassis", [["chassis", 2]])
	_row("a torn rope mount", [["rope_mount", 3]])
	print("")
	print("straight: px covered in 12 s flat out.   flat out: the top speed it can still reach, px/s.")
	print("wander: px off the line after 6 s with the rope held dead ahead.")
	print("left|right: px covered in 6 s round a 300 px circle each way -- a bent chassis turns better")
	print("one way than the other.   FL tyre: front-left wear after the left-hander, 0..1.   heat: 0..1.")
	print("")
	quit()


func _row(label: String, breaks: Array) -> void:
	var straight := _straight(breaks)
	var left := _corner(breaks, 1.0)
	var right := _corner(breaks, -1.0)
	print("%-22s %8.0f %8.0f %8.0f %8s %8.2f %7.2f" % [label, straight[0], straight[1], straight[2],
			"%.0f|%.0f" % [left[0], right[0]], left[1], straight[3]])


func _car(breaks: Array) -> Car:
	var c := Car.new()
	c.use_mouse = false
	c.bounds = Rect2(-100000, -100000, 200000, 200000)
	CarRegistry.apply(c, "sport")
	c.rollovers_enabled = false
	c.rope_snap_enabled = false
	c.reset_to(Vector2.ZERO, 0.0)
	var l: PackedFloat32Array = c._body.load
	for b in breaks:
		var i := CarBody.index_of(String((b as Array)[0]))
		var want := int((b as Array)[1])
		# Just enough load to sit in the wanted state, so each row is the one fault it names.
		var wheel := String(CarBody.PARTS[i]["kind"]) == "wheel"
		var at := [0.0, CarBody.DENT_AT, CarBody.LOOSE_AT,
				CarBody.WHEEL_GONE_AT if wheel else CarBody.GONE_AT]
		l[i] = float(at[want])
	c._body.set_load(l)
	root.add_child(c)
	return c


## Flat out down a straight: how far, how fast, how far off the line it wandered, and how hot it got.
func _straight(breaks: Array) -> Array:
	var c := _car(breaks)
	var t := 0.0
	var top := 0.0
	while t < 12.0:
		# Exactly full throttle and no more: a longer rope is an OVER-PULL, which drags the car past its
		# own top speed and hides every loss of power there is.
		c.physics_step(DT, c.position + Vector2(380.0, 0.0).rotated(c.heading))
		top = maxf(top, c.get_speed())
		t += DT
	var out := [c.position.length(), c._effective_max_speed(), absf(c.position.y), c.engine_heat()]
	c.free()
	return out


## Round a 300 px circle: how far it got, and what it did to the tyres.
func _corner(breaks: Array, way: float) -> Array:
	var c := _car(breaks)
	var middle := Vector2(0.0, 300.0 * way)
	var t := 0.0
	var travelled := 0.0
	var was := c.position
	while t < 6.0:
		c.physics_step(DT, middle + Vector2.from_angle(-PI * 0.5 * way + t * 1.5 * way) * 300.0)
		travelled += was.distance_to(c.position)
		was = c.position
		t += DT
	var out := [travelled, c.get_tyre_wear(CarBody.WHEEL_FL)]
	c.free()
	return out
