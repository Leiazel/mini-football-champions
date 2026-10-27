#!/usr/bin/env python3
"""
Pipeline de procesamiento de sprites para Mini Football: Torneos (v2).
Detecta bandas y sprites (dividiendo automáticamente sprites que se tocan),
alinea cada frame horizontalmente por el centro del torso/cabeza y verticalmente por la base de los pies,
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

EXPECTED_BAND_COUNTS = {
    0: 2,
    1: 9,
    2: 7,
    3: 9,
    4: 9,
    5: 9,
    6: 9,
    7: 10,
    8: 10,
}

# Esquema real verificado contra los sheets:
# Banda 1: frente (4 idle + 5 run)
# Banda 2: espalda (2 idle + 5 run)
# Banda 3: perfil izquierdo (4 walk + 5 run)
# Banda 4: perfil derecho (4 walk + 5 run)
# Banda 5: diagonal abajo-izquierda (4 walk + 5 run)
# Banda 6: diagonal abajo-derecha (4 walk + 5 run)
# Banda 8 (o 7): 0..1 espalda-diagonal, 2..5 pateo limpio, 5..9 correr diagonal arriba-derecha
ANIMATION_SCHEMA = [
    # (band_idx, start_col, count, anim_name, fps, loop, facing)
    (1, 0, 4, "idle_down", 6, True, "down"),
    (1, 4, 5, "run_down", 10, True, "down"),
    (2, 0, 2, "idle_up", 5, True, "up"),
    (2, 2, 5, "run_up", 10, True, "up"),
    (4, 0, 4, "walk_side", 8, True, "right"),
    (4, 4, 5, "run_side", 11, True, "right"),
    (3, 0, 4, "walk_left", 8, True, "left"),
    (3, 4, 5, "run_left", 11, True, "left"),
    (6, 0, 4, "walk_down_side", 8, True, "down_right"),
    (6, 4, 5, "run_down_side", 10, True, "down_right"),
    (5, 0, 4, "walk_down_left", 8, True, "down_left"),
    (5, 4, 5, "run_down_left", 10, True, "down_left"),
    (8, 5, 5, "walk_up_side", 8, True, "up_right"),
    (8, 5, 5, "run_up_side", 10, True, "up_right"),
    (8, 2, 4, "kick", 12, False, "action"),
]


def _split_wide_segments(segments, col_counts, expected_count):
    """Divide segmentos horizontales fusionados (por pelo o manos que se tocan) buscando el valle de menor opacidad."""
    segments = list(segments)
    while len(segments) < expected_count:
        # Buscar el segmento más ancho
        widest_idx = max(range(len(segments)), key=lambda i: segments[i][1] - segments[i][0])
        x1, x2 = segments[widest_idx]
        width = x2 - x1
        if width < 85:
            break

        # Determinar en cuántas partes debería dividirse este segmento según su ancho (~72px por sprite)
        n_parts = max(2, int(round(width / 70.0)))
        target_x = x1 + width // n_parts
        search_min = max(x1 + 28, target_x - 22)
        search_max = min(x2 - 28, target_x + 22)
        if search_min >= search_max:
            split_x = target_x
        else:
            split_x = min(range(search_min, search_max + 1), key=lambda x: col_counts[x])

        segments[widest_idx:widest_idx + 1] = [(x1, split_x), (split_x + 1, x2)]

    # Si hay segmentos de ruido diminutos de más, filtrar los menores
    if len(segments) > expected_count and expected_count > 2:
        segments.sort(key=lambda seg: seg[1] - seg[0], reverse=True)
        segments = sorted(segments[:expected_count], key=lambda seg: seg[0])

    return segments


def detect_bands_and_sprites(img_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    alpha = img.getchannel("A").load()

    # Detección de bandas horizontales
    row_counts = [sum(1 for x in range(w) if alpha[x, y] > 15) for y in range(h)]
    bands = []
    in_band = False
    start = 0
    for y, val in enumerate(row_counts):
        if val > 10 and not in_band:
            in_band = True
            start = y
        elif val <= 10 and in_band:
            in_band = False
            if y - start > 18:
                bands.append((start, y))
    if in_band and h - start > 18:
        bands.append((start, h))

    detected_bands = []
    for b_idx, (y1, y2) in enumerate(bands):
        col_counts = [sum(1 for y in range(y1, y2) if alpha[x, y] > 15) for x in range(w)]
        sprites = []
        in_col = False
        cstart = 0
        for x, cval in enumerate(col_counts):
            if cval > 4 and not in_col:
                in_col = True
                cstart = x
            elif cval <= 4 and in_col:
                in_col = False
                if x - cstart > 10:
                    sprites.append((cstart, x))
        if in_col and w - cstart > 10:
            sprites.append((cstart, w))

        expected = EXPECTED_BAND_COUNTS.get(b_idx, 0)
        if expected > 0 and len(sprites) != expected:
            sprites = _split_wide_segments(sprites, col_counts, expected)

        sprite_boxes = []
        for (x1, x2) in sprites:
            ys = [y for y in range(y1, y2) for x in range(x1, x2) if alpha[x, y] > 15]
            if not ys:
                continue
            sp_y1 = min(ys)
            sp_y2 = max(ys) + 1

            # Recortar también x1..x2 reales dentro del segmento
            xs_all = [x for y in range(sp_y1, sp_y2) for x in range(x1, x2) if alpha[x, y] > 15]
            if xs_all:
                x1 = min(xs_all)
                x2 = max(xs_all) + 1

            # Centro horizontal por el eje espinal (cabeza + torso superior, 70% superior del sprite)
            # Esto evita que un pie extendido al correr desplace todo el cuerpo 25px al costado.
            torso_y2 = sp_y1 + max(1, int((sp_y2 - sp_y1) * 0.72))
            torso_xs = [x for y in range(sp_y1, torso_y2) for x in range(x1, x2) if alpha[x, y] > 25]
            if torso_xs:
                spine_cx = sum(torso_xs) / len(torso_xs)
            else:
                spine_cx = (x1 + x2) / 2.0

            sprite_boxes.append({
                "x1": x1, "y1": sp_y1, "x2": x2, "y2": sp_y2,
                "feet_cx": spine_cx, "feet_cy": sp_y2
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

    if len(bands) < 7:
        raise ValueError(f"El sheet {input_sheet_path} solo tiene {len(bands)} bandas (se esperaban al menos 7)")

    # 1. Extraer Retrato e Ícono si existen en la banda 0
    if len(bands[0]["sprites"]) >= 1:
        p_box = bands[0]["sprites"][0]
        portrait = img.crop((p_box["x1"], p_box["y1"], p_box["x2"], p_box["y2"]))
        portrait.save(os.path.join(output_sprites_dir, f"{player_id}_portrait.png"))

    if len(bands[0]["sprites"]) >= 2:
        i_box = bands[0]["sprites"][1]
        icon = img.crop((i_box["x1"], i_box["y1"], i_box["x2"], i_box["y2"]))
        icon.save(os.path.join(output_sprites_dir, f"{player_id}_icon.png"))
    elif len(bands[0]["sprites"]) == 1:
        p_box = bands[0]["sprites"][0]
        icon = img.crop((p_box["x1"], p_box["y1"], p_box["x2"], p_box["y2"])).resize((52, 58), Image.Resampling.NEAREST)
        icon.save(os.path.join(output_sprites_dir, f"{player_id}_icon.png"))

    # 2. Recolectar todos los frames de las animaciones
    total_frames = sum(item[2] for item in ANIMATION_SCHEMA)
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
        actual_band_idx = band_idx
        if actual_band_idx >= len(bands):
            actual_band_idx = len(bands) - 1

        band = bands[actual_band_idx]
        available_sprites = band["sprites"]
        if not available_sprites:
            continue

        anim_frames = []

        for c in range(count):
            sprite_idx = min(start_col + c, len(available_sprites) - 1)
            sp = available_sprites[sprite_idx]
            crop_box = (sp["x1"], sp["y1"], sp["x2"], sp["y2"])
            sprite_crop = img.crop(crop_box)
            crop_w, crop_h = sprite_crop.size

            cell = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))

            offset_in_crop_x = sp["feet_cx"] - sp["x1"]
            offset_in_crop_y = sp["y2"] - sp["y1"]

            paste_x = int(round(PIVOT_X - offset_in_crop_x))
            paste_y = int(round(PIVOT_Y - offset_in_crop_y))

            # Garantizar que jamás se recorte ningún borde del sprite dentro de la celda 128x128
            if crop_w < CANVAS_W - 4:
                paste_x = max(2, min(CANVAS_W - crop_w - 2, paste_x))
            else:
                paste_x = max(0, (CANVAS_W - crop_w) // 2)

            if crop_h < CANVAS_H - 4:
                paste_y = max(2, min(CANVAS_H - crop_h - 2, paste_y))
            else:
                paste_y = max(0, CANVAS_H - crop_h)

            cell.paste(sprite_crop, (paste_x, paste_y), sprite_crop)

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

    aligned_path = os.path.join(output_sprites_dir, f"{player_id}_aligned.png")
    aligned_sheet.save(aligned_path)

    json_path = os.path.join(output_anims_dir, f"{player_id}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(anims_data, f, indent=2)

    return anims_data


if __name__ == "__main__":
    all_pids = [
        "arg_01", "arg_02", "arg_03", "arg_04",
        "bra_01", "bra_02", "bra_03", "bra_04",
        "ita_01", "ita_02", "ita_03",
        "star_01", "star_02", "star_03", "star_04",
        "vet_01", "vet_02", "vet_03",
        "leg_01", "leg_02",
        "gk_arg", "gk_bra", "gk_ita", "gk_star", "gk_vet", "gk_leg"
    ]
    if len(sys.argv) > 1:
        all_pids = sys.argv[1:]

    for pid in all_pids:
        sheet_path = os.path.join("assets/sprites", f"{pid}.png")
        if not os.path.exists(sheet_path):
            print(f"No existe: {sheet_path}")
            continue
        res = process_player(pid, sheet_path, "assets/sprites", "data/anims")
        total_anim_frames = sum(len(a["frames"]) for a in res["animations"].values())
        print(f"-> {pid}: {len(res['animations'])} animaciones, {total_anim_frames} frames alineados.")
