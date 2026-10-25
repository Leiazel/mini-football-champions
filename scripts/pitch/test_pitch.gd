extends Node2D

@onready var player: Player = $Player
@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

# HUD Labels
@onready var label_player: Label = $CanvasLayer/Panel/VBox/LabelPlayer
@onready var label_stats: Label = $CanvasLayer/Panel/VBox/LabelStats
@onready var label_ball: Label = $CanvasLayer/Panel/VBox/LabelBall
@onready var label_help: Label = $CanvasLayer/Panel/VBox/LabelHelp

var sample_players: Array[String] = [
	"bra_01", # El Mago (Control 95)
	"arg_01", # El Diez (Control 95)
	"star_01", # El Cíborg (Control 82)
	"ita_02", # El Muro (Control 72)
	"leg_01", # La Melena Dorada (Control 92)
	"arg_04"  # El Motor (Control 80)
]
var current_player_index: int = 0

func _ready() -> void:
	player.player_loaded.connect(_on_player_loaded)
	ball.state_changed.connect(_on_ball_state_changed)
	ball.possession_changed.connect(_on_ball_possession_changed)

	_update_hud()

func _process(_delta: float) -> void:
	# La cámara sigue al jugador o a la pelota si está en vuelo
	if is_instance_valid(player):
		if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
			camera.position = camera.position.lerp(ball.position, 0.1)
		else:
			camera.position = camera.position.lerp(player.position, 0.15)

	# Tecla Tab / cambio de jugador de prueba
	if Input.is_action_just_pressed("next_character"):
		_cycle_test_player()

	# Tecla R para reiniciar pelota
	if Input.is_key_pressed(KEY_R):
		_reset_ball()

	_update_hud()

func _cycle_test_player() -> void:
	current_player_index = (current_player_index + 1) % sample_players.size()
	var new_id = sample_players[current_player_index]
	player.load_player(new_id)

func _reset_ball() -> void:
	ball.global_position = player.global_position + Vector2(60, 0)
	ball.set_libre(Vector2.ZERO)

func _on_player_loaded(_p_data: Dictionary) -> void:
	_update_hud()

func _on_ball_state_changed(_new_state: Ball.State) -> void:
	_update_hud()

func _on_ball_possession_changed(_carrier: CharacterBody2D) -> void:
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(label_player):
		return

	if is_instance_valid(player):
		var ctrl = player.stats.get("control", 0)
		var vel = player.stats.get("velocidad", 0)
		var tiro = player.stats.get("tiro", 0)

		label_player.text = "Jugador Activo: %s (%s) [%s]" % [player.player_name, player.player_id, player.role]
		label_stats.text = "CONTROL: %d | VELOCIDAD: %d | TIRO: %d" % [ctrl, vel, tiro]

	if is_instance_valid(ball):
		var state_str = ""
		match ball.current_state:
			Ball.State.LIBRE:
				state_str = "LIBRE (rueda y frena con fricción)"
			Ball.State.CONTROLADA:
				var dist = player.global_position.distance_to(ball.global_position)
				state_str = "CONTROLADA por %s (dist: %.1f px)" % [player.player_name, dist]
			Ball.State.EN_VUELO:
				state_str = "EN VUELO (vel: %.1f px/s)" % [ball.velocity.length()]
		label_ball.text = "Pelota: %s" % state_str

	label_help.text = "[Flechas / WASD] Moverse  |  [Shift] Correr  |  [Espacio / X] Patear  |  [Tab] Cambiar Jugador  |  [R] Reiniciar Pelota"
