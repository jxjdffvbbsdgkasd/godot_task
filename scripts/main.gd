extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var hp_label: Label = $CanvasLayer/hp
@onready var status_label: Label = $CanvasLayer/status

var is_game_over: bool = false

func _ready() -> void:
	if player:
		player.health_changed.connect(_on_player_health_changed)
		player.died.connect(_on_player_died)
		_update_hp_display(player.health)

	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.has_signal("died"):
			e.died.connect(_on_enemy_died)

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
