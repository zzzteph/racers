@tool
class_name MapProp
extends Node2D
## EVERYTHING THAT STANDS IN A STREET (SPEC 76/80/81): 42 kinds, from a traffic cone to a cement mixer.
##
## Props are NOT solid — only a MapBlock stops a car. A car goes through these, and what happens then is
## the whole point: a cone flies, a crate bursts, a bollard takes a wing off, a gas canister goes up and
## takes whoever is nearby with it. Every kind has a row in `WEIGHT` (how far it shifts, how much speed
## it steals, what it costs in damage, what speed breaks it) and some have a row in `EFFECT` — a slick
## of oil, an explosion — which is what makes a street worth aiming at rather than just driving down.
##
## Everything is drawn, not imported. The game is procedural throughout: a bought sprite would sit wrong
## beside the cars and would drag someone else's licence into the repository. Each kind is built from a
## handful of rectangles, polygons and circles in the same flat-with-a-shadow language as the buildings.
##
## Placing them: FENCE, BARRIER, GARDEN, HEDGE and SCAFFOLD use `size` (drag out the length, rotate the
## node to turn it); everything else has its own size and ignores it.

signal broke(world_pos: Vector2, effect: Dictionary)

enum Kind {
	# --- the original street (SPEC 76/80) ---
	CONE, BIN, PLANTER, TYRES, GARDEN, FENCE, SKIP, PALLETS, CRATES, BARRIER, LAMP, WRECK,
	# --- street furniture (SPEC 81) ---
	BOLLARD,       ## barely moves, takes a wing off
	METER,         ## a parking meter: snaps off, and pays for it
	POSTBOX,       ## heavy, never breaks
	BENCH,         ## slides, then splinters
	SHELTER,       ## a bus shelter: the glass goes everywhere
	PHONEBOX,      ## topples, glass burst
	TRAFFIC_LIGHT, ## a pole that falls across the road
	ROAD_SIGN,     ## flattens instantly, costs nothing
	BIKE_RACK,     ## the bikes scatter
	WALL_BIN,      ## a litter bin: sprays rubbish
	# --- commerce and street life ---
	KIOSK,         ## a newsstand: breaks into panels, and pays
	VENDING,       ## heavy, and it drops a coin when it goes
	STALL,         ## a market stall: awning, crates, produce everywhere
	CAFE,          ## tables and a parasol: chairs fly
	A_BOARD,       ## a pavement sign: flips over the bonnet
	ICE_VAN,       ## an ice cream van: big, immovable, painful
	# --- roadworks and industry ---
	OIL_DRUM,      ## spills a slick that costs grip
	GAS_CANISTER,  ## goes up, and takes the neighbours with it
	PORTALOO,      ## topples and rolls
	SCAFFOLD,      ## collapses into poles that stay
	CABLE_SPOOL,   ## rolls away when hit off centre
	MIXER,         ## a cement mixer: immovable, very painful
	WORK_LAMP,     ## a roadworks lamp: breaks at nothing
	# --- junkyard and derelict ---
	PANEL_PILE,    ## car doors and bonnets, scattered
	ENGINE_BLOCK,  ## immovable. Hitting one is a mistake
	SOFA,          ## dumped, absurd, breaks
	WHITE_GOODS,   ## a fridge or a washer: rolls, dents you
	TROLLEY,       ## a shopping trolley: skitters a long way
	# --- green ---
	TREE,          ## immovable, heavy damage
	HEDGE,         ## soft: slows you, costs nothing, leaves a gap
}

## give   how far a hit shifts it (0 = immovable)
## drag   the share of the car's speed it steals
## hurt   damage to the car, per 100 px/s of impact
## breaks the impact speed above which it comes apart (9999 = never)
const WEIGHT := {
	Kind.CONE: {"give": 1.0, "drag": 0.02, "hurt": 0.0, "breaks": 240.0},
	Kind.BIN: {"give": 0.75, "drag": 0.06, "hurt": 0.4, "breaks": 320.0},
	Kind.PLANTER: {"give": 0.28, "drag": 0.22, "hurt": 2.6, "breaks": 9999.0},
	Kind.TYRES: {"give": 0.5, "drag": 0.12, "hurt": 1.1, "breaks": 9999.0},
	Kind.GARDEN: {"give": 0.0, "drag": 0.0, "hurt": 0.0, "breaks": 9999.0},
	Kind.FENCE: {"give": 0.55, "drag": 0.10, "hurt": 0.5, "breaks": 200.0},
	Kind.SKIP: {"give": 0.12, "drag": 0.34, "hurt": 3.4, "breaks": 9999.0},
	Kind.PALLETS: {"give": 0.85, "drag": 0.08, "hurt": 0.3, "breaks": 210.0},
	Kind.CRATES: {"give": 0.95, "drag": 0.05, "hurt": 0.2, "breaks": 170.0},
	Kind.BARRIER: {"give": 0.7, "drag": 0.09, "hurt": 0.6, "breaks": 260.0},
	Kind.LAMP: {"give": 0.2, "drag": 0.18, "hurt": 2.0, "breaks": 380.0},
	Kind.WRECK: {"give": 0.18, "drag": 0.30, "hurt": 2.8, "breaks": 9999.0},
	Kind.BOLLARD: {"give": 0.10, "drag": 0.20, "hurt": 2.2, "breaks": 9999.0},
	Kind.METER: {"give": 0.35, "drag": 0.10, "hurt": 0.8, "breaks": 220.0},
	Kind.POSTBOX: {"give": 0.14, "drag": 0.26, "hurt": 2.4, "breaks": 9999.0},
	Kind.BENCH: {"give": 0.45, "drag": 0.14, "hurt": 1.0, "breaks": 250.0},
	Kind.SHELTER: {"give": 0.30, "drag": 0.20, "hurt": 1.4, "breaks": 230.0},
	Kind.PHONEBOX: {"give": 0.25, "drag": 0.22, "hurt": 1.6, "breaks": 260.0},
	Kind.TRAFFIC_LIGHT: {"give": 0.16, "drag": 0.24, "hurt": 2.2, "breaks": 300.0},
	Kind.ROAD_SIGN: {"give": 0.9, "drag": 0.03, "hurt": 0.0, "breaks": 120.0},
	Kind.BIKE_RACK: {"give": 0.6, "drag": 0.12, "hurt": 0.7, "breaks": 200.0},
	Kind.WALL_BIN: {"give": 0.8, "drag": 0.05, "hurt": 0.2, "breaks": 150.0},
	Kind.KIOSK: {"give": 0.22, "drag": 0.26, "hurt": 1.8, "breaks": 260.0},
	Kind.VENDING: {"give": 0.30, "drag": 0.20, "hurt": 1.9, "breaks": 300.0},
	Kind.STALL: {"give": 0.65, "drag": 0.12, "hurt": 0.6, "breaks": 190.0},
	Kind.CAFE: {"give": 1.0, "drag": 0.04, "hurt": 0.1, "breaks": 140.0},
	Kind.A_BOARD: {"give": 1.0, "drag": 0.01, "hurt": 0.0, "breaks": 90.0},
	Kind.ICE_VAN: {"give": 0.08, "drag": 0.38, "hurt": 3.6, "breaks": 9999.0},
	Kind.OIL_DRUM: {"give": 0.55, "drag": 0.12, "hurt": 0.9, "breaks": 200.0},
	Kind.GAS_CANISTER: {"give": 0.5, "drag": 0.14, "hurt": 1.0, "breaks": 180.0},
	Kind.PORTALOO: {"give": 0.40, "drag": 0.18, "hurt": 1.3, "breaks": 260.0},
	Kind.SCAFFOLD: {"give": 0.18, "drag": 0.28, "hurt": 2.6, "breaks": 280.0},
	Kind.CABLE_SPOOL: {"give": 0.7, "drag": 0.16, "hurt": 1.2, "breaks": 9999.0},
	Kind.MIXER: {"give": 0.0, "drag": 0.42, "hurt": 4.2, "breaks": 9999.0},
	Kind.WORK_LAMP: {"give": 1.0, "drag": 0.02, "hurt": 0.0, "breaks": 100.0},
	Kind.PANEL_PILE: {"give": 0.8, "drag": 0.08, "hurt": 0.4, "breaks": 200.0},
	Kind.ENGINE_BLOCK: {"give": 0.0, "drag": 0.40, "hurt": 4.0, "breaks": 9999.0},
	Kind.SOFA: {"give": 0.75, "drag": 0.10, "hurt": 0.3, "breaks": 210.0},
	Kind.WHITE_GOODS: {"give": 0.5, "drag": 0.16, "hurt": 1.5, "breaks": 320.0},
	Kind.TROLLEY: {"give": 1.2, "drag": 0.02, "hurt": 0.1, "breaks": 260.0},
	Kind.TREE: {"give": 0.0, "drag": 0.44, "hurt": 4.4, "breaks": 9999.0},
	Kind.HEDGE: {"give": 0.3, "drag": 0.26, "hurt": 0.0, "breaks": 9999.0},
}

## What a thing does BEYOND breaking, when it breaks (SPEC 81). This is what a street is for.
##   points paid to whoever broke it (SPEC 114: the arena's score; nothing reads it since SPEC 140)
##   oil    radius of the slick it leaves -- grip goes, the way a race's oil does
##   boom   radius of the explosion -- everyone inside takes `boom_damage`
const EFFECT := {
	Kind.METER: {"points": 1},
	Kind.VENDING: {"points": 1},
	Kind.KIOSK: {"points": 2},
	Kind.STALL: {"points": 1},
	Kind.OIL_DRUM: {"oil": 54.0},
	Kind.GAS_CANISTER: {"boom": 120.0, "boom_damage": 26.0},
}

## How close the car's middle has to be to touch one.
const TOUCH := 22.0
## How fast a knocked prop slows, and how fast its tumble settles.
const DRAG := 2.6
const SPIN := 5.0
## One prop can only cost a car something this often: without it a car resting against a skip was
## charged the full hit every frame and quietly exploded.
const HIT_COOL := 0.7

const WOOD := Color(0.55, 0.40, 0.24)
const WOOD_DARK := Color(0.40, 0.28, 0.16)
const STEEL := Color(0.46, 0.48, 0.52)
const STEEL_DARK := Color(0.28, 0.30, 0.34)
const RUST := Color(0.52, 0.30, 0.18)
const GLASS := Color(0.62, 0.78, 0.84, 0.55)
const PAINT_RED := Color(0.78, 0.22, 0.20)
const PAINT_BLUE := Color(0.25, 0.40, 0.62)
const LEAF := Color(0.22, 0.44, 0.22)

@export var kind: Kind = Kind.CONE:
	set(v):
		kind = v
		queue_redraw()

## FENCE, BARRIER, GARDEN, HEDGE and SCAFFOLD use this; the rest have their own size.
@export var size: Vector2 = Vector2(90, 70):
	set(v):
		size = Vector2(maxf(v.x, 16.0), maxf(v.y, 8.0))
		queue_redraw()

## Where it has been knocked to, relative to where it was placed. The node's own `position` is never
## touched, so the scene still holds the layout you authored.
var _shift: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _broken := false
var _cool: float = 0.0


func _ready() -> void:
	queue_redraw()


func is_standing() -> bool:
	return not _broken


func world_position() -> Vector2:
	return global_position + _shift


## What this kind does when it breaks: `{}` for most of them.
func effect() -> Dictionary:
	return EFFECT.get(kind, {})


## Hit by a car moving `vel` at `speed`. Returns what it costs the car: `{drag, damage}`, and emits
## `broke` with its effect the moment it comes apart, which is how a coin, a slick or an explosion
## reaches the match.
func knock(from: Vector2, vel: Vector2, speed: float) -> Dictionary:
	var w: Dictionary = WEIGHT[kind]
	if _broken or _cool > 0.0:
		return {"drag": 0.0, "damage": 0.0}
	_cool = HIT_COOL
	var away := world_position() - from
	if away.length_squared() < 1.0:
		away = vel
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	if float(w["give"]) > 0.0:
		_vel += away.normalized() * speed * float(w["give"]) * 0.8 + vel * float(w["give"]) * 0.25
		_spin += signf(away.cross(vel)) * speed * 0.02
		set_process(true)
	if speed > float(w["breaks"]):
		_broken = true
		broke.emit(world_position(), effect())
	return {"drag": speed * float(w["drag"]), "damage": float(w["hurt"]) * speed * 0.01}


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cool = maxf(_cool - delta, 0.0)
	if _vel.length_squared() < 1.0 and absf(_spin) < 0.01:
		if _cool <= 0.0:
			set_process(false)
		return
	_shift += _vel * delta
	_vel = _vel.lerp(Vector2.ZERO, clampf(DRAG * delta, 0.0, 1.0))
	_spin = lerpf(_spin, 0.0, clampf(SPIN * delta, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	draw_set_transform(_shift, _spin * 0.35, Vector2.ONE)
	if _broken:
		_draw_wreckage()
	else:
		_draw_whole()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 16, Color(1, 1, 1, 0.18), 1.0, true)


## A flat shadow under a thing, so it sits ON the road rather than floating over it.
func _shadow(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(2.5, 2.5), r.size), Color(0, 0, 0, 0.30))


func _box(r: Rect2, fill: Color, edge := true) -> void:
	_shadow(r)
	draw_rect(r, fill)
	if edge:
		draw_rect(r, Color(0, 0, 0, 0.22), false, 1.5)


## A post seen from above: a dark disc with a lighter cap.
func _post(at: Vector2, r: float, col: Color) -> void:
	draw_circle(at + Vector2(2, 2), r, Color(0, 0, 0, 0.28))
	draw_circle(at, r, col.darkened(0.3))
	draw_circle(at, r * 0.6, col)


func _draw_whole() -> void:
	match kind:
		# ---------------------------------------------------------------- the original street
		Kind.CONE:
			draw_circle(Vector2(1.5, 1.5), 6.0, Color(0, 0, 0, 0.25))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(6, 6), Vector2(-6, 6)]),
					Color(0.95, 0.42, 0.12))
			draw_line(Vector2(-3.4, 0.6), Vector2(3.4, 0.6), Color(1, 1, 1, 0.85), 2.4)
		Kind.BIN:
			_box(Rect2(-Vector2(8, 9), Vector2(16, 18)), Color(0.24, 0.30, 0.26))
			draw_rect(Rect2(Vector2(-8, -9), Vector2(16, 5)), Color(0.33, 0.40, 0.34))
		Kind.PLANTER:
			_box(Rect2(-Vector2(14, 11), Vector2(28, 22)), Color(0.46, 0.37, 0.29))
			draw_rect(Rect2(-Vector2(11, 8), Vector2(22, 16)), Color(0.33, 0.26, 0.20))
			for i in 3:
				draw_circle(Vector2(-6 + 6 * i, -1), 5.5, LEAF.lightened(0.05 * float(i % 2)))
		Kind.TYRES:
			draw_circle(Vector2(2, 2), 13.0, Color(0, 0, 0, 0.28))
			for i in 3:
				draw_circle(Vector2.ZERO, 13.0 - 3.5 * float(i), Color(0.10, 0.10, 0.11))
				draw_circle(Vector2.ZERO, 9.5 - 3.5 * float(i), Color(0.16, 0.16, 0.17))
		Kind.GARDEN:
			var g := Rect2(-size * 0.5, size)
			draw_rect(g, Color(0.26, 0.46, 0.24))
			draw_rect(g, Color(0.20, 0.38, 0.19), false, 2.0)
			var nx := maxi(int(size.x / 34.0), 1)
			var ny := maxi(int(size.y / 34.0), 1)
			for ix in nx:
				for iy in ny:
					if (ix + iy) % 2 == 1:
						continue
					draw_circle(g.position + Vector2((float(ix) + 0.5) * g.size.x / float(nx),
							(float(iy) + 0.5) * g.size.y / float(ny)), 7.0, LEAF)
		Kind.FENCE:
			var half := size.x * 0.5
			_shadow(Rect2(Vector2(-half, -3), Vector2(size.x, 6)))
			draw_rect(Rect2(Vector2(-half, -2.5), Vector2(size.x, 5)), WOOD_DARK)
			var posts := maxi(int(size.x / 16.0), 2)
			for i in posts + 1:
				var x := -half + size.x * float(i) / float(posts)
				draw_rect(Rect2(Vector2(x - 1.5, -7.0), Vector2(3, 14)), WOOD)
			draw_line(Vector2(-half, -4.5), Vector2(half, -4.5), WOOD, 2.0)
			draw_line(Vector2(-half, 3.5), Vector2(half, 3.5), WOOD, 2.0)
		Kind.SKIP:
			_shadow(Rect2(-Vector2(24, 13), Vector2(48, 26)))
			draw_colored_polygon(PackedVector2Array([
					Vector2(-24, -13), Vector2(24, -13), Vector2(20, 13), Vector2(-20, 13)]), RUST)
			draw_colored_polygon(PackedVector2Array([
					Vector2(-19, -8), Vector2(19, -8), Vector2(16, 8), Vector2(-16, 8)]),
					Color(0.30, 0.20, 0.13))
			for i in 7:
				var a := float(i) * 1.9
				draw_circle(Vector2(cos(a) * 11.0, sin(a * 1.3) * 5.0), 3.0 + float(i % 3),
						Color(0.45, 0.44, 0.42))
		Kind.PALLETS:
			_box(Rect2(-Vector2(16, 12), Vector2(32, 24)), WOOD_DARK)
			for i in 4:
				draw_rect(Rect2(Vector2(-16, -12 + 6.5 * float(i)), Vector2(32, 4.0)), WOOD)
		Kind.CRATES:
			for i in 3:
				var at := Vector2(-6 + 7 * i, -4 + (5 if i == 1 else 0))
				_box(Rect2(at - Vector2(9, 8), Vector2(18, 16)), WOOD)
				draw_rect(Rect2(at - Vector2(6, 5), Vector2(12, 10)), WOOD_DARK)
		Kind.BARRIER:
			var hb := size.x * 0.5
			_shadow(Rect2(Vector2(-hb, -6), Vector2(size.x, 12)))
			var bands := maxi(int(size.x / 18.0), 2)
			for i in bands:
				draw_rect(Rect2(Vector2(-hb + size.x * float(i) / float(bands), -6),
						Vector2(size.x / float(bands), 12)),
						PAINT_RED if i % 2 == 0 else Color(0.92, 0.92, 0.90))
			draw_rect(Rect2(Vector2(-hb, -6), Vector2(size.x, 12)), Color(0, 0, 0, 0.25), false, 1.5)
		Kind.LAMP:
			draw_circle(Vector2(5, 8), 24.0, Color(1.0, 0.93, 0.70, 0.045))
			draw_circle(Vector2(5, 8), 13.0, Color(1.0, 0.93, 0.70, 0.05))
			_post(Vector2.ZERO, 4.5, STEEL)
			draw_rect(Rect2(Vector2(-2, -2), Vector2(14, 4)), STEEL)
			draw_circle(Vector2(13, 0), 4.0, Color(1.0, 0.95, 0.78))
		Kind.WRECK:
			_box(Rect2(-Vector2(21, 11), Vector2(42, 22)), Color(0.38, 0.33, 0.30))
			draw_rect(Rect2(Vector2(-8, -8), Vector2(17, 16)), Color(0.26, 0.24, 0.23))
			draw_rect(Rect2(Vector2(9, -7), Vector2(9, 14)), RUST)
			for corner in [Vector2(-13, -12), Vector2(13, -12), Vector2(-13, 12), Vector2(13, 12)]:
				draw_circle(corner, 4.0, Color(0.20, 0.20, 0.21))
				draw_circle(corner, 2.0, Color(0.45, 0.45, 0.47))

		# ---------------------------------------------------------------- street furniture
		Kind.BOLLARD:
			_post(Vector2.ZERO, 5.5, Color(0.18, 0.19, 0.22))
			draw_arc(Vector2.ZERO, 5.5, 0.0, TAU, 14, Color(0.9, 0.85, 0.3, 0.8), 1.6, true)
		Kind.METER:
			_post(Vector2.ZERO, 3.0, STEEL_DARK)
			_box(Rect2(Vector2(-5, -12), Vector2(10, 12)), Color(0.32, 0.36, 0.40))
			draw_rect(Rect2(Vector2(-3, -10), Vector2(6, 5)), Color(0.75, 0.82, 0.5, 0.9))
		Kind.POSTBOX:
			_box(Rect2(-Vector2(9, 10), Vector2(18, 20)), PAINT_RED)
			draw_rect(Rect2(Vector2(-6, -6), Vector2(12, 3)), Color(0.1, 0.05, 0.05, 0.8))
			draw_circle(Vector2(0, -10), 9.0, PAINT_RED.lightened(0.08))
		Kind.BENCH:
			_shadow(Rect2(-Vector2(22, 7), Vector2(44, 14)))
			for i in 3:
				draw_rect(Rect2(Vector2(-22, -7 + 5.0 * float(i)), Vector2(44, 3.5)), WOOD)
			draw_rect(Rect2(Vector2(-20, -8), Vector2(4, 16)), STEEL_DARK)
			draw_rect(Rect2(Vector2(16, -8), Vector2(4, 16)), STEEL_DARK)
		Kind.SHELTER:
			_shadow(Rect2(-Vector2(32, 14), Vector2(64, 28)))
			draw_rect(Rect2(-Vector2(32, 14), Vector2(64, 28)), GLASS)
			draw_rect(Rect2(-Vector2(32, 14), Vector2(64, 28)), STEEL, false, 2.5)
			draw_line(Vector2(-32, 0), Vector2(32, 0), Color(1, 1, 1, 0.25), 1.5)
			draw_rect(Rect2(Vector2(-30, 6), Vector2(26, 5)), WOOD)
		Kind.PHONEBOX:
			_box(Rect2(-Vector2(10, 10), Vector2(20, 20)), PAINT_RED)
			draw_rect(Rect2(-Vector2(6, 6), Vector2(12, 12)), GLASS)
		Kind.TRAFFIC_LIGHT:
			_post(Vector2.ZERO, 4.0, STEEL_DARK)
			_box(Rect2(Vector2(2, -14), Vector2(9, 24)), Color(0.20, 0.22, 0.24))
			for i in 3:
				draw_circle(Vector2(6.5, -9 + 8.0 * float(i)), 2.6,
						[Color(0.85, 0.2, 0.18), Color(0.9, 0.75, 0.2), Color(0.3, 0.8, 0.35)][i])
		Kind.ROAD_SIGN:
			_post(Vector2.ZERO, 2.5, STEEL)
			draw_circle(Vector2(0, -9), 8.0, Color(0, 0, 0, 0.25))
			draw_circle(Vector2(0, -10), 8.0, Color(0.92, 0.92, 0.90))
			draw_circle(Vector2(0, -10), 8.0, PAINT_RED)
			draw_rect(Rect2(Vector2(-5.5, -11.5), Vector2(11, 3)), Color(0.95, 0.95, 0.93))
		Kind.BIKE_RACK:
			_shadow(Rect2(-Vector2(20, 8), Vector2(40, 16)))
			for i in 3:
				var x := -14.0 + 14.0 * float(i)
				draw_arc(Vector2(x, 0), 7.0, PI, TAU, 10, STEEL, 2.4, true)
				draw_circle(Vector2(x - 5, 4), 4.0, Color(0.15, 0.15, 0.17))
				draw_circle(Vector2(x + 5, 4), 4.0, Color(0.15, 0.15, 0.17))
		Kind.WALL_BIN:
			_box(Rect2(-Vector2(6, 7), Vector2(12, 14)), Color(0.30, 0.33, 0.30))
			draw_rect(Rect2(Vector2(-6, -7), Vector2(12, 3)), Color(0.42, 0.45, 0.42))

		# ---------------------------------------------------------------- commerce
		Kind.KIOSK:
			_box(Rect2(-Vector2(26, 18), Vector2(52, 36)), Color(0.42, 0.34, 0.26))
			draw_rect(Rect2(Vector2(-24, -16), Vector2(48, 14)), Color(0.86, 0.80, 0.42))
			for i in 5:
				draw_rect(Rect2(Vector2(-22 + 9.5 * float(i), 2), Vector2(7, 12)),
						Color(0.90, 0.88, 0.80) if i % 2 == 0 else Color(0.72, 0.68, 0.58))
			draw_rect(Rect2(-Vector2(26, 18), Vector2(52, 36)), Color(0, 0, 0, 0.22), false, 2.0)
		Kind.VENDING:
			_box(Rect2(-Vector2(11, 15), Vector2(22, 30)), PAINT_BLUE)
			draw_rect(Rect2(Vector2(-8, -12), Vector2(11, 20)), Color(0.75, 0.85, 0.9, 0.75))
			for i in 3:
				draw_rect(Rect2(Vector2(-7, -10 + 6.0 * float(i)), Vector2(9, 4)),
						Color(0.9, 0.4, 0.3) if i % 2 == 0 else Color(0.35, 0.7, 0.45))
		Kind.STALL:
			_shadow(Rect2(-Vector2(30, 20), Vector2(60, 40)))
			draw_rect(Rect2(-Vector2(30, 20), Vector2(60, 40)), Color(0.36, 0.30, 0.24))
			for i in 6:
				draw_rect(Rect2(Vector2(-30 + 10.0 * float(i), -20), Vector2(10, 12)),
						PAINT_RED if i % 2 == 0 else Color(0.93, 0.92, 0.88))
			for i in 5:
				var a2 := float(i) * 1.6
				draw_circle(Vector2(cos(a2) * 14.0, 6.0 + sin(a2) * 6.0), 3.4,
						[Color(0.85, 0.35, 0.25), Color(0.9, 0.7, 0.25), LEAF][i % 3])
		Kind.CAFE:
			for i in 2:
				var at2 := Vector2(-10 + 20.0 * float(i), 0)
				draw_circle(at2 + Vector2(2, 2), 9.0, Color(0, 0, 0, 0.22))
				draw_circle(at2, 9.0, Color(0.82, 0.80, 0.74))
				for k in 3:
					var a3 := TAU * float(k) / 3.0 + float(i)
					draw_circle(at2 + Vector2.from_angle(a3) * 13.0, 4.0, STEEL_DARK)
			draw_circle(Vector2(0, -2), 16.0, Color(0.85, 0.35, 0.28, 0.35))
		Kind.A_BOARD:
			_shadow(Rect2(-Vector2(9, 12), Vector2(18, 24)))
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -12), Vector2(9, -12),
					Vector2(6, 12), Vector2(-6, 12)]), Color(0.30, 0.26, 0.22))
			draw_rect(Rect2(Vector2(-6, -8), Vector2(12, 14)), Color(0.88, 0.86, 0.78))
			for i in 3:
				draw_line(Vector2(-4, -5 + 4.0 * float(i)), Vector2(4, -5 + 4.0 * float(i)),
						Color(0.25, 0.22, 0.2, 0.8), 1.2)
		Kind.ICE_VAN:
			_box(Rect2(-Vector2(30, 15), Vector2(60, 30)), Color(0.92, 0.90, 0.86))
			draw_rect(Rect2(Vector2(-30, -15), Vector2(20, 30)), Color(0.80, 0.84, 0.88))
			draw_rect(Rect2(Vector2(-6, -12), Vector2(26, 9)), Color(0.90, 0.45, 0.55))
			draw_circle(Vector2(20, -8), 7.0, Color(0.95, 0.85, 0.75))
			for corner in [Vector2(-18, -16), Vector2(18, -16), Vector2(-18, 16), Vector2(18, 16)]:
				draw_circle(corner, 4.5, Color(0.16, 0.16, 0.18))

		# ---------------------------------------------------------------- roadworks
		Kind.OIL_DRUM:
			draw_circle(Vector2(2, 2), 11.0, Color(0, 0, 0, 0.28))
			draw_circle(Vector2.ZERO, 11.0, Color(0.24, 0.30, 0.24))
			draw_circle(Vector2.ZERO, 7.0, Color(0.32, 0.38, 0.30))
			draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 16, Color(0.12, 0.14, 0.12), 1.6, true)
		Kind.GAS_CANISTER:
			draw_circle(Vector2(2, 2), 10.0, Color(0, 0, 0, 0.28))
			draw_circle(Vector2.ZERO, 10.0, Color(0.86, 0.62, 0.18))
			draw_circle(Vector2.ZERO, 6.0, Color(0.94, 0.74, 0.28))
			draw_rect(Rect2(Vector2(-2.5, -13), Vector2(5, 5)), STEEL_DARK)
			draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 16, Color(0.5, 0.3, 0.05), 1.6, true)
		Kind.PORTALOO:
			_box(Rect2(-Vector2(11, 11), Vector2(22, 22)), Color(0.35, 0.55, 0.42))
			draw_rect(Rect2(Vector2(-8, -8), Vector2(16, 16)), Color(0.42, 0.62, 0.48))
			draw_circle(Vector2(5, 0), 1.8, STEEL_DARK)
		Kind.SCAFFOLD:
			var hs := size.x * 0.5
			_shadow(Rect2(Vector2(-hs, -14), Vector2(size.x, 28)))
			draw_rect(Rect2(Vector2(-hs, -14), Vector2(size.x, 28)), Color(0.30, 0.31, 0.34, 0.5))
			var bays := maxi(int(size.x / 30.0), 2)
			for i in bays + 1:
				var x2 := -hs + size.x * float(i) / float(bays)
				draw_line(Vector2(x2, -14), Vector2(x2, 14), STEEL, 3.0)
			draw_line(Vector2(-hs, -12), Vector2(hs, -12), STEEL, 2.5)
			draw_line(Vector2(-hs, 12), Vector2(hs, 12), STEEL, 2.5)
		Kind.CABLE_SPOOL:
			draw_circle(Vector2(2, 2), 15.0, Color(0, 0, 0, 0.26))
			draw_circle(Vector2.ZERO, 15.0, WOOD_DARK)
			draw_circle(Vector2.ZERO, 11.0, Color(0.20, 0.20, 0.22))
			draw_circle(Vector2.ZERO, 4.0, WOOD)
			for i in 8:
				var a4 := TAU * float(i) / 8.0
				draw_line(Vector2.from_angle(a4) * 11.0, Vector2.from_angle(a4) * 15.0, WOOD, 1.6)
		Kind.MIXER:
			_box(Rect2(-Vector2(20, 14), Vector2(40, 28)), Color(0.55, 0.52, 0.48))
			draw_circle(Vector2(4, 0), 12.0, Color(0.40, 0.38, 0.36))
			draw_circle(Vector2(4, 0), 8.0, Color(0.30, 0.29, 0.28))
			draw_rect(Rect2(Vector2(-20, -5), Vector2(10, 10)), STEEL_DARK)
		Kind.WORK_LAMP:
			draw_circle(Vector2(3, 5), 14.0, Color(1.0, 0.72, 0.25, 0.10))
			_post(Vector2.ZERO, 3.0, STEEL_DARK)
			draw_circle(Vector2(0, -6), 4.5, Color(0.95, 0.62, 0.18))

		# ---------------------------------------------------------------- junkyard
		Kind.PANEL_PILE:
			_shadow(Rect2(-Vector2(18, 12), Vector2(36, 24)))
			for i in 4:
				var a5 := float(i) * 0.7
				draw_colored_polygon(PackedVector2Array([
						Vector2(-16, -8).rotated(a5 * 0.3) + Vector2(float(i) * 2.0, float(i) * 1.5),
						Vector2(14, -6).rotated(a5 * 0.3) + Vector2(float(i) * 2.0, float(i) * 1.5),
						Vector2(12, 8).rotated(a5 * 0.3) + Vector2(float(i) * 2.0, float(i) * 1.5)]),
						[Color(0.45, 0.30, 0.28), Color(0.35, 0.40, 0.45), RUST,
						Color(0.40, 0.42, 0.40)][i])
		Kind.ENGINE_BLOCK:
			_box(Rect2(-Vector2(13, 11), Vector2(26, 22)), Color(0.34, 0.35, 0.38))
			for i in 4:
				draw_rect(Rect2(Vector2(-10 + 5.5 * float(i), -14), Vector2(4, 5)), STEEL_DARK)
			draw_rect(Rect2(Vector2(-8, -6), Vector2(16, 12)), Color(0.26, 0.27, 0.30))
		Kind.SOFA:
			_box(Rect2(-Vector2(22, 12), Vector2(44, 24)), Color(0.45, 0.32, 0.38))
			draw_rect(Rect2(Vector2(-20, -10), Vector2(40, 9)), Color(0.55, 0.40, 0.46))
			draw_rect(Rect2(Vector2(-22, -12), Vector2(6, 24)), Color(0.38, 0.27, 0.32))
			draw_rect(Rect2(Vector2(16, -12), Vector2(6, 24)), Color(0.38, 0.27, 0.32))
		Kind.WHITE_GOODS:
			_box(Rect2(-Vector2(11, 13), Vector2(22, 26)), Color(0.88, 0.88, 0.86))
			draw_circle(Vector2(0, 2), 7.0, Color(0.55, 0.62, 0.66))
			draw_circle(Vector2(0, 2), 4.5, Color(0.30, 0.36, 0.40))
			draw_rect(Rect2(Vector2(-9, -11), Vector2(18, 4)), Color(0.70, 0.71, 0.70))
		Kind.TROLLEY:
			_shadow(Rect2(-Vector2(11, 8), Vector2(22, 16)))
			draw_rect(Rect2(-Vector2(11, 8), Vector2(22, 16)), Color(0.62, 0.64, 0.68, 0.85))
			for i in 4:
				draw_line(Vector2(-9 + 6.0 * float(i), -8), Vector2(-9 + 6.0 * float(i), 8),
						Color(0.75, 0.77, 0.80), 1.4)
			for corner in [Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9)]:
				draw_circle(corner, 2.0, STEEL_DARK)

		# ---------------------------------------------------------------- green
		Kind.TREE:
			draw_circle(Vector2(4, 4), 20.0, Color(0, 0, 0, 0.26))
			draw_circle(Vector2.ZERO, 20.0, LEAF.darkened(0.15))
			draw_circle(Vector2(-4, -4), 14.0, LEAF)
			draw_circle(Vector2(5, 3), 10.0, LEAF.lightened(0.10))
			draw_circle(Vector2.ZERO, 5.0, Color(0.32, 0.22, 0.15))
		Kind.HEDGE:
			var hh := size.x * 0.5
			_shadow(Rect2(Vector2(-hh, -9), Vector2(size.x, 18)))
			draw_rect(Rect2(Vector2(-hh, -9), Vector2(size.x, 18)), LEAF.darkened(0.1))
			var lumps := maxi(int(size.x / 18.0), 2)
			for i in lumps:
				draw_circle(Vector2(-hh + size.x * (float(i) + 0.5) / float(lumps), -2.0), 8.0,
						LEAF.lightened(0.06 * float(i % 3)))


## SPEC 82: what is actually left. The first version was the same ring of little rectangles whatever
## you had hit, which is why it read as placeholder: wood, glass and steel all broke into identical
## confetti, all at the same radius, all the same size.
##
## Now the debris is made of the MATERIAL: planks are long splinters lying along the direction they flew,
## glass is a wide scatter of thin bright triangles, steel is a few big bent pieces, and a bin's contents
## are small round rubbish. Everything lies flat with a shadow under it, in a squashed ellipse rather
## than a ring -- things thrown by a car land in a fan, not in a circle.
func _draw_wreckage() -> void:
	var spec := _debris_spec()
	var mat := String(spec["material"])
	var tint: Color = spec["tint"]
	var count := int(spec["count"])
	var spread := float(spec["spread"])
	for i in count:
		# A fan, not a ring: wider across the direction of travel than along it, and seeded off the
		# index so the same wreck looks the same every frame.
		var a := TAU * (float(i) * 0.61803) + _spin * 0.4
		var r := spread * (0.35 + 0.65 * fposmod(float(i) * 0.37, 1.0))
		var at := Vector2(cos(a) * r * 1.35, sin(a) * r * 0.75)
		var ang := a * 1.7 + float(i)
		var shade: Color = tint.lerp(Color(0, 0, 0, tint.a), 0.10 * float(i % 3))
		match mat:
			"wood":
				# A splinter: long, thin, lying the way it flew.
				var len := 7.0 + 5.0 * fposmod(float(i) * 0.53, 1.0)
				_plank(at, ang, len, 2.2, shade)
			"glass":
				var s := 2.5 + 2.0 * fposmod(float(i) * 0.71, 1.0)
				draw_colored_polygon(PackedVector2Array([
						at + Vector2(0, -s).rotated(ang), at + Vector2(s, s * 0.7).rotated(ang),
						at + Vector2(-s * 0.8, s).rotated(ang)]),
						Color(shade.r, shade.g, shade.b, 0.75))
			"steel":
				_plank(at, ang, 6.0 + 4.0 * fposmod(float(i) * 0.29, 1.0), 3.4, shade)
			"rubbish":
				draw_circle(at + Vector2(1, 1), 2.6, Color(0, 0, 0, 0.22))
				draw_circle(at, 2.6 + float(i % 2), shade)
			_:
				# Panel: a crumpled quad, bigger than the rest.
				var w := 6.0 + 4.0 * fposmod(float(i) * 0.41, 1.0)
				draw_colored_polygon(PackedVector2Array([
						at + Vector2(-w, -w * 0.5).rotated(ang), at + Vector2(w, -w * 0.7).rotated(ang),
						at + Vector2(w * 0.8, w * 0.6).rotated(ang),
						at + Vector2(-w * 0.9, w * 0.4).rotated(ang)]), shade)
	# A scorch where something went up.
	if kind == Kind.GAS_CANISTER:
		draw_circle(Vector2.ZERO, 30.0, Color(0.08, 0.06, 0.05, 0.40))
		draw_circle(Vector2.ZERO, 16.0, Color(0.05, 0.04, 0.04, 0.35))


## One flat piece lying on the road, with its shadow.
func _plank(at: Vector2, ang: float, length: float, width: float, col: Color) -> void:
	var dir := Vector2.from_angle(ang)
	var side := dir.orthogonal() * width * 0.5
	var a1 := at - dir * length * 0.5
	var a2 := at + dir * length * 0.5
	var shadow := Vector2(1.5, 1.5)
	draw_colored_polygon(PackedVector2Array([a1 - side + shadow, a2 - side + shadow,
			a2 + side + shadow, a1 + side + shadow]), Color(0, 0, 0, 0.22))
	draw_colored_polygon(PackedVector2Array([a1 - side, a2 - side, a2 + side, a1 + side]), col)


## What this kind breaks INTO.
func _debris_spec() -> Dictionary:
	match kind:
		Kind.PALLETS, Kind.CRATES, Kind.BENCH, Kind.A_BOARD, Kind.STALL, Kind.KIOSK, Kind.FENCE:
			return {"material": "wood", "tint": WOOD, "count": 11, "spread": 17.0}
		Kind.SHELTER, Kind.PHONEBOX:
			return {"material": "glass", "tint": Color(0.70, 0.85, 0.92), "count": 18, "spread": 26.0}
		Kind.LAMP, Kind.TRAFFIC_LIGHT, Kind.SCAFFOLD, Kind.METER, Kind.BIKE_RACK, Kind.TROLLEY:
			return {"material": "steel", "tint": STEEL, "count": 7, "spread": 18.0}
		Kind.BIN, Kind.WALL_BIN:
			return {"material": "rubbish", "tint": Color(0.52, 0.50, 0.42), "count": 12, "spread": 20.0}
		Kind.VENDING:
			return {"material": "rubbish", "tint": Color(0.75, 0.45, 0.40), "count": 12, "spread": 20.0}
		Kind.OIL_DRUM:
			return {"material": "steel", "tint": Color(0.22, 0.26, 0.22), "count": 8, "spread": 17.0}
		Kind.GAS_CANISTER:
			return {"material": "steel", "tint": Color(0.50, 0.40, 0.22), "count": 10, "spread": 24.0}
		Kind.ROAD_SIGN, Kind.BARRIER, Kind.WORK_LAMP:
			return {"material": "panel", "tint": Color(0.80, 0.36, 0.30), "count": 7, "spread": 16.0}
		Kind.SOFA:
			return {"material": "panel", "tint": Color(0.48, 0.34, 0.40), "count": 9, "spread": 19.0}
		Kind.CAFE, Kind.PORTALOO, Kind.WHITE_GOODS, Kind.PANEL_PILE:
			return {"material": "panel", "tint": Color(0.62, 0.62, 0.60), "count": 8, "spread": 18.0}
	return {"material": "panel", "tint": Color(0.60, 0.45, 0.35), "count": 7, "spread": 15.0}
