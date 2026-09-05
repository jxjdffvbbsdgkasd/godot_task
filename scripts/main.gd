extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var hp_label: Label = $CanvasLayer/hp
@onready var status_label: Label = $CanvasLayer/status

func _ready() -> void:
	if player:
		player.health_changed.connect(_on_player_health_changed)
		player.died.connect(_on_player_died)
		_update_hp_display(player.health)

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
	if status_label:
		status_label.text = "YOU DIED"
		status_label.modulate = Color.RED
	
	await get_tree().create_timer(5.0).timeout
	get_tree().reload_current_scene()

func _update_hp_display(hp: float) -> void:
	if hp_label:
		hp_label.text = "HP: %d / 100" % int(hp)
