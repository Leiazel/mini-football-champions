extends CharacterBody2D
class_name Ball

enum State {
	LIBRE,
	CONTROLADA,
	EN_VUELO
}

@export var current_state: State = State.LIBRE
@export var pickup_radius: float = 34.0
@export var base_friction: float = 380.0

var carrier: CharacterBody2D = null
var kick_cooldown: float = 0.0
var last_kicker: CharacterBody2D = null

# Referencias visuales
@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

signal state_changed(new_state: State)
signal possession_changed(new_carrier: CharacterBody2D)

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
	# Fricción desacelerando la pelota
	if velocity.length() > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, base_friction * delta)
		move_and_slide()
		# Rotación visual según movimiento
		sprite.rotation += velocity.length() * 0.03 * delta * (1.0 if velocity.x >= 0 else -1.0)
	
	# Verificación de recogida por jugadores cercanos
	_check_for_pickup()

func _process_controlada(delta: float) -> void:
	if not is_instance_valid(carrier):
		set_libre(Vector2.ZERO)
		return

	# Obtener dirección hacia donde mira el jugador
	var facing = carrier.get("facing_direction")
	if facing == null or facing == Vector2.ZERO:
		facing = Vector2.DOWN

	# El stat control (1-100) determina qué tan pegada va la pelota
	var control_stat: float = 70.0
	if carrier.get("stats") and carrier.stats.has("control"):
		control_stat = float(carrier.stats["control"])

	# Cuanto mayor el control, menor la distancia y más reactivo el seguimiento
	# Control 40 -> 32px | Control 95 -> 18px
	var t: float = clampf(control_stat / 100.0, 0.0, 1.0)
	var ball_distance: float = lerp(34.0, 17.0, t)
	var lerp_weight: float = lerp(18.0, 32.0, t)

	# Posición objetivo frente al jugador
	var target_pos: Vector2 = carrier.global_position + facing.normalized() * ball_distance
	
	# Si el jugador corre, añadimos un micro-dribble en sincronía
	if carrier.get("is_moving"):
		var speed_factor = carrier.velocity.length() / 250.0
		# Rotar la pelota acompañando la carrera
		sprite.rotation += carrier.velocity.length() * 0.025 * delta

	global_position = global_position.lerp(target_pos, lerp_weight * delta)
	velocity = carrier.velocity

func _process_en_vuelo(delta: float) -> void:
	move_and_slide()
	sprite.rotation += velocity.length() * 0.035 * delta
	velocity = velocity.move_toward(Vector2.ZERO, (base_friction * 0.5) * delta)
	
	if velocity.length() < 120.0:
		current_state = State.LIBRE
		emit_signal("state_changed", current_state)
	else:
		_check_for_pickup()

func _check_for_pickup() -> void:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player == last_kicker and kick_cooldown > 0.0:
			continue
		var dist = global_position.distance_to(player.global_position)
		if dist <= pickup_radius:
			take_possession(player)
			break

func take_possession(player: CharacterBody2D) -> void:
	carrier = player
	current_state = State.CONTROLADA
	if player.has_method("on_ball_possessed"):
		player.on_ball_possessed(self)
	emit_signal("possession_changed", carrier)
	emit_signal("state_changed", current_state)

func set_libre(initial_velocity: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	velocity = initial_velocity
	current_state = State.LIBRE
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)

func kick(direction: Vector2, power: float, kicker: CharacterBody2D) -> void:
	last_kicker = kicker
	kick_cooldown = 0.35
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	velocity = direction.normalized() * power
	current_state = State.EN_VUELO
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)
