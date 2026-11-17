# 12 · Texto del documento / 13 · Ajustes

PNG: `screens/12-texto.png`, `13-ajustes.png`
Capas: `layers/12-texto.json`, `13-ajustes.json`
Código: `lib/ui_misc.dart → OcrScreen`, `SettingsScreen`

## 12 · Texto (fondo `#F4F6F8`)
| Elemento | Posición | Detalle |
|---|---|---|
| Atrás | 10,60 | `chevron_left` más el nombre corto del documento («Factura luz») en 17/400 `accentDark` |
| Copiar | 281,57 · 40 | `GlassIconButton` con `doc_on_doc`. Copia todo y muestra un toast breve «Copiado». |
| Compartir | 329,57 · 40 | `GlassIconButton` con `share`. Usa `exportText`. |
| Título | 20,106 | «Texto» 34/700 |
| Volver a reconocer | 16,160 · 361×50 | `PrimaryButton` con radio 25, icono de recargar o varita de 16 y texto 16/600. Lanza el OCR de nuevo con el HUD de la pantalla 16 («Reconociendo texto…»). |
| Ayuda | centrada, y=222 | Candado de 9×12 y «Se hace en el propio dispositivo, sin internet.» 13/400 `muted` |
| Texto editable | 16,254 · 361×556 | Tarjeta blanca con radio 16 y padding 18. Por cada página, un separador «— Página N —» 13/600 `accentDark` y el texto en 15/400 `text` con interlineado ~1,4. Es editable (`CupertinoTextField` sin borde, multilínea) y se guarda en `doc.text` al salir. |

Si todavía no hay texto, se muestra un estado vacío con «Aún no se ha reconocido el texto» y el botón «Reconocer texto».

## 13 · Ajustes (modal de página completa, fondo `#F4F6F8`)
- Cerrar: `GlassIconButton` con `xmark` en 329,57. Título «Ajustes» 34/700 en 20,106.
- Las cabeceras de sección van en 12/600 MAYÚSCULAS `accentDark`, a x=36 y 22 por encima de su tarjeta.
- Cada tarjeta es un `GroupedCard` (o `CupertinoListSection.insetGrouped`) con filas de 52 y separadores desde x=32.

**ESCANEO**
| Fila | Control | Campo |
|---|---|---|
| Detectar bordes automáticamente | `CupertinoSwitch` en ON (`accent`) | `settings.autoCrop` (existe) |
| Captura automática | `CupertinoSwitch` en ON | **nuevo** `settings.autoCapture` (por defecto `true`; es el estado inicial Auto/Manual de la cámara) |
| Filtro por defecto | «Mejorar» 16/400 `muted` y chevron | `settings.defaultFilter`. Abre una lista de selección con ✓ `accent`. |

**PDF E IMÁGENES**
| Fila | Control | Campo |
|---|---|---|
| Tamaño de página | `CupertinoSlidingSegmentedControl` de 329×34 debajo del texto: «A4» · «Carta» · «Ajustar». El segmento activo es blanco con sombra y texto 14/600. | `settings.pageSize`. La etiqueta corta de `PdfPageSize.fit` en la UI es «Ajustar». |
| Calidad | «85 %» 16/600 `accentDark` a la derecha y debajo un `CupertinoSlider` de 50 a 95 (pista `#E1E5EA`, activa `accent`, pulgar blanco de 28 con sombra) con las etiquetas «50» y «95» 12/400 `#9AA5B1` a los lados | `settings.jpegQuality` |

**PRIVACIDAD** (informativa)
- Icono de 32 con radio 8 `accent` y candado blanco: «Todo se guarda en este dispositivo».
- Icono de 32 con radio 8 `accentTint` y carpeta `accentDark`: «Carpeta» y debajo la ruta en 13/400 `muted` («En mi iPhone › Escáner Local»). En Android, la ruta real de `store.root`.

Pie centrado en y=752, en 12/400 `#9AA5B1`: «Escáner Local 1.0» / «Sin anuncios · Sin cuentas · Sin nube». La versión sale de `pubspec.yaml`.

Los ajustes se guardan al cambiar cualquier control (`store.saveSettings()`), sin botón de guardar.
