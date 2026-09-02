extends StaticBody2D

@export var size: Vector2 = Vector2(64, 64):
	set(value):
		size = value
		_update_size()

@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("obstacles")
	_update_size()

func _update_size() -> void:
	if not is_inside_tree():
		return
	if color_rect:
		color_rect.size = size
		color_rect.position = -size / 2.0
	if collision_shape and collision_shape.shape:
		var rect_shape := collision_shape.shape as RectangleShape2D
		if rect_shape:
			rect_shape.size = size
