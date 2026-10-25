extends CharacterBody2D
class_name Player

@export var player_id: String = "bra_01"
@export var is_user_controlled: bool = true

# Stats en escala 1-100
var player_name: String = "Jugador"
var team_id: String = "team_none"
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

# Offset táctico para compañeros no controlados
var tactical_offset: Vector2 = Vector2(160, -80)

# Nodos hijos
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

signal player_loaded(player_data: Dictionary)
signal pass_initiated(from_player: Player, to_player: Player, power: float)

func _ready() -> void:
	add_to_group("players")
	load_player(player_id)

func load_player(p_id: String) -> void:
	player_id = p_id
	var file = FileAccess.open("res://data/players.json", FileAccess.READ)
	if not file:
		push_error("No se pudo abrir data/players.json")
		return

	var json_str = file.get_as_text()
	var parsed = JSON.parse_string(json_str)
	if not parsed or not parsed.has("players") or not parsed["players"].has(player_id):
		push_error("Jugador no encontrado en JSON: " + player_id)
		return

	var p_data = parsed["players"][player_id]
	player_name = p_data.get("name", "Desconocido")
	team_id = p_data.get("team", "team_none")
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
		push_error("Archivo de animaciones no existe: " + anim_json_path)
		return

	var a_file = FileAccess.open(anim_json_path, FileAccess.READ)
	var a_data = JSON.parse_string(a_file.get_as_text())
	if not a_data or not a_data.has("animations"):
		push_error("Formato inválido en animaciones: " + anim_json_path)
		return

	var sheet_texture = load(sheet_path) as Texture2D
	if not sheet_texture:
		push_error("No se pudo cargar textura: " + sheet_path)
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
	if is_kicking:
		kick_anim_timer -= delta
		if kick_anim_timer <= 0.0:
			is_kicking = false

	if is_user_controlled:
		_process_user_controlled(delta)
	else:
		_process_companion_ai(delta)

	_update_animation()
	queue_redraw()

func _process_user_controlled(delta: float) -> void:
	# Búsqueda constante de receptor para pase si tenemos la pelota
	if has_ball and is_instance_valid(current_ball):
		var target = _find_best_pass_target()
		_set_target_receiver(target)
	else:
		_set_target_receiver(null)

	# Cambio de jugador con tecla Z
	if Input.is_action_just_pressed("switch_player"):
		_switch_to_next_teammate()
		return

	# Lógica de carga de acción: Toque corto = Pase, Mantener = Tiro
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

	# Movimiento del usuario
	if is_kicking:
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

func _process_companion_ai(delta: float) -> void:
	if is_kicking:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	# El compañero busca una posición abierta de apoyo relativo al jugador con pelota o centro
	var leader = _get_active_teammate()
	if is_instance_valid(leader):
		var ideal_pos = leader.global_position + tactical_offset
		var dist_to_ideal = global_position.distance_to(ideal_pos)

		if dist_to_ideal > 35.0:
			var move_dir = (ideal_pos - global_position).normalized()
			facing_direction = move_dir
			is_moving = true
			var follow_speed = 150.0
			velocity = velocity.move_toward(move_dir * follow_speed, 800.0 * delta)
		else:
			is_moving = false
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			# Mirar hacia el poseedor del balón
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

		# Cono frontal de visión (~150°)
		if dot >= 0.15:
			# Ponderar alineación con el ángulo y penalizar distancias extremas
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
		# Pase al vacío en la dirección actual si no hay compañero en cono
		_perform_soft_pass()
		return

	is_kicking = true
	kick_anim_timer = 0.32
	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.play("kick")

	# Stat pase (1-100) calcula la velocidad y firmeza del pase
	var pase_stat = float(stats.get("pase", 80))
	var pass_speed = lerp(460.0, 750.0, clampf(pase_stat / 100.0, 0.0, 1.0))

	emit_signal("pass_initiated", self, target, pass_speed)
	current_ball.pass_to(target, pass_speed, self)

	# Cambiar automáticamente el control del usuario al receptor para una experiencia deportiva fluida
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
	var kick_speed = lerp(540.0, 850.0, clampf(tiro_stat / 100.0, 0.0, 1.0))
	current_ball.kick(facing_direction, kick_speed, self)

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
	# 1. Indicador sobre la cabeza del jugador controlado
	if is_user_controlled:
		var tri_color = Color(0.15, 0.9, 1.0, 0.95)
		var pts = PackedVector2Array([
			Vector2(-7, -98),
			Vector2(7, -98),
			Vector2(0, -86)
		])
		draw_colored_polygon(pts, tri_color)
		# Borde fino oscuro
		draw_polyline(PackedVector2Array([
			Vector2(-7, -98), Vector2(7, -98), Vector2(0, -86), Vector2(-7, -98)
		]), Color(0.05, 0.1, 0.15, 0.9), 1.5)

	# 2. Indicador sobre el compañero elegido como receptor de pase
	if is_targeted_for_pass:
		var ring_color = Color(1.0, 0.85, 0.2, 0.9)
		draw_arc(Vector2(0, -3), 19.0, 0, TAU, 24, ring_color, 2.5)
		# Pequeña flecha o rombo sobre la cabeza
		var diam = PackedVector2Array([
			Vector2(0, -96),
			Vector2(6, -90),
			Vector2(0, -84),
			Vector2(-6, -90)
		])
		draw_colored_polygon(diam, ring_color)
