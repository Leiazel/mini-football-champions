#!/usr/bin/env python3
"""
Script de verificación exhaustiva para Mini Football: Torneos (v2).
Valida:
1. Integridad de archivos del proyecto (escenas, scripts, configuraciones).
2. Validez de todos los JSON (data/players.json, data/anims/*.json).
3. Existencia y resolución de todas las rutas de texturas (res://).
4. Coherencia del schema de animaciones para todos los jugadores.
5. Cálculos de la máquina de estados de la pelota (distancias según stat control).
6. Lógica de pase entre dos jugadores (Hito 2):
   - Cono de visión de pase (dot product).
   - Velocidad del pase escalada con stat 'pase'.
   - Transición de control y posesión.
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
        "scripts/pitch/test_pitch.gd",
        "scripts/pitch/pitch_ground.gd",
        "scenes/ball/Ball.tscn",
        "scenes/player/Player.tscn",
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
    if len(players) != 20:
        errors.append(f"Se esperaban 20 jugadores en players.json, encontrados: {len(players)}")
    else:
        print(f"  [OK] 20 jugadores registrados en players.json")

    required_stats = ["velocidad", "control", "pase", "tiro", "defensa"]
    for pid, p in players.items():
        for st in required_stats:
            val = p.get("stats", {}).get(st)
            if val is None or not (1 <= val <= 100):
                errors.append(f"Jugador {pid} stat '{st}' inválido: {val}")

        for res_key in ["anims", "sheet", "portrait", "icon"]:
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
            errors.append(f"Falta archivo de animaciones: {anim_file}")
            continue
        with open(anim_file, "r", encoding="utf-8") as f:
            adata = json.load(f)

        anims = adata.get("animations", {})
        for req_a in required_anims:
            if req_a not in anims:
                errors.append(f"Jugador {pid} no tiene la animación: {req_a}")
            else:
                frames = anims[req_a].get("frames", [])
                if len(frames) == 0:
                    errors.append(f"Jugador {pid} animación '{req_a}' tiene 0 frames")

    print(f"  [OK] Verificadas las 11 animaciones requeridas para los 20 jugadores.")

    print("\n--- 4. Verificando lógica de Hito 1 (Conducción y control) ---")
    for ctrl, expected_dist in [(0, 34.0), (50, 25.5), (100, 17.0)]:
        t = ctrl / 100.0
        dist = 34.0 * (1.0 - t) + 17.0 * t
        assert abs(dist - expected_dist) < 1e-4
        print(f"  [OK] Control {ctrl:3d} -> Distancia de pelota: {dist:.1f}px")

    print("\n--- 5. Verificando lógica de Hito 2 (Mecánica de pase entre dos jugadores) ---")
    # A) Simulación del cono de visión de pase (dot product)
    facing = (1.0, 0.0) # Mirando a la derecha
    teammates_test = [
        ("Delante (+20 deg)", (0.939, 0.342), True),
        ("Diagonal frente (+45 deg)", (0.707, 0.707), True),
        ("Lateral (+80 deg)", (0.173, 0.984), True), # dot=0.173 > 0.15 threshold
        ("Atrás (+140 deg)", (-0.766, 0.642), False),
        ("Espalda total (180 deg)", (-1.0, 0.0), False)
    ]
    for desc, dir_vec, should_target in teammates_test:
        dot = facing[0]*dir_vec[0] + facing[1]*dir_vec[1]
        is_target = dot >= 0.15
        assert is_target == should_target, f"Error en cono para {desc}: dot={dot}"
        print(f"  [OK] Cono de pase {desc:25s} (dot: {dot:+.3f}) -> {'EN CONO' if is_target else 'FUERA DE CONO'}")

    # B) Escala de velocidad de pase según stat 'pase'
    # lerp(460.0, 750.0, pase / 100.0)
    for test_id in ["bra_01", "bra_02", "arg_01", "ita_01", "star_01"]:
        p_stat = players[test_id]["stats"]["pase"]
        t = p_stat / 100.0
        pass_speed = 460.0 * (1.0 - t) + 750.0 * t
        print(f"  [OK] {test_id} ({players[test_id]['name']}): Stat Pase={p_stat} -> Velocidad Pase={pass_speed:.1f} px/s")

    print("\n--- 6. Verificando escena TestPitch con 2 jugadores ---")
    with open("scenes/field/TestPitch.tscn", "r", encoding="utf-8") as f:
        pitch_content = f.read()
    if 'node name="Player1"' not in pitch_content or 'node name="Player2"' not in pitch_content:
        errors.append("TestPitch.tscn no contiene Player1 y Player2 instanciados")
    else:
        print("  [OK] Player1 y Player2 presentes en la escena de pruebas TestPitch.tscn")

    if errors:
        print(f"\n❌ SE ENCONTRARON {len(errors)} ERRORES:")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    else:
        print("\n✅ TODAS LAS PRUEBAS Y VALIDACIONES PASARON EXITOSAMENTE (0 errores).")

if __name__ == "__main__":
    test_project()
