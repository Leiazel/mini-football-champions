extends Node2D

@onready var player1: Player = $Player1
@onready var player2: Player = $Player2
@onready var goalkeeper: Goalkeeper = $Goalkeeper
@onready var goal_right: Goal = $GoalRight
@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

# HUD Labels
@onready var label_player: Label = $CanvasLayer/Panel/VBox/LabelPlayer
@onready var label_stats: Label = $CanvasLayer/Panel/VBox/LabelStats
@onready var label_pass_target: Label = $CanvasLayer/Panel/VBox/LabelPassTarget
@onready var label_ball: Label = $CanvasLayer/Panel/VBox/LabelBall
@onready var label_score: Label = $CanvasLayer/Panel/VBox/LabelScore
@onready var label_help: Label = $CanvasLayer/Panel/VBox/LabelHelp
@onready var label_goal_banner: Label = $CanvasLayer/GoalBanner

# Marcador
var goals_scored: int = 0
var saves_count: int = 0
var goal_celebration_timer: float = 0.0

# Parejas de prueba por equipo para probar pases y stats
var test_teams: Array[Dictionary] = [
	{
		"team_name": "Selección Verdeamarela",
		"p1": "bra_01", # El Mago (Pase: 91, Control: 95, Tiro: 88)
		"p2": "bra_02"  # El Fenómeno (Pase: 78, Control: 92, Tiro: 94)
	},
	{
		"team_name": "Selección Celeste",
		"p1": "arg_03", # El Cañonero (Tiro: 95, Pase: 75, Control: 82)
		"p2": "arg_01"  # El Diez (Tiro: 92, Pase: 94, Control: 95)
	},
	{
		"team_name": "Estrellas Mundiales",
		"p1": "star_01", # El Cíborg (Tiro: 95, Pase: 70, Control: 82)
		"p2": "star_03"  # El Comandante (Tiro: 94, Pase: 82, Control: 88)
	},
	{
		"team_name": "Selección Azzurra",
		"p1": "ita_01", # El Maestro (Tiro: 85, Pase: 96, Control: 93)
		"p2": "ita_03"  # La Coleta Mágica (Tiro: 89, Pase: 89, Control: 91)
	},
	{
		"team_name": "Clásicos Legendarios",
		"p1": "vet_01",  # El Guante Dorado (Tiro: 86, Pase: 94, Control: 87)
		"p2": "vet_02"   # La Furia Rubia (Tiro: 88, Pase: 85, Control: 84)
	}
]
var current_team_index: int = 0

func _ready() -> void:
	ball.state_changed.connect(_on_ball_state_changed)
	ball.possession_changed.connect(_on_ball_possession_changed)
	ball.pass_completed.connect(_on_pass_completed)

	if is_instance_valid(goal_right):
		goal_right.goal_scored.connect(_on_goal_scored)
	if is_instance_valid(goalkeeper):
		goalkeeper.shot_saved.connect(_on_shot_saved)

	_apply_team(0)

func _apply_team(idx: int) -> void:
	current_team_index = idx % test_teams.size()
	var team_data = test_teams[current_team_index]

	player1.load_player(team_data["p1"])
	player1.set_user_controlled(true)
	player1.position = Vector2(200, 0)

	player2.load_player(team_data["p2"])
	player2.set_user_controlled(false)
	player2.position = Vector2(360, -70)
	player2.tactical_offset = Vector2(160, -70)

	ball.position = Vector2(250, 0)
	ball.set_libre(Vector2.ZERO)

	_update_hud()

func _process(delta: float) -> void:
	var active_p = get_active_player()

	# Banner de gol
	if goal_celebration_timer > 0.0:
		goal_celebration_timer -= delta
		label_goal_banner.visible = true
		if goal_celebration_timer <= 0.0:
			label_goal_banner.visible = false
			_reset_positions_after_goal()
	else:
		label_goal_banner.visible = false

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
	player1.position = Vector2(200, 0)
	player2.position = Vector2(360, -70)
	ball.position = Vector2(250, 0)
	ball.set_libre(Vector2.ZERO)

func _reset_positions_after_goal() -> void:
	player1.position = Vector2(0, 0)
	player2.position = Vector2(80, -60)
	ball.position = Vector2(0, 0)
	ball.set_libre(Vector2.ZERO)

func _on_goal_scored(_g_name: String) -> void:
	goals_scored += 1
	goal_celebration_timer = 1.6
	label_goal_banner.text = "¡¡¡ GOOOOOOOL !!!"

func _on_shot_saved(gk: Goalkeeper) -> void:
	saves_count += 1
	label_goal_banner.text = "¡ATAJADA DE %s!" % gk.player_name
	label_goal_banner.visible = true
	goal_celebration_timer = 0.85

func _on_ball_state_changed(_new_state: Ball.State) -> void:
	_update_hud()

func _on_ball_possession_changed(_carrier: CharacterBody2D) -> void:
	_update_hud()

func _on_pass_completed(_receiver: CharacterBody2D) -> void:
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
		label_stats.text = "TIRO: %d | PASE: %d | CONTROL: %d | VELOCIDAD: %d" % [tiro, pase, ctrl, vel]

		if active_p.has_ball:
			if is_instance_valid(active_p.current_pass_target):
				label_pass_target.text = "Pase: Compañero Enfocado (%s)  [Toque Corto X]" % active_p.current_pass_target.player_name
				label_pass_target.modulate = Color(1.0, 0.9, 0.2)
			else:
				label_pass_target.text = "Tiro al arco: Mantener [X / Espacio] para cargar potencia"
				label_pass_target.modulate = Color(0.3, 0.9, 0.5)
		else:
			label_pass_target.text = "Sin posesión de la pelota"
			label_pass_target.modulate = Color(0.65, 0.7, 0.75)

	if is_instance_valid(goalkeeper):
		label_score.text = "MARCADOR: %d GOLES  |  ATAJADAS DEL ARQUERO: %d (Reflejos: %d)" % [
			goals_scored, saves_count, goalkeeper.stats.get("reflejos", 85)
		]

	if is_instance_valid(ball):
		var state_str = ""
		match ball.current_state:
			Ball.State.LIBRE:
				state_str = "LIBRE"
			Ball.State.CONTROLADA:
				var c_name = ball.carrier.player_name if ball.carrier is Player or ball.carrier is Goalkeeper else "Jugador"
				state_str = "CONTROLADA por %s" % c_name
			Ball.State.EN_VUELO:
				state_str = "EN VUELO (vel: %.0f px/s)" % ball.velocity.length()
		label_ball.text = "Pelota: %s" % state_str

	label_help.text = "[Flechas/WASD] Mover | [Mantener X] TIRO AL ARCO | [Toque Corto X] Pase | [Z] Cambiar Jugador | [Tab] Equipo"
