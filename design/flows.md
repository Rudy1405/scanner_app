# Recorridos

## A. Escanear con la cámara (varias páginas) — flujo principal

```
01 Inicio ──[Escanear (FAB 72)]──► 03 Elegir origen ──[Escanear con la cámara]──► 04 Cámara
                (también: pulsar el FAB directamente puede abrir la cámara sin pasar por 03; ver nota)

04 Cámara (hoja detectada, Siguiente desactivado)
   │  pulsar obturador  (o captura automática si la hoja está estable ~1 s)
   ▼
05 Captura procesando pág. 1
   - la foto vuela/encoge al centro, barrido turquesa de arriba abajo
   - HUD "Mejorando imagen…" con 3 pasos ✓ y barra de progreso
   - al terminar: miniatura cae a la pila (abajo izq.), contador = 1, Siguiente se activa
   ▼  (la cámara sigue abierta automáticamente)
06 Cámara pág. 2  ── repetir obturador N veces ──► contador N, botón "Siguiente · N"
   │  [Siguiente · N]
   ▼
07 Ajustar bordes (Página 1 de N; tira de miniaturas para saltar entre páginas)
   │  [Siguiente]
   ▼
08 Filtro (Mejorar por defecto, "Aplicar a todas las páginas" ON)
   │  [Guardar N páginas]
   ▼
09 Documento (nuevo, con nombre automático)
```

- **Cerrar (✕) en 04/06** con páginas capturadas: `CupertinoAlertDialog` con el título "¿Descartar N páginas?" y los botones "Seguir escaneando" y "Descartar" (este último en rojo). Sin páginas, se cierra directamente.
- **Modo UNA PÁGINA:** el primer disparo pasa directamente a 07, sin pila ni "Siguiente".
- **Importar desde 04** (botón de galería abajo a la izquierda, visible solo cuando la pila está vacía): abre la galería, y las imágenes elegidas se añaden a la pila como páginas capturadas.
- **Nota:** el FAB "Escanear" abre la cámara directamente y el botón "Importar" (52) abre la galería directamente. La hoja 03 se usa para "Añadir páginas" dentro de un documento, donde hay que elegir el origen.

## B. Importar imágenes

`01 [Importar]` → selector de fotos del sistema (varias) → **16 Procesando** ("Procesando N páginas…") → 07 → 08 → 09.

## C. Gestionar un documento

```
01 ─[fila/tile]─► 09 Documento
09 ─[título ✎ o ⋯ › Cambiar nombre]─► 14 Cambiar nombre (alerta)
09 ─[icono ordenar]─► 10 Ordenar páginas ─[Listo]─► 09
09 ─[página]─► 11 Visor ─[Recortar]─► 07 (una página) ─► 08 ─► 11
                        ─[Filtro]──► 08 (una página)
                        ─[Girar]───► gira 90° en el sitio
                        ─[Eliminar]► alerta destructiva
09 ─[Añadir páginas / Añadir]─► 03 Elegir origen ─► A o B, añadiendo al mismo documento
09 ─[PDF]─► 16 Procesando "Creando PDF…" ─► 17 hoja nativa de compartir
09 ─[Texto]─► 12 Texto (OCR local)
09 ─[JPG]─► exporta imágenes ─► hoja nativa de compartir
01 ─[⋯ en una fila]─► menú contextual: Cambiar nombre · Compartir PDF · Eliminar ─► 14 / 17 / 15
01 ─[engranaje]─► 13 Ajustes (modal, se cierra con ✕)
01 ─[icono cuadrícula/lista]─► alterna 01 ⇄ 02 (guardar preferencia)
```
