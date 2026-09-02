extends CharacterBody2D

signal health_changed(new_health)
signal died

@export var speed: float = 200.0
@export var max_health: float = 100.0

var health: float

func _ready() -> void:
	health = max_health
	add_to_group("player")

func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")
	
	if direction != Vector2.ZERO:
		direction = direction.normalized()
	
	velocity = direction * speed
	move_and_slide()

func take_damage(amount: float) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		health = 0
		died.emit()
