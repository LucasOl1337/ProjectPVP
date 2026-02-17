@tool
@icon("./icon.svg")
class_name DrawnArea2D
extends Area2D

## DrawnArea2D
##
## An [Area2D] with the ability to draw it's [CollisionShape2D]s and [CollisionPolygon2D]s
## outside of a debugging context.[br]
## It's safe to disable [member redraw_on_frame] and [member redraw_on_physics] and/or
## use [method queue_redraw] to manually redraw this node.

## The [Color] to draw the shapes with.[br]
## The area of the shape will be filled with this exact color,
## and the edges of the shapes will be drawn using a color with the same
## red, green, and blue values, but at maximum opacity (alpha).[br]
## This behaviour replicates the drawing done in editor.
@export var color := Color(0,0,0,0.75)

## When set, only [CollisionShape2D]s/[CollisionPolygon2D]s that aren't
## [member CollisionShape2D.disabled]/[member CollisionPolygon2D.disabled]
## will be drawn.
@export var only_enabled := true

## When set, only [CollisionShape2D]s/[CollisionPolygon2D]s that are
## [member Node2D.visible] will be drawn.
@export var only_visible := true

## Redraw the shapes every processed frame.
## May help fix the drawn area not properly matching the current location of the area, when set,
## though increases rendering load.[br]
## [b]NOTE[/b]: at least this or [member redraw_on_physics] must be set
## for this area to be drawn automatically.
@export var redraw_on_frame := true

## Redraw the shapes every processed physics frame.
## May help fix the drawn area not properly matching the current location of the area, when set,
## though increases rendering load.[br]
## [b]NOTE[/b]: at least this or [member redraw_on_frame] must be set
## for this area to be drawn automatically.
@export var redraw_on_physics := false

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	for i in get_child_count(true):
		var child := get_child(i)

		if not (child is CollisionShape2D or child is CollisionPolygon2D):
			continue

		if only_visible and not child.visible:
			continue

		if only_enabled and child.disabled:
			continue

		var canvas_item:RID = child.get_canvas_item()

		RenderingServer.canvas_item_clear(canvas_item)

		if child is CollisionShape2D:
			child.shape.draw(canvas_item, color)
		else:
			var poly:PackedVector2Array = child.polygon

			var color_array := PackedColorArray()
			color_array.resize(poly.size())
			color_array.fill(color)

			RenderingServer.canvas_item_add_polygon(canvas_item, poly, color_array)

			if color.a < 1:
				var color_op := Color(color, 1)
				var color_array_op := PackedColorArray()
				color_array_op.resize(poly.size())
				color_array_op.fill(color_op)
				RenderingServer.canvas_item_add_polyline(canvas_item, poly, color_array_op)
				# Connect the start of the polyline to the end.
				RenderingServer.canvas_item_add_line(canvas_item, poly[-1], poly[0], color_op)

func _process(_delta:float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()

func _physics_process(_delta:float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()
