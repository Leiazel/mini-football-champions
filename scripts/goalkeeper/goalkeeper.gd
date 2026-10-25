extends CharacterBody2D
class_name Goalkeeper

@export var player_id: String = "gk_01"
@export var goal_center: Vector2 = Vector2(760, 0)
@export var goal_half_height: float = 75.0
@export var patrol_x: float = 720.0

enum GKState {
	GUARD,
	DIVING,
	RECOVERING,
	HOLDING
}

var current_state: GKState = GKState.GUARD
var player_name: String = "El Guardián"
var stats: Dictionary = {
	"reflejos": 88,
	"velocidad": 74,
	"control": 72,
	"defensa": 90
}

var ball: Ball = null
var dive_timer: float = 0.0
var hold_timer: float = 0.0
var has_ball: bool = false
var facing_direction: Vector2 = Vector2.LEFT

# Nodos
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow

signal shot_saved(gk: Goalkeeper)

func _ready() -> void:
	add_to_group("players")
	add_to_group("goalkeepers")
	load_goalkeeper(player_id)

func load_goalkeeper(p_id: String) -> void:
	player_id = p_id
	var file = FileAccess.open("res://data/players.json", FileAccess.READ)
	if not file:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed or not parsed.has("players") or not parsed["players"].has(player_id):
		return

	var p_data = parsed["players"][player_id]
	player_name = p_data.get("name", "Arquero")
	if p_data.has("stats"):
		stats = p_data["stats"]

	_build_sprite_frames(p_data)

func _build_sprite_frames(p_data: Dictionary) -> void:
	var anim_json_path = p_data.get("anims", "res://data/anims/ita_02.json")
	var sheet_path = p_data.get("sheet", "res://assets/sprites/ita_02_aligned.png")

	if not FileAccess.file_exists(anim_json_path):
		return

	var a_file = FileAccess.open(anim_json_path, FileAccess.READ)
	var a_data = JSON.parse_string(a_file.get_as_text())
	var sheet_texture = load(sheet_path) as Texture2D
	if not sheet_texture:
		return

	var sf = SpriteFrames.new()
	for existing in sf.get_animation_names():
		sf.remove_animation(existing)

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
	anim_sprite.flip_h = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ball):
		var balls = get_tree().get_nodes_in_group("ball")
		if not balls.is_empty():
			ball = balls[0] as Ball

	match current_state:
		GKState.GUARD:
			_process_guard(delta)
		GKState.DIVING:
			_process_diving(delta)
		GKState.RECOVERING:
			_process_recovering(delta)
		GKState.HOLDING:
			_process_holding(delta)

func _process_guard(delta: float) -> void:
	if not is_instance_valid(ball):
		return

	# Calcular posición de tapado sobre la línea del arco
	# Bisectriz entre el centro del arco y la pelota
	var to_ball = ball.global_position - goal_center
	var target_y = 0.0
	if to_ball.x < -10.0:
		var slope = to_ball.y / to_ball.x
		target_y = clampf((patrol_x - goal_center.x) * slope, -goal_half_height, goal_half_height)
	else:
		target_y = clampf(ball.global_position.y, -goal_half_height, goal_half_height)

	var target_pos = Vector2(patrol_x, target_y)
	var move_diff = target_pos.y - global_position.y

	# Velocidad según stat reflejos y velocidad
	var refl = float(stats.get("reflejos", 85))
	var vel_stat = float(stats.get("velocidad", 75))
	var max_gk_speed = lerp(180.0, 310.0, clampf(refl / 100.0, 0.0, 1.0))

	if abs(move_diff) > 4.0:
		velocity.y = move_toward(velocity.y, sign(move_diff) * max_gk_speed, 1200.0 * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, 1000.0 * delta)

	velocity.x = move_toward(velocity.x, (patrol_x - global_position.x) * 4.0, 800.0 * delta)
	move_and_slide()

	# Animación
	anim_sprite.flip_h = true
	if abs(velocity.y) > 20.0:
		if anim_sprite.sprite_frames.has_animation("walk_side"):
			anim_sprite.play("walk_side")
		else:
			anim_sprite.play("run_down")
	else:
		if anim_sprite.sprite_frames.has_animation("idle_down"):
			anim_sprite.play("idle_down")

	# Detección de tiro hacia el arco para lanzarse
	if ball.current_state == Ball.State.EN_VUELO and ball.velocity.x > 180.0:
		var dist_to_ball = global_position.distance_to(ball.global_position)
		if dist_to_ball < (130.0 + refl * 0.6) and ball.global_position.x < patrol_x + 20.0:
			_perform_dive()

func _perform_dive() -> void:
	current_state = GKState.DIVING
	dive_timer = 0.45

	# Simulación de atajada con rotación y escala (regla de contexto)
	var dive_up = ball.global_position.y < global_position.y
	var angle = deg_to_rad(-40.0 if dive_up else 40.0)

	anim_sprite.rotation = angle
	anim_sprite.scale = Vector2(1.3, 0.75) # Estiramiento atlético
	
	# Impulso físico de atajada hacia la trayectoria
	var dive_dir = Vector2(-0.3, -1.0 if dive_up else 1.0).normalized()
	velocity = dive_dir * 280.0

func _process_diving(delta: float) -> void:
	dive_timer -= delta
	move_and_slide()

	# Chequear si intercepta la pelota durante la atajada
	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		var dist = global_position.distance_to(ball.global_position)
		var refl = float(stats.get("reflejos", 85))
		var save_reach = 42.0 + (refl / 100.0) * 18.0

		if dist <= save_reach:
			# Atajada exitosa
			_on_save_successful()
			return

	if dive_timer <= 0.0:
		current_state = GKState.RECOVERING

func _on_save_successful() -> void:
	current_state = GKState.HOLDING
	hold_timer = 0.65
	has_ball = true
	ball.take_possession(self)
	emit_signal("shot_saved", self)

func _process_holding(delta: float) -> void:
	hold_timer -= delta
	velocity = Vector2.ZERO
	move_and_slide()

	if hold_timer <= 0.0:
		_clear_ball()

func _clear_ball() -> void:
	has_ball = false
	current_state = GKState.RECOVERING
	# Despeje hacia campo rival
	var clear_dir = Vector2(-1.0, randf_range(-0.5, 0.5)).normalized()
	ball.kick(clear_dir, 550.0, self)

func _process_recovering(delta: float) -> void:
	# Restaurar escala y rotación suavemente
	anim_sprite.rotation = rotate_toward(anim_sprite.rotation, 0.0, 5.0 * delta)
	anim_sprite.scale = anim_sprite.scale.move_toward(Vector2.ONE, 2.5 * delta)
	velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	move_and_slide()

	if abs(anim_sprite.rotation) < 0.05 and anim_sprite.scale.is_equal_approx(Vector2.ONE):
		anim_sprite.rotation = 0.0
		anim_sprite.scale = Vector2.ONE
		current_state = GKState.GUARD

func on_ball_possessed(_b: Ball) -> void:
	has_ball = true

func on_ball_lost(_b: Ball) -> void:
	has_ball = false
