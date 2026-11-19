// The home screen (01 list / 02 grid): every document on the device.
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import 'export.dart';
import 'scan_flow.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_doc.dart';
import 'ui_edit.dart';
import 'ui_misc.dart';
import 'widgets/widgets.dart';
import 'l10n.dart';

String _two(int v) => v.toString().padLeft(2, '0');

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hoy · 10:30", "Ayer · 18:05", "12 nov 2026 · 18:05".
String homeDate(DateTime d, {bool withTime = true}) {
  final now = DateTime.now();
  final time = '${_two(d.hour)}:${_two(d.minute)}';
  String day;
  if (_sameDay(d, now)) {
    day = t('Hoy');
  } else if (_sameDay(d, now.subtract(const Duration(days: 1)))) {
    day = t('Ayer');
  } else {
    day = '${d.day} ${monthsShort[d.month - 1]} ${d.year}';
  }
  return withTime ? '$day · $time' : day;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final Store store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String query = '';
  Store get store => widget.store;
  bool get grid => store.settings.gridView;

  List<ScanDoc> get visible {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return store.docs;
    return store.docs
        .where((d) => d.name.toLowerCase().contains(q) || d.text.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _scan(ScanSource source) async {
    final doc = await scanPages(context, store, source: source);
    if (doc != null && mounted) _open(doc);
  }

  void _open(ScanDoc doc) => Navigator.push(
      context, CupertinoPageRoute(builder: (_) => DocScreen(store: store, doc: doc)));

  void _toggleGrid() {
    store.settings.gridView = !store.settings.gridView;
    store.saveSettings();
  }

  Future<void> _menu(ScanDoc doc) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(doc.name),
        actions: [
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'rename'), child: Text(t('Cambiar nombre'))),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'pdf'), child: Text(t('Compartir PDF'))),
          CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text(t('Eliminar'))),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: Text(t('Cancelar'))),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await askName(context, doc.name);
        if (name != null) {
          doc.name = name;
          await store.saveDoc(doc);
        }
      case 'pdf':
        await withProgress(
            context, t('Creando PDF…'), () => exportPdf(doc, store.settings.pageSize, share: true),
            subtitle: pagesSubtitle(doc.pages.length, store.settings));
      case 'delete':
        if (await confirm(context, t('¿Eliminar «{name}»?', {'name': doc.name}),
            t('Se borrará de este {device} y no se puede deshacer.', {'device': deviceWord}))) {
          await store.deleteDoc(doc);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final docs = visible;
        return CupertinoPageScaffold(
          backgroundColor: AppColors.background,
          child: Stack(children: [
            CustomScrollView(slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _TopBar(
                  top: pad.top,
                  grid: grid,
                  onGrid: _toggleGrid,
                  onSettings: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => SettingsScreen(store: store))),
                ),
              ),
              SliverToBoxAdapter(child: _header(docs.length)),
              if (docs.isEmpty)
                SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      searching: query.trim().isNotEmpty,
                      onScan: () => _scan(isMobile ? ScanSource.camera : ScanSource.gallery),
                      onImport: () => _scan(ScanSource.gallery),
                    ))
              else if (grid)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 170),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 18,
                        childAspectRatio: 174 / 261),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _DocTile(
                          doc: docs[i], onTap: () => _open(docs[i]), onMenu: () => _menu(docs[i])),
                      childCount: docs.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 170),
                  sliver: SliverToBoxAdapter(
                    child: GroupedCard(children: [
                      for (var i = 0; i < docs.length; i++)
                        _DocRow(
                            doc: docs[i],
                            last: i == docs.length - 1,
                            onTap: () => _open(docs[i]),
                            onMenu: () => _menu(docs[i])),
                    ]),
                  ),
                ),
            ]),
            // Fade under the buttons
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 162 + pad.bottom,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.55, 1],
                      colors: [
                        AppColors.background.withValues(alpha: 0),
                        AppColors.background.withValues(alpha: 0.9),
                        AppColors.background
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: pad.bottom + 34,
              left: width / 2 - 36 - 24 - 52,
              child: GlassFab(
                  label: t('Importar imágenes'),
                  icon: CupertinoIcons.photo_on_rectangle,
                  onTap: () => _scan(ScanSource.gallery)),
            ),
            Positioned(
              bottom: pad.bottom + 24,
              left: width / 2 - 36,
              child: ScanFab(
                  onTap: () => _scan(isMobile ? ScanSource.camera : ScanSource.gallery)),
            ),
          ]),
        );
      },
    );
  }

  /// Large title, search, privacy pill and list header. The buttons live in the
  /// pinned [_TopBar] so they stay reachable once documents fill the screen.
  Widget _header(int count) {
    final hasDocs = store.docs.isNotEmpty;
    final searching = query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(header: true, child: Text(t('Mis documentos'), style: ts(34, w700)))),
        const SizedBox(height: 14),
        // With nothing saved yet there is nothing to search: the empty state leads.
        if (hasDocs) ...[
          SizedBox(
            height: 44,
            child: CupertinoSearchTextField(
              placeholder: t('Buscar por nombre o texto'),
              placeholderStyle: ts(16, w400, AppColors.muted),
              style: ts(16, w400),
              backgroundColor: AppColors.fillQuaternary,
              borderRadius: BorderRadius.circular(22),
              itemColor: AppColors.muted,
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          const SizedBox(height: 12),
        ],
        PrivacyPill(text: t('Sin anuncios · Sin nube · Todo queda en tu {device}', {'device': deviceWord})),
        if (hasDocs) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(searching ? t('Resultados') : t('Recientes'), style: ts(20, w700)),
              const Spacer(),
              Text(
                  searching
                      ? '$count ${plural(count, 'resultado', 'resultados')}'
                      : '$count ${plural(count, 'documento', 'documentos')}',
                  style: ts(14, w400, AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 14),
        ],
      ]),
    );
  }
}

/// Pinned bar: logo and the two toolbar buttons; the page title fades in here
/// once the large title scrolls away (iOS large-title behaviour).
class _TopBar extends SliverPersistentHeaderDelegate {
  _TopBar({required this.top, required this.grid, required this.onGrid, required this.onSettings});
  final double top;
  final bool grid;
  final VoidCallback onGrid, onSettings;

  @override
  double get minExtent => top + 56;
  @override
  double get maxExtent => top + 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final p = ((shrinkOffset - 40) / 40).clamp(0.0, 1.0);
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 4, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.92 * p + 0.0),
        border: Border(
            bottom: BorderSide(color: AppColors.separator.withValues(alpha: p))),
      ),
      child: Row(children: [
        const SizedBox(width: 4),
        const AppLogo(),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(alignment: Alignment.centerLeft, children: [
            Opacity(opacity: 1 - p, child: Text('Escáner Local', style: ts(16, w600))),
            Opacity(opacity: p, child: Text(t('Mis documentos'), style: ts(17, w600))),
          ]),
        ),
        GlassIconButton(
            label: grid ? t('Ver como lista') : t('Ver como cuadrícula'),
            icon: grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
            onTap: onGrid),
        const SizedBox(width: 4),
        GlassIconButton(label: t('Ajustes'), icon: CupertinoIcons.gear_alt, onTap: onSettings),
      ]),
    );
  }

  @override
  bool shouldRebuild(covariant _TopBar old) => old.grid != grid || old.top != top;
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching, required this.onScan, required this.onImport});
  final bool searching;
  final VoidCallback onScan, onImport;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(
              child: Icon(searching ? CupertinoIcons.search : CupertinoIcons.doc_text_viewfinder,
                  size: 64, color: searching ? AppColors.tertiary : AppColors.accentDark),
            ),
            const SizedBox(height: 16),
            Text(searching ? t('Nada coincide con la búsqueda') : t('Escanea tu primer documento'),
                textAlign: TextAlign.center, style: ts(20, w700)),
            const SizedBox(height: 6),
            if (!searching) ...[
              Text(t('Apunta la cámara a una hoja: detectamos los bordes y la dejamos lista como PDF.'),
                  textAlign: TextAlign.center, style: ts(15, w400, AppColors.muted, 1.35)),
              const SizedBox(height: 24),
              PrimaryButton(
                  label: t('Escanear documento'), icon: CupertinoIcons.camera_fill, onTap: onScan),
              const SizedBox(height: 4),
              Tap(
                minSize: 48,
                onTap: onImport,
                child: Text(t('Importar de la galería'), style: ts(16, w600, AppColors.accentDark)),
              ),
            ],
          ]),
        ),
      );
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.doc, required this.last, required this.onTap, required this.onMenu});
  final ScanDoc doc;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final cover = doc.cover;
    return Tap(
      onTap: onTap,
      onLongPress: onMenu,
      child: SizedBox(
        height: 92,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Row(children: [
              Container(
                width: 52,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.separator),
                  color: AppColors.surface,
                ),
                clipBehavior: Clip.antiAlias,
                child: cover == null ? null : PageImage(cover.path, cacheWidth: 160),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w600)),
                      const SizedBox(height: 4),
                      Text(homeDate(doc.modified), style: ts(13, w400, AppColors.muted)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Icon(CupertinoIcons.doc_on_doc, size: 11, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text('${doc.pages.length}', style: ts(13, w600, AppColors.muted)),
                        if (doc.text.isNotEmpty) ...[const SizedBox(width: 8), const TextChip()],
                      ]),
                    ]),
              ),
              Tap(
                label: t('Más opciones de {name}', {'name': doc.name}),
                onTap: onMenu,
                child: const SizedBox(
                  width: 48,
                  height: 92,
                  child: Center(child: _Dots()),
                ),
              ),
            ]),
          ),
          if (!last)
            Positioned(
                left: 82, right: 0, bottom: 0, child: SizedBox(height: 1, child: ColoredBox(color: AppColors.separator))),
        ]),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(color: AppColors.tertiary, shape: BoxShape.circle)),
      ]);
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc, required this.onTap, required this.onMenu});
  final ScanDoc doc;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final cover = doc.cover;
    return Tap(
      onTap: onTap,
      onLongPress: onMenu,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadow.withValues(alpha: 0.05),
                    offset: const Offset(0, 2),
                    blurRadius: 8)
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: cover == null
                    ? const SizedBox()
                    : PageImage(cover.path, cacheWidth: 400),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: AppColors.text.withValues(alpha: 0.6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(CupertinoIcons.doc_on_doc, size: 10, color: CupertinoColors.white),
                        const SizedBox(width: 4),
                        Text('${doc.pages.length}',
                            style: ts(12, w600, CupertinoColors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 3),
        Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w600)),
        Text(homeDate(doc.modified, withTime: false), style: ts(12, w400, AppColors.muted)),
      ]),
    );
  }
}
