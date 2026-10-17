class_name CarEffects
extends Node2D
## Procedural particle effects for the car: tire smoke while the tires slide on asphalt, dust on grass,
## sparks and scrape when the barrier is hit, dirt when the car rolls, and a subtle speed motion cue.
##
## Pure consumer of `Car`'s public API and signals (SPEC 9.C): it never writes to the car, never calls
## `physics_step`, and nothing it does can change the simulation. `Race` drives it explicitly with
## `sample(delta)` once per physics frame (SPEC decision 10.13), so there is no `_process` /
## `_physics_process` here and the hand-stepped tests see exactly what the running game sees.
##
## Everything is drawn with `draw_circle` / `draw_line` in four child canvas items at FIXED z, so the effects
## sit on the right side of the bridge deck and the car: "Under" (z = 3, below the car) carries smoke, dust
## and the speed cue, "Over" (z = 25, above the car) carries sparks and rollover dirt, and "DeckUnder"
## (z = 16) / "DeckOver" (z = 8) are their equivalents for particles born on top of, or underneath, the
## figure-8 bridge deck. Each particle remembers the layer it was born on.
## Particles live in fixed-size pools (`max_puffs` / `max_sparks`); when a pool is full the oldest entry is
## recycled, so the per-frame cost is bounded no matter how long the race lasts.

const UNDER_Z := 3
const OVER_Z := 25
## "Under" z while the car is ON the figure-8 bridge deck. The deck polygon is opaque and sits at
## Track.BRIDGE_DECK_Z = 10, so at the normal UNDER_Z (3) every puff of tire smoke, every dust cloud and
## the speed cue were painted *under the bridge the car was driving on* and were completely invisible.
## 16 keeps the same stacking as on the ground (marks below, effects above, car on top): SkidMarks
## "OnBridge" 15 < 16 < Car.Z_ON_BRIDGE 20.
const ON_DECK_UNDER_Z := 16
## "Over" z while the car is on the figure-8 lower branch, under the bridge deck: still above the car
## (Car.Z_UNDER_BRIDGE = 5) but below the deck (Track.BRIDGE_DECK_Z = 10), so sparks and rollover dirt
## thrown under the bridge are never painted on top of it. `Race` drives this via `set_under_deck()`.
const UNDER_DECK_OVER_Z := 8

const DEFAULT_SEED := 20250917
## Corners per puff (SPEC 54). A dust cloud is a soft blob a few pixels across: eight is plenty, and it is
## a third of the triangles `draw_circle` used to tessellate.
const PUFF_SEGMENTS := 8

## Particle layers. Every particle stores the layer it was BORN on, the way SkidMarks stores `_seg_layer`.
## Moving one node's `z_index` at the deck boundary re-layered the whole live pool retroactively: driving
## off the bridge, 16 puffs of tire smoke still sitting ON the deck jumped from z 16 to z 3 in a single
## frame — the entire cloud the player had just made on the bridge blinked out underneath it — and the
## mirror case lifted approach-road smoke on top of the deck.
const LAYER_GROUND_UNDER := 0     # z = UNDER_Z, below the car
const LAYER_DECK_UNDER := 1       # z = ON_DECK_UNDER_Z, below the car but above the deck
const LAYER_GROUND_OVER := 2      # z = OVER_Z, above everything
const LAYER_UNDER_DECK_OVER := 3  # z = UNDER_DECK_OVER_Z, above the car but below the deck
const LAYER_COUNT := 4

# --- emission shaping (the four @export values below are the contract; these are private detail) ---
const SMOKE_MIN_LOAD := 0.45        # load_ratio a sliding wheel needs before it smokes
const SMOKE_LIFE := 0.55            # s, at zero drift intensity
const SMOKE_LIFE_GAIN := 0.45       # s, added at full drift intensity
const DUST_LIFE := 0.50
const SPARK_LIFE := 0.25
const ROLL_DUST_LIFE := 0.85
const PUFF_DRAG := 2.6              # 1/s, exponential
const SPARK_DRAG := 7.0             # 1/s, exponential
const MAX_SPAWN_PER_WHEEL := 3      # hard per-frame limit so a hitch cannot burst the pool
## s a wheel may fail its emit test before its part-spawned puff is thrown away. `is_sliding` is
## `saturation >= slide_threshold`, and `saturation` mixes in the brake/drive demand, so through a real
## drift it flickers on and off from frame to frame. Zeroing the accumulator on every off frame meant a
## wheel emitting at ~9 puffs/s (one puff per 7 frames) practically never reached a whole puff: a measured
## 20 s race with 4.4 s of drifting spawned exactly ONE. Holding the fraction across a short gap emits at
## the honest average rate instead. Same trick, same reason, as SkidMarks.STREAK_GRACE.
const EMIT_GRACE := 0.12
## Lateral saturation at which a wheel of a DRIFTING car smokes even when the combined-saturation
## `is_sliding` test has not tripped. Deliberately the same number as `SkidMarks.mark_min_lat_sat`, so the
## smoke and the skid marks have one shared threshold: where the car paints rubber, it smokes.
const DRIFT_SMOKE_SAT := 0.45
const SPEED_CUE_FRACTION := 0.8     # of car.max_speed, where the motion streaks start
## `Car.get_roll_height()` above which the wheels are treated as off the ground (no smoke, no dust).
const AIRBORNE_HEIGHT := 0.15
const SMOKE_COLOR := Color(0.86, 0.86, 0.90)
const DUST_COLOR := Color(0.58, 0.45, 0.27)
const SPARK_COLOR := Color(1.0, 0.82, 0.35)
const SCRAPE_COLOR := Color(0.75, 0.72, 0.70)
const SAND_COLOR := Color(0.88, 0.78, 0.52)
## SPEC 90: the two stages of engine smoke. White is "hurt", black is "dying".
const WHITE_SMOKE_COLOR := Color(0.86, 0.86, 0.84)
const BLACK_SMOKE_COLOR := Color(0.16, 0.15, 0.15)
const DAMAGE_SMOKE_COLOR := Color(0.16, 0.15, 0.15)
const FIRE_COLORS := [Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.12), Color(0.9, 0.2, 0.05)]
## A wreck burning while it waits to respawn: flames and a column of black smoke over a charred husk.
const BURN_FIRE_RATE := 22.0        # flame puffs/s
const BURN_SMOKE_RATE := 10.0       # smoke puffs/s
const HUSK_COLOR := Color(0.07, 0.06, 0.06)
const HUSK_EMBER_COLOR := Color(0.55, 0.16, 0.05)
const SCORCH_COLOR := Color(0.0, 0.0, 0.0, 0.38)

@export var max_puffs: int = 90             # hard cap on live smoke/dust puffs (oldest recycled)
@export var smoke_rate: float = 26.0        # puffs/s per sliding wheel at full drift intensity
@export var dust_rate: float = 18.0         # puffs/s per wheel on grass, scaled by speed
@export var spark_count: int = 10           # streaks per barrier impact (scaled by force)
@export var max_sparks: int = 48            # hard cap on live spark streaks
var _burn_left: float = 0.0
var _burn_pos: Vector2 = Vector2.ZERO
var _burn_heading: float = 0.0
var _burn_acc: Vector2 = Vector2.ZERO       # fractional flame / smoke puffs owed
var _burn_layer: int = LAYER_GROUND_UNDER

var car: Car
## SPEC 59 -- bought cosmetics, worn by the player's car only: "flames" (a burner out of the exhaust),
## "stars" (a sparkle trail), "underglow" (a coloured pool under the car), "smoke" (coloured tyre smoke).
## Race sets this from the profile; it changes nothing but the picture.
var cosmetics: PackedStringArray = PackedStringArray()
var cosmetic_tint: Color = Color(0.35, 0.75, 1.0)
## SPEC 144: "when you use effects, they are not visible in the main game". They were drawn -- as 2-4 px
## puffs that died in 0.22 s, 1-2 px stars and a pool at 4-10 % alpha on dark asphalt; measured in a 3x
## crop round the car at 268 px/s, the flames were two orange dots and the glow read as the shadow. And
## "smoke" was never applied at all: the drift smoke was grey whatever had been bought. A cosmetic that
## cannot be seen in a race is a cosmetic nobody buys twice.
const FLAME_RATE := 70.0             # puffs/s at full speed: a tongue of fire, not a dot
const FLAME_LIFE := 0.30
const STAR_RATE := 22.0
const STAR_LIFE := 1.1
const GLOW_RADIUS := 30.0
const GLOW_ALPHA := 0.42             # of the car's own colour, lightened; was 0.04-0.10 and invisible
var _cosmetic_acc: Vector2 = Vector2.ZERO

var _layers: Array[Node2D] = [null, null, null, null]
## The mesh each layer is currently drawing (SPEC 54). It MUST be held: `draw_mesh` only records a
## reference, so a mesh built as a local in `_draw` is freed the moment the function returns and the
## layer draws nothing -- which is where the dust, the sparks and the explosion went.
## Perf round: one mesh and one painter per layer, REUSED -- a rebuild is a buffer upload, not a new
## RenderingServer object plus the freeing of the old one, four times per car per redraw.
var _layer_mesh: Array[ArrayMesh] = [null, null, null, null]
var _layer_paint: Array[MeshPaint] = [null, null, null, null]
## Which layers hold anything now, and which drew something at their last redraw (an emptied layer
## needs exactly one more redraw, to clear). Only those are redrawn; on a circuit without a bridge two
## of the four never are.
var _layer_live := PackedByteArray([0, 0, 0, 0])
var _layer_dirty := PackedByteArray([0, 0, 0, 0])
## Raised by the physics tick, flushed once per drawn frame from `_process`: a `queue_redraw` issued
## from a tick paints in that tick's own flush, so at two or three ticks a frame every particle layer
## was tessellated two or three times for one picture.
var _redraw_pending: bool = false
var _rng := RandomNumberGenerator.new()

# --- puff pool (parallel arrays, sized once; swap-remove keeps slots 0.._puff_count-1 live) ---
var _p_pos := PackedVector2Array()
var _p_vel := PackedVector2Array()
var _p_radius := PackedFloat32Array()
var _p_grow := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_life_max := PackedFloat32Array()
var _p_color := PackedColorArray()
var _p_layer := PackedByteArray()
var _p_birth := PackedFloat32Array()
var _puff_count: int = 0

# --- spark pool ---
var _s_pos := PackedVector2Array()
var _s_vel := PackedVector2Array()
var _s_life := PackedFloat32Array()
var _s_life_max := PackedFloat32Array()
var _s_color := PackedColorArray()
var _s_layer := PackedByteArray()
var _s_birth := PackedFloat32Array()
var _spark_count: int = 0

var _smoke_accum := PackedFloat32Array()
var _dust_accum := PackedFloat32Array()
## s of grace left on each wheel's smoke / dust accumulator (see EMIT_GRACE).
var _smoke_grace := PackedFloat32Array()
var _dust_grace := PackedFloat32Array()
var _shake: Vector2 = Vector2.ZERO
var _spawn_seq: float = 0.0
var _damage_smoke_accum: float = 0.0
var _charge_accum: float = 0.0              # SPEC 110: the drift charge's sparks owed
var _speed_cue: float = 0.0         # 0..1, drawn strength of the motion streaks
var _under_deck: bool = false       # car is on the lower branch, beneath the bridge deck
var _on_deck: bool = false          # car is on the upper branch, on top of the bridge deck


func _init() -> void:
	_rng.seed = DEFAULT_SEED
	_ensure_pools()


func _ready() -> void:
	_build_layers()


## Attaches the car this node draws effects for and builds the "Under"/"Over" canvas items.
## Safe to call before or after the node enters the tree.
func set_car(c: Car) -> void:
	car = c
	_ensure_pools()
	_build_layers()
	clear()


## Deterministic stream for tests; also resets nothing else (call clear() for that).
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## True while a live car is attached; every entry point is a no-op without one.
func _has_car() -> bool:
	return car != null and is_instance_valid(car)


func _ensure_pools() -> void:
	var puffs := maxi(max_puffs, 1)
	if _p_pos.size() != puffs:
		_p_pos.resize(puffs)
		_p_vel.resize(puffs)
		_p_radius.resize(puffs)
		_p_grow.resize(puffs)
		_p_life.resize(puffs)
		_p_life_max.resize(puffs)
		_p_color.resize(puffs)
		_p_layer.resize(puffs)
		_p_birth.resize(puffs)
		_puff_count = mini(_puff_count, puffs)
	var sparks := maxi(max_sparks, 1)
	if _s_pos.size() != sparks:
		_s_pos.resize(sparks)
		_s_vel.resize(sparks)
		_s_life.resize(sparks)
		_s_life_max.resize(sparks)
		_s_color.resize(sparks)
		_s_layer.resize(sparks)
		_s_birth.resize(sparks)
		_spark_count = mini(_spark_count, sparks)
	if _smoke_accum.size() != 4 or _smoke_grace.size() != 4:
		_smoke_accum.resize(4)
		_dust_accum.resize(4)
		_smoke_grace.resize(4)
		_dust_grace.resize(4)


func _build_layers() -> void:
	if _layers[LAYER_GROUND_UNDER] == null:
		_layers[LAYER_GROUND_UNDER] = _make_layer("Under", UNDER_Z, LAYER_GROUND_UNDER)
	if _layers[LAYER_DECK_UNDER] == null:
		_layers[LAYER_DECK_UNDER] = _make_layer("DeckUnder", ON_DECK_UNDER_Z, LAYER_DECK_UNDER)
	if _layers[LAYER_GROUND_OVER] == null:
		_layers[LAYER_GROUND_OVER] = _make_layer("Over", OVER_Z, LAYER_GROUND_OVER)
	if _layers[LAYER_UNDER_DECK_OVER] == null:
		_layers[LAYER_UNDER_DECK_OVER] = _make_layer("DeckOver", UNDER_DECK_OVER_Z, LAYER_UNDER_DECK_OVER)


## Keeps the effects on the car's side of the bridge deck: while the car is under the bridge, particles born
## now go on the layer that sits below the deck, so nothing is painted on top of a bridge the car is driving
## beneath. Pure presentation — it never touches the car or the simulation, and it never re-layers particles
## that were born somewhere else.
func set_under_deck(under: bool) -> void:
	_under_deck = under


func is_under_deck() -> bool:
	return _under_deck


## The mirror of [method set_under_deck]: while the car is driving ON the deck its smoke and dust must be
## lifted above the opaque deck polygon, or they are simply not drawn. Driven by Race._update_bridge_layer()
## from the same `Track.is_car_on_deck()` query that sets the car's own raised look, so the two can never
## disagree. Pure presentation — it never touches the car.
func set_on_deck(on_deck: bool) -> void:
	_on_deck = on_deck


func is_on_deck() -> bool:
	return _on_deck


## z a particle born NOW would be drawn at (the layers themselves never move).
func get_over_z() -> int:
	return UNDER_DECK_OVER_Z if _under_deck else OVER_Z


func get_under_z() -> int:
	return ON_DECK_UNDER_Z if _on_deck else UNDER_Z


## Layer a particle born now belongs to.
func _birth_layer(over: bool) -> int:
	if over:
		return LAYER_UNDER_DECK_OVER if _under_deck else LAYER_GROUND_OVER
	return LAYER_DECK_UNDER if _on_deck else LAYER_GROUND_UNDER


func _make_layer(layer_name: String, z: int, index: int) -> Node2D:
	var layer := FxLayer.new()
	layer.name = layer_name
	layer.draw_fn = func(target: Node2D) -> void: _draw_layer(target, index)
	layer.top_level = true
	layer.z_as_relative = false
	layer.z_index = z
	add_child(layer)
	return layer


# ---------------------------------------------------------------- per-frame update

## One frame of effects. Called by `Race` right after `skid_marks.sample(delta)`.
## Moves and ages every live particle, then emits new ones from the car's current wheel states.
func sample(delta: float) -> void:
	if not _has_car() or delta <= 0.0:
		return
	_shake = car.get_shake_offset()
	_spawn_seq += delta
	_age_particles(delta)
	if _burn_left > 0.0:
		_emit_burn(delta)
	if not car.is_locked():
		_emit_cosmetics(delta)
		_emit(delta)
		_emit_damage_smoke(delta)
		_emit_tyre_smoke(delta)
		_emit_charge_sparks(delta)
		if car.is_boosting():
			_emit_boost_flame(delta)
		if car.tyres_enabled and car.get_burst_count() > 0:
			_emit_rims(delta)
	_update_speed_cue()
	_refresh()


func _age_particles(delta: float) -> void:
	var puff_damp := exp(-PUFF_DRAG * delta)
	var i := 0
	while i < _puff_count:
		var life := _p_life[i] - delta
		if life <= 0.0:
			_puff_count -= 1
			_swap_puff(i, _puff_count)
			continue
		_p_life[i] = life
		_p_pos[i] = _p_pos[i] + _p_vel[i] * delta
		_p_vel[i] = _p_vel[i] * puff_damp
		_p_radius[i] = _p_radius[i] + _p_grow[i] * delta
		i += 1

	var spark_damp := exp(-SPARK_DRAG * delta)
	i = 0
	while i < _spark_count:
		var slife := _s_life[i] - delta
		if slife <= 0.0:
			_spark_count -= 1
			_swap_spark(i, _spark_count)
			continue
		_s_life[i] = slife
		_s_pos[i] = _s_pos[i] + _s_vel[i] * delta
		_s_vel[i] = _s_vel[i] * spark_damp
		i += 1


func _emit(delta: float) -> void:
	var wheels := car.get_wheel_states()
	if wheels.is_empty():
		return
	var speed := car.get_speed()
	var intensity := clampf(car.drift_intensity(), 0.0, 1.0)
	var car_pos := car.position
	var over_layer := car.is_rolling()
	var drifting := car.is_drifting()
	if car.get_roll_height() > AIRBORNE_HEIGHT:
		# The car is in the air mid barrel roll. `Car` keeps solving the tires there (the marks and effects
		# still want the geometry), but the wheels are not touching anything, so they must not smoke. The
		# rollover dust burst comes from the `rollover_started` signal instead.
		for i in _smoke_accum.size():
			_smoke_accum[i] = 0.0
			_dust_accum[i] = 0.0
			_smoke_grace[i] = 0.0
			_dust_grace[i] = 0.0
		return
	for idx in wheels.size():
		var w: Dictionary = wheels[idx]
		var wi := int(w.get("index", idx))
		if wi < 0 or wi > 3:
			continue
		var pos: Vector2 = w.get("position", car_pos)
		var load_ratio := float(w.get("load_ratio", 1.0))
		var slip := float(w.get("slip_speed", 0.0))
		var sliding := bool(w.get("is_sliding", false))
		# A drifting car smokes from the wheels that are laying rubber, not only from the ones that pass
		# `is_sliding`. `is_sliding` needs the COMBINED saturation past `slide_threshold` (0.90), which a
		# committed drift on a fast bend reaches only in flashes: a measured clean circle race drifted for
		# 123 frames and spawned 3 puffs. `lat_saturation >= DRIFT_SMOKE_SAT` is the same test the marks
		# use (SkidMarks.mark_min_lat_sat), so smoke now rises exactly where black rubber is being laid.
		var smoking: bool = sliding or (drifting
				and float(w.get("lat_saturation", 0.0)) >= DRIFT_SMOKE_SAT)
		var on_grass := String(w.get("surface", "asphalt")) == "grass"

		if on_grass:
			# Dust follows the wheel whenever it is moving over grass, and doubles when it slides.
			var sp := clampf(speed / 260.0, 0.0, 1.0)
			if sp > 0.05:
				var rate := dust_rate * sp * (1.6 if sliding else 1.0) * clampf(load_ratio, 0.2, 1.6)
				_dust_grace[wi] = EMIT_GRACE
				_dust_accum[wi] = _dust_accum[wi] + rate * delta
				var n := mini(int(_dust_accum[wi]), MAX_SPAWN_PER_WHEEL)
				_dust_accum[wi] = _dust_accum[wi] - float(n)
				for k in n:
					_spawn_dust(pos, car_pos, sp, sliding, over_layer)
			else:
				_hold_or_clear_dust(wi, delta)
			_hold_or_clear_smoke(wi, delta)
		elif smoking and load_ratio >= SMOKE_MIN_LOAD:
			# "Heavy load and slipping" on asphalt: white tire smoke, thicker the harder the slide.
			var slip_f := clampf(slip / 220.0, 0.25, 1.0)
			var load_f := clampf(load_ratio * 0.8, 0.3, 1.4)
			var rate2 := smoke_rate * (0.35 + 0.65 * intensity) * slip_f * load_f
			_smoke_grace[wi] = EMIT_GRACE
			_smoke_accum[wi] = _smoke_accum[wi] + rate2 * delta
			var n2 := mini(int(_smoke_accum[wi]), MAX_SPAWN_PER_WHEEL)
			_smoke_accum[wi] = _smoke_accum[wi] - float(n2)
			for k in n2:
				_spawn_smoke(pos, car_pos, intensity, slip_f, over_layer)
			_hold_or_clear_dust(wi, delta)
		else:
			_hold_or_clear_smoke(wi, delta)
			_hold_or_clear_dust(wi, delta)


## A wheel that stopped qualifying keeps its part-spawned puff for EMIT_GRACE, then loses it. The fraction
## is always < 1, so nothing is ever emitted by the hold itself: it only stops a one-frame gap in a
## flickering slide from throwing away the work of the frames around it. (Two near-identical functions
## rather than one taking the arrays: PackedFloat32Array is a value type, so a helper would write to a
## copy and silently do nothing.)
func _hold_or_clear_smoke(wi: int, delta: float) -> void:
	if _smoke_grace[wi] > 0.0:
		_smoke_grace[wi] = maxf(_smoke_grace[wi] - delta, 0.0)
		if _smoke_grace[wi] > 0.0:
			return
	_smoke_accum[wi] = 0.0


func _hold_or_clear_dust(wi: int, delta: float) -> void:
	if _dust_grace[wi] > 0.0:
		_dust_grace[wi] = maxf(_dust_grace[wi] - delta, 0.0)
		if _dust_grace[wi] > 0.0:
			return
	_dust_accum[wi] = 0.0


func _update_speed_cue() -> void:
	var top := maxf(car.max_speed, 1.0)
	var start := top * SPEED_CUE_FRACTION
	var cue := 0.0
	if not car.is_rolling() and car.get_speed() > start:
		cue = clampf((car.get_speed() - start) / maxf(top - start, 1.0), 0.0, 1.0)
	_speed_cue = cue


## Marks for redraw the layers that hold something now and the ones that held something at their last
## draw (they need one more, to clear); the draw itself is issued from `_process`.
func _refresh() -> void:
	var has := PackedByteArray([0, 0, 0, 0])
	for i in _puff_count:
		has[_p_layer[i]] = 1
	for i in _spark_count:
		has[_s_layer[i]] = 1
	if _speed_cue > 0.0 or (_has_car() and cosmetics.has("underglow")):
		has[_birth_layer(false)] = 1
	if _burn_left > 0.0:
		has[_burn_layer] = 1
	for l in LAYER_COUNT:
		if has[l] != 0 or _layer_live[l] != 0:
			_layer_dirty[l] = 1
			_redraw_pending = true
		_layer_live[l] = has[l]


## Every layer, whatever it holds (a clear).
func _redraw_layers() -> void:
	for l in LAYER_COUNT:
		_layer_dirty[l] = 1
		_layer_live[l] = 0
	_redraw_pending = true


func _process(_delta: float) -> void:
	if not _redraw_pending:
		return
	_redraw_pending = false
	for l in LAYER_COUNT:
		if _layer_dirty[l] == 0:
			continue
		_layer_dirty[l] = 0
		var layer := _layers[l]
		if layer != null and is_instance_valid(layer):
			layer.queue_redraw()


# ---------------------------------------------------------------- signal handlers

## Car.rollover_started -> a burst of dirt/smoke thrown out around the car, scaled by severity.
func on_rollover_started(severity: float) -> void:
	if not _has_car():
		return
	_ensure_pools()
	var s := clampf(severity, 0.0, 1.0)
	var grass := car.get_surface() != "asphalt"
	var n := 10 + int(round(18.0 * s))
	for i in n:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		var pos: Vector2 = car.position + dir * _rng.randf_range(4.0, 20.0)
		var vel := dir * _rng.randf_range(40.0, 130.0) * (0.6 + 0.8 * s) + Vector2(0.0, -_rng.randf_range(10.0, 45.0))
		var col := DUST_COLOR if grass else SMOKE_COLOR.lerp(DUST_COLOR, 0.25)
		_spawn_puff(pos, vel, _rng.randf_range(3.0, 6.5), _rng.randf_range(18.0, 34.0),
				ROLL_DUST_LIFE * _rng.randf_range(0.7, 1.15), col, 0.55 + 0.25 * s, true)


## Car.rollover_recovered -> a small settling puff as the car drops back onto its wheels.
func on_rollover_recovered() -> void:
	if not _has_car():
		return
	_ensure_pools()
	var grass := car.get_surface() != "asphalt"
	var col := DUST_COLOR if grass else SMOKE_COLOR.lerp(DUST_COLOR, 0.35)
	for i in 6:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_puff(car.position + dir * _rng.randf_range(2.0, 14.0), dir * _rng.randf_range(20.0, 60.0),
				_rng.randf_range(2.5, 5.0), 22.0, 0.45, col, 0.4, true)


## Car.hard_impact -> sparks along the barrier the car just hit, plus a grey scrape puff.
## `force` is the px/s of velocity the bounds clamp removed.
func on_hard_impact(force: float) -> void:
	if not _has_car():
		return
	_ensure_pools()
	var f := clampf(force / 320.0, 0.15, 1.0)
	var normal := _barrier_normal()
	var contact := _barrier_contact(normal)
	var tangent := normal.orthogonal()
	var along := tangent.dot(car.velocity)
	if along < 0.0:
		tangent = -tangent
	var n := maxi(3, int(round(float(spark_count) * (0.35 + 0.65 * f))))
	for i in n:
		var spread := _rng.randf_range(-0.9, 0.9)
		var dir := (normal * _rng.randf_range(0.25, 1.0) + tangent * spread).normalized()
		var speed := _rng.randf_range(90.0, 260.0) * (0.5 + 0.7 * f)
		_spawn_spark(contact + tangent * _rng.randf_range(-10.0, 10.0), dir * speed,
				SPARK_LIFE * _rng.randf_range(0.6, 1.2), SPARK_COLOR.lerp(Color(1.0, 1.0, 0.85), _rng.randf()))
	for i in 3:
		_spawn_puff(contact + tangent * _rng.randf_range(-8.0, 8.0),
				normal * _rng.randf_range(15.0, 45.0) * f, _rng.randf_range(2.0, 4.0), 20.0,
				0.35, SCRAPE_COLOR, 0.35 * (0.4 + 0.6 * f), true)


# ---------------------------------------------------------------- pool helpers

func _spawn_smoke(pos: Vector2, car_pos: Vector2, intensity: float, slip_f: float, over: bool) -> void:
	var outward := pos - car_pos
	if outward.length_squared() < 1.0:
		outward = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	else:
		outward = outward.normalized()
	# Drift outward from the car and "up" the screen, so the smoke reads as rising off the tire.
	var vel := outward * _rng.randf_range(18.0, 42.0) * (0.6 + 0.8 * intensity)
	vel += Vector2(_rng.randf_range(-14.0, 14.0), -_rng.randf_range(14.0, 34.0) * (0.7 + 0.6 * intensity))
	var jitter := Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
	var alpha := clampf(0.16 + 0.30 * intensity + 0.12 * slip_f, 0.0, 0.55)
	# SPEC 144: the "smoke" cosmetic -- tyre smoke in the car's own colour, and thicker, so a drift is a
	# coloured cloud. It had been bought and never applied.
	var col := SMOKE_COLOR
	if cosmetics.has("smoke"):
		col = cosmetic_tint.lightened(0.2)
		alpha = clampf(alpha + 0.2, 0.0, 0.8)
	_spawn_puff(pos + jitter, vel, _rng.randf_range(2.2, 3.6) + 2.2 * intensity,
			_rng.randf_range(16.0, 28.0) * (0.8 + 0.6 * intensity),
			(SMOKE_LIFE + SMOKE_LIFE_GAIN * intensity) * _rng.randf_range(0.8, 1.15),
			col, alpha, over)


func _spawn_dust(pos: Vector2, car_pos: Vector2, sp: float, sliding: bool, over: bool) -> void:
	var outward := pos - car_pos
	outward = Vector2.from_angle(_rng.randf_range(0.0, TAU)) if outward.length_squared() < 1.0 else outward.normalized()
	var vel := outward * _rng.randf_range(10.0, 30.0) * (0.5 + sp)
	vel += Vector2(_rng.randf_range(-18.0, 18.0), -_rng.randf_range(6.0, 22.0))
	if car.get_speed() > 1.0:
		vel -= car.velocity.normalized() * _rng.randf_range(10.0, 40.0) * sp
	var alpha := clampf(0.18 + 0.30 * sp + (0.12 if sliding else 0.0), 0.0, 0.55)
	_spawn_puff(pos + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0)), vel,
			_rng.randf_range(1.8, 3.4) + 1.6 * sp, _rng.randf_range(12.0, 24.0),
			DUST_LIFE * _rng.randf_range(0.75, 1.2),
			SAND_COLOR if car.get_surface() == "sand" else DUST_COLOR, alpha, over)


## Adds one puff; when the pool is full the oldest live puff is recycled.
## The bought effects (SPEC 59). Flames come out of the exhaust under power, stars fall behind the car
## as it moves; the underglow is drawn, not spawned.
func _emit_cosmetics(delta: float) -> void:
	if cosmetics.is_empty():
		return
	var speed := car.get_speed()
	var fwd := Vector2.from_angle(car.heading)
	var pace := clampf(speed / maxf(car.max_speed, 1.0), 0.0, 1.0)
	if cosmetics.has("flames") and speed > 60.0:
		# A burner out of the exhaust: a bright core that shrinks as it streams back, red at the tips,
		# longer and hotter the faster the car goes. Drawn OVER the car's layer so the body never hides
		# the root of it.
		_cosmetic_acc.x += FLAME_RATE * delta * clampf(pace, 0.35, 1.0)
		while _cosmetic_acc.x >= 1.0:
			_cosmetic_acc.x -= 1.0
			var at: Vector2 = car.position - fwd * 19.0 + fwd.orthogonal() * _rng.randf_range(-3.0, 3.0)
			var tip := _rng.randf()
			var col: Color = FIRE_COLORS[0] if tip < 0.4 else (FIRE_COLORS[1] if tip < 0.8 else FIRE_COLORS[2])
			# It travels WITH the car (most of the car's velocity), falling back only 40-110 px/s, so the
			# tongue is a car-length long and dense -- receding at 300 px/s it was sparse dots.
			_spawn_puff(at, car.velocity * 0.82 - fwd * _rng.randf_range(40.0, 110.0) * (0.6 + 0.6 * pace),
					_rng.randf_range(4.0, 7.0) * (0.8 + 0.4 * pace), -12.0, FLAME_LIFE * _rng.randf_range(0.7, 1.1),
					col, 0.95, true)
	if cosmetics.has("stars") and speed > 40.0:
		# A sparkle trail: bright, big enough to be stars and not dust, left where the car was and
		# lingering for a second.
		_cosmetic_acc.y += STAR_RATE * delta * clampf(pace, 0.4, 1.0)
		while _cosmetic_acc.y >= 1.0:
			_cosmetic_acc.y -= 1.0
			var star: Vector2 = car.position - fwd * _rng.randf_range(4.0, 20.0) \
					+ fwd.orthogonal() * _rng.randf_range(-13.0, 13.0)
			var warm := _rng.randf() < 0.5
			_spawn_puff(star, Vector2(_rng.randf_range(-10.0, 10.0), -_rng.randf_range(6.0, 18.0)),
					_rng.randf_range(2.4, 4.0), -2.0, STAR_LIFE * _rng.randf_range(0.7, 1.2),
					Color(1.0, 0.96, 0.6) if warm else Color(0.85, 0.95, 1.0), 1.0, true)


func _spawn_puff(pos: Vector2, vel: Vector2, radius: float, grow: float, life: float, color: Color,
		alpha: float, over: bool) -> void:
	var i := _claim_puff_slot()
	_p_pos[i] = pos
	_p_vel[i] = vel
	_p_radius[i] = maxf(radius, 0.5)
	_p_grow[i] = grow
	_p_life[i] = maxf(life, 0.05)
	_p_life_max[i] = maxf(life, 0.05)
	_p_color[i] = Color(color.r, color.g, color.b, clampf(alpha, 0.02, 1.0))
	_p_layer[i] = _birth_layer(over)
	_p_birth[i] = _spawn_seq


func _spawn_spark(pos: Vector2, vel: Vector2, life: float, color: Color) -> void:
	var i := _claim_spark_slot()
	_s_pos[i] = pos
	_s_vel[i] = vel
	_s_life[i] = maxf(life, 0.05)
	_s_life_max[i] = maxf(life, 0.05)
	_s_color[i] = color
	_s_layer[i] = _birth_layer(true)
	_s_birth[i] = _spawn_seq


func _claim_puff_slot() -> int:
	var cap := _p_pos.size()
	if _puff_count < cap:
		_puff_count += 1
		return _puff_count - 1
	var oldest := 0
	var best := _p_birth[0]
	for i in range(1, cap):
		if _p_birth[i] < best:
			best = _p_birth[i]
			oldest = i
	return oldest


func _claim_spark_slot() -> int:
	var cap := _s_pos.size()
	if _spark_count < cap:
		_spark_count += 1
		return _spark_count - 1
	var oldest := 0
	var best := _s_birth[0]
	for i in range(1, cap):
		if _s_birth[i] < best:
			best = _s_birth[i]
			oldest = i
	return oldest


func _swap_puff(a: int, b: int) -> void:
	if a == b:
		return
	var pos := _p_pos[a]
	_p_pos[a] = _p_pos[b]
	_p_pos[b] = pos
	var vel := _p_vel[a]
	_p_vel[a] = _p_vel[b]
	_p_vel[b] = vel
	var r := _p_radius[a]
	_p_radius[a] = _p_radius[b]
	_p_radius[b] = r
	var g := _p_grow[a]
	_p_grow[a] = _p_grow[b]
	_p_grow[b] = g
	var l := _p_life[a]
	_p_life[a] = _p_life[b]
	_p_life[b] = l
	var lm := _p_life_max[a]
	_p_life_max[a] = _p_life_max[b]
	_p_life_max[b] = lm
	var c := _p_color[a]
	_p_color[a] = _p_color[b]
	_p_color[b] = c
	var o := _p_layer[a]
	_p_layer[a] = _p_layer[b]
	_p_layer[b] = o
	var bt := _p_birth[a]
	_p_birth[a] = _p_birth[b]
	_p_birth[b] = bt


func _swap_spark(a: int, b: int) -> void:
	if a == b:
		return
	var pos := _s_pos[a]
	_s_pos[a] = _s_pos[b]
	_s_pos[b] = pos
	var vel := _s_vel[a]
	_s_vel[a] = _s_vel[b]
	_s_vel[b] = vel
	var l := _s_life[a]
	_s_life[a] = _s_life[b]
	_s_life[b] = l
	var lm := _s_life_max[a]
	_s_life_max[a] = _s_life_max[b]
	_s_life_max[b] = lm
	var c := _s_color[a]
	_s_color[a] = _s_color[b]
	_s_color[b] = c
	var sl := _s_layer[a]
	_s_layer[a] = _s_layer[b]
	_s_layer[b] = sl
	var bt := _s_birth[a]
	_s_birth[a] = _s_birth[b]
	_s_birth[b] = bt


# ---------------------------------------------------------------- queries

func get_puff_count() -> int:
	return _puff_count


func get_spark_count() -> int:
	return _spark_count


## Live puffs per birth layer (LAYER_GROUND_UNDER, LAYER_DECK_UNDER, LAYER_GROUND_OVER,
## LAYER_UNDER_DECK_OVER). Debug/test accessor: it is what proves a particle keeps the layer it was born on
## when the car crosses a deck boundary.
func get_layer_puff_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(LAYER_COUNT)
	for i in _puff_count:
		var l := int(_p_layer[i])
		if l >= 0 and l < LAYER_COUNT:
			out[l] += 1
	return out


## Drops every live particle and redraws both layers.
func clear() -> void:
	_puff_count = 0
	_spark_count = 0
	_speed_cue = 0.0
	_shake = Vector2.ZERO
	for i in _smoke_accum.size():
		_smoke_accum[i] = 0.0
		_dust_accum[i] = 0.0
		_smoke_grace[i] = 0.0
		_dust_grace[i] = 0.0
	_redraw_layers()


# ---------------------------------------------------------------- barrier geometry

## Inward unit normal of the barrier the car is closest to (SPEC 1.2: bounds grown by -screen_margin).
func _barrier_normal() -> Vector2:
	var inner := car.bounds.grow(-car.screen_margin)
	var p := car.position
	var left := absf(p.x - inner.position.x)
	var right := absf(inner.end.x - p.x)
	var top := absf(p.y - inner.position.y)
	var bottom := absf(inner.end.y - p.y)
	var best := left
	var normal := Vector2.RIGHT
	if right < best:
		best = right
		normal = Vector2.LEFT
	if top < best:
		best = top
		normal = Vector2.DOWN
	if bottom < best:
		normal = Vector2.UP
	return normal


func _barrier_contact(normal: Vector2) -> Vector2:
	var inner := car.bounds.grow(-car.screen_margin)
	var p := car.position
	if normal == Vector2.RIGHT:
		return Vector2(inner.position.x, p.y)
	if normal == Vector2.LEFT:
		return Vector2(inner.end.x, p.y)
	if normal == Vector2.DOWN:
		return Vector2(p.x, inner.position.y)
	return Vector2(p.x, inner.end.y)


# ---------------------------------------------------------------- drawing

## One of the four fixed layers. Each particle is drawn by the layer it was BORN on, so nothing jumps sides
## of the bridge deck when the car crosses it.
func _draw_layer(target: Node2D, index: int) -> void:
	if _shake != Vector2.ZERO:
		target.draw_set_transform(_shake, 0.0, Vector2.ONE)
	# The speed cue follows the car itself, so it belongs on whichever under-layer the car is on now.
	if index == _birth_layer(false):
		_draw_speed_cue(target)
		if cosmetics.has("underglow") and _has_car():
			# SPEC 59/144: a neon pool under the car in its own colour -- soft-edged (four rings, the
			# inner ones brighter), a little longer than it is wide, brighter the faster it goes.
			var lit := 0.7 + 0.3 * clampf(car.get_speed() / maxf(car.max_speed, 1.0), 0.0, 1.0)
			var tint := cosmetic_tint.lightened(0.15)
			for ring in 4:
				var r := GLOW_RADIUS * (1.0 - 0.2 * float(ring))
				target.draw_set_transform(car.position + _shake, car.heading, Vector2(1.25, 1.0))
				target.draw_circle(Vector2.ZERO, r, Color(tint.r, tint.g, tint.b, GLOW_ALPHA * lit * 0.32))
			target.draw_set_transform(_shake, 0.0, Vector2.ONE)
	if _burn_left > 0.0 and index == _burn_layer:
		_draw_husk(target)
	# SPEC 54: every live puff and spark on this layer in ONE mesh. A car crossing the grass can have 90
	# dust puffs alive, and there are five cars: that was ~450 `draw_circle` calls a frame, which is where
	# the frame rate went on a weak GPU ("the biggest drop is when the car is on the grass with clouds").
	var paint := _layer_paint[index]
	if paint == null:
		paint = MeshPaint.new()
		_layer_paint[index] = paint
	paint.reset()
	for i in _puff_count:
		if int(_p_layer[i]) != index:
			continue
		var pf := clampf(_p_life[i] / _p_life_max[i], 0.0, 1.0)
		var pcol := _p_color[i]
		pcol.a = pcol.a * pf * pf
		paint.add_circle(_p_pos[i], _p_radius[i], pcol, PUFF_SEGMENTS)
	for i in _spark_count:
		if int(_s_layer[i]) != index:
			continue
		var f := clampf(_s_life[i] / _s_life_max[i], 0.0, 1.0)
		var v := _s_vel[i]
		var tail := v * 0.035
		if tail.length_squared() < 4.0:
			tail = Vector2(2.0, 0.0)
		var col := _s_color[i]
		col.a = f
		paint.add_line(_s_pos[i], _s_pos[i] - tail, lerpf(0.8, 2.0, f), col)
	var mesh := _layer_mesh[index]
	if mesh == null:
		mesh = ArrayMesh.new()
		_layer_mesh[index] = mesh
	if paint.build_into(mesh):
		target.draw_mesh(mesh, null)


## Two short streaks trailing the car above 80 % of max speed — a motion cue, not a particle.
func _draw_speed_cue(layer: Node2D) -> void:
	if _speed_cue <= 0.0 or not _has_car():
		return
	var fwd := Vector2.from_angle(car.heading)
	var right := fwd.orthogonal()
	var t := _speed_cue
	var col := Color(1.0, 1.0, 1.0, 0.08 + 0.16 * t)
	for s in [-1.0, 1.0]:
		var base: Vector2 = car.position - fwd * 20.0 + right * (s * 7.5)
		layer.draw_line(base, base - fwd * (16.0 + 38.0 * t), col, 2.0)


## Child canvas item: a bare Node2D whose _draw defers to a Callable on the owning CarEffects.
class FxLayer extends Node2D:
	var draw_fn: Callable = Callable()

	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)


# ---------------------------------------------------------------- damage and wrecks

## A damaged car smokes (black, thicker with damage) and, badly damaged, flickers with flame. Emits
## nothing -- and draws no random numbers -- while the car is undamaged, so the pipeline stays
## bit-identical for every test that never damages the car.
## SPEC 90: the LADDER (GTA IV's): thin white smoke from 30, thick black from 55, and from 80 the bonnet
## is on fire -- so anyone can read how hurt a car is from across the track, and a wreck is never a
## surprise. It was one grey wisp from 35 that a top-down camera could barely see.
func _emit_damage_smoke(delta: float) -> void:
	var dmg := car.get_engine_damage()          # SPEC 102: the engine's -- a hurt tank drips instead
	if dmg < 30.0:
		_damage_smoke_accum = 0.0
		return
	var black := dmg >= 55.0
	var fire := dmg >= 80.0
	_damage_smoke_accum += delta * lerpf(10.0, 42.0, clampf((dmg - 30.0) / 70.0, 0.0, 1.0))
	var fwd := Vector2.from_angle(car.heading)
	var engine: Vector2 = car.position + fwd * 12.0
	while _damage_smoke_accum >= 1.0:
		_damage_smoke_accum -= 1.0
		var vel := Vector2(_rng.randf_range(-14.0, 14.0), -_rng.randf_range(28.0, 60.0)) - car.velocity * 0.12
		var col := BLACK_SMOKE_COLOR if black else WHITE_SMOKE_COLOR
		var alpha := (0.55 if black else 0.40) + 0.25 * clampf((dmg - 55.0) / 45.0, 0.0, 1.0)
		_spawn_puff(engine + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)), vel,
				_rng.randf_range(3.5, 6.0), _rng.randf_range(22.0, 40.0),
				_rng.randf_range(0.8, 1.4), col, alpha, true)
		if fire and _rng.randf() < 0.85:
			_spawn_puff(engine + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0)),
					vel * 0.35 + Vector2(0.0, -30.0), _rng.randf_range(2.5, 5.0), 14.0, 0.28,
					FIRE_COLORS[_rng.randi_range(0, 2)], 0.9, true)


## SPEC 110: the drift charge as sparks off the rear wheels, in the tier's colour (blue, orange, purple)
## -- the mini-turbo's tell, so the release is timed by eye.
func _emit_charge_sparks(delta: float) -> void:
	var tier := car.boost_tier()
	if tier <= 0 or not car.is_drifting() or car.is_boosting():
		_charge_accum = 0.0
		return
	_charge_accum += delta * (14.0 + 10.0 * float(tier))
	var col: Color = Car.TIER_COLORS[tier]
	var back := -Vector2.from_angle(car.heading)
	while _charge_accum >= 1.0:
		_charge_accum -= 1.0
		var at := car.wheel_world(2 + _rng.randi_range(0, 1))
		_spawn_spark(at, back.rotated(_rng.randf_range(-0.6, 0.6)) * _rng.randf_range(60.0, 160.0),
				SPARK_LIFE * _rng.randf_range(0.5, 1.0), col.lerp(Color.WHITE, _rng.randf() * 0.3))


## The wreck: a fireball, a column of black smoke and a shower of sparks at `pos`.
func explode(pos: Vector2) -> void:
	_ensure_pools()
	for i in 34:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_puff(pos + dir * _rng.randf_range(0.0, 12.0), dir * _rng.randf_range(40.0, 170.0),
				_rng.randf_range(4.0, 8.0), _rng.randf_range(30.0, 60.0), _rng.randf_range(0.35, 0.8),
				FIRE_COLORS[_rng.randi_range(0, 2)], 0.9, true)
	for i in 26:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_puff(pos + dir * _rng.randf_range(4.0, 22.0),
				dir * _rng.randf_range(15.0, 60.0) + Vector2(0.0, -_rng.randf_range(20.0, 50.0)),
				_rng.randf_range(5.0, 9.0), _rng.randf_range(24.0, 40.0), _rng.randf_range(1.2, 2.2),
				DAMAGE_SMOKE_COLOR, 0.7, true)
	for i in 30:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_spark(pos, dir * _rng.randf_range(120.0, 380.0), SPARK_LIFE * _rng.randf_range(1.0, 2.4),
				SPARK_COLOR.lerp(Color(1.0, 0.4, 0.1), _rng.randf()))
	_refresh()


## A wheel on its bare rim (SPEC 45): sparks off the metal on the road and a small fire under the wheel,
## more the faster the car goes.
## SPEC 90: a tyre SMOKES before it goes. From `TYRE_SMOKE_FROM` of its wear a grey wisp trails that
## wheel, thicker as it nears the burst -- the warning that was missing, so a burst is something you
## saw coming and could have eased off for.
const TYRE_SMOKE_FROM := 0.55


func _emit_tyre_smoke(delta: float) -> void:
	var speed := car.get_speed()
	if speed < 30.0:
		return
	var back := -car.velocity.normalized()
	for i in Car.WHEEL_COUNT:
		if car.is_tyre_burst(i):
			continue
		var wear: float = car.get_tyre_wear(i)
		if wear < TYRE_SMOKE_FROM:
			continue
		var heat := clampf((wear - TYRE_SMOKE_FROM) / (1.0 - TYRE_SMOKE_FROM), 0.0, 1.0)
		if _rng.randf() < delta * (6.0 + 22.0 * heat) * clampf(speed / 200.0, 0.3, 1.0):
			var at := car.wheel_world(i)
			_spawn_puff(at + back * 3.0, back * 25.0 + Vector2(_rng.randf_range(-8.0, 8.0), -18.0),
					_rng.randf_range(2.0, 3.5) * (1.0 + heat), _rng.randf_range(10.0, 18.0),
					_rng.randf_range(0.5, 0.9), Color(0.55, 0.55, 0.56), 0.3 + 0.4 * heat, false)


func _emit_rims(delta: float) -> void:
	var speed := car.get_speed()
	if speed < 40.0:
		return
	var f := clampf(speed / maxf(car.max_speed, 1.0), 0.2, 1.0)
	for i in Car.WHEEL_COUNT:
		if not car.is_tyre_burst(i):
			continue
		var at := car.wheel_world(i)
		var back := -car.velocity.normalized()
		for k in maxi(1, int(round(delta * 40.0 * f))):
			_spawn_spark(at, back.rotated(_rng.randf_range(-0.6, 0.6)) * _rng.randf_range(80.0, 220.0) * f + car.velocity * 0.4,
					SPARK_LIFE * _rng.randf_range(0.6, 1.3), SPARK_COLOR.lerp(Color(1.0, 0.45, 0.1), _rng.randf()))
		if _rng.randf() < delta * 14.0 * f:
			_spawn_puff(at + back * 4.0, back * 30.0 + Vector2(0, -20), _rng.randf_range(2.0, 3.5),
					_rng.randf_range(6.0, 10.0), _rng.randf_range(0.2, 0.35), FIRE_COLORS[_rng.randi_range(0, 2)], 0.8, false)


## A tyre bursts: a bang of black rubber shreds and dust at that wheel.
func on_tyre_burst(_index: int, at: Vector2) -> void:
	_ensure_pools()
	for k in 14:
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_puff(at + dir * _rng.randf_range(0.0, 5.0), dir * _rng.randf_range(40.0, 140.0) + car.velocity * 0.3,
				_rng.randf_range(2.0, 4.0), _rng.randf_range(10.0, 20.0), _rng.randf_range(0.4, 0.8),
				Color(0.08, 0.08, 0.08) if k % 2 == 0 else SMOKE_COLOR, 0.8, true)
	for k in 10:
		_spawn_spark(at, Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(100.0, 260.0),
				SPARK_LIFE * 1.5, Color(0.15, 0.15, 0.15))
	_refresh()


## Boost (SPEC 39): a jet of flame out of the back of the car while it lasts.
func _emit_boost_flame(delta: float) -> void:
	var fwd := Vector2.from_angle(car.heading)
	var n := maxi(1, int(round(delta * 70.0)))
	for i in n:
		var at := car.position - fwd * _rng.randf_range(18.0, 22.0) + fwd.orthogonal() * _rng.randf_range(-3.0, 3.0)
		_spawn_puff(at, -fwd * _rng.randf_range(90.0, 160.0) + car.velocity * 0.6, _rng.randf_range(2.5, 4.0),
				_rng.randf_range(4.0, 9.0), _rng.randf_range(0.12, 0.22), FIRE_COLORS[_rng.randi_range(0, 1)],
				0.9, false)


## The wreck left where the car exploded: a charred husk that burns -- flames and a rising column of black
## smoke -- for `duration` s (the wait before the respawn), so it is plain where the car died and that it
## is out for the moment. `stop_burning` (the respawn) clears the husk at once; the smoke already in the
## air drifts away on its own.
func start_burning(pos: Vector2, heading: float, duration: float) -> void:
	_ensure_pools()
	_burn_pos = pos
	_burn_heading = heading
	_burn_left = maxf(duration, 0.0)
	_burn_acc = Vector2.ZERO
	_burn_layer = _birth_layer(false)
	_refresh()


func stop_burning() -> void:
	_burn_left = 0.0
	_refresh()


func is_burning() -> bool:
	return _burn_left > 0.0


func _emit_burn(delta: float) -> void:
	_burn_left = maxf(_burn_left - delta, 0.0)
	_burn_acc += Vector2(BURN_FIRE_RATE, BURN_SMOKE_RATE) * delta
	while _burn_acc.x >= 1.0:
		_burn_acc.x -= 1.0
		var at := _burn_pos + Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-6.0, 6.0)).rotated(_burn_heading)
		_spawn_puff(at, Vector2(_rng.randf_range(-10.0, 10.0), -_rng.randf_range(25.0, 55.0)),
				_rng.randf_range(3.0, 6.0), _rng.randf_range(6.0, 14.0), _rng.randf_range(0.3, 0.55),
				FIRE_COLORS[_rng.randi_range(0, 2)], 0.85, true)
	while _burn_acc.y >= 1.0:
		_burn_acc.y -= 1.0
		var at := _burn_pos + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 0.0))
		_spawn_puff(at, Vector2(_rng.randf_range(-8.0, 14.0), -_rng.randf_range(35.0, 60.0)),
				_rng.randf_range(5.0, 8.0), _rng.randf_range(18.0, 30.0), _rng.randf_range(1.1, 1.7),
				DAMAGE_SMOKE_COLOR, 0.6, true)


## The husk: a scorch mark, the burnt body (the car's footprint, blackened, embers glowing) and wheels.
func _draw_husk(layer: Node2D) -> void:
	layer.draw_circle(_burn_pos, 26.0, SCORCH_COLOR)
	layer.draw_set_transform(_burn_pos + _shake, _burn_heading, Vector2.ONE)
	for w in [Vector2(-11, -9), Vector2(11, -9), Vector2(-11, 9), Vector2(11, 9)]:
		layer.draw_rect(Rect2(w - Vector2(4.5, 2.5), Vector2(9, 5)), Color(0.02, 0.02, 0.02))
	layer.draw_rect(Rect2(-17, -7.5, 34, 15), HUSK_COLOR)
	var glow := 0.55 + 0.45 * sin(_spawn_seq * 9.0)
	layer.draw_rect(Rect2(-6, -4, 12, 8), HUSK_EMBER_COLOR * Color(1, 1, 1, glow))
	layer.draw_set_transform(_shake, 0.0, Vector2.ONE)


## Car-to-car contact: a burst of sparks and a scrape puff at the contact point, scaled by the closing
## speed.
func on_car_contact(point: Vector2, force: float) -> void:
	_ensure_pools()
	var f := clampf(force / 300.0, 0.15, 1.0)
	for i in maxi(4, int(12.0 * f)):
		var dir := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		_spawn_spark(point, dir * _rng.randf_range(80.0, 240.0) * (0.5 + f), SPARK_LIFE * _rng.randf_range(0.6, 1.2),
				SPARK_COLOR.lerp(Color(1.0, 1.0, 0.85), _rng.randf()))
	for i in 3:
		_spawn_puff(point, Vector2(_rng.randf_range(-20.0, 20.0), -_rng.randf_range(10.0, 30.0)),
				_rng.randf_range(2.0, 4.0), 18.0, 0.35, SCRAPE_COLOR, 0.35 * (0.4 + 0.6 * f), true)
	_refresh()
