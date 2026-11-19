// Escáner Local: scan documents with the phone, everything stays on the device.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'l10n.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_home.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final shotIndex = args.indexOf('--screenshot');
  final shotPath =
      shotIndex >= 0 && shotIndex + 1 < args.length ? args[shotIndex + 1] : null;
  // The screenshot check uses sample documents in a temporary folder.
  final store = shotPath != null ? await Store.demo() : await Store.open();
  runApp(ScannerApp(store: store, screenshotPath: shotPath));
}

class ScannerApp extends StatefulWidget {
  const ScannerApp({super.key, required this.store, this.screenshotPath});
  final Store store;
  final String? screenshotPath;

  @override
  State<ScannerApp> createState() => _ScannerAppState();
}

class _ScannerAppState extends State<ScannerApp> with WidgetsBindingObserver {
  final GlobalKey _shotKey = GlobalKey();
  int _frames = 0;
  bool _saving = false;

  /// Follows the system: language (Spanish when we don't have it) and dark mode.
  void _syncSystem() {
    final dispatcher = ui.PlatformDispatcher.instance;
    setLang(resolveLang(dispatcher.locales));
    AppColors.dark = dispatcher.platformBrightness == Brightness.dark;
  }

  /// Rebuilds every widget: colours and texts are read at build time.
  void _refreshAll() {
    if (!mounted) return;
    setState(_syncSystem);
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  void didChangePlatformBrightness() => _refreshAll();

  @override
  void didChangeLocales(List<Locale>? locales) => _refreshAll();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _syncSystem();
    WidgetsBinding.instance.addObserver(this);
    if (widget.screenshotPath != null) {
      SchedulerBinding.instance.addPostFrameCallback(_onFrame);
      // Safety net: save whatever is there after 20 s.
      Timer(const Duration(seconds: 20), _save);
    }
  }

  void _onFrame(Duration _) {
    _frames++;
    if (_frames >= 120) {
      _save();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final boundary =
          _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final view = ui.PlatformDispatcher.instance.views.first;
      final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(widget.screenshotPath!);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      try {
        await widget.store.root.delete(recursive: true);
      } catch (_) {}
    } finally {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _shotKey,
      child: CupertinoApp(
        title: 'Escáner Local',
        debugShowCheckedModeBanner: false,
        supportedLocales: [for (final l in supportedLangs) Locale(l)],
        localizationsDelegates: const [
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        localeResolutionCallback: (locale, supported) =>
            Locale(resolveLang([if (locale != null) locale])),
        theme: buildTheme(),
        home: HomeScreen(store: widget.store),
      ),
    );
  }
}
