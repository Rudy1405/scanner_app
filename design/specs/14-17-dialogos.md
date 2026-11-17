# 14 · Cambiar nombre / 15 · Eliminar / 16 · Procesando / 17 · Compartir PDF

PNG: `screens/14-cambiar-nombre.png`, `15-eliminar.png`, `16-procesando-importacion.png`, `17-compartir-pdf.png`
Capas: `layers/14-…`, `15-…`, `16-…`, `17-…`
Código: `lib/ui_misc.dart → askName`, `confirm`; `lib/scan_flow.dart → _withProgress`; `lib/export.dart`

Todas se dibujan **sobre** la pantalla de origen (09 o 01) con un velo `#0B0F14`: 30% para las alertas, 20% para el HUD.

## 14 · Cambiar nombre
`showCupertinoDialog` + `CupertinoAlertDialog` (300 de ancho, radio 24, blanco 95% con desenfoque).
- Título: «Cambiar nombre» 17/600.
- Mensaje: «Escribe un nombre para este documento.» 13/400 `#52606D`.
- Campo: `CupertinoTextField` de 268×40 con radio 10, fondo blanco y borde fino `#E1E5EA`. Lleva el nombre actual en 15/400, todo seleccionado al abrir y botón de borrar.
- Botones: «Cancelar» (17/400 `accentDark`) y «Guardar» (17/600 `accentDark`, acción por defecto). «Guardar» se desactiva si el campo está vacío.

## 15 · Eliminar documento
`CupertinoAlertDialog`:
- Icono: círculo de 48 `#FFE9E7` con `trash` `#FF3B30`, encima del título (en `title`, con una `Column`).
- Título: «¿Eliminar «{nombre}»?» 17/600.
- Mensaje: «Se borrará de este iPhone y no se puede deshacer.» (en Android, «de este teléfono») 13/400 `#52606D`.
- Botones: «Cancelar» (17/400 `accentDark`) y «Eliminar» (`isDestructiveAction`, 17/600 `#FF3B30`).
- Para eliminar una página desde el visor, igual con «¿Eliminar la página N?».

## 16 · Procesando (HUD)
Sustituye al `AlertDialog` de `_withProgress`:
- Tarjeta de 190×157 centrada, radio 28, blanco 92% con desenfoque 30 y sombra suave.
- Anillo de progreso de 52 (pista `accentTint` y arco `accent` de 4). Si el progreso no se conoce, gira; si se conoce (N páginas), avanza.
- Texto 17/600 `text`: «Creando PDF…», «Procesando N páginas…», «Guardando…» o «Reconociendo texto…».
- Subtítulo 13/400 `muted`: «2 páginas · A4» (páginas y tamaño del ajuste).
- No se puede cerrar (`PopScope(canPop: false)`), como ahora.

## 17 · Compartir PDF
Es la **hoja nativa** del sistema (`Share.shareXFiles` de `share_plus`): **no se dibuja en Flutter**. El mockup solo sirve de referencia:
- Nombre del archivo: «{nombre del documento}.pdf», limpiando los caracteres no válidos (`/ \ : * ? " < > |`).
- Pasar `subject` con el nombre del documento y `sharePositionOrigin` en iPad.
- El tamaño, «PDF · 2 páginas · 412 KB», lo pone el sistema.
