# 07 · Ajustar bordes / 08 · Filtro

PNG: `screens/07-ajustar-bordes.png`, `08-filtro.png`
Capas: `layers/07-ajustar-bordes.json`, `08-filtro.json`
Código: `lib/ui_edit.dart → CropScreen`, `FilterScreen`. Ambas pantallas pasan a trabajar con una **lista de páginas** (no con una sola foto) y mantienen la versión de una página para reeditar desde el visor.

Fondo `#15181C`, barra de estado clara.

## 07 · Ajustar bordes
| Elemento | Posición | Detalle |
|---|---|---|
| Atrás | 16,60 · 40 | Círculo blanco 10% con `chevron_left` blanco. Vuelve a la cámara conservando las páginas. |
| Título | centrado, y=62 | «Ajustar bordes» 17/600 blanco |
| Subtítulo | centrado, y=84 | «Página 1 de 2» 13/400 blanco 55% |
| Área de foto | 16,118 · 361×482 | Radio 18, fondo negro, foto original en modo *contain* |
| Fuera del recorte | encima de la foto | Negro 65% con un agujero en el cuadrilátero (`CustomPainter` con `PathFillType.evenOdd`) |
| Recorte | cuadrilátero | Trazo `#48CAE4` de 2, sin relleno |
| Esquinas | — | `CornerHandle` de 22. La que se arrastra pasa a 30 con borde `accent` de 3 y halo. Admite también arrastrar los puntos medios de cada lado (opcional). |
| Lupa | 34,132 · 104 | Solo mientras se arrastra. Aparece en la esquina opuesta al dedo para no taparlo. Zoom ×2,2 con una guía en L del recorte y un punto blanco de 10 en el centro. |
| Tira de páginas | y=618, centrada | Miniaturas de 40×56 con radio 6 y 10 de separación. La activa lleva borde `#48CAE4` de 2 y las demás van al 50%. Al tocar una, se cambia de página. Se oculta si hay una sola página. |
| Barra inferior | 0,694 · 393×158 | `#1E2227` con radio 28 arriba |
| Herramientas | 12,712, 4 × 56×56 | Icono de 20 y etiqueta 11: «Todo» (recorte = foto completa), «Auto» (vuelve a detectar; seleccionada por defecto, en `#48CAE4` 600), «Izquierda» y «Derecha» (giran 90°). Las no seleccionadas van en blanco 70%. |
| Siguiente | 264,716 · 113×48 | `PrimaryButton` con radio 24, «Siguiente» 16/600 y flecha `arrow_right` de 12 detrás. En la última página (o con una sola), pasa a 08. Si no es la última, avanza a la siguiente página; se puede añadir un enlace «Saltar todas» en el subtítulo (opcional). |

## 08 · Filtro
| Elemento | Posición | Detalle |
|---|---|---|
| Atrás | 16,60 · 40 | Igual que en 07 |
| Título | centrado, y=62 | «Filtro» 17/600 blanco |
| Subtítulo | centrado, y=84 | «{nombre del documento} · N páginas» 13/400 blanco 55% |
| Página | 62,116 · 269×380 | Página procesada a tamaño completo, radio 3, sombra negra 60% y=16 blur=36. Se desliza horizontalmente entre páginas con un `PageView`. |
| Indicador | centrado, y=508 · 44×21 | Píldora blanca 10% con radio 11 y «1 / 2» 12/600 blanco 80% |
| Carrusel | y=546, 5 items de 62 de ancho, separación 10, empezando en x=22 | Miniatura de 56×78 con radio 8 y la página actual con cada filtro aplicado. Etiqueta 12/400 blanco 65% a 7 bajo la miniatura. **Seleccionado:** borde `#48CAE4` de 2,5 y etiqueta 12/700 `#48CAE4`. Orden: Original · Mejorar · Aclarar · Grises · B/N (`PageFilter.values`). |
| Aplicar a todas | 16,662 · 361×48 | `#1E2227` con radio 14. «Aplicar a todas las páginas» 15/400 blanco y `CupertinoSwitch` (`activeTrackColor: accent`) en ON. En ON, cambiar el filtro afecta a todas las páginas; en OFF, solo a la visible. Se oculta si hay una sola página. |
| Guardar | 16,726 · 361×54 | `PrimaryButton` con radio 27, `checkmark` de 13 y «Guardar N páginas» 17/600. Con una página: «Guardar». Sombra `accent` 40% y=8 blur=20. |

- El filtro inicial es `settings.defaultFilter` (Mejorar).
- Las miniaturas del carrusel se calculan en un isolate al entrar. Mientras tanto se muestra un placeholder `#2A2F35` con shimmer suave.
- Al guardar se usa `_withProgress('Guardando…')` con el HUD de la pantalla 16. Después se va a 09 (documento nuevo) o se vuelve al documento de origen.
