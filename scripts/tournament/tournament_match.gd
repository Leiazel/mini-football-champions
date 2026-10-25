extends Node2D

# Componentes de campo
@onready var goal_left: Goal = $GoalLeft
@onready var goal_right: Goal = $GoalRight
@onready var gk_left: Goalkeeper = $GoalkeeperLeft
@onready var gk_right: Goalkeeper = $GoalkeeperRight

@onready var user_p1: Player = $UserPlayer1
@onready var user_p2: Player = $UserPlayer2
@onready var rival_p1: Player = $RivalPlayer1
@onready var rival_p2: Player = $RivalPlayer2

@onready var ball: Ball = $Ball
@onready var camera: Camera2D = $Camera2D

# HUD e interfaz de torneo
@onready var label_round: Label = $CanvasLayer/Panel/VBox/LabelRound
@onready var label_score: Label = $CanvasLayer/Panel/VBox/LabelScore
@onready var label_clock: Label = $CanvasLayer/Panel/VBox/LabelClock
@onready var label_player: Label = $CanvasLayer/Panel/VBox/LabelPlayer
@onready var label_stats: Label = $CanvasLayer/Panel/VBox/LabelStats
@onready var label_status: Label = $CanvasLayer/Panel/VBox/LabelStatus
@onready var label_ball: Label = $CanvasLayer/Panel/VBox/LabelBall
@onready var label_help: Label = $CanvasLayer/Panel/VBox/LabelHelp

# Banner y Modales
@onready var label_goal_banner: Label = $CanvasLayer/GoalBanner
@onready var modal_panel: PanelContainer = $CanvasLayer/ModalPanel
@onready var modal_title: Label = $CanvasLayer/ModalPanel/VBox/ModalTitle
@onready var modal_msg: Label = $CanvasLayer/ModalPanel/VBox/ModalMsg
@onready var modal_btn_prompt: Label = $CanvasLayer/ModalPanel/VBox/ModalBtnPrompt

var manager: TournamentManager = null
var celebration_timer: float = 0.0
var current_opp_team_id: String = ""

func _ready() -> void:
	manager = TournamentManager.new()
	add_child(manager)

	manager.round_started.connect(_on_round_started)
	manager.score_updated.connect(_on_score_updated)
	manager.match_ended.connect(_on_match_ended)

	ball.state_changed.connect(_on_ball_state_changed)
	ball.possession_changed.connect(_on_ball_possession_changed)

	goal_left.goal_scored.connect(_on_goal_left_scored)
	goal_right.goal_scored.connect(_on_goal_right_scored)

	gk_left.shot_saved.connect(_on_shot_saved)
	gk_right.shot_saved.connect(_on_shot_saved)

	for p in [user_p1, user_p2, rival_p1, rival_p2]:
		if is_instance_valid(p):
			p.ball_stolen.connect(_on_ball_stolen)

	# Iniciar la primera ronda del torneo
	manager.start_round(0)

func _on_round_started(round_data: Dictionary, user_team: Dictionary, opp_team: Dictionary) -> void:
	modal_panel.visible = false
	current_opp_team_id = opp_team.get("id", "")

	# Cargar titulares del usuario
	var u_forms = user_team.get("formation", ["bra_01", "bra_02"])
	user_p1.load_player(u_forms[0])
	user_p1.team_id = "team_user"
	user_p1.is_ai = false
	user_p1.target_goal_x = 800.0
	user_p1.set_user_controlled(true)

	user_p2.load_player(u_forms[1] if u_forms.size() > 1 else u_forms[0])
	user_p2.team_id = "team_user"
	user_p2.is_ai = false
	user_p2.target_goal_x = 800.0
	user_p2.set_user_controlled(false)
	user_p2.tactical_offset = Vector2(140, -80)

	var u_gk = user_team.get("gk_id", "gk_02")
	gk_left.load_goalkeeper(u_gk)
	gk_left.team_id = "team_user"

	# Cargar rivales según datos de la ronda
	var o_forms = opp_team.get("formation", ["star_01", "star_02"])
	rival_p1.load_player(o_forms[0])
	rival_p1.team_id = "team_opp"
	rival_p1.is_ai = true
	rival_p1.target_goal_x = -800.0
	rival_p1.set_user_controlled(false)

	rival_p2.load_player(o_forms[1] if o_forms.size() > 1 else o_forms[0])
	rival_p2.team_id = "team_opp"
	rival_p2.is_ai = true
	rival_p2.target_goal_x = -800.0
	rival_p2.set_user_controlled(false)
	rival_p2.tactical_offset = Vector2(-140, 80)

	var o_gk = opp_team.get("gk_id", "gk_01")
	gk_right.load_goalkeeper(o_gk)
	gk_right.team_id = "team_opp"

	_reset_pitch_formation()

	label_round.text = "🏆 MODO TORNEO: %s (NIVEL %d/6)" % [
		round_data.get("name", "Partido").to_upper(),
		round_data.get("level", 1)
	]
	_update_hud()

func _reset_pitch_formation() -> void:
	user_p1.position = Vector2(-150, 0)
	user_p2.position = Vector2(-230, -85)
	rival_p1.position = Vector2(150, 20)
	rival_p2.position = Vector2(230, -75)

	gk_left.position = Vector2(-720, 0)
	gk_right.position = Vector2(720, 0)

	ball.position = Vector2(0, 0)
	ball.set_libre(Vector2.ZERO)

func _process(delta: float) -> void:
	if manager.is_active:
		manager.update_time(delta)

	if celebration_timer > 0.0:
		celebration_timer -= delta
		label_goal_banner.visible = true
		if celebration_timer <= 0.0:
			label_goal_banner.visible = false
			_reset_pitch_formation()
	else:
		label_goal_banner.visible = false

	# Entrada del usuario en modales de fin de partido
	if modal_panel.visible:
		if Input.is_action_just_pressed("action_pass") or Input.is_key_pressed(KEY_SPACE):
			if manager.is_champion:
				manager.start_round(0) # Reiniciar torneo
			elif manager.user_score > manager.opp_score:
				manager.next_round()
			else:
				manager.restart_current_round()
		elif Input.is_key_pressed(KEY_R):
			manager.restart_current_round()

	# Cámara suave
	var active_p = get_active_user_player()
	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		camera.position = camera.position.lerp(ball.position, 0.12)
	elif is_instance_valid(active_p):
		camera.position = camera.position.lerp(active_p.position, 0.15)

	_update_hud()

func get_active_user_player() -> Player:
	if is_instance_valid(user_p1) and user_p1.is_user_controlled:
		return user_p1
	if is_instance_valid(user_p2) and user_p2.is_user_controlled:
		return user_p2
	return user_p1

func _on_goal_right_scored(_g_name: String) -> void:
	if not manager.is_active:
		return
	manager.score_user_goal()
	celebration_timer = 1.7
	label_goal_banner.text = "¡¡¡ GOOOOOL DE TU EQUIPO !!!"
	label_goal_banner.modulate = Color(0.2, 1.0, 0.4)

func _on_goal_left_scored(_g_name: String) -> void:
	if not manager.is_active:
		return
	manager.score_opp_goal()
	celebration_timer = 1.7
	label_goal_banner.text = "¡¡¡ GOL DEL RIVAL !!!"
	label_goal_banner.modulate = Color(1.0, 0.3, 0.3)

func _on_shot_saved(gk: Goalkeeper) -> void:
	label_goal_banner.text = "¡PARADÓN DE %s!" % gk.player_name
	label_goal_banner.modulate = Color(1.0, 0.85, 0.2)
	label_goal_banner.visible = true
	celebration_timer = 0.85

func _on_ball_stolen(tackler: Player, victim: Player) -> void:
	var tag = "¡ROBO EXITOSO!" if tackler.team_id == "team_user" else "¡BALÓN RECUPERADO POR RIVAL!"
	label_status.text = "%s (%s desarmó a %s)" % [tag, tackler.player_name, victim.player_name]
	label_status.modulate = Color(0.3, 1.0, 0.6) if tackler.team_id == "team_user" else Color(1.0, 0.4, 0.4)

func _on_score_updated(u_score: int, o_score: int) -> void:
	var u_name = manager.get_team(manager.user_team_id).get("name", "TU EQUIPO")
	var o_name = manager.get_team(current_opp_team_id).get("name", "RIVAL")
	label_score.text = "%s  %d - %d  %s" % [u_name, u_score, o_score, o_name]

func _on_match_ended(user_won: bool, is_champ: bool) -> void:
	modal_panel.visible = true
	var round_info = manager.get_current_round()

	if is_champ:
		modal_title.text = "¡¡¡ CAMPEÓN CONTINENTAL !!! 🏆"
		modal_title.modulate = Color(1.0, 0.88, 0.2)
		modal_msg.text = "¡Derrotaste a la legendaria Selección Celeste en la gran final!\nTu equipo se consagra en lo más alto del torneo."
		modal_btn_prompt.text = "[Presioná ESPACIO para jugar otro Torneo]"
	elif user_won:
		modal_title.text = "¡VICTORIA Y CLASIFICACIÓN! ⚽"
		modal_title.modulate = Color(0.2, 1.0, 0.4)
		modal_msg.text = "Superaste la fase: %s.\nPrepárate para enfrentar al siguiente rival de mayor dificultad." % round_info.get("name", "")
		modal_btn_prompt.text = "[Presioná ESPACIO para avanzar a la Siguiente Ronda]"
	else:
		modal_title.text = "ELIMINADO DEL TORNEO ❌"
		modal_title.modulate = Color(1.0, 0.3, 0.3)
		modal_msg.text = "Has sido superado por %s.\nRefina tus pases, tiros y defensa para volver a intentarlo." % manager.get_team(current_opp_team_id).get("name", "el rival")
		modal_btn_prompt.text = "[Presioná ESPACIO o R para Reintentar esta Ronda]"

func _on_ball_state_changed(_s: Ball.State) -> void:
	_update_hud()

func _on_ball_possession_changed(_c: CharacterBody2D) -> void:
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(label_player):
		return

	var mins = int(manager.time_left) / 60
	var secs = int(manager.time_left) % 60
	label_clock.text = "TIEMPO: %02d:%02d" % [mins, secs]

	var active_p = get_active_user_player()
	if is_instance_valid(active_p):
		var ctrl = active_p.stats.get("control", 0)
		var vel = active_p.stats.get("velocidad", 0)
		var def_stat = active_p.stats.get("defensa", 0)
		var tiro = active_p.stats.get("tiro", 0)
		var pase = active_p.stats.get("pase", 0)

		label_player.text = "Controlando: %s (%s) [%s]" % [active_p.player_name, active_p.player_id, active_p.role]
		label_stats.text = "CTRL: %d | DEF: %d | VEL: %d | TIRO: %d | PASE: %d" % [ctrl, def_stat, vel, tiro, pase]

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

	label_help.text = "[Flechas/WASD] Mover | [Toque X] Pase Dirigido | [Mantener X] Tiro Potente | [Z] Cambiar Jugador"

