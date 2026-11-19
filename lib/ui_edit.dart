// Crop (07) and filter (08) screens, working on a list of pages.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'native/find_corners.dart';
import 'processing.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/widgets.dart';
import 'l10n.dart';

/// A photo on its way to becoming a page: corners, turn and filter.
class CapturedPage {
  CapturedPage(this.photo, this.corners, [this.thumb]);
  final Uint8List photo;
  List<double> corners;
  Uint8List? thumb;
  int rotation = 0;
  PageFilter filter = PageFilter.enhance;

  /// The photo came out moved/blurry (imports are kept but marked).
  bool blurry = false;
}

List<double> _detect(Uint8List photo) {
  final img = decodePhoto(photo);
  if (img == null) return const [0, 0, 1, 0, 1, 1, 0, 1];
  return findCorners(img);
}

Future<List<double>> detectCornersAsync(Uint8List photo) => compute(_detect, photo);

/// Corners and whether the page is blurry, measured on a 1600 px copy.
(List<double>, bool) _check((Uint8List, bool) a) {
  const all = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
  final full = decodePhoto(a.$1);
  if (full == null) return (all, false);
  var im = full;
  final long = im.width > im.height ? im.width : im.height;
  if (long > 1600) {
    final s = 1600 / long;
    im = RgbImage.fromImage(img.copyResize(im.toImage(),
        width: (im.width * s).round(),
        height: (im.height * s).round(),
        interpolation: img.Interpolation.average));
  }
  final corners = a.$2 ? findCorners(im) : all;
  return (corners, isBlurry(flattenPage(im, corners)));
}

/// Finds the page (when [autoCrop]) and checks the photo isn't moved.
Future<(List<double>, bool)> checkPhotoAsync(Uint8List photo, {required bool autoCrop}) =>
    compute(_check, (photo, autoCrop));

const _white = CupertinoColors.white;

// ───────────────────────── 07 · Ajustar bordes ─────────────────────────

class CropScreen extends StatefulWidget {
  const CropScreen(
      {super.key, required this.pages, required this.store, this.index = 0, this.canDelete = true});
  final List<CapturedPage> pages;
  final Store store;
  final int index;

  /// Pages can be thrown away here (wrong or repeated shots). Off when
  /// re-editing a saved page.
  final bool canDelete;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late int index = widget.index;
  int? dragging;
  bool detecting = false;
  String? tool = 'auto';
  final Map<CapturedPage, Size> sizes = {};

  // Pinch-zoom state for the crop area (reset per page).
  CapturedPage? _zoomPage;
  double _zoom = 1;
  double _startZoom = 1;
  Offset _pan = Offset.zero;
  Offset _startContent = Offset.zero;

  List<CapturedPage> get pages => widget.pages;
  CapturedPage get page => pages[index];

  @override
  void initState() {
    super.initState();
    for (final p in pages) {
      _loadSize(p);
    }
  }

  void _loadSize(CapturedPage p) {
    final stream = MemoryImage(p.photo).resolve(const ImageConfiguration());
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => sizes[p] = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      stream.removeListener(l);
    });
    stream.addListener(l);
  }

  /// Throws the current page away (a wrong or repeated shot).
  Future<void> _delete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t('¿Eliminar esta página?'), style: ts(17, w600)),
        content: Text(t('La foto {n} se descartará y no se guardará.', {'n': index + 1}),
            style: ts(13, w400, AppColors.alertBody)),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              textStyle: ts(17, w400, AppColors.accentDark),
              child: Text(t('Cancelar'))),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, true),
              isDestructiveAction: true,
              textStyle: ts(17, w600, AppColors.destructive),
              child: Text(t('Eliminar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = pages.removeAt(index);
    sizes.remove(removed);
    if (pages.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      index = index.clamp(0, pages.length - 1);
      tool = 'auto';
      dragging = null;
    });
  }

  Future<void> _auto() async {
    setState(() {
      detecting = true;
      tool = 'auto';
    });
    final c = await detectCornersAsync(page.photo);
    if (mounted) {
      setState(() {
        page.corners = c;
        detecting = false;
      });
    }
  }

  void _all() => setState(() {
        page.corners = [0, 0, 1, 0, 1, 1, 0, 1];
        tool = 'todo';
      });

  void _next() {
    if (index < pages.length - 1) {
      setState(() {
        index++;
        tool = 'auto';
      });
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final last = index == pages.length - 1;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBg,
      child: Column(children: [
        // Header
        SizedBox(
          height: pad.top + 112,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 6, 16, 0),
            child: Stack(alignment: Alignment.topCenter, children: [
              Align(
                alignment: Alignment.topLeft,
                child: GlassIconButton(
                    label: t('Volver'),
                    icon: CupertinoIcons.chevron_left,
                    style: GlassStyle.subtle,
                    iconSize: 18,
                    onTap: () => Navigator.pop(context)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(children: [
                  Text(t('Ajustar bordes'), style: ts(17, w600, _white)),
                  const SizedBox(height: 2),
                  Text(t('Página {n} de {total}', {'n': index + 1, 'total': pages.length}),
                      style: ts(13, w400, const Color(0x8CFFFFFF))),
                ]),
              ),
            ]),
          ),
        ),
        // Photo
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ColoredBox(
                color: const Color(0xFF000000),
                child: sizes[page] == null
                    ? const Center(child: CupertinoActivityIndicator(color: _white))
                    : Stack(children: [
                        Positioned.fill(child: _cropArea(sizes[page]!)),
                        if (page.blurry && dragging == null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: Center(child: _BlurryNotice(onDelete: widget.canDelete ? _delete : null)),
                          ),
                      ]),
              ),
            ),
          ),
        ),
        if (pages.length > 1 || widget.canDelete)
          SizedBox(
            height: 78,
            child: Center(
              child: ListView.separated(
                shrinkWrap: true,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (_, i) {
                  final selected = i == index;
                  // 52x72 cell: the miniature sits bottom-left and the delete
                  // badge pops over its top-right corner (selected page only).
                  return SizedBox(
                    width: 52,
                    height: 72,
                    child: Stack(children: [
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Tap(
                          label: t('Página {n}', {'n': i + 1}),
                          onTap: () => setState(() {
                            index = i;
                            tool = 'auto';
                          }),
                          child: Opacity(
                            opacity: selected ? 1 : 0.5,
                            child: Container(
                              width: 40,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: selected ? AppColors.accentLight : const Color(0x00000000),
                                    width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(fit: StackFit.expand, children: [
                                Image.memory(pages[i].thumb ?? pages[i].photo,
                                    fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
                                if (pages[i].blurry)
                                  const Positioned(
                                    left: 2,
                                    bottom: 2,
                                    child: Icon(CupertinoIcons.exclamationmark_triangle_fill,
                                        size: 13, color: AppColors.destructiveOnDark),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      if (selected && widget.canDelete)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tap(
                            label: t('Eliminar página {n}', {'n': i + 1}),
                            onTap: _delete,
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: AppColors.destructive,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.darkBg, width: 2),
                                  ),
                                  child: const Icon(CupertinoIcons.trash,
                                      size: 13, color: CupertinoColors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  );
                },
              ),
            ),
          )
        else
          const SizedBox(height: 14),
        // Tools
        Container(
          padding: EdgeInsets.fromLTRB(12, 14, 16, pad.bottom + 14),
          decoration: const BoxDecoration(
            color: AppColors.darkPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Row(children: [
            _Tool(
                icon: CupertinoIcons.crop,
                label: t('Todo'),
                selected: tool == 'todo',
                onTap: _all),
            _Tool(
                icon: CupertinoIcons.wand_stars,
                label: t('Auto'),
                selected: tool == 'auto',
                onTap: _auto),
            _Tool(
                icon: CupertinoIcons.rotate_left,
                label: t('Izquierda'),
                onTap: () => setState(() => page.rotation = (page.rotation + 3) % 4)),
            _Tool(
                icon: CupertinoIcons.rotate_right,
                label: t('Derecha'),
                onTap: () => setState(() => page.rotation = (page.rotation + 1) % 4)),
            const Spacer(),
            PrimaryButton(
                label: last ? t('Siguiente') : t('Siguiente'),
                iconAfter: CupertinoIcons.arrow_right,
                expand: false,
                onTap: _next),
          ]),
        ),
      ]),
    );
  }

  Widget _cropArea(Size imageSize) {
    return LayoutBuilder(builder: (context, box) {
      final fit = applyBoxFit(BoxFit.contain, imageSize, box.biggest);
      final size = fit.destination;
      final offset = Offset((box.maxWidth - size.width) / 2, (box.maxHeight - size.height) / 2);
      final corners = page.corners;
      final loupeLeft = dragging != null &&
          offset.dx + corners[dragging! * 2] * size.width > box.maxWidth / 2 &&
          offset.dy + corners[dragging! * 2 + 1] * size.height < box.maxHeight / 2 + 40;
      if (!identical(_zoomPage, page)) {
        _zoomPage = page;
        _zoom = 1;
        _pan = Offset.zero;
      }
      final boxSize = box.biggest;
      Offset clampPan(Offset p, double z) => Offset(
          p.dx.clamp(boxSize.width * (1 - z), 0.0), p.dy.clamp(boxSize.height * (1 - z), 0.0));
      // Screen point -> unzoomed content point.
      Offset toContent(Offset s) => (s - _pan) / _zoom;
      return Stack(children: [
        Positioned.fill(
          child: ClipRect(
            child: Transform(
              alignment: Alignment.topLeft,
              transform: Matrix4.identity()
                ..translate(_pan.dx, _pan.dy)
                ..scale(_zoom),
              child: Stack(children: [
                Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  width: size.width,
                  height: size.height,
                  child: Image.memory(page.photo,
                      fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                ),
                Positioned.fill(
                    child: CustomPaint(painter: _QuadPainter(corners, offset, size, dragging))),
              ]),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => setState(() {
              _zoom = 1;
              _pan = Offset.zero;
            }),
            onScaleStart: (d) {
              _startZoom = _zoom;
              _startContent = toContent(d.localFocalPoint);
              int? hit;
              if (d.pointerCount == 1) {
                final p = toContent(d.localFocalPoint) - offset;
                var bestDist = double.infinity;
                for (var i = 0; i < 4; i++) {
                  final c = Offset(corners[i * 2] * size.width, corners[i * 2 + 1] * size.height);
                  final dist = (c - p).distance;
                  if (dist < bestDist) {
                    bestDist = dist;
                    hit = i;
                  }
                }
                if (bestDist >= 70 / _zoom) hit = null;
              }
              setState(() {
                dragging = hit;
                if (hit != null) tool = null;
              });
            },
            onScaleUpdate: (d) {
              final i = dragging;
              if (i != null && d.pointerCount == 1) {
                final p = toContent(d.localFocalPoint) - offset;
                setState(() {
                  corners[i * 2] = (p.dx / size.width).clamp(0.0, 1.0);
                  corners[i * 2 + 1] = (p.dy / size.height).clamp(0.0, 1.0);
                });
                return;
              }
              setState(() {
                dragging = null;
                final z = (_startZoom * d.scale).clamp(1.0, 6.0);
                _zoom = z;
                _pan = clampPan(d.localFocalPoint - _startContent * z, z);
              });
            },
            onScaleEnd: (_) => setState(() => dragging = null),
          ),
        ),
        if (dragging != null)
          Positioned(
            top: 14,
            left: loupeLeft ? null : 18,
            right: loupeLeft ? 18 : null,
            child: _Loupe(
              photo: page.photo,
              size: size,
              center: Offset(corners[dragging! * 2] * size.width, corners[dragging! * 2 + 1] * size.height),
            ),
          ),
        if (detecting) const Center(child: CupertinoActivityIndicator(color: _white, radius: 14)),
      ]);
    });
  }
}

/// Pinch to zoom, drag to move when zoomed, double-tap to reset.
class _ZoomView extends StatefulWidget {
  const _ZoomView({required this.child});
  final Widget child;

  @override
  State<_ZoomView> createState() => _ZoomViewState();
}

class _ZoomViewState extends State<_ZoomView> {
  final controller = TransformationController();
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      final z = controller.value.getMaxScaleOnAxis() > 1.01;
      if (z != zoomed) setState(() => zoomed = z);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => controller.value = Matrix4.identity(),
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 1,
        maxScale: 6,
        panEnabled: zoomed,
        clipBehavior: Clip.hardEdge,
        child: widget.child,
      ),
    );
  }
}

/// "This photo came out moved" pill, with a quick way to drop it.
class _BlurryNotice extends StatelessWidget {
  const _BlurryNotice({this.onDelete});
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(CupertinoIcons.exclamationmark_triangle_fill,
            size: 15, color: AppColors.destructiveOnDark),
        const SizedBox(width: 7),
        Text(t('Foto movida'), style: ts(13, w600, _white)),
        if (onDelete != null) ...[
          const SizedBox(width: 10),
          Tap(
            onTap: onDelete!,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(t('Eliminar'), style: ts(13, w600, AppColors.destructiveOnDark)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = selected ? AppColors.accentLight : const Color(0xB3FFFFFF);
    return Tap(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        height: 56,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: ts(12, selected ? w600 : w400, c)),
        ]),
      ),
    );
  }
}

class _Loupe extends StatelessWidget {
  const _Loupe({required this.photo, required this.size, required this.center});
  final Uint8List photo;
  final Size size;
  final Offset center;
  @override
  Widget build(BuildContext context) {
    const d = 104.0, z = 2.2;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: ClipOval(
        child: Stack(children: [
          Positioned(
            left: d / 2 - center.dx * z - 3,
            top: d / 2 - center.dy * z - 3,
            width: size.width * z,
            height: size.height * z,
            child: Image.memory(photo, fit: BoxFit.fill, gaplessPlayback: true),
          ),
          Center(
              child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: _white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accentLight, width: 1.5)))),
        ]),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.c, this.offset, this.size, this.active);
  final List<double> c;
  final Offset offset;
  final Size size;
  final int? active;

  @override
  void paint(Canvas canvas, Size _) {
    final pts =
        List.generate(4, (i) => offset + Offset(c[i * 2] * size.width, c[i * 2 + 1] * size.height));
    final path = Path()..addPolygon(pts, true);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(offset & size)
      ..addPath(path, Offset.zero);
    canvas.drawPath(outside, Paint()..color = const Color(0xA6000000));
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.accentLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < 4; i++) {
      final p = pts[i];
      if (i == active) {
        canvas.drawCircle(
            p,
            15,
            Paint()
              ..color = AppColors.accent.withValues(alpha: 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
        canvas.drawCircle(p, 15, Paint()..color = _white);
        canvas.drawCircle(
            p,
            13.5,
            Paint()
              ..color = AppColors.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      } else {
        canvas.drawCircle(p, 11, Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        canvas.drawCircle(p, 11, Paint()..color = _white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) => true;
}

// ───────────────────────── 08 · Filtro ─────────────────────────

class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key, required this.pages, required this.store, required this.title});
  final List<CapturedPage> pages;
  final Store store;
  final String title;

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late final PageController controller = PageController();
  int index = 0;
  bool applyAll = true;
  final Map<int, Uint8List> flats = {};
  final Map<String, Uint8List> previews = {};
  final Set<String> pending = {};

  List<CapturedPage> get pages => widget.pages;
  CapturedPage get page => pages[index];
  String _key(int i, PageFilter f) => '$i:${f.index}';

  @override
  void initState() {
    super.initState();
    if (pages.length > 1) {
      final f = pages.first.filter;
      for (final p in pages) {
        p.filter = f;
      }
    }
    _prepare(0);
  }

  /// Flattened page without filter, then the previews we need for page [i].
  Future<void> _prepare(int i) async {
    final p = pages[i];
    if (!flats.containsKey(i)) {
      final out = await compute(runPageJob,
          PageJob(p.photo, p.corners, p.rotation, PageFilter.original, 90));
      if (!mounted || out == null) return;
      flats[i] = out;
    }
    final order = [p.filter, ...PageFilter.values.where((f) => f != p.filter)];
    for (final f in order) {
      await _preview(i, f);
      if (!mounted || index != i && f != p.filter) return;
    }
  }

  Future<void> _preview(int i, PageFilter f) async {
    final k = _key(i, f);
    if (previews.containsKey(k) || !pending.add(k)) return;
    if (!flats.containsKey(i)) {
      pending.remove(k);
      return;
    }
    final out = await compute(previewFilter, (flats[i]!, f));
    pending.remove(k);
    if (!mounted) return;
    setState(() => previews[k] = out);
  }

  Future<void> _select(PageFilter f) async {
    setState(() {
      if (applyAll) {
        for (final p in pages) {
          p.filter = f;
        }
      } else {
        page.filter = f;
      }
    });
    // Make sure the visible page has its picture.
    if (!flats.containsKey(index)) await _prepare(index);
    await _preview(index, f);
  }

  Future<void> _onPageChanged(int i) async {
    setState(() => index = i);
    await _prepare(i);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final n = pages.length;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBg,
      child: Column(children: [
        SizedBox(
          height: pad.top + 76,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 6, 16, 0),
            child: Stack(alignment: Alignment.topCenter, children: [
              Align(
                alignment: Alignment.topLeft,
                child: GlassIconButton(
                    label: t('Volver'),
                    icon: CupertinoIcons.chevron_left,
                    style: GlassStyle.subtle,
                    iconSize: 18,
                    onTap: () => Navigator.pop(context)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(children: [
                  Text(t('Filtro'), style: ts(17, w600, _white)),
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 140),
                    child: Text('${widget.title} · $n ${plural(n, 'página', 'páginas')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(13, w400, const Color(0x8CFFFFFF))),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: controller,
            itemCount: n,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) {
              final bytes = previews[_key(i, pages[i].filter)];
              return Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 40, 8),
                child: Center(
                  child: bytes == null
                      ? Container(
                          width: 220,
                          height: 300,
                          color: AppColors.viewerBg,
                          child: const Center(child: CupertinoActivityIndicator(color: _white)))
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(color: Color(0x99000000), offset: Offset(0, 16), blurRadius: 36)
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: _ZoomView(
                                  child: Image.memory(bytes,
                                      gaplessPlayback: true, filterQuality: FilterQuality.medium))),
                        ),
                ),
              );
            },
          ),
        ),
        if (n > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 21,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration:
                  BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(11)),
              child: Center(
                  widthFactor: 1,
                  child: Text('${index + 1} / $n', style: ts(12, w600, const Color(0xCCFFFFFF)))),
            ),
          ),
        // Carousel
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            children: [
              for (final f in PageFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Tap(
                    onTap: () => _select(f),
                    child: SizedBox(
                      width: 62,
                      child: Column(children: [
                        Container(
                          width: 56,
                          height: 78,
                          decoration: BoxDecoration(
                            color: AppColors.viewerBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: f == page.filter ? AppColors.accentLight : const Color(0x00000000),
                                width: 2.5),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: previews[_key(index, f)] == null
                              ? null
                              : Image.memory(previews[_key(index, f)]!,
                                  fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
                        ),
                        const SizedBox(height: 7),
                        Text(f.label,
                            style: ts(12, f == page.filter ? w700 : w400,
                                f == page.filter ? AppColors.accentLight : const Color(0xA6FFFFFF))),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (n > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.darkPanel, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(child: Text(t('Aplicar a todas las páginas'), style: ts(15, w400, _white))),
                CupertinoSwitch(
                    value: applyAll,
                    activeTrackColor: AppColors.accent,
                    onChanged: (v) => setState(() {
                          applyAll = v;
                          if (v) {
                            final f = page.filter;
                            for (final p in pages) {
                              p.filter = f;
                            }
                          }
                        })),
              ]),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 12),
          child: PrimaryButton(
              label: n == 1 ? t('Guardar') : t('Guardar {n} páginas', {'n': n}),
              height: 54,
              fontSize: 17,
              icon: CupertinoIcons.checkmark_alt,
              onTap: flats.isEmpty ? null : () => Navigator.pop(context, true)),
        ),
      ]),
    );
  }
}

/// Shows a page picture from disk, reloading when it changes.
class PageImage extends StatelessWidget {
  const PageImage(this.path, {super.key, this.fit = BoxFit.cover, this.cacheWidth});
  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final stamp = file.existsSync() ? file.lastModifiedSync().millisecondsSinceEpoch : 0;
    return Image.file(
      file,
      key: ValueKey('$path@$stamp'),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
          color: Color(0xFFE8ECEF),
          child: Center(child: Icon(CupertinoIcons.doc_text, color: AppColors.tertiary))),
    );
  }
}
