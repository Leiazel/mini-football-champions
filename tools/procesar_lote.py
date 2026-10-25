import os
import sys
from PIL import Image

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CRUDO = os.path.join(BASE_DIR, "crudo")
SALIDA = os.path.join(BASE_DIR, "transparente")
TOLERANCIA = 90      # subí si queda fondo, bajá si se come el personaje
LIMPIAR_HALO = True  # recomendado: elimina los píxeles claros del borde
FONDO = (255, 0, 255)  # cambialo a (0, 255, 0) si usaste fondo verde

os.makedirs(SALIDA, exist_ok=True)

def procesar(ruta, destino):
    try:
        import numpy as np
        from scipy import ndimage

        a = np.array(Image.open(ruta).convert("RGB")).astype(int)
        fr, fg, fb = FONDO

        dist = np.sqrt((a[..., 0] - fr) ** 2 + (a[..., 1] - fg) ** 2 + (a[..., 2] - fb) ** 2)
        fondo = dist < TOLERANCIA

        # Rosados residuales del JPEG (solo para fondo magenta)
        if FONDO == (255, 0, 255):
            r, g, b = a[..., 0], a[..., 1], a[..., 2]
            fondo |= (r > 150) & (b > 150) & (g < 120)

        # Limpiar halo: quitar píxeles claros o violáceos de borde pegados al fondo
        if LIMPIAR_HALO:
            borde = ndimage.binary_dilation(fondo, iterations=2) & ~fondo
            claros = a.sum(axis=2) > 600       # casi blancos
            rosados = (a[..., 0] > 80) & (a[..., 2] > 80) & ((a[..., 0] + a[..., 2]) > 2.2 * (a[..., 1] + 1))
            fondo |= borde & (claros | rosados)
            # Descontaminar contorno oscuro mezclado con magenta a marrón oscuro natural (50, 30, 20)
            borde_contorno = ndimage.binary_dilation(fondo, iterations=1) & ~fondo
            mezcla_oscura = borde_contorno & (a[..., 0] > 45) & (a[..., 2] > 40) & ((a[..., 0] + a[..., 2]) > 2.1 * (a[..., 1] + 1))
            a[mezcla_oscura] = [50, 30, 20]

        # Quitar motas de fondo aisladas dentro del personaje
        alpha = np.where(fondo, 0, 255).astype(np.uint8)
        rgba = np.dstack([a.astype(np.uint8), alpha])
        Image.fromarray(rgba, "RGBA").save(destino)
    except ImportError:
        img = Image.open(ruta).convert("RGB")
        w, h = img.size
        rgb = img.tobytes()
        fr, fg, fb = FONDO
        tol_sq = TOLERANCIA ** 2
        is_magenta_bg = (FONDO == (255, 0, 255))

        fondo = bytearray(w * h)
        for i in range(w * h):
            r = rgb[i * 3]
            g = rgb[i * 3 + 1]
            b = rgb[i * 3 + 2]
            dist_sq = (r - fr) ** 2 + (g - fg) ** 2 + (b - fb) ** 2
            if dist_sq < tol_sq or (is_magenta_bg and r > 150 and b > 150 and g < 120):
                fondo[i] = 1

        rgb_out = bytearray(rgb)
        if LIMPIAR_HALO:
            for _ in range(2):
                fondo_Snapshot = bytes(fondo)
                for y in range(h):
                    row = y * w
                    for x in range(w):
                        idx = row + x
                        if not fondo_Snapshot[idx]:
                            r = rgb_out[idx * 3]
                            g = rgb_out[idx * 3 + 1]
                            b = rgb_out[idx * 3 + 2]
                            is_claro = (r + g + b > 600)
                            is_rosado = (r > 80 and b > 80 and (r + b) > 2.2 * (g + 1))
                            if is_claro or is_rosado:
                                if (
                                    (x > 0 and fondo_Snapshot[idx - 1])
                                    or (x + 1 < w and fondo_Snapshot[idx + 1])
                                    or (y > 0 and fondo_Snapshot[idx - w])
                                    or (y + 1 < h and fondo_Snapshot[idx + w])
                                ):
                                    fondo[idx] = 1
            # Descontaminar contorno oscuro mezclado con magenta a marrón oscuro natural (50, 30, 20)
            for y in range(h):
                row = y * w
                for x in range(w):
                    idx = row + x
                    if not fondo[idx]:
                        r = rgb_out[idx * 3]
                        g = rgb_out[idx * 3 + 1]
                        b = rgb_out[idx * 3 + 2]
                        if r > 45 and b > 40 and (r + b) > 2.1 * (g + 1):
                            if (
                                (x > 0 and fondo[idx - 1])
                                or (x + 1 < w and fondo[idx + 1])
                                or (y > 0 and fondo[idx - w])
                                or (y + 1 < h and fondo[idx + w])
                            ):
                                rgb_out[idx * 3] = 50
                                rgb_out[idx * 3 + 1] = 30
                                rgb_out[idx * 3 + 2] = 20

        rgba = bytearray(w * h * 4)
        for i in range(w * h):
            if fondo[i]:
                rgba[i * 4] = 0
                rgba[i * 4 + 1] = 0
                rgba[i * 4 + 2] = 0
                rgba[i * 4 + 3] = 0
            else:
                rgba[i * 4] = rgb_out[i * 3]
                rgba[i * 4 + 1] = rgb_out[i * 3 + 1]
                rgba[i * 4 + 2] = rgb_out[i * 3 + 2]
                rgba[i * 4 + 3] = 255

        Image.frombytes("RGBA", (w, h), bytes(rgba)).save(destino)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        ruta_in = sys.argv[1]
        if not os.path.exists(ruta_in) and os.path.exists(os.path.join(BASE_DIR, ruta_in)):
            ruta_in = os.path.join(BASE_DIR, ruta_in)
        if len(sys.argv) > 2:
            ruta_out = sys.argv[2]
        else:
            base = os.path.splitext(os.path.basename(ruta_in))[0]
            ruta_out = os.path.join(SALIDA, base + ".png")
        os.makedirs(os.path.dirname(os.path.abspath(ruta_out)), exist_ok=True)
        procesar(ruta_in, ruta_out)
        print("OK:", os.path.splitext(os.path.basename(ruta_in))[0])
    else:
        for nombre in sorted(os.listdir(CRUDO)):
            if nombre.lower().endswith((".jpg", ".jpeg", ".png")):
                base = os.path.splitext(nombre)[0]
                procesar(os.path.join(CRUDO, nombre), os.path.join(SALIDA, base + ".png"))
                print("OK:", base)
