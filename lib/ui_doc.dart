// One document (09), reorder pages (10) and the page viewer (11).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:share_plus/share_plus.dart';

import 'export.dart';
import 'processing.dart';
import 'scan_flow.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_edit.dart';
import 'ui_misc.dart';
import 'widgets/widgets.dart';

const _white = CupertinoColors.white;

class DocScreen extends StatefulWidget {
  const DocScreen({super.key, required this.store, required this.doc});
  final Store store;
  final ScanDoc doc;

  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  Store get store => widget.store;
  ScanDoc get doc => widget.doc;

  Future<void> _rename() async {
    final name = await askName(context, doc.name);
    if (name != null) {
      doc.name = name;
      await store.saveDoc(doc);
    }
  }

  Future<void> _addPages() async {
    await scanPages(context, store, into: doc);
  }

  Future<void> _pdf({required bool share}) async {
    final path = await withProgress(
        context, 'Creando PDF…', () => exportPdf(doc, store.settings.pageSize, share: share),
        subtitle: pagesSubtitle(doc.pages.length, store.settings));
    if (path != null && mounted) showToast(context, 'PDF guardado');
  }

  Future<void> _jpg() async {
    final path = await exportImages(doc, share: true);
    if (path != null && mounted) showToast(context, 'Imágenes guardadas');
  }

  Future<void> _text() async {
    await Navigator.push(
        context, CupertinoPageRoute(builder: (_) => OcrScreen(store: store, doc: doc)));
  }

  Future<void> _delete() async {
    if (await confirm(context, '¿Eliminar «${doc.name}»?',
        'Se borrará de este $deviceWord y no se puede deshacer.')) {
      await store.deleteDoc(doc);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _more() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Cambiar nombre')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'pdf'), child: const Text('Compartir PDF')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Guardar PDF en Archivos')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'jpg'), child: const Text('Exportar JPG')),
          CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Eliminar documento')),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      ),
    );
    switch (action) {
      case 'rename':
        await _rename();
      case 'pdf':
        await _pdf(share: true);
      case 'save':
        await _pdf(share: false);
      case 'jpg':
        await _jpg();
      case 'delete':
        await _delete();
    }
  }

  Future<void> _reorder() async {
    await Navigator.push(
        context,
        CupertinoPageRoute(
            fullscreenDialog: true, builder: (_) => ReorderScreen(store: store, doc: doc)));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => CupertinoPageScaffold(
        backgroundColor: AppColors.background,
        child: Stack(children: [
          CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, pad.top + 8, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 44,
                    child: Row(children: [
                      BackLink(label: 'Documentos', onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      GlassIconButton(
                          label: 'Ordenar páginas',
                          icon: CupertinoIcons.arrow_up_arrow_down,
                          onTap: _reorder),
                      const SizedBox(width: 8),
                      GlassIconButton(
                          label: 'Más opciones', icon: CupertinoIcons.ellipsis, onTap: _more),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Tap(
                        minSize: 44,
                        label: 'Cambiar nombre: ${doc.name}',
                        onTap: _rename,
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: doc.name),
                            const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(CupertinoIcons.pencil, size: 14, color: AppColors.muted),
                                )),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ts(28, w700),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          '${doc.pages.length} ${doc.pages.length == 1 ? 'página' : 'páginas'} · ${friendlyDate(doc.modified)}',
                          style: ts(14, w400, AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(height: 18),
                ]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, pad.bottom + 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 17,
                    mainAxisSpacing: 18,
                    childAspectRatio: 168 / 238),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => i == doc.pages.length ? _addTile() : _pageTile(i),
                  childCount: doc.pages.length + 1,
                ),
              ),
            ),
          ]),
          Positioned(
            left: 16,
            right: 16,
            bottom: pad.bottom + 8,
            child: FloatingActionBar(actions: [
              BarAction(CupertinoIcons.camera, 'Añadir', _addPages),
              BarAction(CupertinoIcons.doc_text, 'PDF', () => _pdf(share: true)),
              BarAction(CupertinoIcons.text_cursor, 'Texto', _text),
              BarAction(CupertinoIcons.photo, 'JPG', _jpg),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _pageTile(int i) {
    final page = doc.pages[i];
    return Tap(
      onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
              builder: (_) => PageViewer(store: store, doc: doc, initial: i))),
      onLongPress: _reorder,
      child: Container(
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
                color: AppColors.text.withValues(alpha: 0.12),
                offset: const Offset(0, 6),
                blurRadius: 18)
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          PageImage(page.pagePath(doc.dir), fit: BoxFit.cover, cacheWidth: 500),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 28,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: AppColors.text.withValues(alpha: 0.4),
                  alignment: Alignment.center,
                  child: Text('${i + 1}', style: ts(13, w600, _white)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _addTile() => Tap(
        onTap: _addPages,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44,
              height: 44,
              decoration:
                  const BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.plus, size: 20, color: AppColors.accentDark),
            ),
            const SizedBox(height: 10),
            Text('Añadir páginas', style: ts(14, w600, AppColors.accentDark)),
          ]),
        ),
      );
}

// ───────────────────────── 10 · Ordenar páginas ─────────────────────────

class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.store, required this.doc});
  final Store store;
  final ScanDoc doc;
  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final List<ScanPage> order = [...widget.doc.pages];

  Future<void> _done() async {
    final doc = widget.doc;
    final removed = doc.pages.where((p) => !order.contains(p)).toList();
    for (final p in removed) {
      await widget.store.deletePage(doc, p);
    }
    doc.pages
      ..clear()
      ..addAll(order);
    await widget.store.saveDoc(doc);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final doc = widget.doc;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      child: ListView(padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 24), children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            Tap(
                minSize: 44,
                onTap: () => Navigator.pop(context),
                child: Text('Cancelar', style: ts(17, w400, AppColors.accentDark))),
            Expanded(
                child: Text('Ordenar páginas',
                    textAlign: TextAlign.center, style: ts(17, w600))),
            Tap(
              onTap: _done,
              child: Container(
                width: 80,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.accentDark, borderRadius: BorderRadius.circular(22)),
                child: Text('Listo', style: ts(16, w600, _white)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 0, 8),
          child: Text('MANTÉN PULSADO Y ARRASTRA PARA REORDENAR', style: ts(12, w400, AppColors.muted)),
        ),
        Container(
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.text.withValues(alpha: 0.05),
                  offset: const Offset(0, 2),
                  blurRadius: 8)
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ReorderableList(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.length,
            onReorderItem: (from, to) => setState(() {
              final p = order.removeAt(from);
              order.insert(to, p);
            }),
            proxyDecorator: (child, index, animation) => Container(
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.22),
                      offset: const Offset(0, 5),
                      blurRadius: 18)
                ],
              ),
              child: child,
            ),
            itemBuilder: (context, i) {
              final page = order[i];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(page.id),
                index: i,
                child: Container(
                  height: 86,
                  decoration: BoxDecoration(
                    color: _white,
                    border: i == order.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: AppColors.separator)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    if (order.length > 1)
                      Tap(
                        label: 'Quitar página ${i + 1}',
                        minSize: 44,
                        onTap: () => setState(() => order.remove(page)),
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.destructive, shape: BoxShape.circle),
                          child: Container(width: 12, height: 2, color: _white),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Container(
                      width: 44,
                      height: 62,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.separator)),
                      clipBehavior: Clip.antiAlias,
                      child: PageImage(page.pagePath(doc.dir), cacheWidth: 140),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Página ${i + 1}', style: ts(16, w600)),
                            const SizedBox(height: 2),
                            Text('Filtro: ${page.filter.label}', style: ts(13, w400, AppColors.muted)),
                          ]),
                    ),
                    const Icon(CupertinoIcons.line_horizontal_3, size: 18, color: AppColors.tertiary),
                  ]),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 0, 0),
          child: Text('El orden se usa al exportar el PDF.', style: ts(13, w400, AppColors.muted)),
        ),
      ]),
    );
  }
}

// ───────────────────────── 11 · Visor ─────────────────────────

class PageViewer extends StatefulWidget {
  const PageViewer({super.key, required this.store, required this.doc, required this.initial});
  final Store store;
  final ScanDoc doc;
  final int initial;

  @override
  State<PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<PageViewer> {
  late final PageController controller =
      PageController(initialPage: widget.initial, viewportFraction: 0.92);
  late int index = widget.initial;
  bool showHelp = true;
  Timer? helpTimer;

  Store get store => widget.store;
  ScanDoc get doc => widget.doc;
  ScanPage get page => doc.pages[index];

  @override
  void initState() {
    super.initState();
    helpTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => showHelp = false);
    });
  }

  @override
  void dispose() {
    helpTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<CapturedPage> _draft() async {
    final photo = await File(page.originalPath(doc.dir)).readAsBytes();
    return CapturedPage(photo, List.of(page.corners))
      ..rotation = page.rotation
      ..filter = page.filter;
  }

  Future<void> _recrop() async {
    final draft = await _draft();
    if (!mounted) return;
    final cropped = await Navigator.push<bool>(
        context, CupertinoPageRoute(builder: (_) => CropScreen(pages: [draft], store: store, canDelete: false)));
    if (cropped != true || !mounted) return;
    final filtered = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
            builder: (_) => FilterScreen(pages: [draft], store: store, title: doc.name)));
    if (filtered != true || !mounted) return;
    page
      ..corners = draft.corners
      ..rotation = draft.rotation
      ..filter = draft.filter;
    await withProgress(context, 'Guardando…', () => store.renderPage(doc, page),
        subtitle: pagesSubtitle(1, store.settings));
    if (mounted) setState(() {});
  }

  Future<void> _filter() async {
    final draft = await _draft();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
            builder: (_) => FilterScreen(pages: [draft], store: store, title: doc.name)));
    if (ok != true || !mounted) return;
    page.filter = draft.filter;
    await withProgress(context, 'Guardando…', () => store.renderPage(doc, page),
        subtitle: pagesSubtitle(1, store.settings));
    if (mounted) setState(() {});
  }

  Future<void> _rotate() async {
    page.rotation = (page.rotation + 1) % 4;
    await withProgress(context, 'Girando…', () => store.renderPage(doc, page));
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    if (!await confirm(context, '¿Eliminar la página ${index + 1}?', 'No se puede deshacer.')) {
      return;
    }
    final wasLast = doc.pages.length == 1;
    await store.deletePage(doc, page);
    if (!mounted) return;
    if (wasLast) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    setState(() => index = index.clamp(0, doc.pages.length - 1));
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(page.pagePath(doc.dir), mimeType: 'image/jpeg', name: '${safeFileName(doc.name)}_${index + 1}.jpg')],
      subject: doc.name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final n = doc.pages.length;
        return CupertinoPageScaffold(
          backgroundColor: AppColors.viewerBg,
          child: Stack(children: [
            Positioned.fill(
              top: pad.top + 64,
              bottom: pad.bottom + 150,
              child: PageView.builder(
                controller: controller,
                itemCount: n,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x80000000), offset: Offset(0, 16), blurRadius: 36)
                          ],
                        ),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: PageImage(doc.pages[i].pagePath(doc.dir), fit: BoxFit.contain)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: pad.top + 6,
              left: 16,
              right: 16,
              child: Row(children: [
                GlassIconButton(
                    label: 'Volver',
                    icon: CupertinoIcons.chevron_left,
                    style: GlassStyle.subtle,
                    iconSize: 18,
                    onTap: () => Navigator.pop(context)),
                const Spacer(),
                Container(
                  height: 27,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(14)),
                  child: Text('${index + 1} / $n', style: ts(14, w600, _white)),
                ),
                const Spacer(),
                GlassIconButton(
                    label: 'Compartir',
                    icon: CupertinoIcons.share,
                    style: GlassStyle.subtle,
                    onTap: _share),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 118,
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < n && n <= 12; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == index ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: i == index ? _white : const Color(0x59FFFFFF),
                          borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  opacity: showHelp ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Text('Desliza para cambiar de página · Pellizca para ampliar',
                      style: ts(12, w400, const Color(0x73FFFFFF))),
                ),
              ]),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: pad.bottom + 8,
              child: FloatingActionBar(dark: true, actions: [
                BarAction(CupertinoIcons.crop_rotate, 'Recortar', _recrop),
                BarAction(CupertinoIcons.wand_stars, 'Filtro', _filter),
                BarAction(CupertinoIcons.rotate_right, 'Girar', _rotate),
                BarAction(CupertinoIcons.trash, 'Eliminar', _delete,
                    color: AppColors.destructiveOnDark),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
