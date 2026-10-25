extends CharacterBody2D
class_name Player

@export var player_id: String = "bra_01"
@export var team_id: String = "team_user"
@export var is_user_controlled: bool = true
@export var is_ai: bool = false
@export var target_goal_x: float = 800.0 # Hacia dónde ataca este jugador (+800 o -800)

# Stats en escala 1-100
var player_name: String = "Jugador"
var role: String = "FW"
var stats: Dictionary = {
	"velocidad": 80,
	"control": 80,
	"pase": 80,
	"tiro": 80,
	"defensa": 80
}

# Dirección y estados
var facing_direction: Vector2 = Vector2.DOWN
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

# Robo de balón y colisión
var tackle_cooldown: float = 0.0
var stumble_timer: float = 0.0

# IA y táctica
var tactical_offset: Vector2 = Vector2(160, -70)
var ai_decision_timer: float = 0.0

# Nodos hijos
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

signal player_loaded(player_data: Dictionary)
signal pass_initiated(from_player: Player, to_player: Player, power: float)
signal ball_stolen(tackler: Player, victim: Player)

func _ready() -> void:
	add_to_group("players")
	load_player(player_id)

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
	var anim_json_path = p_data.get("anims", "res://data/anims/" + player_id + ".json")
	var sheet_path = p_data.get("sheet", "res://assets/sprites/" + player_id + "_aligned.png")

	if not FileAccess.file_exists(anim_json_path):
		return

	var a_file = FileAccess.open(anim_json_path, FileAccess.READ)
	var a_data = JSON.parse_string(a_file.get_as_text())
	var sheet_texture = load(sheet_path) as Texture2D
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
	anim_sprite.position = Vector2(0, -54)

func set_user_controlled(controlled: bool) -> void:
	is_user_controlled = controlled
	if not is_user_controlled:
		is_charging_action = false
		pass_press_time = 0.0
		_set_target_receiver(null)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(current_ball):
		var balls = get_tree().get_nodes_in_group("ball")
		if not balls.is_empty():
			current_ball = balls[0] as Ball

	if tackle_cooldown > 0.0:
		tackle_cooldown -= delta
	if stumble_timer > 0.0:
		stumble_timer -= delta

	if is_kicking:
		kick_anim_timer -= delta
		if kick_anim_timer <= 0.0:
			is_kicking = false

	# Verificación de intento de robo si estamos cerca de un rival con la pelota
	_check_tackle_attempt()

	if is_user_controlled and not is_ai:
		_process_user_controlled(delta)
	elif is_ai:
		_process_rival_ai(delta)
	else:
		_process_companion_ai(delta)

	_update_animation()
	queue_redraw()

func _check_tackle_attempt() -> void:
	if tackle_cooldown > 0.0 or has_ball or stumble_timer > 0.0:
		return

	if not is_instance_valid(current_ball) or current_ball.current_state != Ball.State.CONTROLADA:
		return

	var carrier = current_ball.carrier as Player
	if not is_instance_valid(carrier) or carrier.team_id == self.team_id:
		return

	# Distancia de robo / disputa
	var dist = global_position.distance_to(carrier.global_position)
	if dist <= 32.0:
		tackle_cooldown = 0.7
		_execute_tackle(carrier)

func _execute_tackle(carrier: Player) -> void:
	var def_stat = float(stats.get("defensa", 50))
	var ctrl_stat = float(carrier.stats.get("control", 50))

	# Fórmula de contexto: P(robo) según defensa del que roba contra control del poseedor
	var steal_chance = clampf(0.50 + (def_stat - ctrl_stat) * 0.008, 0.15, 0.85)

	if randf() < steal_chance:
		# Robo exitoso!
		carrier.stumble()
		current_ball.take_possession(self)
		emit_signal("ball_stolen", self, carrier)
	else:
		# El poseedor resistió con su stat control
		tackle_cooldown = 0.5

func stumble() -> void:
	stumble_timer = 0.35
	velocity = velocity * 0.3

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
			if pass_press_time < 0.28:
				_perform_pass()
			else:
				_perform_power_kick()
			pass_press_time = 0.0

	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_moving = input_vec.length() > 0.05
	is_sprinting = Input.is_action_pressed("sprint")

	if is_moving:
		facing_direction = input_vec.normalized()

	var vel_stat = float(stats.get("velocidad", 75))
	var base_speed = lerp(160.0, 240.0, clampf(vel_stat / 100.0, 0.0, 1.0))
	var target_speed = base_speed * (1.35 if is_sprinting else 1.0)

	if is_moving:
		velocity = velocity.move_toward(facing_direction * target_speed, 1200.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1000.0 * delta)

	move_and_slide()

func _process_rival_ai(delta: float) -> void:
	ai_decision_timer -= delta
	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	var vel_stat = float(stats.get("velocidad", 75))
	var speed = lerp(160.0, 230.0, clampf(vel_stat / 100.0, 0.0, 1.0))

	# 1. Si la IA tiene la pelota: ATACAR
	if has_ball and is_instance_valid(current_ball):
		var goal_target = Vector2(target_goal_x, 0)
		var dist_to_goal = global_position.distance_to(goal_target)

		# Si está en distancia de tiro (< 380px), patear al arco
		if dist_to_goal < 380.0:
			facing_direction = (goal_target - global_position).normalized()
			_perform_power_kick()
			return

		# Posibilidad de pase a compañero abierto
		var mate = _find_best_pass_target()
		if is_instance_valid(mate) and ai_decision_timer <= 0.0:
			var to_mate = mate.global_position - global_position
			# Pasa si el compañero está más adelantado hacia el arco
			if (target_goal_x > 0 and mate.global_position.x > global_position.x + 40.0) or (target_goal_x < 0 and mate.global_position.x < global_position.x - 40.0):
				current_pass_target = mate
				_perform_pass()
				ai_decision_timer = 1.0
				return

		# Conducir hacia el arco rival
		var move_dir = (goal_target - global_position).normalized()
		facing_direction = move_dir
		is_moving = true
		velocity = velocity.move_toward(move_dir * speed, 900.0 * delta)

	# 2. Si la pelota está LIBRE o en el suelo: DISPUTARLA
	elif is_instance_valid(current_ball) and current_ball.current_state == Ball.State.LIBRE:
		var dir_to_ball = (current_ball.global_position - global_position).normalized()
		facing_direction = dir_to_ball
		is_moving = true
		velocity = velocity.move_toward(dir_to_ball * speed, 1000.0 * delta)

	# 3. Si el equipo rival tiene la pelota: PRESIONAR O MARCAR
	elif is_instance_valid(current_ball) and current_ball.current_state == Ball.State.CONTROLADA:
		var carrier = current_ball.carrier
		if is_instance_valid(carrier) and carrier.team_id != self.team_id:
			# Perseguir y presionar al poseedor
			var dir_to_carrier = (carrier.global_position - global_position).normalized()
			facing_direction = dir_to_carrier
			is_moving = true
			velocity = velocity.move_toward(dir_to_carrier * speed, 900.0 * delta)
		else:
			# El compañero de equipo tiene la pelota
			_process_companion_ai(delta)
			return
	else:
		is_moving = false
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)

	move_and_slide()

func _process_companion_ai(delta: float) -> void:
	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	var leader = _get_active_teammate()
	if is_instance_valid(leader):
		var ideal_pos = leader.global_position + tactical_offset
		var dist_to_ideal = global_position.distance_to(ideal_pos)

		if dist_to_ideal > 35.0:
			var move_dir = (ideal_pos - global_position).normalized()
			facing_direction = move_dir
			is_moving = true
			var follow_speed = 155.0
			velocity = velocity.move_toward(move_dir * follow_speed, 800.0 * delta)
		else:
			is_moving = false
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			facing_direction = (leader.global_position - global_position).normalized()
	else:
		is_moving = false
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)

	move_and_slide()

func _find_best_pass_target() -> Player:
	var teammates = []
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
		if dist < 40.0 or dist > 850.0:
			continue

		var dir = to_mate.normalized()
		var dot = facing_direction.dot(dir)

		if dot >= 0.15:
			var score = (dot * 100.0) - (dist * 0.05)
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
		_perform_soft_pass()
		return

	is_kicking = true
	kick_anim_timer = 0.32
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 80))
	var pass_speed = lerp(460.0, 750.0, clampf(pase_stat / 100.0, 0.0, 1.0))

	emit_signal("pass_initiated", self, target, pass_speed)
	current_ball.pass_to(target, pass_speed, self)

	if is_user_controlled:
		target.set_user_controlled(true)
		set_user_controlled(false)

func _perform_soft_pass() -> void:
	is_kicking = true
	kick_anim_timer = 0.3
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 75))
	var pass_speed = lerp(380.0, 580.0, clampf(pase_stat / 100.0, 0.0, 1.0))
	current_ball.kick(facing_direction, pass_speed, self)

func _perform_power_kick() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	is_kicking = true
	kick_anim_timer = 0.35
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.play("kick")

	var tiro_stat = float(stats.get("tiro", 75))
	var charge_factor = clampf(pass_press_time / 0.65, 0.4, 1.0)
	var base_speed = lerp(540.0, 880.0, clampf(tiro_stat / 100.0, 0.0, 1.0))
	var kick_speed = base_speed * (0.8 + 0.35 * charge_factor)

	var shot_dir = facing_direction.normalized()
	# Si ataca hacia un arco determinado, añade ajuste a la meta
	if (target_goal_x > 0 and shot_dir.x > 0.1) or (target_goal_x < 0 and shot_dir.x < -0.1):
		shot_dir.y += clampf(velocity.y * 0.001, -0.25, 0.25)
		shot_dir = shot_dir.normalized()

	current_ball.kick(shot_dir, kick_speed, self)

func _switch_to_next_teammate() -> void:
	var teammates = []
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			teammates.append(p)

	if not teammates.is_empty():
		var next_player = teammates[0]
		next_player.set_user_controlled(true)
		set_user_controlled(false)

func _get_active_teammate() -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id and p.is_user_controlled:
			return p
	return null

func _update_animation() -> void:
	if is_kicking:
		return

	var dir_name = _get_direction_name(facing_direction)
	var flip = facing_direction.x < -0.05
	anim_sprite.flip_h = flip

	var target_anim = "idle_down"

	if is_moving:
		var prefix = "run_" if is_sprinting else "walk_"
		if not anim_sprite.sprite_frames.has_animation(prefix + dir_name):
			prefix = "run_"

		if anim_sprite.sprite_frames.has_animation(prefix + dir_name):
			target_anim = prefix + dir_name
		elif anim_sprite.sprite_frames.has_animation("run_" + dir_name):
			target_anim = "run_" + dir_name
		else:
			target_anim = "run_down"
	else:
		if dir_name == "up" and anim_sprite.sprite_frames.has_animation("idle_up"):
			target_anim = "idle_up"
		elif anim_sprite.sprite_frames.has_animation("idle_" + dir_name):
			target_anim = "idle_" + dir_name
		else:
			target_anim = "idle_down"

	if anim_sprite.animation != target_anim:
		anim_sprite.play(target_anim)

func _get_direction_name(dir: Vector2) -> String:
	var abs_x = abs(dir.x)
	var y = dir.y

	if y < -0.65 and abs_x < 0.5:
		return "up"
	elif y > 0.65 and abs_x < 0.5:
		return "down"
	elif abs_x >= 0.65 and abs(y) < 0.45:
		return "side"
	elif y > 0.25 and abs_x >= 0.45:
		return "down_side"
	elif y < -0.25 and abs_x >= 0.45:
		return "up_side"

	return "down"

func on_ball_possessed(b: Ball) -> void:
	has_ball = true
	current_ball = b

func on_ball_lost(_b: Ball) -> void:
	has_ball = false
	current_ball = null
	_set_target_receiver(null)

func _draw() -> void:
	# 1. Indicador sobre la cabeza del jugador controlado por el usuario
	if is_user_controlled and not is_ai:
		var tri_color = Color(0.15, 0.9, 1.0, 0.95)
		var pts = PackedVector2Array([
			Vector2(-7, -98),
			Vector2(7, -98),
			Vector2(0, -86)
		])
		draw_colored_polygon(pts, tri_color)
		draw_polyline(PackedVector2Array([
			Vector2(-7, -98), Vector2(7, -98), Vector2(0, -86), Vector2(-7, -98)
		]), Color(0.05, 0.1, 0.15, 0.9), 1.5)

	# 2. Indicador sobre el compañero elegido como receptor de pase
	if is_targeted_for_pass:
		var ring_color = Color(1.0, 0.85, 0.2, 0.9)
		draw_arc(Vector2(0, -3), 19.0, 0, TAU, 24, ring_color, 2.5)
		var diam = PackedVector2Array([
			Vector2(0, -96),
			Vector2(6, -90),
			Vector2(0, -84),
			Vector2(-6, -90)
		])
		draw_colored_polygon(diam, ring_color)

	# 3. Indicador sutil sobre rivales (pequeño rombo rojo)
	if is_ai and team_id != "team_user":
		var enemy_color = Color(0.95, 0.2, 0.2, 0.85)
		var mini_pts = PackedVector2Array([
			Vector2(-4, -92),
			Vector2(4, -92),
			Vector2(0, -84)
		])
		draw_colored_polygon(mini_pts, enemy_color)

	# 4. Barra de carga de potencia de tiro
	if is_charging_action and pass_press_time > 0.08:
		var max_charge: float = 0.65
		var pct: float = clampf(pass_press_time / max_charge, 0.0, 1.0)
		var bar_w: float = 38.0
		var bar_h: float = 5.0
		var bar_pos: Vector2 = Vector2(-bar_w / 2.0, -114.0)

		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.85), true)
		var fill_color = Color(0.2, 0.9, 0.3).lerp(Color(1.0, 0.2, 0.2), pct)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), fill_color, true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.9, 0.9, 0.9, 0.9), false, 1.0)
