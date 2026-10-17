@tool
class_name MapBlock
extends Node2D
## A BUILDING in a hand-made map (SPEC 76). Drop one of these in a track scene (a `MapTrack`, SPEC 111),
## drag it where you want it, set its size -- that is the whole job. In the game it is solid: cars bounce
## off it, and the rope bends around its corners (SPEC 75), which is what makes a city worth driving in.
##
## Editing it: select it in the scene tree and it draws itself in the editor viewport, at the size and
## place it will have in the game. Nothing here is generated or baked at author time; the track reads the
## nodes when it loads.
##
## `size` is the whole building, `position` its CENTRE -- so a block dropped at a street corner stays put
## when you resize it.

## The building's footprint in pixels. Keep `MapTrack.BLOCK_CLEAR` of grass between it and the road.
@export var size: Vector2 = Vector2(160, 120):
	set(v):
		size = Vector2(maxf(v.x, 16.0), maxf(v.y, 16.0))
		queue_redraw()
		update_configuration_warnings()

## How tall it looks: the roof is drawn offset by this, so a row of blocks reads as a skyline. Purely
## cosmetic -- the footprint is what cars and ropes meet.
@export_range(0.0, 40.0, 1.0) var height: float = 14.0:
	set(v):
		height = v
		queue_redraw()

@export var color: Color = Color(0.34, 0.31, 0.36):
	set(v):
		color = v
		queue_redraw()


## The footprint in WORLD coordinates -- what the track hands to `Car.solids`.
func get_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	# SPEC 79: a building, not two rectangles. The first version drew the footprint and then the roof
	# offset up-left, which from above reads as two loose walls with a gap. A block is drawn as a solid
	# object instead: the footprint in shadow, the two visible WALLS as quads joining footprint to roof,
	# then the roof itself with a lip -- so the lift reads as height and the shape stays one thing.
	# The whole building is drawn INSIDE its footprint (SPEC 79). The first version lifted the roof up
	# and left, outside the rect -- so a cone standing in the street north of a building looked like it
	# was on the roof, and what you could see stopped matching what you could hit. Now the roof is the
	# footprint inset by the height, and the walls are the ring between them: the lift still reads, and
	# the outline is exactly the thing the car collides with.
	var r := Rect2(-size * 0.5, size)
	var inset: float = minf(height, minf(size.x, size.y) * 0.22)
	var roof := Rect2(r.position + Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var wall_a := color.darkened(0.45)
	var wall_b := color.darkened(0.30)
	var wall_c := color.darkened(0.18)
	# The four walls, as the ring between the footprint and the roof. The sunlit sides are lighter, so
	# the block reads as a solid object from above rather than as a flat card.
	draw_rect(r, wall_a)
	draw_colored_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
			Vector2(roof.end.x, roof.position.y), roof.position]), wall_c)
	draw_colored_polygon(PackedVector2Array([r.position, roof.position,
			Vector2(roof.position.x, roof.end.y), Vector2(r.position.x, r.end.y)]), wall_b)
	draw_rect(roof, color)
	draw_rect(roof, color.lightened(0.12), false, 2.0)
	# A few windows, so the scale reads at a glance. Deterministic in the block's own size.
	var cols := maxi(int(roof.size.x / 46.0), 1)
	var rows := maxi(int(roof.size.y / 46.0), 1)
	var win := color.lightened(0.30)
	win.a = 0.5
	for ix in cols:
		for iy in rows:
			var at := roof.position + Vector2((float(ix) + 0.5) * roof.size.x / float(cols),
					(float(iy) + 0.5) * roof.size.y / float(rows))
			if (ix + iy * 3) % 4 == 0:
				continue
			draw_rect(Rect2(at - Vector2(7, 5), Vector2(14, 10)), win)
	if Engine.is_editor_hint():
		draw_rect(r, Color(1, 1, 1, 0.22), false, 1.0)


func _get_configuration_warnings() -> PackedStringArray:
	if size.x < 24.0 or size.y < 24.0:
		return PackedStringArray(["A building this small reads as a prop -- use a MapProp instead."])
	return PackedStringArray()
