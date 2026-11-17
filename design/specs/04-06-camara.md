# 04 · Cámara / 05 · Captura procesando / 06 · Cámara página 2

PNG: `screens/04-camara.png`, `05-procesando-captura.png`, `06-camara-pagina-2.png`
Capas: `layers/04-camara.json`, `05-…`, `06-…`
Código: **nuevo** `lib/ui_camera.dart` (`CameraScanScreen`). Sustituye a `ImagePicker(source: camera)` en `scan_flow.dart`.

Es la funcionalidad clave del rediseño: **una cámara propia, no la del sistema**, que va acumulando páginas hasta que el usuario pulsa «Siguiente».

## Dependencias
- `camera: ^0.11.x` para la vista previa en vivo y `takePicture()`. Permisos: los de cámara ya están para `image_picker` en `ios/Runner/Info.plist` (`NSCameraUsageDescription`) y en Android.
- La detección en vivo usa `detectCornersAsync` de `ui_edit.dart`, aplicada sobre un fotograma reducido cada ~300 ms con `startImageStream` o con fotos de baja resolución. Mientras no haya detección en vivo, el cuadrilátero puede omitirse sin bloquear el flujo.
- El procesado de cada página usa `store.renderPage` / `processing.dart` en un isolate (`compute`), igual que ahora.

## Estado
```dart
enum CaptureMode { single, multi }        // UNA PÁGINA / VARIAS PÁGINAS (por defecto multi)
bool auto = settings.autoCapture;         // Auto / Manual (nuevo ajuste, por defecto true)
bool flash = false;
final List<CapturedPage> pages = [];      // foto + corners + miniatura procesada
CapturedPage? processing;                 // página en animación de pre-procesado
```

## Capa base (las tres pantallas)
- Vista previa de cámara a pantalla completa (`CameraPreview`, recorte *cover*), fondo `#000`.
- Sombra superior de 0,0 · 393×150: degradado negro 50% → 0%.
- Panel inferior de 0,618 · 393×234: degradado negro 0% → 85% (al 28%) → 100%.
- Barra de estado clara (iconos blancos).

## Barra superior
| Elemento | Posición | Detalle |
|---|---|---|
| Cerrar | 16,60 · 40 | `GlassIconButton` oscuro (blanco 18%, borde 20%, desenfoque 16), `xmark` blanco. Con páginas capturadas pide confirmar (ver flows.md). |
| Auto / Manual | 122,62 · 150×36 | Segmentado de vidrio con radio 18. El segmento activo es blanco (70×28, radio 15) con texto 14/600 `accentDark`; el inactivo lleva texto 14/600 blanco. En **Auto**, dispara solo cuando la hoja lleva ~1 s estable. |
| Flash | 337,60 · 40 | `GlassIconButton` oscuro, `bolt_fill` / `bolt_slash_fill`. |

## Detección (04, 06)
- Cuadrilátero sobre la hoja detectada: relleno `#00B4D8` al 14% y trazo `#48CAE4` de 2,5. Esquinas: círculos blancos de 14. Transición suave de 120 ms entre detecciones.
- `CameraHint` centrado en y=128 (alto 35): punto `#48CAE4` y texto 14/600 blanco.
  - Hoja detectada en Auto: «Hoja detectada · capturando…»
  - Desde la página 2: «Página N · hoja detectada»
  - Sin hoja: «Buscando el documento…» (punto gris).
  - En Manual: «Hoja detectada» (sin "capturando").

## Panel inferior
- Texto de ayuda en y=646, centrado, 12/400 blanco al 60%:
  - 0 páginas: «Haz una foto por página. Pulsa Siguiente al terminar.»
  - Justo tras capturar: «Página N añadida. Coloca la siguiente hoja.»
  - N ≥ 2 en reposo: «N páginas listas. Pulsa Siguiente cuando termines.»
- Modo en y=678: «UNA PÁGINA» 13/600 blanco 55% y «VARIAS PÁGINAS» 13/700 `#48CAE4` (el activo va en acento). Se cambia tocando o deslizando horizontalmente, como en la cámara de iOS.
- **Obturador** centrado en y=760: anillo de 80 con trazo blanco de 4 y disco blanco de 64. Al pulsar, el disco escala a 0,9 (100 ms) y vibra (`HapticFeedback.mediumImpact`).
- **Izquierda (x=36, y=734, 52×52):**
  - Sin páginas: botón Importar (blanco 14%, borde 18%, radio 26, icono galería).
  - Con páginas: **pila de miniaturas** (06: dos miniaturas de 44×62 con radio 6, desplazadas 4 px) más `PageCounterBadge` (22, `accent`, número 12/700) arriba a la derecha. Al tocar la pila se va a 07 con la última página seleccionada.
- **Siguiente (derecha, x final 373, y=740, alto 40, radio 20):**
  - Desactivado (04): blanco 12% con texto 15/600 blanco 35%.
  - Activo con 1 página (05): `accent` con «Siguiente» 15/600 blanco.
  - Activo con N ≥ 2 (06): «Siguiente · N». El ancho se ajusta al contenido (112 en el mock).

## 05 · Animación de pre-procesado (tras cada disparo)
Dura ~1,2–1,6 s y **no bloquea**: la cámara sigue activa por detrás y se puede volver a disparar.
1. **Destello y vuelo** (250 ms, `Curves.easeOutCubic`): la foto recortada a la hoja detectada (perspectiva ya corregida) aparece centrada en 78,118 · 236×334, con radio 3,6 y sombra negra 50% y=16 blur=36.
2. **Barrido** (900 ms, lineal): una línea `#48CAE4` de 3 px con halo (blur 9) baja de arriba abajo. Por encima de la línea se ve la imagen **ya procesada** (filtro por defecto, normalmente Mejorar) y por debajo, la foto original. Detrás de la línea va una estela en degradado `#48CAE4` 0% → 40% de 42 de alto. Se hace con `ClipRect` animando la altura de la zona mejorada.
3. **HUD** `GlassHud` en 66,470 · 260×136:
   - «Mejorando imagen…» 15/700 blanco.
   - Tres pasos 13/400 blanco 80%, con ✓ `#48CAE4` a medida que terminan: «Bordes detectados», «Perspectiva enderezada» y «Limpiando sombras y texto». El paso en curso va en 13/600 blanco con un spinner pequeño.
   - Barra de progreso de 226×4 (fondo blanco 15%, relleno `#48CAE4`, radio 2).
4. **Caída a la pila** (300 ms): la página encoge hacia la pila de abajo a la izquierda, el contador sube con un rebote leve (`Curves.elasticOut`, escala 1→1,25→1) y vibra con `HapticFeedback.lightImpact`.

Los pasos del HUD son reales: corresponden a `detectCorners`, `warpPerspective` y `applyFilter` de `processing.dart`, y la barra avanza con ellos. Si el procesado tarda más que la animación, el barrido espera en bucle suave.

## Modo UNA PÁGINA
Tras la animación se va directamente a 07 con una sola página, sin pila ni «Siguiente».

## Salida
`Navigator.pop(context, pages)` → `scan_flow.dart` continúa a 07 → 08 → guardar (flujo A en `flows.md`).
