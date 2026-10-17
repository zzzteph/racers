class_name Breakables
extends Node2D
## WALLS THAT CAN BE GONE THROUGH (SPEC 124). Everything solid on a circuit until now was permanent: the
## barrier, the buildings, the trees. Destruction therefore only ever happened TO you, and the only
## decision it produced was "try not to crash", which is the decision you were already making.
##
## A breakable is a short wall across a gap that leads somewhere useful. While it stands it is solid, and
## a car bounces off it exactly as it bounces off a building. Hit it hard enough and it goes -- at a
## price: the blow scrubs `SPEED_COST` of the car's speed and counts as a real impact, so the driver who
## opens it arrives on the other side slower than one who went round. The route it opens STAYS open, for
## everybody, for the rest of the race: the cost is paid once by whoever pays it, and after that it is
## part of the circuit.
##
## That is the whole point of the thing. It is a choice with a price and a payoff, it is made once per
## race rather than every lap, and the player who makes it is not the only one who benefits -- which is
## what stops it being a tax on everybody else.
##
## Authoritative online: the machine that owns a car decides that car's hits, and `break_at` is
## broadcast, so a wall is never open on one screen and shut on another. A client that joins late is
## handed the open ones with the rest of the race state.
##
## Pure presentation plus one collision list: `Race` hands the rects to the cars and asks this whether a
## given hit broke anything. Nothing here drives.

signal broken(index: int, at: Vector2)

## How hard a car has to arrive to go through, in px/s of closing speed. Below this it is a wall: a car
## that rolls into one at walking pace bounces, which is what stops a breakable being a doorway.
const BREAK_SPEED := 200.0
## What going through costs: this much of the car's speed, and this much damage.
const SPEED_COST := 0.42
const DAMAGE := 9.0
const WALL := Color(0.52, 0.44, 0.34)
const WALL_EDGE := Color(0.32, 0.26, 0.20)
const CRACK := Color(0.16, 0.13, 0.10, 0.55)
const RUBBLE := Color(0.40, 0.35, 0.28)
const STRIPE := Color(0.92, 0.78, 0.22, 0.85)

## [{rect, open, seed}] -- in the order a track authored them, which is the order the network names them.
var walls: Array = []

var _mesh: ArrayMesh = null


func _ready() -> void:
	z_index = 1
	z_as_relative = false


## Builds the walls for a circuit. `rects` are in world space; a track with none simply has none, which
## is every circuit but the one this is being tried on.
func setup(rects: Array) -> void:
	walls.clear()
	for i in rects.size():
		walls.append({"rect": rects[i] as Rect2, "open": false, "seed": float(i) * 1.7})
	_bake()
	queue_redraw()


## The rects a car must not drive through: the ones still standing. `Race` hands this to every car, and
## hands it again whenever one goes.
func solids() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for w in walls:
		if not bool((w as Dictionary)["open"]):
			out.append((w as Dictionary)["rect"] as Rect2)
	return out


func is_open(index: int) -> bool:
	return index >= 0 and index < walls.size() and bool(walls[index]["open"])


func open_count() -> int:
	var n := 0
	for w in walls:
		if bool((w as Dictionary)["open"]):
			n += 1
	return n


## Did this impact go through a wall? `at` is where the car hit, `closing` how fast it was closing on it.
## Returns the wall's index, or -1. The caller applies the cost -- this only decides.
func hit(at: Vector2, closing: float) -> int:
	if closing < BREAK_SPEED:
		return -1
	for i in walls.size():
		var w: Dictionary = walls[i]
		if bool(w["open"]):
			continue
		if (w["rect"] as Rect2).grow(14.0).has_point(at):
			return i
	return -1


## Opens wall `index`, whatever decided it -- a local hit, or the authority saying so over the network.
## Idempotent, so a duplicated packet cannot open one twice.
func break_at(index: int) -> bool:
	if index < 0 or index >= walls.size() or bool(walls[index]["open"]):
		return false
	walls[index]["open"] = true
	_bake()
	queue_redraw()
	broken.emit(index, (walls[index]["rect"] as Rect2).get_center())
	return true


## Which walls are open, as a bitmask -- the whole state of them in one int for a late joiner.
func to_bits() -> int:
	var bits := 0
	for i in walls.size():
		if bool(walls[i]["open"]):
			bits |= 1 << i
	return bits


func from_bits(bits: int) -> void:
	var changed := false
	for i in walls.size():
		var want := (bits & (1 << i)) != 0
		if want and not bool(walls[i]["open"]):
			walls[i]["open"] = true
			changed = true
	if changed:
		_bake()
		queue_redraw()


# ---------------------------------------------------------------- the look

## One mesh for the lot (SPEC 54), rebuilt only when a wall goes -- which happens at most once per wall
## per race.
func _bake() -> void:
	if walls.is_empty():
		_mesh = null
		return
	var m := MeshPaint.new()
	for w in walls:
		var d: Dictionary = w
		var r: Rect2 = d["rect"]
		if bool(d["open"]):
			# Rubble: what is left, flat on the ground, so the gap reads as "this was knocked through"
			# rather than "there was never anything here".
			var n := 7
			for k in n:
				var t := (float(k) + 0.5) / float(n)
				var along := r.position + r.size * Vector2(t, 0.5)
				var jog := sin(float(k) * 2.3 + float(d["seed"])) * maxf(r.size.y, r.size.x) * 0.35
				var side := Vector2(0.0, jog) if r.size.x >= r.size.y else Vector2(jog, 0.0)
				m.add_circle(along + side, 2.4 + 1.4 * fmod(float(k) * 0.7, 1.0), RUBBLE, 6)
			continue
		m.add_rect(r.grow(1.0), WALL_EDGE)
		m.add_rect(r, WALL)
		# Hazard stripes down its length, so it is read as something placed rather than as scenery.
		var long_ways := r.size.x >= r.size.y
		var span: float = r.size.x if long_ways else r.size.y
		var bands := maxi(int(span / 14.0), 2)
		for k in bands:
			if k % 2 == 1:
				continue
			var t0 := float(k) / float(bands)
			var t1 := float(k + 1) / float(bands)
			var bar := Rect2(r.position + (Vector2(span * t0, 0.0) if long_ways else Vector2(0.0, span * t0)),
					Vector2(span * (t1 - t0), r.size.y) if long_ways else Vector2(r.size.x, span * (t1 - t0)))
			m.add_rect(bar.grow(-1.5), STRIPE)
		# ... and a crack across it: the promise that it can be gone through.
		var mid := r.get_center()
		if long_ways:
			m.add_rect(Rect2(Vector2(mid.x - 1.0, r.position.y), Vector2(2.0, r.size.y)), CRACK)
		else:
			m.add_rect(Rect2(Vector2(r.position.x, mid.y - 1.0), Vector2(r.size.x, 2.0)), CRACK)
	_mesh = m.build()


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)
