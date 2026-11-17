# Escáner Local — diseño iOS (Cupertino)

Este es el diseño de referencia para rehacer la interfaz de la app. Hay que **cambiar la apariencia y el flujo de escaneo** sin tocar el motor: `processing.dart`, `store.dart` y `export.dart` funcionan y se mantienen.

| Qué | Dónde |
|---|---|
| Pantallas a @3x (1179×2556) | `screens/NN-*.png` (vista general: `screens/00-overview.png`) |
| Spec por pantalla (textos exactos, medidas, comportamiento) | `specs/*.md` |
| Capas de cada pantalla en JSON (posición, tamaño, relleno, sombra, texto) | `specs/layers/NN-*.json` |
| Tokens en formato máquina | `tokens.json` |
| Recorrido completo | `flows.md` |
| Logo / icono | `assets/logo.svg`, `assets/logo-1024.png` |
| Imágenes de ejemplo (fotos de cámara, páginas, filtros) | `assets/samples/` |
| Fuente editable | `Escaner Local - iOS.figcraft` (se abre con FigCraft; el MCP `figcraft-app` permite consultar cualquier capa) |

> **Regla:** si un PNG y una spec no coinciden, manda la spec. Si falta un valor en la spec, búscalo en `specs/layers/*.json` en lugar de adivinarlo.

---

## 1. Principios

1. **iOS nativo, no Material.** Se usan widgets `Cupertino*` siempre que existan: `CupertinoPageScaffold`, `CupertinoSliverNavigationBar` (título grande), `CupertinoSwitch`, `CupertinoSlidingSegmentedControl`, `CupertinoAlertDialog`, `CupertinoActionSheet` / modal sheet, `CupertinoSearchTextField`, `CupertinoSlider` e iconos `CupertinoIcons`. Las transiciones son `CupertinoPageRoute`. El mismo diseño se usa en Android: no hay una versión Material aparte.
2. **Dos tonos de un mismo color.** El turquesa `#00B4D8` es el acento principal y `#0089A7` su versión oscura, que se usa para texto sobre fondo claro. En las pantallas oscuras, el acento es `#48CAE4`. No se usa ningún otro color de acento; el rojo solo aparece en acciones destructivas.
3. **Claro para gestionar, oscuro para capturar.** Inicio, documento, texto y ajustes van sobre fondo claro `#F4F6F8`. Cámara, recorte, filtro y visor van en oscuro (`#000`, `#15181C`, `#2A2F35`).
4. **Vidrio.** Los botones flotantes son translúcidos con desenfoque de fondo: `BackdropFilter` con `ImageFilter.blur`, un relleno blanco al 80% (claro) o al 18% (oscuro) y un borde blanco de 1 px.
5. **Privacidad visible.** El mensaje "Sin anuncios · Sin nube · Todo queda en tu iPhone/teléfono" aparece en inicio y en ajustes.

## 2. Tokens → Flutter

Hay que sustituir `lib/theme.dart`. Los valores exactos están en `tokens.json`; este es el núcleo:

```dart
class AppColors {
  static const accent        = Color(0xFF00B4D8);
  static const accentDark    = Color(0xFF0089A7); // texto acento sobre claro
  static const accentLight   = Color(0xFF48CAE4); // acento sobre oscuro
  static const accentTint    = Color(0xFFE0F5FA);
  static const background    = Color(0xFFF4F6F8);
  static const surface       = Colors.white;
  static const text          = Color(0xFF1F2933);
  static const muted         = Color(0xFF7B8794);
  static const tertiary      = Color(0xFF9AA5B1);
  static const separator     = Color(0xFFE1E5EA);
  static const darkBg        = Color(0xFF15181C);
  static const darkPanel     = Color(0xFF1E2227);
  static const viewerBg      = Color(0xFF2A2F35);
  static const destructive   = Color(0xFFFF3B30);
  static const fillQuaternary = Color(0x1A767680); // #767680 @10%
  static const primaryGradient = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF33C3E3), Color(0xFF0096B8)]);
  static const logoGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF48CAE4), Color(0xFF0089A7)]);
}
```

- Usa `CupertinoApp` con `CupertinoThemeData(primaryColor: AppColors.accent, scaffoldBackgroundColor: AppColors.background)`. Si algún widget Material sigue siendo necesario (por ejemplo `ReorderableListView`), envuelve la app en un `Theme` con el mismo `colorScheme`.
- **Tipografía:** los mockups usan Inter como sustituto de SF Pro. No empaquetes ninguna fuente; usa la del sistema. La escala está en `tokens.json → typography` (34/28/20/17/16/15/14/13/12/11; pesos 700/600/400).

## 3. Componentes reutilizables

Créalos en `lib/widgets/` y úsalos en todas las pantallas.

| Componente | Spec | Se usa en |
|---|---|---|
| `GlassIconButton` | Círculo de 40, radio 20. **Claro:** blanco 80% + borde blanco 1 px + sombra `#1F2933` 8% y=4 blur=12. **Oscuro:** blanco 18% + borde blanco 20% + desenfoque 16 (o blanco 10% sin borde en recorte, filtro y visor). Icono de 15–18 px en `text` o en blanco. | Todas |
| `PrimaryButton` | Relleno `accent`, texto blanco 16–17/600, radio = altura/2 (48→24, 54→27, 50→25), sombra `accent` 40% y=6–8 blur=16–20. Admite icono delante o detrás. | Guardar, Siguiente, Volver a reconocer, Listo |
| `ScanFab` | Círculo de 72 con `primaryGradient`, borde blanco 35%, sombra `accent` 40% y=10 blur=24 e icono de cámara blanco de 30. Lleva al lado (a la izquierda, 24 px de separación) un `GlassFab` de 52 para Importar. | Inicio |
| `PrivacyPill` | Alto 36, radio 18, fondo `accentTint`, candado de 9×12 y texto 13/600 `accentDark`. | Inicio |
| `SearchField` | `CupertinoSearchTextField` de alto 40, radio 20, fondo `#767680` 10%, placeholder "Buscar por nombre o texto". | Inicio |
| `GroupedCard` | Blanco, radio 16, sombra `#1F2933` 5% y=2 blur=8. Los separadores son de 1 px `#E1E5EA` con sangría desde el texto. | Lista, ajustes |
| `DocRow` | Alto 92. Miniatura de 52×70 con radio 6; título 16/600, fecha 13/400 `muted`; meta con icono de páginas y número 13/600, más el chip "Texto" si tiene OCR. Botón "⋯" de tres puntos de 4 px `#9AA5B1`. | Inicio lista |
| `DocTile` | Tarjeta de 174×222 con radio 14, portada y badge del nº de páginas abajo a la izquierda; nombre 15/600 y fecha 12/400 debajo. Rejilla de 2 columnas con 12 de separación. | Inicio cuadrícula |
| `TextChip` | Alto 17, radio 6, fondo `accentTint`, texto 11/600 `accentDark`. | DocRow |
| `FloatingActionBar` | Píldora de 361×66 con radio 33, blanco 85%, desenfoque 20, borde blanco 1 px y sombra y=8 blur=24 al 12%. Tiene 4 botones de 86 de ancho con icono arriba y etiqueta 11/600. La versión oscura usa `#1E2227` al 90% con etiquetas en blanco 80%. | Documento, visor |
| `GlassHud` | `#1E2227` al 80%, desenfoque 24, borde blanco 10%, radio 20. | Cámara (procesando) |
| `CameraHint` | Píldora negra al 65% con desenfoque 20, radio 18, punto `accentLight` de 8 y texto 14/600 blanco. | Cámara |
| `PageCounterBadge` | Círculo de 22 `accent` con número 12/700 blanco. Va sobre la pila de miniaturas capturadas. | Cámara |
| `CornerHandle` | Círculo blanco de 22 con sombra. Activo: 30, borde `accent` de 3 y halo `accent` 60% blur 14. | Recorte |
| `Loupe` | Círculo de 104 con borde blanco de 3 y sombra. Muestra la foto ampliada ×2.2 con una cruz y un punto blanco de 10 en el centro. | Recorte |
| Alertas | `CupertinoAlertDialog`: fondo blanco 95% con desenfoque 30 y radio 24; título 17/600, cuerpo 13/400 `#52606D`; botones 17 en `accentDark` (o `destructive` 600). | Renombrar, eliminar |

**Iconos:** usa `CupertinoIcons`:
- `camera_fill`, `photo_on_rectangle`
- `square_grid_2x2`, `list_bullet`, `gear_alt`
- `search`, `lock_fill`, `doc_on_doc`, `ellipsis`
- `xmark`, `bolt_fill`, `chevron_left`
- `crop_rotate`, `rotate_left`, `rotate_right`, `wand_stars`
- `share`, `trash`, `text_cursor`, `doc_text`, `photo`
- `plus`, `checkmark`, `pencil`, `line_horizontal_3` (asa de arrastre), `folder`

Elige el que más se parezca al del PNG.

## 4. Mapa pantalla → código actual

| Pantalla(s) | Archivo actual | Cambio |
|---|---|---|
| 01, 02 Inicio (lista / cuadrícula) | `ui_home.dart` (`HomeScreen`, `_DocRow`, `_DocTile`, `_PrivacyBanner`, `_Logo`) | Rehacer con título grande, buscador, píldora de privacidad, FAB doble (Importar + Escanear) y fundido inferior. |
| 03 Elegir origen | `scan_flow.dart → askSource` | Sheet Cupertino con dos filas grandes y "Cancelar". |
| 04–06 Cámara propia multipágina | **Nuevo** `ui_camera.dart` | Sustituye a `image_picker` para la cámara. Ver `specs/04-06-camara.md`. |
| 07 Ajustar bordes | `ui_edit.dart → CropScreen` | Rediseño oscuro, lupa, tira de páginas y "Página N de M". |
| 08 Filtro | `ui_edit.dart → FilterScreen` | Carrusel de 5 miniaturas, "Aplicar a todas las páginas" y "Guardar N páginas". |
| 09 Documento | `ui_doc.dart → DocScreen` | Título grande editable, rejilla de 2 columnas, tarjeta "Añadir páginas" y barra flotante. |
| 10 Ordenar | Nuevo (dentro de `ui_doc.dart`) | Lista reordenable estilo iOS en modo edición. |
| 11 Visor | `ui_doc.dart → PageViewer` | Fondo `#2A2F35`, `PageView`, puntos y barra flotante oscura. |
| 12 Texto | `ui_misc.dart → OcrScreen` | Título grande, botón "Volver a reconocer" y texto editable con separadores por página. |
| 13 Ajustes | `ui_misc.dart → SettingsScreen` | Lista agrupada iOS. Nuevo ajuste "Captura automática". |
| 14 Cambiar nombre, 15 Eliminar | `ui_misc.dart → askName / confirm` | `CupertinoAlertDialog`. |
| 16 Procesando | `scan_flow.dart → _withProgress` | HUD centrado con anillo de progreso. |
| 17 Compartir PDF | `export.dart` + `share_plus` | Es la hoja **nativa** del sistema: no se dibuja; el mockup solo muestra qué se le pasa (nombre `.pdf` y miniatura). |

## 5. Orden de implementación sugerido

1. `theme.dart` + `lib/widgets/*` (tokens y componentes).
2. Inicio (01–03), porque es lo que más se ve.
3. **Cámara propia (04–06)**, la funcionalidad nueva. Hay que añadir el paquete `camera` y los permisos (ya existen para `image_picker`).
4. Recorte (07) y filtro (08) en modo multipágina.
5. Documento, ordenar y visor (09–11).
6. Texto, ajustes y diálogos (12–17).

Después de cada paso, compara una captura de la app con el PNG de `screens/` a 393×852. En PC, la app acepta `--screenshot <ruta.png>` (ver `lib/main.dart`) y guarda una captura de inicio con documentos de ejemplo.
