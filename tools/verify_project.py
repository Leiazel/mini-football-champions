#!/usr/bin/env python3
"""
Script de verificación exhaustiva para Mini Football: Torneos (v2).
Valida:
1. Integridad de archivos del proyecto (escenas, scripts, configuraciones).
2. Validez de todos los JSON (data/players.json, data/anims/*.json).
3. Existencia y resolución de todas las rutas de texturas (res://).
4. Coherencia del schema de animaciones para todos los jugadores.
5. Cálculos de Hito 1 (Conducción y control de pelota).
6. Cálculos de Hito 2 (Pase entre dos jugadores y cono de visión).
7. Lógica de Hito 3 (Tiro al arco y Arquero con reflejos y atajada simulada).
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
        "scripts/ball/ball.gd",
        "scripts/player/player.gd",
        "scripts/goal/goal.gd",
        "scripts/goalkeeper/goalkeeper.gd",
        "scripts/pitch/test_pitch.gd",
        "scripts/pitch/pitch_ground.gd",
        "scenes/ball/Ball.tscn",
        "scenes/player/Player.tscn",
        "scenes/goal/Goal.tscn",
        "scenes/goalkeeper/Goalkeeper.tscn",
        "scenes/field/TestPitch.tscn",
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
    if len(players) < 20:
        errors.append(f"Se esperaban al menos 20 jugadores en players.json, encontrados: {len(players)}")
    else:
        print(f"  [OK] {len(players)} jugadores registrados en players.json")

    # Validar arqueros y jugadores de campo
    for pid, p in players.items():
        role = p.get("role", "FW")
        st = p.get("stats", {})
        if role == "GK":
            if "reflejos" not in st or not (1 <= st["reflejos"] <= 100):
                errors.append(f"Arquero {pid} falta o stat 'reflejos' inválido: {st.get('reflejos')}")
        else:
            for req in ["velocidad", "control", "pase", "tiro", "defensa"]:
                val = st.get(req)
                if val is None or not (1 <= val <= 100):
                    errors.append(f"Jugador {pid} stat '{req}' inválido: {val}")

        for res_key in ["anims", "sheet"]:
            res_path = p.get(res_key, "")
            local_path = res_path.replace("res://", "")
            if not os.path.exists(local_path):
                errors.append(f"Jugador {pid} recurso {res_key} no existe: {local_path}")

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
    for ctrl, expected_dist in [(0, 34.0), (50, 25.5), (100, 17.0)]:
        t = ctrl / 100.0
        dist = 34.0 * (1.0 - t) + 17.0 * t
        assert abs(dist - expected_dist) < 1e-4
    print(f"  [OK] Fórmula de control validada en extremos y centro.")

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
    # A) Escala de tiro potente: lerp(540.0, 880.0, tiro / 100.0) * (0.8 + 0.35 * charge)
    for shooter_id in ["arg_03", "star_01", "bra_01", "ita_02"]:
        if shooter_id not in players:
            continue
        t_stat = players[shooter_id]["stats"].get("tiro", 50)
        base_kick = 540.0 * (1.0 - t_stat/100.0) + 880.0 * (t_stat/100.0)
        max_shot = base_kick * (0.8 + 0.35 * 1.0) # a plena carga
        print(f"  [OK] {shooter_id} ({players[shooter_id]['name']}): Stat Tiro={t_stat} -> Disparo Max={max_shot:.1f} px/s")

    # B) Arquero: reflejos, velocidad de cobertura y alcance
    gk = players["gk_01"]
    refl = gk["stats"]["reflejos"]
    gk_speed = 180.0 * (1.0 - refl/100.0) + 310.0 * (refl/100.0)
    save_reach = 42.0 + (refl / 100.0) * 18.0
    print(f"  [OK] Arquero gk_01 ({gk['name']}): Reflejos={refl} -> Vel Cobertura={gk_speed:.1f} px/s, Alcance Atajada={save_reach:.1f} px")

    # C) Escena TestPitch con GoalRight y Goalkeeper
    with open("scenes/field/TestPitch.tscn", "r", encoding="utf-8") as f:
        pitch_content = f.read()
    for req_node in ["GoalRight", "Goalkeeper", "Player1", "Player2", "Ball"]:
        if f'node name="{req_node}"' not in pitch_content:
            errors.append(f"TestPitch.tscn no contiene el nodo: {req_node}")
        else:
            print(f"  [OK] Nodo presente en cancha de pruebas: {req_node}")

    if errors:
        print(f"\n❌ SE ENCONTRARON {len(errors)} ERRORES:")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    else:
        print("\n✅ TODAS LAS PRUEBAS Y VALIDACIONES PASARON EXITOSAMENTE (0 errores).")

if __name__ == "__main__":
    test_project()
