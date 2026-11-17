// Settings, text recognition and the small dialogs (screens 12–16).
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'export.dart';
import 'processing.dart';
import 'scan_flow.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

/// "tu iPhone" / "tu teléfono".
String get deviceWord => Platform.isIOS ? 'iPhone' : 'teléfono';

// ───────────────────────── Dialogs (14, 15) ─────────────────────────

Widget _dialogButton(String label, VoidCallback? onTap,
    {bool bold = false, bool destructive = false}) {
  return CupertinoDialogAction(
    onPressed: onTap,
    isDefaultAction: bold,
    isDestructiveAction: destructive,
    textStyle: ts(17, bold || destructive ? w600 : w400,
        destructive ? AppColors.destructive : AppColors.accentDark),
    child: Text(label),
  );
}

Future<String?> askName(BuildContext context, String current) {
  return showCupertinoDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _NameDialog(current: current),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.current});
  final String current;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final controller = TextEditingController(text: widget.current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.current.length);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text('Cambiar nombre', style: ts(17, w600)),
      content: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(children: [
          Text('Escribe un nombre para este documento.',
              style: ts(13, w400, AppColors.alertBody), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          CupertinoTextField(
            controller: controller,
            autofocus: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            style: ts(15, w400),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.separator),
            ),
            onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(context, v.trim()),
          ),
        ]),
      ),
      actions: [
        _dialogButton('Cancelar', () => Navigator.pop(context)),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, _) => _dialogButton(
              'Guardar',
              v.text.trim().isEmpty ? null : () => Navigator.pop(context, v.text.trim()),
              bold: true),
        ),
      ],
    );
  }
}

/// Destructive confirmation (screen 15).
Future<bool> confirm(BuildContext context, String title, String body,
    {String action = 'Eliminar'}) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Column(children: [
        Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(bottom: 12),
          decoration:
              const BoxDecoration(color: AppColors.destructiveTint, shape: BoxShape.circle),
          child: const Icon(CupertinoIcons.trash, size: 22, color: AppColors.destructive),
        ),
        Text(title, style: ts(17, w600), textAlign: TextAlign.center),
      ]),
      content: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(body, style: ts(13, w400, AppColors.alertBody), textAlign: TextAlign.center),
      ),
      actions: [
        _dialogButton('Cancelar', () => Navigator.pop(context, false)),
        _dialogButton(action, () => Navigator.pop(context, true), destructive: true),
      ],
    ),
  );
  return ok ?? false;
}

// ───────────────────────── Settings (13) ─────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final Store store;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings get s => widget.store.settings;
  String? storage; // "3 documentos · 12,4 MB"

  @override
  void initState() {
    super.initState();
    _measure();
  }

  /// Size of everything the app keeps, so the user sees what lives on the phone.
  Future<void> _measure() async {
    var bytes = 0;
    try {
      await for (final e in widget.store.root.list(recursive: true)) {
        if (e is File) bytes += await e.length();
      }
    } catch (_) {}
    final n = widget.store.docs.length;
    final mb = bytes / (1024 * 1024);
    final size = mb < 0.1 ? 'menos de 1 MB' : '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
    if (mounted) setState(() => storage = '$n ${n == 1 ? 'documento' : 'documentos'} · $size');
  }

  Future<void> _save() async {
    await widget.store.saveSettings();
    if (mounted) setState(() {});
  }

  Future<void> _pickFilter() async {
    final picked = await showCupertinoModalPopup<PageFilter>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Filtro por defecto'),
        actions: [
          for (final f in PageFilter.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, f),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (f == s.defaultFilter)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16, color: AppColors.accent),
                  ),
                Text(f.label),
              ]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      ),
    );
    if (picked != null) {
      s.defaultFilter = picked;
      _save();
    }
  }

  Widget _row(String label, Widget trailing, {VoidCallback? onTap, String? sub}) => Tap(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: ts(16, w400)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: ts(13, w400, AppColors.muted, 1.3)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            trailing,
          ]),
        ),
      );

  Widget _switch(bool v, ValueChanged<bool> onChanged) => CupertinoSwitch(
      value: v, activeTrackColor: AppColors.accent, onChanged: onChanged);

  Widget _iconRow(Widget icon, String title, {String? sub}) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(16, w400)),
              if (sub != null) Text(sub, style: ts(13, w400, AppColors.muted)),
            ]),
          ),
        ]),
      );

  Widget _badge(IconData i, Color bg, Color fg) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(i, size: 16, color: fg),
      );

  @override
  Widget build(BuildContext context) {
    final seg = <PdfPageSize, Widget>{
      PdfPageSize.a4: Text('A4', style: ts(14, w600)),
      PdfPageSize.letter: Text('Carta', style: ts(14, w400)),
      PdfPageSize.fit: Text('Ajustar', style: ts(14, w400)),
    };
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      child: ListView(padding: EdgeInsets.zero, children: [
        LargeHeader(
          title: 'Ajustes',
          trailing: [
            GlassIconButton(
                label: 'Cerrar', icon: CupertinoIcons.xmark, onTap: () => Navigator.pop(context)),
          ],
        ),
        const SectionHeader('Escaneo'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GroupedCard(separatorInset: 16, children: [
            _row('Detectar bordes automáticamente', _switch(s.autoCrop, (v) {
              s.autoCrop = v;
              _save();
            }), sub: 'Recorta la hoja sola; luego puedes ajustarla.'),
            _row('Captura automática', _switch(s.autoCapture, (v) {
              s.autoCapture = v;
              _save();
            }), sub: 'Hace la foto cuando la hoja está quieta.'),
            _row(
              'Filtro por defecto',
              Row(children: [
                Text(s.defaultFilter.label, style: ts(16, w400, AppColors.muted)),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.tertiary),
              ]),
              onTap: _pickFilter,
            ),
          ]),
        ),
        const SectionHeader('PDF e imágenes'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GroupedCard(separatorInset: 16, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tamaño de página', style: ts(16, w400)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<PdfPageSize>(
                    groupValue: s.pageSize,
                    children: seg,
                    onValueChanged: (v) {
                      if (v == null) return;
                      s.pageSize = v;
                      _save();
                    },
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Calidad', style: ts(16, w400))),
                  Text('${s.jpegQuality} %', style: ts(16, w600, AppColors.accentDark)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text('50', style: ts(12, w400, AppColors.tertiary)),
                  Expanded(
                    child: CupertinoSlider(
                      value: s.jpegQuality.toDouble(),
                      min: 50,
                      max: 95,
                      divisions: 9,
                      activeColor: AppColors.accent,
                      onChanged: (v) => setState(() => s.jpegQuality = v.round()),
                      onChangeEnd: (_) => _save(),
                    ),
                  ),
                  Text('95', style: ts(12, w400, AppColors.tertiary)),
                ]),
              ]),
            ),
          ]),
        ),
        const SectionHeader('Privacidad'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GroupedCard(separatorInset: 60, children: [
            _iconRow(_badge(CupertinoIcons.lock_fill, AppColors.accent, CupertinoColors.white),
                'Todo se guarda en este dispositivo'),
            // Plain language; the technical path is only a long-press away.
            Tap(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: widget.store.root.path));
                showToast(context, 'Ruta copiada');
              },
              child: _iconRow(
                  _badge(CupertinoIcons.folder, AppColors.accentTint, AppColors.accentDark),
                  'Privado en esta app',
                  sub: storage ?? 'Calculando…'),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        Center(
            child: Text('Escáner Local 1.0\nSin anuncios · Sin cuentas · Sin nube',
                textAlign: TextAlign.center, style: ts(12, w400, AppColors.tertiary, 1.5))),
        // Close within thumb reach (the X at the top is hard to hit one-handed).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SecondaryButton(label: 'Cerrar', onTap: () => Navigator.pop(context)),
        ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom + 30),
      ]),
    );
  }
}

// ───────────────────────── Text / OCR (12) ─────────────────────────

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.store, required this.doc});
  final Store store;
  final ScanDoc doc;
  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  late final TextEditingController controller = TextEditingController(text: widget.doc.text);
  bool busy = false;

  Future<void> _recognise() async {
    if (!isMobile) {
      showToast(context, 'El reconocimiento de texto funciona en Android y iPhone.');
      return;
    }
    setState(() => busy = true);
    final doc = widget.doc;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await withProgress(context, 'Reconociendo texto…', () async {
        final parts = <String>[];
        for (var i = 0; i < doc.pages.length; i++) {
          final result = await recognizer
              .processImage(InputImage.fromFilePath(doc.pages[i].pagePath(doc.dir)));
          parts.add(doc.pages.length > 1 ? '— Página ${i + 1} —\n${result.text}' : result.text);
        }
        controller.text = parts.join('\n\n');
        doc.text = controller.text;
        await widget.store.saveDoc(doc);
      }, subtitle: pagesSubtitle(doc.pages.length, widget.store.settings));
    } finally {
      await recognizer.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = controller.text.trim().isEmpty;
    final shortName = widget.doc.name.length > 18
        ? '${widget.doc.name.substring(0, 18).trim()}…'
        : widget.doc.name;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 8, 20, 0),
          child: SizedBox(
            height: 44,
            child: Row(children: [
              BackLink(label: shortName, onTap: () => Navigator.pop(context)),
              const Spacer(),
              GlassIconButton(
                label: 'Copiar texto',
                icon: CupertinoIcons.doc_on_doc,
                onTap: empty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: controller.text));
                        showToast(context, 'Copiado');
                      },
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                label: 'Compartir texto',
                icon: CupertinoIcons.share,
                onTap: empty
                    ? null
                    : () => exportText(controller.text, widget.doc.name, share: true),
              ),
            ]),
          ),
        ),
        Align(
            alignment: Alignment.centerLeft,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Text('Texto', style: ts(34, w700)))),
        Expanded(
          child: empty && !busy ? _empty() : _editor(),
        ),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.text_cursor, size: 56, color: AppColors.tertiary),
            const SizedBox(height: 14),
            Text('Aún no se ha reconocido el texto', style: ts(17, w600)),
            const SizedBox(height: 18),
            PrimaryButton(
                label: 'Reconocer texto',
                height: 50,
                icon: CupertinoIcons.wand_stars,
                expand: false,
                horizontalPadding: 28,
                onTap: busy ? null : _recognise),
            const SizedBox(height: 14),
            const _OfflineNote(),
          ]),
        ),
      );

  Widget _editor() => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PrimaryButton(
              label: 'Volver a reconocer',
              height: 50,
              icon: CupertinoIcons.wand_stars,
              onTap: busy ? null : _recognise),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: _OfflineNote()),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.05),
                      offset: const Offset(0, 2),
                      blurRadius: 8)
                ],
              ),
              child: CupertinoTextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                padding: const EdgeInsets.all(18),
                decoration: null,
                style: ts(15, w400, AppColors.text, 1.4),
                onChanged: (v) => setState(() => widget.doc.text = v),
              ),
            ),
          ),
        ),
      ]);

  @override
  void dispose() {
    widget.store.saveDoc(widget.doc, touch: false);
    controller.dispose();
    super.dispose();
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(CupertinoIcons.lock_fill, size: 11, color: AppColors.muted),
        const SizedBox(width: 6),
        Text('Se hace en el propio dispositivo, sin internet.', style: ts(13, w400, AppColors.muted)),
      ]);
}
