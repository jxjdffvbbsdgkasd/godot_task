extends CharacterBody2D

@export var speed: float = 130.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var look_ahead_distance: float = 85.0
@export var debug_draw: bool = true

# ranges
@export var melee_range: float = 125.0
@export var preferred_ranged_dist: float = 230.0 # Distance the enemy tries to maintain for shooting
@export var shoot_range: float = 420.0

# Jump
@export var can_jump: bool = true
@export var jump_cooldown: float = 3.5
@export var jump_max_distance: float = 230.0
@export var jump_duration: float = 0.45
@export var jump_height: float = 35.0

# Shooting
@export var can_shoot: bool = true
@export var shoot_cooldown: float = 1.6
@export var projectile_scene: PackedScene = preload("res://scenes/enemy_projectile.tscn")

# Context Steering
var num_rays: int = 16
var ray_directions: Array[Vector2] = []
var interest: Array[float] = []
var danger: Array[float] = []
var final_weights: Array[float] = []

var target_player: Node2D = null
var attack_timer: float = 0.0
var shoot_timer: float = 0.0

# Flanking
var flank_side: float = 1.0 # 1.0 = right, -1.0 = left
var flank_change_timer: float = 0.0
var chosen_direction: Vector2 = Vector2.ZERO
var freeze: bool = false

# Jump
var is_jumping: bool = false
var jump_progress: float = 0.0
var jump_cooldown_timer: float = 0.0
var jump_start_pos: Vector2 = Vector2.ZERO
var jump_target_pos: Vector2 = Vector2.ZERO
var saved_collision_mask: int = 1

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	add_to_group("enemies")
	saved_collision_mask = collision_mask
	
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

	if is_jumping:
		jump_progress += delta
		var t: float = clampf(jump_progress / jump_duration, 0.0, 1.0)
		var ease_t := sin(t * PI * 0.5)
		global_position = jump_start_pos.lerp(jump_target_pos, ease_t)
		
		if color_rect:
			color_rect.position.y = -16.0 - sin(t * PI) * jump_height
		
		if t >= 1.0:
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
		if target_player and target_player.has_signal("died"):
			if not target_player.died.is_connected(_on_player_died):
				target_player.died.connect(_on_player_died)
		if not target_player:
			return

	attack_timer -= delta
	jump_cooldown_timer -= delta
	shoot_timer -= delta
	flank_change_timer -= delta

	var to_player := target_player.global_position - global_position
	var dist_to_player := to_player.length()
	var dir_to_player := to_player.normalized() if dist_to_player > 0 else Vector2.ZERO
	
	var space_state := get_world_2d().direct_space_state

	var los_query := PhysicsRayQueryParameters2D.create(global_position, target_player.global_position)
	los_query.exclude = [get_rid()]
	los_query.collision_mask = 1 # Obstacle layer
	var los_result: Dictionary = space_state.intersect_ray(los_query)
	var has_line_of_sight: bool = los_result.is_empty()

		# jump over obstacle
	if can_jump and jump_cooldown_timer <= 0.0 and not has_line_of_sight:
		var hit_pos: Vector2 = los_result.get("position", global_position) as Vector2
		if global_position.distance_to(hit_pos) <= 80.0:
			var back_query := PhysicsRayQueryParameters2D.create(target_player.global_position, hit_pos)
			back_query.collision_mask = 1
			var back_res := space_state.intersect_ray(back_query)
			if not back_res.is_empty():
				var landing := (back_res.position as Vector2) + dir_to_player * 35.0
				if global_position.distance_to(landing) <= jump_max_distance:
					_start_jump(landing)
					return

	# meele vs ranged
	if dist_to_player <= melee_range:
		_attack_player()
	elif has_line_of_sight and can_shoot and shoot_timer <= 0.0 and dist_to_player <= shoot_range:
		_shoot_projectile(dir_to_player)
		shoot_timer = shoot_cooldown

		#flanking
	var desired_move_dir := Vector2.ZERO
	var tangent := Vector2(-dir_to_player.y, dir_to_player.x) * flank_side

	if flank_change_timer <= 0.0:
		flank_change_timer = randf_range(2.0, 3.5)
		# check which side has more free space
		var left_probe := global_position + Vector2(-dir_to_player.y, dir_to_player.x) * 70.0
		var right_probe := global_position - Vector2(-dir_to_player.y, dir_to_player.x) * 70.0
		var left_free := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(global_position, left_probe, 1, [get_rid()])).is_empty()
		var right_free := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(global_position, right_probe, 1, [get_rid()])).is_empty()
		
		if left_free and not right_free:
			flank_side = 1.0
		elif right_free and not left_free:
			flank_side = -1.0

	if not has_line_of_sight:
		desired_move_dir = (dir_to_player * 0.45 + tangent * 0.55).normalized()
	else:
		if dist_to_player < preferred_ranged_dist - 40.0:
			desired_move_dir = (-dir_to_player * 0.6 + tangent * 0.4).normalized()
		elif dist_to_player > preferred_ranged_dist + 50.0:
			desired_move_dir = (dir_to_player * 0.6 + tangent * 0.4).normalized()
		else:
			desired_move_dir = tangent.normalized()

	if dist_to_player < melee_range * 1.3:
		desired_move_dir = dir_to_player

	# CONTEXT STEERING (16 rays)
	for i in range(num_rays):
		var dir := ray_directions[i]
		
		# Interest weight based on tactical vector
		var dot_interest: float = dir.dot(desired_move_dir)
		interest[i] = maxf(0.0, dot_interest)

		# Scanning Danger (obstacles)
		var ray_end := global_position + dir * look_ahead_distance
		var q := PhysicsRayQueryParameters2D.create(global_position, ray_end)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var res: Dictionary = space_state.intersect_ray(q)

		if not res.is_empty():
			var hit_dist := global_position.distance_to(res.position as Vector2)
			danger[i] = 1.0 - (hit_dist / look_ahead_distance)
		else:
			danger[i] = 0.0

	# Resulting movement vector
	chosen_direction = Vector2.ZERO
	for i in range(num_rays):
		# If a wall is too close in a given direction, we eliminate it completely
		if danger[i] > 0.8:
			final_weights[i] = 0.0
		else:
			final_weights[i] = maxf(0.0, interest[i] - danger[i] * 1.2)
		
		chosen_direction += ray_directions[i] * final_weights[i]

	if chosen_direction.length_squared() > 0.01:
		chosen_direction = chosen_direction.normalized()
	else:
		# Fallback against getting stuck in a right angle: move along the flanking vector
		chosen_direction = tangent.normalized()

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
	collision_mask = 0

func _shoot_projectile(dir: Vector2) -> void:
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate() as Area2D
	if proj:
		proj.global_position = global_position + dir * 22.0
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
		var local_target := jump_target_pos - global_position
		draw_line(Vector2.ZERO, local_target, Color.GOLD, 3.0)
		draw_circle(local_target, 8.0, Color.YELLOW)
		return

	for i in range(num_rays):
		var dir := ray_directions[i]
		if final_weights[i] > 0.0:
			draw_line(Vector2.ZERO, dir * (15.0 + final_weights[i] * 35.0), Color.GREEN, 1.5)
		if danger[i] > 0.1:
			draw_line(Vector2.ZERO, dir * (danger[i] * look_ahead_distance), Color.RED, 1.0)

	if chosen_direction != Vector2.ZERO:
		draw_line(Vector2.ZERO, chosen_direction * 40.0, Color.CYAN, 3.0)
