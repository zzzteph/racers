class_name BridgeDeck
extends Node2D
## Upper-branch bridge deck of the figure-8 track. Drawn above the lower road and above a car that is on the
## lower branch (z_index = Track.BRIDGE_DECK_Z), below a car that is on the bridge.

const SHADOW_OFFSET := Vector2(10, 12)
const SHADOW_COLOR := Color(0, 0, 0, 0.42)
const SHADOW_SPREAD := 8.0  # extra shadow half-width so it is visible on the lower road on both sides
const WALL_COLOR := Color(0.55, 0.55, 0.58)
const DECK_COLOR := Color(0.36, 0.36, 0.38)
const EDGE_COLOR := Color(0.95, 0.95, 0.95)
const RAIL_COLOR := Color(0.85, 0.85, 0.88)
const POST_COLOR := Color(0.45, 0.45, 0.48)
const WALL_OUTSET := 8.0  # px beyond the asphalt edge on each side
const POST_SPACING := 3   # posts every N deck points

## Deck centerline section (global coordinates, open polyline following the direction of travel).
var deck_points: PackedVector2Array = PackedVector2Array()
var deck_width: float = TrackData.TRACK_WIDTH


func set_deck(points: PackedVector2Array, width: float) -> void:
	deck_points = points
	deck_width = width
	queue_redraw()


func _draw() -> void:
	if deck_points.size() < 2:
		return
	var hw := deck_width * 0.5
	# Drop shadow onto the lower road.
	var shadow_pts := deck_points.slice(2, deck_points.size() - 2) if deck_points.size() > 6 else deck_points
	Track.draw_strip(self, shadow_pts, false, hw + WALL_OUTSET + SHADOW_SPREAD, SHADOW_COLOR, SHADOW_OFFSET)
	# Edge walls (concrete), asphalt, white edge lines.
	Track.draw_strip(self, deck_points, false, hw + WALL_OUTSET, WALL_COLOR)
	Track.draw_strip(self, deck_points, false, hw, EDGE_COLOR)
	Track.draw_strip(self, deck_points, false, hw - 4.0, DECK_COLOR)
	# Centre dashes, so the deck reads as a piece of road carried over the crossing, not a blank slab.
	for i in range(0, deck_points.size() - 1, 2):
		var a: Vector2 = deck_points[i]
		draw_line(a, a.lerp(deck_points[i + 1], 0.6), Track.DASH_COLOR, 2.0)
	# Railings along both edges.
	var normals := Track.compute_normals(deck_points, false)
	var n := deck_points.size()
	for side in [-1.0, 1.0]:
		var rail := PackedVector2Array()
		rail.resize(n)
		for i in n:
			rail[i] = deck_points[i] + normals[i] * (hw + WALL_OUTSET * 0.5) * side
		draw_polyline(rail, RAIL_COLOR, 4.0)
		for i in n:
			if i % POST_SPACING == 0 or i == n - 1:
				var is_end := i == 0 or i == n - 1
				var r := 5.0 if is_end else 3.0
				draw_rect(Rect2(rail[i] - Vector2(r, r), Vector2(r, r) * 2.0), POST_COLOR)
	# End beams across the deck ends make the bridge edges obvious.
	for i in [0, n - 1]:
		var a: Vector2 = deck_points[i] + normals[i] * (hw + WALL_OUTSET)
		var b: Vector2 = deck_points[i] - normals[i] * (hw + WALL_OUTSET)
		draw_line(a, b, Color(0.2, 0.2, 0.22, 0.6), 2.0)
