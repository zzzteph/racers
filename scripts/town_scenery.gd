class_name TownScenery
extends Node2D
## The ground around the road (SPEC 52, and SPEC 120's second style): blocks of buildings, yards, parks
## and car parks in a TOWN, or trees, copses and rocks in the COUNTRY, filling the ground a big world
## leaves empty ("in empty space you can put trees or something, so it will look not so empty"). Drawn, not driven into -- the barrier is still what stops a car -- so this
## costs nothing but pixels, and it is what turns 2560x1440 of grass into somewhere.
##
## Deterministic: everything comes from one seeded RNG, so every client of an online race and every replay
## of a single-player one sees the same town. Placement is a grid of plots; a plot is dropped if it is not
## comfortably clear of the road (the racing surface is never decorated) or too close to the barrier.
##
## The look is a flat top-down extrusion: the footprint is the wall colour, the roof is the same rectangle
## offset up and left, so the walls show along two sides exactly as they do in a top-down city game. It is
## cheap (a handful of `draw_rect`s per building) and it reads at the close camera's scale.

const Z := 1                        # over the ground, under the skid marks (2) and the props (3)
const PLOT := Vector2(132.0, 116.0) # the grid a town is laid out on: small plots read as a town
const ROAD_CLEAR := 34.0            # px of grass between the road edge and any building
const BARRIER_CLEAR := 8.0
const EMPTY_CHANCE := 0.10          # plots left as bare ground, so the blocks are not a perfect grid
const PARK_CHANCE := 0.13
const LOT_CHANCE := 0.10
## SPEC 120: the COUNTRY style -- copses of trees and rocks rather than buildings, so a circuit has
## something to look at in its middle. Trees come in copses rather than one per plot, which is what
## stops them reading as an orchard.
##
## SPEC 121: BIGGER, FEWER, AND SOLID. "Trees look like acne -- use more real ones, yet low poly, and
## the car should be able to crash in them (they are solid objects)." They were 9-17 px blobs, up to six
## to a plot: at the close camera's scale that is a rash of green dots, not woodland. They are 17-31 px
## now and one to three to a plot, drawn as a faceted crown over a trunk (`_bake_tree`) instead of two
## flat circles -- the same number of trees over the same ground, each of them actually a tree.
##
## And they STOP A CAR. SPEC 120 made them scenery on the argument that a wall in the middle of a
## circuit is a trap; the answer to that is not to make the trees ghosts but to keep them off the racing
## line, which `COUNTRY_CLEAR` does -- 96 px from the road edge, two car widths of grass, so running
## wide costs time long before it costs a tree. What is solid is the TRUNK (`TRUNK_SHARE` of the crown),
## because that is the part of a tree a car actually hits.
const COUNTRY_EMPTY := 0.34
const COUNTRY_ROCK := 0.14
const COUNTRY_CLEAR := 96.0
const TREES_PER_PLOT := Vector2i(1, 3)
const TREE_R := Vector2(17.0, 31.0)
const TRUNK_SHARE := 0.30           # of the crown radius: what a car can hit
const ROCK_SOLID_SHARE := 0.26      # of the plot: a rock is mostly the bit you can see
const TREE_FACETS := 7              # the crown is one low-poly ring of this many points
const TRUNK_COLOR := Color(0.28, 0.20, 0.13)
const TREE_DARK := Color(0.10, 0.24, 0.11)
const ROCK_COLOR := Color(0.44, 0.44, 0.42)
const GRASS_TUFT := Color(0.22, 0.40, 0.20)

const WALLS := [
	Color(0.62, 0.45, 0.36), Color(0.55, 0.52, 0.50), Color(0.48, 0.42, 0.44),
	Color(0.68, 0.58, 0.44), Color(0.42, 0.46, 0.50), Color(0.58, 0.36, 0.32),
]
const ROOF_LIFT := 0.72             # roof colour = wall colour x this (darker up top reads as shade)
const SHADOW := Color(0, 0, 0, 0.20)
const WINDOW := Color(0.92, 0.88, 0.70, 0.75)
const PARK_COLOR := Color(0.20, 0.42, 0.18)
const TREE_COLOR := Color(0.16, 0.34, 0.15)
const LOT_COLOR := Color(0.28, 0.28, 0.30)
const LOT_LINE := Color(0.85, 0.85, 0.80, 0.35)
## A kerb round every plot: without it the blocks sit straight on the grass and the town looks like a
## field with sheds in it.
const PAVEMENT := Color(0.56, 0.56, 0.54)
const PAVEMENT_EDGE := Color(0.44, 0.44, 0.43)
const PAVEMENT_GROW := 8.0

var _items: Array = []              # {kind, rect, color, lift, seed}
## SPEC 54: the town never changes during a race, so it is baked into one mesh (it was ~411 draw calls).
var _mesh: ArrayMesh = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = Z
	z_as_relative = false


## Lays the town out around `track`. Everything is decided here, once; `_draw` only paints it.
func setup(track: Track, seed_value: int = 1, style: String = "town") -> void:
	_items.clear()
	_rng.seed = seed_value
	if style == "country":
		_setup_country(track)
		return
	var world := track.world_size
	var clear := track.track_width * 0.5 + Track.EDGE_BAND + ROAD_CLEAR
	var m := Track.BARRIER_MARGIN + BARRIER_CLEAR
	var cols := int(floor(world.x / PLOT.x))
	var rows := int(floor(world.y / PLOT.y))
	for cx in cols:
		for cy in rows:
			var cell := Rect2(Vector2(cx, cy) * PLOT, PLOT)
			var size := Vector2(_rng.randf_range(0.6, 0.9), _rng.randf_range(0.58, 0.9)) * PLOT
			var at := cell.position + (cell.size - size) * Vector2(_rng.randf(), _rng.randf())
			var plot := Rect2(at, size)
			if plot.position.x < m or plot.position.y < m or plot.end.x > world.x - m or plot.end.y > world.y - m:
				continue
			if not _clear_of_road(track, plot, clear):
				continue
			var roll := _rng.randf()
			if roll < EMPTY_CHANCE:
				continue
			elif roll < EMPTY_CHANCE + PARK_CHANCE:
				_items.append({"kind": "park", "rect": plot, "color": PARK_COLOR, "lift": 0.0,
						"seed": _rng.randf_range(0.0, 100.0)})
			elif roll < EMPTY_CHANCE + PARK_CHANCE + LOT_CHANCE:
				_items.append({"kind": "lot", "rect": plot, "color": LOT_COLOR, "lift": 0.0,
						"seed": _rng.randf_range(0.0, 100.0)})
			else:
				_items.append({"kind": "block", "rect": plot,
						"color": WALLS[_rng.randi_range(0, WALLS.size() - 1)],
						"lift": _rng.randf_range(7.0, 19.0), "seed": _rng.randf_range(0.0, 100.0)})
	_bake()
	queue_redraw()


## SPEC 120: THE COUNTRY. The same grid of plots, but what goes on one is a copse of trees, a rock or
## nothing. This is what fills the middle of the Serpent.
##
## SPEC 121: all of it is SOLID, and all of it is `COUNTRY_CLEAR` back from the road for that reason --
## a tree you can hit has to be somewhere you only reach by getting it wrong.
func _setup_country(track: Track) -> void:
	var world := track.world_size
	var clear := track.track_width * 0.5 + Track.EDGE_BAND + COUNTRY_CLEAR
	var m := Track.BARRIER_MARGIN + BARRIER_CLEAR
	var cols := int(floor(world.x / PLOT.x))
	var rows := int(floor(world.y / PLOT.y))
	for cx in cols:
		for cy in rows:
			var cell := Rect2(Vector2(cx, cy) * PLOT, PLOT)
			var plot := Rect2(cell.position + PLOT * 0.1, PLOT * 0.8)
			if plot.position.x < m or plot.position.y < m or plot.end.x > world.x - m or plot.end.y > world.y - m:
				continue
			if not _clear_of_road(track, plot, clear):
				continue
			var roll := _rng.randf()
			if roll < COUNTRY_EMPTY:
				continue
			if roll < COUNTRY_EMPTY + COUNTRY_ROCK:
				_items.append({"kind": "rock", "rect": plot, "color": ROCK_COLOR, "lift": 0.0,
						"seed": _rng.randf_range(0.0, 100.0)})
				continue
			var n := _rng.randi_range(TREES_PER_PLOT.x, TREES_PER_PLOT.y)
			for i in n:
				var r := _rng.randf_range(TREE_R.x, TREE_R.y)
				var at := plot.position + Vector2(_rng.randf(), _rng.randf()) * plot.size
				_items.append({"kind": "tree", "rect": Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0),
						"color": TREE_COLOR, "lift": r * 0.35, "seed": _rng.randf_range(0.0, 100.0)})
	_bake()
	queue_redraw()


## True when no corner or edge midpoint of the plot is within `clear` px of the road. Sampling the
## outline (not just the centre) is what keeps a corner of a building off the racing surface.
func _clear_of_road(track: Track, plot: Rect2, clear: float) -> bool:
	var pts := [plot.position, Vector2(plot.end.x, plot.position.y), plot.end,
			Vector2(plot.position.x, plot.end.y), plot.get_center(),
			Vector2(plot.get_center().x, plot.position.y), Vector2(plot.get_center().x, plot.end.y),
			Vector2(plot.position.x, plot.get_center().y), Vector2(plot.end.x, plot.get_center().y)]
	for p in pts:
		if track.distance_to_centerline(p) < clear:
			return false
		# SPEC 124: a paved link is road too. A solid tree in the middle of the route a breakable opens
		# would be a trap at the end of a corridor, which is the worst place in the game for one.
		for r in track.links:
			if (r as Rect2).grow(clear).has_point(p):
				return false
	return true


## SPEC 111: the buildings an author placed on a drawn track -- {rect, color, lift}. Added to whatever
## `setup` laid out (or to nothing: a drawn track with no town flag has only these).
func add_blocks(items: Array) -> void:
	for it in items:
		var d: Dictionary = it
		_items.append({"kind": "block", "rect": d.get("rect", Rect2()), "color": d.get("color", WALLS[0]),
				"lift": float(d.get("lift", 12.0)), "seed": _rng.randf_range(0.0, 100.0)})
	_bake()
	queue_redraw()


func get_item_count(kind: String = "") -> int:
	if kind == "":
		return _items.size()
	var n := 0
	for it in _items:
		if String(it["kind"]) == kind:
			n += 1
	return n


## The plots a car cannot drive through (SPEC 53): the buildings. Parks and car parks are flat ground --
## you can cut across them, which is exactly what makes them worth having.
## Everything a car can hit: the buildings, and -- since SPEC 121 -- the trees and the rocks. A tree is
## not a park or a car park, which really are just paint on the ground.
##
## What a tree contributes is its TRUNK, not its crown: the crown is a canopy the car passes under, and
## making the whole 60 px circle solid would have the car stopping a body-length short of the thing it
## hit. The rock gives the part of it that is drawn, for the same reason.
func get_solids() -> Array[Rect2]:
	return solids_of("")


## The same list for one kind of thing, which is how the suite can say "a tree's solid part is its
## trunk" without knowing which rect belongs to what.
func solids_of(kind: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for it in _items:
		var k := String(it["kind"])
		if kind != "" and k != kind:
			continue
		match k:
			"block":
				out.append(it["rect"] as Rect2)
			"tree":
				var r: Rect2 = it["rect"]
				var t := r.size.x * 0.5 * TRUNK_SHARE
				out.append(Rect2(r.get_center() - Vector2(t, t), Vector2(t, t) * 2.0))
			"rock":
				var rr: Rect2 = it["rect"]
				var rs := rr.size.x * ROCK_SOLID_SHARE
				out.append(Rect2(rr.get_center() - Vector2(rs, rs), Vector2(rs, rs) * 2.0))
	return out


## The baked town (SPEC 54), or null when there is nothing in it.
func get_mesh() -> ArrayMesh:
	return _mesh


## Every plot as data, for tests and for anything that wants to know where the town is.
func get_items() -> Array:
	return _items.duplicate(true)


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)


## Everything the town paints, into one mesh (SPEC 54).
func _bake() -> void:
	_mesh = null
	var m := MeshPaint.new()
	# Kerbs first, so neighbouring plots share one continuous pavement where they meet. A tree or a rock
	# has no kerb -- it is standing in a field, not on a street corner (SPEC 120).
	for it in _items:
		var kind := String(it["kind"])
		if kind != "park" and kind != "tree" and kind != "rock":
			var pave: Rect2 = (it["rect"] as Rect2).grow(PAVEMENT_GROW)
			m.add_rect(pave, PAVEMENT)
			m.add_rect_outline(pave, PAVEMENT_EDGE, 1.0)
	for it in _items:
		match String(it["kind"]):
			"park":
				_bake_park(m, it)
			"lot":
				_bake_lot(m, it)
			"tree":
				_bake_tree(m, it)
			"rock":
				_bake_rock(m, it)
			_:
				_bake_block(m, it)
	_mesh = m.build()


## SPEC 121: A LOW-POLY TREE, seen from above. Two flat circles read as a green spot -- "acne" -- so the
## crown is a seven-point ring with the radius jittered per point (from the item's own seed, so it is
## the same tree on every client and every replay) and the whole thing is built in four passes:
##
##   1. the shadow, the same ring offset down and right, which is what lifts it off the grass;
##   2. the TRUNK, drawn first so it shows under the gaps in the canopy;
##   3. the crown, the jittered ring in the dark green;
##   4. the LIT FACETS -- the three points nearest the light are re-drawn as triangles back to a point
##      offset up and left, in a lighter green. That is the whole low-poly look: flat faces that catch
##      the light at different angles, rather than a gradient.
##
## Nine triangles a tree, all of it baked into the one scenery mesh (SPEC 54), so it costs nothing to
## draw however many there are.
func _bake_tree(m: MeshPaint, it: Dictionary) -> void:
	var rect: Rect2 = it["rect"]
	var at := rect.get_center()
	var r := rect.size.x * 0.5
	var seed_v := float(it["seed"])
	var ring := PackedVector2Array()
	var lit := PackedVector2Array()
	var shade := PackedVector2Array()
	var hi := at - Vector2(r, r) * 0.30
	for i in TREE_FACETS:
		var a := TAU * float(i) / float(TREE_FACETS) + seed_v * 0.11
		# Deterministic jitter: 0.74 to 1.0 of the radius, so no two crowns are the same circle.
		var jitter := 0.87 + 0.13 * sin(seed_v * 2.3 + float(i) * 2.7)
		var p := at + Vector2.from_angle(a) * r * jitter
		ring.append(p)
		# The light comes from the top left, as it does for every shadow in the game.
		if Vector2.from_angle(a).dot(Vector2(-0.7, -0.7)) > 0.15:
			lit.append(p)
		shade.append(p + Vector2(r * 0.22, r * 0.30))
	m.add_fan(at + Vector2(r * 0.22, r * 0.30), shade, SHADOW)
	m.add_circle(at, maxf(r * TRUNK_SHARE, 2.0), TRUNK_COLOR, 6)
	m.add_fan(at, ring, TREE_COLOR)
	for i in maxi(lit.size() - 1, 0):
		m.add_triangle(hi, lit[i], lit[i + 1], TREE_COLOR.lightened(0.26))
	# One dark facet on the shaded side, so the crown is not flat-lit on the way out either.
	if ring.size() >= 3:
		m.add_triangle(at + Vector2(r, r) * 0.18, ring[ring.size() / 2],
				ring[(ring.size() / 2 + 1) % ring.size()], TREE_DARK)


## ... and a rock is the same idea in grey: a five-sided boulder with one lit face, flatter and wider
## than a tree and with no canopy to hide its shadow.
func _bake_rock(m: MeshPaint, it: Dictionary) -> void:
	var rect: Rect2 = it["rect"]
	var at := rect.get_center()
	var r := rect.size.x * ROCK_SOLID_SHARE
	var seed_v := float(it["seed"])
	var ring := PackedVector2Array()
	var shade := PackedVector2Array()
	for i in 5:
		var a := TAU * float(i) / 5.0 + seed_v * 0.17
		var p := at + Vector2.from_angle(a) * r * (0.82 + 0.18 * sin(seed_v + float(i) * 1.9))
		ring.append(p)
		shade.append(p + Vector2(3.0, 4.0))
	m.add_fan(at + Vector2(3.0, 4.0), shade, SHADOW)
	m.add_fan(at, ring, ROCK_COLOR)
	m.add_triangle(at - Vector2(r, r) * 0.25, ring[0], ring[1], ROCK_COLOR.lightened(0.22))


func _bake_block(m: MeshPaint, it: Dictionary) -> void:
	var r: Rect2 = it["rect"]
	var wall: Color = it["color"]
	var lift := float(it["lift"])
	var off := Vector2(-lift * 0.45, -lift)
	m.add_rect(Rect2(r.position + Vector2(5, 6), r.size), SHADOW)
	m.add_rect(r, wall)                                       # the walls, seen from above
	var roof := Rect2(r.position + off, r.size)
	m.add_rect(roof, Color(wall.r * ROOF_LIFT, wall.g * ROOF_LIFT, wall.b * ROOF_LIFT))
	m.add_rect_outline(roof, Color(0, 0, 0, 0.25), 1.0)
	# Windows along the two walls that show, and a vent or a tank on the roof.
	var s := float(it["seed"])
	var step := 11.0
	var x := r.position.x + 6.0
	while x < r.end.x - 8.0:
		m.add_rect(Rect2(Vector2(x, r.end.y - 5.0), Vector2(5, 3)), WINDOW)
		x += step
	var y := r.position.y + 6.0
	while y < r.end.y - 8.0:
		m.add_rect(Rect2(Vector2(r.end.x - 5.0, y), Vector2(3, 5)), WINDOW)
		y += step
	var vent := Vector2(roof.position.x + roof.size.x * (0.3 + 0.4 * fposmod(s, 1.0)),
			roof.position.y + roof.size.y * (0.3 + 0.3 * fposmod(s * 1.7, 1.0)))
	m.add_rect(Rect2(vent, Vector2(10, 8)), Color(wall.r * 0.55, wall.g * 0.55, wall.b * 0.55))


func _bake_park(m: MeshPaint, it: Dictionary) -> void:
	var r: Rect2 = it["rect"]
	m.add_rect(r, it["color"] as Color)
	var s := float(it["seed"])
	var n := 5
	for k in n:
		var f := float(k) + s
		var at := r.position + Vector2(r.size.x * fposmod(sin(f * 12.9898) * 43758.5453, 1.0),
				r.size.y * fposmod(sin(f * 78.233) * 12345.6789, 1.0))
		at = at.clamp(r.position + Vector2(10, 10), r.end - Vector2(10, 10))
		m.add_circle(at + Vector2(3, 4), 9.0, SHADOW, 8)
		m.add_circle(at, 9.0, TREE_COLOR, 8)


func _bake_lot(m: MeshPaint, it: Dictionary) -> void:
	var r: Rect2 = it["rect"]
	m.add_rect(r, it["color"] as Color)
	var x := r.position.x + 10.0
	while x < r.end.x - 8.0:
		m.add_line(Vector2(x, r.position.y + 6.0), Vector2(x, r.end.y - 6.0), 1.0, LOT_LINE)
		x += 18.0
