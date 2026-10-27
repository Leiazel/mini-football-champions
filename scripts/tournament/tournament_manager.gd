extends Node
class_name TournamentManager

static var selected_user_team_id: String = "team_brasil"

signal round_started(round_data: Dictionary, user_team: Dictionary, opp_team: Dictionary)
signal score_updated(user_score: int, opp_score: int)
signal match_ended(user_won: bool, is_champion: bool)

var teams_data: Dictionary = {}
var tournament_data: Dictionary = {}

var user_team_id: String = "team_brasil"
var current_round_index: int = 0
var match_duration: float = 60.0
var target_score: int = 3

var user_score: int = 0
var opp_score: int = 0
var time_left: float = 60.0
var is_active: bool = false
var is_champion: bool = false

func _init() -> void:
	load_data()
	user_team_id = selected_user_team_id

func load_data() -> void:
	# 1. Cargar teams.json
	var t_file = FileAccess.open("res://data/teams.json", FileAccess.READ)
	if t_file:
		var parsed = JSON.parse_string(t_file.get_as_text())
		if parsed and parsed.has("teams"):
			teams_data = parsed["teams"]

	# 2. Cargar tournament.json
	var tour_file = FileAccess.open("res://data/tournament.json", FileAccess.READ)
	if tour_file:
		var parsed = JSON.parse_string(tour_file.get_as_text())
		if parsed and parsed.has("tournament"):
			tournament_data = parsed["tournament"]
			match_duration = float(tournament_data.get("match_duration_seconds", 60))
			target_score = int(tournament_data.get("target_score_to_win", 3))

func get_total_rounds() -> int:
	if tournament_data.has("rounds"):
		return tournament_data["rounds"].size()
	return 0

func get_current_round() -> Dictionary:
	var rounds = tournament_data.get("rounds", [])
	if current_round_index >= 0 and current_round_index < rounds.size():
		return rounds[current_round_index]
	return {}

func get_team(team_id: String) -> Dictionary:
	return teams_data.get(team_id, {})

func start_round(idx: int) -> void:
	current_round_index = idx
	var round_info = get_current_round()
	var opp_id = round_info.get("opponent_team", "team_desafiantes")

	# Si el usuario eligió el mismo equipo rival, alternar
	if opp_id == user_team_id:
		opp_id = "team_estrellas" if user_team_id != "team_estrellas" else "team_italia"

	user_score = 0
	opp_score = 0
	time_left = match_duration
	is_active = true
	is_champion = false

	var u_team = get_team(user_team_id)
	var o_team = get_team(opp_id)

	emit_signal("round_started", round_info, u_team, o_team)
	emit_signal("score_updated", user_score, opp_score)

func update_time(delta: float) -> void:
	if not is_active:
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_check_match_end()

func score_user_goal() -> void:
	if not is_active:
		return
	user_score += 1
	emit_signal("score_updated", user_score, opp_score)
	if user_score >= target_score:
		_check_match_end()

func score_opp_goal() -> void:
	if not is_active:
		return
	opp_score += 1
	emit_signal("score_updated", user_score, opp_score)
	if opp_score >= target_score:
		_check_match_end()

func _check_match_end() -> void:
	is_active = false
	var user_won = false

	if user_score > opp_score:
		user_won = true
	elif user_score < opp_score:
		user_won = false
	else:
		# En empate tras tiempo reglamentario, se define por gol de oro
		is_active = true
		return

	if user_won:
		if current_round_index == get_total_rounds() - 1:
			is_champion = true

	emit_signal("match_ended", user_won, is_champion)

func next_round() -> bool:
	if current_round_index + 1 < get_total_rounds():
		start_round(current_round_index + 1)
		return true
	return false

func restart_current_round() -> void:
	start_round(current_round_index)

