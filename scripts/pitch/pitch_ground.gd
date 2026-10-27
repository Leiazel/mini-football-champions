extends Node2D

@export var field_width: float = 2400.0
@export var field_height: float = 1400.0
@export var line_width: float = 4.5

var grass_outer: Color = Color(0.13, 0.40, 0.17)
var grass_dark: Color = Color(0.18, 0.52, 0.22)
var grass_light: Color = Color(0.21, 0.57, 0.25)
var line_color: Color = Color(0.94, 0.97, 0.94, 0.88)

func _draw() -> void:
	var half_w = field_width / 2.0
	var half_h = field_height / 2.0
	var rect_outer = Rect2(-half_w - 220, -half_h - 180, field_width + 440, field_height + 360)

	# Exterior del campo y césped base
	draw_rect(rect_outer, grass_outer, true)
	draw_rect(Rect2(-half_w, -half_h, field_width, field_height), grass_dark, true)

	# Franjas de césped cortado
	var stripe_w = 120.0
	var start_x = -half_w
	var stripe_count = int(field_width / stripe_w)
	for i in range(stripe_count):
		if i % 2 == 0:
			draw_rect(Rect2(start_x + i * stripe_w, -half_h, stripe_w, field_height), grass_light, true)

	# Límites del campo
	draw_rect(Rect2(-half_w, -half_h, field_width, field_height), line_color, false, line_width)

	# Línea de medio campo
	draw_line(Vector2(0, -half_h), Vector2(0, half_h), line_color, line_width)

	# Círculo central y punto de saque
	draw_arc(Vector2.ZERO, 130.0, 0, TAU, 64, line_color, line_width)
	draw_circle(Vector2.ZERO, 6.5, line_color)

	# Áreas grandes (izquierda y derecha)
	var box_w = 330.0
	var box_h = 620.0
	draw_rect(Rect2(-half_w, -box_h / 2.0, box_w, box_h), line_color, false, line_width)
	draw_rect(Rect2(half_w - box_w, -box_h / 2.0, box_w, box_h), line_color, false, line_width)

	# Áreas chicas
	var small_w = 130.0
	var small_h = 320.0
	draw_rect(Rect2(-half_w, -small_h / 2.0, small_w, small_h), line_color, false, line_width)
	draw_rect(Rect2(half_w - small_w, -small_h / 2.0, small_w, small_h), line_color, false, line_width)

	# Puntos de penal y semicírculos de área
	var pen_dist = 230.0
	draw_circle(Vector2(-half_w + pen_dist, 0), 5.0, line_color)
	draw_circle(Vector2(half_w - pen_dist, 0), 5.0, line_color)
	draw_arc(Vector2(-half_w + pen_dist, 0), 115.0, -0.92, 0.92, 32, line_color, line_width)
	draw_arc(Vector2(half_w - pen_dist, 0), 115.0, PI - 0.92, PI + 0.92, 32, line_color, line_width)

	# Córners
	var corner_r = 28.0
	draw_arc(Vector2(-half_w, -half_h), corner_r, 0, PI * 0.5, 16, line_color, line_width)
	draw_arc(Vector2(half_w, -half_h), corner_r, PI * 0.5, PI, 16, line_color, line_width)
	draw_arc(Vector2(half_w, half_h), corner_r, PI, PI * 1.5, 16, line_color, line_width)
	draw_arc(Vector2(-half_w, half_h), corner_r, PI * 1.5, TAU, 16, line_color, line_width)
