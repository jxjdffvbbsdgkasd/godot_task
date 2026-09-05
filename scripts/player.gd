extends CharacterBody2D

signal health_changed(new_health)
signal died

@export var speed: float = 200.0
@export var max_health: float = 100.0

# Shooting & Spread
@export var fire_rate: float = 0.3
@export var bullet_damage: float = 1.0
@export var spread_angle_deg: float = 15.0 
@export var projectile_scene: PackedScene = preload("res://scenes/player_projectile.tscn")

var health: float
var freeze: bool = false
var shoot_timer: float = 0.0

func _ready() -> void:
	health = max_health
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if freeze:
		velocity = Vector2.ZERO
		return

	shoot_timer -= delta

	# Movement (WSAD + Arrow keys)
	var move_x: float = 0.0
	var move_y: float = 0.0

	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		move_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		move_x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		move_y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		move_y += 1.0

	var direction := Vector2(move_x, move_y)
	if direction != Vector2.ZERO:
		direction = direction.normalized()

	# Shooting
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and shoot_timer <= 0.0:
		_shoot()
		shoot_timer = fire_rate
	
	velocity = direction * speed
	move_and_slide()

func _shoot() -> void:
	if not projectile_scene:
		return
	
	var mouse_pos := get_global_mouse_position()
	var to_mouse := mouse_pos - global_position
	if to_mouse.length_squared() < 1.0:
		return
	
	var base_shoot_dir := to_mouse.normalized()
	
	# Apply bullet spread (recoil angle)
	var half_spread_rad := deg_to_rad(spread_angle_deg * 0.5)
	var random_offset := randf_range(-half_spread_rad, half_spread_rad)
	var final_shoot_dir := base_shoot_dir.rotated(random_offset)
	
	# Instantiate projectile
	var proj := projectile_scene.instantiate() as Area2D
	if proj:
		proj.global_position = global_position + final_shoot_dir * 20.0
		if "direction" in proj:
			proj.set("direction", final_shoot_dir)
		if "damage" in proj:
			proj.set("damage", bullet_damage)
		if "shooter" in proj:
			proj.set("shooter", self)
		get_parent().add_child(proj)

func take_damage(amount: float, _attacker = null) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		health = 0
		died.emit()
		freeze = true
