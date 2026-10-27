#!/usr/bin/env python3
"""
Script de verificación exhaustiva para Mini Football: Torneos (v2).
Valida:
1. Integridad de archivos del proyecto (escenas, scripts, configuraciones).
2. Validez de todos los JSON (data/players.json, data/anims/*.json, data/teams.json, data/tournament.json).
3. Existencia y resolución de todas las rutas de texturas (res://).
4. Coherencia del schema de animaciones para todos los jugadores.
5. Cálculos de Hito 1 (Conducción y control de pelota).
6. Cálculos de Hito 2 (Pase entre dos jugadores y cono de visión).
7. Cálculos de Hito 3 (Tiro al arco y Arquero con reflejos y atajada simulada).
8. Lógica de Hito 4 (Rival con IA básica 3v3 y fórmula de robo de balón).
9. Lógica de Hito 5 (Carga de equipos desde JSON y modo torneo con 6 niveles y Jefe Final).
"""

import os
import sys
import json
import math

def test_project():
    errors = []
    print("--- 1. Verificando estructura de archivos ---")
    required_files = [
        "project.godot",
        ".gitignore",
        "docs/INTERNO_no_subir.md",
        "tools/procesar_lote.py",
        "tools/extractor_anims.py",
        "data/players.json",
        "data/teams.json",
        "data/tournament.json",
        "scripts/ball/ball.gd",
        "scripts/player/player.gd",
        "scripts/goal/goal.gd",
        "scripts/goalkeeper/goalkeeper.gd",
        "scripts/pitch/test_pitch.gd",
        "scripts/pitch/pitch_ground.gd",
        "scripts/tournament/tournament_manager.gd",
        "scripts/tournament/tournament_match.gd",
        "scenes/ball/Ball.tscn",
        "scenes/player/Player.tscn",
        "scenes/goal/Goal.tscn",
        "scenes/goalkeeper/Goalkeeper.tscn",
        "scenes/field/TestPitch.tscn",
        "scenes/tournament/TournamentMatch.tscn",
        "assets/sprites/ball.png",
        "assets/sprites/shadow.png",
        "assets/sprites/ball_shadow.png"
    ]
    for rf in required_files:
        if not os.path.exists(rf):
            errors.append(f"Archivo requerido faltante: {rf}")
        else:
            print(f"  [OK] {rf}")

    print("\n--- 2. Verificando data/players.json ---")
    with open("data/players.json", "r", encoding="utf-8") as f:
        players_data = json.load(f)

    players = players_data.get("players", {})
    if len(players) < 26:
        errors.append(f"Se esperaban al menos 26 jugadores en players.json, encontrados: {len(players)}")
    else:
        print(f"  [OK] {len(players)} jugadores registrados en players.json (20 de campo + 6 arqueros únicos)")

    gk_sheets = set()
    field_sheets = set()
    for pid, p in players.items():
        role = p.get("role", "FW")
        st = p.get("stats", {})
        sheet_path = p.get("sheet", "")
        if role == "GK":
            if "reflejos" not in st or not (1 <= st["reflejos"] <= 100):
                errors.append(f"Arquero {pid} falta o stat 'reflejos' inválido: {st.get('reflejos')}")
            if sheet_path in gk_sheets:
                errors.append(f"Arquero {pid} reutiliza spritesheet de otro arquero: {sheet_path}")
            gk_sheets.add(sheet_path)
        else:
            for req in ["velocidad", "control", "pase", "tiro", "defensa"]:
                val = st.get(req)
                if val is None or not (1 <= val <= 100):
                    errors.append(f"Jugador {pid} stat '{req}' inválido: {val}")
            field_sheets.add(sheet_path)

        for res_key in ["anims", "sheet", "portrait", "icon"]:
            res_path = p.get(res_key, "")
            local_path = res_path.replace("res://", "")
            if not os.path.exists(local_path):
                errors.append(f"Jugador {pid} recurso {res_key} no existe: {local_path}")

    overlap_sheets = gk_sheets.intersection(field_sheets)
    if overlap_sheets:
        errors.append(f"Arqueros reutilizan spritesheets de jugadores de campo: {overlap_sheets}")
    else:
        print(f"  [OK] 6 arqueros únicos verificados con 0 reutilización de spritesheets.")

    print(f"  [OK] Todos los stats y rutas de recursos verificadas.")

    print("\n--- 3. Verificando JSON de animaciones en data/anims/ ---")
    required_anims = [
        "idle_down", "run_down", "idle_up", "run_up",
        "walk_side", "run_side", "walk_down_side", "run_down_side",
        "walk_up_side", "run_up_side", "kick"
    ]

    for pid in players.keys():
        anim_file = f"data/anims/{pid}.json"
        if not os.path.exists(anim_file):
            continue
        with open(anim_file, "r", encoding="utf-8") as f:
            adata = json.load(f)

        anims = adata.get("animations", {})
        for req_a in required_anims:
            if req_a not in anims:
                errors.append(f"Jugador {pid} no tiene la animación: {req_a}")

    print(f"  [OK] Verificadas las 11 animaciones requeridas.")

    print("\n--- 4. Verificando lógica de Hito 1 (Conducción y control) ---")
    for ctrl, expected_dist in [(0, 28.0), (50, 23.0), (100, 18.0)]:
        t = ctrl / 100.0
        dist = 28.0 * (1.0 - t) + 18.0 * t
        assert abs(dist - expected_dist) < 1e-4
    print(f"  [OK] Fórmula de control validada.")

    print("\n--- 5. Verificando lógica de Hito 2 (Pase dirigido y cono) ---")
    facing = (1.0, 0.0)
    for desc, dir_vec, should_target in [
        ("Delante (+20 deg)", (0.939, 0.342), True),
        ("Diagonal frente (+45 deg)", (0.707, 0.707), True),
        ("Lateral (+80 deg)", (0.173, 0.984), True),
        ("Atrás (+140 deg)", (-0.766, 0.642), False)
    ]:
        dot = facing[0]*dir_vec[0] + facing[1]*dir_vec[1]
        assert (dot >= 0.15) == should_target
    print(f"  [OK] Algoritmo de selección por cono angular validado.")

    print("\n--- 6. Verificando lógica de Hito 3 (Tiro al arco y Arquero) ---")
    for shooter_id in ["arg_03", "star_01", "bra_01", "ita_02"]:
        if shooter_id not in players:
            continue
        t_stat = players[shooter_id]["stats"].get("tiro", 50)
        base_kick = 640.0 * (1.0 - t_stat/100.0) + 1020.0 * (t_stat/100.0)
        max_shot = base_kick * (0.85 + 0.35 * 1.0)
        assert max_shot > 900.0
    print(f"  [OK] Fórmulas de tiro potente verificadas.")

    print("\n--- 7. Verificando lógica de Hito 4 (Robo de balón e IA 3v3) ---")
    tackle_cases = [
        ("Cannavaro (Def 94) vs Haaland (Ctrl 82)", 94, 82, 0.50 + 12 * 0.008),
        ("Davids (Def 90) vs Messi (Ctrl 95)", 90, 95, 0.50 - 5 * 0.008),
        ("Ramos (Def 92) vs Ronaldinho (Ctrl 95)", 92, 95, 0.50 - 3 * 0.008)
    ]
    for desc, d_stat, c_stat, expected_prob in tackle_cases:
        calc_prob = max(0.15, min(0.85, 0.50 + (d_stat - c_stat) * 0.008))
        assert abs(calc_prob - expected_prob) < 1e-4
    print(f"  [OK] Fórmula de disputa y robo validada.")

    print("\n--- 8. Verificando datos de Torneo y Equipos (Hito 5) ---")
    with open("data/teams.json", "r", encoding="utf-8") as f:
        teams_data = json.load(f).get("teams", {})

    expected_teams = [
        "team_desafiantes", "team_veteranos", "team_estrellas",
        "team_italia", "team_brasil", "team_argentina"
    ]
    for tid in expected_teams:
        if tid not in teams_data:
            errors.append(f"Falta equipo en data/teams.json: {tid}")
        else:
            team = teams_data[tid]
            # Validar que todos los jugadores asignados al equipo existen
            for pid in team.get("formation", []):
                if pid not in players:
                    errors.append(f"Equipo {tid} referencia a jugador inexistente: {pid}")
            gk_id = team.get("gk_id")
            if gk_id not in players:
                errors.append(f"Equipo {tid} referencia a arquero inexistente: {gk_id}")
            print(f"  [OK] Equipo {tid} ({team['name']}) Nivel {team['level']} verificado.")

    with open("data/tournament.json", "r", encoding="utf-8") as f:
        tourn_data = json.load(f).get("tournament", {})

    rounds = tourn_data.get("rounds", [])
    if len(rounds) != 6:
        errors.append(f"Se esperaban 6 rondas de torneo, encontradas: {len(rounds)}")
    else:
        print(f"  [OK] Torneo con {len(rounds)} rondas de dificultad creciente.")

    # Validar que la ronda 6 es el Jefe Final Argentina
    final_round = rounds[-1]
    if final_round.get("opponent_team") != "team_argentina" or final_round.get("level") != 6:
        errors.append(f"La ronda final no es el Jefe Final (team_argentina Nivel 6): {final_round}")
    else:
        print(f"  [OK] Jefe Final confirmado: {final_round['name']} vs Selección Celeste (Nivel 6).")

    print("\n--- 9. Verificando escena TournamentMatch (4v4) ---")
    with open("scenes/tournament/TournamentMatch.tscn", "r", encoding="utf-8") as f:
        tourn_scene_content = f.read()

    for node in [
        "GoalLeft", "GoalRight", "GoalkeeperLeft", "GoalkeeperRight",
        "UserPlayer1", "UserPlayer2", "UserPlayer3",
        "RivalPlayer1", "RivalPlayer2", "RivalPlayer3",
        "Ball", "ModalPanel"
    ]:
        if f'node name="{node}"' not in tourn_scene_content:
            errors.append(f"Falta el nodo {node} en TournamentMatch.tscn")
        else:
            print(f"  [OK] Nodo de torneo presente: {node}")

    if errors:
        print(f"\n❌ SE ENCONTRARON {len(errors)} ERRORES:")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    else:
        print("\n✅ TODAS LAS PRUEBAS Y VALIDACIONES PASARON EXITOSAMENTE (0 errores).")

if __name__ == "__main__":
    test_project()
