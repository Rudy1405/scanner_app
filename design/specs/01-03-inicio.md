# 01 · Inicio — lista / 02 · Inicio — cuadrícula / 03 · Elegir origen

PNG: `screens/01-inicio-lista.png`, `02-inicio-cuadricula.png`, `03-elegir-origen.png`
Capas: `layers/01-inicio-lista.json`, `02-…`, `03-…`
Código: `lib/ui_home.dart`, `lib/scan_flow.dart → askSource`

Fondo `#F4F6F8`. Lienzo de 393×852. Las coordenadas son (x, y, ancho×alto) en dp.

## Cabecera (igual en 01 y 02)
| Elemento | Posición | Detalle |
|---|---|---|
| Logo | 20,62 · 30×30 | Radio 8, `logoGradient`, icono documento/escáner blanco de 16. Usa `assets/logo.svg`. |
| "Escáner Local" | 58,67 | 16/600 `text` |
| Botón vista | 281,57 · 40 | `GlassIconButton` claro. Muestra `square_grid_2x2` en la lista y `list_bullet` en la cuadrícula. Alterna 01⇄02. |
| Botón ajustes | 329,57 · 40 | `GlassIconButton` claro, `gear_alt`. Abre 13 en modal. |
| "Mis documentos" | 20,106 | 34/700 título grande. Al hacer scroll colapsa al estilo `CupertinoSliverNavigationBar`. |
| Buscador | 16,160 · 361×40 | Radio 20, `#767680` 10%, lupa de 16 `muted`, placeholder "Buscar por nombre o texto" 16/400 `muted`. Filtra por nombre **y** por texto OCR (`doc.text`). |
| Píldora privacidad | 16,212 · 361×36 | `PrivacyPill`: «Sin anuncios · Sin nube · Todo queda en tu iPhone». En Android: «…en tu teléfono» (con tilde; el mockup 01 tiene la errata "telefono"). |
| "Recientes" | 20,268 | 20/700 |
| "4 documentos" | alineado a la derecha, x final 373, y 273 | 14/400 `muted`. Singular: "1 documento". |

## 01 · Lista
- `GroupedCard` en 16,306 con ancho 361 y una fila de 92 de alto por documento (`DocRow`):
  - Miniatura de 52×70 en x=30 (14 desde la tarjeta), y = top+11, radio 6, portada del documento.
  - Título en x=96 (80 desde la tarjeta), 16/600, una línea con elipsis.
  - Fecha 13/400 `muted`: «Hoy · 10:30», «Ayer · 18:05», o «12 nov 2026 · 18:05».
  - Meta: icono de páginas (`doc_on_doc`, 11) + nº de páginas 13/600 `muted`. Si `doc.text` no está vacío, lleva además `TextChip` "Texto".
  - "⋯" en x=345 (tres puntos de 4, `#9AA5B1`) centrado verticalmente. Abre el menú contextual de iOS (`CupertinoContextMenu` o un action sheet) con «Cambiar nombre», «Compartir PDF» y «Eliminar» (este en rojo).
  - Separador de 1 px `#E1E5EA` desde x=96 hasta el borde derecho, salvo en la última fila.
  - Pulsación larga: el mismo menú.
- La lista hace scroll bajo los FAB; deja ~170 de padding inferior.

## 02 · Cuadrícula
- 2 columnas de 174 con 12 de separación (x=16 y x=202). Cada item ocupa 261 de alto más 18 de separación vertical.
- Tarjeta de 174×222, radio 14, blanca con sombra. La portada llena la tarjeta con un margen interior de ~14 y aspecto de hoja.
- Badge de páginas abajo a la izquierda de la portada: píldora oscura (`#1F2933` 60% con desenfoque), icono y número 12/600 blanco.
- Nombre 15/600 a 3 px bajo la tarjeta y fecha 12/400 `muted` (solo la fecha, sin hora, salvo si es "Hoy").

## Pie con FAB (01 y 02)
- "Fundido" de 0,690 · 393×162: degradado vertical de `#F4F6F8` 0% → 90% (al 55%) → 100%. Va por encima de la lista y debajo de los botones.
- **Importar**: 84,748 · 52×52. `GlassFab` blanco 70%, borde blanco y sombra y=6 blur=16 al 12%. Icono `photo_on_rectangle` de 17 `text`. Abre directamente la galería (flujo B).
- **Escanear**: 160,738 · 72×72 (centrado). `ScanFab` con `primaryGradient` e icono `camera_fill` blanco de 30. Abre directamente la cámara propia (04).

## 03 · Elegir origen (hoja modal)
Se usa al pulsar «Añadir páginas» dentro de un documento.
- Velo `#0B0F14` 40% sobre la pantalla.
- Hoja en 8,478 · 377×366: radio 38 (flotante, con 8 de margen lateral), blanca, sombra y=-4 blur=30 al 20%.
  - Asa (grabber) de 37×5 `#C5CBD3` centrada a 8 del borde superior.
  - «Nuevo documento» 20/700 centrado a 30 del borde superior. Si se añade a un documento: «Añadir páginas».
  - Fila 1 en 24,552 · 345×84, radio 20, `#F4F6F8`: icono de 52 con radio 14 y `primaryGradient` (cámara blanca), «Escanear con la cámara» 16/600 y «Varias páginas seguidas, bordes automáticos» 13/400 `muted`, chevron de 7×14 `#B6BEC8` a la derecha.
  - Fila 2 en 24,646 con el mismo formato: icono de 52 blanco (galería en `accent`), «Importar imágenes» y «Elige una o varias fotos de tu galería».
  - «Cancelar» en 24,748 · 345×52: radio 26, `#767680` 10%, 17/600 `text`.
