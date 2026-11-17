// Making PDFs and sharing or saving them, all on the device.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'store.dart';

bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'documento' : cleaned;
}

Future<Uint8List> buildPdf(ScanDoc doc, PdfPageSize size) async {
  final pdf = pw.Document(title: doc.name, creator: 'Escaner Local');
  for (final page in doc.pages) {
    final bytes = await File(page.pagePath(doc.dir)).readAsBytes();
    final image = pw.MemoryImage(bytes);
    PdfPageFormat format;
    switch (size) {
      case PdfPageSize.a4:
        format = PdfPageFormat.a4;
      case PdfPageSize.letter:
        format = PdfPageFormat.letter;
      case PdfPageSize.fit:
        final decoded = img.decodeJpg(bytes);
        final w = (decoded?.width ?? 595).toDouble();
        final h = (decoded?.height ?? 842).toDouble();
        // 150 dpi equivalent.
        format = PdfPageFormat(w * 72 / 150, h * 72 / 150);
    }
    pdf.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));
  }
  return pdf.save();
}

Future<File> _tempFile(String name) async {
  final dir = await getTemporaryDirectory();
  return File('${dir.path}${Platform.pathSeparator}$name');
}

/// Shares the document as a PDF (mobile share sheet) or asks where to save it
/// (computer).
Future<String?> exportPdf(ScanDoc doc, PdfPageSize size, {required bool share}) async {
  final bytes = await buildPdf(doc, size);
  final name = '${safeFileName(doc.name)}.pdf';
  if (share && isMobile) {
    final f = await _tempFile(name);
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/pdf')],
      subject: doc.name,
    ));
    return null;
  }
  return _saveBytes(bytes, name, 'PDF', ['pdf']);
}

/// Shares or saves every page as a JPG picture.
Future<String?> exportImages(ScanDoc doc, {required bool share}) async {
  final files = <XFile>[];
  for (var i = 0; i < doc.pages.length; i++) {
    files.add(XFile(doc.pages[i].pagePath(doc.dir), mimeType: 'image/jpeg',
        name: '${safeFileName(doc.name)}_${i + 1}.jpg'));
  }
  if (share && isMobile) {
    await SharePlus.instance.share(ShareParams(files: files, subject: doc.name));
    return null;
  }
  if (isMobile) {
    await SharePlus.instance.share(ShareParams(files: files, subject: doc.name));
    return null;
  }
  final folder = await getDirectoryPath(confirmButtonText: 'Guardar aquí');
  if (folder == null) return null;
  for (var i = 0; i < files.length; i++) {
    final target = File('$folder${Platform.pathSeparator}${safeFileName(doc.name)}_${i + 1}.jpg');
    await File(files[i].path).copy(target.path);
  }
  return folder;
}

Future<String?> exportText(String text, String name, {required bool share}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final fileName = '${safeFileName(name)}.txt';
  if (share && isMobile) {
    await SharePlus.instance.share(ShareParams(text: text, subject: name));
    return null;
  }
  return _saveBytes(bytes, fileName, 'Texto', ['txt']);
}

Future<String?> _saveBytes(Uint8List bytes, String name, String label, List<String> ext) async {
  if (isMobile) {
    // On phones the share sheet also offers "Save to Files".
    final f = await _tempFile(name);
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    return null;
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: ext)],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}
