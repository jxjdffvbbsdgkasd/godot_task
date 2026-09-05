extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var hp_label: Label = $CanvasLayer/hp
@onready var status_label: Label = $CanvasLayer/status
@onready var background: ColorRect = $Background
@onready var top_wall: CollisionShape2D = $bounds/top
@onready var bottom_wall: CollisionShape2D = $bounds/bottom
@onready var left_wall: CollisionShape2D = $bounds/left
@onready var right_wall: CollisionShape2D = $bounds/right

var is_game_over: bool = false

func _ready() -> void:
	# Adapt map boundaries and background to current viewport/window size
	get_viewport().size_changed.connect(_update_map_to_window)
	_update_map_to_window()

	if player:
		player.health_changed.connect(_on_player_health_changed)
		player.died.connect(_on_player_died)
		_update_hp_display(player.health)

	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.has_signal("died"):
			e.died.connect(_on_enemy_died)

func _update_map_to_window() -> void:
	var view_size := get_viewport_rect().size
	if background:
		background.size = view_size
	
	if top_wall and top_wall.shape is RectangleShape2D:
		var s := top_wall.shape as RectangleShape2D
		s.size = Vector2(view_size.x + 200.0, 40.0)
		top_wall.position = Vector2(view_size.x * 0.5, -20.0)
		
	if bottom_wall and bottom_wall.shape is RectangleShape2D:
		var s := bottom_wall.shape as RectangleShape2D
		s.size = Vector2(view_size.x + 200.0, 40.0)
		bottom_wall.position = Vector2(view_size.x * 0.5, view_size.y + 20.0)
		
	if left_wall and left_wall.shape is RectangleShape2D:
		var s := left_wall.shape as RectangleShape2D
		s.size = Vector2(40.0, view_size.y + 200.0)
		left_wall.position = Vector2(-20.0, view_size.y * 0.5)
		
	if right_wall and right_wall.shape is RectangleShape2D:
		var s := right_wall.shape as RectangleShape2D
		s.size = Vector2(40.0, view_size.y + 200.0)
		right_wall.position = Vector2(view_size.x + 20.0, view_size.y * 0.5)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
		get_tree().reload_current_scene()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_player_health_changed(new_health: float) -> void:
	_update_hp_display(new_health)

func _on_player_died() -> void:
	if is_game_over:
		return
	is_game_over = true

	if status_label:
		status_label.text = "YOU DIED"
		status_label.modulate = Color.RED
	
	await get_tree().create_timer(4.0).timeout
	get_tree().reload_current_scene()

func _on_enemy_died() -> void:
	if is_game_over:
		return
	
	await get_tree().process_frame
	
	var alive_enemies := get_tree().get_nodes_in_group("enemies").filter(
		func(e): return is_instance_valid(e) and not e.is_queued_for_deletion() and ("health" in e and e.health > 0)
	)
	
	if alive_enemies.is_empty():
		_on_all_enemies_died()

func _on_all_enemies_died() -> void:
	if is_game_over:
		return
	is_game_over = true

	if status_label:
		status_label.text = "VICTORY"
		status_label.modulate = Color(0.2, 0.9, 0.3, 1.0)
	
	await get_tree().create_timer(4.0).timeout
	get_tree().reload_current_scene()

func _update_hp_display(hp: float) -> void:
	if hp_label:
		hp_label.text = "HP: %d / 100" % int(hp)
