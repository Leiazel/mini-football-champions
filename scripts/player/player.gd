extends CharacterBody2D
class_name Player

@export var player_id: String = "bra_01"

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

# Nodos hijos
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

signal player_loaded(player_data: Dictionary)

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
	# Remover animaciones por defecto si existen
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
	# El pivot en el sheet está en y=118 de 128 (pies cerca del fondo).
	# Centramos el nodo del AnimatedSprite para que los pies coincidan con la posición (0, 0)
	anim_sprite.position = Vector2(0, -54)

func _physics_process(delta: float) -> void:
	if is_kicking:
		kick_anim_timer -= delta
		if kick_anim_timer <= 0.0:
			is_kicking = false

	_handle_input()
	_update_movement(delta)
	_update_animation()

func _handle_input() -> void:
	if is_kicking:
		return

	# Patear / Pasar la pelota
	if Input.is_action_just_pressed("action_pass"):
		if has_ball and is_instance_valid(current_ball):
			_perform_kick()

func _perform_kick() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	is_kicking = true
	kick_anim_timer = 0.35
	var kick_dir = facing_direction.normalized()
	# Potencia influenciada por stat tiro
	var tiro_stat = float(stats.get("tiro", 75))
	var kick_speed = lerp(480.0, 780.0, clampf(tiro_stat / 100.0, 0.0, 1.0))

	if anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.play("kick")

	current_ball.kick(kick_dir, kick_speed, self)

func _update_movement(delta: float) -> void:
	if is_kicking:
		velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
		move_and_slide()
		return

	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_moving = input_vec.length() > 0.05
	is_sprinting = Input.is_action_pressed("sprint")

	if is_moving:
		facing_direction = input_vec.normalized()

	# Cálculo de velocidad basada en stat 'velocidad'
	var vel_stat = float(stats.get("velocidad", 75))
	var base_speed = lerp(160.0, 240.0, clampf(vel_stat / 100.0, 0.0, 1.0))
	var target_speed = base_speed * (1.35 if is_sprinting else 1.0)

	if is_moving:
		var target_vel = facing_direction * target_speed
		velocity = velocity.move_toward(target_vel, 1200.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1000.0 * delta)

	move_and_slide()

func _update_animation() -> void:
	if is_kicking:
		return

	var dir_name = _get_direction_name(facing_direction)
	var flip = facing_direction.x < -0.05

	anim_sprite.flip_h = flip

	var target_anim = "idle_down"

	if is_moving:
		var prefix = "run_" if is_sprinting else "walk_"
		# Si no existe walk_* en el schema, fallback a run_*
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
