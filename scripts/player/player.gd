extends CharacterBody2D
class_name Player

const BASE_SPRITE_SCALE := Vector2(0.78, 0.78)
const BASE_SPRITE_OFFSET := Vector2(0, -42)

@export var player_id: String = "bra_01"
@export var team_id: String = "team_user"
@export var is_user_controlled: bool = true
@export var is_ai: bool = false
@export var target_goal_x: float = 1200.0 # Hacia dónde ataca este jugador (+1200 o -1200)

# Límites del campo (sincronizados con PitchGround 2400x1400)
@export var field_half_width: float = 1200.0
@export var field_half_height: float = 700.0

# Stats en escala 1-100
var player_name: String = "Jugador"
var role: String = "FW" # "DF", "MF", "FW"
var stats: Dictionary = {
	"velocidad": 80,
	"control": 80,
	"pase": 80,
	"tiro": 80,
	"defensa": 80
}

# Dirección y estados
var facing_direction: Vector2 = Vector2.DOWN
var last_anim_dir: String = "down"
var last_flip_h: bool = false
var is_moving: bool = false
var is_sprinting: bool = false
var is_kicking: bool = false
var kick_anim_timer: float = 0.0

var has_ball: bool = false
var current_ball: Ball = null

# Pase e interacción con compañeros
var pass_press_time: float = 0.0
var is_charging_action: bool = false
var current_pass_target: Player = null
var is_targeted_for_pass: bool = false

# Robo de balón, colisión suave y anti-atasco
var tackle_cooldown: float = 0.0
var stumble_timer: float = 0.0
var pickup_lock_timer: float = 0.0

# IA posicional inspirada en Mini-Football (v1) e Inazuma Eleven
enum AIState {
	GUARDAR_POSICION,
	BUSCAR_PELOTA,
	DESMARCARSE,
	CORTAR,
	APOYAR
}
var ai_state: AIState = AIState.GUARDAR_POSICION
var home_position: Vector2 = Vector2.ZERO
var tactical_offset: Vector2 = Vector2(160, -70)
var ai_decision_timer: float = 0.0
var aurora_time: float = 0.0

# Nodos hijos
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

signal player_loaded(player_data: Dictionary)
signal pass_initiated(from_player: Player, to_player: Player, power: float)
signal ball_stolen(tackler: Player, victim: Player)

func _ready() -> void:
	add_to_group("players")
	home_position = global_position
	_ensure_extra_inputs()
	load_player(player_id)

func _ensure_extra_inputs() -> void:
	# Agregar Q como tecla alternativa de cambio de jugador (como en Mini-Football v1)
	if InputMap.has_action("switch_player"):
		var has_q := false
		for ev in InputMap.action_get_events("switch_player"):
			if ev is InputEventKey and (ev.physical_keycode == KEY_Q or ev.keycode == KEY_Q):
				has_q = true
				break
		if not has_q:
			var ev_q := InputEventKey.new()
			ev_q.physical_keycode = KEY_Q
			InputMap.action_add_event("switch_player", ev_q)

func set_home_position(pos: Vector2) -> void:
	home_position = pos
	global_position = pos
	velocity = Vector2.ZERO

func load_player(p_id: String) -> void:
	player_id = p_id
	var file = FileAccess.open("res://data/players.json", FileAccess.READ)
	if not file:
		return

	var json_str = file.get_as_text()
	var parsed = JSON.parse_string(json_str)
	if not parsed or not parsed.has("players") or not parsed["players"].has(player_id):
		return

	var p_data = parsed["players"][player_id]
	player_name = p_data.get("name", "Desconocido")
	role = p_data.get("role", "FW")
	if p_data.has("stats"):
		stats = p_data["stats"]

	_build_sprite_frames(p_data)
	emit_signal("player_loaded", p_data)
	queue_redraw()

func _build_sprite_frames(p_data: Dictionary) -> void:
	if not is_instance_valid(anim_sprite):
		anim_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(shadow):
		shadow = get_node_or_null("Shadow") as Sprite2D
	if not is_instance_valid(anim_sprite):
		return

	var anim_json_path: String = p_data.get("anims", "res://data/anims/" + player_id + ".json")
	var sheet_path: String = p_data.get("sheet", "res://assets/sprites/" + player_id + "_aligned.png")

	if not FileAccess.file_exists(anim_json_path):
		return

	var a_file = FileAccess.open(anim_json_path, FileAccess.READ)
	var a_data = JSON.parse_string(a_file.get_as_text())
	var sheet_texture: Texture2D = load(sheet_path) as Texture2D
	if not sheet_texture:
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(sheet_path)) == OK:
			sheet_texture = ImageTexture.create_from_image(img)
	if not sheet_texture:
		return

	var sf = SpriteFrames.new()
	for existing_anim in sf.get_animation_names():
		sf.remove_animation(existing_anim)

	for anim_name in a_data["animations"].keys():
		var anim_info = a_data["animations"][anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, float(anim_info.get("fps", 8)))
		sf.set_animation_loop(anim_name, bool(anim_info.get("loop", true)))

		for f in anim_info["frames"]:
			var rect_info = f["rect"]
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet_texture
			atlas.region = Rect2(rect_info["x"], rect_info["y"], rect_info["w"], rect_info["h"])
			sf.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = sf
	anim_sprite.play("idle_down")
	anim_sprite.position = BASE_SPRITE_OFFSET
	anim_sprite.scale = BASE_SPRITE_SCALE
	if is_instance_valid(shadow):
		shadow.scale = BASE_SPRITE_SCALE

func set_user_controlled(controlled: bool) -> void:
	is_user_controlled = controlled
	if not is_user_controlled:
		is_charging_action = false
		pass_press_time = 0.0
		_set_target_receiver(null)
	queue_redraw()

func _physics_process(delta: float) -> void:
	aurora_time += delta

	if not is_instance_valid(current_ball):
		var balls = get_tree().get_nodes_in_group("ball")
		if not balls.is_empty():
			current_ball = balls[0] as Ball

	if tackle_cooldown > 0.0:
		tackle_cooldown -= delta
	if stumble_timer > 0.0:
		stumble_timer -= delta
	if pickup_lock_timer > 0.0:
		pickup_lock_timer -= delta

	if is_kicking:
		kick_anim_timer -= delta
		if kick_anim_timer <= 0.0:
			is_kicking = false

	# Intento de robo si estamos cerca de un rival con la pelota
	_check_tackle_attempt()

	if is_user_controlled and not is_ai:
		_process_user_controlled(delta)
	else:
		_process_positional_ai(delta)

	# Separación física suave (evita que los jugadores se peguen al chocar) y límites de campo
	_apply_soft_player_collisions(delta)
	_clamp_inside_field()

	_update_animation()
	queue_redraw()

func _apply_soft_player_collisions(delta: float) -> void:
	var push_vec := Vector2.ZERO
	var min_dist: float = 28.0
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not is_instance_valid(node):
			continue
		var other := node as Node2D
		if not other:
			continue
		var diff := global_position - other.global_position
		var dist := diff.length()
		if dist < min_dist:
			var dir := diff.normalized() if dist > 0.01 else Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			var overlap := min_dist - dist
			push_vec += dir * overlap * 14.0

	if push_vec.length() > 0.01:
		global_position += push_vec * delta

func _clamp_inside_field() -> void:
	var margin_x: float = 18.0
	var margin_y: float = 18.0
	global_position.x = clampf(global_position.x, -field_half_width + margin_x, field_half_width - margin_x)
	global_position.y = clampf(global_position.y, -field_half_height + margin_y, field_half_height - margin_y)

func _check_tackle_attempt() -> void:
	if tackle_cooldown > 0.0 or has_ball or stumble_timer > 0.0 or pickup_lock_timer > 0.0:
		return

	if not is_instance_valid(current_ball) or current_ball.current_state != Ball.State.CONTROLADA:
		return

	var carrier = current_ball.carrier as Player
	if not is_instance_valid(carrier) or carrier.team_id == self.team_id:
		return

	var dist = global_position.distance_to(carrier.global_position)
	if dist <= 34.0:
		tackle_cooldown = 0.75
		_execute_tackle(carrier)

func _execute_tackle(carrier: Player) -> void:
	var def_stat = float(stats.get("defensa", 50))
	var ctrl_stat = float(carrier.stats.get("control", 50))

	# Fórmula de contexto: P(robo) según defensa del que roba contra control del poseedor
	var steal_chance = clampf(0.50 + (def_stat - ctrl_stat) * 0.008, 0.18, 0.85)

	if randf() < steal_chance:
		var push_away = (carrier.global_position - global_position).normalized()
		if push_away.length() < 0.1:
			push_away = -facing_direction
		carrier.stumble(push_away)
		current_ball.take_possession(self)
		emit_signal("ball_stolen", self, carrier)
	else:
		tackle_cooldown = 0.55

func stumble(push_dir: Vector2 = Vector2.ZERO) -> void:
	stumble_timer = 0.42
	pickup_lock_timer = 0.55
	if push_dir.length() > 0.05:
		velocity = push_dir.normalized() * 140.0
	else:
		velocity = velocity * 0.25

func _get_base_speed() -> float:
	var vel_stat = float(stats.get("velocidad", 75))
	# Velocidad ágil inspirada en Mini-Football para la cancha ampliada
	var speed = lerp(230.0, 315.0, clampf(vel_stat / 100.0, 0.0, 1.0))
	if has_ball:
		var ctrl_stat = float(stats.get("control", 75))
		# Con buen control casi no pierden velocidad al llevar la pelota
		speed *= lerp(0.95, 1.0, clampf(ctrl_stat / 100.0, 0.0, 1.0))
	return speed

func _process_user_controlled(delta: float) -> void:
	if has_ball and is_instance_valid(current_ball):
		var target = _find_best_pass_target()
		_set_target_receiver(target)
	else:
		_set_target_receiver(null)

	if Input.is_action_just_pressed("switch_player"):
		_switch_to_next_teammate()
		return

	if Input.is_action_just_pressed("action_pass"):
		if has_ball and is_instance_valid(current_ball):
			is_charging_action = true
			pass_press_time = 0.0

	if is_charging_action:
		pass_press_time += delta

	if Input.is_action_just_released("action_pass"):
		if is_charging_action and has_ball and is_instance_valid(current_ball):
			is_charging_action = false
			if pass_press_time < 0.26:
				_perform_pass()
			else:
				_perform_power_kick()
			pass_press_time = 0.0

	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_moving = input_vec.length() > 0.05
	is_sprinting = Input.is_action_pressed("sprint")

	if is_moving:
		facing_direction = input_vec.normalized()

	# Boost de agilidad para el jugador humano (igual que en Mini-Football v1)
	var base_speed = _get_base_speed() * 1.12
	var target_speed = base_speed * (1.28 if is_sprinting else 1.0)

	if is_moving:
		velocity = velocity.move_toward(facing_direction * target_speed, 1800.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1500.0 * delta)

	move_and_slide()

# ==============================================================================
# IA POSICIONAL POR ROLES (DF = Defensor, MF = Mediocampista, FW = Delantero)
# Inspirada en JugadorBase de Mini-Football (v1) e Inazuma Eleven DS
# ==============================================================================
func _process_positional_ai(delta: float) -> void:
	ai_decision_timer -= delta
	_set_target_receiver(null)

	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	if not is_instance_valid(current_ball):
		is_moving = false
		velocity = velocity.move_toward(Vector2.ZERO, 1000.0 * delta)
		move_and_slide()
		return

	# Si un jugador del equipo del usuario toma la pelota, cederle el control automáticamente
	if has_ball and not is_ai and not is_user_controlled:
		_promote_self_to_user_controlled()
		_process_user_controlled(delta)
		return

	# 1. Si este jugador IA tiene la pelota: decidir según su rol (DF pasa, MF enlaza/avanza, FW ataca/tira)
	if has_ball:
		_process_ai_with_ball(delta)
		move_and_slide()
		return

	var speed = _get_base_speed()
	var ball_pos = current_ball.global_position
	var dist_to_ball = global_position.distance_to(ball_pos)
	var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
	var own_goal_pos := Vector2(-target_goal_x, 0.0)
	var enemy_goal_pos := Vector2(target_goal_x, 0.0)

	var carrier = current_ball.carrier
	var team_has_ball: bool = is_instance_valid(carrier) and carrier.get("team_id") == self.team_id
	var opp_has_ball: bool = is_instance_valid(carrier) and carrier.get("team_id") != self.team_id
	var ball_is_loose: bool = current_ball.current_state != Ball.State.CONTROLADA

	# Verificar si somos el jugador no-humano del equipo más cercano a la pelota
	var is_closest_to_ball := _is_closest_ai_on_team_to(ball_pos)

	# Determinar estado posicional según rol (DF, MF, FW)
	var target_pos: Vector2 = _compute_role_base_position(ball_pos, own_goal_pos, enemy_goal_pos, attack_dir_x)
	var move_mult: float = 0.92

	match role:
		"DF":
			# DEFENSOR: Se queda atrás defendiendo su zona. Solo sale a cortar cuando la pelota entra a su campo.
			var ball_in_def_zone = (ball_pos.x * attack_dir_x) < 180.0
			var dist_own_goal_ball = own_goal_pos.distance_to(ball_pos)

			if team_has_ball:
				ai_state = AIState.APOYAR
				# Se mantiene detrás de mitad de cancha ofreciendo pase de seguridad
				var support_x = clampf(ball_pos.x - attack_dir_x * 460.0, -field_half_width + 260.0, field_half_width - 260.0)
				if attack_dir_x > 0.0:
					support_x = minf(support_x, -160.0)
				else:
					support_x = maxf(support_x, 160.0)
				var support_y = lerpf(home_position.y, ball_pos.y, 0.35)
				target_pos = Vector2(support_x, support_y)
				move_mult = 0.85
			elif (opp_has_ball or ball_is_loose) and (ball_in_def_zone or dist_own_goal_ball < 780.0 or (ball_is_loose and is_closest_to_ball and dist_to_ball < 420.0)):
				ai_state = AIState.CORTAR
				if opp_has_ball and is_instance_valid(carrier):
					# Cerrar línea entre el portador rival y nuestro arco
					var to_own_goal = (own_goal_pos - carrier.global_position).normalized()
					if dist_to_ball > 110.0:
						target_pos = carrier.global_position + to_own_goal * 45.0
					else:
						target_pos = carrier.global_position
				else:
					target_pos = ball_pos
				move_mult = 1.12
			else:
				ai_state = AIState.GUARDAR_POSICION
				move_mult = 0.88

		"FW":
			# DELANTERO: Se queda arriba esperando la pelota para el contragolpe o desmarque.
			if team_has_ball:
				ai_state = AIState.DESMARCARSE
				var carrier_pos = carrier.global_position if is_instance_valid(carrier) else ball_pos
				var desired_x = carrier_pos.x + attack_dir_x * 440.0
				if attack_dir_x > 0.0:
					desired_x = clampf(desired_x, 220.0, field_half_width - 260.0)
				else:
					desired_x = clampf(desired_x, -field_half_width + 260.0, -220.0)
				# Desmarcarse en Y buscando espacio libre lejos de defensores rivales
				var open_y = _find_open_attacking_lane_y(desired_x, home_position.y, ball_pos.y)
				target_pos = Vector2(desired_x, open_y)
				move_mult = 1.05
			elif ball_is_loose and ((ball_pos.x * attack_dir_x > -120.0 and dist_to_ball < 520.0) or dist_to_ball < 240.0):
				ai_state = AIState.BUSCAR_PELOTA
				target_pos = ball_pos
				move_mult = 1.15
			elif opp_has_ball and (ball_pos.x * attack_dir_x > 60.0) and dist_to_ball < 340.0:
				# Presiona arriba solo si el rival tiene la pelota cerca en zona ofensiva
				ai_state = AIState.CORTAR
				target_pos = carrier.global_position
				move_mult = 1.05
			else:
				# Si la pelota está lejos en defensa, el delantero NO baja a defender: espera arriba
				ai_state = AIState.GUARDAR_POSICION
				var wait_x = attack_dir_x * 340.0
				var wait_y = lerpf(home_position.y, ball_pos.y, 0.30)
				target_pos = Vector2(wait_x, clampf(wait_y, -420.0, 420.0))
				move_mult = 0.85

		_: # "MF" (Mediocampista)
			if team_has_ball:
				ai_state = AIState.DESMARCARSE
				var carrier_pos = carrier.global_position if is_instance_valid(carrier) else ball_pos
				var link_x = clampf(carrier_pos.x + attack_dir_x * 240.0, -field_half_width + 320.0, field_half_width - 320.0)
				var offset_y = -210.0 if carrier_pos.y > 0.0 else 210.0
				var link_y = clampf(lerpf(home_position.y, carrier_pos.y + offset_y, 0.65), -480.0, 480.0)
				target_pos = Vector2(link_x, link_y)
				move_mult = 0.98
			elif (ball_is_loose and is_closest_to_ball) or (abs(ball_pos.x) < 680.0 and dist_to_ball < 520.0):
				ai_state = AIState.BUSCAR_PELOTA
				target_pos = carrier.global_position if (opp_has_ball and is_instance_valid(carrier)) else ball_pos
				move_mult = 1.10
			else:
				ai_state = AIState.GUARDAR_POSICION
				move_mult = 0.90

	# Separación táctica entre compañeros (como en Mini-Football v1) para no amontonarse
	var sep_force := Vector2.ZERO
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			var d = global_position.distance_to(p.global_position)
			if d < 110.0 and d > 0.01:
				sep_force += (global_position - p.global_position).normalized() * ((110.0 - d) / 110.0)

	var to_dest = target_pos - global_position
	if to_dest.length() > 26.0:
		var desired_dir = (to_dest.normalized() + sep_force * 0.45).normalized()
		facing_direction = facing_direction.lerp(desired_dir, clampf(10.0 * delta, 0.0, 1.0)).normalized()
		is_moving = true
		is_sprinting = move_mult > 1.08
		velocity = velocity.move_toward(desired_dir * (speed * move_mult), 1400.0 * delta)
	else:
		is_moving = false
		is_sprinting = false
		velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
		if (ball_pos - global_position).length() > 10.0:
			facing_direction = (ball_pos - global_position).normalized()

	move_and_slide()

func _compute_role_base_position(ball_pos: Vector2, own_goal_pos: Vector2, enemy_goal_pos: Vector2, attack_dir_x: float) -> Vector2:
	var base_x: float = home_position.x
	match role:
		"DF":
			# Entre su propio arco y el mediocampo
			base_x = lerpf(own_goal_pos.x + attack_dir_x * 460.0, ball_pos.x - attack_dir_x * 380.0, 0.35)
			if attack_dir_x > 0.0:
				base_x = clampf(base_x, own_goal_pos.x + 280.0, -140.0)
			else:
				base_x = clampf(base_x, 140.0, own_goal_pos.x - 280.0)
		"MF":
			base_x = lerpf(0.0, ball_pos.x, 0.45)
			base_x = clampf(base_x, -560.0, 560.0)
		"FW":
			base_x = lerpf(attack_dir_x * 360.0, ball_pos.x + attack_dir_x * 340.0, 0.40)
			if attack_dir_x > 0.0:
				base_x = clampf(base_x, 140.0, enemy_goal_pos.x - 280.0)
			else:
				base_x = clampf(base_x, enemy_goal_pos.x + 280.0, -140.0)

	var base_y: float = clampf(lerpf(home_position.y, ball_pos.y, 0.38), -field_half_height + 120.0, field_half_height - 120.0)
	return Vector2(base_x, base_y)

func _find_open_attacking_lane_y(target_x: float, preferred_y: float, ball_y: float) -> float:
	var candidates: Array[float] = [
		clampf(preferred_y, -420.0, 420.0),
		clampf(ball_y - 240.0, -450.0, 450.0),
		clampf(ball_y + 240.0, -450.0, 450.0),
		0.0
	]
	var best_y: float = candidates[0]
	var best_clearance: float = -1.0

	for cy in candidates:
		var test_pt := Vector2(target_x, cy)
		var min_opp_dist: float = 9999.0
		for p in get_tree().get_nodes_in_group("players"):
			if p is Player and p.team_id != self.team_id:
				var d = test_pt.distance_to(p.global_position)
				if d < min_opp_dist:
					min_opp_dist = d
		if min_opp_dist > best_clearance:
			best_clearance = min_opp_dist
			best_y = cy

	return lerpf(preferred_y, best_y, 0.65)

func _is_closest_ai_on_team_to(pos: Vector2) -> bool:
	var my_dist = global_position.distance_to(pos)
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id and not p.is_user_controlled:
			if p.global_position.distance_to(pos) < my_dist - 15.0:
				return false
	return true

func _process_ai_with_ball(delta: float) -> void:
	var speed = _get_base_speed()
	var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
	var goal_target := Vector2(target_goal_x, clampf(global_position.y * 0.35, -75.0, 75.0))
	var dist_to_goal := global_position.distance_to(goal_target)

	# 1. Si está en zona de disparo al arco (< 520px para FW/MF, < 380px para DF)
	var shoot_range: float = 520.0 if role != "DF" else 380.0
	if dist_to_goal < shoot_range and ai_decision_timer <= 0.0:
		# Apuntar a una esquina del arco lejos del arquero rival
		var aim_y: float = randf_range(-75.0, 75.0)
		for gk in get_tree().get_nodes_in_group("goalkeepers"):
			if gk.get("team_id") != self.team_id:
				aim_y = -70.0 if gk.global_position.y >= 0.0 else 70.0
				break
		facing_direction = (Vector2(target_goal_x, aim_y) - global_position).normalized()
		pass_press_time = 0.55
		_perform_power_kick()
		ai_decision_timer = 0.65
		return

	# 2. Evaluar pase inteligente a compañero más adelantado (especialmente DF -> MF/FW y MF -> FW)
	if ai_decision_timer <= 0.0:
		var best_mate := _find_best_ai_pass_target(attack_dir_x)
		if is_instance_valid(best_mate):
			var pass_prob: float = 0.85 if role == "DF" else (0.65 if role == "MF" else 0.35)
			if randf() < pass_prob:
				current_pass_target = best_mate
				facing_direction = (best_mate.global_position - global_position).normalized()
				_perform_pass()
				ai_decision_timer = 0.75
				return
		ai_decision_timer = 0.32

	# 3. Conducir hacia el arco rival esquivando presión cercana
	var move_dir := (goal_target - global_position).normalized()
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.team_id != self.team_id:
			var d = global_position.distance_to(p.global_position)
			if d < 120.0 and d > 0.01:
				var evade = (global_position - p.global_position).normalized()
				move_dir = (move_dir + Vector2(0, evade.y * 0.65)).normalized()

	facing_direction = facing_direction.lerp(move_dir, clampf(10.0 * delta, 0.0, 1.0)).normalized()
	is_moving = true
	is_sprinting = true
	velocity = velocity.move_toward(facing_direction * speed, 1400.0 * delta)

func _find_best_ai_pass_target(attack_dir_x: float) -> Player:
	var best_mate: Player = null
	var best_score: float = -9999.0

	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not (p is Player) or p.team_id != self.team_id:
			continue
		var mate := p as Player
		var to_mate := mate.global_position - global_position
		var dist := to_mate.length()
		if dist < 90.0 or dist > 1100.0:
			continue

		# Avance hacia el arco rival
		var forward_gain := (mate.global_position.x - global_position.x) * attack_dir_x
		if forward_gain < 35.0:
			continue

		if not _has_clear_pass_lane(mate):
			continue

		var role_bonus: float = 60.0 if mate.role == "FW" else (30.0 if mate.role == "MF" else 0.0)
		var score: float = forward_gain * 0.45 + role_bonus - dist * 0.08
		if score > best_score:
			best_score = score
			best_mate = mate

	return best_mate

func _has_clear_pass_lane(mate: Node2D) -> bool:
	var dir_pass: Vector2 = (mate.global_position - global_position).normalized()
	var dist_pass: float = global_position.distance_to(mate.global_position)
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.team_id != self.team_id:
			var opp: Player = p as Player
			var to_opp: Vector2 = opp.global_position - global_position
			var dist_opp: float = to_opp.length()
			if dist_opp < dist_pass and dir_pass.dot(to_opp.normalized()) > 0.88:
				return false
	return true

func _find_best_pass_target() -> Player:
	var teammates: Array[Player] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			teammates.append(p)

	if teammates.is_empty():
		return null

	var best_target: Player = null
	var best_score: float = -9999.0

	for mate in teammates:
		var to_mate = mate.global_position - global_position
		var dist = to_mate.length()
		if dist < 45.0 or dist > 1350.0:
			continue

		var dir = to_mate.normalized()
		var dot = facing_direction.dot(dir)

		# Cono principal hacia donde mira el jugador
		if dot >= 0.15:
			var score = (dot * 120.0) - (dist * 0.04)
			if score > best_score:
				best_score = score
				best_target = mate

	# Fallback: si ningún compañero está en el cono frontal, elegir el compañero más cercano/adelantado
	if best_target == null:
		var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
		for mate in teammates:
			var dist = global_position.distance_to(mate.global_position)
			var forward_bonus = (mate.global_position.x - global_position.x) * attack_dir_x * 0.15
			var score = forward_bonus - dist * 0.1
			if score > best_score:
				best_score = score
				best_target = mate

	return best_target

func _set_target_receiver(target: Player) -> void:
	if current_pass_target == target:
		return

	if is_instance_valid(current_pass_target):
		current_pass_target.is_targeted_for_pass = false
		current_pass_target.queue_redraw()

	current_pass_target = target

	if is_instance_valid(current_pass_target):
		current_pass_target.is_targeted_for_pass = true
		current_pass_target.queue_redraw()

func _perform_pass() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	var target = current_pass_target
	if not is_instance_valid(target):
		target = _find_best_pass_target()
	if not is_instance_valid(target):
		_perform_soft_pass()
		return

	var to_target_dir = (target.global_position - global_position).normalized()
	if to_target_dir.length() > 0.05:
		facing_direction = to_target_dir

	is_kicking = true
	kick_anim_timer = 0.28
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 80))
	var dist = global_position.distance_to(target.global_position)
	var base_pass_speed = lerp(560.0, 860.0, clampf(pase_stat / 100.0, 0.0, 1.0))
	var pass_speed = clampf(maxf(base_pass_speed, dist * 1.15), 540.0, 960.0)

	emit_signal("pass_initiated", self, target, pass_speed)
	current_ball.pass_to(target, pass_speed, self)

	if is_user_controlled and not is_ai:
		target.set_user_controlled(true)
		set_user_controlled(false)

func _perform_soft_pass() -> void:
	is_kicking = true
	kick_anim_timer = 0.26
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 75))
	var pass_speed = lerp(460.0, 680.0, clampf(pase_stat / 100.0, 0.0, 1.0))
	current_ball.kick(facing_direction, pass_speed, self)

func _perform_power_kick() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	is_kicking = true
	kick_anim_timer = 0.32
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var tiro_stat = float(stats.get("tiro", 75))
	var charge_factor = clampf(pass_press_time / 0.60, 0.45, 1.0)
	var base_speed = lerp(640.0, 1020.0, clampf(tiro_stat / 100.0, 0.0, 1.0))
	var kick_speed = base_speed * (0.82 + 0.35 * charge_factor)

	var shot_dir = facing_direction.normalized()
	if (target_goal_x > 0 and shot_dir.x > 0.1) or (target_goal_x < 0 and shot_dir.x < -0.1):
		shot_dir.y += clampf(velocity.y * 0.0008, -0.22, 0.22)
		shot_dir = shot_dir.normalized()

	current_ball.kick(shot_dir, kick_speed, self)

func _switch_to_next_teammate() -> void:
	var candidates: Array = []
	var ref_pos := current_ball.global_position if is_instance_valid(current_ball) else global_position

	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			var d = p.global_position.distance_to(ref_pos)
			candidates.append({"p": p, "dist": d})

	if not candidates.is_empty():
		candidates.sort_custom(func(a, b): return a.dist < b.dist)
		var next_player: Player = candidates[0].p
		next_player.set_user_controlled(true)
		set_user_controlled(false)

func _promote_self_to_user_controlled() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.team_id == self.team_id:
			p.set_user_controlled(p == self)

func _get_active_teammate() -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id and p.is_user_controlled:
			return p
	return null

func _update_animation() -> void:
	if is_kicking or not anim_sprite or not anim_sprite.sprite_frames:
		return

	if velocity.length() > 16.0 or is_moving:
		last_anim_dir = _get_direction_name(facing_direction)
		if facing_direction.x < -0.18:
			last_flip_h = true
		elif facing_direction.x > 0.18:
			last_flip_h = false

	var dir_name := last_anim_dir
	var sf := anim_sprite.sprite_frames
	var target_anim := "idle_down"
	var use_flip := false

	if is_moving and velocity.length() > 12.0:
		var is_fast := is_sprinting or velocity.length() > 210.0
		var prefix := "run_" if is_fast else "walk_"

		if dir_name == "up":
			target_anim = "run_up"
			use_flip = false
		elif dir_name == "down":
			target_anim = "run_down"
			use_flip = false
		elif dir_name == "side":
			if last_flip_h and sf.has_animation(prefix + "left"):
				target_anim = prefix + "left"
				use_flip = false
			else:
				target_anim = (prefix + "side") if sf.has_animation(prefix + "side") else "run_side"
				use_flip = last_flip_h
		elif dir_name == "down_side":
			if last_flip_h and sf.has_animation(prefix + "down_left"):
				target_anim = prefix + "down_left"
				use_flip = false
			else:
				target_anim = (prefix + "down_side") if sf.has_animation(prefix + "down_side") else "run_down_side"
				use_flip = last_flip_h
		elif dir_name == "up_side":
			target_anim = (prefix + "up_side") if sf.has_animation(prefix + "up_side") else "run_up_side"
			use_flip = last_flip_h
	else:
		if dir_name == "up" and sf.has_animation("idle_up"):
			target_anim = "idle_up"
			use_flip = false
		else:
			target_anim = "idle_down"
			use_flip = false

	anim_sprite.flip_h = use_flip
	if anim_sprite.animation != target_anim or not anim_sprite.is_playing():
		anim_sprite.play(target_anim)

func _get_direction_name(dir: Vector2) -> String:
	var n := dir.normalized()
	var abs_x := absf(n.x)
	var y := n.y

	if y < -0.68 and abs_x < 0.48:
		return "up"
	elif y > 0.68 and abs_x < 0.48:
		return "down"
	elif abs_x >= 0.68 and absf(y) < 0.42:
		return "side"
	elif y >= 0.25 and abs_x >= 0.38:
		return "down_side"
	elif y <= -0.25 and abs_x >= 0.38:
		return "up_side"

	return last_anim_dir if last_anim_dir != "" else "down"

func on_ball_possessed(b: Ball) -> void:
	has_ball = true
	current_ball = b
	# Si un compañero del equipo del usuario gana la pelota, pasa a ser controlado por el jugador
	if not is_ai and team_id == "team_user" and not is_user_controlled:
		_promote_self_to_user_controlled()

func on_ball_lost(_b: Ball) -> void:
	has_ball = false
	is_charging_action = false
	pass_press_time = 0.0
	_set_target_receiver(null)

func _draw() -> void:
	# 0. Aura bajo los pies estilo Mini-Football (v1)
	var base_ring_col = Color(0.25, 0.85, 1.0, 0.28) if not is_ai else Color(0.95, 0.25, 0.25, 0.28)
	draw_circle(Vector2(0, 0), 14.0, base_ring_col)

	# 1. Indicador sobre el jugador controlado por el usuario
	if is_user_controlled and not is_ai:
		var pulse = 0.55 + 0.25 * sin(aurora_time * 5.0)
		var ring_col = Color(0.15, 0.92, 1.0, pulse)
		draw_arc(Vector2(0, 0), 21.0, 0.0, TAU, 32, ring_col, 2.5)

		var tri_color = Color(0.15, 0.92, 1.0, 0.95)
		var pts = PackedVector2Array([
			Vector2(-6, -80),
			Vector2(6, -80),
			Vector2(0, -70)
		])
		draw_colored_polygon(pts, tri_color)
		draw_polyline(PackedVector2Array([
			Vector2(-6, -80), Vector2(6, -80), Vector2(0, -70), Vector2(-6, -80)
		]), Color(0.05, 0.1, 0.15, 0.9), 1.5)

	# 2. Indicador sobre el compañero elegido como receptor de pase
	if is_targeted_for_pass:
		var ring_color = Color(1.0, 0.85, 0.2, 0.92)
		draw_arc(Vector2(0, 0), 18.0, 0, TAU, 24, ring_color, 2.5)
		var diam = PackedVector2Array([
			Vector2(0, -79),
			Vector2(5, -74),
			Vector2(0, -69),
			Vector2(-5, -74)
		])
		draw_colored_polygon(diam, ring_color)

	# 3. Indicador sutil sobre rivales
	if is_ai and team_id != "team_user":
		var enemy_color = Color(0.95, 0.22, 0.22, 0.85)
		var mini_pts = PackedVector2Array([
			Vector2(-4, -76),
			Vector2(4, -76),
			Vector2(0, -69)
		])
		draw_colored_polygon(mini_pts, enemy_color)

	# 4. Barra de carga de potencia de tiro
	if is_charging_action and pass_press_time > 0.08:
		var max_charge: float = 0.60
		var pct: float = clampf(pass_press_time / max_charge, 0.0, 1.0)
		var bar_w: float = 34.0
		var bar_h: float = 5.0
		var bar_pos: Vector2 = Vector2(-bar_w / 2.0, -92.0)

		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.85), true)
		var fill_color = Color(0.2, 0.9, 0.3).lerp(Color(1.0, 0.2, 0.2), pct)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), fill_color, true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.9, 0.9, 0.9, 0.9), false, 1.0)