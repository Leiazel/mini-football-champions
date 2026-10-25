extends Node2D

@export var field_width: float = 1600.0
@export var field_height: float = 1000.0
@export var line_width: float = 4.0

var grass_dark: Color = Color(0.18, 0.52, 0.22)
var grass_light: Color = Color(0.20, 0.56, 0.24)
var line_color: Color = Color(0.92, 0.95, 0.92, 0.85)

func _draw() -> void:
	var half_w = field_width / 2.0
	var half_h = field_height / 2.0
	var rect_total = Rect2(-half_w - 100, -half_h - 100, field_width + 200, field_height + 200)
	
	# Césped de base
	draw_rect(rect_total, grass_dark, true)

	# Franjas de césped cortado
	var stripe_w = 100.0
	var start_x = -half_w
	var stripe_count = int(field_width / stripe_w)
	for i in range(stripe_count):
		if i % 2 == 0:
			draw_rect(Rect2(start_x + i * stripe_w, -half_h, stripe_w, field_height), grass_light, true)

	# Límites del campo
	draw_rect(Rect2(-half_w, -half_h, field_width, field_height), line_color, false, line_width)

	# Línea de medio campo
	draw_line(Vector2(0, -half_h), Vector2(0, half_h), line_color, line_width)

	# Círculo central
	draw_arc(Vector2.ZERO, 90.0, 0, TAU, 64, line_color, line_width)
	# Punto central
	draw_circle(Vector2.ZERO, 5.0, line_color)

	# Áreas de penal (izquierda y derecha)
	var box_w = 220.0
	var box_h = 420.0
	draw_rect(Rect2(-half_w, -box_h / 2.0, box_w, box_h), line_color, false, line_width)
	draw_rect(Rect2(half_w - box_w, -box_h / 2.0, box_w, box_h), line_color, false, line_width)

	# Área chica
	var small_w = 90.0
	var small_h = 220.0
	draw_rect(Rect2(-half_w, -small_h / 2.0, small_w, small_h), line_color, false, line_width)
	draw_rect(Rect2(half_w - small_w, -small_h / 2.0, small_w, small_h), line_color, false, line_width)
