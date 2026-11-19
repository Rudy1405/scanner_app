// Taking or importing photos and turning them into pages (flows A and B).
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'export.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_camera.dart';
import 'ui_edit.dart';
import 'widgets/widgets.dart';
import 'l10n.dart';

enum ScanSource { camera, gallery }

/// Sheet to choose camera or gallery (screen 03). Used from "Añadir páginas".
Future<ScanSource?> askSource(BuildContext context, {bool adding = false}) {
  return showCupertinoModalPopup<ScanSource>(
    context: context,
    barrierColor: scrim(0.4),
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      Widget row(IconData icon, bool primary, String title, String sub, ScanSource s) => Tap(
            onTap: () => Navigator.pop(ctx, s),
            child: Container(
              height: 84,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                  color: AppColors.background, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: primary ? AppColors.primaryGradient : null,
                    color: primary ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 24, color: primary ? CupertinoColors.white : AppColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: ts(16, w600)),
                        const SizedBox(height: 2),
                        Text(sub, style: ts(13, w400, AppColors.muted)),
                      ]),
                ),
                Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.tertiary),
              ]),
            ),
          );
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, bottom + 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(38),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.2),
                  offset: const Offset(0, -4),
                  blurRadius: 30)
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 37,
                height: 5,
                decoration: BoxDecoration(
                    color: AppColors.grabber, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 18),
            Text(adding ? t('Añadir páginas') : t('Nuevo documento'), style: ts(20, w700)),
            const SizedBox(height: 16),
            if (isMobile) ...[
              row(CupertinoIcons.camera_fill, true, t('Escanear con la cámara'),
                  t('Varias páginas seguidas, bordes automáticos'), ScanSource.camera),
              const SizedBox(height: 10),
            ],
            row(CupertinoIcons.photo_on_rectangle, false, t('Importar imágenes'),
                t('Elige una o varias fotos de tu galería'), ScanSource.gallery),
            const SizedBox(height: 12),
            SecondaryButton(label: t('Cancelar'), onTap: () => Navigator.pop(ctx)),
          ]),
        ),
      );
    },
  );
}

/// Gallery (phone) or file picker (computer); several images.
Future<List<Uint8List>> pickGallery() async {
  if (isMobile) {
    final shots = await ImagePicker().pickMultiImage(imageQuality: 95);
    return [for (final s in shots) await s.readAsBytes()];
  }
  final files = await openFiles(acceptedTypeGroups: [
    XTypeGroup(label: t('Imágenes'), extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp']),
  ]);
  return [for (final f in files) await f.readAsBytes()];
}

/// Full scan: camera or gallery → crop → filter → save. Returns the document.
Future<ScanDoc?> scanPages(BuildContext context, Store store,
    {ScanDoc? into, ScanSource? source}) async {
  source ??= await askSource(context, adding: into != null);
  if (source == null || !context.mounted) return null;

  var pages = <CapturedPage>[];
  if (source == ScanSource.gallery) {
    final photos = await pickGallery();
    if (photos.isEmpty || !context.mounted) return null;
    final pending = photos;
    pages = await withProgress(context, t('Procesando {n} páginas…', {'n': pending.length}), () async {
      final out = <CapturedPage>[];
      for (final p in pending) {
        final (corners, blurry) = await checkPhotoAsync(p, autoCrop: store.settings.autoCrop);
        out.add(CapturedPage(p, corners)..blurry = blurry);
      }
      return out;
    }, subtitle: pagesSubtitle(pending.length, store.settings));
  }

  var step = source == ScanSource.camera ? 0 : 1;
  while (true) {
    if (!context.mounted) return null;
    if (step == 0) {
      final got = await Navigator.push<List<CapturedPage>>(
          context,
          CupertinoPageRoute(
              fullscreenDialog: true,
              builder: (_) => CameraScanScreen(store: store, initial: pages)));
      if (got == null || got.isEmpty) return null;
      pages = got;
      step = 1;
    } else if (step == 1) {
      for (final p in pages) {
        p.filter = store.settings.defaultFilter;
      }
      final ok = await Navigator.push<bool>(
          context, CupertinoPageRoute(builder: (_) => CropScreen(pages: pages, store: store)));
      if (ok != true) {
        if (source == ScanSource.camera) {
          step = 0;
          continue;
        }
        return null;
      }
      step = 2;
    } else {
      final ok = await Navigator.push<bool>(
          context,
          CupertinoPageRoute(
              builder: (_) => FilterScreen(
                  pages: pages, store: store, title: into?.name ?? t('Nuevo documento'))));
      if (ok != true) {
        step = 1;
        continue;
      }
      break;
    }
  }
  if (!context.mounted) return null;

  final toSave = pages;
  final progress = ValueNotifier<double?>(0);
  return withProgress(context, t('Guardando…'), () async {
    final doc = into ?? await store.createDoc();
    for (var i = 0; i < toSave.length; i++) {
      final p = toSave[i];
      await store.addPage(doc, p.photo, corners: p.corners, rotation: p.rotation, filter: p.filter);
      progress.value = (i + 1) / toSave.length;
    }
    await store.saveDoc(doc);
    return doc;
  }, subtitle: pagesSubtitle(toSave.length, store.settings), progress: progress);
}

/// "2 páginas · A4".
String pagesSubtitle(int n, Settings s) {
  final size = s.pageSize == PdfPageSize.fit ? t('Ajustar') : s.pageSize.label;
  return '$n ${plural(n, 'página', 'páginas')} · $size';
}

/// Progress card over the screen. [progress] null → spinning ring.
Future<T> withProgress<T>(BuildContext context, String text, Future<T> Function() work,
    {String? subtitle, ValueListenable<double?>? progress}) async {
  showCupertinoDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: scrim(0.2),
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: progress == null
            ? HudCard(text: text, subtitle: subtitle)
            : ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (_, v, _) => HudCard(text: text, subtitle: subtitle, progress: v),
              ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
