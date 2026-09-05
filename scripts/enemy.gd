extends CharacterBody2D

signal died

@export var max_health: float = 60.0
@export var speed: float = 130.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var look_ahead_distance: float = 85.0
@export var debug_draw: bool = true

# ranges
@export var melee_range: float = 52.0
@export var shoot_range: float = 450.0

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

# Context Steering (16 rays)
var num_rays: int = 16
var ray_directions: Array[Vector2] = []
var interest: Array[float] = []
var danger: Array[float] = []
var final_weights: Array[float] = []

var health: float = 60.0
var current_target: Node2D = null
var attack_timer: float = 0.0
var shoot_timer: float = 0.0

# Flanking & Coordination
var flank_angle_offset: float = 0.0
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

# Visual feedback
var flash_timer: float = 0.0
var base_color: Color = Color(0.9, 0.2, 0.2, 1.0)
var infight_color: Color = Color(0.95, 0.5, 0.1, 1.0)

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	saved_collision_mask = collision_mask
	
	for i in range(num_rays):
		var angle := i * (TAU / num_rays)
		ray_directions.append(Vector2.RIGHT.rotated(angle))
		interest.append(0.0)
		danger.append(0.0)
		final_weights.append(0.0)

	# randomize shooting timer 
	shoot_timer = randf_range(0.3, shoot_cooldown)

func _physics_process(delta: float) -> void:
	if freeze:
		velocity = Vector2.ZERO
		return

	# Visual flash update
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and color_rect:
			_update_visual_color()

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

	# Target validation & acquisition
	_update_current_target()
	if not current_target or not is_instance_valid(current_target):
		return

	attack_timer -= delta
	jump_cooldown_timer -= delta
	shoot_timer -= delta
	flank_change_timer -= delta

	var to_target := current_target.global_position - global_position
	var dist_to_target := to_target.length()
	var dir_to_target := to_target.normalized() if dist_to_target > 0 else Vector2.ZERO
	
	var space_state := get_world_2d().direct_space_state

	# Check Line of Sight to target (against obstacles on layer 1)
	var los_query := PhysicsRayQueryParameters2D.create(global_position, current_target.global_position)
	los_query.exclude = [get_rid()]
	los_query.collision_mask = 1 # Obstacle layer
	var los_result: Dictionary = space_state.intersect_ray(los_query)
	var has_line_of_sight: bool = los_result.is_empty()

	# TACTICAL OBSTACLE JUMP: leap over obstacle if close to wall and target is on the other side
	if can_jump and jump_cooldown_timer <= 0.0 and not has_line_of_sight:
		var hit_pos: Vector2 = los_result.get("position", global_position) as Vector2
		if global_position.distance_to(hit_pos) <= 85.0:
			var back_query := PhysicsRayQueryParameters2D.create(current_target.global_position, hit_pos)
			back_query.collision_mask = 1
			var back_res := space_state.intersect_ray(back_query)
			if not back_res.is_empty():
				var landing := (back_res.position as Vector2) + dir_to_target * 40.0
				if global_position.distance_to(landing) <= jump_max_distance:
					_start_jump(landing)
					return

	# ATTACKS (Melee vs Ranged)
	if dist_to_target <= melee_range:
		_attack_target()
	elif has_line_of_sight and can_shoot and shoot_timer <= 0.0 and dist_to_target <= shoot_range:
		_shoot_projectile(dir_to_target)
		shoot_timer = shoot_cooldown

	# COORDINATED MOVEMENT & TERRAIN FLANKING
	_update_tactical_flanking(dir_to_target, dist_to_target)

	var flank_dir := dir_to_target.rotated(flank_angle_offset)
	var desired_move_dir := Vector2.ZERO

	if not has_line_of_sight:
		# Target is behind terrain/obstacle: navigate around using the assigned flank angle
		desired_move_dir = (dir_to_target * 0.45 + flank_dir * 0.55).normalized()
	else:
		# In line of sight: aggressively close distance while flanking to surround and melee
		if dist_to_target > melee_range:
			desired_move_dir = (dir_to_target * 0.65 + flank_dir * 0.35).normalized()
		else:
			desired_move_dir = dir_to_target

	# CONTEXT STEERING (16 rays): Obstacle avoidance + Ally separation
	var alive_allies := _get_alive_allies()

	for i in range(num_rays):
		var r_dir := ray_directions[i]
		
		# 1. Interest: how well this ray aligns with our coordinated tactical movement direction
		var dot_interest: float = r_dir.dot(desired_move_dir)
		interest[i] = maxf(0.0, dot_interest)

		# 2. Danger from Static Obstacles
		var ray_end := global_position + r_dir * look_ahead_distance
		var q := PhysicsRayQueryParameters2D.create(global_position, ray_end)
		q.exclude = [get_rid()]
		q.collision_mask = 1 # Obstacle layer
		var res: Dictionary = space_state.intersect_ray(q)

		var obstacle_danger := 0.0
		if not res.is_empty():
			var hit_dist := global_position.distance_to(res.position as Vector2)
			obstacle_danger = 1.0 - (hit_dist / look_ahead_distance)

		# 3. Danger / Repulsion from Allies (Separation to avoid clumping)
		var ally_danger := 0.0
		for ally in alive_allies:
			var to_ally := ally.global_position - global_position
			var ally_dist := to_ally.length()
			if ally_dist > 0.0 and ally_dist < 80.0:
				var ally_dir := to_ally / ally_dist
				var dot_ally := r_dir.dot(ally_dir)
				if dot_ally > 0.0:
					var repulse := (1.0 - (ally_dist / 80.0)) * dot_ally
					ally_danger = maxf(ally_danger, repulse)

		danger[i] = clampf(obstacle_danger + ally_danger * 0.8, 0.0, 1.0)

	# Compute final chosen direction
	chosen_direction = Vector2.ZERO
	for i in range(num_rays):
		if danger[i] > 0.8:
			final_weights[i] = 0.0
		else:
			final_weights[i] = maxf(0.0, interest[i] - danger[i] * 1.2)
		
		chosen_direction += ray_directions[i] * final_weights[i]

	if chosen_direction.length_squared() > 0.01:
		chosen_direction = chosen_direction.normalized()
	else:
		# Fallback: slide along the flank direction if stuck
		chosen_direction = flank_dir.normalized()

	velocity = chosen_direction * speed
	move_and_slide()

	if debug_draw:
		queue_redraw()

func _update_current_target() -> void:
	# If current target is invalid, freed, or dead, acquire player
	if current_target == null or not is_instance_valid(current_target):
		_retarget_player()
		return

	# Check if target is dead (e.g. enemy died or player died)
	if "health" in current_target and current_target.health <= 0:
		_retarget_player()
		return
	elif current_target.has_method("is_dead") and current_target.is_dead():
		_retarget_player()
		return

func _retarget_player() -> void:
	current_target = get_tree().get_first_node_in_group("player") as Node2D
	if current_target and current_target.has_signal("died"):
		if not current_target.died.is_connected(_on_player_died):
			current_target.died.connect(_on_player_died)
	_update_visual_color()

func _update_tactical_flanking(dir_to_target: Vector2, _dist_to_target: float) -> void:
	# Dynamic role coordination: spread enemies around target (Pincer maneuver)
	var allies := _get_alive_allies()
	allies.append(self)
	# Sort allies deterministically by instance ID
	allies.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())

	var my_index := allies.find(self)
	var total := allies.size()

	if total == 1:
		flank_angle_offset = 0.0
	elif total == 2:
		flank_angle_offset = (PI * 0.4) if my_index == 0 else (-PI * 0.4)
	else:
		if my_index == 0:
			flank_angle_offset = 0.0 # Center / front pressure
		elif my_index == 1:
			flank_angle_offset = PI * 0.45 # Flank left
		else:
			flank_angle_offset = -PI * 0.45 # Flank right

	# If infighting another enemy, adjust flank slightly
	if _is_infighting():
		flank_angle_offset = (PI * 0.5) if (get_instance_id() % 2 == 0) else (-PI * 0.5)

func _get_alive_allies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e != self and is_instance_valid(e) and e is CharacterBody2D:
			if "health" in e and e.health > 0:
				result.append(e)
	return result

func _is_infighting() -> bool:
	return current_target != null and is_instance_valid(current_target) and current_target.is_in_group("enemies")

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
		if "shooter" in proj:
			proj.set("shooter", self)
		get_parent().add_child(proj)

func _attack_target() -> void:
	if attack_timer <= 0.0 and current_target and is_instance_valid(current_target):
		if current_target.has_method("take_damage"):
			current_target.take_damage(attack_damage, self)
		attack_timer = attack_cooldown

func take_damage(amount: float, attacker = null) -> void:
	health -= amount
	flash_timer = 0.12
	if color_rect:
		color_rect.color = Color.WHITE

	# AGGRO SWITCH: If accidentally hit by another enemy or attacker, switch aggro to attacker!
	if attacker != null and is_instance_valid(attacker) and attacker != self:
		if "health" in attacker and attacker.health > 0:
			current_target = attacker

	_update_visual_color()

	if health <= 0.0:
		health = 0.0
		died.emit()
		queue_free()

func _update_visual_color() -> void:
	if not color_rect:
		return
	if _is_infighting():
		color_rect.color = infight_color
	else:
		color_rect.color = base_color

func _on_player_died() -> void:
	freeze = true
	velocity = Vector2.ZERO
	if is_jumping:
		is_jumping = false
		collision_mask = saved_collision_mask
		if color_rect:
			color_rect.position.y = -16.0

func _draw() -> void:
	# Draw health bar above enemy
	var bar_w := 32.0
	var bar_h := 4.0
	var bar_pos := Vector2(-16.0, -25.0)
	var hp_ratio := clampf(health / max_health, 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.8))
	var hp_color := Color(0.2, 0.85, 0.3) if hp_ratio > 0.4 else Color(0.95, 0.25, 0.2)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, bar_h)), hp_color)

	# If infighting, draw an aggro indicator
	if _is_infighting() and is_instance_valid(current_target):
		var local_target := current_target.global_position - global_position
		draw_line(Vector2.ZERO, local_target.limit_length(30.0), Color.ORANGE, 2.0)

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
