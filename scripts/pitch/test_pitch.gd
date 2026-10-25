extends Node2D

@onready var player1: Player = $Player1
@onready var player2: Player = $Player2
@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

# HUD Labels
@onready var label_player: Label = $CanvasLayer/Panel/VBox/LabelPlayer
@onready var label_stats: Label = $CanvasLayer/Panel/VBox/LabelStats
@onready var label_pass_target: Label = $CanvasLayer/Panel/VBox/LabelPassTarget
@onready var label_ball: Label = $CanvasLayer/Panel/VBox/LabelBall
@onready var label_help: Label = $CanvasLayer/Panel/VBox/LabelHelp

# Parejas de prueba por equipo para probar pases y stats
var test_teams: Array[Dictionary] = [
	{
		"team_name": "Selección Verdeamarela",
		"p1": "bra_01", # El Mago (Pase: 91, Control: 95)
		"p2": "bra_02"  # El Fenómeno (Pase: 78, Control: 92)
	},
	{
		"team_name": "Selección Celeste",
		"p1": "arg_01", # El Diez (Pase: 94, Control: 95)
		"p2": "arg_02"  # El Cósmico (Pase: 93, Control: 96)
	},
	{
		"team_name": "Selección Azzurra",
		"p1": "ita_01", # El Maestro (Pase: 96, Control: 93)
		"p2": "ita_03"  # La Coleta Mágica (Pase: 89, Control: 91)
	},
	{
		"team_name": "Estrellas Mundiales",
		"p1": "star_01", # El Cíborg (Pase: 70, Control: 82)
		"p2": "star_02"  # El Relámpago (Pase: 81, Control: 86)
	},
	{
		"team_name": "Clásicos Legendarios",
		"p1": "vet_01",  # El Guante Dorado (Pase: 94, Control: 87)
		"p2": "vet_03"   # El Pitbull (Pase: 80, Control: 81)
	}
]
var current_team_index: int = 0

func _ready() -> void:
	ball.state_changed.connect(_on_ball_state_changed)
	ball.possession_changed.connect(_on_ball_possession_changed)
	ball.pass_completed.connect(_on_pass_completed)

	_apply_team(0)

func _apply_team(idx: int) -> void:
	current_team_index = idx % test_teams.size()
	var team_data = test_teams[current_team_index]

	player1.load_player(team_data["p1"])
	player1.set_user_controlled(true)
	player1.position = Vector2(-90, 0)

	player2.load_player(team_data["p2"])
	player2.set_user_controlled(false)
	player2.position = Vector2(130, -60)
	player2.tactical_offset = Vector2(180, -70)

	ball.position = Vector2(-40, 0)
	ball.set_libre(Vector2.ZERO)

	_update_hud()

func _process(_delta: float) -> void:
	var active_p = get_active_player()

	# Cámara suave siguiendo al jugador activo o a la pelota si está en vuelo
	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		camera.position = camera.position.lerp(ball.position, 0.12)
	elif is_instance_valid(active_p):
		camera.position = camera.position.lerp(active_p.position, 0.15)

	# Tecla Tab: cambiar pareja de equipo
	if Input.is_action_just_pressed("next_character"):
		_apply_team(current_team_index + 1)

	# Tecla R: reiniciar posiciones
	if Input.is_key_pressed(KEY_R):
		_reset_positions()

	_update_hud()

func get_active_player() -> Player:
	if is_instance_valid(player1) and player1.is_user_controlled:
		return player1
	if is_instance_valid(player2) and player2.is_user_controlled:
		return player2
	return player1

func _reset_positions() -> void:
	player1.position = Vector2(-90, 0)
	player2.position = Vector2(130, -60)
	ball.position = Vector2(-40, 0)
	ball.set_libre(Vector2.ZERO)

func _on_ball_state_changed(_new_state: Ball.State) -> void:
	_update_hud()

func _on_ball_possession_changed(_carrier: CharacterBody2D) -> void:
	_update_hud()

func _on_pass_completed(receiver: CharacterBody2D) -> void:
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(label_player):
		return

	var active_p = get_active_player()
	var team_data = test_teams[current_team_index]

	if is_instance_valid(active_p):
		var ctrl = active_p.stats.get("control", 0)
		var vel = active_p.stats.get("velocidad", 0)
		var pase = active_p.stats.get("pase", 0)
		var tiro = active_p.stats.get("tiro", 0)

		label_player.text = "[%s] Jugador Activo: %s (%s)" % [team_data["team_name"], active_p.player_name, active_p.player_id]
		label_stats.text = "PASE: %d | CONTROL: %d | VELOCIDAD: %d | TIRO: %d" % [pase, ctrl, vel, tiro]

		if active_p.has_ball:
			if is_instance_valid(active_p.current_pass_target):
				label_pass_target.text = "Receptor Enfocado: %s [PASE DISPONIBLE]" % active_p.current_pass_target.player_name
				label_pass_target.modulate = Color(1.0, 0.9, 0.2)
			else:
				label_pass_target.text = "Receptor: Sin compañero en cono de pase (apuntá hacia él)"
				label_pass_target.modulate = Color(0.7, 0.7, 0.7)
		else:
			label_pass_target.text = "Sin pelota (acercate a ella o presioná Z para cambiar)"
			label_pass_target.modulate = Color(0.6, 0.65, 0.7)

	if is_instance_valid(ball):
		var state_str = ""
		match ball.current_state:
			Ball.State.LIBRE:
				state_str = "LIBRE (rueda y frena sola)"
			Ball.State.CONTROLADA:
				var c_name = ball.carrier.player_name if ball.carrier is Player else "Jugador"
				state_str = "CONTROLADA por %s" % c_name
			Ball.State.EN_VUELO:
				var target_str = ""
				if is_instance_valid(ball.target_receiver):
					target_str = " -> Hacia %s" % ball.target_receiver.player_name
				state_str = "EN VUELO (vel: %.0f px/s)%s" % [ball.velocity.length(), target_str]
		label_ball.text = "Pelota: %s" % state_str

	label_help.text = "[Flechas / WASD] Moverse | [Toque Corto X/Espacio] Pase Dirigido | [Mantener X] Tiro | [Z] Cambiar Jugador | [Tab] Cambiar Equipo"
