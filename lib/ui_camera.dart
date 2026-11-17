// Own multi-page camera (design/specs/04-06-camara.md).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'processing.dart';
import 'scan_flow.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_edit.dart';
import 'widgets/widgets.dart';

enum CaptureMode { single, multi }

/// Input of the live detector: the Y plane of a camera frame.
class _Frame {
  _Frame(this.y, this.width, this.height, this.stride, this.sensor);
  final Uint8List y;
  final int width, height, stride, sensor;
}

/// Down-scales the Y plane to a small portrait picture and finds the page.
List<double>? _detectLive(_Frame f) {
  const target = 200;
  final scale = target / math.max(f.width, f.height);
  final sw = math.max(8, (f.width * scale).round());
  final sh = math.max(8, (f.height * scale).round());
  // Rotated (portrait) size.
  final turn = f.sensor == 90 || f.sensor == 270;
  final ow = turn ? sh : sw, oh = turn ? sw : sh;
  final out = Uint8List(ow * oh * 3);
  for (var y = 0; y < sh; y++) {
    final sy = math.min(f.height - 1, (y / scale).floor());
    for (var x = 0; x < sw; x++) {
      final sx = math.min(f.width - 1, (x / scale).floor());
      final v = f.y[sy * f.stride + sx];
      int px, py;
      if (f.sensor == 90) {
        px = sh - 1 - y;
        py = x;
      } else if (f.sensor == 270) {
        px = y;
        py = sw - 1 - x;
      } else {
        px = x;
        py = y;
      }
      final i = (py * ow + px) * 3;
      out[i] = v;
      out[i + 1] = v;
      out[i + 2] = v;
    }
  }
  final c = detectCorners(RgbImage(ow, oh, out));
  // The fallback (whole picture with a margin) means "nothing found".
  return _isFallback(c) ? null : c;
}

/// True for the "nothing found" corners (whole picture with a margin).
bool _isFallback(List<double> c) {
  const e = 0.045;
  return (c[0] - e).abs() < 0.01 && (c[1] - e).abs() < 0.01 && (c[4] - (1 - e)).abs() < 0.01;
}

/// What a shot becomes, worked out in one go off the UI thread.
class _Shot {
  _Shot(this.corners, this.blurry, this.flat, this.processed, this.aspect);
  final List<double> corners;
  final bool blurry;
  final Uint8List? flat; // flattened photo, display size
  final Uint8List? processed; // same with the filter (the "scanned" look)
  final double aspect; // width / height of the flattened page
}

/// Decode once; find the page (or keep [a.$3]); blur check; flatten; filter.
_Shot _captureJob((Uint8List, bool, List<double>?, int) a) {
  const all = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
  final full = decodePhoto(a.$1);
  if (full == null) return _Shot(all, false, null, null, 0.75);
  var im = full;
  final long = math.max(im.width, im.height);
  if (long > 1600) {
    final s = 1600 / long;
    im = RgbImage.fromImage(img.copyResize(im.toImage(),
        width: (im.width * s).round(),
        height: (im.height * s).round(),
        interpolation: img.Interpolation.average));
  }
  var corners = all;
  if (a.$2) {
    final found = detectCorners(im);
    corners = !_isFallback(found) ? found : (a.$3 ?? found);
  }
  final flat = flattenPage(im, corners);
  if (isBlurry(flat)) return _Shot(corners, true, null, null, flat.width / flat.height);
  final fl = math.max(flat.width, flat.height);
  final small = fl > 1000
      ? RgbImage.fromImage(img.copyResize(flat.toImage(),
          width: (flat.width * 1000 / fl).round(),
          height: (flat.height * 1000 / fl).round(),
          interpolation: img.Interpolation.average))
      : flat;
  return _Shot(corners, false, encodeJpeg(small, quality: 85),
      encodeJpeg(applyFilter(small, PageFilter.values[a.$4]), quality: 85), flat.width / flat.height);
}

class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, required this.store, this.initial = const []});
  final Store store;
  final List<CapturedPage> initial;
  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _system = MethodChannel('escaner/system');

  CameraController? cam;
  String? error;
  bool denied = false; // permission refused: offer the system settings
  bool gotFrame = false; // at least one preview frame arrived
  bool noFrames = false; // none arrived after a few seconds
  double brightness = 255; // mean luma of the last frame, 0..255
  Timer? frameTimer;
  CaptureMode mode = CaptureMode.multi;
  late bool auto = widget.store.settings.autoCapture;
  bool flash = false;
  late final List<CapturedPage> pages = [...widget.initial];

  // Live detection.
  List<double>? quad; // detected corners (0..1, portrait)
  List<double>? shownQuad;
  bool detecting = false;
  DateTime lastDetect = DateTime(2000);
  DateTime? stableSince;
  bool shooting = false;

  // Capture animation (as in the original): the page outline flashes white,
  // the flattened page appears over the preview, a scan line sweeps down
  // revealing the enhanced page, then it shrinks into the thumbnail.
  List<double>? shotQuad; // outline shown while the shot is worked out
  CapturedPage? processing;
  Uint8List? procFlat, procOut;
  double procAspect = 0.75;
  late final AnimationController shotFlash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final AnimationController fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController drop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final AnimationController bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController press =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
  bool justAdded = false;
  Timer? justTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _init();
  }

  Future<void> _retry() async {
    final old = cam;
    cam = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      error = null;
      denied = false;
      gotFrame = false;
      noFrames = false;
    });
    await _init();
  }

  Future<void> _openSettings() async {
    try {
      await _system.invokeMethod<bool>('openAppSettings');
    } catch (_) {}
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No hay cámara');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      cam = c;
      setState(() {});
      await c.startImageStream(_onFrame);
      frameTimer?.cancel();
      frameTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !gotFrame) setState(() => noFrames = true);
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          denied = e.code.startsWith('CameraAccessDenied') || e.code == 'CameraAccessRestricted';
          error = denied
              ? 'Necesitamos la cámara para escanear. Actívala en los ajustes del teléfono.'
              : 'No se pudo abrir la cámara.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo abrir la cámara.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = cam;
    // Back from the system settings after granting the permission.
    if (c == null && error != null && state == AppLifecycleState.resumed) {
      _retry();
      return;
    }
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      cam = null;
    } else if (state == AppLifecycleState.resumed && cam == null) {
      _init();
    }
  }

  void _onFrame(CameraImage image) {
    if (!gotFrame && mounted) {
      setState(() {
        gotFrame = true;
        noFrames = false;
      });
    }
    if (detecting || shooting) return;
    final now = DateTime.now();
    if (now.difference(lastDetect).inMilliseconds < 300) return;
    lastDetect = now;
    detecting = true;
    final plane = image.planes.first;
    // Mean brightness from a sparse sample of the Y plane (to tell "dark" from "broken").
    var sum = 0, n = 0;
    for (var i = 0; i < plane.bytes.length; i += 211) {
      sum += plane.bytes[i];
      n++;
    }
    final mean = n == 0 ? 255.0 : sum / n;
    if ((mean < 28) != (brightness < 28) && mounted) setState(() {});
    brightness = mean;
    final frame = _Frame(Uint8List.fromList(plane.bytes), image.width, image.height,
        plane.bytesPerRow, cam?.description.sensorOrientation ?? 90);
    compute(_detectLive, frame).then((q) {
      detecting = false;
      if (!mounted) return;
      _updateQuad(q);
    }, onError: (Object _) {
      detecting = false;
    });
  }

  void _updateQuad(List<double>? q) {
    final now = DateTime.now();
    if (q == null) {
      stableSince = null;
    } else if (quad != null && _moved(quad!, q) < 0.04) {
      stableSince ??= now;
    } else {
      stableSince = now;
    }
    setState(() {
      quad = q;
      if (q != null) shownQuad = q;
    });
    if (auto &&
        q != null &&
        !shooting &&
        stableSince != null &&
        now.difference(stableSince!).inMilliseconds > 1000) {
      stableSince = null;
      _shoot();
    }
  }

  double _moved(List<double> a, List<double> b) {
    var m = 0.0;
    for (var i = 0; i < 8; i++) {
      m = math.max(m, (a[i] - b[i]).abs());
    }
    return m;
  }

  Future<void> _shoot() async {
    final c = cam;
    if (c == null || shooting || !c.value.isInitialized || !gotFrame) return;
    shooting = true;
    HapticFeedback.mediumImpact();
    press.forward().then((_) => press.reverse());
    try {
      final live = quad;
      setState(() => shotQuad = live ?? const [0.06, 0.08, 0.94, 0.08, 0.94, 0.86, 0.06, 0.86]);
      shotFlash.forward(from: 0);
      await c.stopImageStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) c.startImageStream(_onFrame);
      final settings = widget.store.settings;
      // Edges again on the full photo (more exact than the live preview), the
      // sharpness check (like the original's clear-frame picker), the
      // flattened page and its enhanced look, all in one go.
      final shot = await compute(
          _captureJob, (bytes, settings.autoCrop, live, settings.defaultFilter.index));
      if (!mounted) return;
      if (shot.blurry) {
        setState(() {
          shotQuad = null;
          shooting = false;
        });
        stableSince = null;
        HapticFeedback.heavyImpact();
        showToast(context, 'La foto salió movida. Mantén el móvil quieto y vuelve a intentarlo.');
        return;
      }
      final page = CapturedPage(bytes, shot.corners, shot.processed);
      _animateCapture(page, shot);
    } catch (_) {
      shooting = false;
      shotQuad = null;
      if (mounted) {
        showToast(context, 'No se pudo hacer la foto. Inténtalo de nuevo.');
        c.startImageStream(_onFrame).catchError((Object _) {});
      }
    }
  }

  Future<void> _animateCapture(CapturedPage page, _Shot shot) async {
    final reduce = MediaQuery.disableAnimationsOf(context);
    setState(() {
      shotQuad = null;
      processing = page;
      procFlat = shot.flat;
      procOut = shot.processed;
      procAspect = shot.aspect;
    });
    sweep.value = 0;
    drop.value = 0;
    if (reduce) {
      fly.value = 1;
      sweep.value = 1;
    } else {
      await fly.forward(from: 0);
      if (!mounted) return;
      await sweep.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    if (reduce) {
      drop.value = 1;
    } else {
      await drop.forward(from: 0);
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    pages.add(page);
    bounce.forward(from: 0);
    justTimer?.cancel();
    justAdded = true;
    justTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => justAdded = false);
    });
    setState(() {
      processing = null;
      procFlat = null;
      procOut = null;
      shooting = false;
    });
    if (mode == CaptureMode.single) _next();
  }

  /// The original's undo arrow: drop the last page (a wrong or repeated shot).
  void _undo() {
    if (pages.isEmpty || shooting) return;
    HapticFeedback.lightImpact();
    setState(() => pages.removeLast());
    showToast(context, 'Página ${pages.length + 1} eliminada');
  }

  void _next() {
    if (pages.isEmpty) return;
    Navigator.pop(context, pages);
  }

  Future<void> _close() async {
    if (pages.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('¿Descartar ${pages.length} ${pages.length == 1 ? 'página' : 'páginas'}?',
            style: ts(17, w600)),
        content: Text('Las fotos que has hecho se perderán.',
            style: ts(13, w400, AppColors.alertBody)),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              textStyle: ts(17, w400, AppColors.accentDark),
              child: const Text('Seguir escaneando')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, true),
              isDestructiveAction: true,
              textStyle: ts(17, w600, AppColors.destructive),
              child: const Text('Descartar')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _import() async {
    final photos = await pickGallery();
    if (photos.isEmpty || !mounted) return;
    final settings = widget.store.settings;
    var moved = 0;
    for (final p in photos) {
      final shot =
          await compute(_captureJob, (p, settings.autoCrop, null, settings.defaultFilter.index));
      pages.add(CapturedPage(p, shot.corners, shot.processed)..blurry = shot.blurry);
      if (shot.blurry) moved++;
    }
    if (moved > 0 && mounted) {
      showToast(context,
          moved == 1 ? '1 foto salió movida: revísala al ajustar bordes.' : '$moved fotos salieron movidas: revísalas al ajustar bordes.');
    }
    if (!mounted) return;
    if (mode == CaptureMode.single || _problem) {
      _next();
    } else {
      setState(() {});
      bounce.forward(from: 0);
    }
  }

  Future<void> _toggleFlash() async {
    final c = cam;
    if (c == null) return;
    flash = !flash;
    try {
      await c.setFlashMode(flash ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    justTimer?.cancel();
    frameTimer?.cancel();
    shotFlash.dispose();
    fly.dispose();
    sweep.dispose();
    drop.dispose();
    bounce.dispose();
    press.dispose();
    final c = cam;
    cam = null;
    c?.dispose();
    super.dispose();
  }

  // ─────────────────────────── UI ───────────────────────────

  /// Something is wrong with the camera itself (not just "no page found").
  bool get _problem => error != null || noFrames;

  bool get _dark => gotFrame && brightness < 28;

  String get _hint {
    final n = pages.length + 1;
    if (!gotFrame) return 'Iniciando la cámara…';
    if (_dark && quad == null) {
      return flash ? 'Muy oscuro · acércate a la luz' : 'Poca luz · activa el flash';
    }
    if (quad == null) return 'Buscando el documento…';
    if (!auto) return 'Hoja detectada';
    return pages.isEmpty ? 'Hoja detectada · capturando…' : 'Página $n · hoja detectada';
  }

  static const double _barHeight = 112;

  /// Width / height of the preview as shown (portrait).
  double get _previewAspect {
    final s = cam?.value.previewSize;
    if (s == null || s.width == 0) return 3 / 4;
    return s.height / s.width;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final c = cam;
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: Stack(fit: StackFit.expand, children: [
        // Preview (cover)
        if (c != null && c.value.isInitialized)
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.previewSize!.height,
                height: c.value.previewSize!.width,
                child: CameraPreview(c),
              ),
            ),
          )
        else if (error == null)
          const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white)),
        if (_problem)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.darkBg,
              child: _CameraProblem(
                denied: denied,
                message: error ?? 'La cámara no responde.',
                onSettings: _openSettings,
                onRetry: _retry,
                onImport: _import,
              ),
            ),
          ),
        // Gradients
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x80000000), Color(0x00000000)]))))),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 234 + pad.bottom,
            child: const IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0, 0.28, 1],
                            colors: [Color(0x00000000), Color(0xD9000000), Color(0xD9000000)]))))),
        // Detected page (drawn over the preview as it's shown: cropped to fill)
        if (shownQuad != null && quad != null && processing == null && shotQuad == null)
          Positioned.fill(
              child: IgnorePointer(
                  child: TweenAnimationBuilder<_QuadValue>(
            tween: _QuadTween(end: _QuadValue(quad!)),
            duration: const Duration(milliseconds: 160),
            builder: (_, v, _) => CustomPaint(painter: _DetectPainter(v.c, _previewAspect)),
          ))),
        // Just shot: the outline flashes white while the page is worked out.
        if (shotQuad != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: shotFlash,
                builder: (_, _) => CustomPaint(
                    painter: _DetectPainter(shotQuad!, _previewAspect,
                        shot: true, glow: 1 - shotFlash.value)),
              ),
            ),
          ),
        // Top bar
        Positioned(
          top: pad.top + 6,
          left: 16,
          right: 16,
          child: Row(children: [
            GlassIconButton(
                label: 'Cerrar cámara',
                icon: CupertinoIcons.xmark,
                style: GlassStyle.dark,
                color: CupertinoColors.white,
                onTap: _close),
            const Spacer(),
            if (!_problem) _AutoManual(auto: auto, onChanged: (v) => setState(() => auto = v)),
            const Spacer(),
            GlassIconButton(
                label: flash ? 'Apagar el flash' : 'Encender el flash',
                icon: flash ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt_slash_fill,
                style: GlassStyle.dark,
                onTap: _problem ? null : _toggleFlash),
          ]),
        ),
        // Hint (only while looking for the page, like the original)
        if (!_problem && (quad == null || _dark) && processing == null && shotQuad == null)
          Positioned(
            top: pad.top + 74,
            left: 0,
            right: 0,
            child: Center(child: _CameraHint(text: _hint, active: quad != null, warn: _dark)),
          ),
        // Capture animation
        if (processing != null) _processingLayer(size, pad),
        // Thumbnail of the last page, bottom right (tap: review the pages)
        if (!_problem && pages.isNotEmpty)
          Positioned(right: 16, bottom: pad.bottom + _barHeight + 14, child: _stack()),
        // Bottom panel
        if (!_problem)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottom(pad),
          ),
      ]),
    );
  }

  /// The original's capture moment: the flattened page fills the preview,
  /// a scan line sweeps down showing the enhanced page above it and the
  /// plain photo below, then the page shrinks into the bottom-right
  /// thumbnail.
  Widget _processingLayer(Size size, EdgeInsets pad) {
    // Area between the top bar and the bottom bar, with a margin.
    final area = Rect.fromLTRB(20, pad.top + 70, size.width - 20,
        size.height - pad.bottom - _barHeight - 20);
    var w = area.width, h = w / procAspect;
    if (h > area.height) {
      h = area.height;
      w = h * procAspect;
    }
    final page = Rect.fromCenter(center: area.center, width: w, height: h);
    // Where the thumbnail sits.
    final thumb = Rect.fromLTWH(size.width - 16 - 52, size.height - pad.bottom - _barHeight - 14 - 88, 52, 70);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([fly, sweep, drop]),
          builder: (_, _) {
            final f = Curves.easeOutCubic.transform(fly.value);
            final d = Curves.easeInCubic.transform(drop.value);
            final r = Rect.lerp(page, thumb, d)!;
            final grown = Rect.fromCenter(
                center: r.center, width: r.width * (0.94 + 0.06 * f), height: r.height * (0.94 + 0.06 * f));
            return Stack(children: [
              Positioned.fromRect(
                rect: grown,
                child: Opacity(
                  opacity: f,
                  child: _SweepPage(original: procFlat, processed: procOut, t: sweep.value),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _bottom(EdgeInsets pad) {
    final hasPages = pages.isNotEmpty;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Individual / Lote, until the first page is in (as in the original).
      if (!hasPages && processing == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ModeSwitch(mode: mode, onChanged: (m) => setState(() => mode = m)),
        ),
      Container(
        color: const Color(0xFF000000),
        padding: EdgeInsets.only(bottom: pad.bottom),
        height: _barHeight + pad.bottom,
        child: Stack(alignment: Alignment.center, children: [
            Center(
              child: Tap(
                label: 'Hacer foto',
                onTap: gotFrame ? _shoot : null,
                child: Opacity(
                  opacity: gotFrame ? 1 : 0.4,
                  child: AnimatedBuilder(
                  animation: press,
                  builder: (_, _) => Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: CupertinoColors.white, width: 4)),
                    alignment: Alignment.center,
                    child: Transform.scale(
                      scale: 1 - 0.1 * press.value,
                      child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                              color: CupertinoColors.white, shape: BoxShape.circle)),
                    ),
                  ),
                ),
                ),
              ),
            ),
            // Left: undo the last page once there is one.
            if (hasPages)
              Positioned(
                left: 36,
                child: Tap(
                  label: 'Deshacer la última página',
                  onTap: shooting ? null : _undo,
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(CupertinoIcons.arrow_uturn_left, size: 24, color: CupertinoColors.white),
                  ),
                ),
              ),
            // Right: import while empty, then "Hecho".
            Positioned(
              right: 20,
              child: hasPages
                  ? _NextButton(count: pages.length, onTap: shooting ? null : _next)
                  : _importButton(),
            ),
        ]),
      ),
    ]);
  }

  Widget _importButton() => Tap(
        label: 'Importar imágenes',
        onTap: _import,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x2EFFFFFF)),
          ),
          child: const Icon(CupertinoIcons.photo_on_rectangle, size: 20, color: CupertinoColors.white),
        ),
      );

  Widget _stack() {
    final last = pages.last;
    return Tap(
      label: '${pages.length} ${pages.length == 1 ? 'página' : 'páginas'}. Continuar',
      onTap: _next,
      // As in the original: last page's thumbnail, red counter on its corner,
      // "Modificar" under it.
      child: SizedBox(
        width: 60,
        height: 92,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Positioned(top: 0, child: _thumb(last.thumb ?? last.photo, 1)),
          Positioned(
            right: -4,
            top: -8,
            child: ScaleTransition(
              scale: TweenSequence<double>([
                TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 1),
                TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 1),
              ]).animate(CurvedAnimation(parent: bounce, curve: Curves.easeOut)),
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.destructive, borderRadius: BorderRadius.circular(11)),
                child: Text('${pages.length}', style: ts(12, w700, CupertinoColors.white)),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.accentDark, borderRadius: BorderRadius.circular(5)),
              child: Text('Modificar', style: ts(11, w600, CupertinoColors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _thumb(Uint8List bytes, double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: 52,
          height: 70,
          decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: CupertinoColors.white, width: 1)),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
        ),
      );
}

// ───────────────────────── pieces ─────────────────────────

class _QuadValue {
  const _QuadValue(this.c);
  final List<double> c;
}

class _QuadTween extends Tween<_QuadValue> {
  _QuadTween({required _QuadValue end}) : super(end: end);
  @override
  _QuadValue lerp(double t) {
    final b = end!;
    final a = begin ?? b;
    return _QuadValue([for (var i = 0; i < 8; i++) a.c[i] + (b.c[i] - a.c[i]) * t]);
  }
}

/// The page outline over the live preview, as the original draws it: a
/// translucent fill with a thin border, no handles. Corners are relative to
/// the camera frame, which the preview shows cropped to fill the screen
/// ([aspect] = frame width / height), so they're mapped the same way.
class _DetectPainter extends CustomPainter {
  _DetectPainter(this.c, this.aspect, {this.shot = false, this.glow = 0});
  final List<double> c;
  final double aspect;
  final bool shot; // just captured: white outline
  final double glow;
  @override
  void paint(Canvas canvas, Size size) {
    double dw, dh;
    if (size.width / size.height > aspect) {
      dw = size.width;
      dh = size.width / aspect;
    } else {
      dh = size.height;
      dw = size.height * aspect;
    }
    final ox = (size.width - dw) / 2, oy = (size.height - dh) / 2;
    final pts = [for (var i = 0; i < 4; i++) Offset(ox + c[i * 2] * dw, oy + c[i * 2 + 1] * dh)];
    final path = Path()..addPolygon(pts, true);
    if (shot) {
      canvas.drawPath(path, Paint()..color = CupertinoColors.white.withValues(alpha: 0.25 * glow));
      canvas.drawPath(
          path,
          Paint()
            ..color = CupertinoColors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round);
      return;
    }
    canvas.drawPath(path, Paint()..color = AppColors.accent.withValues(alpha: 0.30));
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.accentLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _DetectPainter old) =>
      old.c != c || old.aspect != aspect || old.glow != glow;
}

class _AutoManual extends StatelessWidget {
  const _AutoManual({required this.auto, required this.onChanged});
  final bool auto;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool active, bool value) => Tap(
          label: value ? 'Captura automática' : 'Captura manual',
          onTap: () => onChanged(value),
          child: Container(
            width: 70,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: active ? CupertinoColors.white.withValues(alpha: 0.9) : null,
                borderRadius: BorderRadius.circular(15)),
            child: Text(label, style: ts(14, w600, active ? AppColors.accentDark : CupertinoColors.white)),
          ),
        );
    return Glass(
      radius: 18,
      color: const Color(0x2EFFFFFF),
      border: const Color(0x33FFFFFF),
      child: SizedBox(
        width: 150,
        height: 44,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          seg('Auto', auto, true),
          seg('Manual', !auto, false),
        ]),
      ),
    );
  }
}

class _CameraHint extends StatelessWidget {
  const _CameraHint({required this.text, required this.active, this.warn = false});
  final String text;
  final bool active;
  final bool warn;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Glass(
          radius: 18,
          blur: 20,
          color: const Color(0xA6000000),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 35,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  warn ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.circle_fill,
                  size: warn ? 14 : 8,
                  color: warn
                      ? CupertinoColors.white
                      : active
                          ? AppColors.accentLight
                          : const Color(0xFFB6BEC8)),
              const SizedBox(width: 8),
              Text(text, style: ts(14, w600, CupertinoColors.white)),
            ]),
          ),
        ),
      );
}

/// Full-screen state when the camera cannot be used: says why and what to do.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({
    required this.denied,
    required this.message,
    required this.onSettings,
    required this.onRetry,
    required this.onImport,
  });
  final bool denied;
  final String message;
  final VoidCallback onSettings, onRetry, onImport;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(20)),
            child: const Icon(CupertinoIcons.camera_fill, size: 28, color: CupertinoColors.white),
          ),
          const SizedBox(height: 20),
          Text(denied ? 'Necesitamos la cámara' : 'No se puede usar la cámara',
              textAlign: TextAlign.center, style: ts(20, w700, CupertinoColors.white)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center, style: ts(15, w400, const Color(0xCCFFFFFF), 1.35)),
          const SizedBox(height: 24),
          PrimaryButton(
              label: denied ? 'Abrir ajustes' : 'Reintentar', onTap: denied ? onSettings : onRetry),
          const SizedBox(height: 10),
          if (denied)
            Tap(
              minSize: 48,
              onTap: onRetry,
              child: Text('Ya la activé · Reintentar',
                  style: ts(15, w600, AppColors.accentLight)),
            ),
          Tap(
            minSize: 48,
            onTap: onImport,
            child: Text('Importar de la galería', style: ts(15, w600, AppColors.accentLight)),
          ),
        ]),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});
  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget item(String label, CaptureMode m) {
      final active = mode == m;
      return Tap(
        onTap: () => onChanged(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0x40FFFFFF) : null,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(label,
              style: ts(14, active ? w600 : w400,
                  active ? CupertinoColors.white : const Color(0xCCFFFFFF))),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -100) onChanged(CaptureMode.multi);
        if (v > 100) onChanged(CaptureMode.single);
      },
      // Pill like the original's "Individual | Lote".
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: const Color(0x99000000), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          item('Individual', CaptureMode.single),
          item('Lote', CaptureMode.multi),
        ]),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tap(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.accentDark : const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        // The original says "Hecho" (done) here.
        child: Text('Hecho',
            style: ts(15, w600, enabled ? CupertinoColors.white : const Color(0x59FFFFFF))),
      ),
    );
  }
}

/// The photo with the processed version revealed top to bottom by a scan line.
class _SweepPage extends StatelessWidget {
  const _SweepPage({required this.original, required this.processed, required this.t});
  final Uint8List? original; // the flattened photo
  final Uint8List? processed;
  final double t;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3.6),
        boxShadow: const [BoxShadow(color: Color(0x80000000), offset: Offset(0, 16), blurRadius: 36)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.6),
        child: LayoutBuilder(builder: (_, box) {
          final h = box.maxHeight;
          final y = t * h;
          return Stack(fit: StackFit.expand, children: [
            Container(color: CupertinoColors.white),
            // Below the line: the flattened photo as taken.
            if (original != null) Image.memory(original!, fit: BoxFit.fill, gaplessPlayback: true),
            // Above the line: the enhanced page.
            if (processed != null && t > 0)
              ClipRect(
                  clipper: _TopClip(y),
                  child: Image.memory(processed!, fit: BoxFit.fill, gaplessPlayback: true)),
            Positioned(
              top: math.max(0, y - 42),
              left: 0,
              right: 0,
              height: 42,
              child: const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x0048CAE4), Color(0x6648CAE4)]))),
            ),
            Positioned(
              top: y - 1.5,
              left: 0,
              right: 0,
              height: 3,
              child: const DecoratedBox(
                  decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      boxShadow: [BoxShadow(color: AppColors.accentLight, blurRadius: 9)])),
            ),
          ]);
        }),
      ),
    );
  }
}

class _TopClip extends CustomClipper<Rect> {
  _TopClip(this.y);
  final double y;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, y);
  @override
  bool shouldReclip(covariant _TopClip old) => old.y != y;
}

