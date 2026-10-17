class_name Dashboard
extends CanvasLayer
## The race bar along the bottom of the race screen -- the ONE place every race readout lives, in the same
## place on every track (the world is drawn above it by Race's camera, so nothing is ever underneath):
##
##   [ SPEED half-circle ][ WHEEL RPM half-circle ][ track / LAP n/N ][ POS ][ lap, total ][ best, record ]
##   [ status: OFF TRACK / DRAGGING / DRIFT, the boost meter and the damage meter ]
##
## A pure consumer of [Car]'s public API: it never writes to the car. Like [SkidMarks] and [CarEffects] it
## has no `_process` of its own -- [Race] calls [method sample] once per physics frame, after
## `car.physics_step()`, so a paused tree freezes it exactly. The race information is pushed in by [Hud]
## (set_track / set_race_info / set_place / set_status). The gearbox, throttle and brake are still
## modelled (the engine sound reads them; the tests pin them), they are just not drawn.
##
## `layer = 9`: below [Hud] (layer 10), so the countdown, the flash and the pause / finish dialogs draw
## over it.

const HEIGHT := 84.0
const RECT := Rect2(0.0, 636.0, 1280.0, 84.0)

## 1 px/s = 0.2 km/h: the Sport tops out at 120 km/h. TrackRegistry.METRES_PER_PX is the same
## scale (0.2 / 3.6), so the speedo and the track lengths agree.
const KMH_PER_PX := 0.2
## Wheel radius in metres, for the wheel rpm readout.
const WHEEL_RADIUS_M := 0.30
## Share of the wheels' limit where the RPM arc turns red.
const RPM_RED_FRACTION := 0.9

## The bar is opaque: nothing of the world is ever under it any more.
const BAR_ALPHA := 0.97
const WELL_ALPHA := 0.94
## The instrument wells: speed gauge, rpm gauge, race information.
const WELLS := [
	Rect2(8.0, 640.0, 148.0, 76.0),
	Rect2(160.0, 640.0, 136.0, 76.0),
	Rect2(304.0, 640.0, 968.0, 76.0),
]
const SPEED_CENTRE := Vector2(82.0, 710.0)
const RPM_CENTRE := Vector2(228.0, 710.0)
const GAUGE_RADIUS := 56.0
const GAUGE_WIDTH := 8.0
const INFO_RECT := Rect2(304.0, 640.0, 968.0, 76.0)
const DAMAGE_BAR := Rect2(1136.0, 692.0, 124.0, 8.0)
## The boost meter (SPEC 39): blue while it charges, pulsing gold when full ("click"), draining orange
## while the boost runs.
const BOOST_BAR := Rect2(1136.0, 668.0, 124.0, 8.0)
## SPEC 63: the damage and boost meters are off -- the car itself shows its damage, and the boost says
## "BOOST: CLICK!" in the status column when it is ready.
const SHOW_METERS := false
const BOOST_CHARGE_COLOR := Color(0.3, 0.7, 1.0)
const BOOST_READY_COLOR := Color(1.0, 0.8, 0.2)
const BOOST_ON_COLOR := Color(1.0, 0.5, 0.15)

## px/s of speed demand above the car's current speed that reads as full throttle.
const THROTTLE_WINDOW := 140.0
## px/s of negative demand that reads as full brake.
const BRAKE_WINDOW := 180.0
## Above this speed, a cursor dropped inside the slack radius IS the brake pedal: full brake.
const SLACK_BRAKE_SPEED := 20.0

const PANEL_COLOR := Color(0.06, 0.07, 0.09)
const CAPTION_COLOR := Color(0.70, 0.75, 0.80)
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.14)
const REDLINE_COLOR := Color(0.95, 0.22, 0.16)
const WARN_COLOR := Color(1.0, 0.55, 0.15)
const CAUTION_COLOR := Color(1.0, 0.84, 0.25)   # SPEC 145: the yellow flag
const DEFAULT_ACCENT := Color(0.35, 0.72, 1.0)
const REDLINE_PULSE_HZ := 8.0
## The accent is drawn on a dark panel next to green grass; an accent that close to the grass in hue and
## value is lifted so the gauges never read green-on-green.
const GRASS_COLOR := Color(0.23, 0.48, 0.2)
const GRASS_HUE_GUARD := 0.075
const GRASS_VALUE_GUARD := 0.30

## Child canvas item whose `_draw` defers to the owning [Dashboard].
class DashCanvas extends Control:
	var dash: Node = null

	func _draw() -> void:
		if dash != null and is_instance_valid(dash):
			dash.draw_strip(self)


var _car: Car = null
var _gearbox := Gearbox.new()
var _accent: Color = DEFAULT_ACCENT

var _canvas: DashCanvas = null
var _speed_label: Label = null
var _rpm_label: Label = null
var _track_label: Label = null
var _lap_label: Label = null
var _pos_label: Label = null
var _times_label: Label = null
var _best_label: Label = null
var _status_label: Label = null

var _speed: float = 0.0
var _speed_kmh: float = 0.0
var _throttle: float = 0.0
var _brake: float = 0.0
var _balance: float = 0.5
var _wheel_rpm: float = 0.0
var _overpull: float = 0.0
var _damage: float = 0.0
var _boost: float = 0.0
var _boost_state: int = 0          # 0 charging, 1 ready, 2 boosting
var _q_boost: int = -1
var _boost_caption: Label = null
var _last_status: Array = [false, "", Color.WHITE]
var _caution: bool = false
var _q_cold: bool = false
var _q_tow: bool = false
var _q_bursts: int = -1
var _held: bool = false
var _time: float = 0.0

# Quantised mirrors of what is drawn: the canvas is redrawn only when one of them moves.
var _q_speed: int = -1
var _q_rpm: int = -1
var _q_damage: int = -1
var _q_pulse: int = -1


func _init() -> void:
	layer = 9
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_canvas = DashCanvas.new()
	_canvas.name = "Strip"
	_canvas.dash = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_canvas)

	_speed_label = _make_label(root, "SpeedLabel", Rect2(SPEED_CENTRE.x - 60, 668, 120, 30), 26)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption(root, "KmhCaption", Rect2(SPEED_CENTRE.x - 40, 696, 80, 14), "km/h")
	_rpm_label = _make_label(root, "RpmLabel", Rect2(RPM_CENTRE.x - 60, 668, 120, 30), 26)
	_rpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption(root, "RpmCaption", Rect2(RPM_CENTRE.x - 40, 696, 80, 14), "wheel rpm")

	# SPEC 63: the race bar is instruments only. The track, the place, the lap, the times, the damage and
	# the boost meter are all either on the board top left or simply not needed at 200 km/h -- they are
	# still built (the API and the tests read them) but they are not drawn.
	_track_label = _make_label(root, "TrackName", Rect2(318, 642, 240, 24), 18)
	_track_label.visible = false
	_track_label.clip_text = true
	_lap_label = _make_label(root, "LapLabel", Rect2(318, 666, 240, 44), 30)
	_lap_label.visible = false
	_caption(root, "PosCaption", Rect2(566, 646, 120, 14), "POSITION").visible = false
	_pos_label = _make_label(root, "PositionLabel", Rect2(566, 660, 120, 50), 34)
	_pos_label.visible = false
	_times_label = _make_label(root, "TimesLabel", Rect2(700, 646, 220, 64), 18)
	_times_label.visible = false
	_best_label = _make_label(root, "BestLabel", Rect2(928, 646, 196, 64), 18)
	_best_label.visible = false
	_status_label = _make_label(root, "StatusLabel", Rect2(1136, 642, 132, 24), 15)
	_status_label.clip_text = true
	# SPEC 63: the boost says what it needs to say in the status column ("BOOST: CLICK!"); the meters and
	# their captions are gone.
	_boost_caption = _caption(root, "BoostCaption", Rect2(1136, 676, 124, 14), "BOOST")
	_boost_caption.visible = false
	_caption(root, "DamageCaption", Rect2(1136, 700, 124, 14), "DAMAGE").visible = false
	set_race_info(1, 1, 0.0, 0.0, INF, INF)
	set_place(0, 0)
	set_status(false, "", Color.WHITE)
	_refresh_labels(true)


## The car whose instruments these are. Only public members are read.
func set_car(c: Car) -> void:
	_car = c
	_gearbox.reset()
	_speed = 0.0
	_speed_kmh = 0.0
	_throttle = 0.0
	_brake = 0.0
	_balance = 0.5
	_time = 0.0
	_refresh_labels(true)


## The track's accent colour tints the bar (hairline, gauges, the track name).
func set_accent(color: Color) -> void:
	_accent = color
	_track_label.add_theme_color_override("font_color", lift_over_grass(color).lightened(0.2))
	_canvas.queue_redraw()


func get_accent() -> Color:
	return _accent


# ---------------------------------------------------------------- race information (pushed by Hud)

func set_track(track_name: String) -> void:
	_track_label.text = track_name


func set_race_info(lap: int, total_laps: int, lap_time: float, total: float, best: float, record: float) -> void:
	_lap_label.text = "LAP %d/%d" % [lap, total_laps]
	_times_label.text = "LAP     %s\nTOTAL  %s" % [_fmt(lap_time), _fmt(total)]
	_best_label.text = "BEST     %s\nRECORD %s" % [_fmt(best), _fmt(record)]


## "P2/5"; 0 shows a dash (a solo race).
func set_place(place: int, field: int) -> void:
	_pos_label.text = "P%d/%d" % [place, field] if place > 0 and field > 1 else "-"


## The tyres are cold below this (SPEC 49): the status column says so, because grip you cannot see is
## grip you cannot plan for.
const COLD_TYRES_BELOW := 0.75
const TOW_COLOR := Color(0.45, 0.85, 1.0)

## The status column: OFF TRACK beats DRAGGING beats FLAT TYRES beats COLD TYRES beats TOW beats the
## drift readout.
func set_status(off_track: bool, drift_text: String, drift_color: Color) -> void:
	_last_status = [off_track, drift_text, drift_color]
	if _caution:
		# SPEC 145: the yellow flag is the one thing everybody on the track is doing right now.
		_status_label.text = "CAUTION"
		_status_label.add_theme_color_override("font_color", CAUTION_COLOR)
	elif off_track:
		_status_label.text = "OFF TRACK"
		_status_label.add_theme_color_override("font_color", WARN_COLOR)
	elif _overpull > 0.02:
		_status_label.text = "DRAGGING"
		_status_label.add_theme_color_override("font_color", REDLINE_COLOR)
	elif _car != null and is_instance_valid(_car) and _car.tyres_enabled and _car.get_burst_count() > 0:
		var nb := _car.get_burst_count()
		_status_label.text = "FLAT TYRE" if nb == 1 else "%d FLAT TYRES" % nb
		_status_label.add_theme_color_override("font_color", REDLINE_COLOR)
	elif _car != null and is_instance_valid(_car) and _car.parts_break and float(_car.worst_part()[1]) < 0.6:
		# SPEC 58: the worst part on the car, so a bent steering rack or a cooked engine is not a mystery.
		var part: Array = _car.worst_part()
		_status_label.text = "%s %d%%" % [String(part[0]).to_upper(), int(float(part[1]) * 100.0)]
		_status_label.add_theme_color_override("font_color",
				REDLINE_COLOR if float(part[1]) < 0.3 else WARN_COLOR)
	elif _car != null and is_instance_valid(_car) and _car.tyre_temp_enabled 			and _car.get_tyre_temp() < COLD_TYRES_BELOW:
		_status_label.text = "COLD TYRES"
		_status_label.add_theme_color_override("font_color", WARN_COLOR)
	elif _car != null and is_instance_valid(_car) and _car.get_slipstream() > 0.25 and drift_text == "":
		_status_label.text = "TOW"
		_status_label.add_theme_color_override("font_color", TOW_COLOR)
	else:
		_status_label.text = drift_text
		_status_label.add_theme_color_override("font_color", drift_color)


## SPEC 145: the yellow flag, up or down. Re-reads the status so the word appears and goes at once.
func set_caution(on: bool) -> void:
	if on == _caution:
		return
	_caution = on
	if _last_status.size() == 3:
		set_status(bool(_last_status[0]), String(_last_status[1]), _last_status[2])


func is_caution() -> bool:
	return _caution


func get_boost_caption() -> String:
	return _boost_caption.text if _boost_caption != null else ""


func get_status_text() -> String:
	return _status_label.text


## The colour that text is shown in, so the HUD's own status line matches (SPEC 69).
func get_status_color() -> Color:
	return _status_label.get_theme_color("font_color")


func get_lap_text() -> String:
	return _lap_label.text


func get_position_text() -> String:
	return _pos_label.text


func get_track_text() -> String:
	return _track_label.text


# ---------------------------------------------------------------- per frame

## One physics frame, called by [Race] AFTER `car.physics_step()`.
func sample(delta: float) -> void:
	delta = maxf(delta, 0.0)
	_time += delta
	var fwd_speed := 0.0
	var throttle := 0.0
	var brake := 0.0
	var held := _held
	if _car != null and is_instance_valid(_car):
		var fwd := Vector2.from_angle(_car.heading)
		fwd_speed = _car.velocity.dot(fwd)
		_speed = _car.get_speed()
		var dist := _car.position.distance_to(_car.get_rope_target())
		# The car owns the rope law (and the off-track crawl cap), so the throttle never reads full while
		# the car is pinned to its crawl speed on the grass.
		# SPEC 130: `get_held_speed()`, not `get_target_speed()` -- the rope's demand passed through the
		# rubber band's slack. Inside that slack the car is neither accelerating nor braking, and a brake
		# needle at two thirds while the car holds a steady speed is the instrument lying about the car.
		var demand := _car.get_held_speed() - fwd_speed
		throttle = clampf(demand / THROTTLE_WINDOW, 0.0, 1.0)
		brake = clampf(-demand / BRAKE_WINDOW, 0.0, 1.0)
		if dist <= _car.slack_radius and _speed > SLACK_BRAKE_SPEED:
			brake = 1.0
			throttle = 0.0
		held = held or _car.is_locked() or _car.is_rolling()
		_balance = _read_axle_balance()
		_damage = _car.get_damage()
		_boost = _car.get_boost_display() if _car.boost_enabled else 0.0
		# The status column is pushed from the race, so anything that changes on its own (a tyre bursting,
		# the tyres coming up to temperature, a tow found or lost) has to re-issue it from here.
		var nb := _car.get_burst_count() if _car.tyres_enabled else 0
		var cold := _car.tyre_temp_enabled and _car.get_tyre_temp() < COLD_TYRES_BELOW
		var towed := _car.get_slipstream() > 0.25
		if nb != _q_bursts or cold != _q_cold or towed != _q_tow:
			_q_bursts = nb
			_q_cold = cold
			_q_tow = towed
			set_status(bool(_last_status[0]), String(_last_status[1]), _last_status[2])
		_boost_state = 2 if _car.is_boosting() else (1 if _car.is_boost_ready() else 0)
	else:
		_speed = 0.0
		_balance = 0.5
	if held:
		# One consistent instrument set: a held car reads 0 km/h, N, idle and no drag (decision 30.7).
		throttle = 0.0
		brake = 0.0
		fwd_speed = 0.0
		_speed = 0.0
	_throttle = throttle
	_brake = brake
	_speed_kmh = _speed * KMH_PER_PX
	_wheel_rpm = wheel_rpm_for(fwd_speed)
	_overpull = 0.0 if held or _car == null or not is_instance_valid(_car) else _car.get_overpull()
	_gearbox.update(delta, fwd_speed, throttle, held)
	_refresh_labels(false)


## Countdown / resume hold / a held car.
func set_held(held: bool) -> void:
	_held = held


func get_rect() -> Rect2:
	return RECT


func gearbox() -> Gearbox:
	return _gearbox


func get_speed_kmh() -> float:
	return _speed_kmh


func get_gear_text() -> String:
	return _gearbox.gear_text()


## ENGINE rpm (the gearbox model). Not drawn; it drives the engine sound.
func get_rpm() -> float:
	return _gearbox.rpm


## Wheel rpm, as drawn.
func get_wheel_rpm() -> float:
	return _wheel_rpm


## 0..~1.5 over-pull of the car, as last sampled (0 while held).
func get_overpull() -> float:
	return _overpull


## Wheel rpm at the car's top speed: the end of the RPM arc.
func get_wheel_rpm_limit() -> float:
	var top := 580.0
	if _car != null and is_instance_valid(_car) and _car.max_speed > 0.0:
		top = _car.max_speed
	return wheel_rpm_for(top)


## Wheel rpm for a road speed in px/s.
static func wheel_rpm_for(speed_px: float) -> float:
	var mps := absf(speed_px) * KMH_PER_PX / 3.6
	return mps / (TAU * WHEEL_RADIUS_M) * 60.0


func get_throttle() -> float:
	return _throttle


func get_brake() -> float:
	return _brake


## Front share of the total axle load, 0..1 (0.5 == neutral).
func get_load_balance() -> float:
	return _balance


## The bar's opacity (constant: it never fades any more).
func get_alpha() -> float:
	return BAR_ALPHA


func get_strip_control() -> Control:
	return _canvas


func _read_axle_balance() -> float:
	if _car.has_method("get_axle_load_balance"):
		return clampf(_car.get_axle_load_balance(), 0.0, 1.0)
	return clampf(0.5 + _car.get_load_transfer().x * 0.5, 0.0, 1.0)


## Rewrites the gauge numbers and dirties the canvas only when a displayed value changes.
func _refresh_labels(force: bool) -> void:
	var dirty := force
	var q_speed := int(round(_speed_kmh))
	if q_speed != _q_speed or force:
		_q_speed = q_speed
		_speed_label.text = str(q_speed)
		dirty = true
	var q_rpm := int(round(_wheel_rpm / 10.0))
	if q_rpm != _q_rpm or force:
		_q_rpm = q_rpm
		_rpm_label.text = str(int(round(_wheel_rpm / 10.0) * 10.0))
		dirty = true
	var q_damage := int(_damage)
	if q_damage != _q_damage or force:
		_q_damage = q_damage
		dirty = true
	var q_boost := int(_boost * 100.0) + 1000 * _boost_state 			+ (int(_time * 6.0) % 2) * 10000 * int(_boost_state == 1)
	if q_boost != _q_boost or force:
		_q_boost = q_boost
		dirty = true
		if _boost_caption != null:
			_boost_caption.text = ["BOOST", "BOOST: CLICK!", "BOOSTING"][_boost_state]
	var q_pulse := int(_time * REDLINE_PULSE_HZ * 4.0) if _overpull > 0.02 else -1
	if q_pulse != _q_pulse or force:
		_q_pulse = q_pulse
		dirty = true
	if dirty and _canvas != null:
		_canvas.queue_redraw()


func _make_label(parent: Control, node_name: String, r: Rect2, font_size: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.position = r.position
	l.size = r.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _caption(parent: Control, node_name: String, r: Rect2, text: String) -> Label:
	var l := _make_label(parent, node_name, r, 11)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", CAPTION_COLOR)
	l.add_theme_constant_override("outline_size", 2)
	return l


# ---------------------------------------------------------------- drawing

func draw_strip(c: CanvasItem) -> void:
	c.draw_rect(RECT, Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b, BAR_ALPHA), true)
	for w in WELLS:
		c.draw_rect(w, Color(0.0, 0.0, 0.0, 0.35), true)
		c.draw_rect(w, Color(1, 1, 1, 0.07), false, 1.0)
	c.draw_rect(Rect2(RECT.position.x, RECT.position.y, RECT.size.x, 2.0), lift_over_grass(_accent), true)
	var top := 580.0
	if _car != null and is_instance_valid(_car) and _car.max_speed > 0.0:
		top = _car.max_speed
	_draw_gauge(c, SPEED_CENTRE, clampf(_speed / top, 0.0, 1.0), lift_over_grass(_accent), false)
	var rpm_f := clampf(_wheel_rpm / maxf(get_wheel_rpm_limit(), 1.0), 0.0, 1.0)
	_draw_gauge(c, RPM_CENTRE, 1.0 if _overpull > 0.02 else rpm_f, lift_over_grass(_accent), true)
	# Boost meter.
	if not SHOW_METERS:
		return
	c.draw_rect(BOOST_BAR, Color(1, 1, 1, 0.10), true)
	var bcol: Color = [BOOST_CHARGE_COLOR, BOOST_READY_COLOR, BOOST_ON_COLOR][_boost_state]
	if _boost_state == 1 and int(_time * 6.0) % 2 == 1:
		bcol = bcol.lightened(0.45)
	if _boost > 0.0:
		c.draw_rect(Rect2(BOOST_BAR.position, Vector2(BOOST_BAR.size.x * clampf(_boost, 0.0, 1.0), BOOST_BAR.size.y)),
				bcol, true)
	# Damage meter under the status column.
	c.draw_rect(DAMAGE_BAR, Color(1, 1, 1, 0.10), true)
	var f := clampf(_damage / 100.0, 0.0, 1.0)
	if f > 0.0:
		var col := Color(0.35, 0.9, 0.3).lerp(Color(1.0, 0.8, 0.1), clampf(f * 2.0, 0.0, 1.0)) \
				.lerp(REDLINE_COLOR, clampf(f * 2.0 - 1.0, 0.0, 1.0))
		c.draw_rect(Rect2(DAMAGE_BAR.position, Vector2(DAMAGE_BAR.size.x * f, DAMAGE_BAR.size.y)), col, true)


## A half-circle gauge (the upper half, left to right). `redzone` gauges turn red past RPM_RED_FRACTION,
## and pulse red all over when full (the over-pull).
func _draw_gauge(c: CanvasItem, centre: Vector2, f: float, col: Color, redzone: bool) -> void:
	var a0 := PI
	var a1 := TAU
	c.draw_arc(centre, GAUGE_RADIUS, a0, a1, 48, TRACK_COLOR, GAUGE_WIDTH, true)
	if redzone:
		c.draw_arc(centre, GAUGE_RADIUS, a0 + PI * RPM_RED_FRACTION, a1, 12,
				Color(REDLINE_COLOR.r, REDLINE_COLOR.g, REDLINE_COLOR.b, 0.35), GAUGE_WIDTH, true)
	for i in range(5):
		var ta := a0 + PI * float(i) / 4.0
		var d := Vector2.from_angle(ta)
		c.draw_line(centre + d * (GAUGE_RADIUS - 12.0), centre + d * (GAUGE_RADIUS - 6.0), Color(1, 1, 1, 0.35), 1.0)
	if f > 0.001:
		var fill := col
		if redzone and f >= RPM_RED_FRACTION:
			fill = REDLINE_COLOR
		if redzone and _overpull > 0.02:
			fill = Color(REDLINE_COLOR.r, REDLINE_COLOR.g, REDLINE_COLOR.b,
					0.55 + 0.45 * sin(_time * TAU * REDLINE_PULSE_HZ))
		c.draw_arc(centre, GAUGE_RADIUS, a0, a0 + PI * f, maxi(4, int(48.0 * f)), fill, GAUGE_WIDTH, true)
	var tip := centre + Vector2.from_angle(a0 + PI * f) * (GAUGE_RADIUS - 4.0)
	c.draw_line(centre + Vector2(0, -2), tip, Color(0, 0, 0, 0.6), 4.0, true)
	c.draw_line(centre + Vector2(0, -2), tip, Color(1.0, 0.97, 0.92), 2.0, true)


## An accent too close to the grass in hue and value, lifted until it is not (circle's and Jeddah's
## accents would otherwise draw green-on-green).
static func lift_over_grass(col: Color) -> Color:
	var dh := absf(col.h - GRASS_COLOR.h)
	dh = minf(dh, 1.0 - dh)
	if dh >= GRASS_HUE_GUARD or absf(col.v - GRASS_COLOR.v) >= GRASS_VALUE_GUARD:
		return col
	return Color.from_hsv(col.h, minf(col.s, 0.62), clampf(GRASS_COLOR.v + GRASS_VALUE_GUARD + 0.18, 0.0, 1.0))


## "m:ss.mmm" (the same format as GameState.format_time, which this file must not reference: it is used
## from `--script` test runs, where the GameState autoload does not exist).
static func _fmt(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "-:--.---"
	var total_ms := int(round(seconds * 1000.0))
	return "%d:%02d.%03d" % [total_ms / 60000, (total_ms / 1000) % 60, total_ms % 1000]
