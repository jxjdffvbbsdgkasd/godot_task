extends Area2D

@export var speed: float = 380.0
@export var damage: float = 8.0
@export var lifetime: float = 4.0

var direction: Vector2 = Vector2.ZERO
var lifetime_timer: float = 0.0
var shooter: Node2D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		queue_free()
		return
	
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if is_instance_valid(shooter) and body == shooter:
		return
	
	if body.has_method("take_damage"):
		var valid_shooter = shooter if is_instance_valid(shooter) else null
		body.take_damage(damage, valid_shooter)
		queue_free()
	elif body is StaticBody2D or body.is_in_group("obstacles") or body.name == "bounds":
		queue_free()
