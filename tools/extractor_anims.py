#!/usr/bin/env python3
"""
Pipeline de procesamiento de sprites para Mini Football: Torneos (v2).
Detecta bandas y sprites, alinea cada frame por el centro de los pies (pivot x=64, y=118 en lienzo 128x128),
y genera:
1. data/anims/<id>.json con metadata de animaciones, frames y configuraciones.
2. assets/sprites/<id>_aligned.png con el sheet alineado en cuadrícula fija de 128x128.
3. assets/sprites/<id>_portrait.png e icono correspondiente.
"""

import os
import sys
import json
from PIL import Image

CANVAS_W = 128
CANVAS_H = 128
PIVOT_X = 64
PIVOT_Y = 118

ANIMATION_SCHEMA = [
    # (band_idx, start_col, count, anim_name, fps, loop, facing)
    (1, 0, 4, "idle_down", 6, True, "down"),
    (1, 4, 5, "run_down", 10, True, "down"),
    (2, 0, 2, "idle_up", 4, True, "up"),
    (2, 2, 5, "run_up", 10, True, "up"),
    (3, 0, 4, "walk_side", 8, True, "right"),
    (3, 4, 5, "run_side", 10, True, "right"),
    (4, 0, 4, "walk_down_side", 8, True, "down_right"),
    (4, 4, 5, "run_down_side", 10, True, "down_right"),
    (5, 0, 4, "walk_up_side", 8, True, "up_right"),
    (5, 4, 5, "run_up_side", 10, True, "up_right"),
    (7, 0, 10, "kick", 12, False, "action"),
]


def detect_bands_and_sprites(img_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    alpha = img.getchannel("A").load()

    # Detección de bandas horizontales
    row_counts = [sum(1 for x in range(w) if alpha[x, y] > 10) for y in range(h)]
    bands = []
    in_band = False
    start = 0
    for y, val in enumerate(row_counts):
        if val > 10 and not in_band:
            in_band = True
            start = y
        elif val <= 10 and in_band:
            in_band = False
            if y - start > 15:
                bands.append((start, y))
    if in_band:
        bands.append((start, h))

    detected_bands = []
    for b_idx, (y1, y2) in enumerate(bands):
        col_counts = [sum(1 for y in range(y1, y2) if alpha[x, y] > 10) for x in range(w)]
        sprites = []
        in_col = False
        cstart = 0
        for x, cval in enumerate(col_counts):
            if cval > 5 and not in_col:
                in_col = True
                cstart = x
            elif cval <= 5 and in_col:
                in_col = False
                if x - cstart > 8:
                    sprites.append((cstart, x))
        if in_col:
            sprites.append((cstart, w))

        sprite_boxes = []
        ground_y = y2
        for (x1, x2) in sprites:
            ys = [y for y in range(y1, y2) for x in range(x1, x2) if alpha[x, y] > 10]
            if not ys:
                continue
            sp_y1 = min(ys)
            sp_y2 = max(ys) + 1
            # Centro de los pies: promedio ponderado de los píxeles de la base
            bottom_y = sp_y2 - 1
            base_xs = [x for x in range(x1, x2) if alpha[x, bottom_y] > 10 or (bottom_y > y1 and alpha[x, bottom_y - 1] > 10)]
            feet_cx = sum(base_xs) / len(base_xs) if base_xs else (x1 + x2) / 2.0
            sprite_boxes.append({
                "x1": x1, "y1": sp_y1, "x2": x2, "y2": sp_y2,
                "feet_cx": feet_cx, "feet_cy": sp_y2
            })
        detected_bands.append({
            "y1": y1, "y2": y2,
            "sprites": sprite_boxes
        })

    return img, detected_bands


def process_player(player_id, input_sheet_path, output_sprites_dir, output_anims_dir):
    os.makedirs(output_sprites_dir, exist_ok=True)
    os.makedirs(output_anims_dir, exist_ok=True)

    img, bands = detect_bands_and_sprites(input_sheet_path)

    if len(bands) < 8:
        raise ValueError(f"El sheet {input_sheet_path} solo tiene {len(bands)} bandas (se esperaban al menos 8)")

    # 1. Extraer Retrato e Ícono si existen en la banda 0
    if len(bands[0]["sprites"]) >= 2:
        p_box = bands[0]["sprites"][0]
        portrait = img.crop((p_box["x1"], p_box["y1"], p_box["x2"], p_box["y2"]))
        portrait.save(os.path.join(output_sprites_dir, f"{player_id}_portrait.png"))

        i_box = bands[0]["sprites"][1]
        icon = img.crop((i_box["x1"], i_box["y1"], i_box["x2"], i_box["y2"]))
        icon.save(os.path.join(output_sprites_dir, f"{player_id}_icon.png"))

    # 2. Recolectar todos los frames de las animaciones
    total_frames = sum(item[2] for item in ANIMATION_SCHEMA)
    # Crear un sheet alineado en una cuadrícula (por ejemplo columnas = 10)
    grid_cols = 10
    grid_rows = (total_frames + grid_cols - 1) // grid_cols
    aligned_sheet = Image.new("RGBA", (grid_cols * CANVAS_W, grid_rows * CANVAS_H), (0, 0, 0, 0))

    anims_data = {
        "player_id": player_id,
        "canvas_size": {"width": CANVAS_W, "height": CANVAS_H},
        "pivot": {"x": PIVOT_X, "y": PIVOT_Y},
        "aligned_sheet": f"res://assets/sprites/{player_id}_aligned.png",
        "animations": {}
    }

    current_frame_idx = 0

    for (band_idx, start_col, count, anim_name, fps, loop, facing) in ANIMATION_SCHEMA:
        if band_idx >= len(bands):
            continue
        band = bands[band_idx]
        available_sprites = band["sprites"]
        
        # Ground baseline para la banda completa (suaviza saltos)
        band_ground_y = max((sp["y2"] for sp in available_sprites), default=band["y2"])

        anim_frames = []

        for c in range(count):
            sprite_idx = start_col + c
            if sprite_idx < len(available_sprites):
                sp = available_sprites[sprite_idx]
                crop_box = (sp["x1"], sp["y1"], sp["x2"], sp["y2"])
                sprite_crop = img.crop(crop_box)

                # Crear lienzo estándar de 128x128
                cell = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))

                # Alineación: los pies van exactamente en (PIVOT_X, PIVOT_Y)
                # sp["feet_cx"] en relación con sp["x1"]
                offset_in_crop_x = sp["feet_cx"] - sp["x1"]
                # En vertical usamos el pie real o la base de la banda para mantener consistencia
                offset_in_crop_y = sp["y2"] - sp["y1"]

                paste_x = int(round(PIVOT_X - offset_in_crop_x))
                paste_y = int(round(PIVOT_Y - offset_in_crop_y))

                cell.paste(sprite_crop, (paste_x, paste_y), sprite_crop)

                # Pegar en la cuadrícula del sheet alineado
                col = current_frame_idx % grid_cols
                row = current_frame_idx // grid_cols
                aligned_sheet.paste(cell, (col * CANVAS_W, row * CANVAS_H))

                anim_frames.append({
                    "frame_index": current_frame_idx,
                    "grid_pos": {"col": col, "row": row},
                    "rect": {
                        "x": col * CANVAS_W,
                        "y": row * CANVAS_H,
                        "w": CANVAS_W,
                        "h": CANVAS_H
                    }
                })
                current_frame_idx += 1

        anims_data["animations"][anim_name] = {
            "fps": fps,
            "loop": loop,
            "facing": facing,
            "frames": anim_frames
        }

    # Guardar sheet alineado
    aligned_path = os.path.join(output_sprites_dir, f"{player_id}_aligned.png")
    aligned_sheet.save(aligned_path)

    # Guardar JSON de metadata
    json_path = os.path.join(output_anims_dir, f"{player_id}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(anims_data, f, indent=2)

    return anims_data


if __name__ == "__main__":
    test_players = ["bra_01", "arg_01", "star_01"]
    if len(sys.argv) > 1:
        test_players = sys.argv[1:]

    for pid in test_players:
        sheet_path = os.path.join("assets/sprites", f"{pid}.png")
        if not os.path.exists(sheet_path):
            print(f"No existe: {sheet_path}")
            continue
        print(f"Procesando {pid}...")
        res = process_player(pid, sheet_path, "assets/sprites", "data/anims")
        total_anim_frames = sum(len(a["frames"]) for a in res["animations"].values())
        print(f"-> {pid}: {len(res['animations'])} animaciones, {total_anim_frames} frames alineados en 128x128.")
