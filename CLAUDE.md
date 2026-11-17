# Escáner Local (Flutter)

Escáner de documentos sin anuncios ni nube: todo se queda en el dispositivo. La interfaz está en español.

## Rediseño iOS — referencia obligatoria
La UI de referencia está en `design/`. Antes de tocar cualquier pantalla:
1. Lee `design/DESIGN.md` (tokens, componentes y mapa pantalla → archivo `.dart`).
2. Lee la spec de esa pantalla en `design/specs/*.md` y mira su PNG en `design/screens/`.
3. Si falta una medida, un color o una sombra, búscala en `design/specs/layers/NN-*.json`. No inventes valores.
4. Para consultar el diseño fuente hay un MCP: `figcraft-app` (con la app FigCraft abierta con `--control 7979`) o `figcraft` (headless). El archivo es `design/Escaner Local - iOS.figcraft`.

Reglas:
- Usa Cupertino (`CupertinoApp`, `CupertinoIcons`, etc.) en iOS y Android.
- Hay dos tonos de acento: `#00B4D8` y `#0089A7` (más `#48CAE4` en las pantallas oscuras). No hay otros colores de acento.
- **No cambies** el motor de imagen (`processing.dart`), el almacenamiento (`store.dart`) ni la exportación (`export.dart`) salvo para añadir lo que pida la spec (por ejemplo `settings.autoCapture`).
- La cámara propia multipágina (`design/specs/04-06-camara.md`) sustituye a `image_picker` solo para la cámara; la galería sigue con `image_picker`/`file_selector`.

## Compilar
- Android: `flutter build apk --release`
- iOS: requiere Mac (`flutter build ios`)
- Vista previa en PC: `python main.py`. La captura automática con `--screenshot <png>` está en `lib/main.dart`.
- Tests: `flutter test`
- Valores del escáner sacados de la app original: `MECHANICS.md`
