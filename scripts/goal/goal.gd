extends Node2D
class_name Goal

signal goal_scored(goal_name: String)

@export var is_right_goal: bool = true
@export var goal_width: float = 220.0
@export var goal_depth: float = 65.0
@export var post_radius: float = 7.5

var post_color: Color = Color(0.96, 0.96, 0.98)
var net_color: Color = Color(0.9, 0.9, 0.9, 0.45)
var net_flash_timer: float = 0.0

@onready var goal_area: Area2D = $GoalArea

func _ready() -> void:
	if not is_right_goal:
		$GoalArea.position.x = -abs($GoalArea.position.x)
		$NetBack.position.x = -abs($NetBack.position.x)
		$NetTop.position.x = -abs($NetTop.position.x)
		$NetBottom.position.x = -abs($NetBottom.position.x)
	goal_area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if net_flash_timer > 0.0:
		net_flash_timer -= delta
		queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body is Ball or body.is_in_group("ball"):
		net_flash_timer = 0.6
		queue_redraw()
		emit_signal("goal_scored", name)

func _draw() -> void:
	var half_w = goal_width / 2.0
	var depth_dir = 1.0 if is_right_goal else -1.0
	var depth = goal_depth * depth_dir

	# 1. Dibujar malla de la red
	var current_net_color = Color(1.0, 0.9, 0.2, 0.75) if net_flash_timer > 0.0 else net_color

	for y in range(int(-half_w), int(half_w) + 1, 16):
		draw_line(Vector2(0, y), Vector2(depth, y), current_net_color, 1.5)

	for x in range(0, int(abs(depth)) + 1, 13):
		var cur_x = x * depth_dir
		draw_line(Vector2(cur_x, -half_w), Vector2(cur_x, half_w), current_net_color, 1.5)

	draw_line(Vector2(depth, -half_w), Vector2(depth, half_w), current_net_color, 2.5)

	# 2. Línea de meta
	draw_line(Vector2(0, -half_w), Vector2(0, half_w), Color(1.0, 1.0, 1.0, 0.75), 3.5)

	# 3. Postes y travesaños laterales
	draw_line(Vector2(0, -half_w), Vector2(depth, -half_w), post_color, 3.5)
	draw_line(Vector2(0, half_w), Vector2(depth, half_w), post_color, 3.5)

	draw_circle(Vector2(0, -half_w), post_radius, post_color)
	draw_circle(Vector2(0, -half_w), post_radius + 1.0, Color(0.1, 0.1, 0.1, 0.55), false, 1.5)

	draw_circle(Vector2(0, half_w), post_radius, post_color)
	draw_circle(Vector2(0, half_w), post_radius + 1.0, Color(0.1, 0.1, 0.1, 0.55), false, 1.5)
