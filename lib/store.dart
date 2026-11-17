// Local storage: every document lives in its own folder on the device, with a
// meta.json, the original photos and the processed pages. Nothing leaves the
// device.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'processing.dart';

enum PdfPageSize { a4, letter, fit }

extension PdfPageSizeLabel on PdfPageSize {
  String get label => switch (this) {
        PdfPageSize.a4 => 'A4',
        PdfPageSize.letter => 'Carta',
        PdfPageSize.fit => 'Ajustar a la imagen',
      };
}

class Settings {
  PageFilter defaultFilter = PageFilter.enhance;
  PdfPageSize pageSize = PdfPageSize.a4;
  int jpegQuality = 85;
  bool autoCrop = true;
  bool autoCapture = true; // camera starts in Auto mode
  bool gridView = false; // home screen: list or grid

  Map<String, dynamic> toJson() => {
        'gridView': gridView,
        'defaultFilter': defaultFilter.name,
        'pageSize': pageSize.name,
        'jpegQuality': jpegQuality,
        'autoCrop': autoCrop,
        'autoCapture': autoCapture,
      };

  void read(Map<String, dynamic> j) {
    defaultFilter = PageFilter.values.firstWhere((f) => f.name == j['defaultFilter'],
        orElse: () => PageFilter.enhance);
    pageSize = PdfPageSize.values
        .firstWhere((f) => f.name == j['pageSize'], orElse: () => PdfPageSize.a4);
    jpegQuality = (j['jpegQuality'] as num?)?.toInt() ?? 85;
    autoCrop = j['autoCrop'] as bool? ?? true;
    autoCapture = j['autoCapture'] as bool? ?? true;
    gridView = j['gridView'] as bool? ?? false;
  }
}

class ScanPage {
  ScanPage({
    required this.id,
    required this.corners,
    this.rotation = 0,
    this.filter = PageFilter.enhance,
  });
  final String id;
  List<double> corners;
  int rotation;
  PageFilter filter;

  String originalPath(Directory dir) => '${dir.path}${Platform.pathSeparator}$id-orig.jpg';
  String pagePath(Directory dir) => '${dir.path}${Platform.pathSeparator}$id.jpg';

  Map<String, dynamic> toJson() =>
      {'id': id, 'corners': corners, 'rotation': rotation, 'filter': filter.name};

  static ScanPage fromJson(Map<String, dynamic> j) => ScanPage(
        id: j['id'] as String,
        corners: (j['corners'] as List).map((e) => (e as num).toDouble()).toList(),
        rotation: (j['rotation'] as num?)?.toInt() ?? 0,
        filter: PageFilter.values
            .firstWhere((f) => f.name == j['filter'], orElse: () => PageFilter.original),
      );
}

class ScanDoc {
  ScanDoc({
    required this.id,
    required this.name,
    required this.created,
    required this.modified,
    required this.dir,
    List<ScanPage>? pages,
    this.text = '',
  }) : pages = pages ?? [];
  final String id;
  String name;
  final DateTime created;
  DateTime modified;
  final Directory dir;
  final List<ScanPage> pages;
  String text; // recognised text (OCR), if any

  File? get cover => pages.isEmpty ? null : File(pages.first.pagePath(dir));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
        'text': text,
      };
}

class Store extends ChangeNotifier {
  Store._(this.root);
  final Directory root;
  final List<ScanDoc> docs = [];
  final Settings settings = Settings();
  int _seq = 0;

  /// Bumped when a page image changes, so pictures reload.
  int revision = 0;

  static Future<Store> open() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}EscanerLocal');
    await root.create(recursive: true);
    final store = Store._(root);
    await store._load();
    return store;
  }

  /// A throw-away store with sample pages, used by the screenshot check so the
  /// person's own documents are never touched.
  static Future<Store> demo() async {
    final root = await Directory.systemTemp.createTemp('escaner_demo_');
    final store = Store._(root);
    final now = DateTime(2026, 11, 14, 10, 30);
    final samples = [
      ('Contrato de alquiler', 3, PageFilter.enhance),
      ('Recibo farmacia', 1, PageFilter.bw),
      ('Apuntes de clase', 4, PageFilter.gray),
      ('Factura luz noviembre', 2, PageFilter.enhance),
    ];
    for (var i = 0; i < samples.length; i++) {
      final (name, pages, filter) = samples[i];
      final doc = await store.createDoc(name: name, at: now.subtract(Duration(days: i * 3, hours: i)));
      for (var p = 0; p < pages; p++) {
        final page = ScanPage(id: store.newId(), corners: const [0, 0, 1, 0, 1, 1, 0, 1], filter: filter);
        final bytes = _samplePage(i * 7 + p, filter);
        await File(page.pagePath(doc.dir)).writeAsBytes(bytes);
        await File(page.originalPath(doc.dir)).writeAsBytes(bytes);
        doc.pages.add(page);
      }
      await store.saveDoc(doc, touch: false);
    }
    return store;
  }

  String newId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq.toRadixString(36)}';
  }

  File get _settingsFile => File('${root.path}${Platform.pathSeparator}settings.json');

  Future<void> _load() async {
    if (await _settingsFile.exists()) {
      try {
        settings.read(jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final meta = File('${entity.path}${Platform.pathSeparator}meta.json');
      if (!await meta.exists()) continue;
      try {
        final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        docs.add(ScanDoc(
          id: j['id'] as String,
          name: j['name'] as String,
          created: DateTime.parse(j['created'] as String),
          modified: DateTime.parse(j['modified'] as String),
          dir: entity,
          pages: (j['pages'] as List).map((e) => ScanPage.fromJson(e as Map<String, dynamic>)).toList(),
          text: j['text'] as String? ?? '',
        ));
      } catch (_) {}
    }
    _sort();
  }

  void _sort() => docs.sort((a, b) => b.modified.compareTo(a.modified));

  Future<void> saveSettings() async {
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
    notifyListeners();
  }

  Future<ScanDoc> createDoc({String? name, DateTime? at}) async {
    final id = newId();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    await dir.create(recursive: true);
    final when = at ?? DateTime.now();
    final doc = ScanDoc(
      id: id,
      name: name ?? 'Escaneo ${_stamp(when)}',
      created: when,
      modified: when,
      dir: dir,
    );
    docs.add(doc);
    return doc;
  }

  Future<void> saveDoc(ScanDoc doc, {bool touch = true}) async {
    if (touch) doc.modified = DateTime.now();
    await File('${doc.dir.path}${Platform.pathSeparator}meta.json')
        .writeAsString(jsonEncode(doc.toJson()));
    revision++;
    _sort();
    notifyListeners();
  }

  Future<void> deleteDoc(ScanDoc doc) async {
    docs.remove(doc);
    if (await doc.dir.exists()) await doc.dir.delete(recursive: true);
    notifyListeners();
  }

  Future<void> deletePage(ScanDoc doc, ScanPage page) async {
    doc.pages.remove(page);
    for (final path in [page.pagePath(doc.dir), page.originalPath(doc.dir)]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    if (doc.pages.isEmpty) {
      await deleteDoc(doc);
    } else {
      await saveDoc(doc);
    }
  }

  /// Adds a photo as a new page: keeps the original, makes the processed page.
  Future<ScanPage> addPage(ScanDoc doc, Uint8List photo,
      {List<double>? corners, PageFilter? filter, int rotation = 0}) async {
    final page = ScanPage(
      id: newId(),
      corners: corners ?? const [0, 0, 1, 0, 1, 1, 0, 1],
      filter: filter ?? settings.defaultFilter,
      rotation: rotation,
    );
    await File(page.originalPath(doc.dir)).writeAsBytes(photo);
    await renderPage(doc, page, save: false);
    doc.pages.add(page);
    return page;
  }

  /// Re-makes a page from its original photo with its corners, turn and filter.
  Future<void> renderPage(ScanDoc doc, ScanPage page, {bool save = true}) async {
    final photo = await File(page.originalPath(doc.dir)).readAsBytes();
    final job = PageJob(photo, page.corners, page.rotation, page.filter, settings.jpegQuality);
    final out = await compute(runPageJob, job);
    if (out != null) await File(page.pagePath(doc.dir)).writeAsBytes(out);
    // Pages keep their file name, so drop cached pictures to show the new one.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (save) await saveDoc(doc);
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _stamp(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}.${_two(t.minute)}';

String friendlyDate(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';

/// A plain sample page (title bar and text lines) for the demo store.
Uint8List _samplePage(int seed, PageFilter filter) {
  final rnd = math.Random(seed);
  final page = img.Image(width: 620, height: 877, numChannels: 3);
  final paper = filter == PageFilter.bw ? 255 : 250;
  img.fill(page, color: img.ColorRgb8(paper, paper, filter == PageFilter.enhance ? 246 : paper));
  final ink = img.ColorRgb8(40, 44, 52);
  img.fillRect(page, x1: 60, y1: 70, x2: 60 + 200 + rnd.nextInt(180), y2: 96, color: ink);
  var y = 140;
  while (y < 800) {
    final indent = rnd.nextInt(6) == 0 ? 40 : 0;
    final len = 260 + rnd.nextInt(240);
    img.fillRect(page,
        x1: 60 + indent, y1: y, x2: 60 + indent + len, y2: y + 9, color: img.ColorRgb8(90, 96, 104));
    y += rnd.nextInt(7) == 0 ? 44 : 24;
  }
  if (filter != PageFilter.bw && filter != PageFilter.gray) {
    img.fillRect(page, x1: 420, y1: 740, x2: 560, y2: 800, color: img.ColorRgb8(60, 110, 200));
  }
  return Uint8List.fromList(img.encodeJpg(page, quality: 85));
}
