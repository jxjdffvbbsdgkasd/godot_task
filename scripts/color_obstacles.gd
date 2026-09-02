extends CollisionShape2D

@export var draw_color: Color = Color("1ca43fd7")
@export var line_width: float = 2.0

func _draw():
	if shape is SegmentShape2D:
		var seg = shape as SegmentShape2D
		draw_line(seg.a, seg.b, draw_color, line_width)
	elif shape is RectangleShape2D:
		var rect_shape = shape as RectangleShape2D
		var rect = Rect2(-rect_shape.size / 2, rect_shape.size)
		draw_rect(rect, draw_color)
	elif shape is CircleShape2D:
		var circle = shape as CircleShape2D
		draw_circle(Vector2.ZERO, circle.radius, draw_color)

func _ready():
	queue_redraw()
