
Estoy empezando **Mini Football: Torneos (v2)**, un juego 2D de fútbol en **Godot 4** para mi portfolio. Es un proyecto nuevo e independiente de mi juego anterior. Leé primero `CONTEXTO.md` en la raíz: ahí está la visión, la mecánica, los sprites y los hitos.

**Tu primera tarea es solo el Hito 1 y la preparación de sprites. No hagas menús, torneo, cartas ni IA todavía.**

1. **Estructura del proyecto**
   - Creá una estructura limpia de carpetas (`assets/sprites`, `scenes`, `scripts`, `data`, `tools`, `docs`).
   - Copiá `procesar_lote.py` a `tools/` y los PNG de `sprites/transparente/` a `assets/sprites/`.
   - Creá un `.gitignore` que incluya `docs/INTERNO_no_subir.md` y mové ahí la sección 6 de `CONTEXTO.md`.

2. **Pipeline de sprites**
   - Abrí un sheet (por ejemplo el de Ronaldinho) y verificá su layout real: dimensiones, filas, cuántos frames tiene cada animación y hacia dónde mira cada fila.
   - Escribí un script en Python en `tools/` que detecte los recortes de cada frame, alinee cada frame por el centro de los pies y exporte un JSON de animaciones (`idle`, `caminar`, `correr`, `patear`, por dirección).
   - Probalo con 3 sheets distintos y mostrame si los frames salen consistentes.

3. **Hito 1 en Godot**
   - Un jugador controlable con flechas que usa las animaciones del JSON (con `flip_h` donde corresponda).
   - Una pelota con tres estados: LIBRE, CONTROLADA y EN_VUELO. Por ahora implementá LIBRE y CONTROLADA.
   - Cuando el jugador se acerca a la pelota, la toma y la lleva pegada, un poco adelante según su dirección.
   - Un stat `control` que cambie qué tan pegada va la pelota.
   - Un campo simple de prueba, sin arcos ni reglas.

**Reglas de trabajo**
- Todo guiado por datos: sumar un jugador nuevo debe ser agregar su PNG y una entrada en un JSON.
- Usá nombres e IDs de ficción en el código y los datos (`arg_01`, etc.), nunca nombres reales.
- Si algo del contexto no coincide con lo que ves en los sheets, avisame antes de decidir.
- Antes de empezar a escribir código, mostrame un plan corto de lo que vas a hacer.
- Al terminar, resumime qué quedó hecho y qué falta para el Hito 2.
