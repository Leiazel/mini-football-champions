extends Control

# Datos cargados
var teams_data: Dictionary = {}
var players_data: Dictionary = {}
var tournament_data: Dictionary = {}

var team_order: Array[String] = [
	"team_desafiantes",
	"team_veteranos",
	"team_estrellas",
	"team_italia",
	"team_brasil",
	"team_argentina"
]

var selected_team_id: String = "team_brasil"
var team_buttons: Dictionary = {}

# Referencias a nodos UI
@onready var container_team_buttons: HBoxContainer = $CanvasLayer/Root/HeaderBox/TeamSelectorBar/Scroll/BtnContainer
@onready var label_team_title: Label = $CanvasLayer/Root/ContentBox/InfoPanel/VBox/LabelTeamTitle
@onready var label_team_level: Label = $CanvasLayer/Root/ContentBox/InfoPanel/VBox/LabelTeamLevel
@onready var label_team_desc: Label = $CanvasLayer/Root/ContentBox/InfoPanel/VBox/LabelTeamDesc
@onready var label_team_stats: Label = $CanvasLayer/Root/ContentBox/InfoPanel/VBox/LabelTeamStats
@onready var label_matchup_preview: Label = $CanvasLayer/Root/ContentBox/InfoPanel/VBox/MatchupBox/LabelMatchup

# Tarjetas de jugadores en la cancha táctica
@onready var card_gk: PanelContainer = $CanvasLayer/Root/ContentBox/PitchWrapper/TacticalPitch/CardGK
@onready var card_p1: PanelContainer = $CanvasLayer/Root/ContentBox/PitchWrapper/TacticalPitch/CardP1
@onready var card_p2: PanelContainer = $CanvasLayer/Root/ContentBox/PitchWrapper/TacticalPitch/CardP2
@onready var card_p3: PanelContainer = $CanvasLayer/Root/ContentBox/PitchWrapper/TacticalPitch/CardP3

# Botones de acción
@onready var btn_play: Button = $CanvasLayer/Root/FooterBox/ActionsBar/BtnPlay
@onready var btn_random: Button = $CanvasLayer/Root/FooterBox/ActionsBar/BtnRandom
@onready var btn_practice: Button = $CanvasLayer/Root/FooterBox/ActionsBar/BtnPractice

func _ready() -> void:
	_load_all_data()
	_create_team_buttons()
	_select_team(TournamentManager.selected_user_team_id if TournamentManager.selected_user_team_id in teams_data else "team_brasil")

	btn_play.pressed.connect(_on_btn_play_pressed)
	btn_random.pressed.connect(_on_btn_random_pressed)
	btn_practice.pressed.connect(_on_btn_practice_pressed)

func _load_all_data() -> void:
	# 1. Teams
	var f_teams = FileAccess.open("res://data/teams.json", FileAccess.READ)
	if f_teams:
		var p = JSON.parse_string(f_teams.get_as_text())
		if p and p.has("teams"):
			teams_data = p["teams"]

	# 2. Players
	var f_players = FileAccess.open("res://data/players.json", FileAccess.READ)
	if f_players:
		var p = JSON.parse_string(f_players.get_as_text())
		if p and p.has("players"):
			players_data = p["players"]

	# 3. Tournament
	var f_tour = FileAccess.open("res://data/tournament.json", FileAccess.READ)
	if f_tour:
		var p = JSON.parse_string(f_tour.get_as_text())
		if p and p.has("tournament"):
			tournament_data = p["tournament"]

func _create_team_buttons() -> void:
	# Limpiar cualquier hijo previo
	for c in container_team_buttons.get_children():
		c.queue_free()
	team_buttons.clear()

	for t_id in team_order:
		if not teams_data.has(t_id):
			continue
		var t_info = teams_data[t_id]
		var btn = Button.new()
		btn.text = "%s (Niv. %d)" % [t_info.get("name", t_id), t_info.get("level", 1)]
		btn.custom_minimum_size = Vector2(160, 36)
		btn.focus_mode = Control.FOCUS_NONE

		# Estilos personalizados inspirados en el draft Red & Beige
		_apply_button_inactive_style(btn)

		btn.pressed.connect(func(): _select_team(t_id))
		container_team_buttons.add_child(btn)
		team_buttons[t_id] = btn

func _apply_button_inactive_style(btn: Button) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.05, 0.06, 0.65)
	sb.border_color = Color(0.83, 0.70, 0.55, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86, 0.8))

func _apply_button_active_style(btn: Button) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.77, 0.13, 0.18, 0.95) # Red vibrant
	sb.border_color = Color(0.95, 0.85, 0.45, 0.95) # Champagne gold
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

func _select_team(t_id: String) -> void:
	if not teams_data.has(t_id):
		return
	selected_team_id = t_id
	TournamentManager.selected_user_team_id = t_id

	# Actualizar estilos de botones
	for id_k in team_buttons.keys():
		var b: Button = team_buttons[id_k]
		if id_k == t_id:
			_apply_button_active_style(b)
		else:
			_apply_button_inactive_style(b)

	var team = teams_data[t_id]
	label_team_title.text = team.get("name", "").to_upper()
	label_team_title.modulate = Color(team.get("color", "#FFFFFF"))
	label_team_level.text = "NIVEL DE DIFICULTAD: %d / 6" % team.get("level", 1)
	label_team_desc.text = team.get("description", "")

	# Cargar tarjetas de la formación
	var gk_id = team.get("gk_id", "gk_bra")
	var formation = team.get("formation", ["bra_03", "bra_01", "bra_02"])
	var p1_id = formation[0] if formation.size() > 0 else "bra_03"
	var p2_id = formation[1] if formation.size() > 1 else p1_id
	var p3_id = formation[2] if formation.size() > 2 else p2_id

	_setup_card(card_gk, gk_id, "ARQUERO")
	_setup_card(card_p1, p1_id, "DEFENSOR")
	_setup_card(card_p2, p2_id, "MEDIOCAMPO")
	if card_p3:
		_setup_card(card_p3, p3_id, "DELANTERO")

	# Estadísticas de equipo
	var avg_ctrl = _calculate_team_avg_stat([p1_id, p2_id, p3_id], "control")
	var avg_vel = _calculate_team_avg_stat([p1_id, p2_id, p3_id], "velocidad")
	var avg_def = _calculate_team_avg_stat([p1_id, p2_id, p3_id, gk_id], "defensa")
	label_team_stats.text = "PROMEDIO SQUAD:  CTRL %d  ·  VEL %d  ·  DEF %d" % [avg_ctrl, avg_vel, avg_def]

	# Preview del rival de Ronda 1
	var rounds = tournament_data.get("rounds", [])
	if not rounds.is_empty():
		var r1_opp_id = rounds[0].get("opponent_team", "team_desafiantes")
		if r1_opp_id == t_id:
			r1_opp_id = "team_estrellas"
		var r1_opp = teams_data.get(r1_opp_id, {})
		label_matchup_preview.text = "Rival Ronda 1: %s" % r1_opp.get("name", "El Rival")

func _calculate_team_avg_stat(p_ids: Array, stat_name: String) -> int:
	var total = 0
	var count = 0
	for pid in p_ids:
		if players_data.has(pid):
			var stats = players_data[pid].get("stats", {})
			if stats.has(stat_name):
				total += int(stats[stat_name])
				count += 1
	return int(float(total) / max(1, count))

func _setup_card(card_node: PanelContainer, player_id: String, slot_label: String) -> void:
	if not players_data.has(player_id):
		return
	var p = players_data[player_id]

	var photo_rect = card_node.get_node("VBox/PhotoContainer/Photo") as TextureRect
	var lbl_role = card_node.get_node("VBox/PhotoContainer/TopBadges/LabelRole") as Label
	var lbl_ovr = card_node.get_node("VBox/PhotoContainer/TopBadges/LabelOVR") as Label
	var lbl_name = card_node.get_node("VBox/Plate/LabelName") as Label
	var lbl_stats = card_node.get_node("VBox/Plate/LabelStats") as Label
	var lbl_slot = card_node.get_node("VBox/Plate/LabelSlot") as Label

	# Foto retrato
	var portrait_path: String = p.get("portrait", "")
	var tex: Texture2D = null
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		tex = load(portrait_path) as Texture2D
	if not tex and portrait_path != "":
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(portrait_path)) == OK:
			tex = ImageTexture.create_from_image(img)
	if not tex and ResourceLoader.exists("res://assets/sprites/bra_01_portrait.png"):
		tex = load("res://assets/sprites/bra_01_portrait.png") as Texture2D
	photo_rect.texture = tex

	# Rol y OVR
	var role = p.get("role", "FW")
	lbl_role.text = role
	lbl_slot.text = slot_label

	var stats = p.get("stats", {})
	var ovr = 85
	if role == "GK":
		ovr = int((stats.get("reflejos", 80) * 0.5) + (stats.get("defensa", 80) * 0.3) + (stats.get("velocidad", 70) * 0.2))
		lbl_stats.text = "REF %d · DEF %d · VEL %d" % [stats.get("reflejos", 80), stats.get("defensa", 80), stats.get("velocidad", 70)]
	else:
		ovr = int((stats.get("control", 80) * 0.35) + (stats.get("velocidad", 80) * 0.25) + (stats.get("tiro", 80) * 0.25) + (stats.get("defensa", 80) * 0.15))
		lbl_stats.text = "CTR %d · VEL %d · TIR %d" % [stats.get("control", 80), stats.get("velocidad", 80), stats.get("tiro", 80)]

	lbl_ovr.text = str(clamp(ovr, 60, 99))
	lbl_name.text = p.get("name", "Jugador").to_upper()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_btn_play_pressed()
		elif event.keycode == KEY_R:
			_on_btn_random_pressed()
		elif event.keycode == KEY_LEFT:
			_cycle_team(-1)
		elif event.keycode == KEY_RIGHT:
			_cycle_team(1)

func _cycle_team(dir: int) -> void:
	var idx = team_order.find(selected_team_id)
	if idx == -1:
		idx = 0
	var new_idx = (idx + dir + team_order.size()) % team_order.size()
	_select_team(team_order[new_idx])

func _on_btn_play_pressed() -> void:
	TournamentManager.selected_user_team_id = selected_team_id
	get_tree().change_scene_to_file("res://scenes/tournament/TournamentMatch.tscn")

func _on_btn_random_pressed() -> void:
	var valid_teams = team_order.filter(func(id): return id != selected_team_id)
	if not valid_teams.is_empty():
		valid_teams.shuffle()
		_select_team(valid_teams[0])

func _on_btn_practice_pressed() -> void:
	TournamentManager.selected_user_team_id = selected_team_id
	get_tree().change_scene_to_file("res://scenes/field/TestPitch.tscn")

