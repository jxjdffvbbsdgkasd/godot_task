extends CharacterBody2D

@export var speed: float = 120.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var look_ahead_distance: float = 100.0
@export var debug_draw: bool = true

# Jump Parameters
@export var can_jump: bool = true
@export var jump_cooldown: float = 3.0
@export var jump_max_distance: float = 220.0
@export var jump_duration: float = 0.5
@export var jump_height: float = 40.0

# Ranged Attack Parameters
@export var can_shoot: bool = true
@export var shoot_cooldown: float = 2.0
@export var shoot_range: float = 400.0
@export var projectile_scene: PackedScene = preload("res://scenes/enemy_projectile.tscn")

var num_rays: int = 8
var ray_directions: Array[Vector2] = []
var interest: Array[float] = []
var danger: Array[float] = []
var final_weights: Array[float] = []

var target_player: Node2D = null
var attack_timer: float = 0.0
var shoot_timer: float = 0.0

# Wall-Following Bypass Hysteresis
var is_bypassing: bool = false
var bypass_direction: float = 1.0 # 1.0 = clockwise, -1.0 = counter-clockwise
var last_wall_normal: Vector2 = Vector2.ZERO
var chosen_direction: Vector2 = Vector2.ZERO

var freeze: bool = false

# Jump State
var is_jumping: bool = false
var jump_progress: float = 0.0
var jump_cooldown_timer: float = 0.0
var jump_start_pos: Vector2 = Vector2.ZERO
var jump_target_pos: Vector2 = Vector2.ZERO
var saved_collision_mask: int = 5

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	add_to_group("enemies")
	saved_collision_mask = collision_mask
	# Initialize 8 direction vectors
	for i in range(num_rays):
		var angle := i * (TAU / num_rays)
		ray_directions.append(Vector2.RIGHT.rotated(angle))
		interest.append(0.0)
		danger.append(0.0)
		final_weights.append(0.0)

func _physics_process(delta: float) -> void:
	if freeze:
		velocity = Vector2.ZERO
		return

	# Update active jump
	if is_jumping:
		jump_progress += delta
		var t: float = clampf(jump_progress / jump_duration, 0.0, 1.0)
		# Smooth jump motion
		var ease_t := sin(t * PI * 0.5)
		global_position = jump_start_pos.lerp(jump_target_pos, ease_t)
		
		# Visual 2D height arc
		var height: float = sin(t * PI) * jump_height
		if color_rect:
			color_rect.position.y = -16.0 - height
		
		if t >= 1.0:
			# Landed safely
			is_jumping = false
			collision_mask = saved_collision_mask
			jump_cooldown_timer = jump_cooldown
			if color_rect:
				color_rect.position.y = -16.0
		
		if debug_draw:
			queue_redraw()
		return

	if not target_player or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node2D
		if target_player:
			if target_player.has_signal("died") and not target_player.died.is_connected(_on_player_died):
				target_player.died.connect(_on_player_died)
		else:
			return

	attack_timer -= delta
	jump_cooldown_timer -= delta
	shoot_timer -= delta
	
	# 1. Main target vector (towards player)
	var to_player := target_player.global_position - global_position
	var dist_to_player := to_player.length()
	var dir_to_player := to_player.normalized() if dist_to_player > 0 else Vector2.ZERO
	
	# Check if player is within attack range (Melee)
	if dist_to_player <= 40.0:
		_attack_player()
		if freeze:
			velocity = Vector2.ZERO
			return

	# 2. Physics sampling (Raycasting)
	var space_state := get_world_2d().direct_space_state
	var direct_ray_blocked: bool = false
	var obstacle_hit_normal: Vector2 = Vector2.ZERO
	
	# Test direct line of sight to player
	var direct_query := PhysicsRayQueryParameters2D.create(global_position, target_player.global_position)
	direct_query.exclude = [get_rid()]
	direct_query.collision_mask = 1 # Layer for physical obstacles
	var direct_result: Dictionary = space_state.intersect_ray(direct_query)
	
	if not direct_result.is_empty():
		direct_ray_blocked = true
		obstacle_hit_normal = direct_result.get("normal", Vector2.ZERO) as Vector2

	# Ranged Attack logic: Shoot projectile when player is in direct line of sight
	if can_shoot and not direct_ray_blocked and shoot_timer <= 0.0 and dist_to_player <= shoot_range and dist_to_player > 40.0:
		_shoot_projectile(dir_to_player)
		shoot_timer = shoot_cooldown

	# Jump logic: Check if player is hiding behind an obstacle
	if can_jump and jump_cooldown_timer <= 0.0 and direct_ray_blocked:
		var hit_pos: Vector2 = direct_result.get("position", global_position) as Vector2
		var dist_to_obstacle: float = global_position.distance_to(hit_pos)
		
		if dist_to_obstacle <= 90.0:
			# Raycast from player to obstacle front face to locate back face of obstacle
			var back_query := PhysicsRayQueryParameters2D.create(target_player.global_position, hit_pos)
			back_query.collision_mask = 1
			var back_result: Dictionary = space_state.intersect_ray(back_query)
			
			if not back_result.is_empty():
				var back_hit_pos: Vector2 = back_result.get("position", target_player.global_position) as Vector2
				var landing_pos: Vector2 = back_hit_pos + dir_to_player * 35.0
				var dist_to_landing: float = global_position.distance_to(landing_pos)
				
				if dist_to_landing <= jump_max_distance and dist_to_landing < dist_to_player:
					_start_jump(landing_pos)
					if debug_draw:
						queue_redraw()
					return

	# Reset or maintain Wall-Following bypass state
	if direct_ray_blocked:
		if not is_bypassing:
			is_bypassing = true
			last_wall_normal = obstacle_hit_normal
			# Choose optimal bypass direction (tangent to wall) towards player
			var tangent := Vector2(-obstacle_hit_normal.y, obstacle_hit_normal.x)
			if tangent.dot(dir_to_player) < 0:
				bypass_direction = -1.0
			else:
				bypass_direction = 1.0
	else:
		is_bypassing = false

	# 3. Calculate Interest Map and Danger Map
	for i in range(num_rays):
		var dir: Vector2 = ray_directions[i]
		
		# Interest Map
		if is_bypassing and last_wall_normal != Vector2.ZERO:
			# When obstacle blocks path, increase interest in directions tangent to wall
			var wall_tangent := Vector2(-last_wall_normal.y * bypass_direction, last_wall_normal.x * bypass_direction)
			var dot_player: float = maxf(0.0, dir.dot(dir_to_player))
			var dot_tangent: float = maxf(0.0, dir.dot(wall_tangent))
			interest[i] = dot_tangent * 0.7 + dot_player * 0.3
		else:
			var dot_p: float = maxf(0.0, dir.dot(dir_to_player))
			interest[i] = dot_p
		
		# Danger Map for rays
		var ray_end: Vector2 = global_position + dir * look_ahead_distance
		var query := PhysicsRayQueryParameters2D.create(global_position, ray_end)
		query.exclude = [get_rid()]
		query.collision_mask = 1
		var result: Dictionary = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var hit_pos: Vector2 = result.get("position", global_position) as Vector2
			var hit_dist: float = global_position.distance_to(hit_pos)
			# Danger increases the closer the obstacle is
			danger[i] = 1.0 - (hit_dist / look_ahead_distance)
			if is_bypassing:
				last_wall_normal = result.get("normal", Vector2.ZERO) as Vector2
		else:
			danger[i] = 0.0

	# 4. Combine maps and compute chosen direction
	chosen_direction = Vector2.ZERO
	for i in range(num_rays):
		# If obstacle is too close in a direction, zero out weight
		if danger[i] > 0.85:
			final_weights[i] = 0.0
		else:
			final_weights[i] = maxf(0.0, interest[i] - danger[i])
		
		chosen_direction += ray_directions[i] * final_weights[i]

	if chosen_direction.length_squared() > 0.001:
		chosen_direction = chosen_direction.normalized()
	elif is_bypassing and last_wall_normal != Vector2.ZERO:
		# Emergency movement along wall if all rays are partially obstructed
		chosen_direction = Vector2(-last_wall_normal.y * bypass_direction, last_wall_normal.x * bypass_direction).normalized()

	velocity = chosen_direction * speed
	move_and_slide()

	if debug_draw:
		queue_redraw()

func _start_jump(target_pos: Vector2) -> void:
	is_jumping = true
	jump_progress = 0.0
	jump_start_pos = global_position
	jump_target_pos = target_pos
	saved_collision_mask = collision_mask
	collision_mask = 0 # Disable obstacle collision while airborne

func _shoot_projectile(dir: Vector2) -> void:
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate() as Area2D
	if proj:
		proj.global_position = global_position + dir * 20.0
		if "direction" in proj:
			proj.set("direction", dir)
		get_parent().add_child(proj)

func _attack_player() -> void:
	if attack_timer <= 0.0 and target_player:
		if target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage)
		attack_timer = attack_cooldown
		
func _on_player_died() -> void:
	freeze = true
	velocity = Vector2.ZERO
	if is_jumping:
		is_jumping = false
		collision_mask = saved_collision_mask
		if color_rect:
			color_rect.position.y = -16.0

func _draw() -> void:
	if not debug_draw:
		return
	
	if is_jumping:
		# Draw jump trajectory line and landing target indicator
		var local_target := jump_target_pos - global_position
		draw_line(Vector2.ZERO, local_target, Color.GOLD, 3.0)
		draw_circle(local_target, 8.0, Color.YELLOW)
		return
	
	# Draw 8 Context Steering rays
	for i in range(num_rays):
		var dir := ray_directions[i]
		# Green = Interest / Final weight
		if final_weights[i] > 0:
			draw_line(Vector2.ZERO, dir * (20.0 + final_weights[i] * 40.0), Color.GREEN, 2.0)
		# Red = Danger
		if danger[i] > 0:
			draw_line(Vector2.ZERO, dir * (danger[i] * look_ahead_distance), Color.RED, 1.5)

	# Cyan line = chosen direction
	if chosen_direction != Vector2.ZERO:
		draw_line(Vector2.ZERO, chosen_direction * 45.0, Color.CYAN, 3.5)
