# Mini Football: Torneos (v2). Contexto del proyecto

> Aviso: la sección 6 contiene nombres reales de jugadores solo como referencia de trabajo.
> No subir esa sección a un repo público. Moverla a `docs/INTERNO_no_subir.md` y agregarla al `.gitignore`.

## 1. Qué es
Juego de fútbol 2D de vista cenital/oblicua hecho en **Godot 4.x** (detectar la versión instalada).
Proyecto de portfolio. Es una **v2** independiente de `Mini-Football` (v1), que queda intacto.

Modo principal: **torneo**. El jugador arma su equipo y enfrenta rivales de dificultad creciente.
El jefe final es el equipo de leyendas de Argentina.

## 2. Diferencia clave con la v1
| | v1 (estilo Haxball) | v2 (esta) |
|---|---|---|
| Pelota | Objeto de física que se choca | Se posee y se conduce |
| Control | Empujar la pelota | Llevarla pegada al jugador |
| Pase | No existe | Pase dirigido con una tecla |
| Habilidad | Casi no influye | Los stats cambian el manejo |
| Referencia | Haxball | Inazuma Eleven (sin habilidades especiales al inicio) |

## 3. Mecánica central: pelota como máquina de estados
Estados de la pelota:
1. **LIBRE**: rueda y se frena sola. Cualquier jugador dentro del radio de recogida puede tomarla.
2. **CONTROLADA**: queda pegada al poseedor, un poco adelante según hacia dónde mira. Cuanto mayor el stat de control, más pegada va y menos se le puede robar.
3. **EN_VUELO**: tras un pase o tiro recibe un impulso. Quien la pateó no puede recogerla durante un instante corto.

Robo: al tocar al poseedor, con probabilidad según defensa del que roba contra control del poseedor.

Controles propuestos (editables):
- Flechas: mover
- X o Espacio: pase (toque corto) / tiro (mantener para cargar potencia)
- Z: cambiar de jugador controlado
- Shift: sprint (gasta resistencia)

## 4. Stats (escala 1 a 100)
`velocidad`, `control`, `pase`, `tiro`, `defensa`. Arqueros: `reflejos` en lugar de tiro y pase.
Referencia de rangos: leyendas 85-95, estrellas mixtas 65-80, jugadores ficticios 40-65.

## 5. Sprites
Ubicación: `assets/sprites/` (copiados desde `sprites/transparente/`).
- Todos los sheets tienen el mismo layout, 768x1376 px, PNG con transparencia real.
- Contenido aproximado (inferido de capturas, **verificar abriendo un sheet**): retrato grande y cabeza pequeña arriba; filas de frente, de espaldas (con número), laterales caminando y corriendo, y filas finales de patear con pelota.
- Hay que detectar los recortes de cada frame (cajas delimitadoras por componentes conectados) y exportar un JSON por sheet o uno global.
- **Alinear cada frame por el centro de los pies** para evitar temblor entre cuadros.
- Diseño guiado por datos: una tabla de animaciones (`idle_*`, `caminar_*`, `correr_*`, `patear`) con fila, frames y fps. Sumar un jugador debe ser solo agregar su PNG.
- Si las vistas laterales vienen solo hacia un lado, usar `flip_h` para el otro.
- No hay animaciones de arquero (atajada, lanzarse): se simulan por ahora con rotación y escala, o se generan después.
- El script `procesar_lote.py` (fondo magenta con chroma key a transparencia) se conserva como herramienta del pipeline.

## 6. Roster actual y equipos (referencia interna)
> Esta sección contiene nombres de referencia y fue trasladada a `docs/INTERNO_no_subir.md` (ignorado en Git).
> Consultar dicho archivo para la tabla de equivalencias de desarrollo y el mapeo hacia los IDs públicos (`arg_01`, `bra_01`, etc.).

## 7. Nombres y derechos de imagen
- En el juego y en el repo público usar **nombres e IDs de ficción**, no nombres reales (ej. `ARG_01`, "El Diez").
- Los archivos públicos deben renombrarse a IDs (`arg_01.png`). La tabla de equivalencias va solo en el archivo interno ignorado por Git.
- Sin escudos ni camisetas oficiales de clubes o selecciones.
- Rasgos exagerados o modificados para que sean arquetipos y no retratos.

## 8. Hitos (en este orden)
1. Un jugador que recibe la pelota y corre con ella (estados LIBRE/CONTROLADA).
2. Pase entre dos jugadores.
3. Tiro al arco con un arquero simple.
4. Rival con IA básica (3v3).
5. Carga de equipos desde datos (JSON) y modo torneo.
6. Cartas, rareza y progreso guardado (después).

## 9. Fuera de alcance por ahora
Menús y UX elaborados, habilidades especiales estilo Inazuma, multijugador en línea, sonido.
