# 09 · Documento / 10 · Ordenar páginas / 11 · Visor de página

PNG: `screens/09-documento.png`, `10-ordenar.png`, `11-visor.png`
Capas: `layers/09-documento.json`, `10-ordenar.json`, `11-visor.json`
Código: `lib/ui_doc.dart → DocScreen`, `PageViewer`. Ordenar es nuevo.

## 09 · Documento (fondo `#F4F6F8`)
| Elemento | Posición | Detalle |
|---|---|---|
| Atrás | 10,60 | `chevron_left` de 7×14 más «Documentos» 17/400 `accentDark` (back de iOS) |
| Ordenar | 281,57 · 40 | `GlassIconButton` claro con icono de lista o reordenar. Abre 10. |
| Más | 329,57 · 40 | `GlassIconButton` claro con `ellipsis`. Action sheet: «Cambiar nombre», «Compartir PDF», «Guardar PDF en Archivos», «Exportar JPG» y «Eliminar documento» (en rojo). |
| Título | 20,106 | Nombre en 28/700 `text` (máx. 2 líneas) más lápiz de 12 `muted` a 8 de distancia. Al tocarlo se abre 14. |
| Meta | 20,144 | «2 páginas · 14/11/2026 10:30» 14/400 `muted` |
| Rejilla de páginas | desde y=184 | 2 columnas de 168×238 (x=20 y x=205; ~17 de separación horizontal y 18 vertical). Cada página es blanca con radio 6 y sombra `#1F2933` 12% y=6 blur=18. Abajo lleva una banda de 28 de alto `#1F2933` 40% con desenfoque 10 y el número 13/600 blanco centrado. Al tocar se abre 11 en esa página; la pulsación larga entra en modo ordenar. |
| Añadir páginas | siguiente hueco de la rejilla | 168×238 con radio 12, `accent` 5% y borde `accent` 50% de 1,5 (discontinuo opcional). Círculo de 44 `accentTint` con `plus` `accentDark` y «Añadir páginas» 14/600 `accentDark`. Abre 03. |
| Barra flotante | 16,744 · 361×66 | `FloatingActionBar` claro con 4 acciones (icono de ~17 y etiqueta 11/600 `text`): «Añadir» (cámara), «PDF» (`doc_text` → 16 → 17), «Texto» (`text_cursor` → 12) y «JPG» (`photo` → exportar imágenes y compartir). |

La rejilla hace scroll por debajo de la barra flotante, con un padding inferior de ~110.

## 10 · Ordenar páginas (fondo `#F4F6F8`)
- Barra: «Cancelar» 17/400 `accentDark` a la izquierda (x=20), «Ordenar páginas» 17/600 centrado y «Listo» como píldora `accent` de 74×36 con radio 18 y texto 16/600 blanco a la derecha.
- Cabecera de sección en 36,124: «MANTÉN PULSADO Y ARRASTRA PARA REORDENAR» 12/400 `muted`.
- `GroupedCard` en 16,146 con filas de 86:
  - Botón borrar rojo (círculo de 22 `#FF3B30` con guion blanco de 12×2) en x=30.
  - Miniatura de 44×62 con radio 6.
  - «Página N» 16/600 y «Filtro: Mejorar» 13/400 `muted`.
  - Asa `line_horizontal_3` de 16×8 `#9AA5B1` a la derecha.
- La fila arrastrada se levanta: tarjeta blanca propia con radio 16, sombra más fuerte y desplazada 5 px. En su lugar queda un hueco `#F4F6F8` de 345×66 con radio 10.
- Pie: «El orden se usa al exportar el PDF.» 13/400 `muted` en 36,326.
- Implementación: `ReorderableListView` con `proxyDecorator` para la sombra. Los cambios se aplican al pulsar «Listo»; «Cancelar» los descarta.

## 11 · Visor (fondo `#2A2F35`, barra de estado clara)
| Elemento | Posición | Detalle |
|---|---|---|
| Cerrar o atrás | 16,60 · 40 | Círculo blanco 10% con `chevron_left` blanco |
| Contador | centrado, y=66 · 56×27 | Píldora blanca 10% con radio 14 y «1 / 2» 14/600 blanco |
| Compartir | 337,60 · 40 | Círculo blanco 10% con `share`. Comparte esta página como JPG. |
| Página | 24,128 · 345×488 | Radio 3 y sombra. `PageView` horizontal: la siguiente asoma a 16 de distancia. Admite pellizcar para ampliar (`InteractiveViewer`). |
| Puntos | y=634, centrados | Activo: píldora de 18×7 blanca con radio 4. Inactivo: punto de 7 blanco 35%. |
| Ayuda | y=658, centrada | «Desliza para cambiar de página · Pellizca para ampliar» 12/400 blanco 45%. Se muestra solo la primera vez o se oculta tras 3 s. |
| Herramientas | 16,736 · 361×66 | `FloatingActionBar` oscuro (`#1E2227` 90%) con «Recortar» (→07), «Filtro» (→08), «Girar» (90° en el sitio) y «Eliminar». Etiquetas 11/400 blanco 80%; Eliminar en `#FF6B61`. |
