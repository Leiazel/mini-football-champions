extends Node2D

# Nodos de porterías
@onready var goal_left: Goal = $GoalLeft
@onready var goal_right: Goal = $GoalRight

# Nodos de arqueros
@onready var gk_left: Goalkeeper = $GoalkeeperLeft
@onready var gk_right: Goalkeeper = $GoalkeeperRight

# Jugadores de campo del usuario (3: DF, MF, FW)
@onready var user_p1: Player = $UserPlayer1
@onready var user_p2: Player = $UserPlayer2
@onready var user_p3: Player = $UserPlayer3

# Jugadores de campo rivales con IA (3: DF, MF, FW)
@onready var rival_p1: Player = $RivalPlayer1
@onready var rival_p2: Player = $RivalPlayer2
@onready var rival_p3: Player = $RivalPlayer3

# Pelota y cámara
@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

# HUD Labels
@onready var label_title: Label = $CanvasLayer/Panel/VBox/LabelTitle
@onready var label_score: Label = $CanvasLayer/Panel/VBox/LabelScore
@onready var label_player: Label = $CanvasLayer/Panel/VBox/LabelPlayer
@onready var label_stats: Label = $CanvasLayer/Panel/VBox/LabelStats
@onready var label_status: Label = $CanvasLayer/Panel/VBox/LabelStatus
@onready var label_ball: Label = $CanvasLayer/Panel/VBox/LabelBall
@onready var label_help: Label = $CanvasLayer/Panel/VBox/LabelHelp
@onready var label_goal_banner: Label = $CanvasLayer/GoalBanner

var score_user: int = 0
var score_opp: int = 0
var total_steals: int = 0
var goal_celebration_timer: float = 0.0

# Configuraciones de emparejamientos con los 6 equipos y sus arqueros únicos
var matchups: Array[Dictionary] = [
	{
		"user_team_name": "Selección Verdeamarela",
		"user_ids": ["bra_03", "bra_01", "bra_02"],
		"user_gk": "gk_bra",
		"opp_team_name": "Estrellas Mundiales",
		"opp_ids": ["star_04", "star_03", "star_01"],
		"opp_gk": "gk_star"
	},
	{
		"user_team_name": "Selección Celeste",
		"user_ids": ["arg_04", "arg_02", "arg_01"],
		"user_gk": "gk_arg",
		"opp_team_name": "Selección Azzurra",
		"opp_ids": ["ita_02", "ita_01", "ita_03"],
		"opp_gk": "gk_ita"
	},
	{
		"user_team_name": "Clásicos Legendarios",
		"user_ids": ["vet_03", "vet_01", "vet_02"],
		"user_gk": "gk_vet",
		"opp_team_name": "Los Desafiantes",
		"opp_ids": ["leg_02", "leg_01", "bra_04"],
		"opp_gk": "gk_leg"
	}
]
var current_matchup_index: int = 0

func _ready() -> void:
	ball.state_changed.connect(_on_ball_state_changed)
	ball.possession_changed.connect(_on_ball_possession_changed)
	ball.pass_completed.connect(_on_pass_completed)

	if is_instance_valid(goal_left):
		goal_left.goal_scored.connect(_on_goal_left_scored)
	if is_instance_valid(goal_right):
		goal_right.goal_scored.connect(_on_goal_right_scored)

	if is_instance_valid(gk_left):
		gk_left.shot_saved.connect(_on_shot_saved)
	if is_instance_valid(gk_right):
		gk_right.shot_saved.connect(_on_shot_saved)

	for p in [user_p1, user_p2, user_p3, rival_p1, rival_p2, rival_p3]:
		if is_instance_valid(p):
			p.ball_stolen.connect(_on_ball_stolen)

	_apply_matchup(0)

func _apply_matchup(idx: int) -> void:
	current_matchup_index = idx % matchups.size()
	var m = matchups[current_matchup_index]

	# Equipo Usuario: [0]=DF, [1]=MF, [2]=FW
	user_p1.load_player(m["user_ids"][0])
	user_p1.role = "DF"
	user_p1.team_id = "team_user"
	user_p1.is_ai = false
	user_p1.target_goal_x = 1200.0
	user_p1.set_user_controlled(false)

	user_p2.load_player(m["user_ids"][1])
	user_p2.role = "MF"
	user_p2.team_id = "team_user"
	user_p2.is_ai = false
	user_p2.target_goal_x = 1200.0
	user_p2.set_user_controlled(true)

	user_p3.load_player(m["user_ids"][2])
	user_p3.role = "FW"
	user_p3.team_id = "team_user"
	user_p3.is_ai = false
	user_p3.target_goal_x = 1200.0
	user_p3.set_user_controlled(false)

	gk_left.load_goalkeeper(m["user_gk"])
	gk_left.team_id = "team_user"

	# Equipo Rival (IA): [0]=DF, [1]=MF, [2]=FW
	rival_p1.load_player(m["opp_ids"][0])
	rival_p1.role = "DF"
	rival_p1.team_id = "team_opp"
	rival_p1.is_ai = true
	rival_p1.target_goal_x = -1200.0
	rival_p1.set_user_controlled(false)

	rival_p2.load_player(m["opp_ids"][1])
	rival_p2.role = "MF"
	rival_p2.team_id = "team_opp"
	rival_p2.is_ai = true
	rival_p2.target_goal_x = -1200.0
	rival_p2.set_user_controlled(false)

	rival_p3.load_player(m["opp_ids"][2])
	rival_p3.role = "FW"
	rival_p3.team_id = "team_opp"
	rival_p3.is_ai = true
	rival_p3.target_goal_x = -1200.0
	rival_p3.set_user_controlled(false)

	gk_right.load_goalkeeper(m["opp_gk"])
	gk_right.team_id = "team_opp"

	_reset_formation()
	_update_hud()

func _reset_formation() -> void:
	user_p1.set_home_position(Vector2(-620, 40))
	user_p2.set_home_position(Vector2(-240, -140))
	user_p3.set_home_position(Vector2(380, 120))
	user_p3.global_position = Vector2(-110, 80)

	rival_p1.set_home_position(Vector2(620, -40))
	rival_p2.set_home_position(Vector2(240, 140))
	rival_p3.set_home_position(Vector2(-380, -120))
	rival_p3.global_position = Vector2(140, -80)

	if is_instance_valid(gk_left):
		gk_left.position = Vector2(-1140, 0)
	if is_instance_valid(gk_right):
		gk_right.position = Vector2(1140, 0)

	ball.position = Vector2(0, 0)
	ball.set_libre(Vector2.ZERO)

func _process(delta: float) -> void:
	var active_p = get_active_user_player()

	if goal_celebration_timer > 0.0:
		goal_celebration_timer -= delta
		label_goal_banner.visible = true
		if goal_celebration_timer <= 0.0:
			label_goal_banner.visible = false
			_reset_formation()
	else:
		label_goal_banner.visible = false

	# Cámara suave con límites
	var cam_target := Vector2.ZERO
	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		cam_target = ball.position
	elif is_instance_valid(active_p) and is_instance_valid(ball):
		cam_target = active_p.position.lerp(ball.position, 0.35)
	elif is_instance_valid(active_p):
		cam_target = active_p.position

	cam_target.x = clampf(cam_target.x, -560.0, 560.0)
	cam_target.y = clampf(cam_target.y, -320.0, 320.0)
	camera.position = camera.position.lerp(cam_target, 0.14)

	if Input.is_action_just_pressed("next_character"):
		_apply_matchup(current_matchup_index + 1)

	if Input.is_key_pressed(KEY_R):
		_reset_formation()

	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/menu/TeamSelectMenu.tscn")

	_update_hud()

func get_active_user_player() -> Player:
	for p in [user_p1, user_p2, user_p3]:
		if is_instance_valid(p) and p.is_user_controlled:
			return p
	return user_p2

func _on_goal_right_scored(_g_name: String) -> void:
	score_user += 1
	goal_celebration_timer = 1.8
	var m = matchups[current_matchup_index]
	label_goal_banner.text = "¡¡¡ GOOOOOL DE %s !!!" % m["user_team_name"].to_upper()
	label_goal_banner.modulate = Color(0.2, 1.0, 0.4)

func _on_goal_left_scored(_g_name: String) -> void:
	score_opp += 1
	goal_celebration_timer = 1.8
	var m = matchups[current_matchup_index]
	label_goal_banner.text = "¡¡¡ GOL RIVAL (%s) !!!" % m["opp_team_name"].to_upper()
	label_goal_banner.modulate = Color(1.0, 0.3, 0.3)

func _on_shot_saved(gk: Goalkeeper) -> void:
	label_goal_banner.text = "¡PARADÓN DE %s!" % gk.player_name
	label_goal_banner.modulate = Color(1.0, 0.85, 0.2)
	label_goal_banner.visible = true
	goal_celebration_timer = 0.9

func _on_ball_stolen(tackler: Player, victim: Player) -> void:
	total_steals += 1
	var tag = "¡ROBO EXITOSO!" if tackler.team_id == "team_user" else "¡BALÓN RECUPERADO POR RIVAL!"
	label_status.text = "%s (%s desarmó a %s)" % [tag, tackler.player_name, victim.player_name]
	label_status.modulate = Color(0.3, 1.0, 0.6) if tackler.team_id == "team_user" else Color(1.0, 0.4, 0.4)

func _on_ball_state_changed(_new_state: Ball.State) -> void:
	_update_hud()

func _on_ball_possession_changed(_carrier: CharacterBody2D) -> void:
	_update_hud()

func _on_pass_completed(_receiver: CharacterBody2D) -> void:
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(label_player):
		return

	var m = matchups[current_matchup_index]
	var active_p = get_active_user_player()

	label_score.text = "%s  %d - %d  %s   (Robos totales: %d)" % [
		m["user_team_name"], score_user, score_opp, m["opp_team_name"], total_steals
	]

	if is_instance_valid(active_p):
		var ctrl = active_p.stats.get("control", 0)
		var vel = active_p.stats.get("velocidad", 0)
		var def_stat = active_p.stats.get("defensa", 0)
		var tiro = active_p.stats.get("tiro", 0)
		var pase = active_p.stats.get("pase", 0)

		label_player.text = "Controlando: %s (%s) [Rol: %s]" % [active_p.player_name, active_p.player_id, active_p.role]
		label_stats.text = "CTRL: %d | DEF: %d | VEL: %d | TIRO: %d | PASE: %d" % [ctrl, def_stat, vel, tiro, pase]

		if active_p.has_ball:
			if is_instance_valid(active_p.current_pass_target):
				label_status.text = "Pase: Compañero Enfocado (%s) [Toque X/Espacio]" % active_p.current_pass_target.player_name
				label_status.modulate = Color(1.0, 0.9, 0.2)
			else:
				label_status.text = "Conducción: Mantener [X/Espacio] para Tiro al arco"
				label_status.modulate = Color(0.3, 0.9, 0.5)
		else:
			if not label_status.text.contains("ROBO"):
				label_status.text = "Sin balón: Acercate al rival para robar con tu Defensa (%d)" % def_stat
				label_status.modulate = Color(0.7, 0.75, 0.8)

	if is_instance_valid(ball):
		var state_str = ""
		match ball.current_state:
			Ball.State.LIBRE:
				state_str = "LIBRE"
			Ball.State.CONTROLADA:
				var c_name = ball.carrier.player_name if ball.carrier is Player or ball.carrier is Goalkeeper else "Jugador"
				state_str = "EN PODER DE %s" % c_name
			Ball.State.EN_VUELO:
				state_str = "EN VUELO (vel: %.0f px/s)" % ball.velocity.length()
		label_ball.text = "Pelota: %s" % state_str

	label_help.text = "[Flechas/WASD] Mover | [Toque X/Espacio] Pase | [Mantener X/Espacio] Tiro | [Z/Q] Cambiar | [Tab] Equipos | [R] Reiniciar"
