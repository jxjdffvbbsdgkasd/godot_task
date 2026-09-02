extends CharacterBody2D

@export var speed: float = 120.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var look_ahead_distance: float = 100.0
@export var debug_draw: bool = true

var num_rays: int = 8
var ray_directions: Array[Vector2] = []
var interest: Array[float] = []
var danger: Array[float] = []
var final_weights: Array[float] = []

var target_player: Node2D = null
var attack_timer: float = 0.0

# Wall-Following Bypass Hysteresis
var is_bypassing: bool = false
var bypass_direction: float = 1.0 # 1.0 = clockwise, -1.0 = counter-clockwise
var last_wall_normal: Vector2 = Vector2.ZERO
var chosen_direction: Vector2 = Vector2.ZERO

var freeze: bool = false

func _ready() -> void:
	add_to_group("enemies")
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

	if not target_player or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node2D
		if target_player:
			if target_player.has_signal("died") and not target_player.died.is_connected(_on_player_died):
				target_player.died.connect(_on_player_died)
		else:
			return

	attack_timer -= delta
	
	# 1. Main target vector (towards player)
	var to_player := target_player.global_position - global_position
	var dist_to_player := to_player.length()
	var dir_to_player := to_player.normalized() if dist_to_player > 0 else Vector2.ZERO
	
	# Check if player is within attack range
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

func _attack_player() -> void:
	if attack_timer <= 0.0 and target_player:
		if target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage)
		attack_timer = attack_cooldown
		
func _on_player_died() -> void:
	freeze = true
	velocity = Vector2.ZERO

func _draw() -> void:
	if not debug_draw:
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
