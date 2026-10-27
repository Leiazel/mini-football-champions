extends CharacterBody2D
class_name Goalkeeper

const BASE_SPRITE_SCALE := Vector2(0.78, 0.78)
const BASE_SPRITE_OFFSET := Vector2(0, -42)

@export var player_id: String = "gk_arg"
@export var team_id: String = "team_opp"
@export var goal_center: Vector2 = Vector2(1200, 0)
@export var goal_half_height: float = 95.0
@export var patrol_x: float = 1140.0

enum GKState {
	GUARD,
	DIVING,
	RECOVERING,
	HOLDING
}

var current_state: GKState = GKState.GUARD
var player_name: String = "El Guardián"
var role: String = "GK"
var stats: Dictionary = {
	"reflejos": 88,
	"velocidad": 76,
	"control": 76,
	"pase": 80,
	"defensa": 90
}

var ball: Ball = null
var dive_timer: float = 0.0
var hold_timer: float = 0.0
var pickup_lock_timer: float = 0.0
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
	anim_sprite.position = BASE_SPRITE_OFFSET
	anim_sprite.scale = BASE_SPRITE_SCALE
	if is_instance_valid(shadow):
		shadow.scale = BASE_SPRITE_SCALE
	anim_sprite.flip_h = false

func _physics_process(delta: float) -> void:
	if pickup_lock_timer > 0.0:
		pickup_lock_timer -= delta

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

	var to_ball = ball.global_position - goal_center
	var target_y = 0.0
	var is_right_side = (patrol_x > 0)

	if (is_right_side and to_ball.x < -10.0) or (!is_right_side and to_ball.x > 10.0):
		var slope = to_ball.y / to_ball.x
		target_y = clampf((patrol_x - goal_center.x) * slope, -goal_half_height, goal_half_height)
	else:
		target_y = clampf(ball.global_position.y, -goal_half_height, goal_half_height)

	# Si la pelota está suelta muy cerca en el área chica, salir a buscarla
	var target_x = patrol_x
	if ball.current_state == Ball.State.LIBRE and global_position.distance_to(ball.global_position) < 135.0:
		target_x = clampf(ball.global_position.x, patrol_x - 75.0, patrol_x + 75.0)
		target_y = clampf(ball.global_position.y, -goal_half_height * 1.2, goal_half_height * 1.2)

	var target_pos = Vector2(target_x, target_y)
	var move_diff = target_pos.y - global_position.y

	var refl = float(stats.get("reflejos", 85))
	var max_gk_speed = lerp(210.0, 340.0, clampf(refl / 100.0, 0.0, 1.0))

	if abs(move_diff) > 4.0:
		velocity.y = move_toward(velocity.y, sign(move_diff) * max_gk_speed, 1400.0 * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, 1200.0 * delta)

	velocity.x = move_toward(velocity.x, (target_x - global_position.x) * 5.0, 1000.0 * delta)
	move_and_slide()

	facing_direction = Vector2.LEFT if is_right_side else Vector2.RIGHT

	if anim_sprite.sprite_frames:
		if abs(velocity.y) > 22.0:
			var side_anim = "walk_left" if (is_right_side and anim_sprite.sprite_frames.has_animation("walk_left")) else "walk_side"
			if anim_sprite.sprite_frames.has_animation(side_anim):
				anim_sprite.flip_h = (is_right_side and side_anim == "walk_side")
				anim_sprite.play(side_anim)
			elif anim_sprite.sprite_frames.has_animation("run_down"):
				anim_sprite.flip_h = false
				anim_sprite.play("run_down")
		elif anim_sprite.sprite_frames.has_animation("idle_down"):
			anim_sprite.flip_h = false
			anim_sprite.play("idle_down")

	# Chequeo de disparo aproximándose
	var is_ball_threatening = false
	if ball.current_state == Ball.State.EN_VUELO:
		if is_right_side and ball.velocity.x > 160.0 and ball.global_position.x < patrol_x + 30.0:
			is_ball_threatening = true
		elif !is_right_side and ball.velocity.x < -160.0 and ball.global_position.x > patrol_x - 30.0:
			is_ball_threatening = true

	if is_ball_threatening:
		var dist_to_ball = global_position.distance_to(ball.global_position)
		if dist_to_ball < (150.0 + refl * 0.7):
			_perform_dive()

func _perform_dive() -> void:
	current_state = GKState.DIVING
	dive_timer = 0.45

	var is_right_side = (patrol_x > 0)
	var dive_up = ball.global_position.y < global_position.y
	var angle = deg_to_rad(-38.0 if dive_up else 38.0)
	if not is_right_side:
		angle = -angle

	anim_sprite.rotation = angle
	anim_sprite.scale = Vector2(BASE_SPRITE_SCALE.x * 1.25, BASE_SPRITE_SCALE.y * 0.78)

	var dir_x = -0.25 if is_right_side else 0.25
	var dive_dir = Vector2(dir_x, -1.0 if dive_up else 1.0).normalized()
	velocity = dive_dir * 310.0

func _process_diving(delta: float) -> void:
	dive_timer -= delta
	move_and_slide()

	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		var dist = global_position.distance_to(ball.global_position)
		var refl = float(stats.get("reflejos", 85))
		var save_reach = 46.0 + (refl / 100.0) * 20.0

		if dist <= save_reach:
			_on_save_successful()
			return

	if dive_timer <= 0.0:
		current_state = GKState.RECOVERING

func _on_save_successful() -> void:
	current_state = GKState.HOLDING
	hold_timer = 0.55
	has_ball = true
	ball.take_possession(self)
	emit_signal("shot_saved", self)

func _process_holding(delta: float) -> void:
	hold_timer -= delta
	velocity = Vector2.ZERO
	anim_sprite.rotation = rotate_toward(anim_sprite.rotation, 0.0, 8.0 * delta)
	anim_sprite.scale = anim_sprite.scale.move_toward(BASE_SPRITE_SCALE, 3.0 * delta)
	move_and_slide()

	if hold_timer <= 0.0:
		_clear_ball()

func _clear_ball() -> void:
	has_ball = false
	pickup_lock_timer = 0.45
	current_state = GKState.RECOVERING
	var is_right_side = (patrol_x > 0)
	var dir_x = -1.0 if is_right_side else 1.0

	# Buscar un compañero desmarcado (preferiblemente DF o MF) para salir jugando
	var best_mate: Player = null
	var best_score: float = -9999.0
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			var dist = global_position.distance_to(p.global_position)
			var score = -dist * 0.4 + (120.0 if p.role == "DF" else (80.0 if p.role == "MF" else 20.0))
			if score > best_score:
				best_score = score
				best_mate = p

	if is_instance_valid(best_mate):
		facing_direction = (best_mate.global_position - global_position).normalized()
		ball.pass_to(best_mate, 720.0, self)
		if team_id == "team_user" and not best_mate.is_ai:
			for p in get_tree().get_nodes_in_group("players"):
				if p is Player and p.team_id == "team_user":
					p.set_user_controlled(p == best_mate)
	else:
		var clear_dir = Vector2(dir_x, randf_range(-0.4, 0.4)).normalized()
		ball.kick(clear_dir, 680.0, self)

func _process_recovering(delta: float) -> void:
	anim_sprite.rotation = rotate_toward(anim_sprite.rotation, 0.0, 6.0 * delta)
	anim_sprite.scale = anim_sprite.scale.move_toward(BASE_SPRITE_SCALE, 2.5 * delta)
	velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()

	if abs(anim_sprite.rotation) < 0.05 and anim_sprite.scale.distance_to(BASE_SPRITE_SCALE) < 0.03:
		anim_sprite.rotation = 0.0
		anim_sprite.scale = BASE_SPRITE_SCALE
		current_state = GKState.GUARD

func on_ball_possessed(_b: Ball) -> void:
	has_ball = true
	if current_state != GKState.HOLDING:
		current_state = GKState.HOLDING
		hold_timer = 0.50

func on_ball_lost(_b: Ball) -> void:
	has_ball = false
