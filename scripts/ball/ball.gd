extends CharacterBody2D
class_name Ball

enum State {
	LIBRE,
	CONTROLADA,
	EN_VUELO
}

@export var current_state: State = State.LIBRE
@export var pickup_radius: float = 36.0
@export var base_friction: float = 340.0

# Límites del campo (sincronizados con PitchGround 2400x1400)
@export var field_half_width: float = 1200.0
@export var field_half_height: float = 700.0
@export var goal_half_mouth: float = 110.0

var carrier: CharacterBody2D = null
var kick_cooldown: float = 0.0
var last_kicker: CharacterBody2D = null
var target_receiver: CharacterBody2D = null

# Referencias visuales
@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

signal state_changed(new_state: State)
signal possession_changed(new_carrier: CharacterBody2D)
signal pass_completed(receiver: CharacterBody2D)

func _ready() -> void:
	add_to_group("ball")

func _physics_process(delta: float) -> void:
	if kick_cooldown > 0.0:
		kick_cooldown -= delta
		if kick_cooldown <= 0.0:
			last_kicker = null

	match current_state:
		State.LIBRE:
			_process_libre(delta)
		State.CONTROLADA:
			_process_controlada(delta)
		State.EN_VUELO:
			_process_en_vuelo(delta)

func _process_libre(delta: float) -> void:
	if velocity.length() > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, base_friction * delta)
		_move_with_bounce(delta)
		sprite.rotation += velocity.length() * 0.028 * delta * (1.0 if velocity.x >= 0 else -1.0)

	_keep_inside_pitch_bounds()
	_check_for_pickup()

func _process_controlada(delta: float) -> void:
	if not is_instance_valid(carrier):
		set_libre(Vector2.ZERO)
		return

	var facing = carrier.get("facing_direction")
	if facing == null or facing == Vector2.ZERO:
		facing = Vector2.DOWN

	var control_stat: float = 75.0
	if carrier.get("stats") and carrier.stats.has("control"):
		control_stat = float(carrier.stats["control"])

	var t: float = clampf(control_stat / 100.0, 0.0, 1.0)
	var ball_distance: float = lerp(28.0, 18.0, t)
	var lerp_weight: float = lerp(20.0, 34.0, t)

	var target_pos: Vector2 = carrier.global_position + facing.normalized() * ball_distance

	if carrier.get("is_moving"):
		sprite.rotation += carrier.velocity.length() * 0.025 * delta * (1.0 if facing.x >= 0 else -1.0)

	global_position = global_position.lerp(target_pos, clampf(lerp_weight * delta, 0.0, 1.0))
	velocity = carrier.velocity

func _process_en_vuelo(delta: float) -> void:
	# Si es un pase dirigido a un compañero, guiar ligeramente la trayectoria estilo Inazuma
	if is_instance_valid(target_receiver):
		var to_target = target_receiver.global_position - global_position
		var dist_to_target = to_target.length()
		if dist_to_target <= (pickup_radius + 22.0):
			var recv = target_receiver
			target_receiver = null
			take_possession(recv)
			emit_signal("pass_completed", recv)
			return
		elif velocity.length() > 120.0:
			var desired_dir = to_target.normalized()
			var current_speed = velocity.length()
			var new_dir = velocity.normalized().lerp(desired_dir, clampf(6.5 * delta, 0.0, 1.0)).normalized()
			velocity = new_dir * current_speed

	_move_with_bounce(delta)
	_keep_inside_pitch_bounds()
	sprite.rotation += velocity.length() * 0.032 * delta * (1.0 if velocity.x >= 0 else -1.0)
	velocity = velocity.move_toward(Vector2.ZERO, (base_friction * 0.42) * delta)

	if velocity.length() < 95.0:
		target_receiver = null
		current_state = State.LIBRE
		emit_signal("state_changed", current_state)
	else:
		_check_for_pickup()

func _move_with_bounce(delta: float) -> void:
	var collision = move_and_collide(velocity * delta)
	if collision:
		var normal = collision.get_normal()
		velocity = velocity.bounce(normal) * 0.72
		target_receiver = null

func _keep_inside_pitch_bounds() -> void:
	var margin: float = 14.0
	# Rebote en bandas laterales (arriba y abajo)
	if global_position.y < -field_half_height + margin:
		global_position.y = -field_half_height + margin
		if velocity.y < 0.0:
			velocity.y = -velocity.y * 0.78
			target_receiver = null
	elif global_position.y > field_half_height - margin:
		global_position.y = field_half_height - margin
		if velocity.y > 0.0:
			velocity.y = -velocity.y * 0.78
			target_receiver = null

	# Rebote en líneas de fondo (excepto dentro de la boca del arco)
	var in_goal_mouth = abs(global_position.y) <= goal_half_mouth
	if not in_goal_mouth:
		if global_position.x < -field_half_width + margin:
			global_position.x = -field_half_width + margin
			if velocity.x < 0.0:
				velocity.x = -velocity.x * 0.78
				target_receiver = null
		elif global_position.x > field_half_width - margin:
			global_position.x = field_half_width - margin
			if velocity.x > 0.0:
				velocity.x = -velocity.x * 0.78
				target_receiver = null
	else:
		# Fondo de la red dentro del arco
		var max_goal_depth = field_half_width + 62.0
		global_position.x = clampf(global_position.x, -max_goal_depth, max_goal_depth)

func _check_for_pickup() -> void:
	var players = get_tree().get_nodes_in_group("players")
	var best_player: CharacterBody2D = null
	var best_dist: float = pickup_radius

	for player in players:
		if not is_instance_valid(player):
			continue
		if player == last_kicker and kick_cooldown > 0.0:
			continue
		if player.get("pickup_lock_timer") != null and player.pickup_lock_timer > 0.0:
			continue
		# Si es un pase dirigido, compañeros que no son el receptor solo la toman si están muy cerca
		var eff_radius = pickup_radius
		if is_instance_valid(target_receiver) and player != target_receiver:
			if player.get("team_id") == target_receiver.get("team_id"):
				eff_radius = pickup_radius * 0.55
			else:
				eff_radius = pickup_radius * 0.85

		var dist = global_position.distance_to(player.global_position)
		if dist <= eff_radius and dist <= best_dist:
			best_dist = dist
			best_player = player

	if is_instance_valid(best_player):
		take_possession(best_player)

func take_possession(player: CharacterBody2D) -> void:
	if is_instance_valid(carrier) and carrier != player and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = player
	target_receiver = null
	current_state = State.CONTROLADA
	if player.has_method("on_ball_possessed"):
		player.on_ball_possessed(self)
	emit_signal("possession_changed", carrier)
	emit_signal("state_changed", current_state)

func set_libre(initial_velocity: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	target_receiver = null
	velocity = initial_velocity
	current_state = State.LIBRE
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)

func kick(direction: Vector2, power: float, kicker: CharacterBody2D) -> void:
	last_kicker = kicker
	kick_cooldown = 0.32
	target_receiver = null
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	velocity = direction.normalized() * power
	current_state = State.EN_VUELO
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)

func pass_to(target: CharacterBody2D, power: float, kicker: CharacterBody2D) -> void:
	last_kicker = kicker
	kick_cooldown = 0.25
	target_receiver = target
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null

	var dir_to_target = (target.global_position - global_position).normalized()
	velocity = dir_to_target * power
	current_state = State.EN_VUELO
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)
